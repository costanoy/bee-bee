"""Bee Bee — models the bee and the rose hedge in Blender and pre-renders
them to sprites for the 2D game, cel-shaded with an ink outline to sit
with the game's cartoon/pixel look.

  blender --background --factory-startup --python make_3d_assets.py -- <out_dir>

Outputs (all transparent PNG):
  bee_flap_0..7.png  one wingbeat, 256x256, facing LEFT (the game mirrors
                     it). Played once per tap; the last frame doubles as
                     the resting pose between taps.
  bee_dead.png       belly-up, X eyes, same camera/canvas.
  rose_bush.png      512x136 seamless tile: everything within reach of a
                     tile edge is duplicated one period over, and the
                     stems are periodic curves, so the edges match.

(Blender may crash while *exiting* in background mode after all files are
written — harmless.)
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Quaternion

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
INK = (0.13, 0.07, 0.05)


def lin(c):
    """sRGB 0-1 -> scene-linear, so authored colours land exactly on screen."""
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


# ================================================================ scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "BLENDER_EEVEE"
    s.eevee.taa_render_samples = 64
    s.render.film_transparent = True
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    w = bpy.data.worlds.new("World")
    s.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sun = bpy.data.lights.new("Key", "SUN")
    sun.energy = 3.2
    sun.angle = math.radians(4)
    o = bpy.data.objects.new("Key", sun)
    s.collection.objects.link(o)
    o.rotation_euler = (-Vector((-0.55, -0.45, 1.35))).to_track_quat("-Z", "Y").to_euler()
    return s


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def link(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    return obj


def camera(target, direction, ortho_scale, rx, ry):
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho_scale
    o = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(o)
    d = Vector(direction).normalized()
    o.location = Vector(target) + d * 20.0
    o.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    s = bpy.context.scene
    s.camera = o
    s.render.resolution_x, s.render.resolution_y, s.render.resolution_percentage = rx, ry, 100


def ink(sets):
    """sets: list of (collection, thickness, inner_lines)."""
    s = bpy.context.scene
    s.render.use_freestyle = True
    s.render.line_thickness_mode = "ABSOLUTE"
    fs = bpy.context.view_layer.freestyle_settings
    fs.crease_angle = math.radians(120)
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    for i, (col, thick, inner) in enumerate(sets):
        ls = fs.linesets.new("Ink%d" % i)
        ls.select_by_visibility = True
        ls.select_by_edge_types = True
        ls.select_by_collection = True
        ls.collection = col
        ls.select_silhouette = inner
        ls.select_border = inner
        ls.select_crease = False
        ls.select_external_contour = True
        ls.linestyle = bpy.data.linestyles.new("Line%d" % i)
        ls.linestyle.color = INK
        ls.linestyle.thickness = thick
        ls.linestyle.caps = "ROUND"


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ================================================================ toon material
def toon(name, color, shade=(0.36, 0.68, 1.0), spec=0.0, rim=0.0, alpha=1.0, flat=False):
    """Cel shading: light is quantised into 3 flat bands of `color`, plus an
    optional hard specular spot and a soft rim. `color` is an RGB tuple or a
    callable(node_tree) -> colour socket (for procedural stripes)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    emit = N.new("ShaderNodeEmission")

    if callable(color):
        base = color(nt)
    else:
        rgb = N.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*lin(color), 1)
        base = rgb.outputs[0]

    if flat:
        col = base
    else:
        dif = N.new("ShaderNodeBsdfDiffuse")
        s2r = N.new("ShaderNodeShaderToRGB")
        bw = N.new("ShaderNodeRGBToBW")
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].position, e[0].color = 0.0, (shade[0],) * 3 + (1,)
        e[1].position, e[1].color = 0.03, (shade[1],) * 3 + (1,)
        e3 = e.new(0.33)
        e3.color = (shade[2],) * 3 + (1,)
        mul = N.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        L.new(dif.outputs[0], s2r.inputs[0]); L.new(s2r.outputs[0], bw.inputs[0])
        L.new(bw.outputs[0], ramp.inputs[0])
        L.new(base, mul.inputs["A"]); L.new(ramp.outputs["Color"], mul.inputs["B"])
        col = mul.outputs["Result"]
        if spec:
            gl = N.new("ShaderNodeBsdfGlossy"); gl.inputs["Roughness"].default_value = 0.18
            s2 = N.new("ShaderNodeShaderToRGB"); b2 = N.new("ShaderNodeRGBToBW")
            r2 = N.new("ShaderNodeValToRGB"); r2.color_ramp.interpolation = "CONSTANT"
            r2.color_ramp.elements[1].position = 0.55
            r2.color_ramp.elements[1].color = (spec,) * 3 + (1,)
            add = N.new("ShaderNodeMix"); add.data_type = "RGBA"; add.blend_type = "ADD"
            add.inputs["Factor"].default_value = 1.0
            L.new(gl.outputs[0], s2.inputs[0]); L.new(s2.outputs[0], b2.inputs[0]); L.new(b2.outputs[0], r2.inputs[0])
            L.new(col, add.inputs["A"]); L.new(r2.outputs["Color"], add.inputs["B"])
            col = add.outputs["Result"]
        if rim:
            lw = N.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
            r3 = N.new("ShaderNodeValToRGB"); r3.color_ramp.interpolation = "CONSTANT"
            r3.color_ramp.elements[1].position = 0.62
            r3.color_ramp.elements[1].color = (rim,) * 3 + (1,)
            add = N.new("ShaderNodeMix"); add.data_type = "RGBA"; add.blend_type = "SCREEN"
            add.inputs["Factor"].default_value = 1.0
            L.new(lw.outputs["Facing"], r3.inputs[0])
            L.new(col, add.inputs["A"]); L.new(r3.outputs["Color"], add.inputs["B"])
            col = add.outputs["Result"]

    L.new(col, emit.inputs["Color"])
    if alpha < 1.0:
        tr = N.new("ShaderNodeBsdfTransparent")
        mix = N.new("ShaderNodeMixShader")
        mix.inputs["Fac"].default_value = alpha
        L.new(tr.outputs[0], mix.inputs[1]); L.new(emit.outputs[0], mix.inputs[2])
        L.new(mix.outputs[0], out.inputs["Surface"])
        m.surface_render_method = "BLENDED"
    else:
        L.new(emit.outputs[0], out.inputs["Surface"])
    return m


