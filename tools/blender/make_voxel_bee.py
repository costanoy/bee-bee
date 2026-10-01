"""Bee Bee — the bee as voxel art (a style test before converting the rest).

  blender --background --factory-startup --python make_voxel_bee.py -- <models_dir> <preview_dir>

Builds the bee cube by cube on a grid, shapes carved from simple volumes,
colour per voxel (with a slight per-cube jitter, the usual voxel-art
touch), only the faces that touch air kept. Wings are separate
translucent voxel slabs under "WingPivotL/R" hinges (rotate about X), eyes
sit under "LiveEyes", and an X-eyed variant under "DeadEyes".

Exports <models_dir>/bee_voxel.glb (vertex colours, flat faces) and
renders preview images to <preview_dir>.
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

V = 0.05                           # voxel edge, in game units (1 unit = 40 game px)
rng = random.Random(11)

YELLOW = (1.0, 0.74, 0.10)
YELLOW_LIGHT = (1.0, 0.88, 0.36)
DARK = (0.16, 0.10, 0.16)
FLUFF = (1.0, 0.93, 0.68)
EYE = (0.06, 0.04, 0.09)
WHITE = (1.0, 1.0, 1.0)
PINK = (1.0, 0.44, 0.56)
MOUTH = (0.45, 0.13, 0.18)
WING = (0.78, 0.92, 1.0)
WING_RIM = (0.95, 0.99, 1.0)

# Optional third argument "shining": the skin unlocked at score 300. Same
# bee, cube for cube, all in silver chrome. Chrome only reads as chrome if it
# mirrors something, so the mirror is painted on: a white sky highlight on
# top, a dark horizon line round the middle with a bright streak under it,
# and a paler ground reflection underneath. Stripes and antennae are
# near-black, the wings cool glass, and a few sparkles float around it under
# a "Sparkles" node. The game is meant to draw it unshaded, so the painted
# mirror stays crisp and it shines just as bright at night; unshaded, the
# game shows the stored colour as linear light, so glow() darkens the
# palette to make it come out on screen as written here (which is also why
# it looks dark in the Blender previews).
# Exports bee_voxel_shining.glb instead of bee_voxel.glb.
# A fourth argument "export_only" skips the review renders.
SHINING = len(ARGS) > 2 and ARGS[2] == "shining"
EXPORT_ONLY = "export_only" in ARGS
OUT_NAME = "bee_voxel_shining" if SHINING else "bee_voxel"


def glow(c):
    return tuple(v ** 2.2 for v in c)


# chrome from the top of a ball down to its underside: (lowest height above the middle, colour)
CHROME = [(6, glow((1.0, 1.0, 1.0))), (4, glow((0.80, 0.84, 0.90))), (2, glow((0.66, 0.70, 0.78))),
          (1, glow((0.52, 0.56, 0.64))), (-1, glow((0.30, 0.33, 0.41))), (-2, glow((0.96, 0.98, 1.0))),
          (-4, glow((0.46, 0.49, 0.56))), (-6, glow((0.60, 0.63, 0.69))), (-99, glow((0.74, 0.76, 0.80)))]
SPARKLE = (1.0, 1.0, 1.0)
SPARKLE_CORE = glow((0.86, 0.93, 1.0))
if SHINING:
    YELLOW = glow((0.64, 0.68, 0.76))
    DARK = glow((0.08, 0.09, 0.13))
    FLUFF = glow((0.96, 0.98, 1.0))
    EYE = glow((0.04, 0.04, 0.07))
    PINK = glow((0.92, 0.72, 0.82))
    MOUTH = glow((0.08, 0.09, 0.13))
    WING = glow((0.84, 0.91, 1.0))
    WING_RIM = (1.0, 1.0, 1.0)


def lin(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def ell(p, c, r):
    return sum(((p[i] - c[i]) / r[i]) ** 2 for i in range(3)) <= 1.0


# ---------------------------------------------------------------- the grid
def bee_voxels():
    """{(x, y, z): colour}. +X is the front, +Z up, -Y faces the camera."""
    vox = {}
    head_c, head_r = (9, 0, 3), (6.5, 6.5, 6.2)
    body_c, body_r = (-4, 0, 0), (10.5, 7.2, 7.2)
    for x in range(-18, 17):
        for y in range(-9, 10):
            for z in range(-9, 11):
                p = (x, y, z)
                if ell(p, head_c, head_r):
                    vox[p] = YELLOW
                elif ell(p, body_c, body_r):
                    # abdomen tapers towards the sting
                    if x < -10 and (y * y + z * z) > (7.2 - (-10 - x) * 0.9) ** 2:
                        continue
                    band = (-11 <= x <= -9) or (-5 <= x <= -3) or x <= -14
                    vox[p] = DARK if band else YELLOW
                elif ell(p, (2, 0, 1), (2.2, 6.4, 6.4)):
                    vox[p] = FLUFF
    # sting
    for x in range(-17, -14):
        vox[(x, 0, -1)] = DARK
    return vox


def face_voxels(vox):
    """Features painted onto the head's surface, per side."""
    live, dead = {}, {}
    for side in (-1, 1):
        # big eyes: tall ovals on the front-side of the head
        ec = (12.6, 4.4 * side, 4.6)
        for (x, y, z) in list(vox):
            if ell((x, y, z), ec, (2.1, 1.7, 2.9)) and _surface(vox, (x, y, z)):
                live[(x, y, z)] = EYE
        # catchlights: a bright 2x2 up-front, a single speck below
        for dx, dz in ((1, 6), (2, 6), (1, 5), (2, 5), (1, 3)):
            q = _surface_along(vox, (12 + dx, int(4.4 * side), dz), side)
            if q and q in live:
                live[q] = WHITE
        # cheeks
        for (x, y, z) in list(vox):
            if ell((x, y, z), (12, 5.8 * side, 0), (1.8, 1.4, 1.2)) and _surface(vox, (x, y, z)):
                vox[(x, y, z)] = PINK
        # X eyes for the dead pose
        for d in range(-2, 3):
            for sgn in (-1, 1):
                p = _surface_along(vox, (13 + d, int(3.6 * side), 5 + d * sgn), side)
                if p:
                    dead[p] = DARK
    # smile across the front
    for y in range(-2, 3):
        z = 0 if abs(y) < 2 else 1
        p = _front(vox, y, z)
        if p:
            vox[p] = MOUTH
    return live, dead


