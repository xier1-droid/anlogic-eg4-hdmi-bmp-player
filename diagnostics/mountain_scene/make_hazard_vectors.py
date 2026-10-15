#!/usr/bin/env python3
"""M3 hazard_layer stimulus and answers from the M2 reference model.

Usage: python -I make_hazard_vectors.py SCENE_OUT VEC_DIR
SCENE_OUT is a make_scene_pack output directory (sd/, expected/). Writes:
  cases.txt           card cases: pic t_now frame_cnt enable thumbnail file
  exp_*.bin           expected RGB, top-down rows, 640x480x3 bytes
  sweep.txt           hex vectors: rgb T t_now stage alert en thumb frame_cnt expected
The expected PNGs are used as written by make_scene_pack (and checked against
hazard_layer_model); extra cases cover mixed blink phases, enable=0 and
thumbnail bypass.
"""
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import make_scene_pack as sp  # noqa: E402


def read_bmp32(path):
    d = path.read_bytes()
    off = int.from_bytes(d[10:14], 'little')
    w = int.from_bytes(d[18:22], 'little')
    h = int.from_bytes(d[22:26], 'little')
    px = np.frombuffer(d, np.uint8, w * h * 4, off).reshape(h, w, 4)[::-1]
    return px[..., 2::-1].copy(), px[..., 3].copy()


def main():
    scene, vec = Path(sys.argv[1]), Path(sys.argv[2])
    vec.mkdir(parents=True, exist_ok=True)
    cases = []
    png_cases = extra_cases = 0
    for n in range(1, 5):
        rgb, T = read_bmp32(scene / 'sd' / f'PIC{n}.BMP')
        stage = n - 1
        for t in sp.EXPECTED_TIMES:
            for phase in (1, 0):
                name = f'PIC{n}_t{t:03d}_{"on" if phase else "off"}'
                exp = np.asarray(Image.open(scene / 'expected' / f'{name}.png').convert('RGB'))
                model = sp.hazard_layer_model(rgb, T, t, stage, phase, phase)
                if not np.array_equal(exp, model):
                    raise SystemExit(f'{name}.png differs from hazard_layer_model')
                (vec / f'exp_{name}.bin').write_bytes(exp.tobytes())
                # all-ones / all-zeros frame counters give both blink bits = phase
                cases.append((n, t, 0x3F if phase else 0x00, 1, 0, f'exp_{name}.bin'))
                png_cases += 1
        # Mixed phases: fast on/slow off, fast off/slow on, and a counter where
        # only bit 2 is set (fast on only at alert_level 3).
        for fc in (0x1F, 0x20, 0x04):
            fast, slow = sp.blink_phase(fc, stage)
            name = f'PIC{n}_t120_f{fc:02x}'
            (vec / f'exp_{name}.bin').write_bytes(sp.hazard_layer_model(rgb, T, 120, stage, fast, slow).tobytes())
            cases.append((n, 120, fc, 1, 0, f'exp_{name}.bin'))
            extra_cases += 1
        (vec / f'exp_PIC{n}_raw.bin').write_bytes(rgb.tobytes())
        cases.append((n, 239, 0x3F, 0, 0, f'exp_PIC{n}_raw.bin'))
        cases.append((n, 239, 0x3F, 1, 1, f'exp_PIC{n}_raw.bin'))
        extra_cases += 2
    with open(vec / 'cases.txt', 'w', newline='\n') as f:
        for c in cases:
            f.write('%d %d %d %d %d %s\n' % c)

    # Exhaustive T x t_now per stage, one random rgb per pixel; each (t_now,
    # stage) group draws its own alert_level, frame_cnt, enable and thumbnail.
    rng = np.random.default_rng(170)
    T = np.arange(256, dtype=np.uint8).reshape(1, 256)
    lines = []
    for stage in range(4):
        for t in range(256):
            rgb = rng.integers(0, 256, (1, 256, 3), dtype=np.uint8)
            alert = int(rng.integers(0, 4))
            fc = int(rng.integers(0, 64))
            en = int(rng.random() < 0.9)
            thumb = int(rng.random() < 0.1)
            fast, slow = sp.blink_phase(fc, alert)
            out = sp.hazard_layer_model(rgb, T, t, stage, fast, slow, enable=bool(en), thumbnail=bool(thumb))
            for i in range(256):
                r, g, b = rgb[0, i]
                er, eg, eb = out[0, i]
                lines.append(f'{r:02x}{g:02x}{b:02x} {i:02x} {t:02x} {stage} {alert} {en} {thumb} {fc:02x} {er:02x}{eg:02x}{eb:02x}\n')
    with open(vec / 'sweep.txt', 'w', newline='\n') as f:
        f.writelines(lines)
    print(f'cases {len(cases)} (png {png_cases}, extra {extra_cases}), sweep {len(lines)}')


if __name__ == '__main__':
    main()
