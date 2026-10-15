"""M1 fixture: the FAT32 core layout with PIC1 rewritten as a 32bpp BMP.

Reuses diagnostics/fat32/generate_core_fixtures.py unchanged. PIC1 keeps the
3x91 size (row stride 12 in both depths) and the same RGB formula; its fourth
byte carries alpha = (row*7 + col*50 + 5) & 255. PIC2-4 stay 24bpp.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'diagnostics/fat32'))
import generate_core_fixtures as core  # noqa: E402

OUT = Path(sys.argv[1])
CASES = [('alpha_fragmented', {}), ('alpha_contiguous', {'contiguous': True})]
_bmp24 = core.bmp


def bmp(seed):
    if seed != 1:
        return _bmp24(seed)
    width, height, stride = 3, 91, 12
    data = _bmp24(seed)
    core.u16(data, 28, 32)
    for row in range(height):
        for col in range(width):
            start = 54 + row * stride + col * 4
            data[start:start + 4] = bytes(((seed + row) % 256, col + 17, (row * 3 + seed) % 256,
                                           (row * 7 + col * 50 + 5) % 256))
    return data


def main():
    core.bmp = bmp
    OUT.mkdir(parents=True, exist_ok=True)
    for idx, (name, cfg) in enumerate(CASES):
        media, lbas, meta, trace, expected, _ = core.generate(name, cfg)

        def write(suffix, values, width):
            (OUT / f'case{idx}_{suffix}.hex').write_text(''.join(f'{v:0{width}x}\n' for v in values), encoding='ascii')
        write('lba', lbas, 8)
        write('meta', meta, 8)
        write('bytes', (b for lba in lbas for b in media[lba]), 2)
    print(f'Generated {len(CASES)} alpha FAT32 cases in {OUT}')


if __name__ == '__main__':
    main()
