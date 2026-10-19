#!/usr/bin/env python3
"""Stage audio for scene packs (M4): SND1-4.PCM, 48 kHz mono s16le.

Each stage in scene.yaml may give
  sound: file          any ffmpeg-readable file, used as the base track
  narration:           lines spoken at a time on the 0-239 t scale
    - {t: 0, text: ...}
    - {t: 65, text: ..., file: voice/line.wav}
A line starts at sample t*1600: on the board t advances once per 1600 played
samples at 1x, so the words line up with the picture's time t. A line that
would overlap the previous one is pushed back (reported). The track lasts at
least until t=239 plus 0.5 s. Narration uses the Windows SAPI voice for
zh-CN through PowerShell; without it (or with tts=False) each line becomes a
short beep at its start, which keeps the timing testable. A line with `file:`
(any ffmpeg-readable recording, relative to scene.yaml, e.g. from another TTS
service) uses that recording instead of SAPI, also with --no-tts; its `text`
stays the subtitle. Speech and recordings are trimmed to 20 ms around the
voice and normalised alike, so the first word starts at the line's t.
A stage with neither gets no SND file: the FPGA plays BGM.PCM for it.
"""
from pathlib import Path
import subprocess, sys, tempfile, wave
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I drops the script directory
from make_audio_corpus import convert  # noqa: E402

SAMPLE_HZ = 48000
SAMPLES_PER_T = 1600
T_END = 240

_SAPI = r'''
$text=[IO.File]::ReadAllText($args[0],[Text.Encoding]::UTF8)
Add-Type -AssemblyName System.Speech
$s=New-Object System.Speech.Synthesis.SpeechSynthesizer
$v=$s.GetInstalledVoices()|Where-Object{$_.VoiceInfo.Culture.Name -eq 'zh-CN'}|Select-Object -First 1
if(!$v){exit 3}
$s.SelectVoice($v.VoiceInfo.Name)
$s.Rate=2
$f=New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$s.SetOutputToWaveFile($args[1],$f);$s.Speak($text);$s.Dispose()
'''


def read_wav48(path):
    with wave.open(str(path), 'rb') as w:
        if w.getframerate() != SAMPLE_HZ or w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise SystemExit(f'{path}: expected 48 kHz mono 16-bit')
        return np.frombuffer(w.readframes(w.getnframes()), '<i2').copy()


def write_wav48(path, pcm):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SAMPLE_HZ)
        w.writeframes(pcm.astype('<i2').tobytes())


def speak(text, work):
    """SAPI zh-CN speech as int16 samples, or None when unavailable."""
    script = work / 'sapi.ps1'
    script.write_text(_SAPI, encoding='utf-8-sig')
    src, wav = work / 'line.txt', work / 'line.wav'
    src.write_text(text, encoding='utf-8')
    if wav.exists():
        wav.unlink()
    try:
        r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script), str(src), str(wav)],
                           capture_output=True)
    except OSError:
        return None
    if r.returncode or not wav.exists():
        return None
    return shape(read_wav48(wav).astype(np.int32))


def recorded(path, work):
    """A narration recording (any ffmpeg-readable file) as int16 samples."""
    if not path.is_file():
        raise SystemExit(f'narration file not found: {path}')
    raw = work / 'line.pcm'
    convert(path, raw, force=True)
    return shape(np.fromfile(raw, '<i2').astype(np.int32))


def shape(pcm):
    # Speech engines pad each line with silence; keep 20 ms around the voice
    # so the first word starts at the line's t.
    loud = np.flatnonzero(np.abs(pcm) > 300)
    if loud.size:
        pad = SAMPLE_HZ // 50
        pcm = pcm[max(0, loud[0] - pad):loud[-1] + pad]
    peak = int(np.abs(pcm).max()) if pcm.size else 0
    if peak:   # normalise to about -1 dBFS
        pcm = pcm * 29000 // peak
    return pcm


def beep(n=int(0.15 * SAMPLE_HZ), hz=880):
    k = np.arange(n)
    env = np.minimum(1, np.minimum(k, n - k) / 240)
    return (np.sin(2 * np.pi * hz * k / SAMPLE_HZ) * env * 12000).astype(np.int32)


def stage_track(n, stage, base_dir, work, tts):
    """Samples for stage n (0..3), or None. Returns (pcm, notes)."""
    sound, lines = stage.get('sound'), stage.get('narration') or []
    if not sound and not lines:
        return None, []
    notes = []
    base = np.zeros(0, np.int32)
    if sound:
        raw = work / f'sound{n + 1}.pcm'
        convert(base_dir / sound, raw, force=True)
        base = np.fromfile(raw, '<i2').astype(np.int32)
    placed, end = [], 0
    for line in sorted(lines, key=lambda d: d['t']):
        t = int(line['t'])
        if not 0 <= t < T_END:
            raise SystemExit(f'stage {n + 1}: narration t={t} outside 0..239')
        if line.get('file'):
            pcm = recorded(base_dir / line['file'], work)
            notes.append(f't={t} {Path(line["file"]).name}')
        else:
            pcm = speak(line['text'], work) if tts else None
        if pcm is None:

            pcm = beep()
            notes.append(f't={t} beep')
        start = max(t * SAMPLES_PER_T, end)
        if start != t * SAMPLES_PER_T:
            notes.append(f't={t} pushed to t={start / SAMPLES_PER_T:.0f} after the previous line')
        placed.append((start, pcm))
        end = start + len(pcm)
    length = max(T_END * SAMPLES_PER_T + SAMPLE_HZ // 2, len(base), end)
    mix = np.zeros(length, np.int32)
    mix[:len(base)] += base
    for start, pcm in placed:
        mix[start:start + len(pcm)] += pcm
    return np.clip(mix, -32768, 32767).astype('<i2'), notes


def write_stage_audio(cfg, base_dir, out, tts=True):
    """Write out/sd/SNDn.PCM and out/audio/SNDn.wav for the stages that have audio."""
    (out / 'audio').mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for n, stage in enumerate(cfg['stages']):
            pcm_path = out / 'sd' / f'SND{n + 1}.PCM'
            pcm, notes = stage_track(n, stage, base_dir, work, tts)
            if pcm is None:
                if pcm_path.exists():
                    pcm_path.unlink()
                print(f'stage {n + 1}: no audio, the board plays BGM.PCM')
                continue
            pcm_path.write_bytes(pcm.tobytes())
            write_wav48(out / 'audio' / f'SND{n + 1}.wav', pcm)
            extra = f' ({"; ".join(notes)})' if notes else ''
            print(f'{pcm_path}: {pcm_path.stat().st_size} bytes, {len(pcm) / SAMPLE_HZ:.2f} s{extra}')
