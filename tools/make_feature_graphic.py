"""Bee Bee — the Google Play feature graphic (1024x500).

  python tools/make_feature_graphic.py

Built from pieces the game itself rendered: the title-screen backdrop
without UI (store/backdrop.png, from tools/godot/render_store_shots.gd), the
voxel logo (art/ui/splash.png) and three of the bees (art/ui/bee_*.png).
Writes store/feature_graphic.png.
"""
from PIL import Image

W, H = 1024, 500

back = Image.open("store/backdrop.png").convert("RGBA")
# the bottom of the title screen: grass, trees, mountains and a band of sky
# (LIFT px up from the very bottom, to leave out most of the earth)
strip_h = round(back.width * H / W)
LIFT = 150
canvas = back.crop((0, back.height - strip_h - LIFT, back.width, back.height - LIFT)).resize((W, H), Image.LANCZOS)

logo = Image.open("art/ui/splash.png").convert("RGBA")
logo = logo.crop(logo.getbbox())
logo_w = 620
logo = logo.resize((logo_w, round(logo.height * logo_w / logo.width)), Image.LANCZOS)
canvas.alpha_composite(logo, ((W - logo_w) // 2, 28))

# a bee either side of the title, flying in towards it
for name, size, x, y, flip in (("queen", 150, 40, 110, False), ("shining", 150, W - 40 - 150, 110, True),
                               ("rosy", 104, 170, 270, False), ("ice", 104, W - 170 - 104, 270, True)):
    bee = Image.open("art/ui/bee_%s.png" % name).convert("RGBA").resize((size, size), Image.LANCZOS)
    if flip:
        bee = bee.transpose(Image.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(bee, (x, y))

canvas.convert("RGB").save("store/feature_graphic.png")
print("wrote store/feature_graphic.png", canvas.size)
