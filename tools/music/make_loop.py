# Tools for turning a generated track (Suno, ElevenLabs...) into the game's
# looping theme, audio/music_theme.wav. Run in this order, from the project:
#   python -I tools/music/analyze_track.py <track.wav> <work_dir>     tempo, bars, first seam scores
#   python -I tools/music/map_track.py <track.wav> <work_dir>         map.png: the track bar by bar
#   python -I tools/music/seams.py <track.wav> <work_dir>             seams before/after each cut
#   python -I tools/music/make_loop.py <track.wav> <work_dir>/analysis.json <start_bar> <end_bar> audio/music_theme.wav [-12.3 [60]]
# Needs numpy, Pillow and ffmpeg. Pick bars where phrases start (the map
# shows the sections); the loudness target -12.3 LUFS is the level the sound
# effects were balanced against.
"""Cuts a seamless loop out of a track, between two bar starts.

    python -I make_loop.py <src.wav> <analysis.json> <start_bar> <end_bar> <out.wav> [target_lufs] [fade_ms]

The track is brought to the target loudness and peak-limited whole (so the
limiter has no seam of its own), the end point is aligned to the start by
cross-correlation, and the loop's last fade_ms are cross-faded into the
audio that precedes the start bar, so playback wraps from exactly what came
before the start into the start itself.
"""
import sys, json, wave, subprocess, re
from pathlib import Path
import numpy as np

src, an_path, a_bar, b_bar, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), Path(sys.argv[5])
target = float(sys.argv[6]) if len(sys.argv) > 6 else -12.3
fade_ms = float(sys.argv[7]) if len(sys.argv) > 7 else 60.0
an = json.load(open(an_path))
bar_t = an["bar_t"]

with wave.open(src) as w:
    sr, ch = w.getframerate(), w.getnchannels()

def loudness(path, ss=None, to=None):
    cmd = ["ffmpeg", "-hide_banner", "-nostats"]
    if ss is not None:
        cmd += ["-ss", f"{ss:.6f}", "-to", f"{to:.6f}"]
    cmd += ["-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"]
    txt = subprocess.run(cmd, capture_output=True, text=True).stderr
    i = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", txt)[-1])
    p = float(re.findall(r"Peak:\s+(-?[\d.]+) dBFS", txt)[-1])
    return i, p

t_a, t_b = bar_t[a_bar], bar_t[b_bar]
i_loop, _ = loudness(src, t_a, t_b)
gain = target - i_loop
print(f"loop region {t_a:.3f}-{t_b:.3f} s: {i_loop:.1f} LUFS -> gain {gain:+.2f} dB")

raw = out.with_suffix(".f32")
subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", src, "-af",
                f"volume={gain:.3f}dB,alimiter=limit=0.891:attack=5:release=60:level=disabled",
                "-f", "f32le", "-acodec", "pcm_f32le", str(raw)], check=True)
x = np.fromfile(raw, dtype=np.float32).reshape(-1, ch)
raw.unlink()
mono = x.mean(axis=1)

A = int(round(t_a * sr))
B = int(round(t_b * sr))
# align: where after B does the music line up with what follows A
span, search = int(0.4 * sr), int(0.025 * sr)
ref = mono[A:A + span]
best, lag = -2.0, 0
for d in range(-search, search + 1):
    seg = mono[B + d:B + d + span]
    c = float(ref @ seg / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-12))
    if c > best:
        best, lag = c, d
B += lag
print(f"end aligned by {lag / sr * 1000:+.2f} ms (correlation {best:+.3f}); loop {B - A} samples = {(B - A) / sr:.4f} s")

F = int(fade_ms / 1000 * sr)
loop = x[A:B].copy()
t = np.linspace(0.0, 1.0, F, endpoint=False)[:, None]
fade_in = np.sin(t * np.pi / 2)
fade_out = np.cos(t * np.pi / 2)
loop[-F:] = x[B - F:B] * fade_out + x[A - F:A] * fade_in

# 16-bit with TPDF dither
rng = np.random.default_rng(1)
d = (rng.random(loop.shape) - rng.random(loop.shape)) / 32768.0
pcm = np.clip(np.round((loop + d) * 32767.0), -32768, 32767).astype(np.int16)
with wave.open(str(out), "wb") as w:
    w.setnchannels(ch)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(pcm.tobytes())
i, p = loudness(out)
print(f"wrote {out}: {len(pcm) / sr:.3f} s, {i:.1f} LUFS, peak {p:.1f} dBFS")
# the wrap: last sample -> first sample, against typical sample-to-sample steps
step = np.abs(pcm[0].astype(int) - pcm[-1].astype(int)).max()
typical = np.percentile(np.abs(np.diff(pcm.astype(int), axis=0)).max(axis=1), 99)
print(f"wrap step {step} (99th percentile of steps in the loop: {typical:.0f})")