# ================================================================ geometry helpers
def mesh_obj(name, bm, col, material, smooth=True, subsurf=0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if subsurf:
        mod = o.modifiers.new("Sub", "SUBSURF")
        mod.levels = mod.render_levels = subsurf
    me.materials.append(material)
    return o


def sphere(name, col, loc, scale, material, segs=40, rot=None, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=1.0)
    o = mesh_obj(name, bm, col, material)
    o.location, o.scale = loc, scale
    if rot is not None:
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rot
    if parent:
        o.parent = parent
    return o


def lathe(name, col, profile, material, segs=48, parent=None):
    """Surface of revolution around X. profile: [(x, r), ...] front to back."""
    bm = bmesh.new()
    rings = []
    for x, r in profile:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            a, b = rings[i][k], rings[i][(k + 1) % segs]
            c, d = rings[i + 1][(k + 1) % segs], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    for ring, x in ((rings[0], profile[0][0]), (rings[-1], profile[-1][0])):
        cap = bm.verts.new((x, 0, 0))
        for k in range(segs):
            bm.faces.new((ring[k], ring[(k + 1) % segs], cap))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, col, material, subsurf=1)
    if parent:
        o.parent = parent
    return o


def curve(name, col, points, radius, material, parent=None, poly=False):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    if poly:
        sp = cu.splines.new("POLY")
        sp.points.add(len(points) - 1)
        for p, co in zip(sp.points, points):
            p.co = (*co, 1)
    else:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(points) - 1)
        for bp, co in zip(sp.bezier_points, points):
            bp.co = co
            bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, cu)
    col.objects.link(o)
    cu.materials.append(material)
    if parent:
        o.parent = parent
    return o


def empty(name, col, loc, parent=None):
    o = bpy.data.objects.new(name, None)
    col.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def flat_shape(name, col, outline_pts, material, parent=None, bend=0.0):
    """A flat (XZ-plane) polygon — wings, leaves, petals — optionally cupped
    along Y by `bend` so it isn't paper-flat."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, bend * (x * x + z * z), z)) for x, z in outline_pts]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])
    o = mesh_obj(name, bm, col, material)
    if parent:
        o.parent = parent
    return o


def teardrop(length, width, n=28, point=1.6):
    """Outline from a root at the origin out to a rounded tip along +Z."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        z = length * 0.5 * (1 - math.cos(t))
        w = width * 0.5 * math.sin(t) * (math.sin(t / 2) ** 0) * (min(1.0, (z / length) ** 0.45 * point) if length else 1)
        pts.append((w, z))
    return pts


