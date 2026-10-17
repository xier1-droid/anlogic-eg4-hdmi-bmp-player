#!/usr/bin/env python3
"""Prepare the flash flood card from the four generated images.

Usage: py -I tools/scenes/flood_village/prepare_flood_village.py [PHOTO_DIR]
PHOTO_DIR defaults to tools/Photo/flood and must hold PIC1.png .. PIC4.png
(4:3). PIC1, PIC3 and PIC4 share one framing (river from the upper left to
the lower right, village on the low near-bank terrace, 5 houses on the far
bank, one bridge); PIC2 is the riverbank close-up. Writes, next to this script:
  pic1.png .. pic4.png   640x480 base maps (Lanczos)
  flood_mask.png         PIC3/PIC4 maximum flood: channel, gravel bars, the
                         near-bank fields up to the village edge and the
                         far-bank fields below the houses
  flood_dem.png          PIC3 cost field: 40 on the river centre line, rising
                         with distance, so water fills the channel first
  bank_mask.png          PIC2 overbank flood: from the river edge over the
                         bank and the fields to the lane before the houses
  bank_dem.png           PIC2 cost field: rising away from the river edge
  river_mask.png         PIC2 river channel between the far-bank rocks and the
                         near-bank edge
  spill_mask.png         PIC2 bank top: a 12 px strip below the river edge
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
W, H = 640, 480
# PIC1/3/4 river centre line (x, y), upstream to downstream.
RIVER = [(140, 104), (170, 122), (205, 148), (240, 172), (275, 196), (320, 222), (370, 246),
         (420, 270), (470, 296), (520, 322), (570, 348), (620, 372), (660, 392)]
FLOOD = [(116, 108), (150, 136), (184, 168), (214, 196), (244, 222), (266, 244), (300, 270),
         (330, 292), (356, 318), (370, 352), (382, 390), (408, 430), (440, 480), (640, 480),
         (640, 330), (600, 300), (560, 272), (520, 252), (470, 232), (440, 222), (400, 212),
         (360, 200), (320, 186), (290, 172), (260, 154), (230, 136), (200, 118), (172, 100), (140, 88)]
# PIC2 river edge (x, y) from left to right; water is above this line.
EDGE2 = [(0, 120), (80, 150), (160, 170), (240, 190), (320, 210), (400, 234), (480, 256),
         (560, 276), (640, 290)]
# PIC2 far-bank rock line (x, y); the river lies between it and EDGE2.
FAR2 = [(130, 0), (160, 10), (240, 26), (320, 42), (400, 62), (480, 82), (560, 100), (640, 118)]
# Water stops at the lane in front of the first row of houses.
HOUSES2 = [(640, 452), (560, 432), (480, 410), (400, 390), (320, 372), (240, 352), (160, 330),
           (80, 306), (0, 286)]
BANK2 = EDGE2 + HOUSES2


def ragged(mask, blur, amp, cell, seed):
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(blur)), np.float64)
    noise = np.random.default_rng(seed).random((H // cell + 2, W // cell + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64) - 128
    return Image.fromarray(np.where(soft + noise * amp > 128, 255, 0).astype(np.uint8))


def line_distance(pts):
    """Distance from every pixel to a polyline."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    best = np.full((H, W), np.inf)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        u = np.clip(((xx - x0) * dx + (yy - y0) * dy) / (dx * dx + dy * dy), 0, 1)
        best = np.minimum(best, np.hypot(xx - x0 - u * dx, yy - y0 - u * dy))
    return best


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / 'Photo' / 'flood'
    for n in range(1, 5):
        im = Image.open(src / f'PIC{n}.png').convert('RGB')
        w, h = im.size
        if abs(w * 3 - h * 4) > 4:
            raise SystemExit(f'PIC{n}.png is {w}x{h}, expected 4:3')
        im.resize((W, H), Image.LANCZOS).save(HERE / f'pic{n}.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(FLOOD, fill=255)
    ragged(m, 6, 0.8, 18, 81).save(HERE / 'flood_mask.png')
    d = line_distance(RIVER)
    Image.fromarray(np.clip(40 + d * 1.2, 0, 255).astype(np.uint8)).save(HERE / 'flood_dem.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(BANK2, fill=255)
    ragged(m, 4, 0.6, 14, 83).save(HERE / 'bank_mask.png')
    # Uneven advance: water runs ahead along low furrows (smooth noise).
    d = line_distance(EDGE2)
    noise = np.random.default_rng(85).random((H // 20 + 2, W // 20 + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64)
    Image.fromarray(np.clip(40 + d * 0.6 + noise * 0.16, 0, 255).astype(np.uint8)).save(HERE / 'bank_dem.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon([(0, 0)] + FAR2 + list(reversed(EDGE2)), fill=255)
    m.save(HERE / 'river_mask.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(EDGE2 + [(x, y + 12) for x, y in reversed(EDGE2)], fill=255)
    ragged(m, 2, 0.6, 6, 87).save(HERE / 'spill_mask.png')
    print('prepared pic1-4, flood_mask, flood_dem, bank_mask, bank_dem, river_mask, spill_mask')


if __name__ == '__main__':
    main()
