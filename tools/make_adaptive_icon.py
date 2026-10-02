"""Bee Bee — an adaptive launcher icon that shows the whole picture.

  python tools/make_adaptive_icon.py            writes store/icon_option.png (a preview)
  python tools/make_adaptive_icon.py --apply    overwrites art/icon_fg.png

NOT APPLIED. The icon was asked to be left as it is, and it is: this only
exists so the alternative can be seen and chosen. store/icon_option.png shows
the icon as launchers draw it today next to how they would draw this one.

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
import sys
from PIL import ImageDraw

if "--apply" in sys.argv:
    Image.fromarray(a).save("art/icon_fg.png", optimize=True)
    print("wrote art/icon_fg.png", a.shape[:2])
    sys.exit(0)


def as_launcher(layer, shape):
    """What a launcher shows of a layer: its middle two thirds, cut to shape."""
    side = layer.width
    v = round(side * 72 / 108)
    o = (side - v) // 2
    vis = layer.crop((o, o, o + v, o + v)).resize((300, 300), Image.LANCZOS)
    mask = Image.new("L", (300, 300), 0)
    d = ImageDraw.Draw(mask)
    if shape == "circle":
        d.ellipse((0, 0, 299, 299), fill=255)
    else:
        d.rounded_rectangle((0, 0, 299, 299), radius=80, fill=255)
    out = Image.new("RGB", (300, 300), (40, 40, 40))
    out.paste(vis, (0, 0), mask)
    return out


now = Image.open("art/icon_fg.png").convert("RGB")
option = Image.fromarray(a)
sheet = Image.new("RGB", (4 * 300 + 3 * 20 + 60, 300), (40, 40, 40))
x = 0
for layer in (now, option):
    for shape in ("circle", "squircle"):
        sheet.paste(as_launcher(layer, shape), (x, 0))
        x += 320
    x += 60
sheet.save("store/icon_option.png")
print("wrote store/icon_option.png: the two on the left are the icon today, the two on the right this option")
