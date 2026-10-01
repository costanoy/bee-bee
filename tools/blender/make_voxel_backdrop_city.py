"""Bee Bee — the far backdrop "city" as voxel art.

  blender --background --factory-startup --python make_voxel_backdrop_city.py -- <models_dir> <preview_dir>

A row of pastel town houses in front of a line of green hills, built like
the hills backdrop: from cubes five times the usual size (BIG = 0.2),
because 95 units back the camera shrinks them to the size of every other
cube on screen, and as thin walls with the shading painted on. Each house
gets a slightly darker right edge, a cornice or a red gabled roof, and a
grid of windows. The windows are a second mesh with a glowing material,
so they stay lit when the scene goes dark, like the low-poly city's did.
Same footprint as the low-poly backdrop (houses 3–5 units wide and 5–11
tall, 84 units of them, foot at z = 0). Exports backdrop_voxel_city.glb
and review renders.
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

PALETTE = [(1.0, 0.62, 0.56), (0.98, 0.82, 0.44), (0.56, 0.78, 0.98), (0.72, 0.62, 0.96), (0.60, 0.88, 0.70),
           (1.0, 0.74, 0.86)]
ROOF = (0.90, 0.40, 0.36)
ROOF_SHADE = (0.74, 0.30, 0.30)
WINDOW = (1.0, 0.95, 0.70)
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

    def put(x, z, c):
        """One column of wall, THICK cubes deep; only the front shows."""
        walls[(x, 0, z)] = c
        for y in range(1, THICK):
            solid.add((x, y, z))

    # the hills behind
    for x in range(X0, X1):
        t = hill_top(x)
        for z in range(FLOOR, t + 1):
            walls[(x, HILLS_Y, z)] = HILL_EDGE if z >= t - 1 else HILL[int(h((x + (z // 3 % 2) * 2) // 5, z // 3, 1) * 3)]
            for y in range(HILLS_Y + 1, HILLS_Y + THICK):
                if z == t:
                    walls[(x, y, z)] = HILL_EDGE
                else:
                    solid.add((x, y, z))

    rng = random.Random(12)
    x = -212
    i = 0
    bag, base = [], None
    while x < 212:
        w, ht = rng.randint(16, 24), rng.randint(25, 55)
        if not bag:                                # deal the colours like cards, so all six keep turning up
            bag = PALETTE[:]
            rng.shuffle(bag)
            if bag[-1] == base:
                bag.insert(0, bag.pop())
        base = bag.pop()
        gabled = rng.random() < 0.5
        tones = [base, shade(base, 0.955)]
        for dx in range(w - 1):                    # the last column is left empty: a one-cube alley
            for z in range(FLOOR, ht):
                if dx >= w - 3:
                    c = shade(base, 0.86)          # right edge in shade
                elif not gabled and z >= ht - 2:
                    c = shade(base, 0.80)          # cornice
                else:
                    c = tones[int(h(dx // 5, z // 4, i) * 2)]
                put(x + dx, z, c)
        if gabled:
            # a stepped gable, overhanging the walls by one cube each side
            width = w + 1
            for k in range(width // 2 + 1):
                for dx in range(-1 + k, width - 1 - k):
                    put(x + dx, ht + k, ROOF if dx < (width - 2) / 2 else ROOF_SHADE)
        # windows: 3 wide, 4 tall, in a centred grid
        cols = max(1, (w - 5) // 6)
        rows = max(1, (ht - 8) // 9)
        left = x + (w - 1 - (cols * 6 - 3)) // 2
        for r in range(rows):
            for c in range(cols):
                for dx in range(3):
                    for dz in range(4):
                        cell = (left + c * 6 + dx, 0, 6 + r * 9 + dz)
                        if cell in walls:
                            del walls[cell]
                            solid.add(cell)
                            windows[cell] = WINDOW
        x += w
        i += 1
    return walls, solid, windows


walls, solid, windows = city()
vk.reset()
root = vk.empty("City")
UNSEEN = ((0, 1, 0), (0, 0, -1))
o = vk.build_mesh_merged("City", walls, vk.material("Voxel", rough=0.8), root, size=BIG,
                         solid=lambda x, y, z: (x, y, z) in solid, skip=UNSEEN)
glow = vk.material("VoxelWindow", rough=0.4)
p = glow.node_tree.nodes["Principled BSDF"]
p.inputs["Emission Color"].default_value = (*vk.lin(WINDOW), 1)
p.inputs["Emission Strength"].default_value = 0.8
wn = vk.build_mesh_merged("Windows", windows, glow, root, size=BIG,
                          solid=lambda x, y, z: (x, y, z) in walls or ((x, y, z) in solid and (x, y, z) not in windows),
                          skip=UNSEEN)
print("backdrop city cubes:", len(walls) + len(windows), "polygons:", len(o.data.polygons) + len(wn.data.polygons))
vk.export(os.path.join(MODELS, "backdrop_voxel_city.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "city_front.png"), (0.0, -1.0, 0.1), (0, 0, 4.5), 62.0, 1700, 520)
pv.shoot(os.path.join(PREVIEW, "city_close.png"), (0.3, -1.0, 0.3), (0, 0, 5), 24.0, 1300, 700)
print("DONE voxel backdrop city")
