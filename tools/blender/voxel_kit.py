"""Shared voxel-art helpers for the make_voxel_*.py scripts.

Every asset uses the same cube size as the bee once it's in the game
(VOX, in 3D units: 0.04 = 1.6 game px), so the whole world shares one
voxel grid — mixed cube sizes are what makes voxel art look off.
Colours are authored in sRGB and stored as vertex colours; only faces that
touch air are generated. build_mesh (with a slight per-cube jitter) and
build_mesh_merged build exactly what they always did.

The "Toybox honey garden" look (STYLE.md, the style guide that goes with
this kit, has the palette and every number) is paint, not polygons, and
only the new calls use it:
  * colour: mix, ramp, luma, shade (hue-shifted tones: warm lights, cool
    shadows) with tones / hue_ramp built on it, ink (toward the UI's plum
    UI_INK), hash01 / patch for colour that varies in deliberate patches;
  * shapes: ellipsoid, blob (round puffs that know their normals), lit,
    posterize;
  * paint passes over a {cell: colour} dict, seen the way the camera sees
    it (along +Y): gradient (the painted top-to-bottom light), rim (a lit or
    dark band along one side of the silhouette), outline (ink cubes round
    it), with silhouette / front / distance_in for anything else, and
    islands to find features too small to read on a phone;
  * build: the builder for new code — no jitter unless asked, painted face
    light (FACE_LIGHT), gentle AO only in concave crevices (AO), faces the
    camera never sees left out (skip=NO_BACK), and same-colour faces merged
    into watertight polygons (no T-junctions to crack open);
  * tri_count / report for the budgets, Preview(game_like=True) to judge
    the paint without the renderer's own shadows and AO (the game has
    neither).
"""
import bpy, bmesh, math, random, os, colorsys
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
               solid_neighbours=None, skip=()):
    """vox: {(x, y, z): sRGB}. Voxel (x,y,z) spans [x, x+1) etc. times `size`,
    offset by -origin (in voxels). solid_neighbours: extra cells treated as
    filled when culling faces (e.g. the next tile over, so seams have no
    inner walls). skip: face directions to leave out altogether, for sides
    the game's camera can never see (e.g. (0, 1, 0), the back)."""
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
            if (dx, dy, dz) in skip or (x + dx, y + dy, z + dz) in solid:
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
    """Same studio look for every asset's review renders. game_like=True
    turns the renderer's own shadows and ambient occlusion off, as in the
    game, so what you judge is the paint (gradient, rims, baked AO) alone."""

    def __init__(self, game_like=False):
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
            if game_like:
                L.use_shadow = False
            lo = bpy.data.objects.new(name, L)
            s.collection.objects.link(lo)
            lo.rotation_euler = tuple(math.radians(a) for a in rot)
        if game_like:
            for attr, val in (("use_gtao", False), ("use_shadows", False), ("use_raytracing", False)):
                if hasattr(s.eevee, attr):
                    try:
                        setattr(s.eevee, attr, val)
                    except Exception:
                        pass
        self.cd = bpy.data.cameras.new("Cam")
        self.cd.type = "ORTHO"
        self.cam = bpy.data.objects.new("Cam", self.cd)
        s.collection.objects.link(self.cam)
        s.camera = self.cam

    def shoot(self, path, direction, target, scale, rx=900, ry=900, dist=20):
        s = bpy.context.scene
        d = Vector(direction).normalized()
        self.cam.location = Vector(target) + d * dist
        self.cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        self.cd.ortho_scale = scale
        s.render.resolution_x, s.render.resolution_y = rx, ry
        s.render.filepath = path
        bpy.ops.render.render(write_still=True)