def leaf_outline(length, width, n=22):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        z = length * 0.5 * (1 - math.cos(t))
        s = math.sin(t)
        pts.append((width * 0.5 * s * (max(0.0, math.sin(math.pi * z / length)) ** 0.8), z))
    return pts


# ================================================================ bee
YELLOW = (1.0, 0.78, 0.12)
BLACK = (0.16, 0.11, 0.12)


def bee_stripes(nt):
    # Bands along the body's own X: front plain yellow, rings towards the tail.
    N, L = nt.nodes, nt.links
    tc = N.new("ShaderNodeTexCoord"); sep = N.new("ShaderNodeSeparateXYZ")
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 2.6
    add = N.new("ShaderNodeMath"); add.operation = "ADD"; add.inputs[1].default_value = 0.05
    frc = N.new("ShaderNodeMath"); frc.operation = "FRACT"
    band = N.new("ShaderNodeMath"); band.operation = "GREATER_THAN"; band.inputs[1].default_value = 0.52
    front = N.new("ShaderNodeMath"); front.operation = "GREATER_THAN"; front.inputs[1].default_value = 0.08
    both = N.new("ShaderNodeMath"); both.operation = "MULTIPLY"
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (*lin(YELLOW), 1); mix.inputs["B"].default_value = (*lin(BLACK), 1)
    L.new(tc.outputs["Object"], sep.inputs[0])
    L.new(sep.outputs["X"], mul.inputs[0]); L.new(mul.outputs[0], add.inputs[0])
    L.new(add.outputs[0], frc.inputs[0]); L.new(frc.outputs[0], band.inputs[0])
    L.new(sep.outputs["X"], front.inputs[0])
    L.new(band.outputs[0], both.inputs[0]); L.new(front.outputs[0], both.inputs[1])
    L.new(both.outputs[0], mix.inputs["Factor"])
    return mix.outputs["Result"]


def on_sphere(center, radius, direction, lift=0.0):
    d = Vector(direction).normalized()
    return center + d * (radius + lift), d


