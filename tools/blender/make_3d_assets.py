"""Bee Bee — the whole game's art as 3D models, built in Blender and
pre-rendered to sprites.

  blender --background --factory-startup --python make_3d_assets.py -- <raw_out_dir> [only,names]

Then tools/blender/conform.py fits each raw render into the canvas the
game expects (same size and content box as the original 2D art), so the
game picks them up from art/3d/ without any scale changes.

STYLE — "candy toy":
  * rounded, chunky, toy-like forms;
  * cel shading in three flat bands whose shadow band is hue-shifted
    cool (yellow shades to ochre, white to lavender) instead of greyed;
  * a soft sky-blue rim light on every silhouette;
  * ink outlines coloured per material — a deep shade of the object's own
    hue rather than one black for everything;
  * one key light for every asset so the whole game is lit consistently.

(Blender may crash while *exiting* in background mode after all files are
written — harmless.)
"""
import bpy, bmesh, math, random, sys, os, colorsys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGS[0]
ONLY = set(ARGS[1].split(",")) if len(ARGS) > 1 else None
os.makedirs(OUT, exist_ok=True)
BLENDER_FONTS = os.path.join(os.path.dirname(bpy.app.binary_path), "%d.%d" % bpy.app.version[:2], "datafiles", "fonts")

LIGHT_DIR = (-0.55, -0.45, 1.35)
LINE_GAME_PX = 1.25          # outline width once drawn in the game, in game px


# ================================================================ colour
def lin(c):
    """sRGB 0-1 -> scene-linear, so authored colours land exactly on screen."""
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def ink_of(c, value=0.26):
    h, s, v = colorsys.rgb_to_hsv(*c)
    return colorsys.hsv_to_rgb(h, min(1.0, s * 1.1 + 0.12), value)


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
    o.rotation_euler = (-Vector(LIGHT_DIR)).to_track_quat("-Z", "Y").to_euler()
    return collection("Ink"), collection("NoInk")


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def cam_basis(direction):
    d = Vector(direction).normalized()
    q = (-d).to_track_quat("-Z", "Y")
    return d, q, q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0))


def camera(target, direction, ortho_scale, rx, ry):
    d, q, _, _ = cam_basis(direction)
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho_scale
    cd.clip_end = 200
    o = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(target) + d * 40.0
    o.rotation_euler = q.to_euler()
    s = bpy.context.scene
    s.camera = o
    s.render.resolution_x, s.render.resolution_y, s.render.resolution_percentage = int(rx), int(ry), 100


def fit_camera(direction, long_px, margin=0.06):
    """Ortho camera framing everything renderable in the scene tightly."""
    d, q, right, up = cam_basis(direction)
    dg = bpy.context.evaluated_depsgraph_get()
    us, vs = [], []
    for o in bpy.context.scene.objects:
        if o.type not in {"MESH", "CURVE", "FONT"} or o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        for v in me.vertices:
            p = ev.matrix_world @ v.co
            us.append(p.dot(right)); vs.append(p.dot(up))
        ev.to_mesh_clear()
    u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
    w, h = (u1 - u0) * (1 + margin), (v1 - v0) * (1 + margin)
    c = right * (u0 + u1) / 2 + up * (v0 + v1) / 2
    if w >= h:
        rx, ry = long_px, max(8, round(long_px * h / w))
    else:
        rx, ry = max(8, round(long_px * w / h)), long_px
    camera(c, direction, max(w, h), rx, ry)


def ink(col, thickness_px, inner=True):
    s = bpy.context.scene
    s.render.use_freestyle = True
    s.render.line_thickness_mode = "ABSOLUTE"
    fs = bpy.context.view_layer.freestyle_settings
    fs.crease_angle = math.radians(120)
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    ls = fs.linesets.new("Ink")
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_by_collection = True
    ls.collection = col
    ls.select_silhouette = inner
    ls.select_border = inner
    ls.select_crease = False
    ls.select_external_contour = True
    st = bpy.data.linestyles.new("Line")
    ls.linestyle = st
    st.thickness = thickness_px
    st.caps = "ROUND"
    st.color = (0.1, 0.06, 0.05)
    mod = st.color_modifiers.new("ByMaterial", "MATERIAL")
    mod.material_attribute = "LINE"
    mod.influence = 1.0


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


