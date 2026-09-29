"""Shared voxel-art helpers for the make_voxel_*.py scripts.

Every asset uses the same cube size as the bee once it's in the game
(VOX, in 3D units: 0.04 = 1.6 game px), so the whole world shares one
voxel grid — mixed cube sizes are what makes voxel art look off.
Colours are authored in sRGB and stored as vertex colours with a slight
per-cube jitter; only faces that touch air are generated.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector

VOX = 0.04
BEE_VOX = 0.05          # the bee's own grid, drawn at BEE_SCALE 0.8 in-game -> 0.04


def lin(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def empty(name, loc=(0, 0, 0), parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


def material(name, alpha=1.0, rough=0.65):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeVertexColor")
    a.layer_name = "Col"
    nt.links.new(a.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    if alpha < 1.0:
        nt.links.new(a.outputs["Alpha"], p.inputs["Alpha"])
        m.surface_render_method = "BLENDED"
    return m


_DIRS = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
         ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
         ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
         ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
         ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]


def build_mesh(name, vox, mat, parent=None, origin=(0, 0, 0), size=VOX, jitter=0.045, seed=1, alpha=1.0,
               solid_neighbours=None):
    """vox: {(x, y, z): sRGB}. Voxel (x,y,z) spans [x, x+1) etc. times `size`,
    offset by -origin (in voxels). solid_neighbours: extra cells treated as
    filled when culling faces (e.g. the next tile over, so seams have no
    inner walls)."""
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    verts = {}
    solid = vox if solid_neighbours is None else {**solid_neighbours, **vox}

    def vert(p):
        if p not in verts:
            verts[p] = bm.verts.new(((p[0] - origin[0]) * size, (p[1] - origin[1]) * size, (p[2] - origin[2]) * size))
        return verts[p]

    for (x, y, z), c in vox.items():
        j = 1.0 + rng.uniform(-jitter, jitter)
        cc = tuple(min(1.0, v * j) for v in c)           # the colour layer stores sRGB as-is
        for (dx, dy, dz), corners in _DIRS:
            if (x + dx, y + dy, z + dz) in solid:
                continue
            f = bm.faces.new([vert((x + a, y + b, z + cz)) for a, b, cz in corners])
            for l in f.loops:
                l[col] = (*cc, alpha)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    return o


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_vertex_color="MATERIAL", export_cameras=False, export_lights=False)
    print("EXPORTED", os.path.basename(path))


# ---------------------------------------------------------------- previews
class Preview:
    """Same studio look for every asset's review renders."""

    def __init__(self):
        s = bpy.context.scene
        s.render.engine = "BLENDER_EEVEE"
        s.eevee.taa_render_samples = 96
        s.render.film_transparent = True
        s.view_settings.view_transform = "Standard"
        s.view_settings.look = "None"
        w = bpy.data.worlds.new("W")
        s.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (*lin((0.62, 0.78, 1.0)), 1)
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.85
        for name, rot, energy, color in (("Key", (-45, -35, 0), 3.9, (1.0, 0.97, 0.90)), ("Rim", (-30, 150, 0), 1.8, (0.72, 0.86, 1.0))):
            L = bpy.data.lights.new(name, "SUN")
            L.energy, L.color, L.angle = energy, color, math.radians(6)
            lo = bpy.data.objects.new(name, L)
            s.collection.objects.link(lo)
            lo.rotation_euler = tuple(math.radians(a) for a in rot)
        self.cd = bpy.data.cameras.new("Cam")
        self.cd.type = "ORTHO"
        self.cam = bpy.data.objects.new("Cam", self.cd)
        s.collection.objects.link(self.cam)
        s.camera = self.cam

    def shoot(self, path, direction, target, scale, rx=900, ry=900):
        s = bpy.context.scene
        d = Vector(direction).normalized()
        self.cam.location = Vector(target) + d * 20
        self.cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        self.cd.ortho_scale = scale
        s.render.resolution_x, s.render.resolution_y = rx, ry
        s.render.filepath = path
        bpy.ops.render.render(write_still=True)
