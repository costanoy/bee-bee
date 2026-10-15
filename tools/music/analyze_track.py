# Tools for turning a generated track (Suno, ElevenLabs...) into the game's
# looping theme, audio/music_theme.wav. Run in this order, from the project:
#   python -I tools/music/analyze_track.py <track.wav> <work_dir>     tempo, bars, first seam scores
#   python -I tools/music/map_track.py <track.wav> <work_dir>         map.png: the track bar by bar
#   python -I tools/music/seams.py <track.wav> <work_dir>             seams before/after each cut
#   python -I tools/music/make_loop.py <track.wav> <work_dir>/analysis.json <start_bar> <end_bar> audio/music_theme.wav [-12.3 [60]]
# Needs numpy, Pillow and ffmpeg. Pick bars where phrases start (the map
# shows the sections); the loudness target -12.3 LUFS is the level the sound
# effects were balanced against.
"""Tempo, bars, structure and loop candidates of a music track (numpy only).

    python -I analyze_track.py <wav> <out_dir>
"""
import sys, wave, json
from pathlib import Path
import numpy as np
from PIL import Image

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

with wave.open(str(src)) as w:
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
x = x.reshape(-1, ch)
mono = x.mean(axis=1)
print(f"{n} samples, {sr} Hz, {ch} ch, {n / sr:.2f} s")

# ---------------------------------------------------------------- STFT
N, H = 2048, 512
win = np.hanning(N).astype(np.float32)
frames = 1 + (len(mono) - N) // H
idx = np.arange(N)[None, :] + H * np.arange(frames)[:, None]
S = np.abs(np.fft.rfft(mono[idx] * win, axis=1)).astype(np.float32)   # frames x bins
fps = sr / H
freqs = np.fft.rfftfreq(N, 1 / sr)
logS = np.log1p(100 * S)

# onset strength: positive spectral flux
flux = np.maximum(0, np.diff(logS, axis=0)).sum(axis=1)
flux = np.concatenate([[0], flux])
flux -= np.convolve(flux, np.ones(17) / 17, mode="same")       # remove slow trend
flux = np.maximum(flux, 0)

# ---------------------------------------------------------------- tempo
def comb_score(period, phase):
    pos = phase + period * np.arange(int((frames - phase) / period))
    i = np.floor(pos).astype(int)
    f = pos - i
    ok = i + 1 < frames
    return float(((1 - f[ok]) * flux[i[ok]] + f[ok] * flux[i[ok] + 1]).mean())

best = (0, 0, 0)
for bpm in np.arange(120, 200, 0.02):
    period = fps * 60 / bpm
    for phase in np.arange(0, period, 0.5):
        s = comb_score(period, phase)
        if s > best[0]:
            best = (s, bpm, phase)
score, bpm, phase = best
# prefer the double tempo if it scores almost as well (eighth-note pulses)
print(f"tempo {bpm:.2f} BPM (score {score:.3f}); half {bpm / 2:.2f}, double {bpm * 2:.2f}")
period = fps * 60 / bpm
beat_t = (phase + period * np.arange(int((frames - phase) / period))) / fps   # seconds
print(f"first beat at {beat_t[0]:.3f} s, {len(beat_t)} beats")

# ---------------------------------------------------------------- chroma per frame
pc = np.full(len(freqs), -1)
valid = (freqs > 55) & (freqs < 4200)
midi = 69 + 12 * np.log2(np.maximum(freqs, 1) / 440.0)
pc[valid] = np.round(midi[valid]).astype(int) % 12
chroma = np.zeros((frames, 12), np.float32)
for k in range(12):
    chroma[:, k] = S[:, pc == k].sum(axis=1)
chroma /= np.maximum(chroma.sum(axis=1, keepdims=True), 1e-9)

low = S[:, freqs < 150].sum(axis=1)
mid = S[:, (freqs >= 150) & (freqs < 2000)].sum(axis=1)
high = S[:, freqs >= 2000].sum(axis=1)
rms = np.sqrt(np.mean(mono[idx] ** 2, axis=1))

