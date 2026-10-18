#!/usr/bin/env python3
"""Scene pack builder (image part) for the v0.17.0 mountain escape classroom.

Reads scene.yaml, builds the per-pixel arrival time T of each stage, writes
PIC1-4.BMP (32bpp, 40-byte header, compression=0, BGRA bottom-up, alpha=T),
reads every BMP back as a self-check, and renders the hazard_layer reference
images (02_技术实现.md §2.3, §2.4, §4.2, §5).

Usage: py -I tools/make_scene_pack.py tools/scenes/demo_village/scene.yaml
The reference model functions (hazard_layer_model, blink_phase) are importable
for the M3 testbench generator.

format: 3 scenes (cause -> hazard -> evacuation cards, tools/hazard_v3.py) give
each stage `hazard` and `role` (written to BMP header bytes 6-7) and each
source a `region`; T becomes region<<6 | time/4, 255 for no layer. Extra
source types: polygon (filled), outline (polygon border), mask, all at t0.
--gif writes one animated preview per stage (every 2nd frame, 8 s loop).
--audio (M4) also writes SND1-4.PCM from each stage's sound/narration
(tools/scene_audio.py); --no-tts replaces speech by timing beeps.
--text (M5) also writes FONT.BIN and TEXT.BIN from village/warning and each
stage's title/subtitle/legend, with OSD previews in osd/ (tools/scene_text.py).
"""
from pathlib import Path
import argparse, heapq, math, struct, sys
import numpy as np
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I drops the script directory
import hazard_v3 as v3  # noqa: E402
from PIL import Image, ImageDraw

T_MAX = 239          # 0..239: arrival time
T_SPOT = 250         # refuge point, blinks
T_NONE = 255         # never covered
EXPECTED_TIMES = (0, 120, 239)

# ---------------------------------------------------------------------------
# hazard_layer reference model (§4.2, v2 effects). Stage index 0..3 is 阶段 1..4.
# Bit-exact contract for the RTL (tools/scenes/README.md):
#   covered = T < 240 && T <= t_now;  age = t_now - T (8 bit)
#   front   = covered && age < 6;     spot = T == 250
#   f = frame_cnt (6 bit), fast = f[FAST_BLINK_BIT[alert]], slow = f[5]
#   blend k (quarters of colour c), per channel:
#     k=1: (a>>1)+(a>>2)+(c>>2)  k=2: (a>>1)+(c>>1)  k=3: (a>>2)+(c>>1)+(c>>2)
#   stage 0 rain (x,y = active pixel position):
#     col = (x + (y>>2)) mod 1024, h = (((col*157) mod 2048) >> 3) ^ (col mod 256)
#     lit = h < 4 + (t_now>>5) && ((y - 8f + 4col) mod 32) < 12 -> blend 2 RAIN
#   stage 1 crack: body blend 3 CRACK; front fast ? CRACK_TIP : blend 3 CRACK
#   stage 2 flood: front blend (fast ? 2 : 1) FOAM; body blend k with k=1 for
#     age<24, 2 for age<64, else 3, colour RIPPLE when ((T - (f>>1)) mod 16) < 2
#     else MUD
#   stage 3 route: front fast ? ROUTE_TIP : ROUTE_TIP_OFF; body DASH when
#     ((T - (f>>1)) mod 8) < 3 else blend 3 ROUTE
#   priority: covered (stages 1-3) > spot && slow (SPOT) > rain > rgb
# ---------------------------------------------------------------------------
CRACK, CRACK_TIP = (0x18, 0x0E, 0x06), (0xFF, 0xD0, 0x00)
MUD, RIPPLE, FOAM = (0x8C, 0x6A, 0x3C), (0xC4, 0xA8, 0x74), (0xF0, 0xE8, 0xD6)
ROUTE, DASH = (0x20, 0xC8, 0x48), (0xAA, 0xFF, 0xBE)
ROUTE_TIP, ROUTE_TIP_OFF = (0xFF, 0xFF, 0xFF), (0x40, 0xFF, 0x40)
RAIN = (0xC8, 0xD2, 0xDC)
SPOT_COLOR = (0x00, 0xFF, 0x00)
FRONT_WIDTH = 6
FAST_BLINK_BIT = (4, 4, 3, 2)   # 60 fps: ~1.9, 1.9, 3.75, 7.5 Hz
SLOW_BLINK_BIT = 5              # ~0.94 Hz


