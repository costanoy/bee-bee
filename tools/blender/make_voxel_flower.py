"""Bee Bee — the collectible flower as voxel art: one shape, three colours.

  blender --background --factory-startup --python make_voxel_flower.py -- <models_dir> <preview_dir>

A soft sticker (STYLE.md, "Flowers"): five puffy petals, each a low dome
painted with its own light from the upper left and snapped to three flat
bands, a deeper seam where two petals meet, a lit edge along the top of
the bloom and a deeper one along its bottom; a big bright centre (a round
button in three steps) with a white catchlight; two pointed leaves peeking
out below; and a warm-white sticker border all round, one cube behind the
petals, so the baked AO lays a soft shadow on it, with a plum ink line
along its lower edge (the UI's ink, the same as the bee's stripes and the
hedge's underside: the sticker sits on the sky like the UI's lettering).
Built at its in-game size on the shared voxel grid (25 cubes across = 1.0
unit), so it's used unscaled; the origin is the bloom's centre, the
collision centre. The back is never seen (the game only sways it
+-0.2 rad), so back faces are left out. Only the petal and centre colours
change between red, yellow and blue.
Exports flower_voxel_<colour>.glb and review renders.
"""
import bpy, math, sys, os
from mathutils import Vector
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

# A true red (no orange in its lights), a lemon yellow and a deep
# periwinkle blue, well away from the day sky's hue (~206) on one side and
# from violet on the other. Authored as they show: the game's light keeps a
# front face close to its vertex colour. The tip is the lit top edge.
PETALS = {
    #        seam               deep               base               light              tip
    "red": ((0.50, 0.03, 0.11), (0.72, 0.05, 0.12), (0.97, 0.13, 0.15), (1.00, 0.29, 0.27), (1.00, 0.50, 0.45)),
    "yellow": ((0.86, 0.52, 0.06), (0.98, 0.70, 0.07), (1.00, 0.87, 0.12), (1.00, 0.95, 0.38), (1.00, 0.99, 0.66)),
    "blue": ((0.13, 0.10, 0.52), (0.20, 0.19, 0.76), (0.32, 0.33, 0.97), (0.50, 0.52, 1.00), (0.70, 0.71, 1.00)),
}
# the centres: golden buttons on the red and the blue; cocoa on the yellow
# (an orange or golden one made the whole flower read orange at phone size)
GOLD = ((0.96, 0.52, 0.07), (1.00, 0.76, 0.16), (1.00, 0.90, 0.45))
CENTRES = {
    #        ring               body               light
    "red": GOLD,
    "yellow": ((0.34, 0.15, 0.10), (0.50, 0.24, 0.11), (0.68, 0.38, 0.16)),
    "blue": GOLD,
}
# what each flower's pickup burst should use (flower.gd KINDS): the petal
# base, since the burst cubes are lit by the same light as the petals
BURSTS = {name: p[2] for name, p in PETALS.items()}
PAPER = (1.00, 0.93, 0.74)          # sticker border, warm white
PAPER_SHADE = (0.96, 0.82, 0.62)    # ... its lower half
INK = (0.22, 0.08, 0.19)            # shows on screen as main.gd UI_INK
INK_AMOUNT = 0.85
CATCH = (1.0, 1.0, 1.0)
#        under              upper              top edge
LEAF = ((0.17, 0.48, 0.15), (0.29, 0.63, 0.17), (0.51, 0.80, 0.23))
LEAF_BASE, LEAF_TIP, LEAF_W = (4.6, -6.2), (11.4, -13.2), 2.3     # the right leaf (cubes); the left is its mirror

N, PD, PR = 5, 6.1, 5.4             # petals, petal centre distance, petal radius (cubes)
DISC_R = 4.5                        # the centre button
DOME = 2.3                          # petal dome height (cubes)
# a gentle dome per petal and only a little darkening toward the heart: a
# steep one made the five petals read as lumpy berries at phone size
PETAL_K = 0.8
HEART = 0.12
SLOPE = 0.16                        # the painted top-to-bottom light, top to bottom of the bloom
LIGHT = vk.PAINT_LIGHT
FRONT = vk.lit((0, -1, 0))          # a face straight at the camera: the petal base
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def petal_centres():
    return [(PD * math.cos(math.pi / 2 + 2 * math.pi * k / N), PD * math.sin(math.pi / 2 + 2 * math.pi * k / N))
            for k in range(N)]


