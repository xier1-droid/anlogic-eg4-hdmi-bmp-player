#!/usr/bin/env python3
"""Scene text for scene packs (M5): FONT.BIN and TEXT.BIN, plus OSD previews.

FONT.BIN: up to 128 glyphs of 16x16, 32 bytes each; row r is bytes 2r (left
8 pixels) and 2r+1 (right 8), MSB leftmost. Glyphs 0-12 are always the
original case-font glyphs of the board (米醋电子工作室忧郁胆肥嘟的, codes
0x80-0x8C of osd_font_cn_16x16.v), so the old subtitle keeps its look; the
others are rendered from SimSun 16px (bit-exact with the case font's SimSun
glyphs) in order of first use.

TEXT.BIN v1 (02_技术实现.md §3.2, segment numbers fixed by M5):
  0 "TX", 1 version 1, 3 N=14; 4 + 4n {offset lo, offset hi, length, type}
  segment 0 village (type 3), 1-4 stage titles (0), 5-8 stage subtitles (1),
  9 warning (2), 10-13 stage legends (4); characters follow from byte 60.
Character codes: 00-7F glyph, E0-E7 legend swatch, F0-F9 digits, FA ':',
FB '.', FC '-', FD '!', FE '?', FF space. Full-width ０-９ ：！？ and the
ASCII forms use the codes; every other character becomes a glyph.

scene.yaml keys (all optional):
  village: name                 segment 0, the warning-mode title
  warning: text                 segment 9, the warning-mode subtitle
  stages[n].title: text         title (16 cells at most)
  stages[n].subtitle: text      default: the stage's narration lines
  stages[n].legend: [[swatch, text], ...]   swatch: danger route refuge mud
                                zone fault rock rain
"""
from pathlib import Path
import re
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL_CHARS = '米醋电子工作室忧郁胆肥嘟的'
SWATCHES = ('danger', 'route', 'refuge', 'mud', 'zone', 'fault', 'rock', 'rain')
SWATCH_RGB = ((0xD8, 0x20, 0x20), (0x20, 0xC8, 0x48), (0x00, 0xFF, 0x00), (0x8C, 0x6A, 0x3C),
              (0xFF, 0xD0, 0x00), (0xE8, 0x30, 0x20), (0x8E, 0x8A, 0x84), (0xC8, 0xD2, 0xDC))
ESCAPES = {':': 0xFA, '.': 0xFB, '-': 0xFC, '!': 0xFD, '?': 0xFE, ' ': 0xFF,
           '：': 0xFA, '！': 0xFD, '？': 0xFE, '　': 0xFF}
ESCAPES.update({str(d): 0xF0 + d for d in range(10)})
ESCAPES.update({chr(0xFF10 + d): 0xF0 + d for d in range(10)})
SEG_COUNT = 14
SEG_TYPES = (3, 0, 0, 0, 0, 1, 1, 1, 1, 2, 4, 4, 4, 4)
MAX_GLYPHS, MAX_TEXT = 128, 4096
TITLE_CELLS, LEGEND_CELLS = 16, 38


def original_glyphs():
    """The 13 case-font glyphs as 16 row words each, read from the RTL."""
    src = (ROOT / 'user_source/hdl_source/osd/osd_font_cn_16x16.v').read_text(encoding='utf-8')
    rows = {}
    for code, base, val in re.findall(r"8'h(8[0-9a-c]): bits = 256'([bh])([0-9a-f]+);", src):
        v = int(val, 2 if base == 'b' else 16)
        rows[int(code, 16) - 0x80] = [(v >> (240 - 16 * r)) & 0xFFFF for r in range(16)]
    if sorted(rows) != list(range(13)):
        raise SystemExit('osd_font_cn_16x16.v: expected glyphs 0x80-0x8C')
    return [rows[i] for i in range(13)]