def blink_phase(frame_cnt, alert_level):
    """Return (blink_fast, blink_slow) for a frame counter value."""
    return (frame_cnt >> FAST_BLINK_BIT[alert_level]) & 1, (frame_cnt >> SLOW_BLINK_BIT) & 1


def blend(a, c, k):
    """a: Nx3 uint8, c: colour, k: quarters of c (scalar or N-vector, 1..3)."""
    a = a.astype(np.int32)
    c = np.asarray(c, np.int32)
    k = np.broadcast_to(np.asarray(k)[..., None] if np.ndim(k) else k, a.shape)
    out = np.where(k == 1, (a >> 1) + (a >> 2) + (c >> 2),
                   np.where(k == 2, (a >> 1) + (c >> 1), (a >> 2) + (c >> 1) + (c >> 2)))
    return out.astype(np.uint8)


def rain_mask(x, y, t_now, frame_cnt):
    col = (x + (y >> 2)) & 1023
    h = (((col * 157) & 2047) >> 3) ^ (col & 255)
    return (h < 4 + (t_now >> 5)) & (((y - 8 * frame_cnt + 4 * col) & 31) < 12)


def hazard_layer_model(rgb, T, t_now, stage, frame_cnt, alert_level=None, enable=True, thumbnail=False,
                       x=None, y=None):
    """rgb: HxWx3 uint8, T: HxW uint8; x/y default to the pixel grid.
    Returns the HxWx3 uint8 layer output."""
    out = rgb.copy()
    if not enable or thumbnail:
        return out
    if alert_level is None:
        alert_level = stage
    if x is None:
        y, x = np.mgrid[0:T.shape[0], 0:T.shape[1]]
    fast, slow = blink_phase(frame_cnt, alert_level)
    T = T.astype(np.int32)
    covered = (T < 240) & (T <= t_now)
    age = (t_now - T) & 255
    front = covered & (age < FRONT_WIDTH)
    body = covered & ~front
    if stage == 0:
        m = rain_mask(x, y, t_now, frame_cnt)
        out[m] = blend(rgb[m], RAIN, 2)
    if slow:
        out[T == T_SPOT] = SPOT_COLOR
    if stage == 1:
        out[body] = blend(rgb[body], CRACK, 3)
        out[front] = CRACK_TIP if fast else blend(rgb[front], CRACK, 3)
    elif stage == 2:
        out[front] = blend(rgb[front], FOAM, 2 if fast else 1)
        k = np.where(age < 24, 1, np.where(age < 64, 2, 3))
        ripple = ((T - (frame_cnt >> 1)) & 15) < 2
        for colour, m in ((RIPPLE, body & ripple), (MUD, body & ~ripple)):
            out[m] = blend(rgb[m], colour, k[m])
    elif stage == 3:
        out[front] = ROUTE_TIP if fast else ROUTE_TIP_OFF
        dash = body & (((T - (frame_cnt >> 1)) & 7) < 3)
        out[dash] = DASH
        m = body & ~dash
        out[m] = blend(rgb[m], ROUTE, 3)
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
            if src.get('accel'):          # falling body: distance grows with time squared
                t = t0 + (t1 - t0) * np.sqrt((c + u * L) / total)
            else:
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


