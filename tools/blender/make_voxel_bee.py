"""Bee Bee — the bee as voxel art.

  blender --background --factory-startup --python make_voxel_bee.py -- <models_dir> <preview_dir> [skin] [export_only]

Builds the bee cube by cube on the world's own grid (voxel_kit.py VOX =
0.04), at the size it has in the game, so the game draws it unscaled and
its cubes are the same size as everything else's. A chubby storybook bee
(STYLE.md, "Storybook shapes, pop contrast"): a big round head about as big
as the abdomen, a fluffy butter collar between them, two ink stripes, and a
face made for the side the camera sees — a big glossy eye with a 2x2 white
catchlight, a rosy cheek and a smile.

Its side view hugs the collision circle (bee.gd BEE_R 12.8 px = 8 cubes):
the head's top and the collar reach +8 cubes, the belly and the collar -8;
head, tail, wings and antennae overhang to the sides, which is forgiving.

Colour is painted, never jittered (STYLE.md "shading recipe"): flat bands
from a top light per volume (head, collar, abdomen), a vertical gradient, a
crisp lit rim along the top silhouette, an ink rim along the bottom, and AO
only in the creases. Eyes sit under "LiveEyes", and an X-eyed variant under
"DeadEyes": the two fill the same hole in the head, so they never overlap
or z-fight. Wings are two lobes fanned apart on one translucent sheet (a
fore wing swept back toward the tail, a small hind wing low over the
abdomen, a white rim round their outline only) under "WingPivotL/R" hinges,
which rotate about X (the game rests them at 0.25 rad and flaps them up to
1.8).

`skin` picks the colours and the accessory (SKINS below; default "normal")
and the file: bee_voxel.glb for the normal bee, bee_voxel_<skin>.glb for the
others. "export_only" skips the review renders; "ascii" prints the side
the camera sees as text, one character per cube (for tuning the face).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

V = vk.VOX
# Cube (x, y, z) spans x-0.5..x+0.5 and y-0.5..y+0.5 (so the bee is mirror
# symmetric about y = 0, as the game shows both sides) and z..z+1, so rows
# -8..7 span exactly the collision circle's -8..+8 cubes. Shapes are tested
# at the cube centres, (x, y, z + 0.5).
O = (0.5, 0.5, 0.0)

# ---------------------------------------------------------------- palette (sRGB)
# The normal bee: STYLE.md's "Bee" table, judged in the game mock under the
# new light (view3d.gd's planned key light, colour ambient, no sky
# reflections). The ink is a touch more violet than STYLE's so the stripes
# show as the UI's plum UI_INK (0.24, 0.13, 0.32) under that light.
YELLOW = (1.00, 0.68, 0.09)        # the body (honey)
STRIPE = (0.20, 0.07, 0.25)        # stripes, antennae, sting, the X eyes, the ink rim
FLUFF = (1.00, 0.76, 0.25)         # the collar: butter, not cream (cream read as a gap, at night too)
PINK = (1.00, 0.42, 0.50)          # the cheek
EYE = (0.07, 0.05, 0.09)
GLINT = (0.40, 0.28, 0.45)         # the glossy plum low in the eye
WHITE = (1.0, 1.0, 1.0)
MOUTH = (0.49, 0.08, 0.17)
# the wing's middle stays thin enough for the sky to show through by day,
# dusk and night, even where the far wing shows through the near one
WING = (0.90, 0.93, 1.0, 0.22)
WING_RIM = (1.0, 1.0, 1.0, 0.95)
WING_SHINE = (1.0, 1.0, 1.0, 0.50)
# the honey's own tones (STYLE.md: warm lights, orange shadows)
TONES = {"RIM": (1.00, 0.92, 0.45), "LIGHT": (1.00, 0.80, 0.23), "SHADE": (0.98, 0.56, 0.08),
         "DEEP": (0.94, 0.44, 0.08)}

# The skins a player can unlock (main.gd BEE_SKINS): the same bee, cube for
# cube, in other colours, each with one small accessory of its own, so the
# unlocks differ in shape too (the bee menu shows locked ones as dark
# silhouettes). Each entry overrides the palette above; the tones are then
# made from the new colours (skin_tones).
SKINS = {
    "normal": {},
    "rosy": {"YELLOW": (1.0, 0.56, 0.72), "STRIPE": (0.56, 0.10, 0.34), "FLUFF": (1.0, 0.80, 0.88),
             "PINK": (1.0, 0.30, 0.46)},                                   # + a bow
    "mint": {"YELLOW": (0.47, 0.88, 0.58), "STRIPE": (0.08, 0.30, 0.24), "FLUFF": (0.80, 0.98, 0.76)},  # + a leaf
    "ice": {"YELLOW": (0.60, 0.85, 1.0), "STRIPE": (0.12, 0.20, 0.50), "FLUFF": (0.90, 0.97, 1.0)},    # + an ice crystal
    "grape": {"YELLOW": (0.69, 0.48, 0.97), "STRIPE": (0.22, 0.09, 0.40), "FLUFF": (0.88, 0.80, 1.0)},  # + grape knobs
    "queen": {"STRIPE": (0.36, 0.12, 0.52), "FLUFF": (1.0, 0.93, 0.78)},  # + the crown
    "shining": {},                                                         # + sparkles (see below)
}
SKIN = ARGS[2] if len(ARGS) > 2 and ARGS[2] in SKINS else "normal"
CUSTOM = "YELLOW" in SKINS[SKIN]
globals().update(SKINS[SKIN])

# "shining" is the skin unlocked at score 300: all silver chrome. Chrome only
# reads as chrome if it mirrors something, so the mirror is painted on, band
# by band from how each volume's surface faces: a white sky on top, a dark
# horizon line round the middle with a bright streak under it, and a paler
# ground underneath. Stripes and antennae are near-black, the wings cool
# glass, and little stars float around it under a "Sparkles" node (the game
# blinks each one on its own beat). The game draws it unshaded, so the
# painted mirror stays crisp and it shines just as bright at night;
# unshaded, the game shows the stored colour as linear light, so glow()
# darkens the palette to make it come out on screen as written here (the
# previews draw it the same way, see glass_preview).
SHINING = SKIN == "shining"
EXPORT_ONLY = "export_only" in ARGS
OUT_NAME = "bee_voxel" if SKIN == "normal" else "bee_voxel_" + SKIN


def glow(c):
    return tuple(v ** 2.2 for v in c[:3]) + tuple(c[3:])


# chrome, from the top of a volume to its underside: (lowest normal z, colour);
# the head's horizon sits lower, under the eyes, so it doesn't run through them
CHROME = [(0.72, (1.0, 1.0, 1.0)), (0.42, (0.82, 0.86, 0.92)), (0.16, (0.66, 0.70, 0.78)),
          (-0.02, (0.50, 0.54, 0.63)), (-0.16, (0.26, 0.29, 0.38)), (-0.30, (0.96, 0.98, 1.0)),
          (-0.55, (0.48, 0.51, 0.58)), (-2.0, (0.70, 0.72, 0.78))]
CHROME_HEAD = [(0.72, (1.0, 1.0, 1.0)), (0.42, (0.82, 0.86, 0.92)), (0.10, (0.68, 0.72, 0.80)),
               (-0.36, (0.56, 0.60, 0.68)), (-0.50, (0.26, 0.29, 0.38)), (-0.62, (0.96, 0.98, 1.0)),
               (-0.80, (0.48, 0.51, 0.58)), (-2.0, (0.70, 0.72, 0.78))]
SPARKLE = (1.0, 1.0, 1.0)
SPARKLE_CORE = (0.86, 0.93, 1.0)
if SHINING:
    STRIPE = (0.08, 0.09, 0.13)
    FLUFF = (0.92, 0.95, 1.0)
    PINK = (0.94, 0.70, 0.80)
    EYE = (0.04, 0.04, 0.07)
    GLINT = (0.30, 0.32, 0.42)
    MOUTH = (0.10, 0.10, 0.15)
    WING = (0.84, 0.91, 1.0, 0.32)


def skin_tones():
    """The tones painted from each colour: light and highlight are warmer
    and paler, shadows cooler and richer (vk.shade). The normal bee keeps
    STYLE.md's hand-picked honey tones."""
    t = dict(TONES) if not CUSTOM else {"RIM": vk.shade(YELLOW, 0.30), "LIGHT": vk.shade(YELLOW, 0.14),
                                         "SHADE": vk.shade(YELLOW, -0.12), "DEEP": vk.shade(YELLOW, -0.24)}
    t.update({"BASE": YELLOW, "INK": STRIPE, "SHEEN": vk.shade(STRIPE, 0.55), "INK_DEEP": vk.shade(STRIPE, -0.40),
              "KNOB": vk.shade(STRIPE, 1.0), "COLLAR": FLUFF, "C_LIGHT": vk.shade(FLUFF, 0.12),
              "C_SHADE": vk.shade(FLUFF, -0.12), "CHEEK": PINK, "CHEEK_LIGHT": vk.shade(PINK, 0.25)})
    return t