def build_mesh_merged(name, cells, mat, parent=None, origin=(0, 0, 0), size=VOX, solid=None, skip=()):
    """Like build_mesh, for big flat assets (the ground): neighbouring cube
    faces of the same colour are merged into one quad, so a surface of
    thousands of cubes costs a few hundred polygons. No per-cube jitter —
    the caller varies colour in patches instead, which is what lets faces
    merge. cells: {(x, y, z): sRGB} for the cubes that show; solid(x, y, z)
    says where the unseen bulk is (faces against it are skipped). skip: face
    directions to leave out altogether, as in build_mesh."""
    planes = {}
    for (x, y, z), c in cells.items():
        for di, ((dx, dy, dz), _) in enumerate(_DIRS):
            n = (x + dx, y + dy, z + dz)
            if (dx, dy, dz) in skip or n in cells or (solid is not None and solid(*n)):
                continue
            if dx:
                key, uv = (di, x), (y, z)
            elif dy:
                key, uv = (di, y), (x, z)
            else:
                key, uv = (di, z), (x, y)
            planes.setdefault(key, {})[uv] = c
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    for (di, plane), mask in planes.items():
        d = _DIRS[di][0]
        axis = 0 if d[0] else (1 if d[1] else 2)
        level = plane + (1 if d[axis] > 0 else 0)
        done = set()
        for (u, v) in sorted(mask):
            if (u, v) in done:
                continue
            c = mask[(u, v)]
            w = 1
            while mask.get((u + w, v)) == c and (u + w, v) not in done:
                w += 1
            h = 1
            while all(mask.get((u + i, v + h)) == c and (u + i, v + h) not in done for i in range(w)):
                h += 1
            for i in range(w):
                for j in range(h):
                    done.add((u + i, v + j))
            pts = []
            for (a, b) in ((u, v), (u + w, v), (u + w, v + h), (u, v + h)):
                p = [a, b]
                p.insert(axis, level)
                pts.append(Vector(((p[0] - origin[0]) * size, (p[1] - origin[1]) * size, (p[2] - origin[2]) * size)))
            if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(Vector(d)) < 0:
                pts.reverse()
            f = bm.faces.new([bm.verts.new(p) for p in pts])
            for l in f.loops:
                l[col] = (*c, 1.0)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    return o


# ================================================================ Toybox honey garden
# Everything below is new and opt-in; nothing above calls it.

UI_INK = (0.24, 0.13, 0.32)      # main.gd UI_INK, the plum outline of the UI text: the world's ink too
NO_BACK = ((0, 1, 0),)                    # the camera is always on the -Y side
NO_BACK_UNDER = ((0, 1, 0), (0, 0, -1))   # ... and above things that stand on the ground

# shade() turns lights toward a warm yellow and shadows toward blue-violet;
# a blue's lights turn toward violet instead, never into the sky's hue band
WARM_HUE = 50.0
COOL_HUE = 255.0
SKY_BAND = (180.0, 262.0)

# painted light per face direction, as shade() amounts: crisp lit tops,
# darker undersides, sides a touch down (the same both ways: the bee and
# the gull turn round). Fronts (-Y) and backs stay as painted.
FACE_LIGHT = {(0, 0, 1): 0.10, (0, 0, -1): -0.16, (1, 0, 0): -0.04, (-1, 0, 0): -0.04}

# where the painted light of round shapes comes from (blob + lit): above,
# a little to the left and in front, like the game's key light
PAINT_LIGHT = Vector((-0.40, -0.50, 0.77)).normalized()

_SIDES = {"top": (0, 1), "bottom": (0, -1), "left": (-1, 0), "right": (1, 0)}


# ---------------------------------------------------------------- colour
def mix(a, b, t):
    """a -> b by t (sRGB); keeps a's alpha, if it has one."""
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3)) + tuple(a[3:])


def ramp(stops, t):
    """stops: [(t, colour), ...] ascending; a linear blend between them, t clamped."""
    if t <= stops[0][0]:
        return stops[0][1]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0) if t1 > t0 else 0.0)
    return stops[-1][1]


