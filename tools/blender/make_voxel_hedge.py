"""Bee Bee — the rose hedge (obstacle) as voxel art: three tiles and the two
end caps that close each bar at the gap.

  blender --background --factory-startup --python make_voxel_hedge.py -- <models_dir> <preview_dir> [<bee.glb>]

A plump, rounded garland of leafy puffs, painted to read as danger at phone
size (STYLE.md has the palette, the recipe and the numbers): a deep green
body lit per puff in flat bands, a lit yellow-green lip along the top, a
plum ink line along the underside, big coral-pink roses, and hooked plum
thorns with warm-white tips on the top and bottom edges.

Tiles (hedge_voxel_a/b/c): TILE cubes wide (0.96 units), cubes x 0..23
(origin at the left edge), z -9..8 round the collision band (obstacle.gd
THICK = 13.75 cubes, +-6.9: the body never comes thinner than +-7 and tops
out at +-9, thorn tips reach +-11), front = -Y, back faces left out. The
game lays them whole, never stretched, outward from the end caps. They butt
in any order: the core and the puffs centred on the tile edges (SHARED) are
the same in every variant, and whatever a variant changes (its own puffs,
roses, thorns) stays inside columns EDGE..TILE-EDGE-1. Seam walls are left
out (the next tile is always there) and the open edges on each seam get a
vertex at every cube, so neighbouring tiles meet vertex to vertex: no crack.
Caps: hedge_voxel_cap_l is the right end of a left bar, cubes x -CAP..-1,
origin at its right edge = the gap edge; hedge_voxel_cap_r is the left end
of a right bar, x 0..CAP-1, origin at its left edge (the game butts the
tiles against their far side, CAP cubes = 19.2 px from the gap edge). Their
tile side carries on from a tile's edge; the gap side rounds off, outlined
(ink below, the lit lip round the upper corner), without ever passing the
gap edge, and still covers the collision band there. Both are lit from the
upper left like everything else, so cap_r is built in its own right, not
mirrored. Exports the five GLBs and review renders.
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
BEE = ARGS[2] if len(ARGS) > 2 else os.path.join(MODELS, "bee_voxel.glb")
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

TILE = 24
EDGE = 3                   # columns at each tile end that every variant shares (the AO's reach)
CAP = 12                   # cap width in cubes: a tile's EDGE columns, then its own END
END = 9                    # the cap's own columns at the gap end
Z_LO, Z_HI = -9, 8         # body cubes (thorns stand on them)
Y_BACK = 0                 # last cube row in depth (its back faces are skipped)
END_RX, END_RZ = 6, 3      # the cap end's rounded corners seen from the front (elliptic, in cubes)
END_RY = 6                 # ... and from above: the end is a dome
Y_MID = -2.5               # the middle of the bush in depth

# STYLE.md palette (authored sRGB), judged in the game mock under the new
# lighting: H_BASE and H_SHADE a touch lighter (the body's median luma 0.37
# by day against the sky's 0.64), the roses a pinker coral (STYLE's read as
# salmon, too near the red flower)
H_LIP = (0.49, 0.77, 0.23)
H_LIGHT = (0.25, 0.56, 0.19)
H_BASE = (0.13, 0.45, 0.17)
H_SHADE = (0.07, 0.34, 0.15)
H_DEEP = (0.03, 0.19, 0.09)
H_INK = (0.20, 0.08, 0.17)
R_HI = (1.00, 0.82, 0.74)
R_LIGHT = (1.00, 0.56, 0.54)
R_BASE = (1.00, 0.37, 0.40)
R_DEEP = (0.84, 0.20, 0.31)
R_HEART = (0.60, 0.08, 0.21)
SEPAL = (0.38, 0.67, 0.17)
INK = (0.22, 0.08, 0.19)
THORN = (0.42, 0.19, 0.25)
THORN_TIP = (1.00, 0.90, 0.64)
GREENS = [(-0.6, H_DEEP), (-0.2, H_SHADE), (0.2, H_BASE), (0.6, H_LIGHT)]

# puffs: (x, y, z, r) or (x, y, z, rx, ry, rz) in cubes, tile coordinates.
# The bush is round leafy balls in two staggered rows (upper and lower,
# their crowns scalloping the top and bottom edges) and smaller balls in
# front of them, over a soft core (a chain of long ellipsoids every 8
# cubes) that keeps the body at +-7 or more between the balls.
CORE = [(x, 0.0, 0.0, 12.0, 4.5, 7.4) for x in (0, 8, 16)]
# the balls that reach into the EDGE columns: the same in every tile
SHARED = [(0.0, -2.0, 3.6, 5.4), (4.5, -2.0, -3.8, 5.2), (19.5, -2.0, -3.8, 5.2), (0.0, -3.5, -0.5, 3.4)]
# what each variant adds: its middle balls (all clear of the EDGE columns),
# roses (x, z of the centre, sprite) on its front balls, thorns (x of the
# foot's middle) on the top and bottom edges. Rose sizes, heights and
# spacings differ per variant, so a long bar never reads as a polka-dot grid.
VARIANTS = {
    "a": dict(puffs=[(8.5, -2.0, 3.8, 5.2), (15.5, -1.8, 3.4, 5.4), (12.0, -2.0, -4.0, 5.6),
                     (9.5, -4.2, 0.5, 4.2)],
              roses=[(9.5, 1.0, "big")], buds=[],
              thorns_top=[4, 12, 18], thorns_bottom=[8, 17]),
    "b": dict(puffs=[(12.0, -2.0, 3.0, 6.6, 5.4, 6.0), (9.0, -2.0, -4.2, 5.0), (15.0, -2.0, -3.6, 5.0),
                     (8.0, -4.0, 2.0, 3.6), (16.0, -4.0, -2.0, 3.6)],
              roses=[(8.0, 2.0, "mid"), (16.0, -2.0, "mid")], buds=[],
              thorns_top=[5, 11, 17], thorns_bottom=[6, 15]),
    "c": dict(puffs=[(8.0, -2.0, 3.4, 4.6), (14.0, -2.2, 4.0, 5.6), (11.5, -2.0, -4.4, 5.4),
                     (10.5, -4.0, -1.5, 3.8), (16.5, -3.6, -2.5, 3.4)],
              roses=[(16.5, -2.5, "small")], buds=[(6, 4)],
              thorns_top=[5, 9, 18], thorns_bottom=[5, 12, 18]),
}
# hand-drawn roses, rows top to bottom: w highlight, o lit outer petal,
# m petal, d swirl, h heart, l sepal leaf
ROSES = {
    "big": ["..oooo..",
            ".owooom.",
            "oodddomm",
            "odmmhdmm",
            "odmhhdmm",
            "omddddmm",
            "lmmmmmml",
            "ll.mm.ll"],
    "mid": ["..ooo..",
            ".owoom.",
            "oodddmm",
            "odmhdmm",
            "odhhdmm",
            "lmdddml",
            "ll.m.ll"],
    "small": [".ooom.",
              "owoomm",
              "oddhmm",
              "odhdmm",
              "lmddml",
              "ll..ll"],
}
ROSE_COL = {"w": R_HI, "o": R_LIGHT, "m": R_BASE, "d": R_DEEP, "h": R_HEART, "l": SEPAL}
# the cap's own clump at the gap end (cap_l coordinates; mirrored for
# cap_r), and its thorns (x of the foot's middle, cap_l; up), both hooked
# toward the gap, their tips short of the gap edge
END_PUFFS = [(-4.8, -2.0, 3.4, 4.8), (-3.8, -2.0, -4.0, 4.2), (-5.0, -3.6, -0.5, 3.6)]
CAP_THORNS = [(-5, 1), (-5, -1)]
BUD = ["oom",
       "omd",
       ".l."]


def periodic(puffs, k=(-1, 0, 1, 2)):
    return [(p[0] + i * TILE,) + tuple(p[1:]) for i in k for p in puffs]


def in_band(x, y, z):
    return Z_LO <= z <= Z_HI and y <= Y_BACK


def bands(shp):
    """Each puff lit as its own ball, in four flat bands of the hedge greens."""
    return {p: vk.ramp(GREENS, vk.posterize(vk.lit(n) * 0.9 - 0.3, 4, -0.6, 0.6)) for p, n in shp.items()}


def despeckle(vox, zone):
    """Band patches too small to read (under 2x2 cubes in the front view, where
    two puffs meet) take the colour most of their neighbours have: no
    speckle, and their faces merge. Only in the columns zone(x) allows, so
    the shared edge columns stay exactly as every tile has them."""
    out = dict(vox)
    fr = vk.front(vox)
    for c, cells in vk.islands(vox, 4):
        for (x, z) in cells:
            if not zone(x):
                continue
            ns = [vox[(x + dx, fr[(x + dx, z + dz)], z + dz)] for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))
                  if (x + dx, z + dz) in fr]
            ns = [n for n in ns if n != c]
            if ns:
                out[(x, fr[(x, z)], z)] = max(sorted(set(ns)), key=ns.count)
    return out


def painted(shp, zone=lambda x: False):
    """The bands (despeckled inside zone), then the vertical gradient (the
    same z0/z1 for every tile and cap)."""
    return vk.gradient(despeckle(bands(shp), zone), top=0.08, bottom=-0.20, z0=Z_LO, z1=Z_HI, steps=4)


def rims(vox):
    vox = vk.rim(vox, "top", colour=H_LIP)
    return vk.rim(vox, "bottom", colour=H_INK)


def add_rose(vox, cx, cz, kind):
    """A rose sprite on a little dome: its petals 1-2 cubes proud of the
    front-most leaf under it (highest in the middle), its swirl a cube
    lower (a groove the AO deepens), its sepals flat on the leaves."""
    rows = ROSES[kind]
    n = len(rows)
    cells = []
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != ".":
                rr = math.hypot(c - (n - 1) / 2, (n - 1) / 2 - r) / (n / 2)
                cells.append((int(math.floor(cx - n / 2 + c + 0.5)), int(math.floor(cz + n / 2 - r - 0.5)), ch, rr))
    fr = vk.front(vox)
    y0 = min(fr[(x, z)] for x, z, ch, rr in cells if ch != "l")
    for x, z, ch, rr in cells:
        back = fr.get((x, z), y0)
        if ch == "l":
            top = min(y0, back - 1)
        else:
            top = y0 - max(1, 1 + round(1.2 * math.sqrt(max(0.0, 1.0 - rr * rr))) - (ch == "d"))
        for y in range(top, back):
            vox[(x, y, z)] = ROSE_COL[ch]


def add_bud(vox, x, z):
    """A closed bud, 3x3, its top-left corner at (x, z): a cube proud of the leaves."""
    fr = vk.front(vox)
    y0 = min(fr[(x + c, z - r)] for r in range(3) for c in range(3))
    for r, row in enumerate(BUD):
        for c, ch in enumerate(row):
            if ch != ".":
                p = (x + c, z - r)
                for y in range(y0 - (1 if ch == "l" else 2), fr[p]):
                    vox[(p[0], y, p[1])] = ROSE_COL[ch]


def add_thorn(vox, x, up, lean=1):
    """A hooked thorn on the top (up=1) or bottom (up=-1) edge, seen from the
    front as a 3-2-1 spike leaning toward `lean` (+x or -x): a 3-wide ink
    foot on the crest (2 cubes deep), a 2-wide plum neck and a warm-white
    tip over the neck's leaning side (1 deep: from above it tapers too).
    The foot never stands past the body's last row, so the tip stays inside
    +-11 cubes."""
    crest = {}
    for (cx, cy, cz) in vox:
        if x - 1 <= cx <= x + 1:
            k = cz * up
            if cx not in crest or (k, -cy) > (crest[cx][0], -crest[cx][1]):
                crest[cx] = (k, cy)
    top = max(k for k, _ in crest.values())
    z0 = up * min(top + 1, Z_HI if up > 0 else -Z_LO)
    y0 = crest[x][1]
    for dx in (-1, 0, 1):
        for dy in (0, 1):
            vox[(x + dx, y0 + dy, z0)] = INK
            for zz in (z0 - up, z0 - 2 * up):     # rest the foot on the leaves
                if (x + dx, y0 + dy, zz) in vox:
                    break
                vox[(x + dx, y0 + dy, zz)] = INK
    vox[(x, y0, z0 + up)] = THORN
    vox[(x + lean, y0, z0 + up)] = THORN
    vox[(x + lean, y0, z0 + 2 * up)] = THORN_TIP


def strip():
    """What every tile has in common (the core and the SHARED puffs, painted),
    for the columns either side of a tile: the neighbour a seam sees."""
    shp = vk.blob(periodic(CORE + SHARED),
                  keep=lambda x, y, z: -EDGE <= x < TILE + EDGE and in_band(x, y, z))
    return rims(painted(shp))


def tile(name):
    v = VARIANTS[name]
    shp = vk.blob(periodic(CORE + SHARED) + v["puffs"], keep=lambda x, y, z: 0 <= x < TILE and in_band(x, y, z))
    vox = rims(painted(shp, lambda x: EDGE <= x < TILE - EDGE))
    for (rx, rz, kind) in v["roses"]:
        add_rose(vox, rx, rz, kind)
    for (bx, bz) in v["buds"]:
        add_bud(vox, bx, bz)
    for tx in v["thorns_top"]:
        add_thorn(vox, tx, 1)
    for tx in v["thorns_bottom"]:
        add_thorn(vox, tx, -1)
    return vox


def cap(side):
    """side -1: hedge_voxel_cap_l (x -CAP..-1, the gap at x 0); +1:
    hedge_voxel_cap_r (x 0..CAP-1, the gap at x 0, the tile at x CAP). Its
    tile side is a tile's edge columns; its gap end is a plump clump of its
    own (END_PUFFS), cut by a box with rounded corners (END_RX x END_RZ)
    so the end column still covers the band (+-7), and rounded from above
    (END_RY): a dome. Near the end the paint follows the dome, and the end
    is outlined: ink on its lower part, the lit lip round its upper corner."""
    off = -CAP if side < 0 else CAP - TILE          # tile x -> cap x
    lo, hi = (-CAP, -1) if side < 0 else (0, CAP - 1)

    def into(x, r):
        """How far column x is into an end rounding of radius r (0 outside it)."""
        return max(0.0, (x + 0.5 + r) if side < 0 else (r - (x + 0.5)))

    def own(x):
        return x >= -END if side < 0 else x < END

    def keep(x, y, z):
        if not (lo <= x <= hi and in_band(x, y, z)):
            return False
        half = Z_HI + 1 - END_RZ * (1.0 - math.sqrt(max(0.0, 1.0 - (into(x, END_RX) / END_RX) ** 2)))
        s = math.sqrt(max(0.0, 1.0 - (into(x, END_RY) / END_RY) ** 2))
        return abs(z + 0.5) <= half and Y_MID - 5.5 * s <= y + 0.5 <= Y_MID + 3.0 * s

    shp = vk.blob([(p[0] + off,) + tuple(p[1:]) for p in periodic(CORE + SHARED, k=(-1, 0, 1))], keep=keep)
    shp.update(vk.blob([(p[0] if side < 0 else -p[0],) + tuple(p[1:]) for p in END_PUFFS],
                       keep=lambda x, y, z: own(x) and keep(x, y, z)))
    # near the end, the paint follows the dome (an ellipsoid round the end)
    xc = side * END_RY
    for p, n in shp.items():
        t = into(p[0], END_RY) / END_RY
        if t > 0:
            dome = Vector(((p[0] + 0.5 - xc) / END_RY ** 2, (p[1] + 0.5 - Y_MID) / 5.5 ** 2, (p[2] + 0.5) / 9.0 ** 2))
            shp[p] = n.lerp(dome.normalized(), t).normalized()
    vox = rims(painted(shp, own))
    fr = vk.front(vox)
    # the end's outline, on its front cube only (from the side the dome stays
    # green): ink below, the lip round the upper corner, lit as the top is
    end = "right" if side < 0 else "left"
    edge = lambda p: into(p[0], END_RX) > 0 and p[1] == fr[(p[0], p[2])]
    vox = vk.rim(vox, end, colour=INK, amount=0.8, only=lambda p, c: edge(p) and p[2] <= 2)
    vox = vk.rim(vox, end, colour=H_LIP, amount=0.5 if side < 0 else 0.8, only=lambda p, c: edge(p) and p[2] > 2)
    for (tx, up) in CAP_THORNS:
        add_thorn(vox, tx if side < 0 else -1 - tx, up, -side)
    return vox


def seal_seams(o, xs):
    """A vertex at every cube along the open edges that lie on the seam
    planes x = xs (in cubes): the mesh on the other side has the same, so
    the two meet vertex to vertex (a merged face's long edge against the
    next tile's short ones would be a T-junction across the two meshes, and
    those open hairline cracks of sky). Fans the triangle on such an edge
    from its third corner, so no new T-junction appears inside the mesh."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    col = bm.loops.layers.color.active or bm.loops.layers.color[0]
    s = vk.VOX
    at = {tuple(round(c / s) for c in v.co): v for v in bm.verts}
    added = 0
    for X in xs:
        for e in [e for e in bm.edges if e.is_boundary and all(abs(v.co.x / s - X) < 1e-4 for v in e.verts)]:
            n = round(e.calc_length() / s)
            if n <= 1:
                continue
            f = e.link_faces[0]
            l = next(l for l in f.loops if l.edge == e)
            a, b, c = l, l.link_loop_next, l.link_loop_next.link_loop_next
            ca, cb, cc = tuple(a[col]), tuple(b[col]), tuple(c[col])
            pa, pb, vc = a.vert.co.copy(), b.vert.co.copy(), c.vert
            pts = [a.vert]
            for i in range(1, n):
                q = pa.lerp(pb, i / n)
                key = tuple(round(v / s) for v in q)
                if key not in at:
                    at[key] = bm.verts.new(q)
                pts.append(at[key])
            pts.append(b.vert)
            bm.faces.remove(f)
            for i in range(n):
                nf = bm.faces.new((pts[i], pts[i + 1], vc))
                for lp, cl in zip(nf.loops, (tuple(ca[k] + (cb[k] - ca[k]) * i / n for k in range(4)),
                                             tuple(ca[k] + (cb[k] - ca[k]) * (i + 1) / n for k in range(4)), cc)):
                    lp[col] = cl
            added += n - 1
    bm.to_mesh(me)
    bm.free()
    return added


