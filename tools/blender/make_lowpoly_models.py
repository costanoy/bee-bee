"""Bee Bee — low-poly 3D models for the real-time 3D view, exported as glTF.

  blender --background --factory-startup --python make_lowpoly_models.py -- <models_dir> [only,names]

Conventions (the Godot side, scripts/view3d.gd, relies on these):
  * 1 unit = 40 game px. Blender -Y faces the camera (becomes glTF +Z).
  * Flat-shaded low-poly facets, matte colours, no outlines — the look
    comes from the real-time light and shadow in Godot.
  * Animated parts are separate named nodes: bee "WingPivotL/R" (hinge
    along the body, rotate about X) and "DeadEyes" (hidden until death);
    gull "WingPivotL/R".
  * The bee and gull face +X (right).
  * hedge_*.glb spans x 0..1 exactly (nothing pokes past it, so bars can
    end flush at the gap edge), centred on the collision band at z=0.
  * ground.glb's grass top is at z=0 (the surface the bee stands on).

(Blender may crash while exiting in background mode after the files are
written — harmless.)
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGS[0]
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 else None
os.makedirs(OUT, exist_ok=True)


def lin(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


# ---------------------------------------------------------------- basics
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    return bpy.context.scene.collection


MATS = {}


def mat(name, color, rough=0.75, alpha=1.0, emit=0.0, metal=0.0):
    key = (name, color, rough, alpha, emit)
    if key in MATS and MATS[key].name in bpy.data.materials:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*lin(color), 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if alpha < 1:
        p.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if emit:
        p.inputs["Emission Color"].default_value = (*lin(color), 1)
        p.inputs["Emission Strength"].default_value = emit
    MATS[key] = m
    return m


def obj_from(name, bm, material, parent=None, loc=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if isinstance(material, list):
        for m in material:
            me.materials.append(m)
    else:
        me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def empty(name, loc=(0, 0, 0), parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def ico(name, loc, scale, material, subdiv=1, parent=None, jitter=0.0, seed=0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    if jitter:
        rnd = random.Random(seed)
        for v in bm.verts:
            v.co *= 1 + rnd.uniform(-jitter, jitter)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return obj_from(name, bm, material, parent, loc)


def cone(name, loc, r1, r2, depth, material, segs=6, rot=(0, 0, 0), parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    o = obj_from(name, bm, material, parent, loc)
    o.rotation_euler = rot
    return o


def box(name, loc, size, material, parent=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    return obj_from(name, bm, material, parent, loc)


def lathe(name, profile, material, segs=8, parent=None, loc=(0, 0, 0), stripe=None):
    """Revolve [(x, r)] around X. stripe(x) -> material index per face."""
    bm = bmesh.new()
    rings = [[bm.verts.new((x, r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs)))
              for k in range(segs)] for x, r in profile]
    for i in range(len(rings) - 1):
        for k in range(segs):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
            if stripe:
                f.material_index = stripe((profile[i][0] + profile[i + 1][0]) / 2)
    for ring, (x, _) in ((rings[0], profile[0]), (rings[-1], profile[-1])):
        c = bm.verts.new((x, 0, 0))
        for k in range(segs):
            f = bm.faces.new((ring[k], ring[(k + 1) % segs], c))
            if stripe:
                f.material_index = stripe(x)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from(name, bm, material, parent, loc)


def flat_poly(name, pts, material, parent=None, loc=(0, 0, 0), thick=0.03):
    """A thin slab from a 2D outline in the XZ plane (wings, petals, leaves)."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -thick / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, thick / 2, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        bm.faces.new((front[i], back[i], back[(i + 1) % n], front[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from(name, bm, material, parent, loc)


