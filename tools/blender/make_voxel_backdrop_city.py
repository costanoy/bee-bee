"""Bee Bee — the far backdrop "city" as voxel art (Toybox honey garden).

  blender --background --factory-startup --python make_voxel_backdrop_city.py -- <models_dir> <preview_dir>

The storybook town the user liked (remade 01-02/10), restyled for the new
world: the same street, house by house — gabled houses with tiled roofs and
chimneys, apartment blocks with rooftop tanks, stepped-gable houses, shops
with striped awnings, a clock tower and a domed hall, with trees along the
street — in a sunny storybook palette (cream, peach, coral, butter, sage,
pink walls; terracotta, slate-blue, teal and plum roofs) and painted the
way the rest of the world is: a lit left edge, a cool lavender shade down
the right of every front and under the eaves, bright top faces (the camera
looks down on the backdrop from about 30 degrees, so they draw a crisp lit
line along every roof, ledge and canopy), coloured doors with round tops
at street level and a plinth below, shutters and flower boxes, honey-warm
glowing windows, round tree canopies lit from the upper left. Far layer
rules: soft, no inks, nothing dark (doors and trunks stay mid-tones).

Three layers so it reads as a place with depth: green hills at the back
(overlapping round mounds, as on the hills backdrop), a hazy lavender-blue
skyline in front of them with rounded tops, and the town itself up front.
In front of the town's feet runs a green bank with round bushes, which the
near grass hides on the title screen and which meets the base slab (the
colour FOOT) when the ground scrolls away during the climb.

Built like the hills backdrop: from cubes five times the usual size
(BIG = 0.2), because 95 units back the camera shrinks them to the size of
every other cube on screen, and as thin walls with the shading painted on.
Three meshes, by the names view3d.gd looks for: "City" (the street and its
trees: drawn without the depth fog, with a light tint of the sky instead,
because fog turned the warm walls lilac), "Far" (the skyline, the hills and
the green bank: they keep the fog, which is what makes them recede, and the
bank then matches the fogged slab) and "Windows", with a glowing material so
they stay lit when the scene goes dark. Same footprint as before (90 units
wide, foot at z = 0, the street STREET cubes up, under the near grass).
Colour changes in patches, never per cube, and equal faces merge (vk.build,
no T-junctions); lit windows the town hides on the skyline and the side
faces that look away from the camera (which never leaves x = 0) are left
out, which keeps the whole town within 10,000 triangles.
Exports backdrop_voxel_city.glb and review renders.
"""
import bpy, bmesh, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.2
X0, X1 = -225, 225
FLOOR = -22
THICK = 2
HILLS_Y = 30
FAR_Y = 14              # the hazy skyline
TREE_Y = -3             # street trees, in front of the houses
BANK_Y = -6             # the green bank in front of everything
# In the game the grass in front hides everything below about this height,
# so the street (doors, shop fronts, tree trunks) is drawn from here up.
STREET = 13
BANK_TOP = 10           # the bank stays under the grass on the title screen
CUT_Z = 1               # the town is never seen below this, behind the bank

# The town ("City" mesh: no fog, a 16% tint of the sky's colour). Warm on
# purpose: blues and lilacs belong to the skyline behind, and a house in
# those colours sank into it. Same number of colours as before, so the town
# keeps its exact layout (the picks are seeded).
WALLS = [(1.00, 0.90, 0.68), (1.00, 0.72, 0.52), (0.97, 0.56, 0.52), (1.00, 0.82, 0.42), (0.62, 0.84, 0.58),
         (1.00, 0.64, 0.76), (0.99, 0.96, 0.88), (0.95, 0.66, 0.44)]