def luma(c):
    """Rec. 709 luma of the sRGB values, the measure the art audit uses
    (the day sky is 0.63 on screen)."""
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def shade(c, k, hue=20.0, sat=0.6):
    """A hue-shifted tone of c: k > 0 lighter and warmer, k < 0 darker and
    cooler, k being the change in value (shade(c, -0.2) is 20% darker).
    The hue turns `hue` degrees per unit of k (12 at most) toward WARM_HUE
    for lights and COOL_HUE for shadows, so a yellow's shadow goes orange,
    a green's goes teal and a red's goes crimson; shadows also gain a
    little saturation (richer, not greyer), and a light with no headroom
    left bleaches toward white instead. Greys keep their hue. The turn is
    small on purpose: the game's blue sky light already cools every dark
    (STYLE.md, "What the renderer does to a colour")."""
    h, s, v = colorsys.rgb_to_hsv(*c[:3])
    if k and s > 0.04:
        turn = min(12.0, abs(k) * hue) / 360.0
        hd = h * 360.0
        if k > 0 and SKY_BAND[0] <= hd <= SKY_BAND[1]:
            h = (h + turn) % 1.0
        else:
            delta = ((WARM_HUE if k > 0 else COOL_HUE) / 360.0 - h + 0.5) % 1.0 - 0.5
            h = (h + math.copysign(min(turn, abs(delta)), delta)) % 1.0
    if k < 0:
        v *= max(0.0, 1.0 + k)
        if s > 0.04:
            s = min(1.0, s + (1.0 - s) * sat * -k)
    elif k > 0:
        v *= 1.0 + k
        if v > 1.0:
            s *= max(0.0, 1.0 - (v - 1.0) * 1.5)
            v = 1.0
    return tuple(min(1.0, max(0.0, ch)) for ch in colorsys.hsv_to_rgb(h, s, v)) + tuple(c[3:])


def tones(base, ks=(-0.45, -0.22, 0.0, 0.15, 0.3)):
    """A hue-shifted ramp of base: deep, shadow, base, light, highlight."""
    return [shade(base, k) for k in ks]


def hue_ramp(base, lo=-0.5, hi=0.3, n=9):
    """ramp() stops from shade(base, lo) to shade(base, hi): ramp(stops, k)
    then gives the tone for any k in between (e.g. k = lit(normal) * 0.3)."""
    return [(lo + (hi - lo) * i / (n - 1), shade(base, lo + (hi - lo) * i / (n - 1))) for i in range(n)]


def ink(c, t=1.0):
    """c pulled toward the UI's plum ink by t (1 = the ink itself)."""
    return mix(c, UI_INK, t)


def hash01(x, y, z, seed=0):
    """Position-hashed noise in [0, 1): the same every build, and the same
    for the same cell in every tile that shares it."""
    h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
    h &= 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return h / 4294967296.0


