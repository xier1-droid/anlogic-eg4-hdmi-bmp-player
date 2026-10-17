#!/usr/bin/env python3
"""Prepare the debris flow card from the four generated images.

Usage: py -I tools/scenes/debris_village/prepare_debris_village.py [PHOTO_DIR]
PHOTO_DIR defaults to tools/Photo/debris_flow and must hold PIC1.png .. PIC4.png
(4:3). PIC1, PIC3 and PIC4 share one framing (gully down the middle, village
left of the gully mouth, two houses on the right bank); PIC2 is the gully
close-up. Writes, next to this script:
  pic1.png .. pic4.png   640x480 base maps (Lanczos)
  flow_mask.png          PIC2 slurry: the gully bed, slightly over the banks
  bank_mask.png          PIC2 mud splashed on the lower gully walls
  fan_mask.png           PIC3/PIC4 runout: gully mouth fan over the flats, the
                         nearest houses, road and bridge, and the channel below
  channel_mask.png       PIC3/PIC4 gully bed above the mouth
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
W, H = 640, 480
# PIC2 gully bed, left and right edge per row (y, x_left, x_right).
BED2 = [(0, 296, 350), (80, 290, 364), (160, 282, 374), (240, 280, 384), (320, 270, 404),
        (400, 250, 436), (440, 236, 474), (470, 232, 480)]
# PIC1/3/4 gully bed above the mouth.
BED1 = [(30, 328, 368), (120, 336, 388), (200, 348, 402), (270, 352, 412)]
# PIC3/4 runout fan below the mouth (clockwise), then the channel past the bridge.
FAN = [(352, 266), (412, 266), (446, 282), (482, 302), (516, 326), (532, 360), (506, 396), (456, 414),
       (400, 418), (344, 412), (300, 400), (262, 382), (248, 348), (262, 314), (300, 286)]
BELOW = [(392, 412), (440, 412), (448, 480), (396, 480)]


def bed_polygon(rows, grow=0):
    left = [(xl - grow, y) for y, xl, _ in rows]
    right = [(xr + grow, y) for y, _, xr in reversed(rows)]
    return left + right


def ragged(mask, blur, amp, cell, seed):
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(blur)), np.float64)
    noise = np.random.default_rng(seed).random((H // cell + 2, W // cell + 2)) * 255
    noise = np.asarray(Image.fromarray(noise.astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float64) - 128
    return Image.fromarray(np.where(soft + noise * amp > 128, 255, 0).astype(np.uint8))


def poly_mask(*polys):
    m = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=255)
    return m


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / 'Photo' / 'debris_flow'
    for n in range(1, 5):
        im = Image.open(src / f'PIC{n}.png').convert('RGB')
        w, h = im.size
        if abs(w * 3 - h * 4) > 4:
            raise SystemExit(f'PIC{n}.png is {w}x{h}, expected 4:3')
        im.resize((W, H), Image.LANCZOS).save(HERE / f'pic{n}.png')
    flow = ragged(poly_mask(bed_polygon(BED2, 4)), 3, 0.6, 8, 51)
    flow.save(HERE / 'flow_mask.png')
    bank = np.asarray(ragged(poly_mask(bed_polygon(BED2, 18)), 4, 0.9, 6, 53)) & ~np.asarray(flow)
    Image.fromarray(bank).save(HERE / 'bank_mask.png')
    ragged(poly_mask(FAN, BELOW), 8, 0.9, 16, 55).save(HERE / 'fan_mask.png')
    ragged(poly_mask(bed_polygon(BED1, 3)), 3, 0.5, 8, 57).save(HERE / 'channel_mask.png')
    print('prepared pic1-4, flow_mask, bank_mask, fan_mask, channel_mask')


if __name__ == '__main__':
    main()