T = skin_tones()

# ---------------------------------------------------------------- shape
HEAD_C, HEAD_R = (4.5, 0.0, 1.0), (7.4, 6.3, 7.0)       # head top at +8
ABD_C, ABD_R = (-5.5, 0.0, -1.0), (7.6, 6.6, 7.0)       # belly at -8
COLLAR_X, COLLAR_R = -1.0, 7.9                          # the fuzz ring at the waist reaches +-8
STRIPES = ((-7, -5), (-13, -11))                        # x ranges of the abdomen painted in ink
PIVOT = (-1, 3, 7)      # the wing hinges: L at -Y, R at +Y, on top of the collar


def ell(p, c, r):
    """How far inside an ellipsoid the centre of cube p is (<= 1: inside)."""
    q = (p[0], p[1], p[2] + 0.5)
    return sum(((q[i] - c[i]) / r[i]) ** 2 for i in range(3))


def normal(p, c, r):
    q = (p[0], p[1], p[2] + 0.5)
    n = [(q[i] - c[i]) / (r[i] * r[i]) for i in range(3)]
    l = math.sqrt(sum(v * v for v in n)) or 1.0
    return tuple(v / l for v in n)


def bee_cells():
    """{cube: (part, unit normal of its volume)}. +X is the front, +Z up,
    -Y faces the camera."""
    cells = {}
    for x in range(-14, 13):
        for y in range(-8, 9):
            for z in range(-9, 10):
                p = (x, y, z)
                zc = z + 0.5
                # the collar: a disc round the waist whose rim breaks into
                # tufts (staggered from one slice to the next, so it reads
                # as fur), thinner toward its two faces
                phi = math.atan2(abs(y), zc)
                dx = x - COLLAR_X
                tuft = 0.45 * math.cos(6 * phi + 1.3 * dx)
                collar = abs(dx) <= 1 and math.hypot(y, zc) <= COLLAR_R - 0.45 * abs(dx) + tuft
                if ell(p, HEAD_C, HEAD_R) <= 1.0:
                    cells[p] = ("head", normal(p, HEAD_C, HEAD_R))
                elif collar:
                    rr = math.hypot(y, zc) or 1.0
                    cells[p] = ("collar", (0.25 * dx, y / rr, zc / rr))
                elif ell(p, ABD_C, ABD_R) <= 1.0:
                    dark = any(a <= x <= b for a, b in STRIPES)
                    cells[p] = ("stripe" if dark else "abd", normal(p, ABD_C, ABD_R))
    return cells


