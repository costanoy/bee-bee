"""Bee Bee — the moon (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_moon.py -- <models_dir> <preview_dir>

A pale yellow ball of cubes, the same size as the low-poly moon it
replaces (radius 1 unit = 25 cubes), with craters scooped out of it all
the way round — the game spins it slowly, so there is no unseen side.
Each crater is a real dent with a darker floor and a light rim. The
surface colour varies in patches rather than per cube and equal faces
are merged (vk.build_mesh_merged), which keeps a ball of 65k cubes to a
few thousand polygons. Exports moon_voxel.glb and review renders (with
the voxel bee for scale).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

R = 25.0
SURFACE = [(1.0, 0.95, 0.74), (1.0, 0.97, 0.80), (0.97, 0.91, 0.69)]
MARE = (0.93, 0.86, 0.64)            # the big darker "seas"
FLOOR = (0.86, 0.78, 0.56)
FLOOR_DEEP = (0.79, 0.70, 0.50)
RIM = (1.0, 0.99, 0.88)


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def craters():
    """(direction, radius in cubes): a few big ones facing the camera at the
    start, the rest scattered over the whole ball without overlapping."""
    out = [(unit((-0.35, -1, 0.35)), 6.5), (unit((0.42, -1, -0.2)), 5.0), (unit((-0.1, -1, -0.5)), 3.5),
           (unit((0.45, -1, 0.5)), 3.0)]
    rng = random.Random(4)
    tries = 0
    while len(out) < 20 and tries < 2000:
        tries += 1
        d = unit((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        r = rng.choice([2.5, 3.0, 3.5, 4.5, 5.5])
        if all(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(d, o))))) * R > r + ro + 3.5 for o, ro in out):
            out.append((d, r))
    return out


def moon():
    cr = craters()
    maria = [(unit((0.2, -1, 0.1)), 13.0), (unit((-0.8, 0.5, -0.3)), 11.0), (unit((0.5, 0.9, 0.5)), 12.0)]
    vox = {}
    n = int(R) + 1
    for x in range(-n, n):
        for y in range(-n, n):
            for z in range(-n, n):
                p = (x + 0.5, y + 0.5, z + 0.5)
                d = math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2)
                if d > R:
                    continue
                c = None
                dug = False
                for cd, r in cr:
                    # a ball centred just above the surface scoops a shallow bowl
                    cc = tuple(k * (R + r * 0.45) for k in cd)
                    dd = math.sqrt(sum((a - b) ** 2 for a, b in zip(p, cc)))
                    if dd < r:
                        dug = True
                        break
                    if dd < r + 1.2:
                        c = FLOOR_DEEP if dd < r + 0.6 and d < R - r * 0.3 else FLOOR
                    elif dd < r + 2.6 and d > R - 1.6 and c is None:
                        c = RIM
                if dug:
                    continue
                if d < R - 4:
                    c = SURFACE[0]                           # the unseen core: one colour, merges away
                elif c is None:
                    u = unit(p)
                    if any(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(u, md))))) * R < mr
                           + 2.5 * (h(x // 3, y // 3, z // 3, 9) - 0.5) for md, mr in maria):
                        c = MARE
                    else:
                        c = SURFACE[int(h(x // 3, y // 3, z // 3, 5) * 3)]
                vox[(x, y, z)] = c
    return vox


vox = moon()
vk.reset()
root = vk.empty("Moon")
o = vk.build_mesh_merged("Moon", vox, vk.material("Voxel", rough=0.9), root)
print("moon cubes:", len(vox), "polygons:", len(o.data.polygons))
vk.export(os.path.join(MODELS, "moon_voxel.glb"))

# ---------------------------------------------------------------- review renders
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (0.8, 0.8, 0.8)
    bee.location = (1.75, 0, -0.6)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "moon_front.png"), (0.0, -1.0, 0.13), (0.45, 0, 0), 3.6, 1100, 800)
pv.shoot(os.path.join(PREVIEW, "moon_3q.png"), (0.6, -1.0, 0.45), (0, 0, 0), 2.5, 800, 800)
pv.shoot(os.path.join(PREVIEW, "moon_back.png"), (-0.5, 1.0, 0.3), (0, 0, 0), 2.5, 800, 800)
print("DONE voxel moon")