ROOFS = [(0.88, 0.44, 0.35), (0.46, 0.54, 0.80), (0.30, 0.64, 0.63), (0.64, 0.44, 0.66), (0.74, 0.47, 0.37)]
STONE = (0.96, 0.93, 0.86)
TRIM = (1.00, 0.98, 0.94)
BRICK = (0.82, 0.56, 0.48)
WINDOW = (1.00, 0.84, 0.52)     # warm honey glass (the Windows mesh glows)
GOLD = (1.00, 0.82, 0.38)
COPPER = (0.46, 0.76, 0.68)     # the dome, mint
AWNING = [((0.94, 0.46, 0.44), TRIM), ((0.42, 0.68, 0.76), TRIM), ((0.52, 0.74, 0.50), TRIM)]
BLOOMS = [(0.96, 0.46, 0.54), (1.0, 0.82, 0.40), (0.98, 0.68, 0.84)]
LEAF = (0.42, 0.70, 0.38)
LEAF_LIGHT = (0.60, 0.84, 0.44)
TRUNK = (0.66, 0.50, 0.40)
# The skyline, hills and bank ("Far" mesh) get the depth fog, which lays a
# lot of the horizon colour over them (by day authored black shows as 0.19,
# 0.40, 0.62), so they are authored warmer than they show; the comments give
# the on-screen colour by day, measured through the game's look.
FAR = [(0.67, 0.70, 0.99), (0.72, 0.76, 1.00), (0.62, 0.63, 0.93)]   # 0.64, 0.72, 0.92 / 0.68, 0.76, 0.93 / 0.60, 0.68, 0.90
HILL = [(0.47, 0.67, 0.26), (0.55, 0.73, 0.28), (0.42, 0.62, 0.22)]  # 0.47, 0.71, 0.66 ...
BUSH_LIGHT = (0.50, 0.68, 0.20)   # the bushes' lit tops
FOOT = (0.40, 0.60, 0.14)       # = the base slab's colour in view3d.gd (city)


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


shade = vk.shade            # hue-shifted: warm lights, cool lavender shadows


def hill_mounds():
    rng = random.Random(17)
    out, x = [], X0 - 30
    while x < X1 + 30:
        out.append((x, rng.uniform(30, 48), rng.uniform(16, 26), rng.random()))
        x += rng.uniform(32, 54)
    return out


MOUNDS = hill_mounds()


def mound_heights(x):
    """[(rank, index, height)] of the back hills over x, front-most first."""
    x -= x % 2
    out = []
    for i, (cx, w, top, rank) in enumerate(MOUNDS):
        t = (x + 1.0 - cx) / w
        if abs(t) < 1.0:
            out.append((rank, i, round(top * math.sqrt(1.0 - t * t))))
    return sorted(out, reverse=True)