BANDS = {   # the painted top light: (lowest normal z, tone), flat bands that merge
    "head": [(0.55, "LIGHT"), (-0.30, "BASE"), (-0.62, "SHADE"), (-2, "DEEP")],
    "abd": [(0.55, "LIGHT"), (-0.30, "BASE"), (-0.62, "SHADE"), (-2, "DEEP")],
    "stripe": [(0.55, "SHEEN"), (-0.50, "INK"), (-2, "INK_DEEP")],
    "collar": [(0.45, "C_LIGHT"), (-0.40, "COLLAR"), (-2, "C_SHADE")],
}


def paint(cells):
    """Tones, gradient and rims (STYLE.md recipe steps 2-5) -> {cube: sRGB}."""
    vox = {}
    for p, (part, n) in cells.items():
        if SHINING and part in ("head", "abd"):
            vox[p] = next(c for lo, c in (CHROME_HEAD if part == "head" else CHROME) if n[2] >= lo)
            continue
        vox[p] = T[next(t for lo, t in BANDS[part] if n[2] >= lo)]
    if not SHINING:
        vox = vk.gradient(vox, top=0.06, bottom=-0.14, z0=-8, z1=8, steps=4)
    # a crisp lit rim along the top (pop: not ink, which showed as dashes
    # inside the head from the camera's 7 degrees above), an ink one along
    # the bottom
    part = lambda p, c: cells[p][0]
    lit = WHITE if SHINING else T["RIM"]
    vox = vk.rim(vox, "top", colour=lit, only=lambda p, c: part(p, c) != "stripe")
    vox = vk.rim(vox, "top", colour=T["SHEEN"], only=lambda p, c: part(p, c) == "stripe")
    vox = vk.rim(vox, "bottom", colour=STRIPE, amount=0.55)
    return vox


