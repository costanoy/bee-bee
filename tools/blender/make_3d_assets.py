"""Bee Bee — builds the bee and the rose hedge as 3D models in Blender and
pre-renders them to sprites for the 2D game.

  blender --background --factory-startup --python make_3d_assets.py -- <out_dir>

Bee: 4 flap frames (wings down -> up, last = rest pose) + a dead pose,
256x256, facing LEFT (the game mirrors it). Hedge: one seamless tile of a
periodic hedge (everything near an edge is duplicated one period over, so
the left and right edges of the render match exactly).
"""
import bpy, math, random, sys, os
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 96
    s.cycles.use_denoising = True
    s.render.film_transparent = True
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    world = bpy.data.worlds.new("World")
    s.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.70, 0.85, 1.0)
    bg.inputs["Strength"].default_value = 0.85
    return s


def mat(name, color, rough=0.45, alpha=1.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Alpha"].default_value = alpha
    if emit:
        p.inputs["Emission Color"].default_value = (*color, 1.0)
        p.inputs["Emission Strength"].default_value = emit
    return m


def striped_mat():
    # Bands along the body's own X axis: the head end stays yellow, then
    # alternating black/yellow rings towards the stinger.
    m = bpy.data.materials.new("BeeBody")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.42
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 1.9
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"; add.inputs[1].default_value = 0.35
    frc = nt.nodes.new("ShaderNodeMath"); frc.operation = "FRACT"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (1.0, 0.70, 0.08, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (0.045, 0.035, 0.03, 1)
    # keep the front third plain yellow
    gate = nt.nodes.new("ShaderNodeMath"); gate.operation = "GREATER_THAN"; gate.inputs[1].default_value = -0.35
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (1.0, 0.70, 0.08, 1)
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nt.links.new(sep.outputs["X"], mul.inputs[0])
    nt.links.new(mul.outputs[0], add.inputs[0])
    nt.links.new(add.outputs[0], frc.inputs[0])
    nt.links.new(frc.outputs[0], ramp.inputs[0])
    nt.links.new(sep.outputs["X"], gate.inputs[0])
    nt.links.new(gate.outputs[0], mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    return m


def sphere(name, loc, scale, material, parent=None, segs=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=1.0, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.shade_smooth()
    o.data.materials.append(material)
    if parent:
        o.parent = parent
    return o


def empty(name, loc, parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def lights():
    for name, direction, strength in (("Key", (-1.0, -1.1, 1.6), 3.6), ("Rim", (1.2, 1.0, 0.6), 1.4)):
        d = bpy.data.lights.new(name, "SUN")
        d.energy = strength
        d.angle = math.radians(8)
        o = bpy.data.objects.new(name, d)
        bpy.context.collection.objects.link(o)
        o.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()


def ortho_camera(target, direction, ortho_scale, res_x, res_y):
    c = bpy.data.cameras.new("Cam")
    c.type = "ORTHO"
    c.ortho_scale = ortho_scale
    o = bpy.data.objects.new("Cam", c)
    bpy.context.collection.objects.link(o)
    d = Vector(direction).normalized()
    o.location = Vector(target) + d * 12.0
    o.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    s = bpy.context.scene
    s.camera = o
    s.render.resolution_x, s.render.resolution_y = res_x, res_y
    s.render.resolution_percentage = 100


def outline(thickness, inner):
    """Cartoon ink line. inner=False draws only the outer contour."""
    sc = bpy.context.scene
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    fs = bpy.context.view_layer.freestyle_settings
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    ls = fs.linesets.new("Ink")
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = inner
    ls.select_border = inner
    ls.select_crease = False
    ls.select_external_contour = True
    ls.linestyle.color = (0.10, 0.06, 0.03)
    ls.linestyle.thickness = thickness


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- bee
def build_bee():
    root = empty("BeeRoot", (0, 0, 0))
    yellow = mat("Yellow", (1.0, 0.70, 0.08), 0.45)
    black = mat("Black", (0.045, 0.035, 0.03), 0.35)
    glossy = mat("Eye", (0.02, 0.02, 0.025), 0.12)
    white = mat("Shine", (1, 1, 1), 0.2, emit=1.5)
    blush = mat("Blush", (1.0, 0.45, 0.40), 0.6)
    wing_m = mat("Wing", (0.86, 0.95, 1.0), 0.15, alpha=0.55)

    body = sphere("Body", (0.28, 0, 0), (0.78, 0.56, 0.56), striped_mat(), root)
    head_c = Vector((-0.58, 0, 0.1))
    sphere("Head", head_c, (0.43, 0.43, 0.42), yellow, root)

    # eyes on the camera-facing (-Y) and forward (-X) side of the head
    for side, dy in ((1, -1), (0, 1)):
        n = Vector((-0.62, 0.52 * dy, 0.28)).normalized()
        e = head_c + n * 0.34
        sphere("Eye", e, (0.155, 0.155, 0.185), glossy, root)
        sphere("Shine", e + Vector((-0.03, -0.11 * (1 if dy < 0 else -1), 0.08)), (0.05,) * 3, white, root, 16)
    sphere("Cheek", head_c + Vector((-0.2, -0.33, -0.12)), (0.07, 0.03, 0.05), blush, root, 16)

    # antennae
    for dy in (-1, 1):
        cu = bpy.data.curves.new("Ant", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.028
        cu.bevel_resolution = 4
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(1)
        a, b = sp.bezier_points
        a.co = head_c + Vector((-0.08, 0.13 * dy, 0.36))
        a.handle_left = a.co - Vector((0, 0, 0.1)); a.handle_right = a.co + Vector((-0.05, 0.02 * dy, 0.25))
        b.co = head_c + Vector((-0.42, 0.24 * dy, 0.78))
        b.handle_left = b.co + Vector((0.12, 0, -0.1)); b.handle_right = b.co + Vector((-0.1, 0, 0.05))
        ob = bpy.data.objects.new("Ant", cu)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(black)
        ob.parent = root
        sphere("AntTip", b.co, (0.065,) * 3, black, root, 24)

    # stinger
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.09, depth=0.28, location=(1.12, 0, -0.03))
    st = bpy.context.object
    st.rotation_euler = (0, math.radians(90), 0)
    st.data.materials.append(black)
    st.parent = root
    bpy.ops.object.shade_smooth()

    # wings: a pivot at the wing root, the membrane offset up/back from it
    wings = []
    for dy in (-1, 1):
        piv = empty("WingPivot", (0.18, 0.2 * dy, 0.42), root)
        w = sphere("Wing", (0.16, 0, 0.36), (0.36, 0.035, 0.24), wing_m, piv, 32)
        w.rotation_euler = (0, math.radians(-28), 0)
        wings.append((piv, dy))
    return root, wings


def pose_wings(wings, angle_deg):
    for piv, dy in wings:
        # positive angle swings the near (-Y) wing out towards the camera
        piv.rotation_euler = (math.radians(angle_deg) * (-dy), 0, 0)


def bee_scene():
    reset()
    lights()
    root, wings = build_bee()
    outline(6.0, True)
    ortho_camera((0.1, 0, 0.18), (-0.30, -1.0, 0.38), 2.9, 256, 256)
    for i, angle in enumerate((105, 72, 40, 12)):
        pose_wings(wings, angle)
        render(os.path.join(OUT, "bee_flap_%d.png" % i))
    # dead: belly up, wings folded
    pose_wings(wings, 8)
    root.rotation_euler = (math.radians(180), 0, 0)
    root.location = (0, 0, 0.25)
    render(os.path.join(OUT, "bee_dead.png"))


# ---------------------------------------------------------------- hedge
def hedge_scene():
    reset()
    lights()
    random.seed(7)
    P = 4.0                       # period = tile width in Blender units
    H = P * 136 / 512             # visible height of the 512x136 tile
    core = H * 22 / 34 / 2        # half-height of the collision band

    greens = [mat("G%d" % i, c, 0.6) for i, c in enumerate(
        ((0.10, 0.36, 0.10), (0.16, 0.48, 0.13), (0.24, 0.58, 0.16), (0.08, 0.28, 0.09)))]
    leaf_m = [mat("L%d" % i, c, 0.5) for i, c in enumerate(((0.22, 0.62, 0.18), (0.30, 0.70, 0.22), (0.14, 0.46, 0.14)))]
    red = mat("Rose", (0.86, 0.06, 0.10), 0.4)
    dark_red = mat("RoseDark", (0.45, 0.02, 0.05), 0.45)

    specs = []
    for _ in range(95):   # leafy clumps forming the body of the hedge
        r = random.uniform(0.13, 0.24)
        specs.append(("clump", random.uniform(0, P), random.uniform(0.0, 0.25),
                      random.uniform(-core + 0.04, core - 0.04), r, random.choice(greens), 0))
    for _ in range(170):  # individual leaves on the front face
        specs.append(("leaf", random.uniform(0, P), random.uniform(-0.22, -0.12),
                      random.uniform(-core - 0.06, core + 0.06), 0, random.choice(leaf_m), random.uniform(0, 360)))
    for _ in range(14):   # roses
        specs.append(("rose", random.uniform(0, P), -0.26, random.uniform(-core + 0.05, core - 0.03), 0, red, random.uniform(0, 360)))

    def place(kind, x, y, z, r, m, rot):
        if kind == "clump":
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r, location=(x, y, z))
            o = bpy.context.object
            o.scale = (random.uniform(0.9, 1.3), 0.8, random.uniform(0.75, 1.0))
            bpy.ops.object.shade_smooth()
            o.data.materials.append(m)
        elif kind == "leaf":
            o = sphere("Leaf", (x, y, z), (0.085, 0.018, 0.045), m, None, 16)
            o.rotation_euler = (math.radians(random.uniform(-25, 25)), math.radians(rot), 0)
        else:
            sphere("RoseCore", (x, y, z), (0.05, 0.05, 0.05), dark_red, None, 20)
            for k in range(5):
                a = math.radians(rot + k * 72)
                o = sphere("Petal", (x + math.cos(a) * 0.055, y + 0.02, z + math.sin(a) * 0.055),
                           (0.062, 0.03, 0.05), m, None, 20)
                o.rotation_euler = (0, -a, 0)

    for spec in specs:
        kind, x, y, z, r, m, rot = spec
        for shift in (-P, 0.0, P):
            xs = x + shift
            if -0.5 <= xs <= P + 0.5:
                place(kind, xs, y, z, r, m, rot)

    outline(3.5, False)
    ortho_camera((P / 2, 0, 0), (0, -1.0, 0.18), P, 512, 136)
    render(os.path.join(OUT, "rose_bush.png"))


bee_scene()
hedge_scene()
print("DONE 3D assets ->", OUT)
