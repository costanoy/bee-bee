"""Bee Bee — the far backdrop "hills and mountains" as voxel art (Toybox honey garden).

  blender --background --factory-startup --python make_voxel_backdrop_hills.py -- <models_dir> <preview_dir>

The backdrop hangs 95 units behind the play plane, where the perspective
camera shrinks everything to under a fifth of its size: cubes of the usual
0.04 would be invisible there. So it is built from cubes five times bigger
(BIG = 0.2), which land on screen at about the same size as every other
cube in the game. Three layers, one behind the other, as the user liked
them: green hills, blue hills, snowy mountains. Each is a stepped wall a few
cubes thick with the light painted on, in the storybook manner of the new
world but as the far layer: soft, low contrast, no inks, no darks.
  * green hills: plump round mounds (ellipse tops, not a wobbly line) that
    overlap like paper cut-outs, each in its own close green with a lit lip
    where it stands in front of the next and a curved shade on its right; a
    row of low mounds in front of them (seen once the ground scrolls away
    during the climb); round tree clumps along the crests;
  * blue hills: wide, soft cut-out mounds in a misty periwinkle-blue,
    paler than the sky's band, with a few round blue tree clumps on the ridge;
  * mountains: the same three peaks (x = -14, 6, 26, the tallest 17 units
    high), with rounded summits, a shoulder on one flank, lit left faces and
    lilac shaded right faces split along a chunky ridge, and plump snow caps
    whose edge hangs down in rounded drips.
Each layer gets the kit's vertical gradient and a lit rim along its top
silhouette (the crisp highlight on top edges; the mountains' left flanks get
one too); the outlines step in 2-cube macro cubes; colour changes in patches,
never per cube, so equal faces merge (vk.build, no T-junctions: the sky
behind would show through the cracks). The foot (below z = FOOT_Z) is one
flat colour, FOOT, which is also the colour view3d.gd must give the base
slab hung under the backdrop, so the two meet without a seam when the
ground scrolls away. The game's depth fog lays a lot of the horizon colour
over the backdrop, so the colours are authored as the inverse of on-screen
targets measured through the game's look. The back, the undersides and the
side faces that look away from the camera (which never leaves x = 0) are
never seen and are left out. Exports backdrop_voxel_hills.glb and review renders.
"""
import bpy, bmesh, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.2
X0, X1 = -225, 225           # 90 units wide
FLOOR = -22                  # the walls run well below the foot, behind the horizon slab
THICK = 2                    # thin walls: the tops of the silhouette's steps catch the light from above
FOOT_Z = -6                  # below this the green hills are one flat colour, the slab's

# The game's depth fog lays a lot of the horizon colour over the backdrop
# (by day authored black shows as 0.19, 0.40, 0.62; white as 0.85, 0.88,
# 0.93), so these are authored warmer and greener than they show: each is
# the inverse of an on-screen target, measured through the game's look
# (the comment gives the target by day).
# green hills, the nearest layer: the richest colours of the backdrop
FIELDS = [(0.46, 0.66, 0.26),   # 0.46, 0.70, 0.66: one tone per hill
          (0.55, 0.73, 0.28),   # 0.54, 0.74, 0.67
          (0.41, 0.61, 0.22),   # 0.42, 0.66, 0.65
          (0.60, 0.74, 0.26)]   # 0.58, 0.74, 0.66, a yellower one
