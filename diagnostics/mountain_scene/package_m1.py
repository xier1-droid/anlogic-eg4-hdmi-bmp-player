"""Freeze a verified v0.17.0 M1 candidate; compare every build input by bytes.

Adapted from diagnostics/lut_opt/package.py.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument('build')
p.add_argument('--candidate', default='m1-local.1')
p.add_argument('--baseline', default='v0.16.0')
p.add_argument('--alpha', default='m1_alpha1')
p.add_argument('--prefix', default='m1r')
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
output = root / 'diagnostics/output'
build = output / a.build
phy = build / 'TD_project/demo_Runs/phy_1'
release = root / 'releases/v0.17.0' / a.candidate
timing = (phy / 'final_timing.rpt').read_text(errors='replace')
for field in ('SWNS', 'HWNS'):
    value = re.search(field + r':\s*([-\d.]+)ns', timing)
    assert value and float(value[1]) >= 0, f'Timing failed: {field}'
inputs = [Path('TD_project/demo.al')]
inputs += [(root / 'TD_project' / n).resolve().relative_to(root)
           for n in re.findall(r'<File Path="([^"]+)"', (root / inputs[0]).read_text(encoding='utf-8'))]
for name in inputs:
    assert (root / name).read_bytes() == (build / name).read_bytes(), f'Changed build input: {name}'

# Final-source runs for this candidate: marker each log must contain.
pre = a.prefix
logs = {}
for f in (output / a.alpha).glob('*.log'):
    if f.name.startswith(('tb_m1_alpha_stream', 'reader_case')) and '.console.' not in f.name:
        logs[f.relative_to(output).as_posix()] = 'PASS alpha stream suite' if f.name.startswith('tb_') else 'PASS M1 reader alpha'
for run in (f'{pre}_regression1', f'{pre}_scaler1'):
    for f in (output / run).glob('tb_*.log'):
        if '.console.' not in f.name:
            logs[f.relative_to(output).as_posix()] = 'PASS '
for run in (f'{pre}_reader0', f'{pre}_reader2', f'{pre}_reader_scale', f'{pre}_reader_modes'):
    for f in (output / run).glob('reader*_gap*_mode*.log'):
        logs[f.relative_to(output).as_posix()] = 'PASS FAT32 reader'
for name, marker in ((f'{pre}_paths1/paths.log', 'PASS frame paths'),
                     (f'{pre}_loader1/sim.log', 'PASS dual loader'),
                     (f'{pre}_memory1/sim.log', 'PASS thumbnail physical memory'),
                     (f'{pre}_production1/tb_pcm_production.log', 'PASS '),
                     (f'{pre}_production1/tb_pcm_preview_rescan.log', 'PASS '),
                     (f'{pre}_top1/top.log', 'PASS production top'),
                     (f'{pre}_preview1/system.log', 'PASS preview system:'),
                     (f'{pre}_system1/system.log', 'PASS transition system:')):
    logs[name] = marker
for name, marker in logs.items():
    text = (output / name).read_text(errors='replace')
    assert marker in text and 'Errors: 0,' in text and not re.search(r'\*\* (Fatal|Error)', text), name
assert (build / 'timing_audit/check_timing.txt').exists(), 'Missing timing audit'
assert not release.exists(), 'Never overwrite an existing candidate'
release.mkdir(parents=True)


def copy(src, name):
    dst = release / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    assert src.read_bytes() == dst.read_bytes()


copy(phy / 'demo.bit', Path('demo.bit'))
for name in ('final_timing.rpt', 'demo_phy.area'):
    copy(phy / name, Path('reports') / name)
for run in ('syn_1', 'phy_1'):
    run_dir = build / 'TD_project/demo_Runs' / run
    copy(run_dir / f'build_{a.build}.log', Path('reports') / f'{run}_build.log')
    copy(run_dir / 'settings.cfg', Path('reports') / f'{run}_settings.cfg')
for name in ('check_timing.txt', 'audit.timing'):
    copy(build / 'timing_audit' / name, Path('reports') / name)
for name in logs:
    copy(output / name, Path('validation') / name)
changed = set(subprocess.check_output(['git', 'diff', a.baseline, '--name-only', '--', 'user_source', 'TD_project'],
                                      cwd=root, text=True).splitlines())
saved = []
for name in inputs:
    if name.as_posix() in changed:
        copy(root / name, Path('sources') / name)
        saved.append(name)
copy(root / 'diagnostics/mountain_scene/BOARD_VALIDATION_M1.md', Path('BOARD_VALIDATION.md'))
manifest = ['# M1 candidate inputs', '', f'Baseline {a.baseline}; build {a.build}.',
            f'Bit {(phy / "demo.bit").stat().st_size} bytes; {len(inputs)} inputs compared byte-for-byte.',
            f'{len(saved)} changed production inputs saved under sources/; {len(logs)} passing simulation logs.', '']
manifest += [f'- {n.as_posix()} ({(root / n).stat().st_size} bytes)' + (' [changed]' if n in saved else '') for n in inputs]
(release / 'MANIFEST.md').write_text('\n'.join(manifest) + '\n', encoding='utf-8')
print(f'Packaged {release}: {len(inputs)} inputs, {len(saved)} changed inputs, {len(logs)} logs')
