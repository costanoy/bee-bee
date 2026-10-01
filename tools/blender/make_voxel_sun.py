"""Bee Bee — the sun as voxel art.

  blender --background --factory-startup --python make_voxel_sun.py -- <models_dir> <preview_dir>

A ball of cubes, like the moon and Jupiter, instead of the flat disc it
used to be: seen head-on and unshaded, a disc read as a 2D drawing next to
the other bodies in the sky. The game turns the ball slowly, so its surface
is painted all the way round — pale patches, brighter cells and a scatter
of warm sunspots that travel across it and give the turning away. Eight
blocky rays stand around it on a node of their own, which stays still.

The sun hangs far behind everything (135 units back), so like the
backdrops it is made of bigger cubes (0.3) that land on screen at the same
size as every other cube; same radius as before (7 units). The game draws
it unshaded, and unshaded it shows the stored colour as linear light, so
glow() darkens the palette to make it come out on screen as written here.
Exports sun_voxel.glb (nodes "Ball" and "Rays") and review renders.
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.3
R = 7.0 / BIG                  # radius in cubes


def glow(c):
    return tuple(v ** 2.2 for v in c)


# Kept pale: a saturated sun competes with the yellow flowers, and those are
# what the player has to read. The spots carry what warmth there is.
BODY = [glow((1.0, 0.94, 0.64)), glow((1.0, 0.96, 0.70)), glow((1.0, 0.91, 0.58))]
CELL = glow((1.0, 0.99, 0.84))             # brighter patches
SPOT = glow((1.0, 0.84, 0.46))
SPOT_CORE = glow((1.0, 0.74, 0.36))
SPOT_RIM = glow((1.0, 0.90, 0.54))
RAY = glow((1.0, 0.91, 0.58))
RAY_TIP = glow((1.0, 0.96, 0.74))


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def spots():
    """(direction, radius in cubes): two facing the camera at the start, the
    rest scattered over the whole ball without touching."""
    out = [(unit((-0.45, -1, 0.3)), 5.0), (unit((0.5, -1, -0.25)), 3.5)]
    rng = random.Random(8)
    tries = 0
    while len(out) < 8 and tries < 3000:
        tries += 1
        d = unit((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        r = rng.choice([2.5, 3.0, 3.5, 4.5, 5.0])
        if all(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(d, o))))) * R > r + ro + 5.0 for o, ro in out):
            out.append((d, r))
    return out


def ball():
    sp = spots()
    vox = {}
    n = int(R) + 1
    for x in range(-n, n):
        for y in range(-n, n):
            for z in range(-n, n):
                p = (x + 0.5, y + 0.5, z + 0.5)
                d = math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2)
                if d > R:
                    continue
                if d < R - 3:
                    vox[(x, y, z)] = BODY[0]             # the unseen core: one colour, merges away
                    continue
                u = unit(p)
                c = None
                for sd, r in sp:
                    a = math.acos(max(-1.0, min(1.0, sum(i * j for i, j in zip(u, sd))))) * R
                    if a < r * 0.5:
                        c = SPOT_CORE
                    elif a < r:
                        c = SPOT
                    elif a < r + 1.3:
                        c = SPOT_RIM
                    if c:
                        break
                if c is None:
                    k = h(x // 4, y // 4, z // 4, 3)
                    c = CELL if k > 0.78 else BODY[int(h(x // 3, y // 3, z // 3, 5) * 3)]
                vox[(x, y, z)] = c
    return vox


def rays():
    """Eight rays in the ball's own plane, two cubes thick: straight bars on
    the axes, square blocks on the diagonals, each with a paler tip."""
    vox = {}
    gap, length = 3, 6
    a = int(R) + gap
    for i in range(length):
        for w in (-2, -1, 0, 1):
            for sx, sz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                x = sx * (a + i) + (w if sx == 0 else (0 if sx > 0 else -1))
                z = sz * (a + i) + (w if sz == 0 else (0 if sz > 0 else -1))
                for y in (-1, 0):
                    vox[(x, y, z)] = RAY_TIP if i >= length - 2 else RAY
    b = int((R + gap) / math.sqrt(2)) + 1
    for i in range(4):
        for j in range(4):
            for sx in (1, -1):
                for sz in (1, -1):
                    x = sx * (b + i) - (1 if sx < 0 else 0)
                    z = sz * (b + j) - (1 if sz < 0 else 0)
                    for y in (-1, 0):
                        vox[(x, y, z)] = RAY_TIP if i + j >= 5 else RAY
    return vox


vk.reset()
root = vk.empty("Sun")
mat = vk.material("Voxel")
pivot = vk.empty("Ball", parent=root)
b = vk.build_mesh_merged("BallMesh", ball(), mat, pivot, size=BIG)
r = vk.build_mesh_merged("Rays", rays(), mat, root, size=BIG, skip=((0, 1, 0),))
print("sun polygons: ball", len(b.data.polygons), "rays", len(r.data.polygons), "radius in cubes:", round(R, 1))
vk.export(os.path.join(MODELS, "sun_voxel.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "sun_front.png"), (0.0, -1.0, 0.0), (0, 0, 0), 26.0, 900, 900)
pv.shoot(os.path.join(PREVIEW, "sun_3q.png"), (0.7, -1.0, 0.5), (0, 0, 0), 26.0, 900, 900)
print("DONE voxel sun")