def tidy(cols, keep=(), passes=2):
    """A 2D colour map {(x, z): colour} with its lone cells taken back into
    their surroundings: a cell with fewer than two neighbours of its own
    colour takes its neighbours' most common colour, so the bands come out
    as clean patches (no single-cube specks at phone size). keep: colours
    left alone (seams, accents)."""
    for _ in range(passes):
        out = dict(cols)
        for q, c in cols.items():
            if c in keep:
                continue
            nb = [cols[(q[0] + a, q[1] + b)] for a, b in N4 if (q[0] + a, q[1] + b) in cols]
            if sum(1 for n in nb if n == c) >= 2:
                continue
            nb = [n for n in nb if n not in keep] or nb
            if nb:
                out[q] = max(sorted(set(nb)), key=nb.count)
        cols = out
    return cols


def flower(name):
    seam, deep, base, light, tip = PETALS[name]
    ring, body, shine = CENTRES[name]
    vox = {}
    cents = petal_centres()
    span = int(PD + PR) + 2
    owner = {}
    for x in range(-span, span + 1):
        for z in range(-span, span + 1):
            best, bd = None, 1e9
            for k, (px, pz) in enumerate(cents):
                d = math.hypot(x - px, z - pz)
                if d <= PR and d < bd:
                    best, bd = k, d
            if best is not None:
                owner[(x, z)] = best
    petals = set(owner)
    # petals: low domes lit from the upper left, a touch darker toward the
    # heart and toward the bottom of the bloom, snapped to three flat bands
    height, cols = {}, {}
    for (x, z), k in owner.items():
        px, pz = cents[k]
        dx, dz = x - px, z - pz
        height[(x, z)] = int(round(DOME * max(0.0, 1.0 - (dx * dx + dz * dz) / (PR * PR))))
        n = Vector((2 * DOME * dx / (PR * PR) * PETAL_K, -1.0, 2 * DOME * dz / (PR * PR) * PETAL_K)).normalized()
        r = math.hypot(x, z)
        t = (vk.lit(n, LIGHT) - FRONT) - HEART * max(0.0, min(1.0, (6.2 - r) / 3.0)) + SLOPE * z / (PD + PR)
        cols[(x, z)] = deep if t < -0.17 else (light if t > 0.12 else base)
    cols = tidy(cols)
    # where two petals meet: a seam, so each petal reads on its own
    for (x, z), k in owner.items():
        if any(owner.get((x + a, z + b), k) != k for a, b in N4):
            cols[(x, z)] = seam if z < 1 else deep
    for (x, z), c in cols.items():
        for y in range(-height[(x, z)], 1):
            vox[(x, y, z)] = c
    # the bloom's edges: lit along the top, deeper along the bottom
    mask = vk.silhouette(vox)
    vox = vk.rim(vox, "top", colour=tip, mask=mask, only=lambda p, c: p[2] > 0)
    vox = vk.rim(vox, "bottom", colour=seam, amount=0.6, mask=mask)
    # two pointed leaves peeking out from behind the lower petals, pointing
    # down and out: the upper half lit, the lower half in shade (the split
    # reads as the midrib), a light top edge
    leaf = {}
    for side in (-1, 1):
        bx, bz = side * LEAF_BASE[0], LEAF_BASE[1]          # hidden behind the petals
        tx, tz = side * LEAF_TIP[0], LEAF_TIP[1]
        ln = math.hypot(tx - bx, tz - bz)
        ux, uz = (tx - bx) / ln, (tz - bz) / ln
        for x in range(-13, 14):
            for z in range(-15, -2):
                dx, dz = x - bx, z - bz
                s = (dx * ux + dz * uz) / ln                 # 0 at the base, 1 at the tip
                across = -dx * uz + dz * ux
                if not 0.0 < s < 1.0 or (x, z) in petals:
                    continue
                # widest a little before the middle, coming to a point
                w = LEAF_W * math.sin(math.pi * s ** 0.85) ** 0.8
                if abs(across) > w:
                    continue
                leaf[(x, z)] = (LEAF[1] if across * side > -0.7 else LEAF[0], abs(across) / max(w, 0.1))
    lc = tidy({q: c for q, (c, e) in leaf.items()})
    for q, (c, e) in leaf.items():
        x, z = q
        c = lc[q]
        if c == LEAF[1] and (x, z + 1) not in leaf and (x, z + 1) not in petals:
            c = LEAF[2]
        vox[(x, 0, z)] = c
        if e < 0.5:
            vox[(x, -1, z)] = c
    # the bright centre: a round button in three steps (rim ring, body,
    # crown), lit from the upper left, with a 2x2 catchlight up front
    for x in range(-5, 6):
        for z in range(-5, 6):
            r = math.hypot(x, z)
            if r > DISC_R:
                continue
            step = 3 if r <= 2.3 else (2 if r <= 3.6 else 1)
            n = Vector((x / DISC_R * 0.8, -1.0, z / DISC_R * 0.8)).normalized()
            t = vk.lit(n, LIGHT) - FRONT
            c = ring if step == 1 else (shine if t > 0.12 and step == 3 else (ring if t < -0.18 else body))
            for y in range(-(step + 1), 1):
                vox[(x, y, z)] = c
    for (x, z) in ((-2, 1), (-1, 1), (-2, 2), (-1, 2)):
        y = min(y for (vx, y, vz) in vox if vx == x and vz == z)
        vox[(x, y, z)] = CATCH
    # sticker border: the silhouette grown by ~1.5 cubes, one layer behind,
    # its lower part a warmer shade, with a plum ink line along its lower
    # edge: every outline cell whose open side faces down (the local normal,
    # from the air round it), so the line runs on round the curves
    sil = vk.silhouette(vox)
    border = {(x + a, z + b) for (x, z) in sil for a in range(-2, 3) for b in range(-2, 3)
              if a * a + b * b <= 2.6}
    paper = {}
    for (x, z) in border:
        c = PAPER if z >= -4 else PAPER_SHADE
        if any((x + a, z + b) not in border for a, b in N4):
            nx = sum(a for a in range(-2, 3) for b in range(-2, 3) if (x + a, z + b) not in border)
            nz = sum(b for a in range(-2, 3) for b in range(-2, 3) if (x + a, z + b) not in border)
            if nz < -0.6 * math.hypot(nx, nz):
                c = vk.mix(c, INK, INK_AMOUNT)
        paper[(x, 1, z)] = c
    vox.update(paper)
    return vox


