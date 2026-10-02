"""Bee Bee — the far backdrop "city" as voxel art.

  blender --background --factory-startup --python make_voxel_backdrop_city.py -- <models_dir> <preview_dir>

A storybook town in three layers, so it reads as a place with depth rather
than a row of boxes: green hills at the back, a hazy blue skyline in front
of them, and the town itself up front — gabled houses with tiled roofs and
chimneys, apartment blocks with rooftop tanks, stepped-gable houses, shops
with striped awnings, a clock tower and a domed hall, with trees along the
street. No two neighbours are the same kind or the same colour.

Built like the hills backdrop: from cubes five times the usual size
(BIG = 0.2), because 95 units back the camera shrinks them to the size of
every other cube on screen, and as thin walls with the shading painted on
(lit left edge, shaded right edge, a shadow under every roof).

Three meshes: "City" (the street and its trees), "Far" (the skyline and the
hills) and "Windows", which has a glowing material so they stay lit when
the scene goes dark. The game hazes "Far" with its depth fog, which takes
the colour of the sky at every hour, and draws the other two without it:
fog turned the street's warm walls lilac. Same footprint as before (84
units wide, foot at z = 0). Exports backdrop_voxel_city.glb and review
renders.
"""
import bpy, math, random, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.2
X0, X1 = -225, 225
FLOOR = -22
THICK = 2
HILLS_Y = 30
FAR_Y = 14              # the hazy skyline
TREE_Y = -3             # street trees, in front of the houses
# In the game the grass in front hides everything below about this height,
# so the street (doors, shop fronts, tree trunks) is drawn from here up.
STREET = 13

# Stronger than they should look: the game's depth haze takes a third of the
# saturation back out.
# Warm on purpose: blues and lilacs belong to the skyline behind, and a
# house in those colours sank into it.
WALLS = [(1.0, 0.90, 0.66), (1.0, 0.70, 0.48), (0.96, 0.46, 0.42), (1.0, 0.80, 0.32), (0.58, 0.82, 0.56),
         (1.0, 0.60, 0.72), (0.99, 0.97, 0.90), (0.92, 0.62, 0.40)]
ROOFS = [(0.86, 0.38, 0.30), (0.34, 0.42, 0.66), (0.22, 0.58, 0.58), (0.56, 0.34, 0.58), (0.62, 0.38, 0.28)]
STONE = (0.96, 0.93, 0.84)
TRIM = (0.99, 0.98, 0.94)
BRICK = (0.70, 0.40, 0.34)
DOOR = (0.46, 0.30, 0.26)
WINDOW = (1.0, 0.94, 0.66)
GOLD = (1.0, 0.80, 0.30)
COPPER = (0.30, 0.68, 0.62)
AWNING = [((0.92, 0.32, 0.34), TRIM), ((0.24, 0.56, 0.78), TRIM), ((0.30, 0.64, 0.44), TRIM)]
BLOOMS = [(0.96, 0.34, 0.44), (1.0, 0.80, 0.30), (0.98, 0.62, 0.80)]
LEAF = [(0.30, 0.56, 0.36), (0.38, 0.68, 0.40), (0.52, 0.80, 0.46)]
TRUNK = (0.50, 0.36, 0.28)
FAR = [(0.52, 0.70, 0.94), (0.58, 0.75, 0.96), (0.48, 0.66, 0.92)]
HILL = [(0.50, 0.78, 0.50), (0.54, 0.82, 0.53), (0.46, 0.74, 0.48)]
HILL_EDGE = (0.62, 0.88, 0.58)


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def shade(c, f):
    return tuple(min(1.0, v * f) for v in c)


def hill_top(x):
    return round(17 + 5 * math.sin(x * 0.041 + 0.6) + 3 * math.sin(x * 0.11 + 1.9))