def font_5x7():
    """{character: 7 row values of 5 bits} from osd_font_5x7.v."""
    src = (ROOT / 'user_source/hdl_source/osd/osd_font_5x7.v').read_text(encoding='utf-8')
    table = {}
    for ch, body in re.findall(r'"(.)": case\(row\)(.*?)endcase', src):
        rows = [0] * 7
        for r, bits in re.findall(r"(\d):glyph_row=5'b([01]{5})", body):
            rows[int(r)] = int(bits, 2)
        table[ch] = rows
    return table


_simsun = None


def render(ch):
    global _simsun
    if _simsun is None:
        for name in ('simsun.ttc', 'C:/Windows/Fonts/simsun.ttc'):
            try:
                _simsun = ImageFont.truetype(name, 16)
                break
            except OSError:
                pass
        else:
            raise SystemExit('SimSun (simsun.ttc) not found')
    im = Image.new('L', (16, 16), 0)
    ImageDraw.Draw(im).text((0, 0), ch, fill=255, font=_simsun)
    a = np.asarray(im) >= 128
    return [int(''.join('1' if b else '0' for b in a[r]), 2) for r in range(16)]


class Builder:
    def __init__(self):
        self.glyphs = original_glyphs()
        self.index = {c: i for i, c in enumerate(ORIGINAL_CHARS)}

    def encode(self, text, where):
        out = []
        for ch in text:
            if ch in ESCAPES:
                out.append(ESCAPES[ch])
                continue
            if ch not in self.index:
                if len(self.glyphs) == MAX_GLYPHS:
                    raise SystemExit(f'{where}: more than {MAX_GLYPHS} glyphs (at {ch!r})')
                self.index[ch] = len(self.glyphs)
                self.glyphs.append(render(ch))
            out.append(self.index[ch])
        return out

    def font_bin(self):
        return b''.join(bytes(b for w in g for b in (w >> 8, w & 0xFF)) for g in self.glyphs)


def stage_subtitle(stage):
    if 'subtitle' in stage:
        return stage['subtitle'] or ''
    return '  '.join(str(line['text']) for line in sorted(stage.get('narration') or [], key=lambda d: d['t']))


def legend_codes(b, legend, where):
    out = []
    for k, item in enumerate(legend or []):
        swatch, text = item
        if swatch not in SWATCHES:
            raise SystemExit(f'{where}: unknown swatch {swatch!r}, use one of {", ".join(SWATCHES)}')
        if k:
            out += [0xFF, 0xFF]
        out += [0xE0 + SWATCHES.index(swatch), 0xFF] + b.encode(str(text), where)
    return out


def build(cfg):
    """(font bytes, text bytes, segments as code lists)."""
    b = Builder()
    stages = cfg['stages']
    segs = [[] for _ in range(SEG_COUNT)]
    segs[0] = b.encode(str(cfg.get('village', '')), 'village')
    for n, st in enumerate(stages):
        segs[1 + n] = b.encode(str(st.get('title', '')), f'stage {n + 1} title')
        segs[5 + n] = b.encode(stage_subtitle(st), f'stage {n + 1} subtitle')
        segs[10 + n] = legend_codes(b, st.get('legend'), f'stage {n + 1} legend')
    segs[9] = b.encode(str(cfg.get('warning', '')), 'warning')
    limits = {0: TITLE_CELLS, 1: TITLE_CELLS, 2: TITLE_CELLS, 3: TITLE_CELLS, 4: TITLE_CELLS}
    limits.update({n: LEGEND_CELLS for n in range(10, 14)})
    for n, s in enumerate(segs):
        if len(s) > limits.get(n, 255):
            raise SystemExit(f'segment {n}: {len(s)} cells, at most {limits.get(n, 255)}')
    head = bytearray(b'TX\x01' + bytes([SEG_COUNT]))
    body = bytearray()
    start = 4 + 4 * SEG_COUNT
    for n, s in enumerate(segs):
        off = start + len(body)
        head += bytes([off & 0xFF, off >> 8, len(s), SEG_TYPES[n]])
        body += bytes(s)
    text = bytes(head + body)
    if len(text) > MAX_TEXT:
        raise SystemExit(f'TEXT.BIN {len(text)} bytes, at most {MAX_TEXT}')
    return b.font_bin(), text, segs