CLUMP = (0.35, 0.50, 0.06)      # 0.38, 0.61, 0.63: the tree clumps
CLUMP_LIGHT = (0.47, 0.64, 0.16)
GREEN_LIP = (0.70, 0.89, 0.42)  # 0.66, 0.83, 0.70
FOOT = (0.40, 0.60, 0.14)       # = the base slab's colour in view3d.gd (hills)
# blue hills: a misty periwinkle-blue, paler than the green and the sky
BLUE = (0.65, 0.73, 0.93)       # 0.62, 0.74, 0.90
BLUE_ALT = (0.61, 0.68, 0.90)   # 0.59, 0.71, 0.89
BLUE_CLUMP = (0.56, 0.62, 0.86)
BLUE_LIP = (0.80, 0.86, 1.00)
# mountains: lilac rock, lit left and shaded right; warm-white snow
ROCK_LIT = (0.81, 0.68, 0.93)       # 0.74, 0.71, 0.90
ROCK_LIT_ALT = (0.76, 0.64, 0.91)
ROCK_SHADE = (0.60, 0.47, 0.77)     # 0.59, 0.58, 0.84
ROCK_SHADE_ALT = (0.56, 0.44, 0.74)
SNOW = (1.00, 1.00, 1.00)           # 0.85, 0.88, 0.93
SNOW_SHADE = (0.91, 0.83, 0.96)     # 0.80, 0.80, 0.91

GREEN_Y, BLUE_Y, ROCK_Y = 0, 15, 30
HIDDEN_Z = 20                # the mountains are never seen below the blue hills' lowest point
PEAKS = [(-70, 60, 46), (30, 85, 56), (130, 55, 41)]      # centre x, height, half-width (in big cubes)
SHOULDERS = [(-48, 34, 22), (2, 50, 26), (150, 30, 18)]   # a lower bump on one flank of each


def mounds(seed, step, width, height, base, foot=0, front=0.0):
    """A row of round mounds across the backdrop: [(centre, half-width, top,
    rank, foot)], each an ellipse arc from z = foot up to its top; where two
    overlap, the one of higher rank is in front (front: added to the rank)."""
    rng = random.Random(seed)
    out = []
    x = X0 - 30
    while x < X1 + 30:
        out.append((x, rng.uniform(*width), base + rng.uniform(*height), rng.random() + front, foot))
        x += rng.uniform(*step)
    return out


# the green hills: a row of tall mounds, and a row of low ones in front of
# them (always in front: rank + 1), which only shows once the near grass
# scrolls away during the climb
GREEN_MOUNDS = mounds(5, (34, 56), (30, 46), (12, 24), 6) + mounds(29, (40, 62), (44, 62), (4, 10), 0, FLOOR, 1.0)
BLUE_MOUNDS = mounds(11, (48, 74), (44, 66), (8, 20), 14)


def mound_heights(ms, x, power=0.5):
    """[(rank, index, height)] of the mounds over x, front-most first (an
    ellipse arc per mound; x in 2-cube macro steps, so outlines are chunky)."""
    x -= x % 2
    out = []
    for i, (cx, w, top, rank, foot) in enumerate(ms):
        t = (x + 1.0 - cx) / w
        if abs(t) < 1.0:
            out.append((rank, i, round(foot + (top - foot) * (1.0 - t * t) ** power)))
    return sorted(out, reverse=True)


def mound_top(ms, x, power=0.5):
    """Height of the union of the mounds at x."""
    return max([h for _, _, h in mound_heights(ms, x, power)] or [-99])


def mound_owner(ms, x, z, power=0.5):
    """The mound a cell belongs to: the front-most one that reaches up to it."""
    for _, i, h in mound_heights(ms, x, power):
        if z <= h:
            return i
    return None


def green_top(x):
    return max(14, round(mound_top(GREEN_MOUNDS, x)))


def blue_top(x):
    return max(20, round(mound_top(BLUE_MOUNDS, x, 0.6)))


def peak_at(x):
    """(height, index of the mountain whose flank it is) of the mountain line
    at x: straight-ish flanks with a softly rounded summit."""
    x -= x % 2
    best, who = -99.0, 0
    for i, ((cx, ph, w), (sx, sh, sw)) in enumerate(zip(PEAKS, SHOULDERS)):
        t = abs(x + 0.5 - cx) / w
        e = 0.05                                       # the summit's roundness
        z = ph * (1.0 - (math.sqrt(t * t + e * e) - e) ** 1.2)
        s = abs(x + 0.5 - sx) / sw
        z = max(z, sh * (1.0 - (math.sqrt(s * s + e * e) - e) ** 1.1))
        if z > best:
            best, who = z, i
    return round(best), who


