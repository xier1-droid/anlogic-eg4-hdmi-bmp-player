#!/usr/bin/env python3
"""Scene pack builder (image part) for the v0.17.0 mountain escape classroom.

Reads scene.yaml, builds the per-pixel arrival time T of each stage, writes
PIC1-4.BMP (32bpp, 40-byte header, compression=0, BGRA bottom-up, alpha=T),
reads every BMP back as a self-check, and renders the hazard_layer reference
images (02_技术实现.md §2.3, §2.4, §4.2, §5).

Usage: py -I tools/make_scene_pack.py tools/scenes/demo_village/scene.yaml
The reference model functions (hazard_layer_model, blink_phase) are importable
for the M3 testbench generator.
"""
from pathlib import Path
import argparse, heapq, math, struct
import numpy as np
import yaml
from PIL import Image

T_MAX = 239          # 0..239: arrival time
T_SPOT = 250         # refuge point, blinks
T_NONE = 255         # never covered
EXPECTED_TIMES = (0, 120, 239)

# ---------------------------------------------------------------------------
# hazard_layer reference model (§4.2). Stage index 0..3 is 阶段 1..4.
# Bit-exact contract for the RTL:
#   covered = T < 240 && T <= t_now
#   front   = covered && (t_now - T) < 6
#   spot    = T == 250
#   mix 3/4 = (a>>2) + (c>>1) + (c>>2)   per channel
#   mix 1/2 = (a>>1) + (c>>1)            per channel
#   blink_fast = frame_cnt[FAST_BLINK_BIT[alert_level]], blink_slow = frame_cnt[5]
# Stage 0 does not colour covered/front pixels; refuge points blink in every stage.
# ---------------------------------------------------------------------------
HAZ_COLOR = (None, (0x60, 0x38, 0x18), (0x20, 0x60, 0xFF), (0x20, 0xC0, 0x40))
FRONT_COLOR = (None, (0xFF, 0xE0, 0x00), (0xFF, 0xFF, 0xFF), (0x40, 0xFF, 0x40))
HAZ_ALPHA_34 = (False, True, False, True)   # True: 3/4, False: 1/2
SPOT_COLOR = (0x00, 0xFF, 0x00)
FRONT_WIDTH = 6
FAST_BLINK_BIT = (4, 4, 3, 2)   # 60 fps: ~1.9, 1.9, 3.75, 7.5 Hz
SLOW_BLINK_BIT = 5              # ~0.94 Hz


def blink_phase(frame_cnt, alert_level):
    """Return (blink_fast, blink_slow) for a frame counter value."""
    return (frame_cnt >> FAST_BLINK_BIT[alert_level]) & 1, (frame_cnt >> SLOW_BLINK_BIT) & 1


def mix(a, c, alpha_34):
    a = a.astype(np.uint16)
    c = np.asarray(c, np.uint16)
    if alpha_34:
        return ((a >> 2) + (c >> 1) + (c >> 2)).astype(np.uint8)
    return ((a >> 1) + (c >> 1)).astype(np.uint8)


def hazard_layer_model(rgb, T, t_now, stage, blink_fast, blink_slow, enable=True, thumbnail=False):
    """rgb: HxWx3 uint8, T: HxW uint8. Returns the HxWx3 uint8 layer output."""
    out = rgb.copy()
    if not enable or thumbnail:
        return out
    T = T.astype(np.int16)
    covered = (T < 240) & (T <= t_now)
    front = covered & ((t_now - T) < FRONT_WIDTH)
    spot = T == T_SPOT
    if blink_slow:
        out[spot] = SPOT_COLOR
    haz = HAZ_COLOR[stage]
    if haz is not None:
        body = covered & ~front
        out[body] = mix(rgb[body], haz, HAZ_ALPHA_34[stage])
        out[front] = FRONT_COLOR[stage] if blink_fast else mix(rgb[front], haz, True)
    return out


# ---------------------------------------------------------------------------
# T sources. Each returns an HxW uint8 array: 0..239 arrival, 255 elsewhere.
# ---------------------------------------------------------------------------
def load_gray(path, shape):
    im = Image.open(path).convert('L')
    if im.size != (shape[1], shape[0]):
        raise SystemExit(f'{path}: size {im.size}, scene is {shape[1]}x{shape[0]}')
    return np.asarray(im, np.uint8)


def time_range(src):
    t0, t1 = src.get('t0', 0), src.get('t1', T_MAX)
    if not 0 <= t0 <= t1 <= T_MAX:
        raise SystemExit(f't0/t1 must satisfy 0 <= t0 <= t1 <= {T_MAX}: {t0}, {t1}')
    return t0, t1