def polygon_t(shape, src, outline=False):
    m = Image.new('L', (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(m)
    pts = [tuple(p) for p in src['points']]
    if outline:
        d.line(pts + [pts[0]], fill=255, width=src.get('width', 3))
    else:
        d.polygon(pts, fill=255)
    hit = np.asarray(m) > 0
    if src.get('rough') and not outline:
        hit = rough(hit, src['rough'], src.get('seed', 1))
    if src.get('grade') in ('down', 'right'):
        return graded_t(shape, src, hit)
    return np.where(hit, src.get('t0', 0), T_NONE).astype(np.uint8)


def rough(mask, amp, seed):
    """Let a mask edge wander by about amp px with fixed-seed smooth noise."""
    from PIL import ImageFilter
    h, w = mask.shape
    soft = np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(amp)), np.float64)
    rng = np.random.default_rng(seed)
    noise = Image.fromarray((rng.random((h // 16 + 2, w // 16 + 2)) * 255).astype(np.uint8))
    noise = np.asarray(noise.resize((w, h), Image.BICUBIC), np.float64) - 128
    return soft + noise * 0.8 > 128


def smooth_noise(shape, cell, seed):
    """Fixed-seed value noise in [0,1), bicubic between cell-sized lattice points."""
    h, w = shape
    rng = np.random.default_rng(seed)
    lat = (rng.random((h // cell + 3, w // cell + 3)) * 255).astype(np.uint8)
    n = np.asarray(Image.fromarray(lat).resize(((w // cell + 3) * cell, (h // cell + 3) * cell), Image.BICUBIC),
                   np.float64)[cell:cell + h, cell:cell + w]
    return np.clip(n / 255.0, 0, 0.999)


def crack_t(shape, src):
    """Natural cracks: each line is densified, wanders sideways with smooth
    noise (jitter px), and its width varies between width_min and width_max;
    T grows along the line from t0 to t1."""
    h, w = shape
    best = np.full(shape, np.inf)
    rng = np.random.default_rng(src.get('seed', 1))
    yy, xx = np.mgrid[0:h, 0:w]
    for line in src['lines']:
        t0, t1 = time_range({**src, **line})
        pts = np.asarray(line['points'], float)
        seg = np.diff(pts, axis=0)
        lens = np.hypot(seg[:, 0], seg[:, 1])
        total = lens.sum()
        n = max(2, int(total / 1.5))
        s = np.linspace(0, total, n)
        cum = np.concatenate(([0.0], np.cumsum(lens)))
        k = np.clip(np.searchsorted(cum, s, side='right') - 1, 0, len(seg) - 1)
        u = (s - cum[k]) / np.maximum(lens[k], 1e-9)
        px = pts[k, 0] + u * seg[k, 0]
        py = pts[k, 1] + u * seg[k, 1]
        nx, ny = -seg[k, 1] / np.maximum(lens[k], 1e-9), seg[k, 0] / np.maximum(lens[k], 1e-9)
        ph = rng.random(6) * 2 * np.pi
        off = sum(np.sin(s / per + ph[i]) / (i + 1) for i, per in enumerate((23.0, 9.0, 4.0)))
        off = src.get('jitter', 3) * off / 1.8
        wv = sum(np.sin(s / per + ph[3 + i]) for i, per in enumerate((17.0, 6.0)))
        wmin, wmax = src.get('width_min', 1.0), src.get('width_max', 3.0)
        r = (wmin + (wmax - wmin) * (wv + 2) / 4) / 2
        cx, cy = px + nx * off, py + ny * off
        taper = np.minimum(1, np.minimum(s, total - s) / 6 + 0.35)   # thin ends
        for x0, y0, rr, sv in zip(cx, cy, r * taper, s):
            xa, xb = int(max(0, x0 - rr - 1)), int(min(w, x0 + rr + 2))
            ya, yb = int(max(0, y0 - rr - 1)), int(min(h, y0 + rr + 2))
            if xa >= xb or ya >= yb:
                continue
            d = np.hypot(xx[ya:yb, xa:xb] - x0, yy[ya:yb, xa:xb] - y0)
            t = np.where(d <= max(rr, 0.5), t0 + (t1 - t0) * sv / total, np.inf)
            view = best[ya:yb, xa:xb]
            np.minimum(view, t, out=view)
    out = np.full(shape, T_NONE, np.uint8)
    hit = np.isfinite(best)
    out[hit] = np.floor(best[hit]).astype(np.uint8)
    return out


def graded_t(shape, src, hit):
    """Times for an area that moves from its top edge down (grade: down) or
    from its left edge right (grade: right), broken up by smooth noise so it
    does not advance as a straight front."""
    t0, t1 = time_range(src)
    axis = 1 if src.get('grade') == 'right' else 0
    ys = np.nonzero(hit)[axis]
    if not len(ys):
        return np.full(shape, T_NONE, np.uint8)
    yy = np.mgrid[0:shape[0], 0:shape[1]][axis]
    down = (yy - ys.min()) / max(1, ys.max() - ys.min())
    mix = src.get('noise', 0.35)
    f = (1 - mix) * down + mix * smooth_noise(shape, src.get('cell', 24), src.get('seed', 1))
    return np.where(hit, np.floor(t0 + (t1 - t0) * np.clip(f, 0, 1)), T_NONE).astype(np.uint8)


def rockfall_lines(src):
    """Random downhill rock paths: start inside `starts` box, end near `foot`
    y, wander sideways; each path gets its own start/end time (so rocks set
    off at different moments and fall at different speeds) and width."""
    rng = np.random.default_rng(src.get('seed', 1))
    (sx0, sy0), (sx1, sy1) = src['starts']
    fy0, fy1 = src['foot']
    lines = []
    for _ in range(src['count']):
        x, y = rng.uniform(sx0, sx1), rng.uniform(sy0, sy1)
        end = rng.uniform(fy0, fy1)
        pts = [[x, y]]
        for k in range(1, 5):
            yk = y + (end - y) * k / 4
            x += rng.uniform(-1, 1) * src.get('wander', 8)
            pts.append([x, yk])
        t0 = int(rng.uniform(0, src.get('start_spread', 70)))
        t1 = int(min(239, t0 + rng.uniform(*src.get('fall', (150, 230)))))
        w = float(rng.uniform(src.get('width_min', 3), src.get('width_max', 6)))
        lines.append({'points': pts, 't0': t0, 't1': t1, 'width': w})
    return lines


def dust_levels(shape, src):
    """Dust cloud, 4 densities (0 thin .. 3 dense): a blurred polygon gives
    soft edges, a vertical ramp keeps it densest at the foot, smooth noise
    breaks it into billows. Pixels below the thinnest level are left out."""
    from PIL import ImageFilter
    area = polygon_t(shape, {**src, 't0': 0}) < 240
    ys = np.nonzero(area)[0]
    soft = np.asarray(Image.fromarray(area.astype(np.uint8) * 255).filter(
        ImageFilter.GaussianBlur(src.get('soft', 10))), np.float64) / 255
    yy = np.mgrid[0:shape[0], 0:shape[1]][0]
    low = np.clip((yy - ys.min()) / max(1, ys.max() - ys.min()), 0, 1)   # 0 top, 1 foot
    n = smooth_noise(shape, src.get('cell', 20), src.get('seed', 1))
    f = soft * (0.45 * low + 0.55 * n)
    lv = np.floor((f - 0.18) / 0.12).astype(np.int32)
    return np.where(f >= 0.18, np.clip(lv, 0, 3), -1)


def quake_rings(shape, src):
    """Seismicity map circles: explicit events [x, y, r, t] plus `aftershocks`
    random events near `near` (count, spread, r range, t range). Returns
    (white, dark) time maps: a 1-2 px white ring of radius r and a 1 px dark
    outline just outside it; where rings overlap the earliest event wins."""
    h, w = shape
    events = [tuple(e) for e in src.get('events', [])]
    a = src.get('aftershocks')
    if a:
        rng = np.random.default_rng(a.get('seed', 1))
        cx, cy = a['near']
        (r0, r1), (t0, t1) = a['radius'], a['time']
        ang = np.radians(a.get('along', 0))
        for _ in range(a['count']):
            u = rng.normal(0, a['spread'])            # along the fault
            v = rng.normal(0, a.get('across', 6))
            x = cx + u * np.cos(ang) - v * np.sin(ang)
            y = cy + u * np.sin(ang) + v * np.cos(ang)
            r = r0 + (r1 - r0) * rng.random() ** 2      # mostly small
            events.append((x, y, r, int(rng.uniform(t0, t1))))
    white = np.full(shape, np.inf)
    dark = np.full(shape, np.inf)
    yy, xx = np.mgrid[0:h, 0:w]
    for x, y, r, t in events:
        xa, xb = int(max(0, x - r - 3)), int(min(w, x + r + 4))
        ya, yb = int(max(0, y - r - 3)), int(min(h, y + r + 4))
        d = np.hypot(xx[ya:yb, xa:xb] - x, yy[ya:yb, xa:xb] - y)
        width = 2.0 if r >= 8 else 1.2
        ring = (d >= r - width / 2) & (d <= r + width / 2)
        edge = (d > r + width / 2) & (d <= r + width / 2 + 1.2)
        np.minimum(white[ya:yb, xa:xb], np.where(ring, t, np.inf), out=white[ya:yb, xa:xb])
        np.minimum(dark[ya:yb, xa:xb], np.where(edge, t, np.inf), out=dark[ya:yb, xa:xb])
    return white, dark


def distance_t(shape, src):
    """Time = distance from `center` / `step` px, capped at 239 (wave field)."""
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    d = np.hypot(xx - src['center'][0], yy - src['center'][1]) * 4 / src.get('step', 6)
    return np.minimum(d, 239).astype(np.uint8)


def source_t(shape, src, base_dir):
    kind = src['type']
    if kind == 'distance':
        return distance_t(shape, src)
    if kind == 'rockfall':
        out = np.full(shape, T_NONE, np.uint8)
        for line in rockfall_lines(src):
            t = polyline_t(shape, {'width': line.pop('width'), 'accel': True, 'lines': [line]})
            out = np.where(t < 240, np.minimum(out, t), out)
        return out
    if kind == 'crack':
        return crack_t(shape, src)
    if kind == 'patches':
        # Bare-ground patches inside a polygon where smooth noise is high.
        area = polygon_t(shape, {**src, 't0': 0}) < 240
        n = smooth_noise(shape, src.get('cell', 10), src.get('seed', 1))
        return graded_t(shape, src, area & (n > src.get('threshold', 0.7)))
    if kind == 'paint':
        return paint_t(shape, src, base_dir)
    if kind == 'polyline':
        return polyline_t(shape, src)
    if kind == 'seeds':
        return seeds_t(shape, src, base_dir)
    if kind in ('polygon', 'outline'):
        return polygon_t(shape, src, kind == 'outline')
    if kind == 'mask':
        hit = load_gray(base_dir / src['file'], shape) >= 128
        if src.get('rough'):
            hit = rough(hit, src['rough'], src.get('seed', 1))
        if src.get('grade') in ('down', 'right'):
            return graded_t(shape, src, hit)
        return np.where(hit, src.get('t0', 0), T_NONE).astype(np.uint8)
    raise SystemExit(f'unknown source type: {kind}')


def stage_t3(shape, stage, base_dir):
    """format 3: later sources overwrite earlier ones where they reach.
    Evacuation stages: refuges must lie outside the danger region; a route may
    start inside it (homes at the slope foot) but once out must not re-enter.
    A violation stops the build."""
    T = np.full(shape, T_NONE, np.uint8)
    reach = {}
    routes = []
    for src in stage.get('sources') or []:
        region = src.get('region', 0)
        if src['type'] == 'quakes':      # white ring in `region`, dark outline in `region`+1
            white, dark = quake_rings(shape, src)
            for reg, tm in ((region + 1, dark), (region, white)):
                hit = np.isfinite(tm)
                T[hit] = (reg << 6) | np.minimum(tm[hit].astype(np.int32) >> 2, v3.TIME_MAX)
            continue
        if src['type'] == 'dust':        # special codes: time 60..63 = dust density 0..3
            lv = dust_levels(shape, src)
            T[lv >= 0] = (region << 6) | (v3.SPECIAL + lv[lv >= 0])
            continue
        t = source_t(shape, src, base_dir)
        hit = t < 240
        T[hit] = (region << 6) | np.minimum(t[hit] >> 2, v3.TIME_MAX)
        reach[region] = reach.get(region, np.zeros(shape, bool)) | hit
        if region == v3.EVAC_ROUTE and src['type'] == 'polyline':
            for line in src['lines']:
                routes.append(polyline_t(shape, {**src, 'lines': [line]}))
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    refuge = np.zeros(shape, bool)
    for x, y, r in stage.get('spots') or []:
        refuge |= (xx - x) ** 2 + (yy - y) ** 2 <= r * r
    T[refuge] = v3.encode(v3.EVAC_REFUGE, 0)
    if stage.get('role') == 'evacuation' and v3.EVAC_DANGER in reach:
        danger = reach[v3.EVAC_DANGER]
        name = stage.get('name', 'evacuation')

        def fail(what, bad):
            ys, xs = np.nonzero(bad)
            raise SystemExit(f'{name}: {what} at {int(bad.sum())} px, '
                             f'x {xs.min()}..{xs.max()}, y {ys.min()}..{ys.max()}')
        if (refuge & danger).any():
            fail('refuge inside the danger zone', refuge & danger)
        for n, t in enumerate(routes):
            on = t < 240
            inside, outside = on & danger, on & ~danger
            if outside.any() and inside.any():
                # Pixels across the line width share times within a few steps.
                late = inside & (t > t[outside].min() + 4)
                if late.any():
                    fail(f'route {n + 1} re-enters the danger zone after leaving it', late)
            elif inside.any():
                fail(f'route {n + 1} never leaves the danger zone', inside)
    return T


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


def write_bmp32(path, rgb, T, kind=(0, 0)):
    h, w = T.shape
    px = np.empty((h, w, 4), np.uint8)
    px[..., 0], px[..., 1], px[..., 2], px[..., 3] = rgb[..., 2], rgb[..., 1], rgb[..., 0], T
    data = px[::-1].tobytes()     # bottom-up rows, width*4 needs no padding
    head = struct.pack('<2sIBBHI', b'BM', HEADER_BYTES + len(data), kind[0], kind[1], 0, HEADER_BYTES)
    head += struct.pack('<IiiHHIIiiII', 40, w, h, 1, 32, 0, len(data), 3780, 3780, 0, 0)
    path.write_bytes(head + data)


def check_bmp32(path, rgb, T, kind=(0, 0)):
    d = path.read_bytes()
    if tuple(d[6:8]) != tuple(kind):
        raise SystemExit(f'{path}: header type bytes {tuple(d[6:8])}, expected {kind}')
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


def t_preview3(T):
    """format 3: white none; one hue per region, darker = earlier."""
    out = np.full(T.shape + (3,), 255, np.uint8)
    hue = ((40, 90, 200), (210, 60, 40), (30, 170, 60), (150, 80, 180))
    for r, c in enumerate(hue):
        m = ((T >> 6) == r) & (T != T_NONE)
        g = (T[m] & 63).astype(np.int32)
        out[m] = np.stack([np.minimum(255, c[i] + g * 2) for i in range(3)], axis=-1)
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
    ap.add_argument('--gif', action='store_true', help='format 3: also write gif/PICn.gif previews')
    ap.add_argument('--audio', action='store_true', help='also write SND1-4.PCM from stage sound/narration')
    ap.add_argument('--no-tts', action='store_true', help='with --audio: beeps instead of SAPI speech')
    ap.add_argument('--text', action='store_true', help='also write FONT.BIN and TEXT.BIN (scene OSD text)')
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
    fmt = cfg.get('format', 2)
    if a.gif:
        (out / 'gif').mkdir(parents=True, exist_ok=True)
    for sub in ('sd', 'expected', 'tmap'):
        (out / sub).mkdir(parents=True, exist_ok=True)

    rows = []
    for n, stage in enumerate(stages):
        img = Image.open(base_dir / stage.get('image', cfg['base'])).convert('RGB')
        if img.size != (w, h):
            raise SystemExit(f'stage {n + 1} image size {img.size}, scene is {w}x{h}')
        rgb = np.asarray(img, np.uint8)
        if fmt == 3:
            hz, role = stage['hazard'], stage['role']
            kind = (v3.HAZARDS[hz], v3.ROLES[role])
            T = stage_t3(shape, stage, base_dir)
            def model(t, fc, rgb=rgb, T=T, hz=hz, role=role):
                return v3.render(rgb, T, hz, role, t, 0x3FF if fc else 0)
        else:
            kind = (0, 0)
            T = stage_t(shape, stage, base_dir)
            def model(t, fc, rgb=rgb, T=T, n=n):
                return hazard_layer_model(rgb, T, t, n, 0x3F if fc else 0x00)
        bmp = out / 'sd' / f'PIC{n + 1}.BMP'
        write_bmp32(bmp, rgb, T, kind)
        check_bmp32(bmp, rgb, T, kind)
        Image.fromarray(t_preview3(T) if fmt == 3 else t_preview(T)).save(out / 'tmap' / f'PIC{n + 1}_T.png')
        if a.gif and fmt == 3:
            frames = [Image.fromarray(v3.render(rgb, T, hz, role, k // 2 % 240, k & 1023)).convert(
                'P', palette=Image.ADAPTIVE, colors=160) for k in range(0, 480, 2)]
            frames[0].save(out / 'gif' / f'PIC{n + 1}.gif', save_all=True, append_images=frames[1:],
                           duration=33, loop=0)
        row = []
        for t in EXPECTED_TIMES:
            for phase in (1, 0):
                # on: every blink bit 1 (frame_cnt 0x3F, or 0x3FF for format 3), off: 0
                exp = model(t, phase)
                Image.fromarray(exp).save(out / 'expected' / f'PIC{n + 1}_t{t:03d}_{"on" if phase else "off"}.png')
                if phase or t == T_MAX:
                    row.append(exp)
        row.append(t_preview(T))
        rows.append(row)
        if fmt == 3:
            regs = ', '.join(f'r{r} {int((((T >> 6) == r) & (T != T_NONE)).sum())} px' for r in range(4))
            print(f'{bmp}: {bmp.stat().st_size} bytes, stage {n + 1} {hz}/{role}: {regs}')
        else:
            cov = T < 240
            tr = f'T {T[cov].min()}..{T[cov].max()}' if cov.any() else 'no hazard pixels'
            print(f'{bmp}: {bmp.stat().st_size} bytes, stage {n + 1}: '
                  f'{int(cov.sum())} hazard px ({tr}), {int((T == T_SPOT).sum())} refuge px')
    overview(rows, out / 'overview.png')
    print(f'{out / "overview.png"}: columns t=0 on, t=120 on, t=239 on, t=239 off, T map')
    if a.audio:
        import scene_audio
        scene_audio.write_stage_audio(cfg, base_dir, out, tts=not a.no_tts)
    if a.text:
        import scene_text
        scene_text.write_scene_text(cfg, base_dir, out)



if __name__ == '__main__':
    main()