def _surface(vox, p):
    x, y, z = p
    return any(n not in vox for n in ((x + 1, y, z), (x - 1, y, z), (x, y + 1, z), (x, y - 1, z), (x, y, z + 1), (x, y, z - 1)))


def _surface_along(vox, p, side):
    """The outermost head voxel at (x, ?, z) on the given side."""
    x, _, z = p
    ys = [y for (vx, y, vz) in vox if vx == x and vz == z and y * side > 0]
    if not ys:
        return None
    y = max(ys) if side > 0 else min(ys)
    return (x, y, z)


def _front(vox, y, z):
    xs = [x for (x, vy, vz) in vox if vy == y and vz == z and x > 8]
    return (max(xs), y, z) if xs else None


def antenna_voxels():
    """Stalk + knob, every cube sharing a face with the next: cubes that only
    touch at an edge or corner read as separate floating bits."""
    vox = {}
    for side in (-1, 1):
        waypoints = [(9, 2 * side, 8), (9, 2 * side, 10), (11, 2 * side, 12), (13, 3 * side, 13), (15, 3 * side, 14)]
        x, y, z = waypoints[0]
        vox[(x, y, z)] = DARK
        for tx, ty, tz in waypoints[1:]:
            # walk one axis at a time so the path stays face-connected
            while (x, y, z) != (tx, ty, tz):
                if x != tx:
                    x += 1 if tx > x else -1
                elif z != tz:
                    z += 1 if tz > z else -1
                else:
                    y += 1 if ty > y else -1
                vox[(x, y, z)] = DARK
        # 2x2x2 knob butted right against the end of the stalk
        for dx in (1, 2):
            for dy in (0, side):
                for dz in (0, 1):
                    vox[(x + dx, y + dy, z + dz)] = DARK
    return vox


