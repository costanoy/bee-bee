"""Bee Bee — the sun as voxel art.

  blender --background --factory-startup --python make_voxel_sun.py -- <models_dir> <preview_dir>

The sun hangs far behind everything (135 units back), so like the
backdrops it is made of bigger cubes (0.3) that land on screen at the same
size as every other cube. It is a flat disc — it always faces the camera
and the game draws it unshaded, so only its front exists — with a pale
core, a warmer rim, a soft highlight towards the upper left, and eight
short blocky rays. Same radius as the smooth sphere it replaces (7 units).
Unshaded, the game shows the stored colour as linear light, so glow()
darkens the palette to make it come out on screen as written here.
Exports sun_voxel.glb and a review render.
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.3
R = 7.0 / BIG                  # the old sphere's radius, in cubes


def glow(c):
    return tuple(v ** 2.2 for v in c)


# Kept pale, like the sphere it replaces: a saturated sun competes with the
# yellow flowers, and those are what the player has to read.
CORE = glow((1.0, 0.98, 0.80))
BODY = glow((1.0, 0.94, 0.64))
RIM = glow((1.0, 0.88, 0.50))
SHINE = glow((1.0, 1.0, 0.94))
RAY = glow((1.0, 0.91, 0.58))


def sun():
    vox = {}
    n = int(R) + 1
    for x in range(-n, n):
        for z in range(-n, n):
            d = math.hypot(x + 0.5, z + 0.5)
            if d > R:
                continue
            if d > R - 2.2:
                c = RIM
            elif d < R * 0.55:
                c = CORE
            else:
                c = BODY
            # a soft crescent of light inside the upper-left edge
            hd = math.hypot(x + 0.5 + R * 0.28, z + 0.5 - R * 0.28)
            if R * 0.50 < hd < R * 0.62 and (x + 0.5) < -(z + 0.5) * 0.2 and z > 0 and d < R - 2.2:
                c = SHINE
            vox[(x, 0, z)] = c
    # eight rays: straight bars on the axes, square blocks on the diagonals
    gap, length = 3, 6
    a = int(R) + gap
    for i in range(length):
        for w in (-2, -1, 0, 1):
            for sx, sz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                x = sx * (a + i) + (w if sx == 0 else (0 if sx > 0 else -1))
                z = sz * (a + i) + (w if sz == 0 else (0 if sz > 0 else -1))
                vox[(x, 0, z)] = RAY
    b = int((R + gap) / math.sqrt(2)) + 1
    for i in range(4):
        for j in range(4):
            for sx in (1, -1):
                for sz in (1, -1):
                    x = sx * (b + i) - (1 if sx < 0 else 0)
                    z = sz * (b + j) - (1 if sz < 0 else 0)
                    vox[(x, 0, z)] = RAY
    return vox


vox = sun()
vk.reset()
root = vk.empty("Sun")
FRONT_ONLY = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1))
o = vk.build_mesh_merged("Sun", vox, vk.material("Voxel"), root, size=BIG, skip=FRONT_ONLY)
print("sun cubes:", len(vox), "polygons:", len(o.data.polygons), "radius in cubes:", round(R, 1))
vk.export(os.path.join(MODELS, "sun_voxel.glb"))

# ---------------------------------------------------------------- review render
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "sun_front.png"), (0.0, -1.0, 0.0), (0, 0, 0), 24.0, 900, 900)
print("DONE voxel sun")
