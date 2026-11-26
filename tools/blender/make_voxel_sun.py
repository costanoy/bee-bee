"""Bee Bee — the sun as voxel art.

  blender --background --factory-startup --python make_voxel_sun.py -- <models_dir> <preview_dir>

A warm, golden ball of cubes with chunky rounded rays, like a sun in a
picture book. The ball (node "Ball") is turned slowly by the game, so it
is painted all the way round, lit from straight above (the one light
that stays put while it turns): a creamy cap, a rich butter-gold middle,
a deeper gold underneath, and a few big soft patches of deeper gold that
drift round with it and show it turning — no disco-tile mottling or
orange spots. Everything that should stay put on screen is on the "Rays"
node, which the game leaves still: a cream highlight crescent over the
upper left of the ball and a warm gold crescent over its lower right
(a thin shell of cubes just clear of the turning ball, so they read as
the light on a sphere however far it has turned), a rim round the ball
that carries them on, and eight plump rounded rays in the body's gold,
each with a lighter tip.

The sun hangs far behind everything (135 units back), so like the
backdrops it is made of bigger cubes (0.3) that land on screen at about
the size of every other cube; same radius as before (7 units). A ball of
single cubes that size costs about 11k triangles, so the ball is built of
2x2x2 macro cubes (STYLE.md: "design in 2x2 macro cubes"); the rim and
the rays are flat and the crescents a single shell, all single cubes,
with their backs left out (the Rays node never turns). Equal faces are merged watertight (vk.build).
The game draws the sun unshaded, with a material of its own (view3d.gd)
that fades it out at sunset; glow() writes the palette as the screen will
show it. Exports sun_voxel.glb (nodes "Ball" and "Rays") and review
renders in the colours the game shows.
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
# and at night (measured per channel on grey swatches in the game's look;
# the sun material's emission does nothing on an unshaded material).
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


BIG = 0.3
R = 7.0 / BIG                  # radius in cubes
M = 2                          # the ball's macro cube, in cubes
RM = R / M

# on screen. A rich butter-gold (hue about 44 degrees, clear of the lemon
# flower's 55; saturation about 0.58, well under the honey bee's 0.86),
# cream at the cap and a deeper gold underneath.
TONES = [(-0.80, (1.0, 0.74, 0.32)), (-0.35, (1.0, 0.80, 0.38)), (0.10, (1.0, 0.84, 0.42)),
         (0.65, (1.0, 0.89, 0.54))]
PATCH = (1.0, 0.78, 0.35)      # the drifting patches: a deeper gold
SHINE = (1.0, 0.95, 0.72)      # the highlight crescent, upper left
SHINE_EDGE = (1.0, 0.91, 0.62) # ... its inner edge, half way to the body
GLOW_DEEP = (1.0, 0.70, 0.28)  # the warm crescent, lower right
GLOW_EDGE = (1.0, 0.76, 0.34)  # ... its inner edge
RIM = (1.0, 0.82, 0.40)        # the rim between the crescents
RAY = (1.0, 0.78, 0.36)        # the rays: the body's gold
RAY_BASE = (1.0, 0.74, 0.32)
RAY_TIP = (1.0, 0.92, 0.64)


def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def patches():
    """(direction, radius in macro cubes): big soft patches all round."""
    out = [(unit((-0.5, -1, 0.15)), 3.6)]
    rng = random.Random(8)
    tries = 0
    while len(out) < 7 and tries < 3000:
        tries += 1
        d = unit((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * 0.7))
        r = rng.choice([2.8, 3.2, 3.6, 4.0])
        if all(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(d, o))))) * RM > r + ro + 2.0 for o, ro in out):
            out.append((d, r))
    return out


def inside(X, Y, Z):
    """Macro cube (X, Y, Z) is the 2x2x2 block of cubes centred on the cube
    corner (2X, 2Y, 2Z): the ball is 2 * int(RM) + 1 macro cubes across,
    which keeps it as wide as the ball of single cubes it replaces."""
    return X * X + Y * Y + Z * Z <= RM * RM


def ball():
    """{cube: colour} for the outer shell of macro cubes."""
    sp = patches()
    n = int(RM) + 2
    vox = {}
    for X in range(-n, n):
        for Y in range(-n, n):
            for Z in range(-n, n):
                if not inside(X, Y, Z) or all(inside(X + a, Y + b, Z + c) for a, b, c in
                                              ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))):
                    continue
                u = unit((X, Y, Z))
                c = vk.ramp(TONES, vk.posterize(u[2], 4, -0.8, 0.65))
                if any(math.acos(max(-1.0, min(1.0, sum(a * b for a, b in zip(u, d))))) * RM < r for d, r in sp):
                    c = vk.mix(c, PATCH, 0.6)
                c = glow(c)
                for i in range(M):
                    for j in range(M):
                        for k in range(M):
                            vox[(X * M - 1 + i, Y * M - 1 + j, Z * M - 1 + k)] = c
    return vox


def swept(vox):
    """{z: radius} that the turning ball reaches in each layer of cubes, at
    the far corner of its farthest cube: the still shell must stay outside
    it, or the ball's corners poke through as it turns."""
    out = {}
    for (x, y, z) in vox:
        r = math.hypot(max(abs(x), abs(x + 1)), max(abs(y), abs(y + 1)))
        out[z] = max(out.get(z, 0.0), r)
    return out


