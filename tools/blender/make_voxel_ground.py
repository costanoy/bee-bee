"""Bee Bee — the ground of the start scene as voxel art (Toybox honey garden).

  blender --background --factory-startup --python make_voxel_ground.py -- <models_dir> <preview_dir> [<bee_dir>]

Same footprint as before: 16 units wide, grass top at z=0 (where the bee
stands), running from just in front of the play plane back to the trees,
with a soil face towards the camera. A storybook lawn: soft sunlit patches
and clover patches (wide ovals, which read as flat dapples at the game's
grazing view), a cooler band of shade along the back where the trees
stand, chunky three-blade tufts and tiny daisies (a plus of petals round a
golden heart, facing the camera), and a clear patch where the bee rests.
The front is a plump grass lip with a lit top edge that hangs over the soil
in round scallops, tufts poking up along it and the lip's shadow on the
soil right under it. The soil comes in layers, the way a cut-away picture
book shows them: dark topsoil, warm soil in staggered clods, a band of
sandy clay with wavy edges, then darker soil going down, with a dozen
rounded sandy pebbles standing a cube proud.
Only the top 20 cubes of soil are ever on screen, so the detail lives
there. Colour changes in patches and bands, never per cube, so the faces
merge (vk.build, watertight: no T-junctions to crack open against the sky)
and the whole ground stays under 10,000 triangles. Faces the camera never
sees are left out (the back, the undersides and the two far ends).
Exports ground_voxel.glb and review renders (with the voxel bee for scale,
from <models_dir> or <bee_dir>).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
BEE_DIRS = [MODELS] + ARGS[2:]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

X0, X1 = -200, 200         # 16 units wide
Y_FRONT, Y_BACK = -13, 63  # 0.52 units in front of the play plane, 2.5 behind it
DEPTH = 58                 # cubes of soil below the grass

# lawn: a lush spring green, warm in the sun patches, cooler in the shade
GRASS = (0.42, 0.77, 0.27)
GRASS_SUN = (0.50, 0.82, 0.30)
GRASS_CLOVER = (0.35, 0.69, 0.25)
GRASS_SHADE = (0.31, 0.63, 0.25)  # the band under the trees
BLADE = (0.27, 0.60, 0.22)
BLADE_LIGHT = (0.56, 0.86, 0.33)
# the lip along the front
LIP_EDGE = (0.66, 0.92, 0.40)      # its lit top edge
LIP = (0.38, 0.72, 0.26)
LIP_DEEP = (0.20, 0.46, 0.20)      # the bottom cube of every scallop
# soil, in layers
TOPSOIL = (0.47, 0.30, 0.19)
SOIL = (0.63, 0.42, 0.25)
SOIL_LIGHT = (0.70, 0.49, 0.30)
CLAY = (0.78, 0.59, 0.36)
SUBSOIL = (0.53, 0.34, 0.21)
DEEP = (0.42, 0.26, 0.17)
SHADOW = (0.36, 0.22, 0.15)        # the lip's shadow on the soil
# pebbles: sand and taupe, the top only a step lighter (never near-white,
# or they read as scattered rice against the soil)
STONE_LIGHT = (0.75, 0.65, 0.55)
STONE = (0.69, 0.59, 0.50)        # shows as about (0.72, 0.64, 0.54)
STONE_DARK = (0.59, 0.50, 0.42)
STONES = (STONE_LIGHT, STONE, STONE_DARK)
PEBBLES = 13                       # in the soil face
# tiny daisies: petals and heart (soft, so they never compete with the flowers in play)
DAISIES = [((1.00, 0.98, 0.94), (1.00, 0.80, 0.24)),
           ((1.00, 0.72, 0.82), (1.00, 0.86, 0.36)),
           ((1.00, 0.92, 0.50), (0.96, 0.58, 0.16))]


def clear(x, y):
    """Where the bee stands: no tufts, daisies or pebbles."""
    return abs(x) < 16 and -10 <= y <= 10


def wave(x, seed, amp=1.5):
    """A gentle wavy edge for a soil layer, in 4-cube steps."""
    xx = x // 4
    return round(amp * math.sin(xx * 0.62 + seed) + 0.8 * math.sin(xx * 0.22 + 2 * seed))


def lip(x):
    """How many cubes the grass hangs down the front: round scallops 10
    cubes wide, each 2-4 cubes deeper in its middle than at its ends."""
    k = (x - X0) // 10
    lw = 5.0
    m = ((x - X0) % 10) + 0.5 - lw
    d = 2 + int(3 * vk.hash01(k, 0, 0, 7))
    return 3 + round(d * math.sqrt(max(0.0, 1.0 - (m / lw) ** 2)))


def ovals(rng, n, rx, ry):
    """n soft ovals over the lawn: (cx, cy, rx, ry)."""
    out = []
    for _ in range(n):
        out.append((rng.uniform(X0, X1), rng.uniform(Y_FRONT, Y_BACK), rx * rng.uniform(0.7, 1.3), ry * rng.uniform(0.7, 1.3)))
    return out


def inside(ov, x, y):
    return any(((x + 0.5 - cx) / a) ** 2 + ((y + 0.5 - cy) / b) ** 2 <= 1.0 for cx, cy, a, b in ov)


def lawn_at(x, y, sun, clover):
    """The lawn's colour, in macro cubes 2 wide and 4 deep (the lawn is seen
    edge-on, so depth steps hardly show): the band of shade under the trees
    at the back, then clover and sun patches."""
    x, y = x // 2 * 2, y // 4 * 4 + 1
    if y >= 44 - wave(x, 3.0, 2.0):
        return GRASS_SHADE if not inside(sun, x, y) else GRASS
    if inside(clover, x, y):
        return GRASS_CLOVER
    if inside(sun, x, y):
        return GRASS_SUN
    return GRASS


def soil_at(x, z, n):
    """The soil face's colour at (x, z), under a lip n cubes deep."""
    if z >= -n - 2:
        return SHADOW                                        # the lip's shadow
    if z >= -9 + wave(x, 1.0):
        return TOPSOIL
    if z >= -18 + wave(x, 2.0):
        # warm soil with lighter clods, 8x3, staggered like brickwork
        row = z // 3
        r = vk.hash01((x + (row % 2) * 4) // 8, row, 0, 2)
        return SOIL_LIGHT if r < 0.3 else SOIL
    if z >= -21 + wave(x, 4.0, 1.0):
        return CLAY
    if z >= -34:
        return SUBSOIL
    return DEEP


def ground():
    rng = random.Random(21)
    sun = ovals(rng, 34, 16, 7)
    clover = ovals(rng, 24, 10, 5)
    cells = {}
    for x in range(X0, X1):
        for y in range(Y_FRONT, Y_BACK):
            cells[(x, y, -1)] = lawn_at(x, y, sun, clover)
        n = lip(x)
        # the lip stands one cube proud of the soil, with a lit top edge
        for z in range(-n, 0):
            if z == -1:
                c = LIP_EDGE
            elif z == -n:
                c = LIP_DEEP
            else:
                c = LIP
            cells[(x, Y_FRONT - 1, z)] = c
        for z in range(-DEPTH, -n):
            cells[(x, Y_FRONT, z)] = soil_at(x, z, n)
    # about a dozen rounded sandy pebbles standing a cube proud of the soil,
    # a step lighter on top. They keep a cube of soil between them and the
    # topsoil, so the lip's shadow line stays clean, and keep apart from each
    # other. Every spot is drawn, kept or not, so the tufts and daisies stay put.
    kept = 0
    for _ in range(28):
        x, z = rng.randrange(X0 + 3, X1 - 6), rng.randint(-21, -10)
        w, t = rng.choice([(3, 2), (4, 3), (5, 3), (4, 2)])
        if kept == PEBBLES or any(z + t - 1 > -11 + wave(x + i, 1.0) for i in range(w)):
            continue
        if any(cells.get((x + i, Y_FRONT - 1, z + j)) in STONES for i in range(-6, w + 6) for j in range(-3, t + 3)):
            continue
        kept += 1
        for i in range(w):
            for j in range(t):
                if t == 3 and (i in (0, w - 1)) and (j in (0, t - 1)):
                    continue                                 # round the corners
                c = STONE_LIGHT if j == t - 1 else (STONE_DARK if j == 0 else STONE)
                cells[(x + i, Y_FRONT - 1, z + j)] = c
    print("pebbles", kept)
    # tufts poking up along the front edge
    x = X0 + 2
    while x < X1 - 3:
        if not clear(x, Y_FRONT - 1):
            for i, hgt in enumerate((1, 2, 1) if rng.random() < 0.6 else (2, 1)):
                for k in range(hgt):
                    cells[(x + i, Y_FRONT - 1, k)] = LIP
        x += rng.randint(10, 22)
    # chunky tufts, tiny daisies and pebbles on the lawn, thicker toward the front
    for _ in range(105):
        x = rng.randrange(X0 + 2, X1 - 3)
        y = int(Y_FRONT + 1 + (Y_BACK - Y_FRONT - 3) * rng.random() ** 1.5)
        if clear(x, y) or clear(x + 2, y):
            continue
        kind = rng.random()
        if kind < 0.62:
            # three blades, the middle one tallest (their tops catch the
            # painted top light, so one colour is enough)
            tall = rng.choice((2, 3))
            for i, hgt in ((0, tall - 1), (1, tall), (2, tall - 1)):
                for k in range(hgt):
                    cells[(x + i, y, k)] = BLADE
        elif kind < 0.9:
            petal, heart = DAISIES[rng.randrange(3)] if rng.random() < 0.8 else DAISIES[0]
            cells[(x + 1, y, 0)] = BLADE
            for (i, k) in ((0, 2), (2, 2), (1, 3), (1, 1)):
                cells[(x + i, y, k)] = petal
            cells[(x + 1, y, 2)] = heart
        else:
            cells[(x, y, 0)] = STONE
            cells[(x + 1, y, 0)] = STONE_LIGHT
            cells[(x + 2, y, 0)] = STONE_DARK
    return cells


def solid(x, y, z):
    """The ground goes on past both ends (they are off screen)."""
    return (x < X0 or x >= X1) and z < 0 and y >= Y_FRONT


cells = ground()
vk.reset()
root = vk.empty("Ground")
o = vk.build("Ground", cells, vk.material("Voxel", rough=0.9), root, solid=solid, skip=vk.NO_BACK_UNDER)
vk.report("ground", root, budget=10000)
vk.export(os.path.join(MODELS, "ground_voxel.glb"))

# ---------------------------------------------------------------- review renders
for d in BEE_DIRS:
    try:
        bpy.ops.import_scene.gltf(filepath=os.path.join(d, "bee_voxel.glb"))
        bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
        bee.scale = (1.0, 1.0, 1.0)
        bee.location = (0, 0, 0.38)
        for b in bpy.context.scene.objects:
            if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
                b.hide_render = True
        break
    except Exception as e:
        print("no bee for scale in", d, ":", e)
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "ground_front.png"), (0.0, -1.0, 0.2), (0, 0, -0.3), 10.0, 1600, 520)
pv.shoot(os.path.join(PREVIEW, "ground_3q.png"), (0.5, -1.0, 0.45), (0.3, 0, -0.1), 5.0, 1600, 800)
pv.shoot(os.path.join(PREVIEW, "ground_close.png"), (0.35, -1.0, 0.4), (-1.6, -0.3, -0.1), 2.2, 1100, 800)
print("DONE voxel ground")