# ---------------------------------------------------------------- face
# Drawn as pixel art in the side view (columns: x from the back of the head
# to the front; rows: z from the top down) and pressed onto both sides of
# the head. E eye, W catchlight (upper front), w glint (lower back), G the
# eye's glossy plum, C cheek, c light cheek, M mouth.
FACE_X0, FACE_Z0 = 2, 5            # x of the first column, z of the first row
FACE = ["...EEEE..",
        "..EEEWWE.",
        "..EEEWWE.",
        "..EEEEEE.",
        "..EwEEEE.",
        "..EEGGGE.",
        "...EEGE..",
        ".cCC.M..M",
        ".CCC..MM."]
FACE_COL = {"E": EYE, "W": WHITE, "w": WHITE, "G": GLINT, "C": T["CHEEK"], "c": T["CHEEK_LIGHT"], "M": MOUTH}
EYE_AT = (FACE_X0 + 5, FACE_Z0 - 3)      # the eye's centre, where the dead bee's X crosses


def exposed(shape, p):
    x, y, z = p
    return any(n not in shape for n in ((x + 1, y, z), (x - 1, y, z), (x, y + 1, z), (x, y - 1, z),
                                        (x, y, z + 1), (x, y, z - 1)))


def pressed(shape, x, z, side, depth=2):
    """The cubes the face covers at (x, z) on one side (-1: -Y, +1: +Y): the
    outermost one, plus those right behind it that the curve of the head
    leaves showing (up to `depth` deeper)."""
    ys = [y for y in range(-9, 10) if (x, y, z) in shape and y * side > 0]
    if not ys:
        return []
    y0 = max(ys, key=lambda y: y * side)
    out = [(x, y0, z)]
    y = y0 - side
    while (x, y, z) in shape and exposed(shape, (x, y, z)) and abs(y - y0) <= depth:
        out.append((x, y, z))
        y -= side
    return out


def face(vox, cells):
    """Press the face onto both sides. Cheeks and mouth are painted on the
    head; the eye cubes are taken out of it and returned as (live, dead):
    two colourings of the same cubes (glossy eyes / skin with an X)."""
    live, dead = {}, {}
    head = {p for p, (part, n) in cells.items() if part == "head"}
    for side in (-1, 1):
        for r, row in enumerate(FACE):
            for c, ch in enumerate(row):
                if ch == ".":
                    continue
                x, z = FACE_X0 + c, FACE_Z0 - r
                for i, p in enumerate(pressed(head, x, z, side)):
                    if ch in "EWwG":
                        # only the outermost cube carries a catchlight; the
                        # ones behind it are the eye's dark rim
                        live[p] = FACE_COL[ch] if i == 0 or ch in "EG" else EYE
                        dx, dz = x - EYE_AT[0], z - EYE_AT[1]
                        on_x = abs(dx) == abs(dz) and abs(dx) <= 2
                        dead[p] = STRIPE if on_x else vox[p]
                    else:
                        vox[p] = FACE_COL[ch]
    for p in live:
        del vox[p]
    return live, dead


# ---------------------------------------------------------------- accents
def walk(points, colour):
    """A face-connected path of cubes through the given points (cubes that
    only touch at an edge read as separate floating bits)."""
    out = {}
    x, y, z = points[0]
    out[(x, y, z)] = colour
    for tx, ty, tz in points[1:]:
        while (x, y, z) != (tx, ty, tz):
            if x != tx:
                x += 1 if tx > x else -1
            elif z != tz:
                z += 1 if tz > z else -1
            else:
                y += 1 if ty > y else -1
            out[(x, y, z)] = colour
    return out, (x, y, z)


def ball3(x, y, z, side, colour, light, deep):
    """A 3x3x3 ball (a cube with its corners cut) from (x, y, z) upward,
    forward and outward (toward `side`), lit on its upper front cube."""
    out = {}
    for a in range(3):
        for b in range(3):
            for c in range(3):
                if a != 1 and b != 1 and c != 1:
                    continue
                out[(x + a, y + side * b, z + c)] = light if (a, b, c) == (2, 0, 2) or (a, b, c) == (1, 0, 2)                     else (deep if c == 0 else colour)
    return out


