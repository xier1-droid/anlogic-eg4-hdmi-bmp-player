"""Freeze a verified v0.17.0 M5 candidate; compare every build input by bytes.

Adapted from package_m4.py.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument('build')
p.add_argument('--candidate', default='m5-local.1')
p.add_argument('--baseline', default='v0.16.0')
p.add_argument('--m5', default='m5_text2')
p.add_argument('--m4', default='m5_m4_1')
p.add_argument('--m3', default='m5_m3v3_1')
p.add_argument('--adjust', default='m5_adjust_unit2')
p.add_argument('--prefix', default='m5r1')
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
pre, m5, m4, m3, adj = a.prefix, a.m5, a.m4, a.m3, a.adjust
logs = {f'{m5}/check_scene_text.log': 'PASS M5 scene text',
        f'{m5}/tb_m5_fsm.log': 'PASS M5 scenario_fsm',
        f'{m5}/tb_m5_keys.log': 'PASS M5 keys',
        f'{m5}/tb_m5_scroll_font.log': 'PASS M5 subtitle font',
        f'{m5}/tb_m5_osd_landslide.log': 'PASS M5 scene OSD',
        f'{m5}/tb_m5_osd_quake.log': 'PASS M5 scene OSD',
        f'{m5}/tb_m5_scene.log': 'PASS M5 scene',
        f'{m5}/tb_m5_top.log': 'PASS M5 production top',
        f'{m5}/tb_m4_top.log': 'PASS M4 production top',
        f'{m4}/tb_m4_fsm.log': 'PASS M4 scenario_fsm',
        f'{m4}/tb_m4_fade.log': 'PASS M4 fade',
        f'{m4}/tb_m4_keys.log': 'PASS M4 keys',
        f'{m4}/tb_m4_scanner_gap0.log': 'PASS M4 scanner',
        f'{m4}/tb_m4_scanner_gap2.log': 'PASS M4 scanner',
        f'{m4}/tb_audio_scan_gap0.log': 'PASS audio scan',
        f'{m4}/tb_audio_scan_gap2.log': 'PASS audio scan',
        f'{m4}/tb_m4_scene_audio.log': 'PASS M4 scene audio',
        f'{m4}/tb_m4_top.log': 'PASS M4 production top',
        f'{m3}/tb_m3v3_sweep.log': 'PASS hazard v3 sweep',
        f'{m3}/tb_m3v3_card.log': 'PASS hazard v3 cards',
        f'{m3}/tb_m3_chain.log': 'PASS M3 chain',
        f'{m3}/tb_m3_test_source.log': 'PASS hazard test source',
        f'{m3}/tb_m3_top.log': 'PASS M3 production top'}
for t in ('tb_adjust', 'tb_volume', 'tb_adjust_cdc', 'tb_adjust_keys', 'tb_adjust_osd', 'tb_adjust_decimal'):
    logs[f'{adj}/{t}.log'] = 'PASS '
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
                     (f'{pre}_system1/system.log', 'PASS transition system:'),
                     (f'{pre}_video_delay1/tb_m3_video_delay_equiv.log', 'PASS video_delay equivalence')):
    logs[name] = marker
for name, marker in logs.items():
    text = (output / name).read_text(errors='replace')
    assert marker in text, name
    if name.endswith('check_scene_text.log'):
        continue
    assert 'Errors: 0,' in text and not re.search(r'\*\* (Fatal|Error)', text), name
# Mutant runs must have failed; they are kept as detection evidence.
mutants = {f'{m5}/{n}.log' for n in ('mut_sub_row', 'mut_cell_len', 'mut_desc_addr', 'mut_scroll_step', 'mut_status_band',
                                     'mut_next_char', 'mut_warn_t', 'mut_warn_key', 'mut_speed_clamp',
                                     'mut_text_magic', 'mut_bin_limit', 'mut_warn_target', 'mut_warn_next', 'mut_font_name')}
mutants |= {f'{m4}/{n}.log' for n in ('mut_fade_step', 'mut_sample_step', 'mut_hold_restart', 'mut_t_frozen',
                                      'mut_snd_name', 'mut_scan_stop', 'mut_scene_prev', 'mut_auto_press',
                                      'mut_no_fallback')}
mutants |= {f'{m3}/{n}.log' for n in ('mut_rain_len', 'mut_noise', 'mut_dust', 'mut_shake_clamp', 'mut_sync')}
for name in mutants:
    assert '** Fatal' in (output / name).read_text(errors='replace'), f'Mutant not detected: {name}'
evidence = [f'{m3}/card_compare.log', f'{m3}/vectors.log', f'{pre}_summary.log']
assert 'DIFFERENT' not in (output / evidence[0]).read_text(errors='replace')
assert 'FAIL' not in (output / evidence[2]).read_text(errors='replace')
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
for name in list(logs) + sorted(mutants) + evidence:
    copy(output / name, Path('validation') / name)
changed = set(subprocess.check_output(['git', 'diff', a.baseline, '--name-only', '--', 'user_source', 'TD_project'],
                                      cwd=root, text=True).splitlines())
untracked = set(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', 'user_source'],
                                        cwd=root, text=True).splitlines())
saved = []
for name in inputs:
    if name.as_posix() in changed | untracked:
        copy(root / name, Path('sources') / name)
        saved.append(name)
copy(root / 'diagnostics/mountain_scene/BOARD_VALIDATION_M5.md', Path('BOARD_VALIDATION.md'))
copy(root / 'diagnostics/mountain_scene/README_M5.md', Path('README.md'))
manifest = ['# M5 candidate inputs', '', f'Baseline {a.baseline}; build {a.build}.',
            f'Bit {(phy / "demo.bit").stat().st_size} bytes; {len(inputs)} inputs compared byte-for-byte.',
            f'{len(saved)} production inputs changed or added since {a.baseline}, saved under sources/; '
            f'{len(logs)} passing simulation logs, {len(mutants)} mutant logs (expected failures).', '']
manifest += [f'- {n.as_posix()} ({(root / n).stat().st_size} bytes)' + (' [changed]' if n in saved else '') for n in inputs]
(release / 'MANIFEST.md').write_text('\n'.join(manifest) + '\n', encoding='utf-8')
print(f'Packaged {release}: {len(inputs)} inputs, {len(saved)} changed inputs, {len(logs)} logs')