def city():
    walls, solid, windows, far = {}, set(), {}, {}

    def put(x, z, c, y=0):
        """One cube of wall, THICK cubes deep; only the front shows."""
        if z < FLOOR or not X0 - 12 <= x < X1 + 12:
            return
        z += STREET
        if y < FAR_Y and z < CUT_Z:
            return
        cell = (x, y, z)
        if y >= FAR_Y:
            far[cell] = c
        else:
            walls[cell] = c
        windows.pop(cell, None)
        for k in range(1, THICK):
            solid.add((x, y + k, z))

    def glass(x, z, y=0):
        cell = (x, y, z + STREET)
        for d in (walls, far):
            if cell in d:
                del d[cell]
                solid.add(cell)
                windows[cell] = WINDOW

    def rect(x, z, w, ht, c, y=0):
        for dx in range(w):
            for dz in range(ht):
                put(x + dx, z + dz, c, y)

    def body(x, w, ht, base):
        """A house front: lit left edge, a cool shade down the right, and a
        plinth below the street (z < 0), which shows during the climb."""
        for dx in range(w):
            c = shade(base, 0.10) if dx == 0 else (shade(base, -0.14) if dx >= w - 2 else base)
            for z in range(FLOOR, ht):
                put(x + dx, z, c if z >= 0 else shade(base, -0.18))

    def window(x, z, w, ht, base, arched=False, box=None, shutters=None):
        """Glass with a pale sill that sticks out a cube and a soft shadow
        above; `box` plants a flower box on the sill, `shutters` hangs a
        coloured shutter on each side."""
        for dx in range(w):
            for dz in range(ht):
                if arched and dz == ht - 1 and dx in (0, w - 1):
                    continue
                glass(x + dx, z + dz)
        for dx in range(-1, w + 1):
            if box is None:
                put(x + dx, z - 1, TRIM, -1)
            else:
                put(x + dx, z - 1, LEAF if dx in (-1, w) else box, -1)
        if not arched:
            for dx in range(w):
                put(x + dx, z + ht, shade(base, -0.14))
        if shutters:
            for dz in range(ht):
                put(x - 1, z + dz, shutters)
                put(x + w, z + dz, shade(shutters, -0.08))

    def window_grid(x, w, z0, z1, base, ww=3, wh=4, gap_x=3, gap_z=5, boxes=None, arched=False, shutters=None):
        cols = max(1, (w - 4 + gap_x) // (ww + gap_x))
        left = x + (w - (cols * (ww + gap_x) - gap_x)) // 2
        z = z0
        row = 0
        while z + wh < z1:
            for c in range(cols):
                box = None
                if boxes is not None and h(x, c, row, 7) < 0.4:
                    box = boxes[int(h(x, c, row, 9) * len(boxes))]
                window(left + c * (ww + gap_x), z, ww, wh, base, arched, box, shutters)
            z += wh + gap_z
            row += 1

    def door(x, w, base, colour):
        """A coloured door with a round top and a lintel of shade above."""
        left = x + (w - 3) // 2
        rect(left, 0, 3, 5, colour)
        put(left, 4, base)
        put(left + 2, 4, base)
        put(left + 1, 4, shade(colour, -0.08))
        for dx in range(-1, 4):
            put(left + dx, 5, shade(base, -0.14))

    def eaves(x, w, ht, base):
        for dx in range(w):
            put(x + dx, ht - 1, shade(base, -0.20))

    # ------------------------------------------------------------ the buildings
    def townhouse(x, w, ht, base, roof, rng):
        body(x, w, ht, base)
        eaves(x, w, ht, base)
        door(x, w, base, shade(roof, -0.10))
        # shutters on every other house, in the roof's colour
        shut = shade(roof, 0.05) if h(x, 3) < 0.5 and w >= 17 else None
        window_grid(x, w, 9, ht - 2, base, boxes=BLOOMS, gap_x=4 if shut else 3, shutters=shut)
        # tiled gable, one cube of overhang each side, tile rows in two tones
        span = w + 2
        rise = (span + 1) // 2
        for k in range(rise):
            for dx in range(k, span - k):
                c = roof if k % 2 == 0 else shade(roof, -0.07)
                if dx >= span / 2:
                    c = shade(c, -0.12)
                put(x - 1 + dx, ht + k, c)
        for dx in range(span):
            put(x - 1 + dx, ht, shade(roof, 0.14), -1)               # the eave's lip
        if w >= 15:                                                   # attic window
            glass(x + w // 2 - 1, ht + 3)
            glass(x + w // 2, ht + 3)
            glass(x + w // 2 - 1, ht + 4)
            glass(x + w // 2, ht + 4)
        cx = x + (2 if rng.random() < 0.5 else w - 5)                 # chimney
        base_z = ht + min(cx - x + 1, x + w - cx - 2)
        rect(cx, base_z, 3, rise - (base_z - ht) + 3, BRICK)
        rect(cx - 1, ht + rise + 2, 5, 1, shade(BRICK, 0.10))

    def apartments(x, w, ht, base, roof, rng):
        body(x, w, ht, base)
        door(x, w, base, shade(roof, -0.10))
        window_grid(x, w, 9, ht - 3, base, gap_z=4)
        rect(x - 1, ht, w + 2, 2, shade(base, 0.08))                  # parapet
        rect(x - 1, ht + 1, w + 2, 1, TRIM, -1)
        kind = rng.randint(0, 2)
        if kind == 0:                                                 # water tank on legs
            tx = x + 2
            put(tx, ht + 2, shade(roof, -0.15))
            put(tx + 4, ht + 2, shade(roof, -0.15))
            rect(tx - 1, ht + 3, 7, 4, roof)
            rect(tx, ht + 7, 5, 1, shade(roof, -0.16))                # a rounded lid
            rect(tx + 4, ht + 3, 2, 4, shade(roof, -0.12))
            rect(tx - 1, ht + 6, 2, 1, shade(roof, 0.12))
        elif kind == 1:                                               # stair hut and aerial
            rect(x + w - 8, ht + 2, 6, 5, shade(base, -0.06))
            rect(x + w - 9, ht + 7, 8, 1, roof)
            for dz in range(9):
                put(x + 3, ht + 2 + dz, shade(roof, -0.15))
            rect(x + 2, ht + 8, 3, 1, shade(roof, -0.15))
        else:                                                         # a little roof garden
            for dx in range(2, w - 2):
                if h(x, dx, 3) < 0.6:
                    put(x + dx, ht + 2, (LEAF, LEAF_LIGHT, LEAF)[int(h(x, dx, 4) * 3)])
                    if h(x, dx, 5) < 0.35:
                        put(x + dx, ht + 3, BLOOMS[int(h(x, dx, 6) * 3)])

    def stepped(x, w, ht, base, roof, rng):
        """A narrow house with a stepped gable."""
        body(x, w, ht, base)
        door(x, w, base, shade(roof, -0.10))
        window_grid(x, w, 9, ht - 1, base, ww=2, wh=5, gap_x=3, gap_z=4, boxes=BLOOMS)
        k = 0
        z = ht
        while w - 4 * k > 1:
            ww = w - 4 * k
            rect(x + 2 * k, z, ww, 3, base)
            rect(x + 2 * k, z + 2, ww, 1, TRIM)
            put(x + 2 * k, z, shade(base, 0.06))
            put(x + 2 * k, z + 1, shade(base, 0.06))
            for dz in range(2):
                put(x + 2 * k + ww - 1, z + dz, shade(base, -0.10))
            z += 3
            k += 1
        glass(x + w // 2, ht + 2)
        glass(x + w // 2, ht + 3)

    def shop(x, w, ht, base, roof, rng):
        body(x, w, ht, base)
        stripe = AWNING[rng.randrange(len(AWNING))]
        for dx in range(3, w - 3):                                    # the shop window
            for z in range(1, 8):
                if (dx - 3) % 6 != 5:
                    glass(x + dx, z)
        for dx in range(1, w - 1):                                    # awning, scalloped along the bottom
            c = stripe[(dx // 2) % 2]
            put(x + dx, 10, shade(c, -0.08), -1)
            put(x + dx, 9, c, -2)
            if dx % 4 < 2:
                put(x + dx, 8, c, -2)
        rect(x + 2, 12, w - 4, 4, shade(roof, -0.04))                 # the sign
        for dx in range(4, w - 4):
            if h(x, dx, 11) < 0.55:
                put(x + dx, 13 + int(h(x, dx, 12) * 2), TRIM)
        rect(x - 1, ht, w + 2, 1, TRIM, -1)                           # cornice
        rect(x - 1, ht, w + 2, 1, TRIM)
        rect(x + 3, ht + 1, w - 6, 2, shade(base, -0.06))
        rect(x + 3, ht + 3, w - 6, 1, roof)

    def clock_tower(x, w, ht, base, roof, rng):
        body(x, w, ht, STONE)
        door(x, w, STONE, shade(roof, -0.10))
        window_grid(x, w, 10, ht - 16, STONE, ww=3, wh=6, gap_z=6, arched=True)
        rect(x - 1, ht - 13, w + 2, 1, TRIM, -1)                      # ledge under the clock
        cx, cz = x + w // 2, ht - 7
        for dx in range(-3, 4):                                       # the clock
            for dz in range(-3, 4):
                d = dx * dx + dz * dz
                if d <= 6:
                    put(cx + dx, cz + dz, TRIM)
                elif d <= 11:
                    put(cx + dx, cz + dz, roof)
        hand = shade(roof, -0.16)
        put(cx, cz, hand)
        put(cx, cz + 1, hand)
        put(cx, cz + 2, hand)
        put(cx + 1, cz, hand)
        rect(x - 1, ht, w + 2, 1, TRIM, -1)
        rect(x - 1, ht, w + 2, 1, TRIM)
        k = 0                                                         # steep spire: one cube in for two up
        while w + 2 - 2 * k > 0:
            ww = w + 2 - 2 * k
            for dz in range(2):
                for dx in range(ww):
                    c = roof if dx < ww / 2 else shade(roof, -0.14)
                    if dx == 0:
                        c = shade(roof, 0.10)
                    put(x - 1 + k + dx, ht + 1 + 2 * k + dz, c)
            k += 1
        top = ht + 1 + 2 * k
        put(cx, top, shade(roof, -0.15))
        put(cx, top + 1, GOLD)
        put(cx, top + 2, GOLD)

    def hall(x, w, ht, base, roof, rng):
        """A domed hall with columns."""
        body(x, w, ht, STONE)
        for dx in range(2, w - 2, 5):                                 # columns
            rect(x + dx, FLOOR, 2, ht - 3 - FLOOR, TRIM, -1)
        for dx in range(4, w - 4, 5):                                 # tall windows between them
            if dx + 2 < w - 2:
                window(x + dx + 1, 6, 2, 7, STONE, arched=True)
        rect(x - 1, ht - 3, w + 2, 3, shade(STONE, -0.05))
        rect(x - 1, ht - 1, w + 2, 1, TRIM, -1)
        rect(x + 2, ht, w - 4, 2, STONE)                              # drum
        cx = x + w / 2
        r = (w - 6) / 2
        for dz in range(int(r) + 1):                                  # dome, lit on the upper left
            half = math.sqrt(max(0.0, r * r - dz * dz))
            for xi in range(int(math.floor(cx - half)), int(math.ceil(cx + half))):
                t = (xi + 0.5 - cx) / r
                lt = -t * 0.8 + dz / r * 0.6
                c = shade(COPPER, 0.16) if lt > 0.45 else (shade(COPPER, -0.14) if lt < -0.25 else COPPER)
                put(xi, ht + 2 + dz, c)
        top = ht + 3 + int(r)
        mid = int(cx) - 1
        rect(mid, top, 3, 3, STONE)
        glass(mid + 1, top + 1)
        rect(mid - 1, top + 3, 5, 1, COPPER)
        put(mid + 1, top + 4, COPPER)
        put(mid + 1, top + 5, GOLD)

    def tree(x, r, z):
        """A street tree: a round, chunky canopy lit from the upper left on
        a two-tone trunk."""
        for dz in range(FLOOR, z):
            put(x, dz, TRUNK, TREE_Y)
            put(x + 1, dz, shade(TRUNK, -0.12), TREE_Y)
        # a round canopy a little taller than wide, with a light crescent
        # on the upper left
        cx, cz = x + 1.0, z + r + 0.5
        for X in range(x - r - 1, x + r + 3):
            for Z in range(z - 1, z + 2 * r + 3):
                u, v = (X + 0.5 - cx) / (r + 0.7), (Z + 0.5 - cz) / (r + 0.7) / 1.12
                if u * u + v * v <= 1.0:
                    put(X, Z, LEAF_LIGHT if -u * 0.55 + v * 0.8 > 0.40 else LEAF, TREE_Y)

    # ------------------------------------------------------------ hills at the back
    for x in range(X0, X1):
        ms = mound_heights(x)
        t = max([m[2] for m in ms] or [16])
        for z in range(FLOOR, t + 1):
            i = next((j for _, j, hh in ms if z <= hh), ms[0][1] if ms else 0)
            c = HILL[i % 3] if z > 12 else HILL[0]                    # (lower down the town hides them)
            far[(x, HILLS_Y, z)] = c
            for y in range(HILLS_Y + 1, HILLS_Y + THICK):
                if z == t:
                    far[(x, y, z)] = c
                else:
                    solid.add((x, y, z))

    # ------------------------------------------------------------ hazy skyline
    rng = random.Random(41)
    x = X0 + 4
    i = 0
    while x < X1 - 10:
        w, ht = rng.randint(12, 22), rng.randint(24, 50)
        c = FAR[i % 3]
        for dx in range(w):
            for z in range(FLOOR, ht):
                put(x + dx, z, shade(c, -0.06) if dx == w - 1 else c, FAR_Y)
        top = rng.randint(0, 3)
        if top == 0 and w >= 14:                                      # a set-back upper storey
            rect(x + 3, ht, w - 6, 6, c, FAR_Y)
        elif top == 1:                                                # mast
            rect(x + w // 2, ht, 1, 9, shade(c, -0.06), FAR_Y)
        elif top == 2:                                                # pointed top
            for k in range(w // 2):
                rect(x + k, ht + k, w - 2 * k, 1, shade(c, -0.03), FAR_Y)
        else:                                                         # a rounded top
            r = (w - 2) / 2
            for dz in range(int(r * 0.7) + 1):
                half = r * math.sqrt(max(0.0, 1.0 - (dz / (r * 0.7 + 0.5)) ** 2))
                for xi in range(int(round(x + w / 2 - half)), int(round(x + w / 2 + half))):
                    put(xi, ht + dz, c, FAR_Y)
        for wx in range(x + 2, x + w - 3, 4):                         # a scatter of lit windows
            for wz in range(12, ht - 4, 6):
                r = h(wx, wz, 21)
                if r < 0.12:
                    glass(wx, wz, FAR_Y)
                    glass(wx + 1, wz, FAR_Y)
        x += w + (rng.randint(8, 26) if rng.random() < 0.3 else rng.randint(0, 2))
        i += 1

    # ------------------------------------------------------------ the town
    KINDS = {
        "townhouse": (townhouse, (15, 21), (20, 32)),
        "apartments": (apartments, (15, 19), (30, 44)),
        "stepped": (stepped, (11, 13), (28, 38)),
        "shop": (shop, (19, 23), (16, 19)),
        "clock": (clock_tower, (11, 13), (44, 52)),
        "hall": (hall, (27, 31), (20, 24)),
    }
    rng = random.Random(7)
    x = X0 + 6
    last_kind = last_wall = last_roof = None
    since_landmark = 2
    gaps = []
    while x < X1 - 14:
        pool = ["townhouse", "townhouse", "apartments", "stepped", "shop"]
        if since_landmark >= 5:
            pool += ["clock", "hall", "clock", "hall"]
        kind = rng.choice([k for k in pool if k != last_kind])
        build, (w0, w1), (h0, h1) = KINDS[kind]
        w, ht = rng.randint(w0, w1), rng.randint(h0, h1)
        wall = rng.choice([c for c in WALLS if c != last_wall])
        roof = rng.choice([c for c in ROOFS if c != last_roof])
        build(x, w, ht, wall, roof, rng)
        since_landmark = 0 if kind in ("clock", "hall") else since_landmark + 1
        last_kind, last_wall, last_roof = kind, wall, roof
        x += w
        gap = rng.choice([1, 1, 1, 2, 9, 11])                         # alleys, and now and then a small square
        if gap > 2:
            gaps.append(x + gap // 2 - 1)
        x += gap

    for gx in gaps:                                                   # a tree in every square
        tree(gx, 5, 11)
    rng = random.Random(3)
    x = X0 + 20
    while x < X1 - 10:                                                # and smaller ones along the street
        if all(abs(x - gx) > 14 for gx in gaps):
            tree(x, rng.randint(3, 4), rng.randint(5, 7))
        x += rng.randint(34, 58)

    # ------------------------------------------------------------ the green bank
    # In front of the town's feet, in the fogged mesh like the slab below it:
    # a flat FOOT-coloured bank topped by round bushes in twos and threes,
    # all under the near grass on the title screen.
    bank = {}
    for x in range(X0, X1):
        for z in range(FLOOR, BANK_TOP - 5):
            bank[(x, BANK_Y, z)] = FOOT
    bx = X0
    while bx < X1:
        r = 5.5 + 2.0 * h(bx, 31)
        if h(bx, 33) < 0.6:
            cz = BANK_TOP - 4
            for x in range(math.floor(bx - r) - 1, math.ceil(bx + r) + 2):
                for z in range(math.floor(cz - r) - 1, math.ceil(cz + r * 0.8) + 2):
                    u = (x - x % 2 + 1.0 - bx) / r                      # 2x2 macro cubes
                    v = (z - z % 2 + 1.0 - cz) / (r * 0.8)
                    if u * u + v * v <= 1.0 and X0 <= x < X1:
                        bank[(x, BANK_Y, z)] = FOOT
        bx += round(r * 1.6) + (4 if h(bx, 35) < 0.2 else 0)
    bank = vk.rim(bank, "top", colour=BUSH_LIGHT)
    for p in bank:
        far[p] = bank[p]
        solid.add((p[0], p[1] + 1, p[2]))
    return walls, solid, windows, far


walls, solid, windows, far = city()


def hidden(far, cover, dy):
    """The far cells (dy cubes behind `cover`, the projected cells in front)
    that the camera can never see: from above and in front, between the
    title and the top of the climb, a cell shows through at most 0.47-0.70
    dy cubes lower and 0.21 dy cubes to either side."""
    zs = range(int(0.47 * dy), int(0.70 * dy) + 2)
    xs = range(-int(0.21 * dy) - 1, int(0.21 * dy) + 2)
    return {p for p in far if all((p[0] + dx, p[2] + dz) in cover for dx in xs for dz in zs)}


# Whatever the town hides of the skyline loses its lit windows: they would
# only cost triangles nobody sees.
town = {(x, z) for (x, y, z) in walls if y <= 0}
for p in hidden({p: 0 for p in windows if p[1] == FAR_Y}, town, FAR_Y):
    del windows[p]
    far[p] = FAR[0]
# The painted light is per building (lit left edge, cool shade down the
# right, shade under the eaves) and the top faces draw the lit top edges
# (FACES, below). No rim pass and no vertical gradient on the town: at this
# distance a 6% gradient doesn't show, and both cost triangles the budget
# needs for the windows, sills and trees.
solid -= set(walls) | set(far) | set(windows)



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
root = vk.empty("City")
filled = lambda x, y, z: (x, y, z) in solid or (x, y, z) in walls or (x, y, z) in far or (x, y, z) in windows
# The camera looks down on the backdrop from about 30 degrees above, so the
# top faces show as a line along every roof, ledge and canopy: painted
# brighter than the kit's default, they are the crisp lit top edges.
FACES = {**vk.FACE_LIGHT, (0, 0, 1): 0.22}
o = vk.build("City", walls, vk.material("Voxel", rough=0.8), root, size=BIG, solid=filled, skip=vk.NO_BACK_UNDER, faces=FACES)
fo = vk.build("Far", far, vk.material("VoxelFar", rough=0.8), root, size=BIG, solid=filled, skip=vk.NO_BACK_UNDER, faces=FACES)
glow = vk.material("VoxelWindow", rough=0.4)
p = glow.node_tree.nodes["Principled BSDF"]
p.inputs["Emission Color"].default_value = (*vk.lin(WINDOW), 1)
p.inputs["Emission Strength"].default_value = 0.6
wn = vk.build("Windows", windows, glow, root, size=BIG, solid=filled, skip=vk.NO_BACK_UNDER, faces=None)
for m in (o, fo, wn):
    drop_back_sides(m)
vk.report("backdrop city", root, budget=10000)
vk.export(os.path.join(MODELS, "backdrop_voxel_city.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "city_front.png"), (0.0, -1.0, 0.1), (0, 0, 5.5), 62.0, 1700, 560)
pv.shoot(os.path.join(PREVIEW, "city_close.png"), (0.15, -1.0, 0.15), (-8, 0, 6), 26.0, 1500, 800)
pv.shoot(os.path.join(PREVIEW, "city_close2.png"), (0.15, -1.0, 0.15), (20, 0, 6), 26.0, 1500, 800)
print("DONE voxel backdrop city")
