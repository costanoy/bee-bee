"""Bee Bee — the images the site uses (site/assets/), made from the game's own.

  python tools/make_site_assets.py

Sources, all produced by other tools from the real game:
  store/screenshots/pt-BR/*.png   tools/godot/render_store_shots.gd
  store/backdrop.png              (the same tool: the title scene, no interface)
  store/feature_graphic.png       tools/make_feature_graphic.py
  art/ui/splash.png, bee_*.png    the logo and the bee icons the game draws
  build/promo/BeeBee-promo.mp4    tools/build_promo.sh, for the muted trailer
                                  that plays in the phone at the top of the page

Run it again whenever the screenshots or the video are re-rendered, then
tools/build_site.sh.
"""
import glob
import os
import shutil
import subprocess

from PIL import Image

A = "site/assets/"
os.makedirs(A, exist_ok=True)

logo = Image.open("art/ui/splash.png").convert("RGBA")
logo = logo.crop(logo.getbbox())
logo.resize((900, round(logo.height * 900 / logo.width)), Image.LANCZOS).save(A + "logo.png", optimize=True)

shots = sorted(glob.glob("store/screenshots/pt-BR/*.png"))
for old in glob.glob(A + "shot*.webp"):
    os.remove(old)
for i, path in enumerate(shots, 1):
    im = Image.open(path).convert("RGB").resize((540, 1080), Image.LANCZOS)
    im.save(A + "shot%d.webp" % i, quality=84, method=6)

for skin in ("normal", "rosy", "mint", "ice", "grape", "queen", "shining"):
    Image.open("art/ui/bee_%s.png" % skin).convert("RGBA").resize((160, 160), Image.LANCZOS) \
        .save(A + "bee_%s.png" % skin, optimize=True)

# the horizon of the title scene: mountains, trees, grass and earth
back = Image.open("store/backdrop.png").convert("RGB")
back.crop((0, int(back.height * 0.70), back.width, back.height)).save(A + "ground.webp", quality=86, method=6)

icon = Image.open("art/ui/window_icon.png").convert("RGB")
icon.resize((192, 192), Image.LANCZOS).save(A + "icon.png", optimize=True)
icon.resize((48, 48), Image.LANCZOS).save(A + "favicon.png", optimize=True)
shutil.copy("store/feature_graphic.png", A + "cover.png")
shutil.copy("fonts/Jersey10-Regular.ttf", A + "Jersey10-Regular.ttf")
shutil.copy("fonts/Jersey10-OFL.txt", A + "Jersey10-OFL.txt")

promo = "build/promo/BeeBee-promo.mp4"
if os.path.exists(promo):
    # small, silent and light: it autoplays in a 330-px-wide frame
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", promo, "-an", "-vf", "scale=540:960:flags=lanczos,fps=30",
                    "-c:v", "libx264", "-preset", "veryslow", "-crf", "27", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", A + "trailer.mp4"], check=True)
else:
    print("no", promo, "- the trailer was left as it is")

for name in sorted(os.listdir(A)):
    print("%9d  %s" % (os.path.getsize(A + name), name))
print(len(shots), "screenshots")
