#!/usr/bin/env python3
"""M3 v3 hazard_layer stimulus and answers from tools/hazard_v3.render.

Usage: python -I make_hazard_vectors3.py VEC_DIR CARD_OUT...
CARD_OUT are make_scene_pack output directories of format 3 cards (sd/).
Writes into VEC_DIR:
  sweep.txt   one block per (hazard, role) plus pass-through blocks; a block
              is 240 rows of 256 pixels (row n: t_now=n, pixel i: T=i, so the
              layer sees x=i, y=n), each row with its own random frame_cnt.
              Line: "rgb T t_now frame_cnt hazard role thumb expected" (hex).
  cards.txt   card cases: "bmp_path t_now frame_cnt exp_file"; hazard and
              role come from the BMP header (bytes 6-7).
  card_*.bin  expected RGB, top-down rows, 640x480x3 bytes.
"""
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import hazard_v3 as v3  # noqa: E402

HZ = {v: k for k, v in v3.HAZARDS.items()}
RL = {v: k for k, v in v3.ROLES.items()}
# Card cases per role: times and frame counters. Onset images get extra
# counters so the earthquake shake sees every offset (fc & 3 = 1, 3) at
# amplitudes 4..1 and the flood/debris motion several phases.
CARD_T = {1: (0, 100, 239), 2: (0, 50, 90, 120, 150, 239), 3: (0, 120, 239), 4: (0, 120, 239)}
CARD_FC = (0x3FF, 0x000, 0x1A5, 0x2D3, 0x0F1)


def read_bmp32(path):
    d = path.read_bytes()
    off = int.from_bytes(d[10:14], 'little')
    w = int.from_bytes(d[18:22], 'little')
    h = int.from_bytes(d[22:26], 'little')
    px = np.frombuffer(d, np.uint8, w * h * 4, off).reshape(h, w, 4)[::-1]
    return px[..., 2::-1].copy(), px[..., 3].copy(), d[6], d[7]


def sweep(vec):
    rng = np.random.default_rng(317)
    T = np.arange(256, dtype=np.uint8).reshape(1, 256)
    x = np.arange(256).reshape(1, 256)
    blocks = [(h, r, 0) for h in range(1, 5) for r in range(1, 5)]
    blocks += [(0, 2, 0), (4, 0, 0), (3, 2, 1), (4, 2, 1)]      # pass-through: no kind, thumbnail
    n = 0
    with open(vec / 'sweep.txt', 'w', newline='\n') as f:
        for hz, role, thumb in blocks:
            for t in range(240):
                rgb = rng.integers(0, 256, (1, 256, 3), dtype=np.uint8)
                fc = int(rng.integers(0, 1024))
                if thumb or hz not in HZ or role not in RL or HZ[hz] == 'none' or RL[role] == 'none':
                    out = rgb
                else:
                    out = v3.render(rgb, T, HZ[hz], RL[role], t, fc, x=x, y=np.full((1, 256), t))
                for i in range(256):
                    r, g, b = rgb[0, i]
                    er, eg, eb = out[0, i]
                    f.write(f'{r:02x}{g:02x}{b:02x} {i:02x} {t:02x} {fc:03x} {hz} {role} {thumb} {er:02x}{eg:02x}{eb:02x}\n')
                    n += 1
    return n, len(blocks)


def cards(vec, dirs):
    lines = []
    for n, d in enumerate(dirs):           # card number in the name: output dirs may share a parent
        d = Path(d)
        for k in range(1, 5):
            bmp = d / 'sd' / f'PIC{k}.BMP'
            rgb, T, hz, role = read_bmp32(bmp)
            for t in CARD_T[role]:
                for fc in (CARD_FC if role == 2 else CARD_FC[:2]):
                    out = v3.render(rgb, T, HZ[hz], RL[role], t, fc)
                    name = f'card_{n}_PIC{k}_t{t:03d}_f{fc:03x}.bin'
                    (vec / name).write_bytes(out.tobytes())
                    lines.append(f'{bmp.resolve().as_posix()} {t} {fc} {name}\n')
    with open(vec / 'cards.txt', 'w', newline='\n') as f:
        f.writelines(lines)
    return len(lines)


def main():
    vec = Path(sys.argv[1])
    vec.mkdir(parents=True, exist_ok=True)
    n, b = sweep(vec)
    c = cards(vec, sys.argv[2:])
    print(f'sweep {n} vectors in {b} blocks, cards {c} frames')


if __name__ == '__main__':
    main()