def wing_voxels(length, width):
    """A flat slab in the XZ plane from the hinge (origin) up and back."""
    vox = {}
    for x in range(-width, width + 1):
        for z in range(0, length + 1):
            u = z / length
            w = width * (0.45 + 0.55 * math.sin(math.pi * min(1.0, u * 0.95)))
            if abs(x + u * width * 0.6) <= w and u <= 1.0:
                edge = abs(x + u * width * 0.6) > w - 1.2 or z >= length - 1
                vox[(x, 0, z)] = WING_RIM if edge else WING
    return vox


def polish(vox):
    """Shining skin: paint the chrome's mirrored sky, horizon and ground by
    height — measured from the middle of the body, or from just under the
    eyes on the head, so each gets its own horizon line and the head's
    doesn't run through the eyes."""
    for (x, y, z), c in list(vox.items()):
        if c != YELLOW:
            continue
        rel = z - (1 if x >= 5 else 0)
        vox[(x, y, z)] = next(col for low, col in CHROME if rel >= low)


def sparkle_voxels(size):
    """A little star: a core with an arm out along each axis in the XZ plane."""
    vox = {(0, 0, 0): SPARKLE_CORE}
    for d in range(1, size + 1):
        for p in ((d, 0, 0), (-d, 0, 0), (0, 0, d), (0, 0, -d)):
            vox[p] = SPARKLE
    return vox


# ---------------------------------------------------------------- meshing
def build_mesh(name, vox, material, parent=None, loc=(0, 0, 0), alpha=1.0, offset=(0, 0, 0)):
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    verts = {}

    def vert(p):
        if p not in verts:
            verts[p] = bm.verts.new(((p[0] + offset[0]) * V, (p[1] + offset[1]) * V, (p[2] + offset[2]) * V))
        return verts[p]

    dirs = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
            ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
            ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
            ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
            ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
            ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]
    for (x, y, z), c in vox.items():
        j = 1.0 + rng.uniform(-0.045, 0.045)
        # the bmesh colour layer stores sRGB as-is: no linear conversion here
        cc = tuple(min(1.0, v * j) for v in c)
        for (dx, dy, dz), corners in dirs:
            if (x + dx, y + dy, z + dz) in vox:
                continue
            f = bm.faces.new([vert((x - 0.5 + a, y - 0.5 + b, z - 0.5 + cz)) for a, b, cz in corners])
            for l in f.loops:
                l[col] = (*cc, alpha)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def voxel_material(name, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.62
    if alpha < 1.0:
        nt.links.new(attr.outputs["Alpha"], p.inputs["Alpha"])
        m.surface_render_method = "BLENDED"
    return m


def empty(name, loc=(0, 0, 0), parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


# ---------------------------------------------------------------- build
bpy.ops.wm.read_factory_settings(use_empty=True)
solid = voxel_material("Voxel")
glass = voxel_material("VoxelWing", alpha=0.6)
root = empty("Bee")

body = bee_voxels()
if SHINING:
    polish(body)
live, dead = face_voxels(body)
body.update(antenna_voxels())
build_mesh("Body", body, solid, root)
face_mat = solid
eyes = empty("LiveEyes", parent=root)
build_mesh("Eyes", {p: c for p, c in live.items()}, face_mat, eyes, offset=(0, 0, 0))
dead_node = empty("DeadEyes", parent=root)
build_mesh("XEyes", dead, face_mat, dead_node)
# nudge painted features a hair outwards so they win over the head surface
for o in (eyes.children[0], dead_node.children[0]):
    me = o.data
    for v in me.vertices:
        v.co *= 1.004

fore, hind = wing_voxels(14, 4), wing_voxels(9, 3)
for side, tag in ((-1, "L"), (1, "R")):
    piv = empty("WingPivot" + tag, (1 * V, 5 * side * V, 6 * V), root)
    f = build_mesh("ForeWing", fore, glass, piv, alpha=0.6)
    f.rotation_euler = (0, math.radians(-30), 0)
    h = build_mesh("HindWing", hind, glass, piv, loc=(-2 * V, 0.02 * side, 0), alpha=0.6)
    h.rotation_euler = (0, math.radians(-62), 0)

if SHINING:
    sparkles = empty("Sparkles", parent=root)
    twinkle = voxel_material("VoxelSparkle")
    p = twinkle.node_tree.nodes["Principled BSDF"]
    p.inputs["Emission Color"].default_value = (0.90, 0.95, 1.0, 1)
    p.inputs["Emission Strength"].default_value = 1.5
    for i, (at, size) in enumerate((((-13, -9, 10), 2), ((6, -10, -8), 1), ((17, -8, 11), 1), ((-3, 9, 12), 2),
                                    ((-17, 8, -6), 1), ((11, 9, -9), 1))):
        build_mesh("Sparkle%d" % i, sparkle_voxels(size), twinkle, sparkles, loc=tuple(c * V for c in at))

dead_node.hide_render = False
bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, OUT_NAME + ".glb"), export_format="GLB", export_yup=True,
                          export_vertex_color="MATERIAL", export_cameras=False, export_lights=False)