def knob(tip, side):
    """A 2x2x2 knob whose upper front cube catches the light."""
    x, y, z = tip
    return {(x + a, y + b, z + c): T["KNOB"] if (a, b, c) == (1, 0, 1) else STRIPE
            for a in (1, 2) for b in (0, side) for c in (0, 1)}


def ice_tip(tip, side):
    """Ice: each antenna ends in an ice crystal, a diamond standing on its
    point, cut in facets (lit upper left, deep lower right) with a white
    glint on top."""
    HI, ICE, DEEP = (0.96, 1.0, 1.0), (0.70, 0.90, 1.0), (0.40, 0.60, 0.98)
    x, y, z = tip
    out = {}
    for k, half in enumerate((0, 1, 2, 1, 0)):
        for a in range(-half, half + 1):
            up, left = k >= 2, a <= 0
            c = HI if (up and left) else (DEEP if not (up or left) else ICE)
            for b in (0, side):
                out[(x + 1 + a, y + b, z + k)] = c
    out[(x + 1, y, z + 4)] = WHITE
    out[(x, y, z + 3)] = WHITE
    return out


def grape_tip(tip, side):
    """Grape: each antenna ends in a bunch of three round grapes (two on
    top, one under) with a little green leaf, instead of a knob. Each grape
    has its own shade, so the three read apart."""
    LEAF = (0.32, 0.66, 0.18)
    x, y, z = tip
    out = {}
    for (gx, gz), (g, hi, deep) in (((1, 0), ((0.50, 0.20, 0.74), (0.82, 0.62, 1.0), (0.34, 0.10, 0.54))),
                                    ((4, 0), ((0.36, 0.12, 0.58), (0.66, 0.44, 0.92), (0.24, 0.06, 0.42))),
                                    ((2, -3), ((0.58, 0.28, 0.82), (0.86, 0.68, 1.0), (0.38, 0.12, 0.58)))):
        out.update(ball3(x + gx, y, z + gz, side, g, hi, deep))
    out[(x + 3, y, z + 3)] = LEAF
    out[(x + 2, y, z + 3)] = LEAF
    out[(x + 2, y, z + 4)] = LEAF
    return out


def antennae():
    """Two short antennae from the forehead, rising and curling forward,
    each ending in the skin's knob."""
    vox = {}
    for side in (-1, 1):
        stalk, tip = walk([(9, 2 * side, 6), (9, 2 * side, 10), (10, 2 * side, 10), (10, 2 * side, 11)], STRIPE)
        vox.update(stalk)
        vox.update({"ice": ice_tip, "grape": grape_tip}.get(SKIN, knob)(tip, side))
    return vox


def sting():
    return {(-14, 0, -2): STRIPE, (-15, 0, -2): STRIPE, (-14, 0, -1): STRIPE}


def head_top(shape, x):
    """The z of the highest cube of the head's middle slice at x."""
    zs = [p[2] for p in shape if p[0] == x and p[1] == 0]
    return max(zs) if zs else 0


# The accessories on top of the head sit forward, just behind the
# antennae: from the camera they stand out against the sky, and in the bee
# menu's three-quarter view they clear the wings, so they still show in a
# locked bee's dark silhouette.
TOP_X = 4


def bow(shape):
    """Rosy: a bow on top of the head, two loops and a knot (seen from the
    side, a bow tie), tilted a little forward like a hair bow."""
    out = {}
    cx, z0 = TOP_X, head_top(shape, TOP_X) + 1
    BASE, LIGHT, DEEP = (0.93, 0.20, 0.44), (1.0, 0.52, 0.68), (0.62, 0.08, 0.30)
    for dx in range(-4, 5):
        for dz in range(-2, 3):
            if dx == 0:
                if abs(dz) > 1:
                    continue
                c = DEEP
            elif abs(dz) <= abs(dx) * 0.55 + 0.5:
                c = LIGHT if dz == 2 or (dz == 1 and abs(dx) <= 2) else (DEEP if dz == -2 else BASE)
            else:
                continue
            for y in (-1, 0, 1):
                out[(cx + dx, y, z0 + 1 + dz + (1 if dx >= 3 else 0))] = c
    return out


