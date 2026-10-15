# Tools for turning a generated track (Suno, ElevenLabs...) into the game's
# looping theme, audio/music_theme.wav. Run in this order, from the project:
#   python -I tools/music/analyze_track.py <track.wav> <work_dir>     tempo, bars, first seam scores
#   python -I tools/music/map_track.py <track.wav> <work_dir>         map.png: the track bar by bar
#   python -I tools/music/seams.py <track.wav> <work_dir>             seams before/after each cut
#   python -I tools/music/make_loop.py <track.wav> <work_dir>/analysis.json <start_bar> <end_bar> audio/music_theme.wav [-12.3 [60]]
# Needs numpy, Pillow and ffmpeg. Pick bars where phrases start (the map
# shows the sections); the loudness target -12.3 LUFS is the level the sound
# effects were balanced against.
"""Scores loop seams precisely: for a loop from bar A to bar B, how much the
audio right after B sounds like the audio right after A (what the loop plays
instead), and right before A like right before B.

    python -I seams.py <wav> <analysis_dir>
"""
import sys, wave, json
from pathlib import Path
import numpy as np

src, an = Path(sys.argv[1]), Path(sys.argv[2])
a = json.load(open(an / "analysis.json"))
bar_t = np.array(a["bar_t"])
nb = len(bar_t) - 1
with wave.open(str(src)) as w:
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
mono = x.reshape(-1, ch).mean(axis=1)

N, H = 2048, 256
win = np.hanning(N).astype(np.float32)

def spec(s0, s1):
    k = np.arange(s0, s1 - N, H)
    fr = mono[k[:, None] + np.arange(N)[None, :]] * win
    S = np.log1p(100 * np.abs(np.fft.rfft(fr, axis=1)))
    return S / np.maximum(np.linalg.norm(S, axis=1, keepdims=True), 1e-9)

def wave_corr(sa, sb, span, search):
    """best normalised correlation of mono[sa:sa+span] against mono[sb+d:...]"""
    ref = mono[sa:sa + span]
    best, best_d = -1.0, 0
    for d in range(-search, search + 1, 4):
        seg = mono[sb + d:sb + d + span]
        c = float(ref @ seg / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-9))
        if c > best:
            best, best_d = c, d
    for d in range(best_d - 4, best_d + 5):
        seg = mono[sb + d:sb + d + span]
        c = float(ref @ seg / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-9))
        if c > best:
            best, best_d = c, d
    return best, best_d

W = int(0.75 * sr)
res = []
for A in range(2, 24):
    for length in range(16, 72, 4):
        B = A + length
        if B + 1 > nb:
            continue
        sa, sb = int(bar_t[A] * sr), int(bar_t[B] * sr)
        after = float((spec(sa, sa + W) * spec(sb, sb + W)).sum(axis=1).mean())
        before = float((spec(sa - W, sa) * spec(sb - W, sb)).sum(axis=1).mean())
        wc, d = wave_corr(sa, sb, int(0.4 * sr), int(0.02 * sr))
        res.append((min(after, before), after, before, wc, d, A, B, length))

res.sort(key=lambda r: -(r[0] + 0.05 * r[3]))
print(" score  after  before  wave  lag(ms)  bars        length")
for r in res[:25]:
    print(f" {r[0]:.4f} {r[1]:.4f} {r[2]:.4f} {r[3]:+.3f} {r[4] / sr * 1000:+6.1f}   {r[5]:2d}..{r[6]:2d}  {r[7]} bars = {r[7] * a['bar_len']:.1f} s")
for lo in (24, 32, 40, 48, 56, 64):
    sub = [r for r in res if r[7] >= lo]
    r = sub[0]
    print(f"best of {lo}+ bars: {r[5]}..{r[6]} ({r[7]} bars, {r[7] * a['bar_len']:.1f} s) score {r[0]:.4f} wave {r[3]:+.3f}")
json.dump([list(map(float, r)) for r in res[:80]], open(an / "seams.json", "w"))
