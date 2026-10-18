#!/usr/bin/env python3
"""Convert an input audio file to the board's fixed 48 kHz mono PCM format."""
from pathlib import Path
import argparse, subprocess

def convert(src, dst, force=False):
    """ffmpeg src -> dst as raw s16le, 48 kHz, mono; returns the byte size."""
    src, dst = Path(src), Path(dst)
    if src.resolve() == dst.resolve(): raise ValueError('input and output must differ')
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd=['ffmpeg','-y' if force else '-n','-v','error','-i',str(src),'-f','s16le','-acodec','pcm_s16le','-ac','1','-ar','48000',str(dst)]
    subprocess.run(cmd,check=True)
    return dst.stat().st_size

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('input'); ap.add_argument('output')
    ap.add_argument('--force', action='store_true', help='replace an existing output file')
    a=ap.parse_args(); src=Path(a.input); dst=Path(a.output)
    if src.resolve() == dst.resolve(): ap.error('input and output must differ')
    size=convert(src,dst,a.force)
    print(f'{dst}: {size} bytes, {size//2} samples, {size/2/48000:.3f} seconds')
if __name__=='__main__': main()