def leaf(shape):
    """Mint: a sprout on top of the head, a short stem and two leaves in a
    V (a big one forward, a small one back), with a light vein."""
    out = {}
    cx, z0 = TOP_X, head_top(shape, TOP_X) + 1
    STEM, LEAF, LIGHT, DEEP = (0.24, 0.50, 0.14), (0.30, 0.66, 0.16), (0.56, 0.86, 0.26), (0.16, 0.42, 0.12)
    for z in range(z0, z0 + 3):
        out[(cx, 0, z)] = STEM
    # each leaf: a pointed oval along an axis from the top of the stem
    for (ax, az), length, width in (((0.75, 0.66), 6.5, 1.9), ((-0.8, 0.6), 4.5, 1.4)):
        for dx in range(-8, 9):
            for dz in range(0, 8):
                s = dx * ax + dz * az
                t = -dx * az + dz * ax
                if not 0.3 <= s <= length:
                    continue
                w = width * math.sin(math.pi * s / length) + 0.35
                if abs(t) <= w:
                    p = (cx + dx, 0, z0 + 2 + dz)
                    out[p] = LIGHT if abs(t) < 0.5 and s < length - 1 else (LEAF if t > -0.4 else DEEP)
    for p in list(out):
        if p[2] > z0 + 2 and out[p] == LEAF and (p[0], 0, p[2] + 1) not in out:
            out[p] = LIGHT          # lit top edge
    return out


def crown(shape):
    """Queen: a gold crown on top of the head, a red band round its foot,
    points all the way round and a gem in front."""
    out = {}
    GOLD, GOLD_HI, GOLD_DEEP = (1.0, 0.84, 0.20), (1.0, 0.95, 0.55), (0.86, 0.56, 0.08)
    BAND, GEM = (0.80, 0.14, 0.22), (0.30, 0.85, 0.95)
    cx, cy = TOP_X, 0
    z0 = head_top(shape, cx)
    for x in range(cx - 3, cx + 4):
        for y in range(cy - 3, cy + 4):
            d = math.hypot(x - cx, y - cy)
            if not 1.6 < d <= 3.3:
                continue
            top = z0 + (5 if (x + y) % 2 == 0 else 3)
            for z in range(z0 - 1, top + 1):
                if (x, y, z) in shape:
                    continue
                out[(x, y, z)] = BAND if z <= z0 + 1 else (GOLD_HI if z == top else (GOLD_DEEP if x < cx - 1 else GOLD))
    out[(cx + 3, 0, z0 + 1)] = GEM
    return out


def ermine(vox, cells):
    """Queen: her white collar is ermine, three ink spots on each side."""
    collar = {p for p, (part, n) in cells.items() if part == "collar"}
    for side in (-1, 1):
        for x, z in ((-1, 4), (-2, 0), (-1, -4)):
            for p in pressed(collar, x, z, side, depth=0):
                vox[p] = STRIPE


def sparkle(size):
    """A little star: a core with an arm out along each axis in the XZ plane."""
    vox = {(0, 0, 0): glow(SPARKLE_CORE)}
    for d in range(1, size + 1):
        for p in ((d, 0, 0), (-d, 0, 0), (0, 0, d), (0, 0, -d)):
            vox[p] = SPARKLE
    return vox


# ---------------------------------------------------------------- wings
def lobe(root, axis, length, width):
    """An egg-shaped wing lobe in the XZ plane: thin at the root, widest past
    the middle, round at the tip. {(x, z): (s along, t across, half width)}.
    It may dip a little below the hinge (z < 0): at rest those cubes lean in
    over the abdomen, which stays clear of them."""
    ux, uz = axis
    l = math.hypot(ux, uz)
    ux, uz = ux / l, uz / l
    sc = 0.64 * length
    out = {}
    for x in range(-20, 8):
        for z in range(-3, 18):
            dx, dz = x - root[0], z - root[1]
            s = dx * ux + dz * uz
            t = -dx * uz + dz * ux
            if not 0 <= s <= length:
                continue
            k = (s - sc) / (sc if s < sc else length - sc)
            w = width * math.sqrt(max(0.0, 1 - k * k)) * (0.55 + 0.45 * min(1.0, s / sc)) + (0.5 if s > 1.5 else 0.0)
            if abs(t) <= w:
                out[(x, z)] = (s, t, w)
    return out


