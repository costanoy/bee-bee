"""Bee Bee — the rose hedge (obstacle) as voxel art.

  blender --background --factory-startup --python make_voxel_hedge.py -- <models_dir> <preview_dir>

One hedge segment is a tile TILE voxels wide (x = 0..TILE*VOX in 3D units),
centred on the collision band at z=0. The top and bottom outlines follow
curves periodic in TILE, so any variant sits flush against any other.
Exports hedge_voxel_a/b/c.glb and review renders (a bar of mixed tiles,
with the voxel bee beside it for scale).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

TILE = 24
GREENS = [(0.30, 0.64, 0.24), (0.38, 0.72, 0.28), (0.24, 0.54, 0.22)]
LEAF_LIGHT = (0.52, 0.82, 0.32)
DEEP = (0.16, 0.40, 0.18)
ROSE = (1.0, 0.36, 0.48)
ROSE_LIGHT = (1.0, 0.62, 0.70)
ROSE_DEEP = (0.80, 0.12, 0.30)
BUD = (0.95, 0.22, 0.36)
THORN = (0.52, 0.34, 0.20)
THORN_TIP = (0.96, 0.88, 0.70)


def _bumps(x, seed, amp):
    """Irregular bumps that fade to zero at both tile ends, so every variant
    keeps the same edges (and tiles seamlessly) but its own middle."""
    rng = random.Random(seed)
    env = math.sin(math.pi * x / TILE) ** 2
    v = sum(rng.uniform(0.4, 1.0) * math.sin(2 * math.pi * k * x / TILE + rng.uniform(0, 6.28)) / k for k in (2, 3, 5))
    return env * amp * v


def top(x, seed=0):
    t = 2 * math.pi * x / TILE
    return 8 + round(0.8 * math.sin(t) + _bumps(x, seed, 1.9))


def bottom(x, seed=0):
    t = 2 * math.pi * x / TILE
    return -8 - round(0.6 * math.sin(t + 2.0) + _bumps(x, seed + 1, 1.4))


def hash3(x, y, z, seed):
    return random.Random((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ seed).random()


def hedge_tile(seed):
    rng = random.Random(seed)
    vox = {}
    fronts = {}
    for x in range(TILE):
        zt, zb = top(x, seed), bottom(x, seed)
        for z in range(zb, zt + 1):
            zn = z / (zt if z >= 0 else -zb)
            depth = max(2, round(7 * math.sqrt(max(0.0, 1 - zn * zn * 0.85))))
            y_front = -depth
            fronts[(x, z)] = y_front
            for y in range(y_front, 6):
                # leafy patches: pick a green per 2x2x2 block, darker deep inside
                g = GREENS[int(hash3(x // 2, y // 2, z // 2, seed) * 3)]
                vox[(x, y, z)] = DEEP if y > 2 else g
    # tufts of lighter leaves popping out of the front and the top edge
    for _ in range(16):
        x, z = rng.randrange(TILE), rng.randint(bottom(0) + 2, top(0) - 1)
        if (x, z) in fronts:
            vox[(x, fronts[(x, z)] - 1, z)] = LEAF_LIGHT
    for _ in range(7):
        x = rng.randrange(TILE)
        vox[(x, rng.randint(-4, 0), top(x, seed) + 1)] = LEAF_LIGHT
    # thorns: two-cube spikes (brown base, pale tip) poking up from the top,
    # down from the bottom, and out of the front
    for _ in range(3):
        x = rng.randint(1, TILE - 2)
        zt = top(x, seed)
        yy = rng.randint(-5, -1)
        vox[(x, yy, zt + 1)] = THORN
        vox[(x, yy, zt + 2)] = THORN_TIP
    for _ in range(3):
        x = rng.randint(1, TILE - 2)
        zb = bottom(x, seed)
        yy = rng.randint(-5, -1)
        vox[(x, yy, zb - 1)] = THORN
        vox[(x, yy, zb - 2)] = THORN_TIP
    for _ in range(4):
        x, z = rng.randint(1, TILE - 2), rng.randint(-6, 6)
        if (x, z) in fronts:
            vox[(x, fronts[(x, z)] - 1, z)] = THORN
            vox[(x, fronts[(x, z)] - 2, z)] = THORN_TIP
    # roses: a plus of petals with a deep centre and one light petal,
    # spread out so they don't clump
    centres = []
    tries = 0
    while len(centres) < rng.choice([5, 6]) and tries < 200:
        tries += 1
        c = (rng.randint(2, TILE - 3), rng.randint(-5, 5))
        if all(abs(c[0] - o[0]) + abs(c[1] - o[1]) >= 5 for o in centres):
            centres.append(c)
    for cx, cz in centres:
        y = min(fronts.get((cx + dx, cz + dz), -2) for dx in (-1, 0, 1) for dz in (-1, 0, 1)) - 1
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx == 0 and dz == 0:
                    vox[(cx, y - 1, cz)] = ROSE_DEEP
                elif dx == 0 or dz == 0:
                    vox[(cx + dx, y, cz + dz)] = ROSE
                else:
                    vox[(cx + dx, y + 1, cz + dz)] = ROSE
        vox[(cx - 1, y - 1, cz + 1)] = ROSE_LIGHT
    # a bud or two
    for _ in range(rng.choice([1, 2])):
        bx, bz = rng.randint(1, TILE - 2), rng.randint(-5, 5)
        by = fronts.get((bx, bz), -2) - 1
        vox[(bx, by, bz)] = BUD
        vox[(bx, by, bz - 1)] = LEAF_LIGHT
    return vox


tiles = {}
for variant, seed in (("a", 101), ("b", 202), ("c", 303)):
    vk.reset()
    mat = vk.material("Voxel")
    root = vk.empty("Hedge")
    vox = hedge_tile(seed)
    tiles[variant] = vox
    vk.build_mesh("Hedge", vox, mat, root, seed=seed)
    vk.export(os.path.join(MODELS, "hedge_voxel_%s.glb" % variant))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel")
row = vk.empty("Row")
order = "abca"
for i, v in enumerate(order):
    o = vk.build_mesh("Tile", tiles[v], mat, row, seed=i + 7)
    o.location = (i * TILE * vk.VOX, 0, 0)
bee = None
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
    bee.scale = (0.8, 0.8, 0.8)
    bee.location = (len(order) * TILE * vk.VOX + 0.9, -0.3, 0.05)
    for o in bpy.context.scene.objects:
        if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
            o.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
w = len(order) * TILE * vk.VOX
centre = (w / 2 + 0.4, 0, 0)
pv.shoot(os.path.join(PREVIEW, "hedge_3q.png"), (0.35, -1.0, 0.55), centre, w + 1.6, 1400, 700)
pv.shoot(os.path.join(PREVIEW, "hedge_game.png"), (0.0, -1.0, 0.13), centre, w + 1.6, 1400, 700)
pv.shoot(os.path.join(PREVIEW, "hedge_close.png"), (0.5, -1.0, 0.45), (0.75, 0, 0), 1.7, 900, 700)
print("DONE voxel hedge")
