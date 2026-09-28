"""Fits the raw Blender renders into the canvases the game already expects
and writes them to art/3d/.

  python conform.py <raw_render_dir> <project_art_3d_dir>

Every original 2D asset had a canvas size and a content box that the
scripts' scale constants were measured against. Each render here is
cropped to its own content and placed into that same box (keeping its
aspect, or stretched for full-bleed strips rendered at the exact shape),
so the game uses the 3D art with no scale changes. Also writes the four
sky gradients.
"""
import os, sys, shutil
from PIL import Image

RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

# name: (canvas_w, canvas_h, (box x, y, w, h), mode)
#   fit     – keep aspect, centred in the box
#   fit_low – keep aspect, centred horizontally, sitting on the box bottom
#   fill    – stretched to the box (rendered at the box's exact shape)
TARGETS = {
    "flower_red": (768, 768, (204, 228, 348, 336), "fit"),
    "flower_yellow": (768, 768, (204, 228, 348, 336), "fit"),
    "flower_blue": (768, 768, (204, 228, 348, 336), "fit"),
    "cloud": (768, 768, (12, 264, 744, 240), "fit_low"),
    "moon": (768, 768, (160, 166, 427, 442), "fit"),
    "jupiter": (768, 768, (35, 34, 697, 700), "fit"),
    "ufo": (768, 768, (134, 280, 500, 205), "fit"),
    "logo": (1344, 768, (264, 264, 822, 254), "fit"),
    "play_button": (768, 768, (174, 224, 418, 320), "fit"),
    "button_plate": (768, 768, (84, 252, 598, 262), "fill"),
    "ground": (1568, 640, (0, 416, 1568, 81), "fill_raw"),
    "trees": (1568, 640, (0, 280, 1568, 360), "fill_raw"),
    "mountain_day": (768, 920, (0, 0, 768, 920), "fill_raw"),
    "mountain_sunset": (1024, 1024, (0, 376, 1024, 648), "fill_raw"),
}
COPY = ["bee_flap_%d" % i for i in range(8)] + ["bee_dead", "rose_bush"]

# sky gradients, top colour -> bottom colour (sRGB), at the old sizes
SKIES = {
    "bg_start": ((2016, 1152), (110, 176, 244), (255, 214, 176)),
    "bg_day": ((2016, 1152), (74, 160, 238), (176, 226, 255)),
    "bg_fade": ((1344, 768), (72, 70, 150), (252, 150, 120)),
    "bg_night": ((2016, 1152), (14, 18, 54), (44, 44, 110)),
}


def content(im):
    box = im.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox()
    return im.crop(box)


def conform(name, cw, ch, box, mode):
    im = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    bx, by, bw, bh = box
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    if mode == "fill_raw":                   # already rendered at the exact shape; keep full frame
        canvas.alpha_composite(im.resize((bw, bh), Image.LANCZOS), (bx, by))
    elif mode == "fill":
        canvas.alpha_composite(content(im).resize((bw, bh), Image.LANCZOS), (bx, by))
    else:
        c = content(im)
        k = min(bw / c.width, bh / c.height)
        w, h = max(1, round(c.width * k)), max(1, round(c.height * k))
        c = c.resize((w, h), Image.LANCZOS)
        x = bx + (bw - w) // 2
        y = by + (bh - h) // 2 if mode == "fit" else by + bh - h
        canvas.alpha_composite(c, (x, y))
    canvas.save(os.path.join(OUT, name + ".png"))


def gull_frames():
    """Crop all four frames to their shared bounding box so the body stays
    put from frame to frame. Returns the crop height (the game's scale ref)."""
    frames = [Image.open(os.path.join(RAW, "seagull_%d.png" % i)).convert("RGBA") for i in range(4)]
    boxes = [f.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox() for f in frames]
    union = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    for i, f in enumerate(frames):
        f.crop(union).save(os.path.join(OUT, "seagull_%d.png" % i))
    return union[3] - union[1]


def sky(name, size, top, bottom):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        t = t * t * (3 - 2 * t)             # smoothstep: a softer horizon glow
        col.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    col.resize((w, h), Image.NEAREST).save(os.path.join(OUT, name + ".png"))


for name, (cw, ch, box, mode) in TARGETS.items():
    conform(name, cw, ch, box, mode)
for name in COPY:
    shutil.copy(os.path.join(RAW, name + ".png"), os.path.join(OUT, name + ".png"))
for name, (size, top, bottom) in SKIES.items():
    sky(name, size, top, bottom)
print("seagull frame height:", gull_frames())
print("conformed ->", OUT)