def crescent(px, pz):
    """The paint of the still light at (px, pz) on the face of the disc, or
    None: a crescent is the part of the disc outside a smaller disc pushed
    the other way, so it is thickest at its middle and tapers to nothing."""
    for (ox, oz), k, full, edge in (((0.24, -0.24), 1.02, SHINE, SHINE_EDGE),
                                    ((-0.20, 0.20), 1.03, GLOW_DEEP, GLOW_EDGE)):
        if px * ox + pz * oz > 0.0:
            continue                # only on its own half: clean tips, no strays
        e = math.hypot(px - ox * R, pz - oz * R) - k * R
        if e > 1.6:
            return full
        if e > 0.0:
            return edge
    return None


def shell(sweep):
    """The two crescents over the face of the ball, in 2x2 columns lined up
    with the ball's macro cubes (single columns cost three times the
    triangles, in the steps between them): each column starts at the first
    cube clear of the turning ball, on the camera side, and reaches forward
    as far as the column next to it, so the steps between them are closed
    walls (the game sees the sun from a little above and to the left, and
    open steps showed the ball through them as streaks)."""
    n = int(RM) + 2
    fronts = {}                 # (X, Z) -> (y of the column's back cube, paint)
    for X in range(-n, n):
        for Z in range(-n, n):
            c = crescent(2 * X, 2 * Z)
            cols = [(X * M - 1 + i, Z * M - 1 + k) for i in range(M) for k in range(M)]
            hit = [(x, z) for x, z in cols
                   if (0 if x <= 0 <= x + 1 else min(abs(x), abs(x + 1))) < sweep.get(z, 0.0)]
            if not c or not hit:
                continue
            y = -1
            while any(math.hypot(0 if x <= 0 <= x + 1 else min(abs(x), abs(x + 1)),
                                 min(abs(y), abs(y + 1))) <= sweep.get(z, 0.0) + 0.05 for x, z in cols):
                y -= 1
            fronts[(X, Z)] = (y, c)
    vox = {}
    for (X, Z), (y, c) in fronts.items():
        y0 = min([y] + [fronts[nb][0] + 1 for nb in ((X - 1, Z), (X + 1, Z), (X, Z - 1), (X, Z + 1))
                        if nb in fronts])
        for i in range(M):
            for k in range(M):
                for yy in range(y0, y + 1):
                    vox[(X * M - 1 + i, yy, Z * M - 1 + k)] = glow(c)
    return vox


def rays(sweep):
    """The still part: the crescents (shell()), a rim just outside the
    ball that carries them on, then eight plump rounded rays standing clear
    of it (capsules that taper a little), each with a deeper foot and a
    lighter tip. The rim and rays lie in the ball's own plane, two cubes
    thick."""
    vox = shell(sweep)
    covered = {(x, z) for (x, _, z) in vox}
    n = int(R) + 14
    start, end = R + 6.2, R + 8.0            # the rays' centre line: clear of the ball
    for x in range(-n, n):
        for z in range(-n, n):
            if (x, z) in covered:
                continue
            px, pz = x + 0.5, z + 0.5
            d = math.hypot(px, pz)
            c = None
            if R - 2.5 <= d <= R + 1.8:
                # the rim (inside R it is hidden behind the ball, except
                # where the ball's macro steps leave a notch)
                c = crescent(px, pz) or RIM
            elif d > R + 1.8:
                k = round(math.atan2(pz, px) / (math.pi / 4))
                a = k * math.pi / 4
                along = px * math.cos(a) + pz * math.sin(a)
                across = -px * math.sin(a) + pz * math.cos(a)
                s = min(end, max(start, along))
                f = (s - start) / (end - start)
                if math.hypot(along - s, across) <= 2.5 - 0.6 * f:
                    c = RAY_TIP if along > end + 0.4 else (RAY_BASE if along < start - 0.8 else RAY)
            if c:
                for y in (-1, 0):
                    vox[(x, y, z)] = glow(c)
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


vk.reset()
root = vk.empty("Sun")
mat = vk.material("Voxel")
pivot = vk.empty("Ball", parent=root)
bv = ball()
b = vk.build("BallMesh", bv, mat, pivot, size=BIG, faces=None,
             solid=lambda x, y, z: inside((x + 1) // M, (y + 1) // M, (z + 1) // M))
r = vk.build("Rays", rays(swept(bv)), mat, root, size=BIG, faces=None, skip=vk.NO_BACK)
print("radius in cubes:", round(R, 1))
vk.report("sun ball", pivot)
vk.report("sun rays", r)
vk.report("sun", root, budget=6000)
vk.export(os.path.join(MODELS, "sun_voxel.glb"))

# ---------------------------------------------------------------- review renders
in_game_colours(root)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "sun_front.png"), (0.0, -1.0, 0.0), (0, 0, 0), 26.0, 900, 900)
pivot.rotation_euler = (0, 0, 1.2)              # turned: the patches drift, the crescents, rim and rays stay
pv.shoot(os.path.join(PREVIEW, "sun_turned.png"), (0.0, -1.0, 0.0), (0, 0, 0), 26.0, 900, 900)
pivot.rotation_euler = (0, 0, 0)
pv.shoot(os.path.join(PREVIEW, "sun_3q.png"), (0.7, -1.0, 0.5), (0, 0, 0), 26.0, 900, 900)
print("DONE voxel sun")