built = {}
for name in PETALS:
    vk.reset()
    root = vk.empty("Flower")
    vox = flower(name)
    built[name] = vox
    vk.build("Flower", vox, vk.material("Voxel"), root, origin=(0.5, 0.5, 0.5), skip=vk.NO_BACK, ao=vk.AO())
    vk.report("flower " + name, root, budget=2500)
    xs, zs = [p[0] for p in vox], [p[2] for p in vox]
    print("SIZE", name, "x", min(xs), max(xs), "z", min(zs), max(zs), "burst", BURSTS[name])
    small = vk.islands(vox, 4, ignore=(CATCH, PETALS[name][4], PETALS[name][0], LEAF[2]))
    print("ISLANDS", name, len(small), [(c, len(g)) for c, g in small][:12])
    vk.export(os.path.join(MODELS, "flower_voxel_%s.glb" % name))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel")
for i, name in enumerate(PETALS):
    o = vk.build("Flower_" + name, built[name], mat, None, origin=(0.5, 0.5, 0.5), skip=vk.NO_BACK, ao=vk.AO())
    o.location = (i * 1.35 - 1.35, 0, 0)
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "flowers_front.png"), (0.0, -1.0, 0.05), (0, 0, 0), 4.3, 1300, 520)
pv.shoot(os.path.join(PREVIEW, "flowers_3q.png"), (0.55, -1.0, 0.4), (0, 0, 0), 4.3, 1300, 620)
pv.shoot(os.path.join(PREVIEW, "flowers_game.png"), (0.0, -1.0, 0.12), (0, 0, 0), 4.3, 1300, 520)
for o in bpy.context.scene.objects:
    if o.name.startswith("Flower_") and not o.name.endswith("red"):
        o.hide_render = True
pv.shoot(os.path.join(PREVIEW, "flower_close.png"), (0.35, -1.0, 0.3), (-1.35, 0, 0), 1.35, 800, 800)
print("DONE voxel flowers")
