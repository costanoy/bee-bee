"""Bee Bee — the seagull (drifting scenery) as voxel art.

  blender --background --factory-startup --python make_voxel_gull.py -- <models_dir> <preview_dir> [scale_bee.glb]

Seen from the side in the game, flying towards +X: a small, clean
storybook seabird. A plump white body with a pearl-grey back, a big round
head (the cute share: about a third of its length) with a 2 x 2 dark eye
in its middle and a golden beak with the gull's red spot, a short white
fan tail, and two long pearl-grey wings with small slate tips, a white
leading edge (so the flap reads at a distance) and a white underside. It
is scenery and stays it: no inks, soft values, and the game hazes it 50%
toward the horizon. Painted, not jittered: a gentle vertical gradient and
a lavender-grey belly, like the clouds. The wings hang off
WingPivotL/R and lie flat at rest; the game flaps them by rotating the
pivots around X. It turns round in the game (yaw PI when it flies left),
so no faces are skipped. Built on the shared voxel grid at its in-game
size, so it's used unscaled. Exports gull_voxel.glb and review renders
(wings up / level / down, with the voxel bee for scale).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
BEE = ARGS[2] if len(ARGS) > 2 else os.path.join(MODELS, "bee_voxel.glb")
os.makedirs(PREVIEW, exist_ok=True)

# STYLE.md "Mid layer": today's whites and greys, a warmer beak, no inks
WHITE = (0.98, 0.98, 1.00)
BELLY = (0.86, 0.85, 0.94)          # the clouds' lavender, lighter
PEARL = (0.70, 0.72, 0.82)          # back and wing tops
PEARL_LIGHT = (0.80, 0.82, 0.90)
PEARL_DEEP = (0.52, 0.54, 0.66)
SLATE = (0.26, 0.27, 0.36)          # wing tips and the eye: the darkest, still not ink
BEAK = (1.00, 0.70, 0.16)
BEAK_SPOT = (0.95, 0.36, 0.18)

WING_SPAN = 13          # cubes from shoulder to tip
SHOULDER = (0, 2, 1)    # wing pivot (x, |y|, z) in cubes


def body():
    vox = {}
    # torso: an egg, full at the chest, tapering to the tail
    for x in range(-8, 6):
        for y in range(-4, 4):
            for z in range(-4, 4):
                cx, cy, cz = x + 0.5, y + 0.5, z + 0.5
                r = 3.2 if cx > -1 else 3.2 - 1.3 * ((-cx - 1) / 7.0) ** 1.4
                if (cx / 6.8) ** 2 + (cy / r) ** 2 + ((cz + 0.2) / r) ** 2 <= 1.0:
                    vox[(x, y, z)] = PEARL if (cz > 1.2 and cx < 2.5) else WHITE
    # tail: a short fan, pearl on top, white below
    for x in range(-11, -6):
        half = 2 if x > -10 else 1
        for y in range(-half, half):
            for z in (0, 1):
                if (x, y, z) not in vox:
                    vox[(x, y, z)] = PEARL if z == 1 else WHITE
    # head: big and round, set up and forward
    hx, hz, hr = 5.0, 2.2, 3.3
    for x in range(1, 10):
        for y in range(-4, 4):
            for z in range(-2, 7):
                if (x + 0.5 - hx) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - hz) ** 2 <= hr * hr:
                    vox[(x, y, z)] = WHITE
    vox = vk.gradient(vox, top=0.02, bottom=-0.04)
    vox = vk.rim(vox, "bottom", colour=BELLY, amount=0.8)
    # beak: two cubes tall at the face, a cube at the tip, the red spot under it
    front = max(x for (x, y, z) in vox if z == 1 and y == 0)
    for y in (-1, 0):
        for (dx, z) in ((1, 1), (1, 0), (2, 1), (2, 0), (3, 1)):
            vox[(front + dx, y, z)] = BEAK
        vox[(front + 3, y, 0)] = BEAK_SPOT
    # eyes: 2 x 2, the outermost head cubes on each side, above the beak
    for ex in (5, 6):
        for ez in (2, 3):
            ys = [y for (x, y, z) in vox if x == ex and z == ez]
            vox[(ex, min(ys), ez)] = SLATE
            vox[(ex, max(ys), ez)] = SLATE
    return vox


def wing(side):
    """Local to the pivot: spans outwards along side*Y, flat in XY, two cubes
    thick (pearl on top, white below)."""
    vox = {}
    for j in range(WING_SPAN):
        t = j / (WING_SPAN - 1)
        lead = 3 - round(2.5 * t * t)                    # leading edge sweeps back near the tip
        chord = max(2, round(7 - 4.5 * t))
        y = j if side > 0 else -j - 1
        for i in range(chord):
            x = lead - i
            if j >= WING_SPAN - 2:
                top = SLATE                              # the gull's dark tips, small
            elif j == WING_SPAN - 3:
                top = PEARL_DEEP
            elif i == 0:
                top = WHITE                              # white leading edge: the flap reads far away
            elif i == chord - 1:
                top = PEARL_LIGHT                        # paler trailing edge
            else:
                top = PEARL
            vox[(x, y, 0)] = top
            vox[(x, y, -1)] = SLATE if j >= WING_SPAN - 2 else WHITE
    return vox


def gull(mat, at=(0, 0, 0), flap=0.0):
    root = vk.empty("Gull", at)
    vk.build("Body", body(), mat, root)
    for side, tag in ((-1, "L"), (1, "R")):
        piv = vk.empty("WingPivot" + tag, (SHOULDER[0] * vk.VOX, side * SHOULDER[1] * vk.VOX, SHOULDER[2] * vk.VOX), root)
        vk.build("Wing", wing(side), mat, piv)
        piv.rotation_euler = (flap * side, 0, 0)
    return root


vk.reset()
g = gull(vk.material("Voxel"))
vk.report("gull", g, budget=1500)
vk.export(os.path.join(MODELS, "gull_voxel.glb"))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel")
for i, flap in enumerate((0.8, 0.0, -0.8)):
    gull(mat, (i * 1.25 - 1.6, 0, 0), flap)
try:
    bpy.ops.import_scene.gltf(filepath=BEE)
    bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (2.25, 0, 0)
    for o in bpy.context.scene.objects:
        if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
            o.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview(game_like=True)
pv.shoot(os.path.join(PREVIEW, "gull_side.png"), (0.0, -1.0, 0.13), (0.2, 0, 0.1), 5.4, 1500, 560)
pv.shoot(os.path.join(PREVIEW, "gull_3q.png"), (0.55, -1.0, 0.5), (0.2, 0, 0.1), 5.4, 1500, 760)
pv.shoot(os.path.join(PREVIEW, "gull_close.png"), (0.6, -1.0, 0.45), (-0.35, 0, 0.05), 1.5, 900, 800)
pv.shoot(os.path.join(PREVIEW, "gull_top.png"), (0.15, -0.5, 1.0), (-0.35, 0, 0.0), 1.5, 900, 800)
print("DONE voxel gull")
