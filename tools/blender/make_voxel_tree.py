"""Bee Bee — the trees of the start scene as voxel art (Toybox honey garden).

  blender --background --factory-startup --python make_voxel_tree.py -- <models_dir> <preview_dir> [<bee_dir>]

Two kinds, three sizes each (a = large, b = medium, c = small), at the
heights the game was laid out for (round 58/49/41 cubes, pine 59/50/41):
a round tree (a lush, cauliflower canopy of big leafy clumps on a chunky,
flared trunk) and a pine (stacked tiers with scalloped skirts and a rounded
tip). Built like a pop-up storybook: each clump and each tier is a plump,
flat-fronted pillow (its edge rounded back over two cubes), and the ones in
front stand two cubes proud of the ones behind, so the crisp lit top edge
of every clump catches the light. The paint does the rest, in flat bands
that merge: every clump is lit as its own ball (pines: as a cone) from the
painted light (vk.lit), snapped to four bands, so it shows a light crescent
upper left and a shade lower right; a lit rim along its top edge, a deep
line along its bottom edge and the shadow it casts on the clump right
under it; then the kit's vertical gradient. A few accents give each tree
its character: apples on the big round tree, blossoms on the middle one,
root toes and a knot hole on the trunks. No per-cube jitter, and the flat
fronts have no stepped rings (which striped the first try), so every tree
fits in 2,500 triangles (the old ones were 4.7k-9.4k).
They are never scaled or turned (the shared cube grid), and the camera is
always in front of and above them, so everything behind the centre and the
undersides are left out (vk.NO_BACK_UNDER); the cut keeps the whole
silhouette for any camera in front.
Exports tree_voxel_round_a/b/c.glb and tree_voxel_pine_a/b/c.glb, plus
review renders (with the voxel bee for scale, from <models_dir> or <bee_dir>).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
BEE_DIRS = [MODELS] + ARGS[2:]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

# round trees: a fresh spring green, warm in the light, teal in the shade
LEAF_TOP = (0.72, 0.92, 0.36)      # the lit top edge of every clump
LEAF_LIGHT = (0.54, 0.83, 0.26)
LEAF = (0.36, 0.70, 0.22)
LEAF_SHADE = (0.21, 0.54, 0.21)
LEAF_DEEP = (0.11, 0.38, 0.19)     # bottom edges, cast shadows, the underside
APPLE = (0.92, 0.28, 0.22)
APPLE_LIGHT = (1.00, 0.62, 0.48)
APPLE_SHADE = (0.70, 0.14, 0.16)
BLOSSOM = (1.00, 0.66, 0.76)
BLOSSOM_LIGHT = (1.00, 0.90, 0.92)
BLOSSOM_HEART = (1.00, 0.80, 0.30)
# pines: a deeper, cooler green (still well away from the sky's blue band)
PINE_TOP = (0.46, 0.80, 0.42)
PINE_LIGHT = (0.27, 0.64, 0.34)
PINE = (0.14, 0.49, 0.31)
PINE_SHADE = (0.08, 0.37, 0.28)
PINE_DEEP = (0.04, 0.25, 0.22)
# bark: warm cocoa, lit on the left like everything else
BARK_LIGHT = (0.74, 0.50, 0.30)
BARK = (0.57, 0.36, 0.22)
BARK_SHADE = (0.43, 0.26, 0.17)
BARK_DEEP = (0.27, 0.16, 0.12)     # the knot hole, the canopy's shadow on the trunk

LEAVES = [(-0.55, LEAF_DEEP), (-0.2, LEAF_SHADE), (0.2, LEAF), (0.55, LEAF_LIGHT)]
NEEDLES = [(-0.55, PINE_DEEP), (-0.2, PINE_SHADE), (0.2, PINE), (0.55, PINE_LIGHT)]
Y_CUT = 1                          # nothing behind this row is kept (the back is never seen)
STEP = 2                           # how far each layer of clumps stands in front of the last


def band(stops, n, bias=0.0):
    """The painted light of a cell with normal n, snapped to four flat bands
    (bias: lighter or darker for the whole clump)."""
    return vk.ramp(stops, vk.posterize(vk.lit(n) * 0.95 - 0.25 + bias, 4, -0.55, 0.55))


def pillows(items, top, deep, edge=0.65):
    """Stacks flat-fronted pillows into cells. items, back to front: (mask,
    front, paint) with mask a set of (x, z), front the y of its face and
    paint(x, z) its colour. Each pillow's rim is rounded back by two cubes.
    Seen from the front, a pillow gets a `top` rim along its upper edge, a
    line toward `deep` along its lower edge and casts a shadow on the two
    rows of whatever lies right under it. Returns ({cell: colour}, {(x, z):
    index of the pillow seen there})."""
    owner, fronts = {}, {}
    for k, (mask, front, paint) in enumerate(items):
        dist = vk.distance_in(mask, 3)
        for q in mask:
            f = front + {1: 2, 2: 1}.get(dist.get(q, 3), 0)
            owner[q] = k
            fronts[q] = min(fronts.get(q, 99), f)
    col = {}
    for (x, z), k in owner.items():
        c = items[k][2](x, z)
        up, down = owner.get((x, z + 1), -1), owner.get((x, z - 1), -1)
        if up < k:
            c = top
        elif down < k:
            c = vk.mix(c, deep, edge)
        elif max(owner.get((x, z + 1), -1), owner.get((x, z + 2), -1)) > k:
            c = vk.mix(c, deep, 0.55)                # the shadow of the clump just above
        col[(x, z)] = c
    vox = {}
    for (x, z), c in col.items():
        for y in range(fronts[(x, z)], Y_CUT + 1):
            vox[(x, y, z)] = c
    return vox, owner


def disc(cx, cz, rx, rz):
    return {(x, z) for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1)
            for z in range(math.floor(cz - rz), math.ceil(cz + rz) + 1)
            if ((x + 0.5 - cx) / rx) ** 2 + ((z + 0.5 - cz) / rz) ** 2 <= 1.0}


def ball_paint(cx, cz, rx, rz, stops, bias=0.0):
    """Paints a disc as the front of a ball lit from the painted light, in
    2x2 macro cubes (half the steps along every band's edge)."""
    def paint(x, z):
        x, z = x // 2 * 2 + 0.5, z // 2 * 2 + 0.5
        u, w = (x + 0.5 - cx) / rx, (z + 0.5 - cz) / rz
        return band(stops, (u, -math.sqrt(max(0.0, 1.0 - u * u - w * w)), w), bias)
    return paint


def trunk(vox, top, half, seed, knot=None, shadow=4):
    """A chunky trunk 2*half cubes wide up to row `top`, flared into root
    toes at the foot, lit on the left, with the shadow of what sits on it
    painted on its top `shadow` rows."""
    for z in range(top):
        flare = 1 if z < 3 else 0                              # the foot spreads a cube each way
        w = half + flare
        for x in range(-w, w):
            for y in range(-half - flare, half):
                c = BARK_LIGHT if x < -half + 1 + flare else (BARK_SHADE if x >= half - 1 + flare else BARK)
                if z >= top - shadow:
                    c = vk.shade(c, -0.30)                     # in the shade of the canopy
                vox[(x, y, z)] = c
    # two root toes reaching forward and out, lit on top
    for s in (-1, 1):
        x0 = -half - 3 if s < 0 else half + 1
        for x in (x0, x0 + 1):
            vox[(x, -half - 1, 0)] = BARK_LIGHT if s < 0 else BARK
        vox[(x0 + (1 if s < 0 else 0), -half - 1, 1)] = BARK_LIGHT if s < 0 else BARK_SHADE
    if knot:
        kx, kz = knot
        for x in (kx, kx + 1):
            for z in (kz, kz + 1):
                vox[(x, -half - 1, z)] = BARK_DEEP if z == kz else BARK_SHADE
        for x in (kx - 1, kx, kx + 1, kx + 2):
            vox[(x, -half - 1, kz + 2)] = BARK_LIGHT            # its lit lip, standing proud
        vox[(kx - 1, -half - 1, kz + 1)] = vox[(kx + 2, -half - 1, kz + 1)] = BARK


def round_tree(height, seed, accent=None, bare=0.33):
    """bare: the share of the height left to the trunk below the canopy."""
    rng = random.Random(seed)
    j = lambda a: rng.uniform(-a, a)
    R = height * (1.0 - bare) / 2.08          # the canopy is about 2.08 R tall
    cz = height - 1 - 1.14 * R                # the centre of the middle mass
    f0 = -round(R * 0.35)                     # the face of the middle mass
    clumps = [(0.0, 0.0, R, R * 0.88, f0)]    # (x, z, rx, rz, front), back to front
    for a in (168, 132, 98, 64, 22):          # a ring of clumps over the top, left to right
        r = R * rng.uniform(0.46, 0.52)
        t = math.radians(a + j(6))
        clumps.append((math.cos(t) * R * 0.78, math.sin(t) * R * 0.66, r, r, f0 - STEP))
    for f in (-0.62, -0.2, 0.24, 0.64):       # the scalloped underside
        r = R * rng.uniform(0.40, 0.45)
        clumps.append((f * R + j(1), -R * 0.52 + j(1), r, r * 0.9, f0 - STEP))
    for (fx, fz, fr) in ((0.04, -0.24, 0.40), (-0.36, 0.18, 0.42), (0.32, 0.28, 0.38)):
        r = R * fr                            # three bulging toward the camera
        clumps.append((fx * R + j(1), fz * R + j(1), r, r, f0 - 2 * STEP))
    # the light top and darker underside of the whole canopy, painted per
    # clump (a gradient across the clumps would cut every band in pieces)
    items = [(disc(cx, cz + z, rx, rz), fy,
              ball_paint(cx, cz + z, rx, rz, LEAVES, max(-0.16, min(0.12, 0.2 * z / R))))
             for (cx, z, rx, rz, fy) in clumps]
    canopy, owner = pillows(items, LEAF_TOP, LEAF_DEEP)
    # the top cube at the contract's height
    lift = height - 1 - max(p[2] for p in canopy)
    canopy = {(x, y, z + lift): c for (x, y, z), c in canopy.items()}
    z0 = min(p[2] for p in canopy)
    canopy = vk.rim(canopy, "bottom", colour=LEAF_DEEP, amount=0.8)
    vox = {}
    half = 3 if height > 45 else 2
    trunk(vox, z0 + 6, half, seed, knot=(-2, max(4, round(z0 * 0.42))) if accent != "blossom" else None)
    # two stubby branches up into the canopy, left and right of the trunk
    for s in (-1, 1):
        for i in range(5):
            for y in range(-half + 1, half):
                for w in (0, 1):
                    vox[(s * (half - 1 + i + w) - (1 if s < 0 else 0), y, z0 + 3 + i)] = BARK_SHADE
    vox.update(canopy)
    if accent:
        fr = vk.front(canopy)
        dist = vk.distance_in(set(fr), 6)
        spots = [q for q in sorted(fr) if dist.get(q, 0) >= 5 and q[1] > z0 + 6]
        rng.shuffle(spots)
        placed = []
        for (x, z) in spots:
            if len(placed) >= (3 if accent == "apple" else 6):
                break
            if any(abs(x - a) < 9 and abs(z - b) < 8 for a, b in placed):
                continue
            placed.append((x, z))
            y = min(fr.get((x + i, z + k), 99) for i in range(4) for k in range(4)) - 1
            if accent == "apple":
                # a round 4x4 apple a cube proud of the leaves, lit top-left,
                # with a stalk and a leaf
                for i in range(4):
                    for k in range(4):
                        if (i in (0, 3)) and (k in (0, 3)):
                            continue
                        vox[(x + i, y, z + k)] = APPLE_SHADE if (k == 0 or (i == 3 and k == 1)) else APPLE
                vox[(x + 1, y, z + 2)] = APPLE_LIGHT
                vox[(x + 1, y + 1, z + 4)] = BARK_DEEP
                vox[(x + 2, y + 1, z + 4)] = vox[(x + 2, y + 1, z + 5)] = LEAF_LIGHT
            else:
                # a round blossom with a golden heart, lighter on top
                for (i, k) in ((1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (1, 3), (2, 3)):
                    vox[(x + i, y, z + k)] = BLOSSOM_LIGHT if k >= 2 else BLOSSOM
                for (i, k) in ((1, 1), (2, 1), (1, 2), (2, 2)):
                    vox[(x + i, y, z + k)] = BLOSSOM_HEART if (i, k) == (1, 2) else BLOSSOM
    return vox


def pine_tree(height, R, tiers, seed, bare=0.15):
    rng = random.Random(seed)
    trunk_h = max(7, round(height * bare))
    # tier sizes: R is the bottom tier's half-width, each tier is narrower
    # than the one below it, overlaps it by 40% of its height, and they are
    # as tall as the height allows (the tip two cubes above the top tier)
    shrink = [1.0 - (0.6 / tiers) * i for i in range(tiers)]
    span = sum(s * 0.6 for s in shrink[:-1]) + shrink[-1]
    tall = (height - 3 - trunk_h - 2) / (R * span)
    items = []
    base = trunk_h + 2
    for i, s in enumerate(shrink):
        r0 = R * s * rng.uniform(0.97, 1.03)
        h = round(r0 * tall)
        lobes = 3 + (1 if r0 > 12 else 0) + (1 if r0 > 16 else 0)
        lw = (r0 + 1.0) / lobes                # half the width of one scallop
        mask = set()
        for x in range(-int(r0) - 2, int(r0) + 2):
            # a cone whose flanks bulge out a little
            for z in range(base, base + h):
                t = (z - base) / h
                if abs(x + 0.5) <= r0 * (1.0 - t) ** 0.8 + 1.0:
                    mask.add((x, z))
            # the skirt droops below it in round scallops
            if abs(x + 0.5) <= r0 + 1.0:
                m = ((x + 0.5 + r0 + 1.0) % (2 * lw)) - lw
                drop = 3.4 * math.sqrt(max(0.0, 1.0 - (m / lw) ** 2))
                for z in range(base - round(drop), base):
                    mask.add((x, z))

        def paint(x, z, base=base, h=h, r0=r0, bias=-0.12 + 0.08 * i):
            # lit as a cone: across by where it sits in the row; the skirt
            # bulges toward the light, so each tier is lightest low down,
            # just above its deep bottom edge (in 2x2 macro cubes, like the
            # round trees)
            x, z = x // 2 * 2 + 0.5, z // 2 * 2 + 0.5
            t = min(1.0, max(0.0, (z - base) / h))
            u = max(-1.0, min(1.0, (x + 0.5) / (r0 * (1.0 - t) ** 0.8 + 1.0)))
            return band(NEEDLES, (u * 0.85, -math.sqrt(1.0 - u * u) * 0.85, 0.8 - 0.6 * t), bias)
        items.append((mask, -round(r0 * 0.30) - STEP * i, paint))
        base += round(h * 0.6)                 # the next tier starts inside this one
    needles, owner = pillows(items, PINE_TOP, PINE_DEEP, edge=0.75)
    # a rounded tip, two cubes tall
    zt = max(p[2] for p in needles)
    fy = min(p[1] for p in needles if p[2] == zt)
    for (x, z) in ((-1, zt + 1), (0, zt + 1), (-1, zt + 2), (0, zt + 2), (-2, zt + 1), (1, zt + 1)):
        for y in range(fy, fy + 2):
            needles[(x, y, z)] = PINE_TOP if z == zt + 2 else PINE_LIGHT
    lift = height - 1 - max(p[2] for p in needles)
    needles = {(x, y, z + lift): c for (x, y, z), c in needles.items()}
    zlo = min(p[2] for p in needles)
    vox = {}
    trunk(vox, zlo + 3, 3 if height > 45 else 2, seed, knot=(-1, 2) if height > 55 else None, shadow=3)
    vox.update(needles)
    return vox


TREES = {
    "round_a": lambda: round_tree(58, 11, "apple"),
    "round_b": lambda: round_tree(49, 22, "blossom"),
    "round_c": lambda: round_tree(41, 33),
    "pine_a": lambda: pine_tree(59, 17.0, 4, 44),
    "pine_b": lambda: pine_tree(50, 14.5, 3, 55),
    "pine_c": lambda: pine_tree(41, 12.0, 3, 66),
}
BUDGET = 2500
ONLY = os.environ.get("TREES", "")               # e.g. TREES=round_a,pine_a: build just those

built = {}
for name, make in TREES.items():
    if ONLY and name not in ONLY.split(","):
        continue
    vk.reset()
    root = vk.empty("Tree")
    vox = make()
    built[name] = vox
    o = vk.build("Tree", vox, vk.material("Voxel", rough=0.85), root, skip=vk.NO_BACK_UNDER)
    vk.report("tree " + name, root, budget=BUDGET)
    vk.export(os.path.join(MODELS, "tree_voxel_%s.glb" % name))
    xs = [p[0] for p in vox]
    print("tree", name, "cubes:", len(vox), "height:", max(z for _, _, z in vox) + 1, "width:", max(xs) - min(xs) + 1)

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel", rough=0.85)
xs = {"round_a": -4.3, "round_b": -2.4, "round_c": -0.75, "pine_a": 0.75, "pine_b": 2.2, "pine_c": 3.45}
for name, vox in built.items():
    o = vk.build("Tree_" + name, vox, mat, None, skip=vk.NO_BACK_UNDER)
    o.location = (xs[name], 0, 0)
for d in BEE_DIRS:
    try:
        bpy.ops.import_scene.gltf(filepath=os.path.join(d, "bee_voxel.glb"))
        bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
        bee.scale = (1.0, 1.0, 1.0)
        bee.location = (4.55, -0.3, 0.4)
        for b in bpy.context.scene.objects:
            if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
                b.hide_render = True
        break
    except Exception as e:
        print("no bee for scale in", d, ":", e)
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "trees_front.png"), (0.0, -1.0, 0.2), (0.1, 0, 1.2), 10.4, 1600, 600)
pv.shoot(os.path.join(PREVIEW, "trees_3q.png"), (0.45, -1.0, 0.5), (0.1, 0, 1.2), 10.6, 1600, 700)
pv.shoot(os.path.join(PREVIEW, "tree_round_close.png"), (0.3, -1.0, 0.2), (-3.4, 0, 1.15), 2.9, 800, 800)
pv.shoot(os.path.join(PREVIEW, "tree_pine_close.png"), (0.3, -1.0, 0.2), (1.1, 0, 1.15), 2.9, 800, 800)
print("DONE voxel trees")
