"""Bee Bee — the collectible flower as voxel art: one shape, three colours.

  blender --background --factory-startup --python make_voxel_flower.py -- <models_dir> <preview_dir>

Five rounded, slightly cupped petals facing the camera (-Y), a darker
seam where petals meet so each reads on its own, a lighter rim on the
upper petal edges, a raised cream centre with a golden dot and a
catchlight, and two small leaves underneath. Built at its in-game size
on the shared voxel grid (~26 cubes across = ~1.04 units), so it's used
unscaled. Only the petal colours change between red, yellow and blue.
Exports flower_voxel_<colour>.glb and review renders.
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

PETALS = {
    #          base               seam / inner         rim highlight
    "red": ((1.0, 0.20, 0.26), (0.78, 0.06, 0.16), (1.0, 0.52, 0.52)),
    "yellow": ((1.0, 0.88, 0.10), (0.96, 0.62, 0.04), (1.0, 0.97, 0.55)),
    "blue": ((0.30, 0.52, 1.0), (0.16, 0.30, 0.86), (0.62, 0.80, 1.0)),
}
CENTRE = (1.0, 0.70, 0.14)
CENTRE_RING = (0.86, 0.42, 0.06)
GOLD = (0.62, 0.30, 0.08)
WHITE = (1.0, 1.0, 1.0)
LEAF = (0.36, 0.72, 0.28)
LEAF_DARK = (0.24, 0.54, 0.22)

N_PETALS = 5
PETAL_DIST = 6.6      # petal centre distance from the flower centre (cubes)
PETAL_R = 5.6


def petal_of(x, z):
    """Index of the petal whose disc contains (x, z), nearest first; None."""
    best, best_d = None, 1e9
    for k in range(N_PETALS):
        a = math.pi / 2 + 2 * math.pi * k / N_PETALS
        px, pz = PETAL_DIST * math.cos(a), PETAL_DIST * math.sin(a)
        d = math.hypot(x - px, z - pz)
        if d <= PETAL_R and d < best_d:
            best, best_d = k, d
    return best


def flower(colours):
    base, seam, rim = colours
    vox = {}
    span = int(PETAL_DIST + PETAL_R) + 1
    owner = {}
    for x in range(-span, span + 1):
        for z in range(-span, span + 1):
            k = petal_of(x + 0.5, z + 0.5)
            if k is not None:
                owner[(x, z)] = k
    for (x, z), k in owner.items():
        r = math.hypot(x + 0.5, z + 0.5)
        # a cup: the outer part of each petal curls a cube or two forward
        front = -round(max(0.0, r - 6.0) / 3.2)
        edge = any(owner.get((x + dx, z + dz), k) != k for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        outline = any((x + dx, z + dz) not in owner for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge:
            c = seam
        elif outline and z > 1 and r > 8:
            c = rim
        elif r < 5.0:
            c = seam if r > 4.2 else base
        else:
            c = base
        for y in range(front, front + 2):
            vox[(x, y, z)] = c
    # raised centre: two layers of cream, a ring, a golden dot, a catchlight
    for x in range(-5, 6):
        for z in range(-5, 6):
            r = math.hypot(x + 0.5, z + 0.5)
            if r <= 4.6:
                c = CENTRE_RING if r > 3.8 else CENTRE
                vox[(x, -1, z)] = c
                if r <= 3.6:
                    vox[(x, -2, z)] = GOLD if r <= 1.5 else CENTRE
    vox[(-2, -3, 2)] = (1.0, 0.95, 0.70)
    vox[(-1, -3, 2)] = (1.0, 0.95, 0.70)
    vox[(-2, -3, 1)] = (1.0, 0.95, 0.70)
    # two leaves peeking out from behind the lower petals: solid tilted
    # ellipses (a darker midrib along the long axis), pointing down and out
    for side in (-1, 1):
        cx, cz = side * 8.0, -10.0
        ux, uz = side * 0.80, -0.60            # long axis
        for x in range(int(cx) - 7, int(cx) + 8):
            for z in range(int(cz) - 7, int(cz) + 8):
                dx, dz = x + 0.5 - cx, z + 0.5 - cz
                along = dx * ux + dz * uz
                across = -dx * uz + dz * ux
                if (along / 5.2) ** 2 + (across / 2.3) ** 2 <= 1 and petal_of(x + 0.5, z + 0.5) is None:
                    vox[(x, 2, z)] = LEAF_DARK if abs(across) < 0.6 else LEAF
    return vox


built = {}
for name, colours in PETALS.items():
    vk.reset()
    root = vk.empty("Flower")
    vox = flower(colours)
    built[name] = vox
    vk.build_mesh("Flower", vox, vk.material("Voxel"), root, origin=(0.5, 0.5, 0.5), seed=7, jitter=0.035)
    vk.export(os.path.join(MODELS, "flower_voxel_%s.glb" % name))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel")
for i, name in enumerate(PETALS):
    o = vk.build_mesh("Flower_" + name, built[name], mat, None, origin=(0.5, 0.5, 0.5), seed=7, jitter=0.035)
    o.location = (i * 1.35 - 1.35, 0, 0)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "flowers_front.png"), (0.0, -1.0, 0.05), (0, 0, 0), 4.3, 1300, 520)
pv.shoot(os.path.join(PREVIEW, "flowers_3q.png"), (0.55, -1.0, 0.4), (0, 0, 0), 4.3, 1300, 620)
for o in bpy.context.scene.objects:
    if o.name.startswith("Flower_") and not o.name.endswith("red"):
        o.hide_render = True
pv.shoot(os.path.join(PREVIEW, "flower_close.png"), (0.35, -1.0, 0.3), (-1.35, 0, 0), 1.35, 800, 800)
print("DONE voxel flowers")
