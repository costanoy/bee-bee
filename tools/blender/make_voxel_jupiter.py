"""Bee Bee — Jupiter (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_jupiter.py -- <models_dir> <preview_dir>

A ball of cubes in clean bands of cream, sand, tan and soft rust, built
at its in-game size (radius 1.25 units = 31 cubes; a voxel model can't
be scaled without breaking the shared cube size) and used unscaled. The
two dark belts either side of the bright equator have gently waving
edges; the Great Red Spot sits in a notch below the southern belt, a
soft brick-coloured oval with a darker core and a cream ring, and a
little string of white ovals runs round the south. The game spins it
about its vertical axis and draws it unshaded, so the bands go all the
way round and the light is painted from straight above, the one light
that stays put while it turns: a lighter north, a deeper south and cool
grey-violet poles. Muted on purpose (STYLE.md, mid layer): it must not
compete with the red and yellow flowers.

A ball of single cubes this size costs about 21k triangles, so it is
built of 2x2x2 macro cubes (STYLE.md: "design in 2x2 macro cubes"),
still on the shared grid; only the outer shell is generated and equal
faces are merged watertight (vk.build).
Exports jupiter_voxel.glb and review renders in the colours the game
shows (with the voxel bee for scale).
"""
import bpy, math, sys, os
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


R = 31.0                     # radius in cubes
M = 2                        # the macro cube, in cubes
RM = R / M                   # radius in macro cubes

# on screen (STYLE.md, "Mid layer": cooler and softer than the flowers)
CREAM = (0.98, 0.92, 0.80)
SAND = (0.94, 0.82, 0.65)
TAN = (0.88, 0.67, 0.50)
RUST = (0.83, 0.54, 0.41)
RUST_EDGE = (0.73, 0.44, 0.36)     # the lower edge of the belts
POLE = (0.76, 0.72, 0.80)
SPOT = (0.88, 0.50, 0.40)
SPOT_CORE = (0.78, 0.40, 0.35)
SPOT_RING = (1.0, 0.93, 0.82)
OVAL = (0.98, 0.95, 0.90)

# bands from the north pole down: (lowest macro row of the band, colour,
# waviness of its lower edge in macro cubes)
BANDS = [(12, POLE, 0), (10, TAN, 0), (6, CREAM, 0), (2, RUST, 1), (-2, CREAM, 1), (-6, RUST, 0),
         (-10, SAND, 0), (-12, TAN, 0), (-99, POLE, 0)]
SPOT_LON = math.radians(-128)        # facing the camera as the mock shows it (turned 0.75 rad)
SPOT_Z = -8.0                        # height of its centre, in macro cubes
SPOT_SIZE = (4.6, 2.3)               # half-width along the surface, half-height
OVALS = [(SPOT_LON + math.radians(a), -10.5) for a in (75, 120, 165, 230, 290)]


def lon_of(p):
    return math.atan2(p[1], p[0])


def surface_dist(lon, lon0, z):
    """Distance round the ball (in macro cubes) from lon0 to lon at height z."""
    dl = (lon - lon0 + math.pi) % (2 * math.pi) - math.pi
    return dl * math.sqrt(max(0.0, RM * RM - z * z))


def band(zc, lon):
    for i, (lo, c, wave) in enumerate(BANDS):
        edge = lo
        if wave:
            # a slow wave round the planet: 4 crests, one macro cube high
            edge += round(wave * 0.8 * math.sin(4 * lon + i))
        if zc >= edge:
            return RUST_EDGE if c == RUST and zc < edge + 1 else c
    return POLE


def colour(X, Y, Z):
    p = (X, Y, Z)
    lon = lon_of(p)
    zc = p[2]
    # the Great Red Spot, with the southern belt bending round it
    u = surface_dist(lon, SPOT_LON, zc) / SPOT_SIZE[0]
    v = (zc - SPOT_Z) / SPOT_SIZE[1]
    s = u * u + v * v
    if s < 0.30:
        c = SPOT_CORE
    elif s < 1.0:
        c = SPOT
    elif s < 1.9:
        c = SPOT_RING
    elif any(abs(surface_dist(lon, ol, zc)) < 1.6 and abs(zc - oz) < 0.9 for ol, oz in OVALS):
        c = OVAL
    else:
        c = band(zc, lon)
    # the painted light from above, one tone per macro row: a lighter
    # north, a deeper south
    t = zc / RM
    k = 0.04 * t if t > 0 else 0.16 * t
    if t < -0.55:
        k -= 0.04
    return glow(vk.shade(c, k))


def inside(X, Y, Z):
    """Macro cube (X, Y, Z) is the 2x2x2 block of cubes centred on the cube
    corner (2X, 2Y, 2Z): the ball is 2 * int(RM) + 1 macro cubes across,
    which keeps it as wide as the ball of single cubes it replaces."""
    return X * X + Y * Y + Z * Z <= RM * RM


def jupiter():
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


vox = jupiter()
vk.reset()
root = vk.empty("Jupiter")
# no painted face light (faces=None): seen from below or above, the
# terraces of a ball would show it as stripes round the poles
o = vk.build("Jupiter", vox, vk.material("Voxel", rough=0.8), root, faces=None,
             solid=lambda x, y, z: inside((x + 1) // M, (y + 1) // M, (z + 1) // M))
print("jupiter cubes:", len(vox))
vk.report("jupiter", root, budget=8000)
vk.export(os.path.join(MODELS, "jupiter_voxel.glb"))

# ---------------------------------------------------------------- review renders
in_game_colours(root)
bee_glb = os.path.join(MODELS, "bee_voxel.glb")
if not os.path.exists(bee_glb):
    bee_glb = "C:/jtmp/bb/before/models/bee_voxel.glb"
try:
    bpy.ops.import_scene.gltf(filepath=bee_glb)
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
root.rotation_euler = (0, 0, 0.75)              # as the game mock shows it
pv.shoot(os.path.join(PREVIEW, "jupiter_turned.png"), (0.0, -1.0, 0.13), (0, 0, 0), 3.0, 800, 800)
root.rotation_euler = (0, 0, 0)
pv.shoot(os.path.join(PREVIEW, "jupiter_3q.png"), (0.6, -1.0, 0.45), (0, 0, 0), 3.0, 800, 800)
pv.shoot(os.path.join(PREVIEW, "jupiter_back.png"), (-0.5, 1.0, 0.3), (0, 0, 0), 3.0, 800, 800)
print("DONE voxel jupiter")