def build(name, vox, solid, seams, parent=None):
    o = vk.build(name, vox, vk.material("Voxel"), parent, solid=solid, skip=vk.NO_BACK, ao=vk.AO())
    n = seal_seams(o, seams)
    if parent is not None:
        print("SEAL %s: %d vertices added along the seams" % (name, n))
    return o


def columns(vox, xs):
    return {(x % TILE, y, z): c for (x, y, z), c in vox.items() if x in xs}


# ---------------------------------------------------------------- build and export
STRIP = strip()


def beside(x, y, z):
    """The neighbour across a tile's seams: the shared columns of any tile."""
    return not (0 <= x < TILE) and (x, y, z) in STRIP


tiles = {name: tile(name) for name in VARIANTS}
caps = {"cap_l": cap(-1), "cap_r": cap(1)}
for name, vox in tiles.items():
    vk.reset()
    root = vk.empty("Hedge")
    build("Hedge", vox, beside, (0, TILE), root)
    vk.report("hedge %s" % name, root, budget=2000)
    vk.export(os.path.join(MODELS, "hedge_voxel_%s.glb" % name))
# a cap's tile side is a tile edge: cap_l's x -CAP is a tile's column 0, cap_r's x CAP-1 a tile's column 23
CAP_SOLID = {"cap_l": lambda x, y, z: x < -CAP and (x + CAP, y, z) in STRIP,
             "cap_r": lambda x, y, z: x >= CAP and (x + TILE - CAP, y, z) in STRIP}