# ---------------------------------------------------------------- downbeat: which beat of four starts the bars
def seg(t0, t1):
    return int(t0 * fps), max(int(t0 * fps) + 1, int(t1 * fps))

beat_chroma = np.array([chroma[slice(*seg(beat_t[i], beat_t[i + 1]))].mean(axis=0) for i in range(len(beat_t) - 1)])
beat_low = np.array([low[slice(*seg(beat_t[i], beat_t[i] + 0.06))].mean() for i in range(len(beat_t) - 1)])
nov = np.r_[0, np.linalg.norm(np.diff(beat_chroma, axis=0), axis=1)]
cand = []
for off in range(4):
    sel = np.arange(off, len(nov), 4)
    cand.append((nov[sel].mean() + 0.5 * beat_low[sel].mean() / beat_low.mean() * nov.mean(), off))
cand.sort(reverse=True)
off = cand[0][1]
print("downbeat offset scores:", [(round(s, 4), o) for s, o in sorted(cand, key=lambda c: c[1])], "-> beat", off)
bar_t = beat_t[off::4]
nbars = len(bar_t) - 1
bar_len = 4 * 60 / bpm
print(f"{nbars} full bars of {bar_len:.4f} s, first at {bar_t[0]:.3f} s")

# per-bar features
feat, info = [], []
for b in range(nbars):
    s0, s1 = seg(bar_t[b], bar_t[b + 1])
    c = chroma[s0:s1].mean(axis=0)
    e = np.log1p(np.array([low[s0:s1].mean(), mid[s0:s1].mean(), high[s0:s1].mean()]))
    feat.append(np.r_[c / np.linalg.norm(c), 0.15 * e])
    info.append((b, bar_t[b], 20 * np.log10(rms[s0:s1].mean() + 1e-9)))
feat = np.array(feat)
featn = feat / np.linalg.norm(feat, axis=1, keepdims=True)
ssm = featn @ featn.T
img = ((ssm - ssm.min()) / (ssm.max() - ssm.min()) * 255).astype(np.uint8)
Image.fromarray(img).resize((nbars * 8, nbars * 8), Image.NEAREST).save(out / "ssm.png")

print("bar  time   rms(dB)  sim-to-prev")
for b, t, db in info:
    sp = ssm[b, b - 1] if b else 0
    print(f"{b:3d} {t:6.2f} {db:7.1f}  {sp:.3f}")

# ---------------------------------------------------------------- loop candidates
# The seam B -> A sounds like the track itself if the audio around A matches
# the audio around B: compare log-spectra frame by frame over a bar before
# and a bar after each point.
L = logS / np.maximum(np.linalg.norm(logS, axis=1, keepdims=True), 1e-9)
def around(t):
    s0, s1 = int((t - bar_len) * fps), int((t + bar_len) * fps)
    return s0, s1

res = []
for a in range(1, nbars):
    for length in (8, 16, 24, 32, 40, 48, 56, 64):
        b = a + length
        if b + 1 > nbars:
            continue
        (a0, a1), (b0, b1) = around(bar_t[a]), around(bar_t[b])
        m = min(a1 - a0, b1 - b0)
        sim = float((L[a0:a0 + m] * L[b0:b0 + m]).sum(axis=1).mean())
        res.append((sim, a, b, length))
res.sort(reverse=True)
print("best seams overall (similarity, start bar, end bar, bars):")
for r in res[:15]:
    print(f"  {r[0]:.4f}  bars {r[1]}..{r[2]}  ({r[3]} bars, {r[3] * bar_len:.1f} s)")
for length in (16, 24, 32, 40, 48, 56, 64):
    sub = [r for r in res if r[3] == length]
    if sub:
        r = sub[0]
        print(f"best {length:2d}-bar loop: {r[0]:.4f} bars {r[1]}..{r[2]}  {bar_t[r[1]]:.3f}s..{bar_t[r[2]]:.3f}s")
json.dump({"sr": sr, "bpm": bpm, "bar_t": [float(t) for t in bar_t], "bar_len": bar_len,
           "candidates": [list(r) for r in res[:60]]}, open(out / "analysis.json", "w"))