def paint_t(shape, src, base_dir):
    """Hand-painted grayscale: darker arrives earlier, pure white is never covered."""
    v = load_gray(base_dir / src['file'], shape).astype(np.uint16)
    return np.where(v == 255, T_NONE, v * T_MAX // 254).astype(np.uint8)


def polyline_t(shape, src):
    """T grows with arc length along each line; pixels within width/2 are covered."""
    h, w = shape
    r = src.get('width', 4) / 2
    best = np.full(shape, np.inf)
    yy, xx = np.mgrid[0:h, 0:w]
    for line in src['lines']:
        if not isinstance(line, dict):
            line = {'points': line}
        t0, t1 = time_range({**src, **line})
        pts = np.asarray(line['points'], float)
        seg = np.diff(pts, axis=0)
        lens = np.hypot(seg[:, 0], seg[:, 1])
        total = lens.sum()
        cum = np.concatenate(([0.0], np.cumsum(lens)))
        for (x0, y0), (dx, dy), L, c in zip(pts[:-1], seg, lens, cum):
            if L == 0:
                continue
            xa, xb = int(max(0, math.floor(min(x0, x0 + dx) - r))), int(min(w, math.ceil(max(x0, x0 + dx) + r) + 1))
            ya, yb = int(max(0, math.floor(min(y0, y0 + dy) - r))), int(min(h, math.ceil(max(y0, y0 + dy) + r) + 1))
            px, py = xx[ya:yb, xa:xb] - x0, yy[ya:yb, xa:xb] - y0
            u = np.clip((px * dx + py * dy) / (L * L), 0, 1)
            dist = np.hypot(px - u * dx, py - u * dy)
            t = t0 + (t1 - t0) * (c + u * L) / total
            t = np.where(dist <= r, t, np.inf)
            view = best[ya:yb, xa:xb]
            np.minimum(view, t, out=view)
    out = np.full(shape, T_NONE, np.uint8)
    hit = np.isfinite(best)
    out[hit] = np.floor(best[hit]).astype(np.uint8)
    return out


def geodesic_distance(passable, dem, climb, seeds):
    """8-neighbour Dijkstra; each step costs 1 or sqrt(2) plus climb * uphill rise."""
    h, w = passable.shape
    ok = passable.ravel().tolist()
    z = dem.ravel().tolist() if dem is not None else None
    dist = [math.inf] * (h * w)
    heap = []
    for x, y in seeds:
        i = int(y) * w + int(x)
        if not ok[i]:
            raise SystemExit(f'seed ({x},{y}) is outside the passable area')
        dist[i] = 0.0
        heap.append((0.0, i))
    heapq.heapify(heap)
    steps = [(dx, dy, math.hypot(dx, dy)) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy]
    while heap:
        d, i = heapq.heappop(heap)
        if d > dist[i]:
            continue
        y, x = divmod(i, w)
        for dx, dy, base in steps:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not ok[j]:
                    continue
                nd = d + base
                if z is not None and z[j] > z[i]:
                    nd += climb * (z[j] - z[i])
                if nd < dist[j]:
                    dist[j] = nd
                    heapq.heappush(heap, (nd, j))
    return np.asarray(dist).reshape(h, w)


def seeds_t(shape, src, base_dir):
    """Spread from seed points; optional mask (white passable), DEM level cap and climb cost."""
    t0, t1 = time_range(src)
    passable = np.ones(shape, bool)
    if 'mask' in src:
        passable &= load_gray(base_dir / src['mask'], shape) >= 128
    dem = None
    if 'dem' in src:
        dem = load_gray(base_dir / src['dem'], shape).astype(np.int32)
        if 'max_level' in src:
            passable &= dem <= src['max_level']
    dist = geodesic_distance(passable, dem, src.get('climb', 0.0), src['points'])
    reach = np.isfinite(dist)
    dmax = src.get('max_distance') or dist[reach].max()
    reach &= dist <= dmax
    out = np.full(shape, T_NONE, np.uint8)
    out[reach] = np.floor(t0 + (t1 - t0) * dist[reach] / dmax).astype(np.uint8)
    return out


def stage_t(shape, stage, base_dir):
    T = np.full(shape, T_NONE, np.uint8)
    for src in stage.get('sources') or []:
        kind = src['type']
        if kind == 'paint':
            t = paint_t(shape, src, base_dir)
        elif kind == 'polyline':
            t = polyline_t(shape, src)
        elif kind == 'seeds':
            t = seeds_t(shape, src, base_dir)
        else:
            raise SystemExit(f'unknown source type: {kind}')
        T = np.where(t < 240, np.minimum(T, t), T)
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    for x, y, r in stage.get('spots') or []:
        T[(xx - x) ** 2 + (yy - y) ** 2 <= r * r] = T_SPOT
    return T


# ---------------------------------------------------------------------------
# 32bpp BMP writer and read-back check (bmp_header_check.v acceptance).
# ---------------------------------------------------------------------------
HEADER_BYTES = 54


def write_bmp32(path, rgb, T):
    h, w = T.shape
    px = np.empty((h, w, 4), np.uint8)
    px[..., 0], px[..., 1], px[..., 2], px[..., 3] = rgb[..., 2], rgb[..., 1], rgb[..., 0], T
    data = px[::-1].tobytes()     # bottom-up rows, width*4 needs no padding
    head = struct.pack('<2sIHHI', b'BM', HEADER_BYTES + len(data), 0, 0, HEADER_BYTES)
    head += struct.pack('<IiiHHIIiiII', 40, w, h, 1, 32, 0, len(data), 3780, 3780, 0, 0)
    path.write_bytes(head + data)


def check_bmp32(path, rgb, T):
    d = path.read_bytes()
    magic, file_len, _, _, offset = struct.unpack_from('<2sIHHI', d, 0)
    dib, w, h, planes, bpp, comp = struct.unpack_from('<IiiHHI', d, 14)
    need = offset + w * 4 * h
    problems = [msg for ok, msg in (
        (magic == b'BM', 'magic'), (file_len == len(d), 'file length'),
        (dib >= 40, 'dib_size>=40'), (planes == 1, 'planes=1'),
        (bpp == 32, 'bitcount=32'), (comp == 0, 'compression=0'),
        ((w, h) == (T.shape[1], T.shape[0]), 'dimensions'),
        (w <= 1920 and h <= 1080, 'dimension range'),
        (offset >= 14 + dib and need <= file_len, 'pixel bounds')) if not ok]
    if problems:
        raise SystemExit(f'{path}: BMP check failed: {", ".join(problems)}')
    px = np.frombuffer(d, np.uint8, w * h * 4, offset).reshape(h, w, 4)[::-1]
    if not (np.array_equal(px[..., 2::-1], rgb) and np.array_equal(px[..., 3], T)):
        raise SystemExit(f'{path}: pixel read-back differs from source')


# ---------------------------------------------------------------------------
# Previews
# ---------------------------------------------------------------------------
def t_preview(T):
    """White: never covered, red: refuge point, dark->light blue: early->late."""
    out = np.full(T.shape + (3,), 255, np.uint8)
    cov = T < 240
    g = (T[cov].astype(np.uint16) * 200 // T_MAX).astype(np.uint8)
    out[cov] = np.stack([g // 2, g, 55 + g], axis=-1)
    out[T == T_SPOT] = (255, 0, 0)
    return out


def overview(rows, path):
    """rows: per stage list of HxWx3 images; written at half size in a grid."""
    h, w = rows[0][0].shape[:2]
    hw, hh = w // 2, h // 2
    sheet = Image.new('RGB', (hw * len(rows[0]) + 4 * (len(rows[0]) - 1), hh * len(rows) + 4 * (len(rows) - 1)), (40, 40, 40))
    for r, imgs in enumerate(rows):
        for c, img in enumerate(imgs):
            sheet.paste(Image.fromarray(img).resize((hw, hh), Image.NEAREST), (c * (hw + 4), r * (hh + 4)))
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('scene', help='scene.yaml')
    ap.add_argument('--out', help='output directory (default: scene "output", relative to the yaml)')
    a = ap.parse_args()
    scene_path = Path(a.scene)
    base_dir = scene_path.parent
    cfg = yaml.safe_load(scene_path.read_text(encoding='utf-8'))
    w, h = cfg['size']
    shape = (h, w)
    stages = cfg['stages']
    if len(stages) != 4:
        raise SystemExit('scene.yaml must define exactly 4 stages')
    out = Path(a.out) if a.out else base_dir / cfg.get('output', 'out')
    for sub in ('sd', 'expected', 'tmap'):
        (out / sub).mkdir(parents=True, exist_ok=True)

    rows = []
    for n, stage in enumerate(stages):
        img = Image.open(base_dir / stage.get('image', cfg['base'])).convert('RGB')
        if img.size != (w, h):
            raise SystemExit(f'stage {n + 1} image size {img.size}, scene is {w}x{h}')
        rgb = np.asarray(img, np.uint8)
        T = stage_t(shape, stage, base_dir)
        bmp = out / 'sd' / f'PIC{n + 1}.BMP'
        write_bmp32(bmp, rgb, T)
        check_bmp32(bmp, rgb, T)
        Image.fromarray(t_preview(T)).save(out / 'tmap' / f'PIC{n + 1}_T.png')
        row = []
        for t in EXPECTED_TIMES:
            for phase in (1, 0):
                exp = hazard_layer_model(rgb, T, t, n, phase, phase)
                Image.fromarray(exp).save(out / 'expected' / f'PIC{n + 1}_t{t:03d}_{"on" if phase else "off"}.png')
                if phase or t == T_MAX:
                    row.append(exp)
        row.append(t_preview(T))
        rows.append(row)
        cov = T < 240
        tr = f'T {T[cov].min()}..{T[cov].max()}' if cov.any() else 'no hazard pixels'
        print(f'{bmp}: {bmp.stat().st_size} bytes, stage {n + 1}: '
              f'{int(cov.sum())} hazard px ({tr}), {int((T == T_SPOT).sum())} refuge px')
    overview(rows, out / 'overview.png')
    print(f'{out / "overview.png"}: columns t=0 on, t=120 on, t=239 on, t=239 off, T map')


if __name__ == '__main__':
    main()