def patch(p, size=2, seed=0):
    """hash01 per block of size^3 cubes: colour that changes in patches
    (no per-cube speckle, and the faces of a patch merge)."""
    return hash01(p[0] // size, p[1] // size, p[2] // size, seed)


# ---------------------------------------------------------------- shapes
def ellipsoid(cx, cy, cz, rx, ry=None, rz=None):
    """The cells whose centres lie inside an ellipsoid (centre and radii in
    cubes; one radius = a ball). Cube (x, y, z) spans [x, x+1)."""
    ry = rx if ry is None else ry
    rz = rx if rz is None else rz
    out = set()
    for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
        for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
            for z in range(math.floor(cz - rz), math.ceil(cz + rz) + 1):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 + ((z + 0.5 - cz) / rz) ** 2 <= 1.0:
                    out.add((x, y, z))
    return out


def blob(puffs, keep=None):
    """A union of round puffs, each (cx, cy, cz, r) or (cx, cy, cz, rx, ry, rz)
    in cubes: {cell: unit normal}, the normal of the puff the cell is most
    inside of, so each puff can be painted as its own little ball (lit).
    keep(x, y, z): which cells to keep (e.g. the tile's columns only)."""
    best = {}
    for pf in puffs:
        cx, cy, cz = pf[:3]
        rx, ry, rz = (pf[3], pf[3], pf[3]) if len(pf) == 4 else pf[3:6]
        for (x, y, z) in ellipsoid(cx, cy, cz, rx, ry, rz):
            if keep is not None and not keep(x, y, z):
                continue
            u, v, w = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, (z + 0.5 - cz) / rz
            d = u * u + v * v + w * w
            if (x, y, z) not in best or d < best[(x, y, z)][0]:
                n = Vector((u / rx, v / ry, w / rz))
                best[(x, y, z)] = (d, n.normalized() if n.length > 1e-6 else Vector((0, -1, 0)))
    return {p: n for p, (d, n) in best.items()}


def lit(n, light=PAINT_LIGHT):
    """How much a surface with normal n faces the painted light (-1..1)."""
    return Vector(n).dot(light)


def posterize(t, steps=4, lo=-1.0, hi=1.0):
    """t snapped to `steps` even levels between lo and hi: cel bands, so a
    lit ball is a few flat patches (which merge) instead of a smooth blur."""
    if steps < 2:
        return t
    q = round((min(hi, max(lo, t)) - lo) / (hi - lo) * (steps - 1))
    return lo + (hi - lo) * q / (steps - 1)


# ---------------------------------------------------------------- paint passes (the camera looks along +Y)
def silhouette(vox):
    """The 2D mask {(x, z)} the camera sees: the cells projected along Y."""
    return {(x, z) for (x, _, z) in vox}


def front(vox):
    """{(x, z): y of the cube nearest the camera} (the lowest y)."""
    out = {}
    for (x, y, z) in vox:
        if (x, z) not in out or y < out[(x, z)]:
            out[(x, z)] = y
    return out


def distance_in(mask, maxd=6):
    """4-neighbour distance from outside for every cell of a 2D mask
    {(x, z)}: 1 = on the outline, 2 = just inside... (up to maxd)."""
    dist = {}
    frontier = []
    for (x, z) in mask:
        if any((x + dx, z + dz) not in mask for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            dist[(x, z)] = 1
            frontier.append((x, z))
    d = 1
    while frontier and d < maxd:
        d += 1
        nxt = []
        for (x, z) in frontier:
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, z + dz)
                if q in mask and q not in dist:
                    dist[q] = d
                    nxt.append(q)
        frontier = nxt
    return dist


def gradient(vox, top=0.08, bottom=-0.20, z0=None, z1=None, steps=None, only=None):
    """The painted vertical light: every cube shade()d by its height, from
    `bottom` at z0 (default: the lowest cube) to `top` at z1 (default: the
    highest). Pass z0/z1 for tiles and for sets of models that must match.
    One tone per cube row, so rows still merge sideways; steps=n paints n
    even bands instead (bands 2-4 cubes tall also merge upward: fewer
    triangles). only(cell, colour): which cubes to touch (e.g. leave the
    catchlights alone)."""
    zs = [p[2] for p in vox]
    lo = min(zs) if z0 is None else z0
    hi = max(zs) if z1 is None else z1
    out = {}
    for p, c in vox.items():
        if only is not None and not only(p, c):
            out[p] = c
            continue
        t = 0.5 if hi == lo else min(1.0, max(0.0, (p[2] - lo) / (hi - lo)))
        if steps:
            t = min(steps - 1, int(t * steps)) / max(1, steps - 1)
        out[p] = shade(c, bottom + (top - bottom) * t)
    return out


def rim(vox, side="top", k=0.15, colour=None, amount=1.0, width=1, fade=False, mask=None, only=None):
    """A band along one side of the silhouette ("top", "bottom", "left",
    "right"): the cubes whose 2D cell has air within `width` cells on that
    side. They are shade()d by k (lit rim: k > 0, dark rim: k < 0), or mixed
    toward `colour` by `amount` (an ink line: colour=UI_INK). fade: the band
    weakens inward (full on the outline, 1/width on its last row). mask: the
    2D silhouette to test against (default: this dict's own; pass the
    union with the neighbouring tiles' so a seam is not an edge). only(cell,
    colour): which cubes to touch."""
    dx, dz = _SIDES[side]
    m = silhouette(vox) if mask is None else mask
    out = {}
    for p, c in vox.items():
        x, _, z = p
        d = next((i for i in range(1, width + 1) if (x + dx * i, z + dz * i) not in m), None)
        if d is None or (only is not None and not only(p, c)):
            out[p] = c
            continue
        f = (1.0 - (d - 1) / width) if fade else 1.0
        out[p] = mix(c, colour, amount * f) if colour is not None else shade(c, k * f)
    return out


def outline(vox, colour=UI_INK, sides=("top", "bottom", "left", "right"), depth=2, inset=0, mask=None):
    """Ink cubes round the silhouette: a 1-cube ring just outside it on the
    given sides (4-neighbour, so round shapes keep round corners), `depth`
    cubes deep from `inset` cubes behind the front of the cube it borders.
    Returns only the new cubes: vox.update(outline(vox, ...)). It grows the
    silhouette by a cube, so keep it off sides that must match a hitbox."""
    m = silhouette(vox) if mask is None else mask
    fr = front(vox)
    start = {}
    for (x, z), y in fr.items():
        for s in sides:
            dx, dz = _SIDES[s]
            q = (x + dx, z + dz)
            if q not in m:
                start[q] = min(start.get(q, y + inset), y + inset)
    out = {}
    for (x, z), y0 in start.items():
        for y in range(y0, y0 + depth):
            if (x, y, z) not in vox:
                out[(x, y, z)] = colour
    return out


def islands(vox, min_cells=9, ignore=()):
    """Features too small to read: the same-colour patches of the front view
    (the cube nearest the camera in each column, 4-neighbour) smaller than
    min_cells (9 = 3x3). ignore: colours that are accents on purpose
    (catchlights, rims, tips). Returns [(colour, cells)], smallest first.
    Run it on the design colours, before the gradient and rims."""
    fr = front(vox)
    face = {(x, z): vox[(x, y, z)][:3] for (x, z), y in fr.items()}
    seen = set()
    out = []
    for q, c in face.items():
        if q in seen or c in ignore:
            continue
        group, todo = [], [q]
        seen.add(q)
        while todo:
            x, z = todo.pop()
            group.append((x, z))
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                r = (x + dx, z + dz)
                if r not in seen and face.get(r) == c:
                    seen.add(r)
                    todo.append(r)
        if len(group) < min_cells:
            out.append((c, sorted(group)))
    return sorted(out, key=lambda g: len(g[1]))


# ---------------------------------------------------------------- baked ambient occlusion
_BALLS = {}


def _ball(radius):
    """The cells round a grid point whose centres lie within radius (cubes)."""
    if radius not in _BALLS:
        R = int(math.ceil(radius))
        _BALLS[radius] = [(i, j, k) for i in range(-R - 1, R + 1) for j in range(-R - 1, R + 1)
                          for k in range(-R - 1, R + 1)
                          if (i + 0.5) ** 2 + (j + 0.5) ** 2 + (k + 0.5) ** 2 <= radius * radius]
    return _BALLS[radius]


class AO:
    """Gentle baked occlusion for concave crevices only (under a clump,
    between two puffs, the flower's cup). Each face corner measures how
    concave the shape is round it: the solid share of the ball of cells
    within `radius` cubes, minus a half (a flat wall is exactly 0, a bump
    is below 0, a crease above). Classic per-corner voxel AO darkens the
    inner corner of every step of a curved front, which is what striped
    the hedge and the trees in the audit; seen through a whole ball the
    steps of a convex shape stay low (measured: balls of radius 4-8, a
    10x5x7 ellipsoid and a hedge-like pill never pass 0.12), so they get
    none, while creases (0.15-0.28) darken from `start` up to `strength`
    (a shade() amount: cooler and richer, not grey) at `full`. It is the same for every face meeting
    at a grid point, so it blends smoothly from cube to cube, and the
    faces it leaves alone still merge; it is snapped to `levels` steps, so
    the faces deep in a crease (shaded the same at all four corners) merge
    too."""

    def __init__(self, strength=0.28, radius=3, start=0.11, full=0.26, levels=4):
        self.strength, self.radius, self.start, self.full, self.levels = strength, radius, start, full, levels
        self._cache = {}

    def concavity(self, occ, g):
        """Solid share of the ball round grid point g, minus 0.5."""
        if g not in self._cache:
            ball = _ball(self.radius)
            self._cache[g] = sum(1 for (i, j, k) in ball if occ((g[0] + i, g[1] + j, g[2] + k))) / len(ball) - 0.5
        return self._cache[g]

    def dark(self, occ, g, d=None):
        """The shade() amount (0..strength) for a face corner at grid point g."""
        t = (self.concavity(occ, g) - self.start) / (self.full - self.start)
        t = min(1.0, max(0.0, t))
        t = t * t * (3.0 - 2.0 * t)
        if self.levels:             # a few even steps: faces shaded the same all over merge
            t = round(t * self.levels) / self.levels
        return self.strength * t


# ---------------------------------------------------------------- the new builder
def _test(cells):
    if cells is None:
        return lambda p: False
    if callable(cells):
        return lambda p: bool(cells(*p))
    return cells.__contains__


def _ears(pts):
    """Triangulates a convex polygon that may have collinear points on its
    edges (a merged rectangle plus the corners of its neighbours), using
    every point, with no sliver of zero area: clip real corners only, and
    never one that would leave the rest of the points on a line."""
    idx = list(range(len(pts)))

    def cross(a, b, c):
        return (pts[b][0] - pts[a][0]) * (pts[c][1] - pts[a][1]) - (pts[b][1] - pts[a][1]) * (pts[c][0] - pts[a][0])

    def flat(ring):
        return all(cross(ring[0], ring[1], r) == 0 for r in ring[2:])

    tris = []
    while len(idx) > 3:
        for n in range(len(idx)):
            a, b, c = idx[n - 1], idx[n], idx[(n + 1) % len(idx)]
            rest = idx[:n] + idx[n + 1:]
            if cross(a, b, c) != 0 and not flat(rest):
                tris.append((a, b, c))
                idx = rest
                break
        else:
            raise ValueError("cannot triangulate %r" % (pts,))
    tris.append(tuple(idx))
    return tris


def build(name, vox, mat, parent=None, origin=(0, 0, 0), size=VOX, solid=None, occluders=None, skip=(),
          ao=None, faces=FACE_LIGHT, merge=True, jitter=0.0, seed=1, alpha=1.0, loc=(0, 0, 0)):
    """The builder for new code. vox: {(x, y, z): sRGB or sRGBA}; cube
    (x, y, z) spans [x, x+1) times `size`, offset by -origin (in cubes).
    solid: extra cells (dict, set or callable(x, y, z)) that hide faces and
    cast AO, e.g. the next tile over (no seam walls, creases run on across
    the seam); occluders: cells that only cast AO. skip: face directions
    never built (NO_BACK for anything that doesn't turn round). ao: an AO()
    or None. faces: per-direction shade() amounts (FACE_LIGHT; None = flat).
    merge: neighbouring faces of one colour with no AO become one polygon,
    which also takes the corners of the faces around it, so there are no
    T-junctions (those open hairline cracks in the game); merge="loose"
    skips that (as build_mesh_merged: fewer triangles, for big surfaces with
    nothing behind them to show through), False builds every face on its
    own. jitter: per-cube value noise, hashed on the position (0, the
    default, = none)."""
    extra, occ_extra = _test(solid), _test(occluders)
    if ao is not None:
        ao._cache.clear()           # the cache belongs to one mesh's cells

    def full(p):
        return p in vox or extra(p)

    def occ(p):
        return full(p) or occ_extra(p)

    flat = {}       # (direction index, plane) -> {(u, v): rgba}
    single = []     # [(corner points, colours, darks)]
    for (x, y, z), c in vox.items():
        a = c[3] if len(c) > 3 else alpha
        base = tuple(c[:3])
        if jitter:
            j = 1.0 + (hash01(x, y, z, seed) * 2.0 - 1.0) * jitter
            base = tuple(min(1.0, v * j) for v in base)
        for di, (d, corners) in enumerate(_DIRS):
            if d in skip or full((x + d[0], y + d[1], z + d[2])):
                continue
            fc = shade(base, faces[d]) if faces and faces.get(d) else base
            pts = [(x + cr[0], y + cr[1], z + cr[2]) for cr in corners]
            darks = [ao.dark(occ, g, d) for g in pts] if ao else [0.0] * 4
            if merge and darks.count(darks[0]) == 4:
                if darks[0]:            # evenly shaded all over: merges like a flat face
                    fc = shade(fc, -darks[0])
                axis = 0 if d[0] else (1 if d[1] else 2)
                cell = (x, y, z)
                uv = tuple(cell[i] for i in range(3) if i != axis)
                flat.setdefault((di, cell[axis]), {})[uv] = fc + (a,)
            else:
                single.append((pts, [(shade(fc, -dk) if dk else fc) + (a,) for dk in darks], darks))

    # greedy rectangles of one colour per plane (as build_mesh_merged)
    rects = []      # (direction index, axis, level, u, v, w, h, rgba)
    for (di, plane), mask in flat.items():
        d = _DIRS[di][0]
        axis = 0 if d[0] else (1 if d[1] else 2)
        level = plane + (1 if d[axis] > 0 else 0)
        done = set()
        for (u, v) in sorted(mask):
            if (u, v) in done:
                continue
            c = mask[(u, v)]
            w = 1
            while mask.get((u + w, v)) == c and (u + w, v) not in done:
                w += 1
            h = 1
            while all(mask.get((u + i, v + h)) == c and (u + i, v + h) not in done for i in range(w)):
                h += 1
            for i in range(w):
                for jj in range(h):
                    done.add((u + i, v + jj))
            rects.append((di, axis, level, u, v, w, h, c))

    def at(axis, level, u, v):
        p = [u, v]
        p.insert(axis, level)
        return tuple(p)

    used = set()
    for pts, _, _ in (single if merge != "loose" else ()):
        used.update(pts)
    for (di, axis, level, u, v, w, h, c) in (rects if merge != "loose" else ()):
        used.update(at(axis, level, a, b) for a, b in ((u, v), (u + w, v), (u + w, v + h), (u, v + h)))

    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    verts = {}

    def vert(p):
        if p not in verts:
            verts[p] = bm.verts.new(((p[0] - origin[0]) * size, (p[1] - origin[1]) * size, (p[2] - origin[2]) * size))
        return verts[p]

    def tri(ps, cs):
        try:
            f = bm.faces.new([vert(p) for p in ps])
        except ValueError:
            return
        for l, cc in zip(f.loops, cs):
            l[col] = cc

    for pts, cols, darks in single:
        # split along the diagonal whose ends are lighter, so a dark corner
        # stays a soft corner instead of a streak across the face
        order = ((1, 2, 3), (1, 3, 0)) if darks[0] + darks[2] > darks[1] + darks[3] else ((0, 1, 2), (0, 2, 3))
        for t in order:
            tri([pts[i] for i in t], [cols[i] for i in t])
    for (di, axis, level, u, v, w, h, c) in rects:
        ring = [(u + i, v) for i in range(w)] + [(u + w, v + j) for j in range(h)] + \
               [(u + w - i, v + h) for i in range(w)] + [(u, v + h - j) for j in range(h)]
        corners = {(u, v), (u + w, v), (u + w, v + h), (u, v + h)}
        ring = [q for q in ring if q in corners or at(axis, level, *q) in used]
        p3 = [Vector(at(axis, level, *q)) for q in ((u, v), (u + w, v), (u + w, v + h))]
        if (p3[1] - p3[0]).cross(p3[2] - p3[0]).dot(Vector(_DIRS[di][0])) < 0:
            ring.reverse()
        for t in _ears(ring):
            tri([at(axis, level, *ring[i]) for i in t], [c] * 3)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o


# ---------------------------------------------------------------- budgets
def tri_count(*objs):
    """Triangles in these objects and everything parented under them."""
    n = 0
    todo = list(objs)
    while todo:
        o = todo.pop()
        todo.extend(o.children)
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            n += len(o.data.loop_triangles)
    return n


def report(label, *objs, budget=None):
    """Prints the triangle count (against a budget, if given) and returns it."""
    n = tri_count(*objs)
    flag = "" if budget is None else ("  (budget %d: %s)" % (budget, "ok" if n <= budget else "OVER"))
    print("TRIS %s: %d%s" % (label, n, flag))
    return n