def build_bee(ink_col, ghost_col):
    M = {
        "body": toon("Body", bee_stripes, spec=0.28, rim=0.18),
        "yellow": toon("Yellow", YELLOW, spec=0.28, rim=0.18),
        "fluff": toon("Fluff", (0.99, 0.86, 0.52), shade=(0.5, 0.78, 1.0)),
        "black": toon("Black", BLACK, shade=(0.7, 1.0, 1.6), spec=0.30),
        "eye": toon("Eye", (0.10, 0.07, 0.14), shade=(1, 1, 1), spec=0.0),
        "shine": toon("Shine", (1, 1, 1), flat=True),
        "cheek": toon("Cheek", (1.0, 0.58, 0.55), flat=True),
        "mouth": toon("Mouth", (0.35, 0.10, 0.10), flat=True),
        "wing": toon("Wing", (0.86, 0.96, 1.0), shade=(0.85, 1.0, 1.0), alpha=0.70),
        "ghost": toon("Ghost", (0.85, 0.95, 1.0), flat=True, alpha=0.22),
    }
    root = empty("BeeRoot", ink_col, (0, 0, 0))
    squash = empty("Squash", ink_col, (0.15, 0, 0), root)   # pivot at the body's middle

    # abdomen+thorax as one egg, fuller at the front, tapering to the sting
    prof = []
    for i in range(34):
        t = i / 33
        x = -0.45 + 1.50 * t
        r = 0.60 * (math.sin(math.pi * min(1, t * 1.02)) ** 0.62) * (1 - 0.30 * t)
        prof.append((x, max(r, 0.004)))
    body = lathe("Body", ink_col, prof, M["body"], parent=squash)
    body.location = (-0.15, 0, 0)
    body.rotation_euler = (0, math.radians(-7), 0)

    hc = Vector((-0.78, 0, 0.16))
    HR = 0.50
    head = sphere("Head", ink_col, hc - Vector((0.15, 0, 0)), (HR, HR * 0.98, HR * 0.94), M["yellow"], parent=squash)

    # fluffy collar where head meets body
    for k in range(9):
        a = 2 * math.pi * k / 9 + 0.3
        p = Vector((-0.50, 0.33 * math.cos(a), 0.04 + 0.33 * math.sin(a)))
        sphere("Fluff", ink_col, p - Vector((0.15, 0, 0)), (0.12, 0.15, 0.15), M["fluff"], 20, parent=squash)

    face = {}
    hcl = hc - Vector((0.15, 0, 0))

    # eyes: tall glossy ovals set into the head, two catchlights each
    for dy, tag in ((-1, "near"),):
        pos, d = on_sphere(hcl, HR * 0.955, (-0.66, 0.56 * dy, 0.18))
        q = d.to_track_quat("Y", "Z")
        eye = sphere("Eye_" + tag, ink_col, pos, (0.13, 0.075, 0.19), M["eye"], 32, q, squash)
        s1 = sphere("Shine_" + tag, ink_col, pos + d * 0.08 + Vector((-0.03, 0, 0.075)), (0.052,) * 3, M["shine"], 16, parent=squash)
        s2 = sphere("Shine2_" + tag, ink_col, pos + d * 0.08 + Vector((0.04, 0, -0.07)), (0.026,) * 3, M["shine"], 12, parent=squash)
        face.setdefault("eyes", []).extend([eye, s1, s2])
        # dead variant: an X over the eye
        xs = []
        for sgn in (-1, 1):
            a = pos + d * 0.07
            p1 = a + Vector((-0.09, 0, 0.09 * sgn)); p2 = a + Vector((0.09, 0, -0.09 * sgn))
            xs.append(curve("X_" + tag, ink_col, [p1, p2], 0.03, M["black"], squash, poly=True))
        face.setdefault("xeyes", []).extend(xs)

    # smile, cheek, and a dead "o" mouth
    arc = []
    for i in range(7):
        u = -1 + 2 * i / 6
        p, _ = on_sphere(hcl, HR * 0.975, (-0.78 + 0.06 * u, -0.52 + 0.30 * u, -0.34 + 0.13 * u * u))
        arc.append(p)
    face["smile"] = curve("Smile", ink_col, arc, 0.024, M["mouth"], squash, poly=True)
    pos, d = on_sphere(hcl, HR * 0.97, (-0.18, -0.92, -0.20))
    sphere("Cheek", ink_col, pos, (0.085, 0.02, 0.06), M["cheek"], 20, d.to_track_quat("Y", "Z"), squash)
    pos, d = on_sphere(hcl, HR * 0.95, (-0.75, -0.52, -0.40))
    face["o"] = sphere("OMouth", ink_col, pos, (0.05, 0.03, 0.06), M["mouth"], 16, d.to_track_quat("Y", "Z"), squash)

    # antennae on pivots so they can lag behind the wingbeat
    ants = []
    for dy in (-1, 1):
        base, _ = on_sphere(hcl, HR * 0.9, (-0.25, 0.28 * dy, 0.95))
        piv = empty("AntPivot", ink_col, base, squash)
        pts = [Vector((0, 0, 0)), Vector((-0.10, 0.04 * dy, 0.26)), Vector((-0.30, 0.08 * dy, 0.44)), Vector((-0.50, 0.10 * dy, 0.46))]
        curve("Antenna", ink_col, pts, 0.03, M["black"], piv)
        sphere("AntTip", ink_col, pts[-1], (0.075,) * 3, M["black"], 20, parent=piv)
        ants.append(piv)

    # little legs tucked under
    for x in (-0.30, -0.08, 0.14):
        p0 = Vector((x, -0.20, -0.40))
        pts = [p0, p0 + Vector((0.03, -0.04, -0.10)), p0 + Vector((0.11, -0.05, -0.15))]
        curve("Leg", ink_col, pts, 0.034, M["black"], squash)

    # stinger
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.085, radius2=0.0, depth=0.26)
    st = mesh_obj("Sting", bm, ink_col, M["black"])
    st.parent = squash
    st.location = (0.98 - 0.15, 0, -0.14)
    st.rotation_euler = (0, math.radians(97), 0)

    # wings: fore + hind per side on a hinge along the body axis
    wings, ghosts = [], []
    fore, hind = teardrop(0.95, 0.46), teardrop(0.64, 0.32)
    for dy in (-1, 1):
        piv = empty("WingPivot", ink_col, (0.0, 0.14 * dy, 0.50), squash)
        f = flat_shape("Fore", ink_col, fore, M["wing"], piv, bend=0.05 * dy)
        f.rotation_euler = (0, math.radians(-38), 0)
        h = flat_shape("Hind", ink_col, hind, M["wing"], piv, bend=0.05 * dy)
        h.rotation_euler = (0, math.radians(-68), 0)
        h.location = (0.08, 0.01 * dy, -0.02)
        wings.append((piv, dy))
        for g in range(2):
            gp = empty("GhostPivot", ghost_col, (0.0, 0.14 * dy, 0.50), squash)
            gf = flat_shape("GFore", ghost_col, fore, M["ghost"], gp)
            gf.rotation_euler = (0, math.radians(-38), 0)
            gh = flat_shape("GHind", ghost_col, hind, M["ghost"], gp)
            gh.rotation_euler = (0, math.radians(-68), 0)
            ghosts.append((gp, dy, [gf, gh]))
    return root, squash, wings, ghosts, ants, face


