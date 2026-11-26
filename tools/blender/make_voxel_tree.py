"""Bee Bee — the trees of the start scene as voxel art.

  blender --background --factory-startup --python make_voxel_tree.py -- <models_dir> <preview_dir>

Two kinds, three sizes each (a = large, b = medium, c = small): a round
tree (a canopy of overlapping leafy balls on a short trunk) and a pine
(three stepped tiers). The low-poly trees got their variety from a random
scale and a random turn; voxel trees can't be scaled or turned without
breaking the shared cube grid, so the variety comes from the six models
instead, all used unscaled and unrotated. Because they are never turned
and the camera is always in front of and above them, the back and the
underside are left out of the mesh (a third fewer polygons).
Exports tree_voxel_round_a/b/c.glb and tree_voxel_pine_a/b/c.glb, plus
review renders (with the voxel bee for scale).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

BARK = (0.58, 0.38, 0.24)
BARK_DARK = (0.46, 0.29, 0.19)
LEAVES = [(0.38, 0.72, 0.30), (0.44, 0.78, 0.33), (0.33, 0.66, 0.28)]
LEAF_TOP = (0.56, 0.86, 0.40)
LEAF_UNDER = (0.25, 0.55, 0.27)
PINE = [(0.24, 0.56, 0.36), (0.28, 0.61, 0.39), (0.21, 0.51, 0.34)]
PINE_TOP = (0.36, 0.70, 0.46)
PINE_UNDER = (0.15, 0.41, 0.29)

UNSEEN = ((0, 1, 0), (0, 0, -1))     # back and underside


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def trunk(vox, half, height, seed):
    for z in range(height):
        w = half + (1 if z < 1 else 0)                 # a little flare at the foot
        for x in range(-w, w):
            for y in range(-w, w):
                vox[(x, y, z)] = BARK_DARK if h(x, y, z // 3, seed) < 0.3 else BARK


def round_tree(scale, seed):
    rng = random.Random(seed)
    vox = {}
    r = 13 * scale
    trunk_h = round(20 * scale)
    trunk(vox, 2 if scale > 0.8 else 1, trunk_h + round(r * 0.6), seed)
    cz = trunk_h + r * 0.75
    balls = [(0, 0, cz, r)]
    for side in (-1, 1):
        balls.append((side * r * rng.uniform(0.62, 0.78), rng.uniform(-2, 2), cz - r * rng.uniform(0.25, 0.4), r * rng.uniform(0.62, 0.74)))
    balls.append((rng.uniform(-3, 3), -r * 0.3, cz + r * rng.uniform(0.55, 0.7), r * rng.uniform(0.6, 0.7)))
    balls.append((rng.uniform(-4, 4), -r * 0.55, cz - r * 0.3, r * 0.62))        # a bulge towards the camera
    leaves = set()
    for bx, by, bz, br in balls:
        for x in range(int(bx - br) - 1, int(bx + br) + 2):
            for y in range(int(by - br) - 1, int(by + br) + 2):
                for z in range(int(bz - br) - 1, int(bz + br) + 2):
                    if (x + 0.5 - bx) ** 2 + (y + 0.5 - by) ** 2 + (z + 0.5 - bz) ** 2 <= br * br:
                        leaves.add((x, y, z))
    zlo = min(z for _, _, z in leaves)
    zhi = max(z for _, _, z in leaves)
    for (x, y, z) in leaves:
        t = (z - zlo) / (zhi - zlo)
        patch = h(x // 2, y // 2, z // 2, seed)
        if (x, y, z + 1) not in leaves and patch < 0.75:
            c = LEAF_TOP
        elif t < 0.22 or ((x, y, z - 1) not in leaves and t < 0.6):
            c = LEAF_UNDER
        else:
            c = LEAVES[int(patch * 3)]
        vox[(x, y, z)] = c
    return vox


def pine_tree(scale, seed):
    rng = random.Random(seed)
    vox = {}
    trunk_h = round(11 * scale)
    trunk(vox, 2 if scale > 0.8 else 1, trunk_h + 4, seed)
    z0 = trunk_h
    needles = {}
    tiers = [(14, 17), (11, 15), (8, 15)]
    for i, (R, H) in enumerate(tiers):
        R, H = R * scale * rng.uniform(0.94, 1.06), round(H * scale)
        for dz in range(H):
            r = R * (1.0 - dz / H) ** 0.85 + 1.2
            z = z0 + dz
            for x in range(int(-r) - 1, int(r) + 2):
                for y in range(int(-r) - 1, int(r) + 2):
                    if (x + 0.5) ** 2 + (y + 0.5) ** 2 <= r * r:
                        needles[(x, y, z)] = (i, dz)
        z0 += round(H * 0.62)            # the next tier starts inside this one
    top = max(z for _, _, z in needles)
    needles[(0, 0, top + 1)] = needles[(-1, 0, top + 1)] = needles[(0, -1, top + 1)] = needles[(-1, -1, top + 1)] = (2, 99)
    for (x, y, z), (i, dz) in needles.items():
        patch = h(x // 2, y // 2, z // 2, seed)
        if dz == 0:
            c = PINE_UNDER                                 # the skirt of each tier
        elif (x, y, z + 1) not in needles:
            c = PINE_TOP if patch < 0.8 else PINE[0]
        else:
            c = PINE[int(patch * 3)]
        vox[(x, y, z)] = c
    return vox


TREES = {
    "round_a": lambda: round_tree(1.25, 11), "round_b": lambda: round_tree(1.05, 22), "round_c": lambda: round_tree(0.88, 33),
    "pine_a": lambda: pine_tree(1.25, 44), "pine_b": lambda: pine_tree(1.05, 55), "pine_c": lambda: pine_tree(0.88, 66),
}

built = {}
for name, make in TREES.items():
    vk.reset()
    root = vk.empty("Tree")
    vox = make()
    built[name] = vox
    o = vk.build_mesh("Tree", vox, vk.material("Voxel", rough=0.85), root, seed=3, jitter=0.03, skip=UNSEEN)
    vk.export(os.path.join(MODELS, "tree_voxel_%s.glb" % name))
    print("tree", name, "cubes:", len(vox), "polygons:", len(o.data.polygons), "height:", max(z for _, _, z in vox) + 1)

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel", rough=0.85)
xs = {"round_a": -4.1, "round_b": -2.5, "round_c": -1.1, "pine_a": 0.4, "pine_b": 1.9, "pine_c": 3.2}
for name, vox in built.items():
    o = vk.build_mesh("Tree_" + name, vox, mat, None, seed=3, jitter=0.03, skip=UNSEEN)
    o.location = (xs[name], 0, 0)
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (4.4, -0.3, 0.4)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "trees_front.png"), (0.0, -1.0, 0.2), (0.1, 0, 1.2), 10.4, 1600, 600)
pv.shoot(os.path.join(PREVIEW, "trees_3q.png"), (0.45, -1.0, 0.5), (0.1, 0, 1.2), 10.6, 1600, 700)
pv.shoot(os.path.join(PREVIEW, "tree_round_close.png"), (0.35, -1.0, 0.35), (-3.3, 0, 1.0), 2.6, 800, 800)
pv.shoot(os.path.join(PREVIEW, "tree_pine_close.png"), (0.35, -1.0, 0.35), (0.3, 0, 1.0), 2.6, 800, 800)
print("DONE voxel trees")
