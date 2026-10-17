#!/usr/bin/env python3
"""Prepare the earthquake card from the generated images.

Usage: py -I tools/scenes/quake_village/prepare_quake_village.py [PHOTO_DIR]
PHOTO_DIR defaults to tools/Photo/earthquake. Uses PIC1.png (geological map),
PIC2.png (village close-up), PIC3.png (hazy overview) and PIC4.png (clear
overview, same framing as PIC3); PIC0.png (an earlier overview) is not used.
Writes, next to this script:
  pic1.png .. pic4.png   640x480 base maps (Lanczos)
  debris_mask.png        PIC3 cliff-collapse runout over the slope foot and
                         the top row of houses below the scree
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
W, H = 640, 480
# PIC3/PIC4: debris below the scree, reaching the top row of houses.
DEBRIS = [(330, 150), (420, 132), (520, 150), (600, 168), (640, 178), (640, 232), (590, 228),
          (530, 214), (470, 206), (420, 200), (370, 196), (336, 182)]


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / 'Photo' / 'earthquake'
    for n in range(1, 5):
        im = Image.open(src / f'PIC{n}.png').convert('RGB')
        w, h = im.size
        if abs(w * 3 - h * 4) > 4:
            raise SystemExit(f'PIC{n}.png is {w}x{h}, expected 4:3')
        im.resize((W, H), Image.LANCZOS).save(HERE / f'pic{n}.png')
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(DEBRIS, fill=255)
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(6)), np.float64)
    noise = np.random.default_rng(91).random((H // 12 + 2, W // 12 + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64) - 128
    Image.fromarray(np.where(soft + noise * 0.9 > 128, 255, 0).astype(np.uint8)).save(HERE / 'debris_mask.png')
    print('prepared pic1-4, debris_mask')


if __name__ == '__main__':
    main()