def set_hidden(objs, hidden):
    for o in objs:
        o.hide_render = hidden


def wing_rot(angle, dy):
    # Mostly a sweep in the picture plane (about Y: up-back -> back-down),
    # with a little roll out from the body so it still reads as 3D.
    a = math.radians(angle)
    return (a * 0.35 * -dy, -a, 0)


def pose(squash, wings, ghosts, ants, wing, sx, sz, ant, smear=0.0):
    squash.scale = (sx, 1.0 / math.sqrt(sx * sz), sz)
    for piv, dy in wings:
        piv.rotation_euler = wing_rot(wing, dy)
    for i, (gp, dy, objs) in enumerate(ghosts):
        off = (-1 if i % 2 == 0 else 1) * smear
        gp.rotation_euler = wing_rot(wing + off, dy)
        set_hidden(objs, smear == 0.0)
    for p in ants:
        p.rotation_euler = (0, math.radians(-ant), 0)


def bee_scene():
    reset()
    ink_col, ghost_col = collection("BeeInk"), collection("BeeGhost")
    root, squash, wings, ghosts, ants, face = build_bee(ink_col, ghost_col)
    ink([(ink_col, 5.0, True)])
    camera((-0.05, 0, 0.08), (-0.28, -1.0, 0.30), 3.15, 256, 256)
    set_hidden(face["xeyes"] + [face["o"]], True)

    #        wing  sx    sz    antenna  smear
    beat = [(-6, 1.00, 1.00, 0, 0),
            (22, 1.04, 0.96, -5, 12),
            (55, 1.08, 0.92, -12, 16),
            (82, 1.05, 0.95, -16, 10),
            (62, 0.95, 1.06, -8, 14),
            (34, 0.97, 1.04, 5, 12),
            (10, 1.00, 1.01, 7, 0),
            (0, 1.00, 1.00, 0, 0)]
    for i, (w, sx, sz, a, sm) in enumerate(beat):
        pose(squash, wings, ghosts, ants, w, sx, sz, a, sm)
        render(os.path.join(OUT, "bee_flap_%d.png" % i))

    # dead: X eyes, "o" mouth, wings limp, flipped belly-up (mirror in Z,
    # which keeps the face towards the camera and the light from above)
    set_hidden(face["eyes"] + [face["smile"]], True)
    set_hidden(face["xeyes"] + [face["o"]], False)
    pose(squash, wings, ghosts, ants, 70, 1.0, 1.0, 55, 0)
    root.scale = (1, 1, -1)
    root.location = (0, 0, 0.16)
    render(os.path.join(OUT, "bee_dead.png"))