def city():
    walls, solid, windows = {}, set(), {}

    def put(x, z, c, y=0):
        """One cube of wall, THICK cubes deep; only the front shows."""
        if z < FLOOR or not X0 - 12 <= x < X1 + 12:
            return
        z += STREET
        walls[(x, y, z)] = c
        windows.pop((x, y, z), None)
        for k in range(1, THICK):
            solid.add((x, y + k, z))

    def glass(x, z, y=0):
        cell = (x, y, z + STREET)
        if cell in walls:
            del walls[cell]
            solid.add(cell)
            windows[cell] = WINDOW

    def rect(x, z, w, ht, c, y=0):
        for dx in range(w):
            for dz in range(ht):
                put(x + dx, z + dz, c, y)

    def body(x, w, ht, base):
        """A house front: lit left edge, shaded right edge."""
        for dx in range(w):
            c = shade(base, 1.07) if dx == 0 else (shade(base, 0.85) if dx >= w - 2 else base)
            for z in range(FLOOR, ht):
                put(x + dx, z, c)

    def window(x, z, w, ht, base, arched=False, box=None):
        """Glass with a pale sill that sticks out a cube and a shadow line
        above; `box` plants a flower box on the sill."""
        for dx in range(w):
            for dz in range(ht):
                if arched and dz == ht - 1 and dx in (0, w - 1):
                    continue
                glass(x + dx, z + dz)
        for dx in range(-1, w + 1):
            if box is None:
                put(x + dx, z - 1, TRIM, -1)
            else:
                put(x + dx, z - 1, LEAF[1] if (dx + w) % 2 else box, -1)
        if not arched:
            for dx in range(w):
                put(x + dx, z + ht, shade(base, 0.80))

    def window_grid(x, w, z0, z1, base, ww=3, wh=4, gap_x=3, gap_z=5, boxes=None, arched=False):
        cols = max(1, (w - 4 + gap_x) // (ww + gap_x))
        left = x + (w - (cols * (ww + gap_x) - gap_x)) // 2
        z = z0
        row = 0
        while z + wh < z1:
            for c in range(cols):
                box = None
                if boxes is not None and h(x, c, row, 7) < 0.4:
                    box = boxes[int(h(x, c, row, 9) * len(boxes))]
                window(left + c * (ww + gap_x), z, ww, wh, base, arched, box)
            z += wh + gap_z
            row += 1

    def door(x, w, base):
        left = x + (w - 3) // 2
        rect(left, FLOOR, 3, 5 - FLOOR, DOOR)
        for dx in range(-1, 4):
            put(left + dx, 5, shade(base, 0.80))

    def eaves(x, w, ht, base):
        for dx in range(w):
            put(x + dx, ht - 1, shade(base, 0.78))

    # ------------------------------------------------------------ the buildings
    def townhouse(x, w, ht, base, roof, rng):
        body(x, w, ht, base)
        eaves(x, w, ht, base)
        door(x, w, base)
        window_grid(x, w, 9, ht - 2, base, boxes=BLOOMS)
        # tiled gable, one cube of overhang each side, tile rows in two tones
        span = w + 2
        rise = (span + 1) // 2
        for k in range(rise):
            for dx in range(k, span - k):
                c = roof if k % 2 == 0 else shade(roof, 0.88)
                if dx >= span / 2:
                    c = shade(c, 0.84)
                put(x - 1 + dx, ht + k, c)
        for dx in range(span):
            put(x - 1 + dx, ht, shade(roof, 1.12), -1)               # the eave's lip
        if w >= 15:                                                   # attic window
            glass(x + w // 2 - 1, ht + 3)
            glass(x + w // 2, ht + 3)
            glass(x + w // 2 - 1, ht + 4)
            glass(x + w // 2, ht + 4)
        cx = x + (2 if rng.random() < 0.5 else w - 5)                 # chimney
        base_z = ht + min(cx - x + 1, x + w - cx - 2)
        rect(cx, base_z, 3, rise - (base_z - ht) + 3, BRICK)
        rect(cx - 1, ht + rise + 2, 5, 1, shade(BRICK, 0.80))

    def apartments(x, w, ht, base, roof, rng):
        body(x, w, ht, base)
        door(x, w, base)
        window_grid(x, w, 9, ht - 3, base, gap_z=4)
        z = 7
        while z < ht - 4:                                             # a line under every floor
            for dx in range(1, w - 2):
                if (x + dx, 0, z + STREET) in walls:
                    put(x + dx, z, shade(base, 0.90))
            z += 8
        rect(x - 1, ht, w + 2, 2, shade(base, 1.10))                  # parapet
        rect(x - 1, ht + 1, w + 2, 1, TRIM, -1)
        kind = rng.randint(0, 2)
        if kind == 0:                                                 # water tank on legs
            tx = x + 2
            put(tx, ht + 2, DOOR)
            put(tx + 4, ht + 2, DOOR)
            rect(tx - 1, ht + 3, 7, 4, roof)
            rect(tx - 1, ht + 7, 7, 1, shade(roof, 0.80))
            rect(tx + 4, ht + 3, 2, 4, shade(roof, 0.84))
        elif kind == 1:                                               # stair hut and aerial
            rect(x + w - 8, ht + 2, 6, 5, shade(base, 0.92))
            rect(x + w - 9, ht + 7, 8, 1, roof)
            for dz in range(9):
                put(x + 3, ht + 2 + dz, DOOR)
            rect(x + 2, ht + 8, 3, 1, DOOR)
        else:                                                         # a little roof garden
            for dx in range(2, w - 2):
                if h(x, dx, 3) < 0.6:
                    put(x + dx, ht + 2, LEAF[int(h(x, dx, 4) * 3)])
                    if h(x, dx, 5) < 0.35:
                        put(x + dx, ht + 3, BLOOMS[int(h(x, dx, 6) * 3)])

    def stepped(x, w, ht, base, roof, rng):
        """A narrow house with a stepped gable."""
        body(x, w, ht, base)
        door(x, w, base)
        window_grid(x, w, 9, ht - 1, base, ww=2, wh=5, gap_x=3, gap_z=4, boxes=BLOOMS)
        k = 0
        z = ht
        while w - 4 * k > 1:
            ww = w - 4 * k
            rect(x + 2 * k, z, ww, 3, base)
            rect(x + 2 * k, z + 2, ww, 1, TRIM)
            put(x + 2 * k, z, shade(base, 1.07))
            put(x + 2 * k, z + 1, shade(base, 1.07))
            for dz in range(2):
                put(x + 2 * k + ww - 1, z + dz, shade(base, 0.85))
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
            put(x + dx, 10, shade(c, 0.9), -1)
            put(x + dx, 9, c, -2)
            if dx % 4 < 2:
                put(x + dx, 8, c, -2)
        rect(x + 2, 12, w - 4, 4, shade(roof, 0.95))                  # the sign
        for dx in range(4, w - 4):
            if h(x, dx, 11) < 0.55:
                put(x + dx, 13 + int(h(x, dx, 12) * 2), TRIM)
        rect(x - 1, ht, w + 2, 1, TRIM, -1)                           # cornice
        rect(x - 1, ht, w + 2, 1, TRIM)
        rect(x + 3, ht + 1, w - 6, 2, shade(base, 0.92))
        rect(x + 3, ht + 3, w - 6, 1, roof)

    def clock_tower(x, w, ht, base, roof, rng):
        body(x, w, ht, STONE)
        door(x, w, STONE)
        window_grid(x, w, 10, ht - 16, STONE, ww=3, wh=6, gap_z=6, arched=True)
        rect(x - 1, ht - 13, w + 2, 1, TRIM, -1)                      # ledge under the clock
        cx, cz = x + w // 2, ht - 7
        for dx in range(-3, 4):                                       # the clock
            for dz in range(-3, 4):
                d = dx * dx + dz * dz
                if d <= 6:
                    put(cx + dx, cz + dz, TRIM)
                elif d <= 11:
                    put(cx + dx, cz + dz, shade(roof, 0.9))
        put(cx, cz, DOOR)
        put(cx, cz + 1, DOOR)
        put(cx, cz + 2, DOOR)
        put(cx + 1, cz, DOOR)
        rect(x - 1, ht, w + 2, 1, TRIM, -1)
        rect(x - 1, ht, w + 2, 1, TRIM)
        k = 0                                                         # steep spire: one cube in for two up
        while w + 2 - 2 * k > 0:
            ww = w + 2 - 2 * k
            for dz in range(2):
                for dx in range(ww):
                    c = roof if dx < ww / 2 else shade(roof, 0.82)
                    put(x - 1 + k + dx, ht + 1 + 2 * k + dz, c)
            k += 1
        top = ht + 1 + 2 * k
        put(cx, top, DOOR)
        put(cx, top + 1, DOOR)
        put(cx, top + 2, GOLD)

    def hall(x, w, ht, base, roof, rng):
        """A domed hall with columns."""
        body(x, w, ht, STONE)
        for dx in range(2, w - 2, 5):                                 # columns
            rect(x + dx, FLOOR, 2, ht - 3 - FLOOR, TRIM, -1)
        for dx in range(4, w - 4, 5):                                 # arched windows between them
            if dx + 2 < w - 2:
                window(x + dx + 1, 6, 2, 7, STONE, arched=False)
        rect(x - 1, ht - 3, w + 2, 3, shade(STONE, 0.94))
        rect(x - 1, ht - 1, w + 2, 1, TRIM, -1)
        rect(x + 2, ht, w - 4, 2, STONE)                              # drum
        cx = x + w / 2
        r = (w - 6) / 2
        for dz in range(int(r) + 1):                                  # dome
            half = math.sqrt(max(0.0, r * r - dz * dz))
            for xi in range(int(math.floor(cx - half)), int(math.ceil(cx + half))):
                t = (xi + 0.5 - cx) / r
                c = shade(COPPER, 1.18) if t < -0.35 else (shade(COPPER, 0.82) if t > 0.45 else COPPER)
                put(xi, ht + 2 + dz, c)
        top = ht + 3 + int(r)
        mid = int(cx) - 1
        rect(mid, top, 3, 3, STONE)
        glass(mid + 1, top + 1)
        rect(mid - 1, top + 3, 5, 1, COPPER)
        put(mid + 1, top + 4, COPPER)
        put(mid + 1, top + 5, GOLD)

    def tree(x, r, z):
        for dz in range(FLOOR, z):
            put(x, dz, TRUNK, TREE_Y)
            put(x + 1, dz, shade(TRUNK, 0.85), TREE_Y)
        for dx in range(-r, r + 2):
            for dz in range(-r, r + 1):
                d = math.hypot(dx - 0.5, dz * 1.15)
                if d <= r:
                    lit = (-(dx - 0.5) + dz) / r
                    c = LEAF[2] if lit > 0.75 else (LEAF[0] if lit < -0.45 else LEAF[1])
                    put(x + dx, z + r + dz - 1, c, TREE_Y)

    # ------------------------------------------------------------ hills at the back
    for x in range(X0, X1):
        t = hill_top(x)
        for z in range(FLOOR, t + 1):
            walls[(x, HILLS_Y, z)] = HILL_EDGE if z >= t - 1 else HILL[int(h((x + (z // 3 % 2) * 2) // 5, z // 3, 1) * 3)]
            for y in range(HILLS_Y + 1, HILLS_Y + THICK):
                if z == t:
                    walls[(x, y, z)] = HILL_EDGE
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
                put(x + dx, z, shade(c, 0.92) if dx >= w - 2 else c, FAR_Y)
        top = rng.randint(0, 3)
        if top == 0 and w >= 14:                                      # a set-back upper storey
            rect(x + 3, ht, w - 6, 6, c, FAR_Y)
        elif top == 1:                                                # mast
            rect(x + w // 2, ht, 1, 9, shade(c, 0.9), FAR_Y)
        elif top == 2:                                                # pointed top
            for k in range(w // 2):
                rect(x + k, ht + k, w - 2 * k, 1, shade(c, 0.95), FAR_Y)
        for wx in range(x + 2, x + w - 3, 4):                         # a scatter of small windows
            for wz in range(12, ht - 4, 6):
                r = h(wx, wz, 21)
                if r < 0.16:
                    glass(wx, wz, FAR_Y)
                    glass(wx + 1, wz, FAR_Y)
                elif r < 0.62:
                    put(wx, wz, shade(c, 1.10), FAR_Y)
                    put(wx + 1, wz, shade(c, 1.10), FAR_Y)
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
    return walls, solid, windows


walls, solid, windows = city()
vk.reset()
root = vk.empty("City")
UNSEEN = ((0, 1, 0), (0, 0, -1))
filled = lambda x, y, z: (x, y, z) in solid or (x, y, z) in walls
near = {k: c for k, c in walls.items() if k[1] < FAR_Y}
far = {k: c for k, c in walls.items() if k[1] >= FAR_Y}
o = vk.build_mesh_merged("City", near, vk.material("Voxel", rough=0.8), root, size=BIG, solid=filled, skip=UNSEEN)
fo = vk.build_mesh_merged("Far", far, vk.material("VoxelFar", rough=0.8), root, size=BIG, solid=filled, skip=UNSEEN)
glow = vk.material("VoxelWindow", rough=0.4)
p = glow.node_tree.nodes["Principled BSDF"]
p.inputs["Emission Color"].default_value = (*vk.lin(WINDOW), 1)
p.inputs["Emission Strength"].default_value = 0.8
wn = vk.build_mesh_merged("Windows", windows, glow, root, size=BIG,
                          solid=lambda x, y, z: (x, y, z) in walls or ((x, y, z) in solid and (x, y, z) not in windows),
                          skip=UNSEEN)
print("backdrop city cubes:", len(walls) + len(windows), "polygons:", len(o.data.polygons) + len(fo.data.polygons) + len(wn.data.polygons))
vk.export(os.path.join(MODELS, "backdrop_voxel_city.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "city_front.png"), (0.0, -1.0, 0.1), (0, 0, 5.5), 62.0, 1700, 560)
pv.shoot(os.path.join(PREVIEW, "city_close.png"), (0.15, -1.0, 0.15), (-8, 0, 6), 26.0, 1500, 800)
pv.shoot(os.path.join(PREVIEW, "city_close2.png"), (0.15, -1.0, 0.15), (20, 0, 6), 26.0, 1500, 800)
print("DONE voxel backdrop city")