def oval(length, width, n=8, root_taper=0.55):
    """Outline from the root (origin) out along +Z, narrower at the root."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        z = length * 0.5 * (1 - math.cos(t))
        w = width * 0.5 * math.sin(t) * (root_taper + (1 - root_taper) * min(1.0, z / length * 1.6))
        pts.append((w, z))
    return pts


def join_by_parent():
    """Merge sibling meshes into one per parent (root, each wing pivot,
    DeadEyes...). Cuts a hedge segment from ~30 draw calls to one per
    material, while the named animated nodes stay separate."""
    groups = {}
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            groups.setdefault(o.parent, []).append(o)
    for objs in groups.values():
        if len(objs) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()


def export(name):
    join_by_parent()
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              use_selection=False, export_cameras=False, export_lights=False)
    print("EXPORTED", name)


# ---------------------------------------------------------------- palette
YELLOW = (1.0, 0.78, 0.18)
DARK = (0.20, 0.13, 0.20)
WHITE = (1.0, 1.0, 1.0)
PINK = (1.0, 0.55, 0.62)
GREENS = [(0.36, 0.72, 0.28), (0.46, 0.80, 0.32), (0.28, 0.60, 0.26)]
DEEP_GREEN = (0.16, 0.42, 0.20)
ROSE = (1.0, 0.30, 0.42)
ROSE_DEEP = (0.82, 0.12, 0.30)


# ---------------------------------------------------------------- bee
def bee():
    reset()
    root = empty("Bee")
    yellow, dark = mat("BeeYellow", YELLOW, 0.55), mat("BeeDark", DARK, 0.5)
    eye_m = mat("Eye", (0.08, 0.06, 0.12), 0.25)
    shine = mat("Shine", WHITE, 0.3, emit=0.6)
    cheek = mat("Cheek", PINK, 0.8)
    wing_m = mat("Wing", (0.85, 0.95, 1.0), 0.2, alpha=0.55)

    def stripe(x):
        return 1 if (-0.40 < x < -0.26) or (-0.15 < x < -0.02) or x < -0.52 else 0

    prof = [(-0.62, 0.02), (-0.56, 0.14), (-0.46, 0.26), (-0.32, 0.34), (-0.16, 0.37), (0.0, 0.35), (0.14, 0.29), (0.24, 0.18), (0.28, 0.04)]
    body = lathe("Body", prof, [yellow, dark], segs=10, parent=root, stripe=stripe)
    body.rotation_euler = (0, math.radians(8), 0)
    hc = Vector((0.46, 0, 0.1))
    ico("Head", hc, (0.31, 0.30, 0.29), yellow, 2, root)
    ico("Fluff", (0.26, 0, 0.04), (0.14, 0.27, 0.27), mat("Fluff", (1.0, 0.9, 0.6)), 1, root)
    dead = empty("DeadEyes", (0, 0, 0), root)
    for side in (-1, 1):
        d = Vector((0.62, 0.62 * side, 0.22)).normalized()
        e = hc + d * 0.27
        ico("Eye", e, (0.075, 0.075, 0.1), eye_m, 1, root)
        ico("Shine", e + d * 0.05 + Vector((0.0, 0, 0.04)), (0.028,) * 3, shine, 1, root)
        ico("Cheek", hc + Vector((0.15, 0.25 * side, -0.1)), (0.06, 0.03, 0.045), cheek, 1, root)
        for s in (-1, 1):   # an X per eye, shown only when dead
            b = box("X", e + d * 0.04, (0.02, 0.02, 0.17), dark, dead)
            b.rotation_euler = (0, math.radians(45 * s), 0)
            b.rotation_mode = "XYZ"
        # antennae
        base = hc + Vector((0.02, 0.1 * side, 0.26))
        a = cone("Antenna", base + Vector((0.08, 0.02 * side, 0.14)), 0.02, 0.02, 0.3, dark, 5, (0, math.radians(30), 0), root)
        ico("AntTip", base + Vector((0.17, 0.04 * side, 0.29)), (0.05,) * 3, dark, 1, root)
        # legs
        for x in (-0.18, 0.0, 0.16):
            cone("Leg", (x, 0.13 * side, -0.33), 0.022, 0.018, 0.16, dark, 5, (math.radians(20 * side), math.radians(-15), 0), root)
    cone("Sting", (-0.68, 0, -0.05), 0.06, 0.0, 0.16, dark, 6, (0, math.radians(-90), 0), root)
    # wings: hinge along the body top, fore + hind wing per side
    for side, tag in ((-1, "L"), (1, "R")):
        piv = empty("WingPivot" + tag, (0.02, 0.12 * side, 0.3), root)
        f = flat_poly("ForeWing", oval(0.62, 0.34, 10), wing_m, piv)
        f.rotation_euler = (0, math.radians(-32), 0)
        h = flat_poly("HindWing", oval(0.42, 0.24, 8), wing_m, piv, loc=(-0.06, 0.01 * side, 0))
        h.rotation_euler = (0, math.radians(-62), 0)
    export("bee")


# ---------------------------------------------------------------- hedge segments
def rose_head(loc, s, parent):
    c = Vector(loc)
    ico("RoseCore", c, (0.05 * s, 0.05 * s, 0.05 * s), mat("RoseDeep", ROSE_DEEP), 1, parent)
    for k in range(5):
        a = 2 * math.pi * k / 5
        ico("Petal", c + Vector((math.cos(a) * 0.06 * s, 0.02, math.sin(a) * 0.06 * s)), (0.055 * s, 0.03 * s, 0.05 * s),
            mat("Rose", ROSE, 0.6), 1, parent)


def hedge(variant, seed):
    reset()
    rnd = random.Random(seed)
    root = empty("Hedge")
    greens = [mat("Leaf%d" % i, c) for i, c in enumerate(GREENS)]
    # an unbroken core with flat ends, so segments laid side by side read as
    # one continuous bush (a bevelled box made each segment a separate pillow)
    core = lathe("Core", [(0.0, 0.27), (0.25, 0.28), (0.5, 0.27), (0.75, 0.28), (1.0, 0.27)],
                 mat("HedgeCore", DEEP_GREEN), 8, root, loc=(0, 0.08, 0))
    core.scale = (1.0, 0.95, 1.0)
    for i in range(7):
        r = rnd.uniform(0.2, 0.27)
        x = rnd.uniform(r, 1 - r)
        z = rnd.uniform(-0.12, 0.12)
        ico("Clump", (x, rnd.uniform(-0.12, 0.08), z), (r, r * 0.9, r * rnd.uniform(0.85, 1.05)), rnd.choice(greens), 1, root,
            jitter=0.12, seed=seed * 10 + i)
    for i in range(10):   # small leaf facets breaking up the silhouette
        x = rnd.uniform(0.08, 0.92)
        z = rnd.choice([-1, 1]) * rnd.uniform(0.2, 0.34)
        l = ico("LeafBit", (x, rnd.uniform(-0.2, 0.05), z), (0.07, 0.04, 0.05), rnd.choice(greens), 1, root)
        l.rotation_euler = (0, rnd.uniform(0, 3.14), 0)
    for i in range(rnd.choice([1, 2, 2])):
        rose_head((rnd.uniform(0.2, 0.8), -0.3, rnd.uniform(-0.12, 0.12)), rnd.uniform(1.0, 1.25), root)
    export("hedge_%s" % variant)


# ---------------------------------------------------------------- flowers
def flower(name, petal, centre, n, plen, pw):
    reset()
    root = empty("Flower")
    pm = mat(name + "Petal", petal, 0.55)
    pm2 = mat(name + "Petal2", tuple(v * 0.88 for v in petal), 0.6)
    for ring, (off, tilt, sc, m) in enumerate(((0.0, 14, 1.0, pm2), (math.pi / n, 26, 0.86, pm))):
        for k in range(n):
            a = 2 * math.pi * k / n + off
            p = flat_poly("Petal", oval(plen * sc, pw * sc, 8, 0.35), m, root, thick=0.05)
            p.location = (math.cos(a) * 0.05, -0.03 * ring, math.sin(a) * 0.05)
            p.rotation_mode = "XYZ"
            p.rotation_euler = (math.radians(tilt), math.pi / 2 - a, 0)
    ico("Centre", (0, -0.08, 0), (0.14, 0.08, 0.14), mat(name + "Centre", centre, 0.5), 1, root)
    for side in (-1, 1):
        lf = flat_poly("Leaf", oval(0.32, 0.16, 8, 0.3), mat("FlowerLeaf", GREENS[0]), root, thick=0.03)
        lf.location = (0.03 * side, 0.06, -0.14)
        lf.rotation_euler = (0, math.radians(180 - 60 * side), 0)
    export(name)


# ---------------------------------------------------------------- cloud, gull
def cloud(variant, puffs):
    reset()
    root = empty("Cloud")
    m = mat("Cloud", (1.0, 1.0, 1.0), 0.95)
    for i, (x, z, r) in enumerate(puffs):
        ico("Puff", (x, 0, z), (r, r * 0.8, r * 0.85), m, 1, root, jitter=0.08, seed=i + len(variant))
    box("Base", (0, 0, -0.18), (1.5, 0.6, 0.22), m, root, bevel=0.1)
    export("cloud_%s" % variant)


def gull():
    reset()
    root = empty("Gull")
    white, grey = mat("GullWhite", (0.98, 0.98, 1.0), 0.8), mat("GullGrey", (0.66, 0.72, 0.84), 0.8)
    tip = mat("GullTip", (0.22, 0.24, 0.32))
    prof = [(-0.38, 0.02), (-0.26, 0.09), (-0.05, 0.13), (0.14, 0.12), (0.26, 0.07), (0.32, 0.02)]
    lathe("Body", prof, white, 8, root)
    ico("Head", (0.32, 0, 0.07), (0.11, 0.1, 0.1), white, 1, root)
    cone("Beak", (0.46, 0, 0.05), 0.035, 0.0, 0.14, mat("Beak", (1.0, 0.64, 0.16)), 5, (0, math.radians(90), 0), root)
    for side in (-1, 1):
        ico("Eye", (0.38, 0.075 * side, 0.1), (0.022,) * 3, mat("GEye", (0.05, 0.05, 0.08)), 1, root)
    t = flat_poly("Tail", [(0.0, 0.0), (-0.07, 0.16), (0.0, 0.12), (0.07, 0.16)], white, root)
    t.location = (-0.36, 0, 0.0)
    t.rotation_euler = (0, math.radians(-90), 0)
    for side, tag in ((-1, "L"), (1, "R")):
        piv = empty("WingPivot" + tag, (0.02, 0.08 * side, 0.08), root)
        w = flat_poly("Wing", [(-0.12, 0.0), (0.12, 0.0), (0.16, 0.25), (0.10, 0.55), (-0.02, 0.62), (-0.14, 0.3)], grey, piv)
        w.rotation_euler = (math.radians(90 * side), 0, 0)   # spread sideways from the body
        tp = flat_poly("WingTip", [(0.05, 0.42), (0.12, 0.5), (0.02, 0.63), (-0.06, 0.56)], tip, piv, thick=0.035)
        tp.rotation_euler = (math.radians(90 * side), 0, 0)
    export("gull")


# ---------------------------------------------------------------- celestials
def moon():
    reset()
    root = empty("Moon")
    ico("Moon", (0, 0, 0), (1, 1, 1), mat("Moon", (1.0, 0.95, 0.74), 0.9), 2, root, jitter=0.03, seed=3)
    for d, r in (((-0.35, -1, 0.35), 0.24), ((0.4, -1, -0.2), 0.18), ((-0.1, -1, -0.45), 0.13), ((0.45, -1, 0.45), 0.1)):
        n = Vector(d).normalized()
        c = ico("Crater", n * 0.93, (r, 0.1, r), mat("Crater", (0.88, 0.8, 0.58), 0.95), 1, root)
        c.rotation_mode = "QUATERNION"
        c.rotation_quaternion = n.to_track_quat("Y", "Z")
    export("moon")


def jupiter():
    reset()
    root = empty("Jupiter")
    cols = [mat("J%d" % i, c, 0.8) for i, c in enumerate(((0.98, 0.84, 0.62), (0.9, 0.58, 0.34), (1.0, 0.92, 0.74), (0.82, 0.48, 0.3)))]
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    for f in bm.faces:
        z = f.calc_center_median().z
        f.material_index = int((z + 1) * 4.5) % 4
    obj_from("Jupiter", bm, cols, root)
    n = Vector((0.3, -1, -0.28)).normalized()
    s = ico("Spot", n * 0.96, (0.22, 0.08, 0.13), mat("Spot", (0.88, 0.34, 0.24), 0.8), 1, root)
    s.rotation_mode = "QUATERNION"
    s.rotation_quaternion = n.to_track_quat("Y", "Z")
    export("jupiter")


def ufo():
    reset()
    root = empty("UFO")
    bm = bmesh.new()
    prof = [(-0.3, 0.05), (-0.22, 0.8), (-0.08, 1.35), (0.04, 1.4), (0.16, 1.0), (0.26, 0.4), (0.3, 0.05)]
    o = lathe("Saucer", prof, mat("Hull", (0.78, 0.82, 0.96), 0.35, metal=0.3), 12, root)
    o.rotation_euler = (0, math.radians(-90), 0)   # revolve axis X -> Z
    ico("Dome", (0, 0, 0.3), (0.66, 0.66, 0.55), mat("Glass", (0.6, 0.95, 0.9), 0.1, alpha=0.5), 2, root)
    ico("Alien", (0, 0, 0.4), (0.26, 0.24, 0.28), mat("Alien", (0.5, 0.9, 0.4), 0.6), 1, root)
    for s in (-1, 1):
        ico("AlienEye", (0.09 * s, -0.2, 0.46), (0.05, 0.03, 0.07), mat("AEye", (0.05, 0.05, 0.08), 0.3), 1, root)
    for k in range(8):
        a = 2 * math.pi * k / 8
        ico("Lamp", (1.18 * math.cos(a), 1.18 * math.sin(a), 0.06), (0.09,) * 3, mat("Lamp", (1.0, 0.9, 0.4), 0.4, emit=2.0), 1, root)
    export("ufo")


# ---------------------------------------------------------------- ground, trees
def ground():
    reset()
    root = empty("Ground")
    rnd = random.Random(5)
    grass, grass2 = mat("Grass", (0.44, 0.78, 0.30)), mat("Grass2", (0.34, 0.68, 0.26))
    soil, soil2 = mat("Soil", (0.62, 0.42, 0.26), 0.9), mat("Soil2", (0.52, 0.34, 0.22), 0.9)
    box("Soil", (0, 1.0, -1.1), (16, 3.0, 2.0), soil, root)
    box("Turf", (0, 1.0, -0.14), (16, 3.0, 0.28), grass, root)
    for i in range(60):   # a bumpy grass lip along the front edge
        x = -8 + 16 * i / 59
        ico("Lip", (x, -0.5, -0.16), (0.2, 0.12, 0.13), grass if i % 3 else grass2, 1, root)
    for i in range(40):
        ico("Pebble", (rnd.uniform(-8, 8), -0.52, rnd.uniform(-1.8, -0.5)), (rnd.uniform(0.06, 0.12), 0.05, rnd.uniform(0.04, 0.07)),
            rnd.choice([soil2, mat("Stone", (0.8, 0.78, 0.84), 0.9)]), 1, root)
    for i in range(30):   # tufts and tiny flowers on the grass top
        x, y = rnd.uniform(-8, 8), rnd.uniform(-0.3, 2.2)
        cone("Tuft", (x, y, 0.05), 0.06, 0.0, 0.14, grass2, 4, parent=root)
        if i % 3 == 0:
            ico("Bloom", (x + 0.1, y, 0.06), (0.04,) * 3, mat("Bloom%d" % (i % 2), (1.0, 0.95, 0.5) if i % 2 else PINK), 1, root)
    export("ground")


def tree(variant):
    reset()
    root = empty("Tree")
    bark = mat("Bark", (0.58, 0.38, 0.24), 0.9)
    cone("Trunk", (0, 0, 0.45), 0.1, 0.08, 0.9, bark, 6, parent=root)
    if variant == "round":
        g = mat("Canopy", (0.38, 0.72, 0.30))
        for i, (x, z, r) in enumerate(((0, 1.25, 0.6), (-0.35, 1.05, 0.42), (0.36, 1.08, 0.44), (0.05, 1.6, 0.4))):
            ico("Canopy", (x, 0, z), (r, r, r), g, 1, root, jitter=0.1, seed=i)
    else:
        g = mat("Pine", (0.24, 0.56, 0.36))
        for i, (z, r) in enumerate(((0.9, 0.6), (1.35, 0.46), (1.75, 0.32))):
            cone("Tier", (0, 0, z), r, 0.0, 0.7, g, 7, parent=root)
    export("tree_%s" % variant)


# ---------------------------------------------------------------- backdrops (far away)
def backdrop_hills():
    reset()
    root = empty("Hills")
    rnd = random.Random(8)
    far, mid = mat("FarHill", (0.60, 0.72, 0.94), 0.95), mat("MidHill", (0.46, 0.76, 0.46), 0.9)
    mountain, snow = mat("Mountain", (0.58, 0.54, 0.84), 0.9), mat("Snow", (1.0, 1.0, 1.0), 0.9)
    for x, h, r in ((-14, 12, 9), (6, 17, 11), (26, 11, 8)):
        cone("Mountain", (x, 6, h / 2), r, 0.0, h, mountain, 7, parent=root)
        cone("Snow", (x, 6 - 0.05, h * 0.82), r * 0.3, 0.0, h * 0.36, snow, 7, parent=root)
    for i in range(10):
        ico("Far", (-40 + i * 9, 3, 0), (7, 3, rnd.uniform(3.5, 5)), far, 1, root, jitter=0.1, seed=i)
    for i in range(12):
        ico("Mid", (-44 + i * 8, 0, -0.5), (6, 3, rnd.uniform(2.5, 3.5)), mid, 1, root, jitter=0.1, seed=20 + i)
    export("backdrop_hills")


def backdrop_city():
    reset()
    root = empty("City")
    rnd = random.Random(12)
    palette = [(1.0, 0.62, 0.56), (0.98, 0.82, 0.44), (0.56, 0.78, 0.98), (0.72, 0.62, 0.96), (0.60, 0.88, 0.70), (1.0, 0.74, 0.86)]
    win = mat("Window", (1.0, 0.95, 0.7), 0.4, emit=0.8)
    roof = mat("Roof", (0.9, 0.4, 0.36))
    hill = mat("CityHill", (0.5, 0.78, 0.5), 0.9)
    for i in range(10):
        ico("Hill", (-44 + i * 10, 6, -0.5), (7, 3, rnd.uniform(3, 4.5)), hill, 1, root, jitter=0.1, seed=i)
    x = -42.0
    while x < 42:
        w, h = rnd.uniform(3.2, 4.8), rnd.uniform(5, 11)
        b = mat("B%d" % int(x), rnd.choice(palette), 0.8)
        box("Bldg", (x + w / 2, 0, h / 2), (w * 0.92, 3, h), b, root, bevel=0.2)
        if rnd.random() < 0.5:
            cone("Roof", (x + w / 2, 0, h + 1.0), w * 0.66, 0.0, 2.0, roof, 4, (0, 0, math.radians(45)), root)
        cols = max(1, int((w - 1) / 1.2))
        for wy in range(int((h - 1.5) / 2)):
            for wx in range(cols):
                box("Win", (x + w / 2 + (wx - (cols - 1) / 2) * 1.2, -1.55, 1.5 + wy * 2), (0.6, 0.1, 0.8), win, root)
        x += w
    export("backdrop_city")


SCENES = {
    "bee": bee,
    "hedges": lambda: [hedge(v, s) for v, s in (("a", 1), ("b", 2), ("c", 3))],
    "flowers": lambda: [flower("flower_red", (0.98, 0.28, 0.32), (1.0, 0.82, 0.25), 6, 0.36, 0.3),
                        flower("flower_yellow", (1.0, 0.8, 0.16), (0.55, 0.3, 0.14), 10, 0.38, 0.16),
                        flower("flower_blue", (0.38, 0.52, 1.0), (1.0, 0.95, 0.72), 5, 0.36, 0.34)],
    "clouds": lambda: [cloud("a", ((-0.55, 0.05, 0.38), (-0.1, 0.22, 0.5), (0.42, 0.14, 0.42), (0.8, -0.02, 0.28))),
                       cloud("b", ((-0.4, 0.0, 0.32), (0.1, 0.2, 0.46), (0.55, 0.05, 0.34)))],
    "gull": gull, "moon": moon, "jupiter": jupiter, "ufo": ufo, "ground": ground,
    "trees": lambda: [tree("round"), tree("pine")],
    "backdrops": lambda: [backdrop_hills(), backdrop_city()],
}
for key, fn in SCENES.items():
    if ONLY is None or key in ONLY:
        fn()
print("DONE low-poly models ->", OUT)
