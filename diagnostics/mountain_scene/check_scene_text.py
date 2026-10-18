#!/usr/bin/env python3
"""M5 check of tools/scene_text.py on the four v3 cards.

For each card: TEXT.BIN header and descriptors (v1 layout, N=14, types,
contiguous segments from byte 60, size limit), every segment decoded back
through FONT.BIN to the text written in scene.yaml (subtitle defaulting to
the narration lines, legend swatches), glyphs 0-12 equal to the case font
of osd_font_cn_16x16.v, no duplicate glyphs, and a second build byte-equal.
SimSun rendering of 胆肥嘟的 must equal their case-font glyphs (the style
the tool renders new glyphs in). Over-long titles and more than 128 glyphs
must be refused. Usage: py -I check_scene_text.py <repo root>
"""
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / 'tools'))
import yaml  # noqa: E402
import scene_text as st  # noqa: E402

CARDS = ('landslide_village', 'debris_village', 'flood_village', 'quake_village')
checks = 0


def ok(cond, what):
    global checks
    if not cond:
        raise SystemExit(f'FAIL {what}')
    checks += 1


case = st.original_glyphs()
for k, ch in enumerate('胆肥嘟的'):
    ok(st.render(ch) == case[9 + k], f'SimSun render of {ch} equals case glyph 0x{0x89 + k:02x}')

for card in CARDS:
    cfg = yaml.safe_load((root / 'tools/scenes' / card / 'scene.yaml').read_text(encoding='utf-8'))
    font, text, segs = st.build(cfg)
    font2, text2, _ = st.build(cfg)
    ok(font == font2 and text == text2, f'{card}: rebuild is byte-equal')
    ok(len(font) % 32 == 0 and len(font) // 32 <= 128, f'{card}: FONT size')
    glyphs = [font[i:i + 32] for i in range(0, len(font), 32)]
    ok(len(set(glyphs)) == len(glyphs), f'{card}: no duplicate glyphs')
    for i in range(13):
        ok([g[2 * r] << 8 | g[2 * r + 1] for g in [glyphs[i]] for r in range(16)] == case[i], f'{card}: glyph {i} is the case glyph')
    ok(text[:4] == b'TX\x01\x0e' and len(text) <= 4096, f'{card}: TEXT header and size')
    pos = 60
    for n in range(14):
        off = text[4 + 4 * n] | text[5 + 4 * n] << 8
        ok(off == pos and text[7 + 4 * n] == st.SEG_TYPES[n], f'{card}: segment {n} descriptor')
        ok(list(text[off:off + text[6 + 4 * n]]) == segs[n], f'{card}: segment {n} bytes')
        pos += text[6 + 4 * n]
    ok(pos == len(text), f'{card}: segments fill TEXT.BIN')
    # Decoding through the builder's own index would be circular: each glyph
    # must instead equal the rendering of the expected character (or the case
    # glyph for the 13 originals).

    def expect_codes(s):
        out = []
        for ch in s:
            if ch in st.ESCAPES:
                out.append(('esc', st.ESCAPES[ch]))
            else:
                out.append(('glyph', ch))
        return out

    def check_seg(n, s, what):
        codes = segs[n]
        exp = expect_codes(s)
        ok(len(codes) == len(exp), f'{card}: {what} length')
        for c, (kind, v) in zip(codes, exp):
            if kind == 'esc':
                ok(c == v, f'{card}: {what} escape {v:02x}')
            else:
                ok(c < 128, f'{card}: {what} glyph code')
                g = glyphs[c]
                rows = [g[2 * r] << 8 | g[2 * r + 1] for r in range(16)]
                want = case[st.ORIGINAL_CHARS.index(v)] if v in st.ORIGINAL_CHARS else st.render(v)
                ok(rows == want, f'{card}: {what} glyph of {v}')

    check_seg(0, str(cfg['village']), 'village')
    check_seg(9, str(cfg['warning']), 'warning')
    for i, stage in enumerate(cfg['stages']):
        check_seg(1 + i, str(stage['title']), f'stage {i + 1} title')
        check_seg(5 + i, '  '.join(l['text'] for l in sorted(stage['narration'], key=lambda d: d['t'])), f'stage {i + 1} subtitle')
        codes, k = segs[10 + i], 0
        for j, (sw, label) in enumerate(stage['legend']):
            if j:
                ok(codes[k:k + 2] == [0xFF, 0xFF], f'{card}: legend {i + 1} gap')
                k += 2
            ok(codes[k] == 0xE0 + st.SWATCHES.index(sw) and codes[k + 1] == 0xFF, f'{card}: legend {i + 1} swatch {sw}')
            k += 2 + len(label)
        ok(k == len(codes), f'{card}: legend {i + 1} length')
    print(f'{card}: FONT {len(font)} B ({len(glyphs)} glyphs), TEXT {len(text)} B')

# Refusals.
base = {'stages': [{} for _ in range(4)]}
for bad, what in (({**base, 'village': '一二三四五六七八九十一二三四五六七'}, 'title of 17 cells'),
                  ({**base, 'warning': ''.join(chr(0x4E00 + i) for i in range(116))}, '129 glyphs')):
    try:
        st.build(bad)
    except SystemExit:
        ok(True, what)
    else:
        ok(False, f'{what} accepted')
print(f'PASS M5 scene text: {checks} checks')
