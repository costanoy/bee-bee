"""Bee Bee — Jupiter (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_jupiter.py -- <models_dir> <preview_dir>

A ball of cubes in cream, tan and rust bands with wavy edges, a few thin
pale streaks inside the bands, and the Great Red Spot with its darker
core. The low-poly Jupiter was drawn at scale 1.25; a voxel model can't
be scaled without breaking the shared cube size, so this one is built at
that size (radius 1.25 units = 31 cubes) and used unscaled. The game
spins it, so the bands go all the way round. Only the outer shell is
generated, and equal faces are merged (vk.build_mesh_merged).
Exports jupiter_voxel.glb and review renders (with the voxel bee for scale).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

# The game draws this unshaded (it shines by itself in the night sky), and
# unshaded it shows the stored colour as linear light, which comes out much
# paler. glow() darkens the palette so the screen shows the colours as
# written here; it is also why the model looks dark in the Blender previews.
def glow(c):
    return tuple(v ** 2.2 for v in c)


R = 31.0
SHELL = 3.0

CREAM = glow((1.0, 0.92, 0.74))
SAND = glow((0.98, 0.84, 0.62))
TAN = glow((0.90, 0.58, 0.34))
RUST = glow((0.82, 0.48, 0.30))
BROWN = glow((0.66, 0.38, 0.26))
POLE = glow((0.78, 0.62, 0.50))
SPOT = glow((0.88, 0.34, 0.24))
SPOT_CORE = glow((0.72, 0.22, 0.18))
SPOT_RING = glow((1.0, 0.80, 0.62))

# bands from the south pole up: (top edge in cubes from the centre, colour)
BANDS = [(-25, POLE), (-19, RUST), (-13, CREAM), (-7, TAN), (-2, SAND), (4, CREAM), (10, RUST), (15, SAND),
         (20, TAN), (26, CREAM), (99, POLE)]
SPOT_AT = (math.radians(-70), -10.0)     # longitude (facing the camera at the start), height in cubes
SPOT_SIZE = (8.5, 4.5)                   # half-width along the surface, half-height, in cubes


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def colour(x, y, z):
    lon = math.atan2(y + 0.5, x + 0.5)
    zc = z + 0.5
    # the spot: an oval on the surface, measured along the equator-wise arc
    dl = (lon - SPOT_AT[0] + math.pi) % (2 * math.pi) - math.pi
    u = dl * R * math.cos(math.asin(max(-1.0, min(1.0, zc / R)))) / SPOT_SIZE[0]
    v = (zc - SPOT_AT[1]) / SPOT_SIZE[1]
    s = u * u + v * v
    if s < 0.28:
        return SPOT_CORE
    if s < 1.0:
        return SPOT
    if s < 1.55:
        return SPOT_RING
    # wavy band edges: each latitude line wobbles by a cube or two round the planet
    wob = 1.3 * math.sin(lon * 5 + zc * 0.45) + 0.8 * math.sin(lon * 11 - zc * 0.3)
    zz = zc + wob
    for i, (top, c) in enumerate(BANDS):
        if zz < top:
            # thin streaks of the neighbouring tone inside the wider bands
            if c in (TAN, RUST) and h(int((lon + math.pi) * 6), z, 3) < 0.10:
                return BROWN
            if c in (CREAM, SAND) and h(int((lon + math.pi) * 5), z, 4) < 0.08:
                return SAND if c == CREAM else CREAM
            return c
    return POLE


def inside(x, y, z, r):
    return (x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5) ** 2 <= r * r


def jupiter():
    vox = {}
    n = int(R) + 1
    for x in range(-n, n):
        for y in range(-n, n):
            for z in range(-n, n):
                if inside(x, y, z, R) and not inside(x, y, z, R - SHELL):
                    vox[(x, y, z)] = colour(x, y, z)
    return vox


vox = jupiter()
vk.reset()
root = vk.empty("Jupiter")
o = vk.build_mesh_merged("Jupiter", vox, vk.material("Voxel", rough=0.8), root,
                         solid=lambda x, y, z: inside(x, y, z, R - SHELL))
print("jupiter cubes:", len(vox), "polygons:", len(o.data.polygons))
vk.export(os.path.join(MODELS, "jupiter_voxel.glb"))

# ---------------------------------------------------------------- review renders
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (2.05, 0, -0.8)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "jupiter_front.png"), (0.0, -1.0, 0.13), (0.5, 0, 0), 4.2, 1100, 800)
pv.shoot(os.path.join(PREVIEW, "jupiter_3q.png"), (0.6, -1.0, 0.45), (0, 0, 0), 3.0, 800, 800)
pv.shoot(os.path.join(PREVIEW, "jupiter_back.png"), (-0.5, 1.0, 0.3), (0, 0, 0), 3.0, 800, 800)
print("DONE voxel jupiter")
