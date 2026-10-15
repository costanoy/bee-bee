# Tools for turning a generated track (Suno, ElevenLabs...) into the game's
# looping theme, audio/music_theme.wav. Run in this order, from the project:
#   python -I tools/music/analyze_track.py <track.wav> <work_dir>     tempo, bars, first seam scores
#   python -I tools/music/map_track.py <track.wav> <work_dir>         map.png: the track bar by bar
#   python -I tools/music/seams.py <track.wav> <work_dir>             seams before/after each cut
#   python -I tools/music/make_loop.py <track.wav> <work_dir>/analysis.json <start_bar> <end_bar> audio/music_theme.wav [-12.3 [60]]
# Needs numpy, Pillow and ffmpeg. Pick bars where phrases start (the map
# shows the sections); the loudness target -12.3 LUFS is the level the sound
# effects were balanced against.
"""A picture of a track bar by bar: loudness, bands, chroma and self-similarity.

    python -I map_track.py <wav> <analysis_dir>
"""
import sys, wave, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

src, an = Path(sys.argv[1]), Path(sys.argv[2])
a = json.load(open(an / "analysis.json"))
bar_t = np.array(a["bar_t"])
with wave.open(str(src)) as w:
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
mono = x.reshape(-1, ch).mean(axis=1)

N = 4096
freqs = np.fft.rfftfreq(N, 1 / sr)
pc = np.full(len(freqs), -1)
ok = (freqs > 55) & (freqs < 4200)
pc[ok] = np.round(69 + 12 * np.log2(freqs[ok] / 440.0)).astype(int) % 12
bands = [(0, 150), (150, 600), (600, 2000), (2000, 6000), (6000, 20000)]

nb = len(bar_t) - 1
chroma = np.zeros((nb, 12))
band_e = np.zeros((nb, len(bands)))
rms = np.zeros(nb)
for b in range(nb):
    s0, s1 = int(bar_t[b] * sr), int(bar_t[b + 1] * sr)
    seg = mono[s0:s1]
    rms[b] = 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9)
    acc = np.zeros(len(freqs))
    for k in range(0, len(seg) - N, N // 2):
        acc += np.abs(np.fft.rfft(seg[k:k + N] * np.hanning(N)))
    for c in range(12):
        chroma[b, c] = acc[pc == c].sum()
    chroma[b] /= chroma[b].max()
    for i, (lo, hi) in enumerate(bands):
        band_e[b, i] = acc[(freqs >= lo) & (freqs < hi)].sum()
band_db = 20 * np.log10(band_e + 1e-9)
band_db -= band_db.max(axis=0)

cw = 14                      # px per bar
W = nb * cw + 60
names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
H = 40 + 90 + 20 + len(bands) * 14 + 20 + 12 * 12 + 20 + nb * 6
img = Image.new("RGB", (W, H), (20, 20, 24))
d = ImageDraw.Draw(img)
y = 10
for b in range(0, nb + 1, 4):
    d.text((60 + b * cw - 4, y), str(b), fill=(220, 220, 220))
y = 30
# loudness bars
lo_db, hi_db = rms.min() - 1, rms.max() + 0.5
for b in range(nb):
    h = int(80 * (rms[b] - lo_db) / (hi_db - lo_db))
    d.rectangle([60 + b * cw, y + 80 - h, 60 + b * cw + cw - 2, y + 80], fill=(240, 200, 60))
d.text((2, y + 30), "rms", fill=(200, 200, 200))
y += 100
for i, (lo, hi) in enumerate(bands):
    d.text((2, y + i * 14), f"{lo}-{hi}"[:7], fill=(160, 160, 160))
    for b in range(nb):
        v = int(255 * np.clip(1 + band_db[b, i] / 12, 0, 1))
        d.rectangle([60 + b * cw, y + i * 14, 60 + b * cw + cw - 1, y + i * 14 + 12], fill=(v, v // 2, 255 - v))
y += len(bands) * 14 + 20
for c in range(12):
    d.text((2, y + (11 - c) * 12), names[c], fill=(160, 160, 160))
    for b in range(nb):
        v = int(255 * chroma[b, c] ** 2)
        d.rectangle([60 + b * cw, y + (11 - c) * 12, 60 + b * cw + cw - 1, y + (11 - c) * 12 + 11], fill=(v, v, int(v * 0.6)))
y += 12 * 12 + 20
# self-similarity of chroma+bands per bar, small
f = np.c_[chroma / np.linalg.norm(chroma, axis=1, keepdims=True), 0.05 * band_db]
f /= np.linalg.norm(f, axis=1, keepdims=True)
ssm = f @ f.T
ssm = (ssm - ssm.min()) / (ssm.max() - ssm.min())
small = Image.fromarray((ssm * 255).astype(np.uint8)).resize((nb * 6, nb * 6), Image.NEAREST).convert("RGB")
img.paste(small, (60, y))
img.save(an / "map.png")
print("wrote", an / "map.png", img.size)
key = chroma.mean(axis=0)
print("pitch-class weight:", " ".join(f"{names[i]}:{key[i]:.2f}" for i in np.argsort(-key)[:7]))