def wall(top, y0, paint):
    """A wall THICK cubes deep from FLOOR to top(x): {cell: colour} for the
    front and the top row (the top shows from above), plus the solid inside."""
    vox, solid = {}, set()
    for x in range(X0, X1):
        t = top(x)
        for z in range(FLOOR, t + 1):
            vox[(x, y0, z)] = paint(x, z, t)
            for y in range(y0 + 1, y0 + THICK):
                if z == t:
                    vox[(x, y, z)] = vox[(x, y0, z)]
                else:
                    solid.add((x, y, z))
    return vox, solid


def round_clump(vox, cx, cz, r, y0, dark, light, lip=None):
    """A round tree clump standing on a wall (its face only, flat in depth):
    lit on the upper left, one cube of lip on top."""
    for x in range(math.floor(cx - r), math.ceil(cx + r) + 1):
        for z in range(math.floor(cz - r), math.ceil(cz + r) + 1):
            u, v = (x + 0.5 - cx) / r, (z + 0.5 - cz) / (r * 0.9)
            if u * u + v * v > 1.0:
                continue
            c = light if (-u * 0.6 + v * 0.8) > 0.35 else dark
            for y in range(y0, y0 + THICK):
                vox[(x, y, z)] = c
    if lip:
        for x in range(math.floor(cx - r), math.ceil(cx + r) + 1):
            col = [z for (xx, y, z) in vox if xx == x and y == y0 and abs(z - cz) <= r + 1]
            if col and abs(x + 0.5 - cx) < r * 0.6:
                vox[(x, y0, max(col))] = lip


# ---------------------------------------------------------------- the three layers
def mound_paint(ms, power, tones, floor_z, lift=0.14):
    """Paint for a wall of overlapping mounds, like paper cut-outs: each
    mound in its own tone (neighbours differ), its right flank a little in
    shade, and a lit lip along its top wherever it stands in front of
    another mound (the top silhouette gets its rim later)."""
    def paint(x, z, t):
        i = mound_owner(ms, x, z, power)
        if i is None or z < floor_z:
            i = mound_owner(ms, x, floor_z, power) or 0
        cx, w, top = ms[i][:3]
        c = tones[i % len(tones)]
        # the shade side: lit from the upper left like a ball, so the
        # light/shade edge curves round the mound instead of running straight down
        if (x + 1.0 - cx) / w * 0.8 - (z - floor_z) / max(1.0, top - floor_z) * 0.6 > 0.15:
            c = vk.shade(c, -0.06)
        above = mound_owner(ms, x, z + 1, power)
        if above is not None and above != i:
            c = vk.shade(c, lift)
        return c
    return paint


def green_layer():
    hill = mound_paint(GREEN_MOUNDS, 0.5, FIELDS, FOOT_Z)
    paint = lambda x, z, t: FOOT if z < FOOT_Z else hill(x, z, t)

    vox, solid = wall(green_top, GREEN_Y, paint)
    vox = vk.gradient(vox, top=0.05, bottom=-0.12, z0=FOOT_Z, z1=30, steps=5, only=lambda p, c: p[2] >= FOOT_Z)
    vox = vk.rim(vox, "top", colour=GREEN_LIP, amount=0.8)
    # round tree clumps along the crests, alone or in pairs
    rng = random.Random(23)
    x = X0 + rng.randint(4, 20)
    while x < X1 - 4:
        r = rng.choice((3.0, 3.5, 4.0))
        round_clump(vox, x + 0.5, green_top(x) + r * 0.55, r, GREEN_Y, CLUMP, CLUMP_LIGHT)
        if rng.random() < 0.45:
            x2 = int(x + r * 1.7)
            round_clump(vox, x2 + 0.5, green_top(x2) + r * 0.4, r - 0.5, GREEN_Y, CLUMP, CLUMP_LIGHT)
        x += rng.randint(18, 46)
    for p in [p for p in vox if p[2] < FOOT_Z]:
        vox[p] = FOOT
    return vox, solid


