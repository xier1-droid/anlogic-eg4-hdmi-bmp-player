#!/usr/bin/env python3
"""Prepare the landslide card from the four generated images.

Usage: py -I tools/scenes/landslide_village/prepare_landslide_village.py [PHOTO_DIR]
PHOTO_DIR defaults to tools/Photo/landslide and must hold PIC1.png .. PIC4.png
(4:3). Writes, next to this script:
  pic1.png .. pic4.png   640x480 base maps (Lanczos)
  deposit_mask.png       PIC3 runout fan: slope foot over the terraces, the
                         houses below the scar and the road (white = reached)
  scarp_mask.png         PIC2 main scarp: 6-20 px below the crack arc, ragged
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
W, H = 640, 480
# PIC3 (same framing as PIC1): deposit fan below the scar.
# PIC2 crack arc, west end to east end (scene.yaml uses the same points).
CRACK = [(266, 98), (296, 78), (330, 64), (380, 58), (430, 64), (470, 80), (500, 102), (512, 124)]
SCARP_DEPTH = 14
DEPOSIT = [(300, 232), (425, 232), (446, 270), (470, 318), (482, 368), (472, 402), (400, 408),
           (300, 398), (258, 372), (254, 320), (274, 270)]


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / 'Photo' / 'landslide'
    for n in range(1, 5):
        im = Image.open(src / f'PIC{n}.png').convert('RGB')
        w, h = im.size
        if abs(w * 3 - h * 4) > 4:
            raise SystemExit(f'PIC{n}.png is {w}x{h}, expected 4:3')
        im.resize((W, H), Image.LANCZOS).save(HERE / f'pic{n}.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(DEPOSIT, fill=255)
    # Lobed edge: fixed-seed smooth noise, so the fan is not a clean polygon.
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(8)), np.float64)
    noise = np.random.default_rng(31).random((H // 16 + 2, W // 16 + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64) - 128
    Image.fromarray(np.where(soft + noise * 0.9 > 128, 255, 0).astype(np.uint8)).save(HERE / 'deposit_mask.png')
    # Scarp: deepest in the middle of the arc, shallow at the ends, ragged
    # lower edge.
    m = Image.new('L', (W, H), 0)
    n = len(CRACK)
    depth = [6 + SCARP_DEPTH * (1 - abs(2 * i / (n - 1) - 1)) for i in range(n)]
    ImageDraw.Draw(m).polygon(CRACK + [(x, y + d) for (x, y), d in reversed(list(zip(CRACK, depth)))], fill=255)
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(3)), np.float64)
    noise = np.random.default_rng(37).random((H // 6 + 2, W // 6 + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64) - 128
    Image.fromarray(np.where(soft + noise * 0.9 > 128, 255, 0).astype(np.uint8)).save(HERE / 'scarp_mask.png')
    print('prepared pic1-4, deposit_mask, scarp_mask')


if __name__ == '__main__':
    main()