for name, vox in caps.items():
    vk.reset()
    root = vk.empty("HedgeCap")
    build("HedgeCap", vox, CAP_SOLID[name], (-CAP,) if name == "cap_l" else (CAP,), root)
    vk.report("hedge %s" % name, root, budget=1000)
    vk.export(os.path.join(MODELS, "hedge_voxel_%s.glb" % name))

# seams: every variant's edge columns (shape and paint) are the shared ones,
# and each cap's tile side is too, so any pair butts flush
ref_l, ref_r = columns(STRIP, range(0, EDGE)), columns(STRIP, range(TILE - EDGE, TILE))
for name, vox in tiles.items():
    print("SEAM %s: left edge = shared %s, right edge = shared %s"
          % (name, columns(vox, range(0, EDGE)) == ref_l, columns(vox, range(TILE - EDGE, TILE)) == ref_r))
print("SEAM cap_l: tile side = a tile's left edge %s"
      % ({(x + CAP, y, z): c for (x, y, z), c in caps["cap_l"].items() if x < -CAP + EDGE} == ref_l))
print("SEAM cap_r: tile side = a tile's right edge %s"
      % ({(x + TILE - CAP, y, z): c for (x, y, z), c in caps["cap_r"].items() if x >= CAP - EDGE} == ref_r))