def blue_layer():
    vox, solid = wall(blue_top, BLUE_Y, mound_paint(BLUE_MOUNDS, 0.6, (BLUE, BLUE_ALT), HIDDEN_Z, 0.10))
    vox = vk.gradient(vox, top=0.05, bottom=-0.10, z0=20, z1=36, steps=4)
    vox = vk.rim(vox, "top", colour=BLUE_LIP, amount=0.8)
    rng = random.Random(31)
    x = X0 + 12
    while x < X1 - 4:
        t = blue_top(x)
        round_clump(vox, x + 0.5, t + 1.2, rng.choice((2.5, 3.0)), BLUE_Y, BLUE_CLUMP, BLUE, BLUE_LIP)
        x += rng.randint(14, 38)
    return vox, solid


def rock_layer():
    def paint(x, z, t):
        _, i = peak_at(x)
        if z < HIDDEN_Z:
            return ROCK_SHADE                    # behind the hills: one flat colour, which merges
        cx, ph, w = PEAKS[i]
        sx, sh, sw = SHOULDERS[i]
        on_shoulder = t < ph * (1.0 - (abs(x + 0.5 - cx) / w)) - 3 and abs(x - sx) < sw
        rx = sx if on_shoulder else cx
        rh = sh if on_shoulder else ph
        # the ridge runs down from the summit, leaning right, in 2-cube steps
        ridge = rx + (rh - z) * 0.16 + 2 * round(1.2 * math.sin((z // 2) * 0.55 + i))
        lit = x < ridge
        # snow cap: its edge hangs down in plump, rounded drips
        drip = 3.5 * max(0.0, math.cos((x + i * 5) * 2 * math.pi / 11)) ** 2
        snow_line = rh * (0.72 if not on_shoulder else 0.80) - drip + 1.5 * math.sin(x * 0.13 + i)
        if z > snow_line:
            return SNOW if lit else SNOW_SHADE
        strata = vk.hash01((x + 4 * (z // 8)) // 12, z // 8, i, 7) < 0.2
        if lit:
            return ROCK_LIT_ALT if strata else ROCK_LIT
        return ROCK_SHADE_ALT if strata else ROCK_SHADE

    vox, solid = wall(lambda x: peak_at(x)[0], ROCK_Y, paint)
    rock = lambda p, c: c not in (SNOW, SNOW_SHADE)
    vox = vk.gradient(vox, top=0.06, bottom=-0.08, z0=15, z1=70, steps=6, only=rock)
    vox = vk.rim(vox, "top", k=0.12, only=rock)
    vox = vk.rim(vox, "left", k=0.10, only=rock)           # the sunlit edge of every left flank
    return vox, solid


cells, solid = {}, set()
for v, s in (rock_layer(), blue_layer(), green_layer()):
    cells.update(v)
    solid |= s
solid -= set(cells)



def drop_back_sides(o):
    """The game camera never leaves x = 0, so the side faces that look away
    from it (+X on the right half, -X on the left) are back faces it never
    draws: leave them out."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    gone = [f for f in bm.faces if abs(f.normal.x) > 0.5 and f.normal.x * f.calc_center_median().x > 0]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    bm.to_mesh(o.data)
    bm.free()


vk.reset()
root = vk.empty("Hills")
o = vk.build("Hills", cells, vk.material("Voxel", rough=0.9), root, size=BIG, solid=solid, skip=vk.NO_BACK_UNDER)
drop_back_sides(o)
vk.report("backdrop hills", root, budget=10000)
vk.export(os.path.join(MODELS, "backdrop_voxel_hills.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "hills_front.png"), (0.0, -1.0, 0.1), (5, 0, 6.5), 62.0, 1700, 620)
pv.shoot(os.path.join(PREVIEW, "hills_3q.png"), (0.45, -1.0, 0.45), (5, 0, 6), 62.0, 1700, 760)
pv.shoot(os.path.join(PREVIEW, "hills_close.png"), (0.25, -1.0, 0.3), (6, 0, 11), 22.0, 1100, 760)
print("DONE voxel backdrop hills")
