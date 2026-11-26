"""Bee Bee — the drifting clouds as voxel art: three sizes on the shared grid.

  blender --background --factory-startup --python make_voxel_cloud.py -- <models_dir> <preview_dir> [scale_bee.glb]

Storybook clouds: a flat base and a few big round puffs, the tallest a
little left of centre, painted rather than see-through. Each puff is
painted the way a picture book draws a cloud, flat in the front view: a
white face, a lavender crescent along its belly (the puff's own outline
offset up toward the light) and a deeper sliver at the very bottom of the
crescent. Where a puff sits in front of another, the one behind gets a
soft lavender crease line along the front one's outline, so every puff
reads as its own ball. Over that, a gentle vertical gradient, a white top
rim and a lavender underside (STYLE.md, "Clouds": never grey, never inked,
0.25 of luma at most inside a cloud). Opaque and single-sided with the
back left out (the camera is always on the -Y side), so there are no alpha
streaks and no overdraw; the time-of-day colour comes from the game, which
hazes the cloud material toward the horizon like the gulls. One model per
size (large / medium / small = a / b / c, 45 / 35 / 25 cubes wide), all
used unscaled. Exports cloud_voxel_a/b/c.glb and review renders (with the
voxel bee beside them for scale, from <models_dir> or the optional third
path).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
BEE = ARGS[2] if len(ARGS) > 2 else os.path.join(MODELS, "bee_voxel.glb")
os.makedirs(PREVIEW, exist_ok=True)

# STYLE.md "Clouds" (mid layer): white tops, a lavender belly
C_TOP = (1.00, 1.00, 1.00)
C_BODY = (0.95, 0.94, 0.99)
C_LAV = (0.81, 0.75, 0.93)
C_UNDER = (0.69, 0.62, 0.85)
C_CREASE = (0.87, 0.83, 0.95)       # the line a puff draws on the one behind it

# variant: (width, [(cx, cy, cz, rx, ry, rz) per puff]) — in cubes, x centred
# on 0, the base on z 0. Front puffs (lower cy) overlap the ones behind; the
# first puff is the long flat base the others sit on.
CLOUDS = {
    "a": (45, [(0.0, 1.5, 2.0, 19.0, 2.5, 2.5),
               (-15.0, -1.0, 4.0, 7.5, 3.0, 5.0), (-4.0, 0.5, 8.0, 9.5, 3.5, 9.5),
               (8.0, -1.5, 5.5, 7.5, 3.5, 7.0), (17.5, -0.5, 3.0, 5.5, 3.0, 4.5)]),
    "b": (35, [(0.0, 1.5, 2.0, 14.5, 2.5, 2.5),
               (-10.5, -1.0, 4.0, 6.5, 3.0, 5.0), (-1.0, 0.5, 7.0, 8.5, 3.5, 8.5),
               (11.0, -1.5, 4.0, 7.0, 3.0, 5.0)]),
    "c": (25, [(0.0, 1.5, 2.0, 9.5, 2.0, 2.5),
               (-6.0, -1.0, 4.0, 6.5, 3.0, 5.0), (6.0, 0.0, 5.0, 7.0, 3.0, 7.0)]),
}

# Each puff's front is cut flat this far in front of its centre (a share of
# its depth): a round ball's front steps back one cube per contour, and the
# lit top of every step showed as a white dash across the puff. Cut, only
# the outer ring of a puff steps back.
FRONT = 0.45
# the crescents, as how far the puff's own outline is moved up (and a little
# left, toward the painted light) before it is cut out of the puff, in
# shares of the puff's radii: what is left over is the shaded belly
BELLY = (-0.10, 0.42)
DEEP = (-0.05, 0.18)
# and the white shine on the other side: the outline moved down and right
SHINE = (0.08, -0.14)


def puff_cells(pf, width):
    """A puff's cells: cut flat in front, the base on z 0 and the cloud kept
    to its width (columns -width//2 .. width - width//2 - 1)."""
    cx, cy, cz, rx, ry, rz = pf
    return {(x, y, z) for (x, y, z) in vk.ellipsoid(cx, cy, cz, rx, ry, rz)
            if z >= 0 and -(width // 2) <= x < width - width // 2 and y + 0.5 >= cy - FRONT * ry}


def inside(pf, x, z, shift=(0.0, 0.0)):
    """Whether column (x, z) lies inside the puff's front outline moved by
    shift (shares of its radii)."""
    cx, cy, cz, rx, ry, rz = pf
    u = (x + 0.5 - cx) / rx - shift[0]
    w = (z + 0.5 - cz) / rz - shift[1]
    return u * u + w * w <= 1.0


def smooth(cells):
    """Drops lone cubes from the outline (seen from the front: a cell with
    one neighbour or none in the 2D silhouette, or a single cube standing
    on a top edge), so no single-cube nub sticks out of a puff's curve."""
    while True:
        m = {(x, z) for (x, _, z) in cells}
        lone = {(x, z) for (x, z) in m if sum((x + dx, z + dz) in m for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))) <= 1}
        lone |= {(x, z) for (x, z) in m if (x, z + 1) not in m and (x - 1, z) not in m and (x + 1, z) not in m}
        if not lone:
            return cells
        cells = {p for p in cells if (p[0], p[2]) not in lone}


def cloud(width, puffs):
    half = width / 2.0
    sets = [puff_cells(pf, width) for pf in puffs]
    cells = smooth(set().union(*sets))
    # a flat base with its bottom corners rounded off
    cells = {p for p in cells if not (p[2] == 0 and abs(p[0] + 0.5) > half - 2.5)}
    # who owns each column of the front view: the puff whose front is
    # nearest the camera there (the most inside one on a tie)
    fronts = [vk.front({p: 1 for p in s}) for s in sets]
    owner = {}
    for (x, z) in vk.silhouette({p: 1 for p in cells}):
        best = None
        for i, pf in enumerate(puffs):
            if (x, z) in fronts[i]:
                u, w = (x + 0.5 - pf[0]) / pf[3], (z + 0.5 - pf[2]) / pf[5]
                key = (fronts[i][(x, z)], u * u + w * w)
                if best is None or key < best[0]:
                    best = (key, i)
        owner[(x, z)] = best[1] if best else 0
    paint = {}
    for (x, z), i in owner.items():
        pf = puffs[i]
        if not inside(pf, x, z, DEEP):
            c = C_UNDER
        elif not inside(pf, x, z, BELLY):
            c = C_LAV
        else:
            c = C_BODY if inside(pf, x, z, SHINE) else C_TOP
            # the crease: next to the outline of a puff in front of this one
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                j = owner.get((x + dx, z + dz))
                if j is not None and j != i and fronts[j][(x + dx, z + dz)] < fronts[i].get((x, z), 99) - 0.5:
                    c = C_CREASE
                    break
        paint[(x, z)] = c
    vox = {p: paint[(p[0], p[2])] for p in cells}
    vox = vk.gradient(vox, top=0.03, bottom=-0.07)
    vox = vk.rim(vox, "top", colour=C_TOP)
    vox = vk.rim(vox, "bottom", colour=C_UNDER)
    return vox


def cloud_material():
    # opaque and single-sided: the camera only ever sees the front, and the
    # back is left out (NO_BACK), so nothing needs drawing from behind
    m = vk.material("Voxel", rough=0.9)
    m.use_backface_culling = True
    return m


def centre(vox):
    xs = [x for x, _, _ in vox]
    zs = [z for _, _, z in vox]
    return ((min(xs) + max(xs) + 1) / 2.0, 0.0, (min(zs) + max(zs) + 1) / 2.0)


BUDGET = {"a": 2000, "b": 1500, "c": 1000}
built = {}
for name, (width, puffs) in CLOUDS.items():
    vk.reset()
    root = vk.empty("Cloud")
    vox = cloud(width, puffs)
    built[name] = vox
    vk.build("Cloud", vox, cloud_material(), root, origin=centre(vox), skip=vk.NO_BACK)
    vk.report("cloud " + name, root, budget=BUDGET[name])
    vk.export(os.path.join(MODELS, "cloud_voxel_%s.glb" % name))
    xs = [x for x, _, _ in vox]
    zs = [z for _, _, z in vox]
    print("cloud", name, "cubes:", len(vox), "w:", max(xs) - min(xs) + 1, "h:", max(zs) - min(zs) + 1,
          "luma %.2f-%.2f" % (min(map(vk.luma, vox.values())), max(map(vk.luma, vox.values()))))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = cloud_material()
xpos = {"a": -1.75, "b": 0.05, "c": 1.45}
for name, vox in built.items():
    o = vk.build("Cloud_" + name, vox, mat, None, origin=centre(vox), skip=vk.NO_BACK)
    o.location = (xpos[name], 0, 0)
try:
    bpy.ops.import_scene.gltf(filepath=BEE)
    bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (2.55, 0, 0)
    for o in bpy.context.scene.objects:
        if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
            o.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "clouds_front.png"), (0.0, -1.0, 0.13), (0.25, 0, 0), 6.2, 1500, 520)
pv.shoot(os.path.join(PREVIEW, "clouds_3q.png"), (0.5, -1.0, 0.5), (0.25, 0, 0), 6.2, 1500, 680)
pv.shoot(os.path.join(PREVIEW, "cloud_close.png"), (0.45, -1.0, 0.4), (-1.75, 0, 0), 2.3, 900, 700)
pv.shoot(os.path.join(PREVIEW, "cloud_under.png"), (0.4, -1.0, -0.45), (-1.75, 0, 0), 2.3, 900, 700)
print("DONE voxel clouds")
