#!/usr/bin/env python3
"""Draw the fictional demo village: base.png, dem.png and gully_flood.png (640x480).

Terrain is synthetic (no map data). Evacuation paths and refuge points are read
from scene.yaml so the base map matches the stage 4 T layer.
Usage: py -I tools/scenes/demo_village/draw_demo_village.py
"""
from pathlib import Path
import math
import numpy as np
import yaml
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
W, H = 640, 480
FLOOR = 40                      # valley floor height (dem units)
VILLAGE = (245, 255, 325, 345)  # x0, y0, x1, y1
PLATEAUS = [((548, 250), 48, 150), ((95, 420), 34, 118)]   # centre, radius, level
GULLY = [(92, 228), (138, 250), (184, 270), (230, 290), (266, 300)]   # side gully, top to mouth


def river_x(y):
    return 430 - 0.2 * y + 25 * np.sin(y / 70)


def smooth_noise(rng, scale):
    """Low-frequency noise: coarse random grid upsampled bicubically."""
    g = rng.random((H // scale + 2, W // scale + 2)).astype(np.float32)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((W + 2 * scale, H + 2 * scale), Image.BICUBIC)
    return np.asarray(im, np.float32)[scale:scale + H, scale:scale + W] / 255 - 0.5


def polyline_distance(xx, yy, pts):
    """Distance to a polyline and the arc length of the nearest point."""
    best, arc, cum = np.full(xx.shape, np.inf, np.float32), np.zeros(xx.shape, np.float32), 0.0
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        u = np.clip(((xx - x0) * dx + (yy - y0) * dy) / (L * L), 0, 1)
        d = np.hypot(xx - x0 - u * dx, yy - y0 - u * dy)
        closer = d < best
        best, arc = np.where(closer, d, best), np.where(closer, cum + u * L, arc)
        cum += L
    return best, arc


def make_dem(rng):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    rx = river_x(yy)
    d = np.abs(xx - rx)
    half = np.where(xx < rx, 115.0, 55.0)          # wider floor on the village side
    h = FLOOR + 0.85 * np.maximum(0, d - half) ** 1.08
    for (cx, cy), amp, sig in [((40, 60), 70, 90), ((620, 30), 60, 100), ((20, 300), 40, 70), ((630, 440), 50, 90)]:
        h += amp * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * sig * sig))
    rough = 14 * smooth_noise(rng, 40) + 5 * smooth_noise(rng, 12)
    h += rough * np.clip((h - FLOOR) / 30, 0, 1)    # keep the floor flat
    gd, _ = polyline_distance(xx, yy, GULLY)
    h -= np.clip(h - FLOOR, 0, 18) * np.exp(-gd * gd / 72)   # carve the gully into the slope
    for (cx, cy), r, level in PLATEAUS:
        rr = np.hypot(xx - cx, yy - cy)
        blend = np.clip((r + 25 - rr) / 25, 0, 1)
        h = np.where(rr <= r, level, h * (1 - blend) + level * blend)
    return np.clip(h, 0, 255)


def hillshade(h):
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx, -gy, np.full_like(h, 2.0)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = -0.6, -0.6, 0.53                  # light from the north-west
    return 0.6 + 0.4 * np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1)


def colour(h, rng):
    stops = [(FLOOR, (150, 190, 105)), (70, (110, 160, 80)), (110, (120, 140, 70)),
             (145, (150, 130, 90)), (200, (165, 150, 130)), (255, (210, 205, 200))]
    lv = np.array([s[0] for s in stops], np.float32)
    rgb = np.stack([np.interp(h, lv, [s[1][c] for s in stops]) for c in range(3)], axis=-1)
    yy, xx = np.mgrid[0:H, 0:W]
    for (cx, cy), r, _ in PLATEAUS:                 # flat meadow on high ground
        rgb[np.hypot(xx - cx, yy - cy) <= r] = (165, 195, 115)
    rgb *= hillshade(h)[..., None]
    rgb += 6 * smooth_noise(rng, 6)[..., None]
    return np.clip(rgb, 0, 255).astype(np.uint8)


