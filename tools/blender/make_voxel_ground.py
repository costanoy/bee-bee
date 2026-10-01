"""Bee Bee — the ground of the start scene as voxel art.

  blender --background --factory-startup --python make_voxel_ground.py -- <models_dir> <preview_dir>

Same footprint as the low-poly ground it replaces: 16 units wide, grass
top at z=0 (where the bee stands), running from just in front of the play
plane back to the trees, with a soil face towards the camera. Patchy
grass on top with tufts, tiny flowers and pebbles; a grass lip that drips
unevenly over the soil; soil in patches with stones, darkening downwards.
It is far too big to store cube by cube, so the colour varies per patch
instead of per cube and equal neighbours are merged (vk.build_mesh_merged)
— the cubes that stick out (tufts, flowers, the lip) still sit on the
shared voxel grid. Exports ground_voxel.glb and review renders.
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

X0, X1 = -200, 200        # 16 units wide
Y_FRONT, Y_BACK = -13, 63  # 0.52 units in front of the play plane, 2.5 behind it
DEPTH = 58                 # cubes of soil below the grass

GRASS = (0.44, 0.78, 0.30)
GRASS_LIGHT = (0.49, 0.82, 0.33)
GRASS_DARK = (0.39, 0.73, 0.28)
LIP = (0.36, 0.70, 0.27)
LIP_LIGHT = (0.41, 0.75, 0.29)
GRASS_EDGE = (0.60, 0.90, 0.40)
BLADE = (0.28, 0.62, 0.24)
SOIL = (0.62, 0.42, 0.26)
SOIL_LIGHT = (0.70, 0.50, 0.31)
SOIL_DARK = (0.52, 0.34, 0.22)
SOIL_DEEP = (0.44, 0.28, 0.19)
STONE = (0.80, 0.78, 0.84)
STONE_DARK = (0.62, 0.60, 0.68)
BLOOMS = [(1.0, 1.0, 1.0), (1.0, 0.90, 0.40), (1.0, 0.55, 0.72)]


def h(*k):
    """Cheap deterministic hash of integers -> [0, 1)."""
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def grass_at(x, y):
    """Patches about 4x3 cubes, staggered like brickwork."""
    row = y // 3
    r = h((x + (row % 2) * 2) // 4, row, 1)
    return GRASS_LIGHT if r < 0.22 else (GRASS_DARK if r > 0.84 else GRASS)


def soil_at(x, z):
    if z < -34:
        return SOIL_DEEP
    row = z // 3
    r = h((x + (row % 2) * 3) // 6, row, 2)
    if z < -22:
        return SOIL_DEEP if r < 0.55 else SOIL_DARK
    return SOIL_LIGHT if r < 0.16 else (SOIL_DARK if r > 0.74 else SOIL)


def lip_at(x, z):
    """The lip is a shade darker than the lawn, so its drips read against it."""
    return LIP_LIGHT if h(x // 3, z // 2, 3) < 0.35 else LIP


def lip(x):
    """How many cubes the grass hangs down the front, in 2-cube-wide drips."""
    xx = x // 2
    wave = (0.5 + 0.5 * math.sin(xx * 0.37 + 1.3)) * (0.5 + 0.5 * math.sin(xx * 0.13))
    return 3 + int(3.0 * wave + 2.4 * h(xx, 77))


def ground():
    cells = {}
    for x in range(X0, X1):
        for y in range(Y_FRONT, Y_BACK):
            cells[(x, y, -1)] = grass_at(x, y)
        n = lip(x)
        # the lip stands one cube proud of the soil, with a bright top edge
        for z in range(-n, 0):
            cells[(x, Y_FRONT - 1, z)] = GRASS_EDGE if z == -1 else (BLADE if z == -n else lip_at(x, z))
        for z in range(-DEPTH, -n):
            cells[(x, Y_FRONT, z)] = SOIL_DEEP if z >= -n - 1 else soil_at(x, z)      # a line of shade under the lip
    rng = random.Random(21)
    # stones in the soil face
    for _ in range(46):
        x, z = rng.randrange(X0 + 2, X1 - 4), rng.randint(-30, -9)
        w, t = rng.choice([(2, 1), (2, 2), (3, 2)])
        for i in range(w):
            for j in range(t):
                if (x + i, Y_FRONT, z + j) in cells:
                    cells[(x + i, Y_FRONT, z + j)] = STONE if j == t - 1 else STONE_DARK

    def clear(x, y):
        return not (abs(x) < 16 and -10 <= y <= 10)        # where the bee stands

    # tufts, tiny flowers and pebbles on the grass, thicker towards the front
    for _ in range(150):
        x, y = rng.randrange(X0 + 1, X1 - 2), int(Y_FRONT + 2 + (Y_BACK - Y_FRONT - 4) * rng.random() ** 1.6)
        if not clear(x, y):
            continue
        kind = rng.random()
        if kind < 0.62:
            cells[(x, y, 0)] = BLADE
            cells[(x, y, 1)] = GRASS_DARK
            if rng.random() < 0.6:
                cells[(x + 1, y, 0)] = BLADE
            if rng.random() < 0.3:
                cells[(x, y, 2)] = GRASS_LIGHT
        elif kind < 0.9:
            cells[(x, y, 0)] = BLADE
            cells[(x, y, 1)] = rng.choice(BLOOMS)
        else:
            cells[(x, y, 0)] = STONE
            cells[(x + 1, y, 0)] = STONE_DARK
    return cells


def solid(x, y, z):
    return z < 0 and y >= Y_FRONT


cells = ground()
vk.reset()
root = vk.empty("Ground")
o = vk.build_mesh_merged("Ground", cells, vk.material("Voxel", rough=0.9), root, solid=solid)
print("ground cubes:", len(cells), "polygons:", len(o.data.polygons))
vk.export(os.path.join(MODELS, "ground_voxel.glb"))

# ---------------------------------------------------------------- review renders
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (0.8, 0.8, 0.8)
    bee.location = (0, 0, 0.38)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "ground_front.png"), (0.0, -1.0, 0.2), (0, 0, -0.3), 10.0, 1600, 520)
pv.shoot(os.path.join(PREVIEW, "ground_3q.png"), (0.5, -1.0, 0.45), (0.3, 0, -0.1), 5.0, 1600, 800)
pv.shoot(os.path.join(PREVIEW, "ground_close.png"), (0.35, -1.0, 0.4), (-1.6, -0.3, -0.1), 2.2, 1100, 800)
print("DONE voxel ground")
