"""Bee Bee — the drifting clouds as voxel art: three sizes on the shared grid.

  blender --background --factory-startup --python make_voxel_cloud.py -- <models_dir> <preview_dir>

Each cloud is a union of rounded puffs sitting on a flat-bottomed slab, so
it reads as the classic cartoon cloud from the front. Pure white where a
cube faces the sky, a touch of blue on the body and a blue-grey underside
give it volume without any texture. They are see-through (ALPHA), so the
sky and the sun show through them. The game used to stretch one model to
every cloud size; a scaled voxel model would break the shared cube size,
so there is one model per size instead (large / medium / small = a / b / c),
all used unscaled. Exports cloud_voxel_a/b/c.glb and review renders (with
the voxel bee beside them for scale).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

TOP = (1.0, 1.0, 1.0)
BODY = (0.93, 0.96, 1.0)
LOW = (0.86, 0.92, 1.0)
UNDER = (0.72, 0.82, 0.96)
# see-through, like the wings: the sky (and the sun) show through the cloud
ALPHA = 0.6

# variant: (slab half-width, [(cx, cz, rx, rz, ry) per puff]) — all in cubes
CLOUDS = {
    "a": (22, [(-13, 4, 9, 8, 5), (-3, 8, 11, 11, 6), (9, 6, 10, 9, 5), (17, 3, 6, 5, 4)]),
    "b": (17, [(-9, 3, 8, 7, 5), (2, 7, 10, 10, 6), (12, 3, 6, 6, 4)]),
    "c": (12, [(-5, 3, 7, 6, 4), (5, 5, 8, 8, 5)]),
}


def cloud(half_w, puffs):
    cells = set()
    # the slab: a rounded bar the puffs sit on, which gives the flat base
    for x in range(-half_w, half_w):
        for z in range(0, 4):
            inset = 2 if z == 0 else (1 if z == 3 else 0)
            if not (-half_w + inset <= x < half_w - inset):
                continue
            end = min(x + half_w, half_w - 1 - x)          # cubes from the nearer tip
            depth = 3 if (z == 0 or end < 2) else 4
            for y in range(-depth, depth):
                cells.add((x, y, z))
    for cx, cz, rx, rz, ry in puffs:
        for x in range(cx - rx, cx + rx + 1):
            for z in range(0, cz + rz + 1):
                for y in range(-ry, ry + 1):
                    if ((x + 0.5 - cx) / rx) ** 2 + ((z + 0.5 - cz) / rz) ** 2 + ((y + 0.5) / ry) ** 2 <= 1.0:
                        cells.add((x, y, z))
    vox = {}
    # nearest cubes first (the camera is always on the -Y side): see cloud_material
    for (x, y, z) in sorted(cells, key=lambda c: (c[1], c[2], c[0])):
        if z == 0:
            c = UNDER
        elif z == 1:
            c = LOW
        elif (x, y, z + 1) not in cells:
            c = TOP
        else:
            c = BODY
        vox[(x, y, z)] = c
    return vox


def cloud_material():
    # Single-sided: with the default double-sided export the far side of the
    # cloud shows through the near side as a grid of streaks, and the layers
    # add up until it is nearly opaque again. For the same reason the cubes
    # are emitted nearest-first and the game draws the cloud with
    # depth_draw_mode ALWAYS, so only its nearest surface gets blended.
    m = vk.material("Voxel", alpha=ALPHA, rough=0.9)
    m.use_backface_culling = True
    return m


def centre(vox):
    zs = [z for _, _, z in vox]
    return (0.0, 0.0, (min(zs) + max(zs) + 1) / 2.0)


built = {}
for name, (half_w, puffs) in CLOUDS.items():
    vk.reset()
    root = vk.empty("Cloud")
    vox = cloud(half_w, puffs)
    built[name] = vox
    vk.build_mesh("Cloud", vox, cloud_material(), root, origin=centre(vox), seed=11, jitter=0.03, alpha=ALPHA)
    vk.export(os.path.join(MODELS, "cloud_voxel_%s.glb" % name))
    xs = [x for x, _, _ in vox]
    zs = [z for _, _, z in vox]
    print("cloud", name, "cubes:", len(vox), "w:", max(xs) - min(xs) + 1, "h:", max(zs) - min(zs) + 1)

# ---------------------------------------------------------------- review renders
vk.reset()
mat = cloud_material()
xpos = {"a": -1.75, "b": 0.05, "c": 1.45}
for name, vox in built.items():
    o = vk.build_mesh("Cloud_" + name, vox, mat, None, origin=centre(vox), seed=11, jitter=0.03, alpha=ALPHA)
    o.location = (xpos[name], 0, 0)
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
    bee.scale = (0.8, 0.8, 0.8)
    bee.location = (2.55, 0, 0)
    for o in bpy.context.scene.objects:
        if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
            o.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "clouds_front.png"), (0.0, -1.0, 0.13), (0.25, 0, 0), 6.2, 1500, 520)
pv.shoot(os.path.join(PREVIEW, "clouds_3q.png"), (0.5, -1.0, 0.5), (0.25, 0, 0), 6.2, 1500, 680)
pv.shoot(os.path.join(PREVIEW, "cloud_close.png"), (0.45, -1.0, 0.4), (-1.75, 0, 0), 2.3, 900, 700)
pv.shoot(os.path.join(PREVIEW, "cloud_under.png"), (0.4, -1.0, -0.45), (-1.75, 0, 0), 2.3, 900, 700)
print("DONE voxel clouds")
