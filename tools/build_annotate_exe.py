#!/usr/bin/env python3
"""Build tools/annotate_scene.exe (one file, no console) with PyInstaller.

Usage: py -I tools/build_annotate_exe.py
Needs: py -m pip install pyinstaller (plus pillow numpy pyyaml). The exe is a
build product, not tracked (.gitignore); rebuild it after changing
annotate_scene.py, make_scene_pack.py or hazard_v3.py. Build files go to a
temporary directory, so only the exe is left in tools/.
"""
from pathlib import Path
import sys, tempfile
import PyInstaller.__main__

tools = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as tmp:
    PyInstaller.__main__.run([
        str(tools / 'annotate_scene.py'),
        '--name', 'annotate_scene', '--onefile', '--windowed', '--noconfirm', '--clean',
        '--paths', str(tools),                       # make_scene_pack, hazard_v3
        '--distpath', str(tools), '--workpath', tmp, '--specpath', tmp,
        *[a for m in ('matplotlib', 'scipy', 'pandas', 'IPython', 'pytest') for a in ('--exclude-module', m)],
    ])
print(f'{tools / "annotate_scene.exe"}', file=sys.stderr)