print("EXPORTED", OUT_NAME)


if EXPORT_ONLY:
    print("DONE voxel bee (export only)")
    sys.exit(0)

# ---------------------------------------------------------------- preview renders
s = bpy.context.scene
s.render.engine = "BLENDER_EEVEE"
s.eevee.taa_render_samples = 96
for attr, val in (("use_gtao", True), ("gtao_distance", 0.4), ("use_shadows", True), ("use_raytracing", True)):
    if hasattr(s.eevee, attr):
        setattr(s.eevee, attr, val)
s.render.film_transparent = True
s.view_settings.view_transform = "Standard"
s.view_settings.look = "None"
world = bpy.data.worlds.new("W")
s.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (*lin((0.62, 0.78, 1.0)), 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.85
for name, rot, energy, color in (("Key", (-45, -35, 0), 3.9, (1.0, 0.97, 0.90)), ("Rim", (-30, 150, 0), 1.8, (0.72, 0.86, 1.0))):
    L = bpy.data.lights.new(name, "SUN")
    L.energy = energy
    L.color = color
    L.angle = math.radians(6)
    lo = bpy.data.objects.new(name, L)
    s.collection.objects.link(lo)
    lo.rotation_euler = tuple(math.radians(a) for a in rot)
cd = bpy.data.cameras.new("Cam")
cd.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cd)
s.collection.objects.link(cam)
s.camera = cam


def shoot(name, direction, scale=2.4, res=900, target=(0.05, 0, 0.1)):
    d = Vector(direction).normalized()
    cam.location = Vector(target) + d * 12
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cd.ortho_scale = scale
    s.render.resolution_x = s.render.resolution_y = res
    s.render.filepath = os.path.join(PREVIEW, name + ".png")
    bpy.ops.render.render(write_still=True)


def wings(a):
    for side, tag in ((-1, "L"), (1, "R")):
        bpy.data.objects["WingPivot" + tag].rotation_euler = (math.radians(a) * side * -1, 0, 0)


dead_node.hide_render = True
for c in dead_node.children:
    c.hide_render = True
wings(18)
shoot("hero_3q", (0.75, -1.0, 0.45))
shoot("game_side", (0.12, -1.0, 0.12))
shoot("front", (1.0, -0.35, 0.2))
for i, a in enumerate((18, 60, 105, 60)):
    wings(a)
    shoot("flap_%d" % i, (0.45, -1.0, 0.3), res=500)
wings(15)
for i in range(16):
    ang = 2 * math.pi * i / 16
    shoot("turn_%02d" % i, (math.cos(ang), math.sin(ang), 0.35), res=420)
eyes.hide_render = True
for c in eyes.children:
    c.hide_render = True
dead_node.hide_render = False
for c in dead_node.children:
    c.hide_render = False
wings(120)
root.rotation_euler = (math.radians(180), 0, 0)
shoot("dead", (0.5, 1.0, -0.3), res=500)
print("DONE voxel bee")
