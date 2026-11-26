"""Bee Bee — the moon (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_moon.py -- <models_dir> <preview_dir>

A soft, pale ball the same size as before (radius 1 unit = 25 cubes),
with a few big round craters all the way round — the game spins it
slowly, so there is no unseen side. The game draws it unshaded, so all
its light is painted, and painted from straight above: that is the one
light that stays put while the ball turns about its vertical axis. The
upper two thirds are a warm cream (no butter yellow: that is the lemon
flower's), and only the lower third cools to lavender. Each crater is
painted as a ring: its floor one step deeper than the ground round it,
its upper wall in shade and its lower rim, one macro cube wide, catching
the light, so it reads as a dent from any side, like the old moon's.
Soft on purpose (STYLE.md, mid layer): it must not compete with the
lemon-yellow flower.

A ball of single cubes this size costs about 13k triangles even in one
colour, so the ball is built of 2x2x2 macro cubes (STYLE.md: "design in
2x2 macro cubes"), still on the shared grid; equal faces are merged
watertight (vk.build). Exports moon_voxel.glb and review renders in the
colours the game shows (with the voxel bee for scale).
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

# The game draws the sky bodies unshaded, through its Filmic tone mapping:
# a stored value s shows on screen as SCREEN(s), the same by day, at dusk
# and at night (measured per channel on grey swatches in the game's look).
# Mid tones come out lighter, and darks under 0.06 are crushed to black.
# glow() turns a colour as it should show on screen into the value to store,
# so every palette below is written as the screen will show it.
SCREEN = ((0.0, 0.0), (0.05, 0.01), (0.10, 0.10), (0.15, 0.165), (0.20, 0.228), (0.25, 0.296),
          (0.30, 0.37), (0.35, 0.445), (0.40, 0.506), (0.46, 0.584), (0.52, 0.655), (0.58, 0.718),
          (0.64, 0.773), (0.70, 0.824), (0.76, 0.867), (0.82, 0.906), (0.88, 0.941), (0.94, 0.973), (1.0, 1.0))


def glow(c):
    out = []
    for v in c[:3]:
        for (s0, v0), (s1, v1) in zip(SCREEN, SCREEN[1:]):
            if v <= v1:
                out.append(s0 + (s1 - s0) * max(0.0, v - v0) / (v1 - v0))
                break
        else:
            out.append(1.0)
    return tuple(out) + tuple(c[3:])


def screen(s):
    """The other way round: what a stored colour shows as (for the previews)."""
    out = []
    for v in s[:3]:
        for (s0, v0), (s1, v1) in zip(SCREEN, SCREEN[1:]):
            if v <= s1:
                out.append(v0 + (v1 - v0) * (v - s0) / (s1 - s0))
                break
        else:
            out.append(1.0)
    return tuple(out)


R = 25.0                     # radius in cubes
M = 2                        # the macro cube, in cubes
RM = R / M                   # radius in macro cubes

# lit from above, by height on the ball (on screen): a cream cap and body
# over the upper two thirds, then lavender in the lower third only
BANDS = [(0.55, (1.0, 0.97, 0.88)), (-0.33, (1.0, 0.96, 0.84)), (-0.50, (0.93, 0.90, 0.90)),
         (-0.70, (0.86, 0.84, 0.93)), (-2.0, (0.79, 0.77, 0.90))]
FLOOR = (0.92, 0.86, 0.76)       # a crater floor: one step deeper than the ground round it
WALL = (0.82, 0.75, 0.71)        # its upper wall, in shade
LIT = (1.0, 1.0, 0.97)           # its lower rim, catching the light
def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def dot(a, b):
    return sum(i * j for i, j in zip(a, b))


def craters():
    """(direction, radius in macro cubes): three facing the camera at the
    start (and as the game mock shows it, turned 0.75 rad), the rest
    scattered over the whole ball, well apart, so four or five show at a
    time. Big on purpose: a ring under 3 macro cubes reads as a blob."""
    out = [(unit((-0.40, -1, 0.38)), 4.4), (unit((0.50, -1, -0.10)), 3.6),
           (unit((-0.32, -1, -0.55)), 3.2)]
    rng = random.Random(4)
    tries = 0
    while len(out) < 8 and tries < 4000:
        tries += 1
        d = unit((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * 0.8))
        r = rng.choice([3.4, 3.8, 4.2])
        if all(math.acos(max(-1.0, min(1.0, dot(d, o)))) * RM > r + ro + 3.0 for o, ro in out):
            out.append((d, r))
    return out


CR = craters()


def ground(z):
    """The band of the ball at height z (of a unit vector)."""
    for z0, c in BANDS:
        if z > z0:
            return c
    return BANDS[-1][1]


def deeper(c, t):
    """c taken toward t by the same step it would take from the cream body:
    so a floor in the lavender third is a deeper lavender, not a cream."""
    body = BANDS[1][1]
    return tuple(min(1.0, max(0.0, ci + ti - bi)) for ci, ti, bi in zip(c, t, body))


def colour(X, Y, Z):
    """The paint of one macro cube. The ball itself is smooth (dents this
    small come out ragged in macro cubes); the craters are painted, round
    on the surface, so they foreshorten toward the edge like real ones."""
    u = unit((X, Y, Z))
    c = ground(u[2])
    for cd, r in CR:
        a = math.acos(max(-1.0, min(1.0, dot(u, cd)))) * RM
        if a >= r + 1.0:
            continue
        # height on the surface above the crater's centre, in macro cubes
        up = unit(tuple((0, 0, 1)[i] - cd[i] * cd[2] for i in range(3)))
        v = dot(tuple(u[i] - cd[i] for i in range(3)), up) * RM
        if a >= r:
            if v < 0.2 * r:
                c = LIT                                 # the lower rim, lit, one macro cube wide
            else:
                c = vk.mix(c, LIT, 0.5)                 # the rest of the ring, softly
        elif a >= r - 1.2 and v > 0.3 * r:
            c = deeper(c, WALL)                         # the upper wall, in shade
        else:
            c = deeper(c, FLOOR)                        # the floor
        break
    return glow(c)


def inside(X, Y, Z):
    """Macro cube (X, Y, Z) is the 2x2x2 block of cubes centred on the cube
    corner (2X, 2Y, 2Z): the ball is 2 * int(RM) + 1 macro cubes across,
    which keeps it as wide as the ball of single cubes it replaces."""
    return X * X + Y * Y + Z * Z <= RM * RM


def moon():
    """{cube: colour} for the outer shell of macro cubes."""
    n = int(RM) + 2
    vox = {}
    for X in range(-n, n):
        for Y in range(-n, n):
            for Z in range(-n, n):
                if not inside(X, Y, Z) or all(inside(X + a, Y + b, Z + c) for a, b, c in
                                              ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))):
                    continue
                c = colour(X, Y, Z)
                for i in range(M):
                    for j in range(M):
                        for k in range(M):
                            vox[(X * M - 1 + i, Y * M - 1 + j, Z * M - 1 + k)] = c
    return vox


# No painted face light (vk.FACE_LIGHT): seen from below or above, the
# terraces of a ball would show it as stripes round the poles.
FACES = None


def in_game_colours(root):
    """For the review renders: every mesh under root shows its colours as
    the game shows them (unshaded: an emission of the screen colour)."""
    m = bpy.data.materials.new("InGame")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    a = nt.nodes.new("ShaderNodeVertexColor")
    a.layer_name = "Col"
    e = nt.nodes.new("ShaderNodeEmission")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(a.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    todo = [root]
    while todo:
        ob = todo.pop()
        todo.extend(ob.children)
        if ob.type != "MESH":
            continue
        col = ob.data.color_attributes["Col"]
        for d in col.data:
            s = d.color_srgb
            d.color_srgb = screen(s) + (s[3],)
        ob.data.materials.clear()
        ob.data.materials.append(m)


vox = moon()
vk.reset()
root = vk.empty("Moon")
o = vk.build("Moon", vox, vk.material("Voxel", rough=0.9), root, faces=FACES,
             solid=lambda x, y, z: inside((x + 1) // M, (y + 1) // M, (z + 1) // M))
print("moon cubes:", len(vox), "craters:", len(CR))
vk.report("moon", root, budget=8000)
vk.export(os.path.join(MODELS, "moon_voxel.glb"))

# ---------------------------------------------------------------- review renders
in_game_colours(root)
bee_glb = os.path.join(MODELS, "bee_voxel.glb")
if not os.path.exists(bee_glb):
    bee_glb = "C:/jtmp/bb/before/models/bee_voxel.glb"
try:
    bpy.ops.import_scene.gltf(filepath=bee_glb)
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (1.75, 0, -0.6)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "moon_front.png"), (0.0, -1.0, 0.13), (0.45, 0, 0), 3.6, 1100, 800)
root.rotation_euler = (0, 0, 0.75)              # as the game mock shows it
pv.shoot(os.path.join(PREVIEW, "moon_turned.png"), (0.0, -1.0, 0.13), (0, 0, 0), 2.5, 800, 800)
root.rotation_euler = (0, 0, 0)
pv.shoot(os.path.join(PREVIEW, "moon_3q.png"), (0.6, -1.0, 0.45), (0, 0, 0), 2.5, 800, 800)
pv.shoot(os.path.join(PREVIEW, "moon_back.png"), (-0.5, 1.0, 0.3), (0, 0, 0), 2.5, 800, 800)
print("DONE voxel moon")