def wing():
    """popview's lesson: two clearly separate lobes fanned apart like a V,
    so the pair reads as wings rather than one glass egg. The fore wing is
    swept 45 degrees back, its tip well behind the hinge (the game camera,
    above and to the side, shows it at about 35); the hind wing, about 30%
    smaller, starts a little further back and runs back just under the
    hinge's level, low over the abdomen. (Upright, the two stacked into one
    white column on the collar.) Only the pair's outline carries the white
    rim, so the sky shows through the middle; a short shine streak runs
    along the fore wing's leading edge."""
    fore = lobe((0, 0), (-0.71, 0.71), 13.0, 1.8)
    hind = lobe((-3, 0), (-1.0, -0.15), 6.0, 1.25)
    both = set(fore) | set(hind)
    vox = {}
    for (x, z) in both:
        rim = any((x + dx, z + dz) not in both for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        vox[(x, 0, z)] = WING_RIM if rim else WING
    for (x, z), (s, t, w) in fore.items():         # leading edge = the side toward +x / up
        if 4.0 <= s <= 7.5 and -w + 1.0 <= t <= -w + 2.0 and vox[(x, 0, z)] is WING:
            vox[(x, 0, z)] = WING_SHINE
    return vox


# ---------------------------------------------------------------- build
vk.reset()
solid = vk.material("Voxel", rough=0.62)
glass = vk.material("VoxelWing", alpha=0.6, rough=0.35)
root = vk.empty("Bee")

cells = bee_cells()
shape = set(cells)
body = paint(cells)
live, dead = face(body, cells)
if SHINING:
    body = {p: glow(c) for p, c in body.items()}
ant = antennae()
body.update(ant)
body.update(sting())
body.update({"rosy": bow, "mint": leaf, "queen": crown}.get(SKIN, lambda s: {})(shape))
if SKIN == "queen":
    ermine(body, cells)
if SHINING:
    for p in set(ant) | set(sting()):
        body[p] = glow(body[p] if body[p] != T["KNOB"] else (0.46, 0.50, 0.60))
    live = {p: glow(c) for p, c in live.items()}
    dead = {p: glow(c) for p, c in dead.items()}

# The eye cubes are out of the body, but its AO sees them; the body keeps the
# faces round the hole, so a hairline between the meshes shows the head, not
# the sky behind it.
vk.build("Body", body, solid, root, origin=O, occluders=set(live), ao=vk.AO())
eyes = vk.empty("LiveEyes", parent=root)
vk.build("Eyes", live, solid, eyes, origin=O, solid=body)
dead_node = vk.empty("DeadEyes", parent=root)
vk.build("XEyes", dead, solid, dead_node, origin=O, solid=body)

wvox = wing()
if SHINING:
    wvox = {p: glow(c) for p, c in wvox.items()}
# Each wing is one sheet: the cubes' -Y faces only (the material is
# double-sided, so it shows from both sides). As 1-cube slabs, the two faces
# of each wing and of the far one behind it stacked into a milky white, and
# the rim's stepped edges showed as white bars.
SHEET = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1))   # every face but -Y is skipped
for side, tag in ((-1, "L"), (1, "R")):
    piv = vk.empty("WingPivot" + tag, (PIVOT[0] * V, side * PIVOT[1] * V, PIVOT[2] * V), root)
    vk.build("Wing", wvox, glass, piv, origin=O, faces=None, skip=SHEET)

if SHINING:
    sparkles = vk.empty("Sparkles", parent=root)
    twinkle = vk.material("VoxelSparkle")
    p = twinkle.node_tree.nodes["Principled BSDF"]
    p.inputs["Emission Color"].default_value = (0.90, 0.95, 1.0, 1)
    p.inputs["Emission Strength"].default_value = 1.5
    for i, (at, size) in enumerate((((-13, -8, 9), 2), ((5, -9, -9), 1), ((14, -8, 9), 1), ((1, 8, 14), 2),
                                    ((-16, 8, -5), 1), ((11, 8, -7), 1))):
        vk.build("Sparkle%d" % i, sparkle(size), twinkle, sparkles, origin=(0.5, 0.5, 0.5), faces=None,
                 loc=tuple(c * V for c in at))

