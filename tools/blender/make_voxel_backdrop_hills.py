"""Bee Bee — the far backdrop "hills and mountains" as voxel art.

  blender --background --factory-startup --python make_voxel_backdrop_hills.py -- <models_dir> <preview_dir>

The backdrop hangs 95 units behind the play plane, where the perspective
camera shrinks everything to under a fifth of its size: cubes of the usual
0.04 would be invisible there. So it is built from cubes five times bigger
(BIG = 0.2), which land on screen at about the same size as every other
cube in the game. It is three layers one behind the other — green hills,
blue hills, purple mountains with snow — each a stepped wall a few cubes
thick, with the light and shade painted on (lit left slopes, darker right
slopes): real stepped relief would turn into thin stripes at this size.
Same footprint as the low-poly backdrop (peaks at x = -14, 6, 26, the
tallest 17 units high, foot at z = 0). Colour varies per patch and equal
faces are merged; the back and underside are never seen and are left out.
Exports backdrop_voxel_hills.glb and review renders.
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

BIG = 0.2
X0, X1 = -225, 225           # 90 units wide
FLOOR = -22                  # the walls run well below the foot, behind the horizon slab
THICK = 2                    # thin walls: the sides of the silhouette's steps catch the light as dotted lines

GREEN = [(0.46, 0.76, 0.46), (0.50, 0.80, 0.49), (0.42, 0.72, 0.44)]
GREEN_EDGE = (0.58, 0.86, 0.54)
GREEN_DEEP = (0.38, 0.67, 0.42)
BLUE = [(0.60, 0.72, 0.94), (0.64, 0.76, 0.96), (0.56, 0.68, 0.91)]
BLUE_EDGE = (0.72, 0.82, 0.99)
ROCK_LIT = [(0.64, 0.60, 0.89), (0.68, 0.64, 0.92)]
ROCK_SHADE = [(0.50, 0.47, 0.78), (0.46, 0.43, 0.74)]
SNOW = (1.0, 1.0, 1.0)
SNOW_SHADE = (0.84, 0.87, 1.0)

PEAKS = [(-70, 60, 46), (30, 85, 56), (130, 55, 41)]      # centre x, height, half-width (in big cubes)


def h(*k):
    n = 0x9E3779B1
    for v in k:
        n = ((n ^ ((v * 0x85EBCA6B) & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 2 ** 32


def green_top(x):
    return round(12 + 5 * math.sin(x * 0.047 + 2.0) + 3 * math.sin(x * 0.121 + 0.4))


def blue_top(x):
    return round(21 + 7 * math.sin(x * 0.034 + 1.0) + 4 * math.sin(x * 0.083 + 2.2))


def peak_at(x):
    """(height, peak index) of the mountain silhouette at x; jagged, not ruler-straight."""
    best, who = -99.0, 0
    for i, (cx, ph, w) in enumerate(PEAKS):
        t = abs(x - cx) / w
        z = ph * (1.0 - t ** 1.15) + 2.2 * math.sin(x * 0.31 + i) * min(1.0, t * 3)
        if z > best:
            best, who = z, i
    return round(best), who


def backdrop():
    cells = {}
    solid = set()

    def wall(y0, top, colour):
        for x in range(X0, X1):
            t = top(x)
            for z in range(FLOOR, t + 1):
                cells[(x, y0, z)] = colour(x, z, t)
                for y in range(y0 + 1, y0 + THICK):
                    if z == t:
                        cells[(x, y, z)] = colour(x, z, t)          # the top of the wall shows from above
                    else:
                        solid.add((x, y, z))

    def green(x, z, t):
        if z >= t - 1:
            return GREEN_EDGE
        if z < t - 9 and h(x // 5, z // 3, 11) < 0.5:
            return GREEN_DEEP
        return GREEN[int(h((x + (z // 3 % 2) * 2) // 5, z // 3, 1) * 3)]

    def blue(x, z, t):
        if z >= t - 1:
            return BLUE_EDGE
        return BLUE[int(h((x + (z // 3 % 2) * 3) // 6, z // 3, 2) * 3)]

    def rock(x, z, t):
        _, i = peak_at(x)
        cx, ph, w = PEAKS[i]
        # the ridge runs down from the summit, leaning a little to the right
        lit = x < cx + (ph - z) * 0.12 + 2.5 * math.sin(z * 0.4 + i)
        snow_line = ph * 0.74 + 3.0 * math.sin(x * 0.55 + i * 2) + 2.0 * math.sin(x * 0.21)
        if z > snow_line:
            return SNOW if lit else SNOW_SHADE
        tones = ROCK_LIT if lit else ROCK_SHADE
        return tones[int(h((x + (z // 4 % 2) * 3) // 6, z // 4, 3) * 2)]

    wall(30, lambda x: peak_at(x)[0], rock)
    wall(15, blue_top, blue)
    wall(0, green_top, green)
    return cells, solid


cells, solid = backdrop()
vk.reset()
root = vk.empty("Hills")
o = vk.build_mesh_merged("Hills", cells, vk.material("Voxel", rough=0.9), root, size=BIG,
                         solid=lambda x, y, z: (x, y, z) in solid, skip=((0, 1, 0), (0, 0, -1)))
print("backdrop hills cubes:", len(cells), "polygons:", len(o.data.polygons))
vk.export(os.path.join(MODELS, "backdrop_voxel_hills.glb"))

# ---------------------------------------------------------------- review renders
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "hills_front.png"), (0.0, -1.0, 0.1), (5, 0, 6.5), 62.0, 1700, 620)
pv.shoot(os.path.join(PREVIEW, "hills_3q.png"), (0.45, -1.0, 0.45), (5, 0, 6), 62.0, 1700, 760)
pv.shoot(os.path.join(PREVIEW, "hills_close.png"), (0.25, -1.0, 0.3), (6, 0, 11), 22.0, 1100, 760)
print("DONE voxel backdrop hills")