# ================================================================ material
def toon(name, color, spec=0.0, rim=True, alpha=1.0, flat=False, line=None, glow=0.0):
    """The one material of the style. `color` is sRGB, or a callable
    (node_tree) -> colour socket for procedural patterns (then give `line`)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    emit = N.new("ShaderNodeEmission")
    m.line_color = (*lin(line if line else ink_of(color)), 1.0)

    if callable(color):
        base = color(nt)
    else:
        rgb = N.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*lin(color), 1)
        base = rgb.outputs[0]

    def mix(a, b, blend):
        n = N.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = blend
        n.inputs["Factor"].default_value = 1.0
        L.new(a, n.inputs["A"]); L.new(b, n.inputs["B"])
        return n.outputs["Result"]

    if flat:
        col = base
    else:
        dif = N.new("ShaderNodeBsdfDiffuse")
        s2r = N.new("ShaderNodeShaderToRGB")
        bw = N.new("ShaderNodeRGBToBW")
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].position, e[0].color = 0.0, (0.55, 0.50, 0.72, 1)      # cool shadow
        e[1].position, e[1].color = 0.03, (0.85, 0.84, 0.93, 1)     # mid
        e3 = e.new(0.33)
        e3.color = (1.0, 0.99, 0.95, 1)                           # warm light
        L.new(dif.outputs[0], s2r.inputs[0]); L.new(s2r.outputs[0], bw.inputs[0])
        L.new(bw.outputs[0], ramp.inputs[0])
        col = mix(base, ramp.outputs["Color"], "MULTIPLY")
        if spec:
            gl = N.new("ShaderNodeBsdfGlossy"); gl.inputs["Roughness"].default_value = 0.18
            s2 = N.new("ShaderNodeShaderToRGB"); b2 = N.new("ShaderNodeRGBToBW")
            r2 = N.new("ShaderNodeValToRGB"); r2.color_ramp.interpolation = "CONSTANT"
            r2.color_ramp.elements[1].position = 0.55
            r2.color_ramp.elements[1].color = (spec,) * 3 + (1,)
            L.new(gl.outputs[0], s2.inputs[0]); L.new(s2.outputs[0], b2.inputs[0]); L.new(b2.outputs[0], r2.inputs[0])
            col = mix(col, r2.outputs["Color"], "ADD")
        if rim:
            lw = N.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
            r3 = N.new("ShaderNodeValToRGB"); r3.color_ramp.interpolation = "CONSTANT"
            r3.color_ramp.elements[1].position = 0.64
            r3.color_ramp.elements[1].color = (0.20, 0.28, 0.34, 1)
            L.new(lw.outputs["Facing"], r3.inputs[0])
            col = mix(col, r3.outputs["Color"], "SCREEN")

    L.new(col, emit.inputs["Color"])
    emit.inputs["Strength"].default_value = 1.0 + glow
    if alpha < 1.0:
        tr = N.new("ShaderNodeBsdfTransparent")
        mx = N.new("ShaderNodeMixShader")
        mx.inputs["Fac"].default_value = alpha
        L.new(tr.outputs[0], mx.inputs[1]); L.new(emit.outputs[0], mx.inputs[2])
        L.new(mx.outputs[0], out.inputs["Surface"])
        m.surface_render_method = "BLENDED"
    else:
        L.new(emit.outputs[0], out.inputs["Surface"])
    return m


def bands(axis, freq, offset, colors, gate=None):
    """Procedural stripes along an object-space axis (bee body, planet)."""
    def build(nt):
        N, L = nt.nodes, nt.links
        tc = N.new("ShaderNodeTexCoord"); sep = N.new("ShaderNodeSeparateXYZ")
        L.new(tc.outputs["Object"], sep.inputs[0])
        mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = freq
        add = N.new("ShaderNodeMath"); add.operation = "ADD"; add.inputs[1].default_value = offset
        frc = N.new("ShaderNodeMath"); frc.operation = "FRACT"
        L.new(sep.outputs[axis], mul.inputs[0]); L.new(mul.outputs[0], add.inputs[0]); L.new(add.outputs[0], frc.inputs[0])
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].color = (*lin(colors[0]), 1)
        e[1].position = 1.0 / len(colors)
        e[1].color = (*lin(colors[1]), 1)
        for i, c in enumerate(colors[2:], start=2):
            el = e.new(i / len(colors)); el.color = (*lin(c), 1)
        L.new(frc.outputs[0], ramp.inputs[0])
        if gate is None:
            return ramp.outputs["Color"]
        g = N.new("ShaderNodeMath"); g.operation = "GREATER_THAN"; g.inputs[1].default_value = gate[0]
        L.new(sep.outputs[axis], g.inputs[0])
        mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
        mx.inputs["A"].default_value = (*lin(gate[1]), 1)
        L.new(g.outputs[0], mx.inputs["Factor"]); L.new(ramp.outputs["Color"], mx.inputs["B"])
        return mx.outputs["Result"]
    return build


# ================================================================ geometry
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


def rounded_box(name, col, loc, size, radius, material, parent=None):
    """Box with evenly rounded edges (the geometry is built at full size,
    so the bevel isn't distorted by object scale)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    o = mesh_obj(name, bm, col, material, smooth=True)
    o.location = loc
    bev = o.modifiers.new("Bevel", "BEVEL")
    bev.width = min(radius, min(size) * 0.49)
    bev.segments = 6
    bev.affect = "EDGES"
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    if parent:
        o.parent = parent
    return o


def cylinder(name, col, loc, radius, depth, material, rot=(0, 0, 0), segs=24, parent=None):
    return cone(name, col, loc, radius, radius, depth, material, rot, segs, parent)


def cone(name, col, loc, r1, r2, depth, material, rot=(0, 0, 0), segs=24, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    o = mesh_obj(name, bm, col, material)
    o.location, o.rotation_euler = loc, rot
    if parent:
        o.parent = parent
    return o


def lathe(name, col, profile, material, segs=48, parent=None, axis="X"):
    """Surface of revolution. profile: [(t, r), ...] along the axis."""
    bm = bmesh.new()
    rings = []
    for t, r in profile:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            c, s = r * math.cos(a), r * math.sin(a)
            ring.append(bm.verts.new((t, c, s) if axis == "X" else (c, s, t)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
    for ring, (t, _) in ((rings[0], profile[0]), (rings[-1], profile[-1])):
        cap = bm.verts.new((t, 0, 0) if axis == "X" else (0, 0, t))
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


def flat_shape(name, col, outline_pts, material, parent=None, bend=0.0, thickness=0.0, smooth=False):
    """Polygon in the XZ plane (wings, leaves, petals), cupped along Y by
    `bend`; optional thickness so it has a real edge. smooth=True builds it
    as a dense fan (so the cup bends smoothly instead of in facets)."""
    bm = bmesh.new()
    if smooth:
        cx = sum(x for x, _ in outline_pts) / len(outline_pts)
        cz = sum(z for _, z in outline_pts) / len(outline_pts)
        rings = []
        for k in range(1, 7):
            f = k / 6
            rings.append([bm.verts.new(((cx + (x - cx) * f), 0, (cz + (z - cz) * f))) for x, z in outline_pts])
        c = bm.verts.new((cx, 0, cz))
        n = len(outline_pts)
        for i in range(n):
            bm.faces.new((c, rings[0][i], rings[0][(i + 1) % n]))
        for r in range(5):
            for i in range(n):
                bm.faces.new((rings[r][i], rings[r + 1][i], rings[r + 1][(i + 1) % n], rings[r][(i + 1) % n]))
        for v in bm.verts:
            v.co.y = bend * (v.co.x * v.co.x + v.co.z * v.co.z)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    else:
        vs = [bm.verts.new((x, bend * (x * x + z * z), z)) for x, z in outline_pts]
        f = bm.faces.new(vs)
        bmesh.ops.triangulate(bm, faces=[f])
    o = mesh_obj(name, bm, col, material)
    if thickness:
        sol = o.modifiers.new("Thick", "SOLIDIFY")
        sol.thickness = thickness
        sol.offset = 0
    if parent:
        o.parent = parent
    return o


def leaf_outline(length, width, n=22, tip=0.8):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        z = length * 0.5 * (1 - math.cos(t))
        pts.append((width * 0.5 * math.sin(t) * (max(0.0, math.sin(math.pi * z / length)) ** tip), z))
    return pts


def petal_outline(length, width, n=24):
    """Rounded petal: narrow at the root, broad round end."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        z = length * 0.5 * (1 - math.cos(t))
        pts.append((width * 0.5 * math.sin(t) * (max(0.0, z / length) ** 0.5), z))
    return pts


def on_sphere(center, radius, direction, lift=0.0):
    d = Vector(direction).normalized()
    return center + d * (radius + lift), d


def text_obj(name, col, body, material, size, extrude, bevel, offset, font_file="Inter.woff2"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.font = bpy.data.fonts.load(os.path.join(BLENDER_FONTS, font_file))
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    cu.offset = offset
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_character = 1.04
    o = bpy.data.objects.new(name, cu)
    col.objects.link(o)
    cu.materials.append(material)
    o.rotation_euler = (math.radians(90), 0, 0)   # stand the text up, facing -Y
    return o


# ================================================================ bee
BEE_YELLOW = (1.0, 0.80, 0.16)
BEE_DARK = (0.24, 0.16, 0.26)


def build_bee(col, ghost_col, scale=1.0):
    M = {
        "body": toon("BeeBody", bands("X", 2.6, 0.05, [BEE_YELLOW, BEE_DARK], gate=(0.08, BEE_YELLOW)), spec=0.28,
                     line=ink_of(BEE_YELLOW, 0.3)),
        "yellow": toon("BeeYellow", BEE_YELLOW, spec=0.28, line=ink_of(BEE_YELLOW, 0.3)),
        "fluff": toon("Fluff", (1.0, 0.90, 0.60), line=ink_of((1.0, 0.8, 0.4), 0.32)),
        "dark": toon("BeeDark", BEE_DARK, spec=0.30, line=(0.08, 0.05, 0.10)),
        "eye": toon("Eye", (0.13, 0.09, 0.20), rim=False, line=(0.06, 0.04, 0.09)),
        "shine": toon("Shine", (1, 1, 1), flat=True, line=(0.06, 0.04, 0.09)),
        "cheek": toon("Cheek", (1.0, 0.56, 0.60), flat=True),
        "mouth": toon("Mouth", (0.42, 0.14, 0.18), flat=True, line=(0.2, 0.05, 0.08)),
        "wing": toon("Wing", (0.86, 0.96, 1.0), alpha=0.72, line=(0.30, 0.42, 0.62)),
        "ghost": toon("Ghost", (0.88, 0.96, 1.0), flat=True, alpha=0.22),
    }
    root = empty("BeeRoot", col, (0, 0, 0))
    root.scale = (scale,) * 3
    squash = empty("Squash", col, (0.15, 0, 0), root)

    prof = []
    for i in range(34):
        t = i / 33
        r = 0.60 * (math.sin(math.pi * min(1, t * 1.02)) ** 0.62) * (1 - 0.30 * t)
        prof.append((-0.45 + 1.50 * t, max(r, 0.004)))
    body = lathe("Body", col, prof, M["body"], parent=squash)
    body.location = (-0.15, 0, 0)
    body.rotation_euler = (0, math.radians(-7), 0)

    HR = 0.50
    hc = Vector((-0.93, 0, 0.16))
    sphere("Head", col, hc, (HR, HR * 0.98, HR * 0.94), M["yellow"], parent=squash)
    for k in range(9):
        a = 2 * math.pi * k / 9 + 0.3
        sphere("Fluff", col, Vector((-0.65, 0.33 * math.cos(a), 0.04 + 0.33 * math.sin(a))), (0.12, 0.15, 0.15),
               M["fluff"], 20, parent=squash)

    face = {"eyes": [], "xeyes": []}
    pos, d = on_sphere(hc, HR * 0.955, (-0.66, -0.56, 0.18))
    face["eyes"].append(sphere("Eye", col, pos, (0.13, 0.075, 0.19), M["eye"], 32, d.to_track_quat("Y", "Z"), squash))
    face["eyes"].append(sphere("Shine", col, pos + d * 0.08 + Vector((-0.03, 0, 0.075)), (0.052,) * 3, M["shine"], 16, parent=squash))
    face["eyes"].append(sphere("Shine2", col, pos + d * 0.08 + Vector((0.04, 0, -0.07)), (0.026,) * 3, M["shine"], 12, parent=squash))
    for sgn in (-1, 1):
        a = pos + d * 0.07
        face["xeyes"].append(curve("X", col, [a + Vector((-0.09, 0, 0.09 * sgn)), a + Vector((0.09, 0, -0.09 * sgn))],
                                   0.03, M["dark"], squash, poly=True))
    arc = [on_sphere(hc, HR * 0.975, (-0.78 + 0.06 * u, -0.52 + 0.30 * u, -0.34 + 0.13 * u * u))[0]
           for u in (-1 + 2 * i / 6 for i in range(7))]
    face["smile"] = curve("Smile", col, arc, 0.024, M["mouth"], squash, poly=True)
    pos, d = on_sphere(hc, HR * 0.97, (-0.18, -0.92, -0.20))
    sphere("Cheek", col, pos, (0.085, 0.02, 0.06), M["cheek"], 20, d.to_track_quat("Y", "Z"), squash)
    pos, d = on_sphere(hc, HR * 0.95, (-0.75, -0.52, -0.40))
    face["o"] = sphere("OMouth", col, pos, (0.05, 0.03, 0.06), M["mouth"], 16, d.to_track_quat("Y", "Z"), squash)

    ants = []
    for dy in (-1, 1):
        base, _ = on_sphere(hc, HR * 0.9, (-0.25, 0.28 * dy, 0.95))
        piv = empty("AntPivot", col, base, squash)
        pts = [Vector((0, 0, 0)), Vector((-0.10, 0.04 * dy, 0.26)), Vector((-0.30, 0.08 * dy, 0.44)), Vector((-0.50, 0.10 * dy, 0.46))]
        curve("Antenna", col, pts, 0.03, M["dark"], piv)
        sphere("AntTip", col, pts[-1], (0.075,) * 3, M["dark"], 20, parent=piv)
        ants.append(piv)
    for x in (-0.30, -0.08, 0.14):
        p0 = Vector((x, -0.20, -0.40))
        curve("Leg", col, [p0, p0 + Vector((0.03, -0.04, -0.10)), p0 + Vector((0.11, -0.05, -0.15))], 0.034, M["dark"], squash)
    cone("Sting", col, (0.83, 0, -0.14), 0.085, 0.0, 0.26, M["dark"], rot=(0, math.radians(97), 0), segs=20, parent=squash)

    def teardrop(length, width, n=28):
        pts = []
        for i in range(n):
            t = 2 * math.pi * i / n
            z = length * 0.5 * (1 - math.cos(t))
            pts.append((width * 0.5 * math.sin(t) * min(1.0, (z / length) ** 0.45 * 1.6), z))
        return pts

    wings, ghosts = [], []
    fore, hind = teardrop(0.95, 0.46), teardrop(0.64, 0.32)
    for dy in (-1, 1):
        piv = empty("WingPivot", col, (0.0, 0.14 * dy, 0.50), squash)
        f = flat_shape("Fore", col, fore, M["wing"], piv, bend=0.05 * dy)
        f.rotation_euler = (0, math.radians(-38), 0)
        h = flat_shape("Hind", col, hind, M["wing"], piv, bend=0.05 * dy)
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
    # a sweep in the picture plane (up-back -> back-down), with a little
    # roll out from the body so it still reads as 3D
    a = math.radians(angle)
    return (a * 0.35 * -dy, -a, 0)


def pose_bee(squash, wings, ghosts, ants, wing, sx, sz, ant, smear=0.0):
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
    col, ghost_col = reset()
    root, squash, wings, ghosts, ants, face = build_bee(col, ghost_col)
    # fixed camera: the game's BEE_CONTENT_W is calibrated to this framing
    camera((-0.05, 0, 0.08), (-0.28, -1.0, 0.30), 3.15, 256, 256)
    ink(col, 5.5)
    set_hidden(face["xeyes"] + [face["o"]], True)
    #        wing  sx    sz    antenna  smear
    beat = [(-6, 1.00, 1.00, 0, 0), (22, 1.04, 0.96, -5, 12), (55, 1.08, 0.92, -12, 16), (82, 1.05, 0.95, -16, 10),
            (62, 0.95, 1.06, -8, 14), (34, 0.97, 1.04, 5, 12), (10, 1.00, 1.01, 7, 0), (0, 1.00, 1.00, 0, 0)]
    for i, (w, sx, sz, a, sm) in enumerate(beat):
        pose_bee(squash, wings, ghosts, ants, w, sx, sz, a, sm)
        render("bee_flap_%d.png" % i)
    set_hidden(face["eyes"] + [face["smile"]], True)
    set_hidden(face["xeyes"] + [face["o"]], False)
    pose_bee(squash, wings, ghosts, ants, 70, 1.0, 1.0, 55, 0)
    root.scale = (1, 1, -1)          # belly-up: mirror in Z keeps the face to camera, light from above
    root.location = (0, 0, 0.16)
    render("bee_dead.png")


# ================================================================ hedge (seamless tile)
def rose_head(col, c, size, petal_out, petal_in, sepal_m):
    petal = leaf_outline(0.085, 0.085, 18)
    sphere("RoseCore", col, c + Vector((0, -0.03, 0)), (0.028 * size,) * 3, petal_in, 16)
    for ring, (n, rad, tilt, grow, mat_) in enumerate((
            (3, 0.012, 58, 0.62, petal_in), (5, 0.03, 32, 0.9, petal_out), (6, 0.05, 8, 1.15, petal_out))):
        for k in range(n):
            a = 2 * math.pi * k / n + ring * 0.55
            o = flat_shape("Petal", col, petal, mat_, bend=-1.4)
            o.scale = (size * grow,) * 3
            o.location = c + Vector((math.cos(a) * rad * size, 0.025 * ring, math.sin(a) * rad * size))
            o.rotation_euler = (math.radians(tilt), math.pi / 2 - a, 0)
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        o = flat_shape("Sepal", col, leaf_outline(0.09, 0.035, 14), sepal_m, bend=0.6)
        o.location = c + Vector((0, 0.05, 0))
        o.rotation_euler = (0, -a + math.pi / 2, 0)


def hedge_scene():
    col, _ = reset()
    random.seed(21)
    P = 4.0
    H = P * 136 / 512
    core = H * 22 / 34 / 2
    greens = [toon("G%d" % i, c) for i, c in enumerate(((0.38, 0.74, 0.27), (0.50, 0.83, 0.32), (0.27, 0.62, 0.25)))]
    filler = toon("Filler", (0.13, 0.40, 0.22), rim=False)
    stem_m = toon("Stem", (0.45, 0.52, 0.20))
    thorn_m = toon("Thorn", (0.72, 0.52, 0.26))
    petal_out = toon("PetalOut", (1.0, 0.36, 0.44), spec=0.18)
    petal_in = toon("PetalIn", (0.86, 0.14, 0.32))
    sepal_m = toon("Sepal", (0.30, 0.64, 0.24))

    def periodic(x):
        return [x + s for s in (-P, 0.0, P) if -0.6 <= x + s <= P + 0.6]

    for _ in range(26):
        x0, z = random.uniform(0, P), random.uniform(-core * 0.6, core * 0.6)
        for x in periodic(x0):
            sphere("Fill", col, (x, 0.12, z), (0.26, 0.12, core * 0.95), filler, 20)
    for amp, ph, zc, freq in ((core * 0.55, 0.0, 0.02, 2), (core * 0.45, 1.9, -0.05, 3)):
        pts = [Vector((-0.6 + (P + 1.2) * i / 80, -0.16, 0)) for i in range(81)]
        for p in pts:
            p.z = zc + amp * math.sin(2 * math.pi * freq * p.x / P + ph)
        curve("Stem", col, pts, 0.028, stem_m, poly=True)
        for i in range(0, 80, 5):
            p = pts[i]
            if 0 <= p.x < P:
                for x in periodic(p.x):
                    cone("Thorn", col, (x, -0.17, p.z + (0.03 if i % 10 else -0.03)), 0.018, 0.0, 0.06, thorn_m,
                         rot=(math.radians(0 if i % 10 else 180), 0, 0), segs=8)
    leaf = leaf_outline(0.17, 0.085)
    for _ in range(360):
        x0 = random.uniform(0, P)
        z, y = random.uniform(-core - 0.05, core + 0.05), random.uniform(-0.24, 0.05)
        yaw, roll, tilt = random.uniform(-35, 35), random.uniform(0, 360), random.uniform(-30, 30)
        m = random.choice(greens)
        for x in periodic(x0):
            o = flat_shape("Leaf", col, leaf, m, bend=0.9)
            o.location = (x, y, z)
            o.rotation_euler = (math.radians(tilt), math.radians(roll), math.radians(yaw))
    for _ in range(8):
        x0, z = random.uniform(0, P), random.uniform(-core + 0.05, core - 0.05)
        s = random.uniform(1.45, 1.75)
        for x in periodic(x0):
            rose_head(col, Vector((x, -0.30, z)), s, petal_out, petal_in, sepal_m)
    for _ in range(3):
        x0, z = random.uniform(0, P), random.uniform(-core, core)
        for x in periodic(x0):
            sphere("Bud", col, (x, -0.26, z), (0.035, 0.035, 0.05), petal_out, 16)
            for k in range(3):
                o = flat_shape("BudSepal", col, leaf_outline(0.07, 0.03, 12), sepal_m, bend=0.5)
                o.location = (x, -0.25, z - 0.03)
                o.rotation_euler = (0, math.radians(150 + k * 30), 0)
    camera((P / 2, 0, 0), (0, -1.0, 0.16), P, 512, 136)
    ink(col, 4.5, inner=False)
    render("rose_bush.png")


# ================================================================ flowers
def flower_scene():
    specs = {
        # name: (petal colour, centre colour, petal count, petal length, width, cup)
        "flower_red": ((0.98, 0.26, 0.30), (1.0, 0.82, 0.24), 6, 0.62, 0.52, -0.5),
        "flower_yellow": ((1.0, 0.82, 0.16), (0.55, 0.30, 0.14), 11, 0.66, 0.26, -0.3),
        "flower_blue": ((0.38, 0.52, 1.0), (1.0, 0.95, 0.72), 5, 0.60, 0.60, -0.6),
    }
    for name, (pc, cc, n, ln, wd, cup) in specs.items():
        col, _ = reset()
        pm = toon(name + "P", pc, spec=0.22)
        pm2 = toon(name + "P2", tuple(min(1, v * 0.86) for v in pc), spec=0.15)
        cm = toon(name + "C", cc, spec=0.35)
        seed_m = toon(name + "S", tuple(v * 0.7 for v in cc), flat=True)
        leaf_m = toon(name + "L", (0.40, 0.76, 0.28))
        root = empty("Flower", col, (0, 0, 0))
        outline = petal_outline(ln, wd)
        for ring, (count, off, tilt, grow, mat_) in enumerate(((n, 0.0, 12, 1.0, pm2), (n, math.pi / n, 22, 0.9, pm))):
            for k in range(count):
                a = 2 * math.pi * k / count + off
                o = flat_shape("Petal", col, outline, mat_, root, bend=cup, thickness=0.03, smooth=True)
                o.scale = (grow,) * 3
                o.location = (math.cos(a) * 0.1, -0.02 * ring, math.sin(a) * 0.1)
                o.rotation_euler = (math.radians(tilt), math.pi / 2 - a, 0)
        sphere("Centre", col, (0, -0.10, 0), (0.24, 0.13, 0.24), cm, 32, parent=root)
        for k in range(6):
            a = 2 * math.pi * k / 6
            sphere("Seed", col, (math.cos(a) * 0.12, -0.21, math.sin(a) * 0.12), (0.03,) * 3, seed_m, 10, parent=root)
        for side in (-1, 1):
            o = flat_shape("Leaf", col, leaf_outline(0.55, 0.26), leaf_m, root, bend=0.5, thickness=0.02, smooth=True)
            o.location = (0.05 * side, 0.08, -0.25)
            o.rotation_euler = (0, math.radians(180 - 55 * side), 0)
        root.rotation_euler = (math.radians(-12), 0, math.radians(8))
        fit_camera((0.10, -1.0, 0.10), 512)
        ink(col, 1.1 * 512 / 34, inner=False)
        render(name + ".png")


# ================================================================ cloud
def cloud_scene():
    col, _ = reset()
    m = toon("Cloud", (0.99, 0.99, 1.0), line=(0.52, 0.56, 0.78))
    for x, y, z, r in ((-1.35, 0.0, -0.05, 0.62), (-0.55, 0.0, 0.28, 0.86), (0.35, 0.0, 0.42, 0.98), (1.2, 0.0, 0.12, 0.72),
                       (1.85, 0.0, -0.12, 0.48), (-1.9, 0.0, -0.2, 0.40), (0.0, -0.25, -0.1, 0.7), (0.9, -0.2, -0.15, 0.6)):
        sphere("Puff", col, (x, y, z), (r, r * 0.9, r * 0.92), m, 40)
    sphere("Base", col, (0.0, 0.0, -0.32), (2.2, 0.8, 0.34), m, 48)
    fit_camera((0.0, -1.0, 0.12), 1024)
    ink(col, LINE_GAME_PX * 1024 / 62, inner=False)
    render("cloud.png")


# ================================================================ seagull (4 frames, one camera)
def gull_scene():
    col, _ = reset()
    white = toon("GullWhite", (0.99, 0.99, 1.0), line=(0.36, 0.40, 0.56))
    grey = toon("GullGrey", (0.70, 0.76, 0.86), line=(0.25, 0.30, 0.44))
    tip = toon("GullTip", (0.22, 0.24, 0.32), line=(0.1, 0.1, 0.15))
    beak = toon("Beak", (1.0, 0.66, 0.16), spec=0.3)
    eye = toon("GullEye", (0.08, 0.07, 0.10), rim=False, line=(0.05, 0.05, 0.07))
    root = empty("Gull", col, (0, 0, 0))
    prof = [(0.9 - 1.8 * i / 25, 0.30 * math.sin(math.pi * i / 25) ** 0.7 * (1 - 0.35 * (25 - i) / 25) + 0.003) for i in range(26)]
    lathe("Body", col, prof, white, parent=root)
    sphere("Head", col, (0.78, 0, 0.16), (0.26, 0.24, 0.24), white, parent=root)
    cone("Beak", col, (1.10, 0, 0.12), 0.07, 0.01, 0.26, beak, rot=(0, math.radians(95), 0), segs=16, parent=root)
    sphere("Eye", col, (0.92, -0.19, 0.22), (0.045, 0.02, 0.05), eye, 12, parent=root)
    t = flat_shape("Tail", col, [(0.0, 0.0), (-0.16, 0.34), (0.0, 0.26), (0.16, 0.34)], white, root, thickness=0.03)
    t.location = (-0.82, 0, 0.02)
    t.rotation_euler = (0, math.radians(-90), 0)
    wing_pts = [(-0.12, 0.0), (0.30, 0.0), (0.58, 0.45), (0.56, 0.95), (0.36, 1.32), (0.12, 1.40), (-0.04, 1.10), (-0.16, 0.55)]
    tip_pts = [(0.42, 1.00), (0.56, 0.98), (0.37, 1.33), (0.12, 1.41), (0.04, 1.28), (0.22, 1.18)]
    grey_far = toon("GullGreyFar", (0.58, 0.64, 0.76), line=(0.25, 0.30, 0.44))
    wings = []
    for y, m_body, lag in ((0.22, grey_far, -10), (-0.26, grey, 0)):   # far wing behind, near wing in front
        piv = empty("WingPivot", col, (0.12, y, 0.2), root)
        for pts, m in ((wing_pts, m_body), (tip_pts, tip)):
            o = flat_shape("Wing", col, pts, m, piv, thickness=0.04, smooth=True)
            o.location = (-0.12, 0, 0)
        wings.append((piv, lag))
    frames = [-8, -64, -140, -104]  # up, mid-stroke, down, tucked (about Y: tip sweeps back and down)
    direction = (0.10, -1.0, 0.16)
    for piv, lag in wings:
        piv.rotation_euler = (0, math.radians(-12 + lag), 0)
    fit_camera(direction, 384, margin=1.1)
    ink(col, LINE_GAME_PX * 384 / 40)
    for i, a in enumerate(frames):
        for piv, lag in wings:
            piv.rotation_euler = (0, math.radians(a + lag), 0)
        render("seagull_%d.png" % i)


# ================================================================ celestials
def moon_scene():
    col, _ = reset()
    m = toon("Moon", (1.0, 0.95, 0.72), spec=0.12, line=(0.52, 0.40, 0.22))
    cr = toon("Crater", (0.90, 0.82, 0.58), line=(0.52, 0.40, 0.22))
    sphere("Moon", col, (0, 0, 0), (1, 1, 1), m, 64)
    for d, r in (((-0.35, -1, 0.35), 0.24), ((0.4, -1, -0.2), 0.18), ((-0.1, -1, -0.45), 0.13), ((0.35, -1, 0.45), 0.1), ((-0.6, -1, -0.1), 0.09)):
        pos, n = on_sphere(Vector((0, 0, 0)), 0.97, d)
        sphere("Crater", col, pos, (r, 0.05, r), cr, 32, n.to_track_quat("Y", "Z"))
    fit_camera((0.2, -1.0, 0.15), 640)
    ink(col, LINE_GAME_PX * 640 / 80)
    render("moon.png")


def jupiter_scene():
    col, _ = reset()
    m = toon("Jupiter", bands("Z", 3.2, 0.3, [(0.98, 0.84, 0.62), (0.90, 0.58, 0.34), (1.0, 0.92, 0.74), (0.82, 0.48, 0.30)]),
             line=(0.40, 0.20, 0.10))
    sphere("Jupiter", col, (0, 0, 0), (1, 1, 1), m, 64)
    pos, n = on_sphere(Vector((0, 0, 0)), 0.985, (0.3, -1, -0.28))
    sphere("RedSpot", col, pos, (0.2, 0.04, 0.12), toon("Spot", (0.88, 0.36, 0.26), line=(0.40, 0.14, 0.08)), 32, n.to_track_quat("Y", "Z"))
    fit_camera((0.2, -1.0, 0.15), 640)
    ink(col, LINE_GAME_PX * 640 / 100)
    render("jupiter.png")


def ufo_scene():
    col, _ = reset()
    hull = toon("Hull", (0.78, 0.82, 0.96), spec=0.4, line=(0.24, 0.26, 0.42))
    band_m = toon("Band", (0.56, 0.44, 0.92), spec=0.3)
    glass = toon("Glass", (0.62, 0.96, 0.92), spec=0.6, alpha=0.55, line=(0.18, 0.40, 0.44))
    alien = toon("Alien", (0.52, 0.90, 0.40), spec=0.2)
    alien_eye = toon("AlienEye", (0.05, 0.05, 0.08), flat=True)
    lamp = toon("Lamp", (1.0, 0.92, 0.40), flat=True, glow=0.4, line=(0.5, 0.35, 0.05))
    prof = [(-0.36, 0.02), (-0.3, 0.7), (-0.18, 1.35), (-0.02, 1.55), (0.12, 1.4), (0.24, 0.9), (0.3, 0.3), (0.32, 0.01)]
    lathe("Saucer", col, prof, hull, axis="Z")
    lathe("Band", col, [(-0.06, 1.48), (-0.02, 1.58), (0.04, 1.52)], band_m, axis="Z")
    sphere("Dome", col, (0, 0, 0.3), (0.72, 0.72, 0.62), glass, 48)
    sphere("AlienHead", col, (0, 0.05, 0.42), (0.28, 0.26, 0.3), alien, 32)
    for dx in (-0.1, 0.1):
        sphere("AlienEye", col, (dx, -0.19, 0.48), (0.06, 0.03, 0.08), alien_eye, 12)
    for k in range(8):
        a = 2 * math.pi * k / 8
        sphere("Lamp", col, (1.25 * math.cos(a), 1.25 * math.sin(a), 0.1), (0.1,) * 3, lamp, 16)
    fit_camera((0.0, -1.0, 0.30), 800)
    ink(col, LINE_GAME_PX * 800 / 80)
    render("ufo.png")


# ================================================================ ground + trees (full-bleed strips)
def ground_scene():
    col, _ = reset()
    W, H = 15.68, 0.81
    grass = toon("Grass", (0.46, 0.80, 0.30), line=(0.12, 0.32, 0.10))
    grass2 = toon("Grass2", (0.36, 0.70, 0.26), line=(0.12, 0.32, 0.10))
    soil = toon("Soil", (0.66, 0.44, 0.26), line=(0.30, 0.16, 0.08))
    soil2 = toon("Soil2", (0.56, 0.36, 0.22), line=(0.30, 0.16, 0.08))
    stone = toon("Stone", (0.78, 0.76, 0.82), line=(0.3, 0.3, 0.36))
    random.seed(3)
    rounded_box("Soil", col, (W / 2, 0.3, -H / 2 - 0.1), (W + 2, 0.8, H + 0.2), 0.05, soil)
    for i in range(70):
        x = -0.3 + (W + 0.6) * i / 69
        sphere("Lip", col, (x, -0.12, -0.13), (0.19, 0.12, 0.13), grass if i % 3 else grass2, 20)
    # the turf's top face sits exactly at z=0: that's where the bee stands
    rounded_box("Turf", col, (W / 2, 0.2, -0.12), (W + 2, 0.7, 0.24), 0.08, grass)
    for _ in range(60):
        sphere("Pebble", col, (random.uniform(0, W), -0.12, random.uniform(-0.65, -0.35)),
               (random.uniform(0.05, 0.1), 0.04, random.uniform(0.03, 0.06)), random.choice([soil2, stone]), 12)
    camera((W / 2, 0, -H / 2), (0, -1.0, 0.0), W, 3136, 162)
    ink(col, LINE_GAME_PX * 3136 / 400, inner=False)
    render("ground.png")


def trees_scene():
    col, _ = reset()
    W, H = 15.68, 3.6
    random.seed(9)
    leaf_ms = [toon("T%d" % i, c) for i, c in enumerate(((0.36, 0.74, 0.30), (0.46, 0.82, 0.34), (0.30, 0.64, 0.30), (0.54, 0.84, 0.30)))]
    bark = toon("Bark", (0.62, 0.40, 0.26))
    bush = toon("Bush", (0.30, 0.62, 0.30))
    x = -0.4
    while x < W + 0.6:
        s = random.uniform(0.75, 1.15)
        trunk_h = 1.0 * s
        cylinder("Trunk", col, (x, 0.3, trunk_h / 2), 0.12 * s, trunk_h, bark)
        m = random.choice(leaf_ms)
        cz = trunk_h + 0.55 * s
        for dx, dz, r in ((0, 0, 0.72), (-0.42, -0.2, 0.5), (0.44, -0.18, 0.52), (0.1, 0.42, 0.5)):
            sphere("Canopy", col, (x + dx * s, 0.3, cz + dz * s), (r * s, r * s * 0.9, r * s), m, 32)
        x += random.uniform(1.25, 1.75)
    for i in range(40):
        sphere("Bush", col, (-0.3 + (W + 0.6) * i / 39, -0.2, 0.12), (0.36, 0.3, 0.3), bush, 24)
    camera((W / 2, 0, H / 2), (0, -1.0, 0.0), W, 3136, 720)
    ink(col, LINE_GAME_PX * 3136 / 400, inner=False)
    render("trees.png")


# ================================================================ horizons (full-bleed, bottom flush)
def sun_disc(col, loc, r):
    core = toon("Sun", (1.0, 0.86, 0.36), flat=True, glow=0.25, line=(0.9, 0.55, 0.15))
    halo = toon("Halo", (1.0, 1.0, 0.96), flat=True, alpha=0.26)
    halo2 = toon("Halo2", (1.0, 1.0, 0.96), flat=True, alpha=0.12)
    sphere("Sun", col, loc, (r, 0.05, r), core, 64)
    plain = bpy.data.collections["NoInk"]
    sphere("Halo", plain, Vector(loc) + Vector((0, 0.3, 0)), (r * 1.32, 0.02, r * 1.32), halo, 64)
    sphere("Halo2", plain, Vector(loc) + Vector((0, 0.4, 0)), (r * 1.5, 0.02, r * 1.5), halo2, 64)


def city_scene():
    col, _ = reset()
    W, H = 7.68, 9.20              # the 768x920 canvas, 1 unit = 100 px
    random.seed(12)
    palette = [(1.0, 0.62, 0.56), (0.98, 0.82, 0.44), (0.56, 0.78, 0.98), (0.72, 0.62, 0.96), (0.60, 0.88, 0.70), (1.0, 0.74, 0.86)]
    roof_m = toon("Roof", (0.90, 0.40, 0.36))
    win_m = toon("Window", (1.0, 0.96, 0.72), flat=True, glow=0.15, line=(0.35, 0.28, 0.2))
    hill = toon("HillBack", (0.52, 0.80, 0.52), line=(0.2, 0.4, 0.22))
    sun_disc(col, (W * 0.5, 2.0, H - 2.2), 1.15)
    for i in range(6):
        sphere("Hill", col, (-0.5 + i * 1.7, 1.2, 1.2), (1.4, 0.4, 1.3), hill, 32)
    x = -0.2
    while x < W + 0.2:
        w = random.uniform(0.75, 1.2)
        h = random.uniform(1.4, 2.8)
        m = toon("B%.2f" % x, random.choice(palette), spec=0.08)
        rounded_box("Bldg", col, (x + w / 2, 0.0, h / 2), (w * 0.94, 0.8, h), 0.1, m)
        if random.random() < 0.55:
            cone("Roof", col, (x + w / 2, 0.0, h + 0.28), w * 0.62, 0.02, 0.56, roof_m, rot=(0, 0, math.radians(45)), segs=4)
        cols = max(1, int((w - 0.2) / 0.36))
        for wy in range(int((h - 0.35) / 0.55)):
            for wx in range(cols):
                cx = x + w / 2 + (wx - (cols - 1) / 2) * 0.36
                rounded_box("Win", col, (cx, -0.42, 0.45 + wy * 0.55), (0.2, 0.06, 0.26), 0.03, win_m)
        x += w
    camera((W / 2, 0, H / 2), (0, -1.0, 0.0), H, 1536, 1840)
    ink(col, LINE_GAME_PX * 1536 / 400)
    render("mountain_day.png")


def hills_scene():
    col, _ = reset()
    W, H = 10.24, 6.48             # the 1024x648 content box of the 1024x1024 canvas
    random.seed(4)
    far = toon("FarHill", (0.62, 0.74, 0.96), line=(0.3, 0.36, 0.6))
    mnt = toon("Mountain", (0.60, 0.56, 0.86), line=(0.26, 0.22, 0.46))
    snow = toon("Snow", (1.0, 0.99, 1.0), line=(0.4, 0.42, 0.62))
    mid = toon("MidHill", (0.46, 0.80, 0.46), line=(0.15, 0.38, 0.2))
    near = toon("NearHill", (0.56, 0.86, 0.40), line=(0.16, 0.40, 0.14))
    tree_m = toon("HillTree", (0.30, 0.64, 0.34))
    sun_disc(col, (W * 0.62, 3.0, H - 1.85), 1.0)
    cone("Mountain", col, (W * 0.38, 2.4, 2.1), 2.6, 0.12, 4.4, mnt, segs=7, rot=(0, 0, 0.3))
    cone("Snow", col, (W * 0.38, 2.38, 3.55), 0.95, 0.12, 1.5, snow, segs=7, rot=(0, 0, 0.3))
    for i in range(7):
        sphere("Far", col, (-0.6 + i * 1.8, 1.8, 0.9), (1.6, 0.4, 1.3), far, 32)
    for i in range(6):
        sphere("Mid", col, (-0.2 + i * 2.1, 0.8, 0.4), (1.5, 0.4, 1.0), mid, 32)
    for i in range(5):
        sphere("Near", col, (0.4 + i * 2.5, 0.0, -0.2), (1.7, 0.4, 0.9), near, 32)
    for _ in range(12):
        sphere("Tree", col, (random.uniform(0.3, W - 0.3), 0.5, random.uniform(0.9, 1.3)), (0.22, 0.2, 0.3), tree_m, 20)
    camera((W / 2, 0, H / 2), (0, -1.0, 0.0), W, 2048, 1296)
    ink(col, LINE_GAME_PX * 2048 / 400)
    render("mountain_sunset.png")


# ================================================================ UI
def logo_scene():
    col, ghost_col = reset()
    honey = toon("Honey", (1.0, 0.80, 0.20), spec=0.35, line=(0.45, 0.22, 0.04))
    side = toon("HoneySide", (0.98, 0.56, 0.12), line=(0.45, 0.22, 0.04))
    t = text_obj("Logo", col, "Bee   Bee", honey, 1.6, 0.20, 0.03, 0.0)
    t.data.materials.append(side)
    root, squash, wings, ghosts, ants, face = build_bee(col, ghost_col, scale=0.36)
    set_hidden(face["xeyes"] + [face["o"]], True)
    pose_bee(squash, wings, ghosts, ants, 20, 1, 1, 0, 0)
    root.location = (0.02, -0.5, 0.52)
    root.rotation_euler = (0, math.radians(-12), 0)
    fit_camera((0.08, -1.0, 0.10), 1644, margin=0.04)
    ink(col, 1.6 * 1644 / 320, inner=False)
    render("logo.png")


def play_button_scene():
    col, _ = reset()
    plate = toon("PlayPlate", (0.44, 0.84, 0.40), spec=0.3, line=(0.12, 0.34, 0.14))
    rim_m = toon("PlayRim", (1.0, 0.86, 0.34), spec=0.3, line=(0.46, 0.28, 0.06))
    tri = toon("Tri", (1.0, 1.0, 1.0), line=(0.12, 0.34, 0.14))
    rounded_box("Rim", col, (0, 0.12, 0), (3.1, 0.5, 2.36), 0.45, rim_m)
    rounded_box("Plate", col, (0, -0.02, 0.04), (2.7, 0.5, 1.96), 0.38, plate)
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in ((-0.42, 0, -0.62), (0.62, 0, 0.0), (-0.42, 0, 0.62))]
    bm.faces.new(v)
    o = mesh_obj("Tri", bm, col, tri, smooth=False)
    o.location = (0.06, -0.3, 0.04)
    sol = o.modifiers.new("T", "SOLIDIFY"); sol.thickness = 0.12
    bev = o.modifiers.new("B", "BEVEL"); bev.width = 0.06; bev.segments = 4
    fit_camera((0.0, -1.0, 0.18), 836, margin=0.04)
    ink(col, 1.5 * 836 / 110)
    render("play_button.png")


def plate_scene():
    col, _ = reset()
    top = toon("Plate", (1.0, 0.90, 0.56), spec=0.25, line=(0.46, 0.30, 0.08))
    edge = toon("PlateEdge", (0.96, 0.66, 0.26), line=(0.46, 0.30, 0.08))
    rounded_box("Edge", col, (0, 0.1, -0.05), (4.6, 0.5, 2.0), 0.9, edge)
    rounded_box("Top", col, (0, -0.05, 0.05), (4.4, 0.5, 1.78), 0.82, top)
    fit_camera((0.0, -1.0, 0.18), 1196, margin=0.02)
    ink(col, 1.5 * 1196 / 230, inner=False)
    render("button_plate.png")


SCENES = {
    "bee": bee_scene, "hedge": hedge_scene, "flowers": flower_scene, "cloud": cloud_scene, "gull": gull_scene,
    "moon": moon_scene, "jupiter": jupiter_scene, "ufo": ufo_scene, "ground": ground_scene, "trees": trees_scene,
    "city": city_scene, "hills": hills_scene, "logo": logo_scene, "play": play_button_scene, "plate": plate_scene,
}
for key, fn in SCENES.items():
    if ONLY is None or key in ONLY:
        fn()
        print("SCENE OK", key)
print("DONE 3D assets ->", OUT)
