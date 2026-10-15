#!/usr/bin/env python3
"""Prepare the valley village scene from the four generated aerial images.

Usage: py -I tools/scenes/valley_village/prepare_valley_village.py [PHOTO_DIR]
PHOTO_DIR defaults to tools/Photo and must hold "phase1 pic.png" ...
"phase4 pic.png" (4:3). Writes, next to this script:
  pic1.png .. pic4.png   640x480 stage base maps (Lanczos)
  flood_dem.png          stage 3 cost field: 40 on the river centre line,
                         rising with distance, so water fills the channel
                         before it spills onto the west floodplain
  flood_mask.png         stage 3 maximum flood extent (white passable)
  gully_mask.png         stage 3 gully corridor and debris fan
Each stage's T is drawn on that stage's own image (the AI variants shift by a
few pixels); coordinates live here and in scene.yaml.
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
W, H = 640, 480

# Stage 3 (pic3) river centre line, x at y, read off the image.
RIVER = [(0, 422), (60, 424), (120, 428), (180, 430), (240, 432), (300, 432), (360, 436), (420, 444), (480, 452)]
# Maximum flood extent on pic3: river channel plus the west floodplain fields,
# reaching the lowest houses next to the bridge path. The east bank is cliff.
FLOOD_EXTENT = [(384, 0), (376, 50), (360, 100), (340, 150), (332, 200), (318, 240), (300, 285),
                (288, 330), (296, 380), (322, 425), (342, 480), (492, 480), (482, 400), (474, 300),
                (470, 200), (466, 100), (458, 50), (456, 0)]
# Gully corridor from the slope down to the village, opening into a debris fan
# behind the houses (pic3).
GULLY = [(112, 48), (130, 80), (148, 106), (164, 132), (178, 156), (188, 172), (186, 204), (204, 236),
         (238, 252), (268, 240), (262, 206), (232, 178), (210, 164), (198, 148), (184, 124), (168, 98),
         (150, 72), (128, 44)]


def rough_mask(poly, seed, blur=6, amp=70):
    """Polygon mask whose edge wanders with smooth fixed-seed noise."""
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(blur)), np.float64)
    rng = np.random.default_rng(seed)
    noise = Image.fromarray((rng.random((H // 24 + 2, W // 24 + 2)) * 255).astype(np.uint8))
    noise = np.asarray(noise.resize((W, H), Image.BICUBIC), np.float64) - 128
    return Image.fromarray(np.where(soft + noise * amp / 128 > 128, 255, 0).astype(np.uint8))


def river_x(y):
    ys, xs = zip(*RIVER)
    return np.interp(y, ys, xs)


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / 'Photo'
    for n in range(1, 5):
        im = Image.open(src / f'phase{n} pic.png').convert('RGB')
        w, h = im.size
        if abs(w * 3 - h * 4) > 4:
            raise SystemExit(f'phase{n} pic.png is {w}x{h}, expected 4:3')
        im.resize((W, H), Image.LANCZOS).save(HERE / f'pic{n}.png')
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.abs(xx - river_x(yy))
    Image.fromarray(np.clip(40 + d * 1.5, 0, 255).astype(np.uint8)).save(HERE / 'flood_dem.png')
    rough_mask(FLOOD_EXTENT, 17).save(HERE / 'flood_mask.png')
    rough_mask(GULLY, 23, blur=3, amp=50).save(HERE / 'gully_mask.png')
    print('prepared pic1-4, flood_dem, flood_mask, gully_mask')


if __name__ == '__main__':
    main()