# ---------------------------------------------------------------------------
# Preview of the scene OSD (layout of scene_osd.v); the subtitle is drawn with
# its first character at x=8.
# ---------------------------------------------------------------------------
ALERT_RGB = ((0x20, 0x80, 0xFF), (0xFF, 0xD0, 0x00), (0xFF, 0x80, 0x00), (0xFF, 0x20, 0x20))


def _dim(img, x0, x1, y0, y1):
    img[y0:y1, x0:x1] >>= 1


def _cell(img, code, x, y, font, f57, blink=True):
    if code < 0x80:
        g = font[code * 32:(code + 1) * 32]
        for r in range(16):
            w = g[2 * r] << 8 | g[2 * r + 1]
            for c in range(16):
                if w >> (15 - c) & 1 and 0 <= x + c < 640:
                    img[y + r, x + c] = 255
    elif 0xE0 <= code <= 0xE7:
        if code != 0xE2 or blink:
            img[y + 2:y + 14, max(x + 2, 0):min(x + 14, 640)] = SWATCH_RGB[code - 0xE0]
    elif code >= 0xF0:
        ch = ':.-!? '[code - 0xFA] if code >= 0xFA else str(code - 0xF0)
        rows = f57.get(ch, [0] * 7)
        for r in range(14):
            for c in range(10):
                if rows[r >> 1] >> (4 - (c >> 1)) & 1 and 0 <= x + c < 640:
                    img[y + r, x + c] = 255


def _line(img, codes, x0, y, font, f57):
    for i, code in enumerate(codes):
        if x0 + 16 * i >= 632:
            break
        _cell(img, code, x0 + 16 * i, y, font, f57)


def preview(rgb, segs, font, stage, warn=False, t_now=239):
    img = np.array(rgb, np.uint8)
    f57 = font_5x7()
    title, sub, legend = (segs[0], segs[9], segs[13]) if warn else (segs[1 + stage], segs[5 + stage], segs[10 + stage])
    alert = ALERT_RGB[3 if warn else stage]
    _dim(img, 348, 636, 28, 60)
    img[32:48, 352:368] = alert
    img[52:56, 376:616] = (0x40, 0x40, 0x40)
    img[52:56, 376:376 + min(t_now, 239) + 1] = alert
    _line(img, title, 376, 32, font, f57)
    if legend:
        _dim(img, 4, min(12 + 16 * len(legend), 640), 412, 436)
        _line(img, legend, 8, 416, font, f57)
    if sub:
        _dim(img, 8, 632, 440, 464)
        _line(img, sub, 8, 444, font, f57)
    if warn:
        img[:8] = img[-8:] = (0xFF, 0x20, 0x20)
        img[:, :8] = img[:, -8:] = (0xFF, 0x20, 0x20)
    return img


def write_scene_text(cfg, base_dir, out):
    """Write out/sd/FONT.BIN, TEXT.BIN and out/osd/ previews."""
    font, text, segs = build(cfg)
    sd = out / 'sd'
    sd.mkdir(parents=True, exist_ok=True)
    (sd / 'FONT.BIN').write_bytes(font)
    (sd / 'TEXT.BIN').write_bytes(text)
    osd = out / 'osd'
    osd.mkdir(parents=True, exist_ok=True)
    for n, st in enumerate(cfg['stages']):
        rgb = np.asarray(Image.open(base_dir / st.get('image', cfg['base'])).convert('RGB'))
        Image.fromarray(preview(rgb, segs, font, n)).save(osd / f'STAGE{n + 1}.png')
        if n == len(cfg['stages']) - 1:
            Image.fromarray(preview(rgb, segs, font, n, warn=True)).save(osd / 'WARN.png')
    print(f'{sd / "FONT.BIN"}: {len(font)} bytes, {len(font) // 32} glyphs')
    print(f'{sd / "TEXT.BIN"}: {len(text)} bytes, segments ' +
          ' '.join(str(len(s)) for s in segs))