for name, vox in list(tiles.items()) + list(caps.items()):
    xs = [p[0] for p in vox]
    zs = [p[2] for p in vox]
    ys = [p[1] for p in vox]
    print("BOX %s: x %d..%d y %d..%d z %d..%d" % (name, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
for name in ("cap_l", "cap_r"):
    vox = caps[name]
    end = -1 if name == "cap_l" else 0
    zs = sorted(z for (x, y, z), c in vox.items() if x == end and c not in (THORN, THORN_TIP))
    print("CAP %s: gap-side column x %d covers z %d..%d (band -7..6)" % (name, end, zs[0], zs[-1]))
for name, vox in list(tiles.items()) + list(caps.items()):
    body = [(x, z) for (x, y, z), c in vox.items() if c not in (INK, THORN, THORN_TIP)]
    cols = sorted({x for x, _ in body})
    thin = [x for x in cols if max(z for xx, z in body if xx == x) < 6 or min(z for xx, z in body if xx == x) > -7]
    print("BAND %s: every column covers z -7..6 (the collision band, +-6.9): %s" % (name, "yes" if not thin else "NO at x %s" % thin))
for name, v in VARIANTS.items():
    shp = vk.blob(periodic(CORE + SHARED) + v["puffs"], keep=lambda x, y, z: 0 <= x < TILE and in_band(x, y, z))
    small = vk.islands(bands(shp), 4)
    left = vk.islands(despeckle(bands(shp), lambda x: EDGE <= x < TILE - EDGE), 4)
    print("ISLANDS %s: %d band patches under 4 cubes (%d cubes), %d after despeckle"
          % (name, len(small), sum(len(g) for _, g in small), len(left)))

if "export_only" in ARGS:
    sys.exit(0)

# ---------------------------------------------------------------- review renders
class Kit:
    """Each model built once per scene; place() adds copies that share its mesh."""

    def __init__(self):
        self.done = {}

    def place(self, name, x, z=0, parent=None):
        if name not in self.done:
            if name in tiles:
                self.done[name] = build("Hedge_" + name, tiles[name], beside, (0, TILE))
            else:
                self.done[name] = build(name, caps[name], CAP_SOLID[name], (-CAP,) if name == "cap_l" else (CAP,))
            self.done[name].hide_render = True
        o = self.done[name].copy()
        bpy.context.scene.collection.objects.link(o)
        o.hide_render = False
        o.location = (x * vk.VOX, 0, z * vk.VOX)
        if parent:
            o.parent = parent
        return o


def add_bee(x, z=0.0):
    try:
        bpy.ops.import_scene.gltf(filepath=BEE)
        bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
        bee.location = (x * vk.VOX, -0.3, z * vk.VOX)
        for o in bpy.context.scene.objects:
            if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
                o.hide_render = True
    except Exception as e:
        print("no bee for scale:", e)


# a row as the game lays it: a left bar ending in cap_l, the gap, cap_r and a right bar
vk.reset()
kit = Kit()
GAP = 64                   # cubes, about 102 px: a gap near the hardest
x = 0
for v in "abcab":
    kit.place(v, x)
    x += TILE
gap_l = x + CAP
kit.place("cap_l", gap_l)
gap_r = gap_l + GAP
kit.place("cap_r", gap_r)
x = gap_r + CAP
for v in "cbac":
    kit.place(v, x)
    x += TILE
width = x
add_bee(gap_l + GAP / 2)
pv = vk.Preview(game_like=True)
mid = (gap_l + GAP / 2) * vk.VOX
pv.shoot(os.path.join(PREVIEW, "hedge_row.png"), (0.0, -1.0, 0.12), (width * vk.VOX / 2, 0, 0), width * vk.VOX + 0.4, 2400, 420)
span = (GAP + 2 * CAP + 20) * vk.VOX       # the gap, both caps and a little of each bar
pv.shoot(os.path.join(PREVIEW, "hedge_gap.png"), (0.0, -1.0, 0.12), (mid, 0, 0), span, 1600, 560)
pv.shoot(os.path.join(PREVIEW, "hedge_gap_3q.png"), (0.45, -1.0, 0.45), (mid, 0, 0), span, 1600, 800)
pv.shoot(os.path.join(PREVIEW, "hedge_gap_under.png"), (-0.3, -1.0, -0.35), (mid, 0, 0), span, 1600, 800)
pv.shoot(os.path.join(PREVIEW, "hedge_tile.png"), (0.0, -1.0, 0.12), ((TILE + 12) * vk.VOX, 0, 0), 1.7, 1100, 700)
pv.shoot(os.path.join(PREVIEW, "hedge_tile_3q.png"), (0.5, -1.0, 0.45), ((TILE + 12) * vk.VOX, 0, 0), 1.7, 1100, 800)

# the old script's three views (studio light, a bar of four tiles and the
# bee), for before/after sheets
vk.reset()
kit = Kit()
order = "abca"
for i, v in enumerate(order):
    kit.place(v, i * TILE)
add_bee(len(order) * TILE + 0.9 / vk.VOX, 0.05 / vk.VOX)
pv = vk.Preview()
w = len(order) * TILE * vk.VOX
centre = (w / 2 + 0.4, 0, 0)
pv.shoot(os.path.join(PREVIEW, "hedge_3q.png"), (0.35, -1.0, 0.55), centre, w + 1.6, 1400, 700)
pv.shoot(os.path.join(PREVIEW, "hedge_game.png"), (0.0, -1.0, 0.13), centre, w + 1.6, 1400, 700)
pv.shoot(os.path.join(PREVIEW, "hedge_close.png"), (0.5, -1.0, 0.45), (0.75, 0, 0), 1.7, 900, 700)

# every pair of tiles (rows 1-3), each tile against cap_l (row 4), cap_r against each tile (row 5)
vk.reset()
kit = Kit()
for k, (a, b) in enumerate((a, b) for a in "abc" for b in "abc"):
    ox, oz = (k % 3) * (2 * TILE + 10), -(k // 3) * 30
    kit.place(a, ox, oz)
    kit.place(b, ox + TILE, oz)
for k, v in enumerate("abc"):
    ox = k * (2 * TILE + 10)
    kit.place(v, ox, -90)
    kit.place("cap_l", ox + TILE + CAP, -90)
    kit.place("cap_r", ox, -120)
    kit.place(v, ox + CAP, -120)
pv = vk.Preview(game_like=True)
W = (3 * (2 * TILE + 10)) * vk.VOX
pv.shoot(os.path.join(PREVIEW, "hedge_seams.png"), (0.0, -1.0, 0.12), (W / 2 - 0.2, 0, -2.4), 6.2 * 4 / 3, 2000, 1500)
print("DONE voxel hedge")