def draw_village(dr, rng):
    x0, y0, x1, y1 = VILLAGE
    dr.line([(x0 - 5, (y0 + y1) // 2), (x1 + 25, (y0 + y1) // 2 - 4)], fill=(205, 190, 150), width=4)
    for gx in range(x0 + 4, x1 - 8, 19):
        for gy in range(y0 + 4, y1 - 8, 22):
            if rng.random() < 0.18:
                continue
            ox, oy = gx + int(rng.integers(-3, 4)), gy + int(rng.integers(-3, 4))
            dr.rectangle([ox, oy + 4, ox + 12, oy + 14], fill=(235, 228, 210), outline=(90, 80, 70))
            roof = (180, 60, 45) if rng.random() < 0.6 else (90, 95, 110)
            dr.polygon([(ox - 2, oy + 5), (ox + 6, oy - 2), (ox + 14, oy + 5)], fill=roof, outline=(70, 50, 40))


def draw_refuge(dr, x, y):
    dr.rectangle([x - 9, y + 2, x + 9, y + 12], fill=(245, 240, 225), outline=(60, 60, 60))
    dr.polygon([(x - 12, y + 3), (x, y - 6), (x + 12, y + 3)], fill=(40, 120, 200), outline=(30, 60, 100))
    dr.line([(x + 14, y + 12), (x + 14, y - 14)], fill=(60, 60, 60), width=2)
    dr.polygon([(x + 15, y - 14), (x + 26, y - 10), (x + 15, y - 6)], fill=(230, 40, 40))


def main():
    rng = np.random.default_rng(170)
    cfg = yaml.safe_load((HERE / 'scene.yaml').read_text(encoding='utf-8'))
    route_stage = cfg['stages'][3]
    dem = make_dem(rng)
    base = Image.fromarray(colour(dem, rng))
    dr = ImageDraw.Draw(base)

    ys = np.arange(-5, H + 6)
    river = [(float(river_x(y)), float(y)) for y in ys]
    dr.line(river, fill=(90, 140, 200), width=13)
    dr.line(river, fill=(70, 120, 190), width=7)
    dr.line(GULLY, fill=(90, 140, 200), width=3)
    for src in route_stage.get('sources') or []:
        for line in src.get('lines', []):
            pts = [tuple(p) for p in (line['points'] if isinstance(line, dict) else line)]
            dr.line(pts, fill=(200, 180, 130), width=3)
    by = 300
    bx = float(river_x(by))
    dr.rectangle([bx - 12, by - 5, bx + 12, by + 3], fill=(150, 110, 70), outline=(80, 60, 40))   # bridge
    draw_village(dr, rng)
    for x, y, _ in route_stage.get('spots') or []:
        draw_refuge(dr, x, y)

    # Stand-in for a hand-painted T map: a flash flood running down the side gully
    # into the village, dark (early) at the top and widening towards the mouth.
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    gd, arc = polyline_distance(xx, yy, GULLY)
    total = sum(math.dist(a, b) for a, b in zip(GULLY[:-1], GULLY[1:]))
    inside = gd <= 3 + 22 * (arc / total) ** 2
    gully = np.full((H, W), 255, np.uint8)
    gully[inside] = (10 + 150 * arc[inside] / total + gd[inside]).astype(np.uint8)

    base.save(HERE / 'base.png')
    Image.fromarray(dem.astype(np.uint8)).save(HERE / 'dem.png')
    Image.fromarray(gully).save(HERE / 'gully_flood.png')
    for name in ('base.png', 'dem.png', 'gully_flood.png'):
        print(f'{HERE / name}: {(HERE / name).stat().st_size} bytes')


if __name__ == '__main__':
    main()