# ================================================================ hedge
def hedge_scene():
    reset()
    random.seed(21)
    P = 4.0
    H = P * 136 / 512
    core = H * 22 / 34 / 2
    body_col, rose_col = collection("Hedge"), collection("Roses")

    greens = [toon("G%d" % i, c, shade=(0.62, 0.84, 1.0), rim=0.10) for i, c in enumerate(
        ((0.22, 0.58, 0.18), (0.32, 0.70, 0.22), (0.16, 0.47, 0.16)))]
    filler = toon("Filler", (0.09, 0.30, 0.11), shade=(0.7, 0.9, 1.0))
    stem_m = toon("Stem", (0.30, 0.40, 0.14), shade=(0.65, 0.88, 1.0))
    thorn_m = toon("Thorn", (0.55, 0.40, 0.18), shade=(0.7, 0.9, 1.0))
    petal_out = toon("PetalOut", (0.96, 0.24, 0.28), shade=(0.45, 0.75, 1.0), spec=0.18)
    petal_in = toon("PetalIn", (0.74, 0.08, 0.16), shade=(0.55, 0.82, 1.0))
    sepal_m = toon("Sepal", (0.20, 0.52, 0.16))

    def periodic(x):
        return [x + s for s in (-P, 0.0, P) if -0.6 <= x + s <= P + 0.6]

    # dark filler blobs so the hedge core never shows sky through it
    for _ in range(26):
        x0, z = random.uniform(0, P), random.uniform(-core * 0.6, core * 0.6)
        for x in periodic(x0):
            o = sphere("Fill", body_col, (x, 0.12, z), (0.26, 0.12, core * 0.95), filler, 20)

    # thorny stems weaving along the hedge — periodic curves, so seamless
    for k, (amp, ph, zc, freq) in enumerate(((core * 0.55, 0.0, 0.02, 2), (core * 0.45, 1.9, -0.05, 3))):
        pts = []
        for i in range(81):
            x = -0.6 + (P + 1.2) * i / 80
            pts.append(Vector((x, -0.16, zc + amp * math.sin(2 * math.pi * freq * x / P + ph))))
        curve("Stem", body_col, pts, 0.028, stem_m, poly=True)
        for i in range(0, 80, 5):
            p = pts[i]
            if not (0 <= p.x < P):
                continue
            for x in periodic(p.x):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.018, radius2=0.0, depth=0.06)
                th = mesh_obj("Thorn", bm, body_col, thorn_m, smooth=False)
                th.location = (x, -0.17, p.z + (0.03 if i % 10 else -0.03))
                th.rotation_euler = (math.radians(0 if i % 10 else 180), 0, 0)

    # leaves: the bulk of the hedge
    leaf = leaf_outline(0.17, 0.085)
    for _ in range(360):
        x0 = random.uniform(0, P)
        z = random.uniform(-core - 0.05, core + 0.05)
        y = random.uniform(-0.24, 0.05)
        yaw = random.uniform(-35, 35)
        roll = random.uniform(0, 360)
        tilt = random.uniform(-30, 30)
        m = random.choice(greens)
        for x in periodic(x0):
            o = flat_shape("Leaf", body_col, leaf, m, bend=0.9)
            o.location = (x, y, z)
            o.rotation_euler = (math.radians(tilt), math.radians(roll), math.radians(yaw))

    # roses: layered cupped petals around a dark centre, with sepals
    petal = leaf_outline(0.085, 0.085, 18)
    def rose(x, z, size):
        c = Vector((x, -0.30, z))
        sphere("RoseCore", rose_col, c + Vector((0, -0.03, 0)), (0.028 * size,) * 3, petal_in, 16)
        # inner ring cups up towards the camera, outer ring lies open
        for ring, (n, rad, tilt, grow, mat_) in enumerate((
                (3, 0.012, 58, 0.62, petal_in), (5, 0.03, 32, 0.9, petal_out), (6, 0.05, 8, 1.15, petal_out))):
            for k in range(n):
                a = 2 * math.pi * k / n + ring * 0.55
                o = flat_shape("Petal", rose_col, petal, mat_, bend=-1.4)
                o.scale = (size * grow,) * 3
                o.location = c + Vector((math.cos(a) * rad * size, 0.025 * ring, math.sin(a) * rad * size))
                # petal points radially outward in the picture plane (spin about
                # the view axis), tilted so its tip comes towards the camera
                o.rotation_mode = "XYZ"
                o.rotation_euler = (math.radians(tilt), math.pi / 2 - a, 0)
        for k in range(4):
            a = 2 * math.pi * k / 4 + 0.4
            o = flat_shape("Sepal", body_col, leaf_outline(0.09, 0.035, 14), sepal_m, bend=0.6)
            o.location = c + Vector((0, 0.05, 0))
            o.rotation_euler = (0, -a + math.pi / 2, 0)

    for _ in range(8):
        x0, z = random.uniform(0, P), random.uniform(-core + 0.05, core - 0.05)
        s = random.uniform(1.45, 1.75)
        for x in periodic(x0):
            rose(x, z, s)
    for _ in range(3):   # buds
        x0, z = random.uniform(0, P), random.uniform(-core, core)
        for x in periodic(x0):
            sphere("Bud", rose_col, (x, -0.26, z), (0.035, 0.035, 0.05), petal_out, 16)
            for k in range(3):
                o = flat_shape("BudSepal", body_col, leaf_outline(0.07, 0.03, 12), sepal_m, bend=0.5)
                o.location = (x, -0.25, z - 0.03)
                o.rotation_euler = (0, math.radians(150 + k * 30), 0)

    ink([(body_col, 3.2, False), (rose_col, 2.4, True)])
    camera((P / 2, 0, 0), (0, -1.0, 0.16), P, 512, 136)
    render(os.path.join(OUT, "rose_bush.png"))


bee_scene()
hedge_scene()
print("DONE 3D assets ->", OUT)
