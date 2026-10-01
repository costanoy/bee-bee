"""Bee Bee — the UFO (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_ufo.py -- <models_dir> <preview_dir>

A classic flying saucer: a lens-shaped lavender hull with a darker rim
band carrying eight yellow lamps, a glowing teal emitter underneath, and
a see-through glass dome with a little green alien inside. The low-poly
UFO was drawn at scale 0.7; this one is built at that size (about 2 units
= 49 cubes across) and used unscaled. The game spins it, so it is
modelled all the way round. Hull, alien and dome are separate meshes
under one root: the hull's faces are merged (vk.build_mesh_merged), and
the dome carries its transparency in its vertex colours like the bee's
wings. Exports ufo_voxel.glb and review renders (with the voxel bee).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

R = 24.0                     # hull radius in cubes

def glow(c):
    """The game draws the UFO unshaded, and there the stored colour is shown
    as linear light — much paler than authored. Darkening it here makes the
    colour on screen come out as written."""
    return tuple(v ** 2.2 for v in c)


HULL_TOP = glow((0.80, 0.84, 1.0))
HULL = glow((0.62, 0.67, 0.95))
HULL_UNDER = glow((0.43, 0.47, 0.80))
RIM = glow((0.26, 0.29, 0.58))
LAMP = glow((1.0, 0.88, 0.30))
EMITTER = glow((0.55, 0.96, 0.90))
EMITTER_RING = glow((0.30, 0.66, 0.78))
GLASS = glow((0.70, 0.97, 0.95))
GLASS_ALPHA = 0.3
ALIEN = glow((0.46, 0.88, 0.36))
ALIEN_DARK = glow((0.30, 0.68, 0.30))
EYE = (0.01, 0.01, 0.02)
EYE_SHINE = (1.0, 1.0, 1.0)

DOME_Z, DOME_R = 5, 11.0


def hull_radius(z):
    """Lens profile: a shallow bowl below, a two-cube rim, a low cone on top."""
    if z < -7 or z > 5:
        return 0.0
    if z < 0:
        return R * math.sqrt(max(0.0, 1.0 - ((-z - 0.5) / 7.5) ** 2)) * 0.98
    if z < 2:
        return R
    return R - 4.0 - (z - 2) * 2.6


def hull():
    vox = {}
    n = int(R) + 1
    for z in range(-7, 6):
        r = hull_radius(z)
        for x in range(-n, n):
            for y in range(-n, n):
                d = math.hypot(x + 0.5, y + 0.5)
                if d > r:
                    continue
                if 0 <= z < 2:
                    a = math.atan2(y + 0.5, x + 0.5)
                    k = round(a / (math.pi / 4))
                    near_lamp = abs(a - k * math.pi / 4) * R < 1.6 and d > R - 3
                    c = LAMP if near_lamp else RIM
                elif z >= 2:
                    c = HULL_TOP if z >= 4 else HULL
                elif z == -7 or (z == -6 and d < 6):
                    c = EMITTER if d < 4.5 else EMITTER_RING
                else:
                    c = HULL_UNDER if z < -3 else HULL
                vox[(x, y, z)] = c
    return vox


def dome():
    """A one-cube-thick glass bubble sitting on the hull's top."""
    vox = {}
    n = int(DOME_R) + 1
    for x in range(-n, n):
        for y in range(-n, n):
            for z in range(DOME_Z, DOME_Z + n + 1):
                d = math.sqrt((x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - DOME_Z) ** 2)
                if DOME_R - 1.0 < d <= DOME_R:
                    vox[(x, y, z)] = GLASS
    return vox


def alien():
    vox = {}
    # shoulders, then a big head
    for x in range(-3, 3):
        for y in range(-2, 2):
            for z in range(DOME_Z + 1, DOME_Z + 3):
                vox[(x, y, z)] = ALIEN_DARK
    hz = DOME_Z + 5.5            # keeps the top of the head clear of the glass
    for x in range(-5, 5):
        for y in range(-5, 5):
            for z in range(DOME_Z + 2, DOME_Z + 12):
                if ((x + 0.5) / 4.6) ** 2 + ((y + 0.5) / 4.2) ** 2 + ((z + 0.5 - hz) / 3.8) ** 2 <= 1.0:
                    vox[(x, y, z)] = ALIEN
    # big dark eyes on the camera side (-Y), three cubes square, each with a glint
    for x0 in (-4, 1):
        for x in range(x0, x0 + 3):
            for z in range(DOME_Z + 4, DOME_Z + 7):
                front = min(y for (xx, y, zz) in vox if xx == x and zz == z)
                vox[(x, front, z)] = EYE
        gx, gz = x0 + (0 if x0 > 0 else 2), DOME_Z + 6
        front = min(y for (xx, y, zz) in vox if xx == gx and zz == gz)
        vox[(gx, front, gz)] = EYE_SHINE
    return vox


def glass_material():
    # single-sided, so the far wall of the bubble doesn't show through the near one
    m = vk.material("VoxelGlass", alpha=GLASS_ALPHA, rough=0.2)
    m.use_backface_culling = True
    return m


def ufo(at=(0, 0, 0)):
    root = vk.empty("UFO", at)
    solid = vk.material("Voxel", rough=0.5)
    h = vk.build_mesh_merged("Hull", hull(), solid, root)
    vk.build_mesh("Alien", alien(), solid, root, seed=4, jitter=0.03)
    vk.build_mesh("Dome", dome(), glass_material(), root, seed=4, jitter=0.0, alpha=GLASS_ALPHA)
    return h


vk.reset()
h = ufo()
print("ufo hull polygons:", len(h.data.polygons))
vk.export(os.path.join(MODELS, "ufo_voxel.glb"))

# ---------------------------------------------------------------- review renders
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (1.75, 0, -0.1)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "ufo_front.png"), (0.0, -1.0, 0.13), (0.45, 0, 0.15), 3.6, 1100, 620)
pv.shoot(os.path.join(PREVIEW, "ufo_3q.png"), (0.5, -1.0, 0.5), (0, 0, 0.15), 2.6, 800, 620)
pv.shoot(os.path.join(PREVIEW, "ufo_under.png"), (0.4, -1.0, -0.6), (0, 0, 0.0), 2.6, 800, 620)
print("DONE voxel ufo")
