"""Bee Bee — the adaptive launcher icon's foreground (art/icon_fg.png).

  python tools/make_adaptive_icon.py

Android shows only the middle two thirds of an adaptive icon's layers (72 of
108 dp) and then cuts that to the launcher's shape. The foreground used to
be the icon picture at full size, so every launcher cropped the bee's
antennae and wings. Here the picture (art/icon_bg.png, the full square
artwork) is scaled to exactly the part that shows, and the margin around it,
which only peeks out during launcher animations, is filled by continuing the
picture: the sky straight up, the rose bushes mirrored at the sides and
below.
"""
import numpy as np
from PIL import Image

N = 2000
art = Image.open("art/icon_bg.png").convert("RGB")
inner = round(N * 72 / 108)
pad = (N - inner) // 2
rest = N - inner - pad
a = np.asarray(art.resize((inner, inner), Image.LANCZOS))
a = np.pad(a, ((0, rest), (0, 0), (0, 0)), mode="reflect")
a = np.pad(a, ((pad, 0), (0, 0), (0, 0)), mode="edge")
a = np.pad(a, ((0, 0), (pad, rest), (0, 0)), mode="reflect")
Image.fromarray(a).save("art/icon_fg.png", optimize=True)
print("wrote art/icon_fg.png", a.shape[:2])