vk.report("bee %s" % SKIN, root, budget=5000)
xs = [p[0] for p in shape]
print("SIDE VIEW: body x %d..%d, z %d..%d (circle +-8); at x = 0: z %d..%d" % (
    min(xs), max(xs) + 1, min(p[2] for p in shape), max(p[2] for p in shape) + 1,
    min(p[2] for p in shape if p[0] == 0), max(p[2] for p in shape if p[0] == 0) + 1))
if "ascii" in ARGS:
    seen = {**body, **live}
    names = {EYE: "E", WHITE: "W", GLINT: "G", T["CHEEK"]: "C", T["CHEEK_LIGHT"]: "c", MOUTH: "M"}
    for z in range(15, -10, -1):
        row = ""
        for x in range(-16, 16):
            ys = [y for y in range(-12, 1) if (x, y, z) in seen]
            p = (x, min(ys), z) if ys else None
            row += "." if p is None else names.get(seen[p], "#" if p in shape else "+")
        print("%4d %s" % (z, row))
vk.export(os.path.join(MODELS, OUT_NAME + ".glb"))

if EXPORT_ONLY:
    print("DONE voxel bee (export only)")
    sys.exit(0)

# ---------------------------------------------------------------- preview renders
s = bpy.context.scene


def glass_preview():
    """The silver bee is drawn unshaded in the game: show it that way here
    too (the stored colour, brought back from glow(), as light)."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        p = nt.nodes["Principled BSDF"]
        a = next(n for n in nt.nodes if n.type == "VERTEX_COLOR")
        g = nt.nodes.new("ShaderNodeGamma")
        g.inputs["Gamma"].default_value = 1 / 2.2
        nt.links.new(a.outputs["Color"], g.inputs["Color"])
        nt.links.new(g.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = 1.0
        p.inputs["Base Color"].default_value = (0, 0, 0, 1)
        p.inputs["Specular IOR Level"].default_value = 0.0


def wings(a):
    for side, tag in ((-1, "L"), (1, "R")):
        bpy.data.objects["WingPivot" + tag].rotation_euler = (math.radians(a) * side * -1, 0, 0)


def show(node, on):
    node.hide_render = not on
    for c in node.children:
        c.hide_render = not on


if SHINING:
    glass_preview()
tgt = (-0.02, 0, 0.06)
for mode in ("studio", "flat"):
    pv = vk.Preview(game_like=(mode == "flat"))
    if mode == "studio":
        for attr, val in (("use_gtao", True), ("gtao_distance", 0.4), ("use_shadows", True), ("use_raytracing", True)):
            if hasattr(s.eevee, attr):
                setattr(s.eevee, attr, val)
    suf = "" if mode == "studio" else "_flat"
    shoot = lambda name, d, sc=1.55, res=900, t=tgt: pv.shoot(os.path.join(PREVIEW, name + suf + ".png"), d, t, sc,
                                                             res, res, dist=12)
    show(dead_node, False)
    show(eyes, True)
    root.rotation_euler = (0, 0, 0)
    wings(14)                       # 0.25 rad, the game's rest pose
    shoot("hero_3q", (0.75, -1.0, 0.45))
    shoot("game_side", (0.0, -1.0, 0.123))            # the game camera: 7 degrees above
    if mode == "studio":
        shoot("front", (1.0, -0.35, 0.2))
        shoot("back_side", (0.0, 1.0, 0.123))         # the other side, shown when it flies left
        shoot("face_close", (0.12, -1.0, 0.12), 0.75, 700, (0.22, 0, 0.1))
        # render_bee_icons.gd's view (3/4 front, from above) at the menu's size
        shoot("icon", (0.9, -3.0, 0.55), 1.36, 256, (0.01, 0, 0.08))
        for i, a in enumerate((14, 60, 103, 60)):
            wings(a)
            shoot("flap_%d" % i, (0.45, -1.0, 0.3), res=500)
        wings(14)
        for i in range(8):
            ang = 2 * math.pi * i / 8
            shoot("turn_%d" % i, (math.cos(ang), math.sin(ang), 0.35), res=420)
        show(eyes, False)
        show(dead_node, True)
        wings(92)                   # 1.6 rad, as the game holds them on death
        root.rotation_euler = (math.radians(180), 0, 0)
        shoot("dead", (0.0, -1.0, 0.123), t=(-0.02, 0, -0.06), res=600)
        root.rotation_euler = (0, 0, 0)
    for o in list(s.objects):       # this studio's lights and camera go before the next one's
        if o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o)
print("DONE voxel bee")
