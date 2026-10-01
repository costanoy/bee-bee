"""Bee Bee — the seagull (drifting scenery) as voxel art.

  blender --background --factory-startup --python make_voxel_gull.py -- <models_dir> <preview_dir>

Seen from the side in the game, flying towards +X: a plump white body with
a grey back, a round head with a dark eye and an orange beak, a short fan
tail, and two grey wings with dark tips. The wings hang off WingPivotL/R
(same names as the low-poly gull) and lie flat at rest; the game flaps
them by rotating the pivots around X. Built on the shared voxel grid at
its in-game size, so it's used unscaled. Exports gull_voxel.glb and review
renders (wings up / level / down, with the voxel bee for scale).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(PREVIEW, exist_ok=True)

WHITE = (0.98, 0.98, 1.0)
BELLY = (0.90, 0.93, 1.0)
GREY = (0.62, 0.69, 0.82)
GREY_LIGHT = (0.74, 0.80, 0.90)
DARK = (0.20, 0.22, 0.30)
BEAK = (1.0, 0.68, 0.14)
BEAK_TIP = (0.93, 0.36, 0.14)
EYE = (0.05, 0.05, 0.08)

WING_SPAN = 13          # cubes from shoulder to tip
SHOULDER = (0, 2, 1)    # wing pivot (x, |y|, z) in cubes


def body():
    vox = {}
    # torso: an egg, fuller at the chest than at the tail
    for x in range(-8, 8):
        for y in range(-4, 4):
            for z in range(-4, 4):
                cx, cy, cz = x + 0.5, y + 0.5, z + 0.5
                rx = 7.0
                r = 3.0 if cx > 0 else 3.0 - 1.1 * (-cx / rx) ** 1.5      # taper towards the tail
                if (cx / rx) ** 2 + (cy / r) ** 2 + (cz / r) ** 2 <= 1.0:
                    vox[(x, y, z)] = GREY if (cz > 0.9 and cx < 3) else (BELLY if cz < -1.4 else WHITE)
    # tail: a flat fan, grey on top like the back, dark at the very end
    for x in range(-11, -5):
        half = 2 if x > -10 else 1
        for y in range(-half, half):
            for z in (0, 1):
                if (x, y, z) not in vox:
                    vox[(x, y, z)] = DARK if x == -11 else (GREY if z == 1 else WHITE)
    # head
    hx, hz, hr = 5.5, 1.6, 2.6
    for x in range(2, 10):
        for y in range(-3, 3):
            for z in range(-2, 6):
                if (x + 0.5 - hx) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - hz) ** 2 <= hr * hr:
                    vox[(x, y, z)] = WHITE
    # beak: two cubes tall at the face, one at the tip
    front = max(x for (x, y, z) in vox if z == 1 and y == 0)
    for y in (-1, 0):
        vox[(front + 1, y, 1)] = BEAK
        vox[(front + 1, y, 0)] = BEAK
        vox[(front + 2, y, 1)] = BEAK
        vox[(front + 3, y, 0)] = BEAK_TIP
        vox[(front + 2, y, 0)] = BEAK
    # eyes: the outermost head cube on each side, a little above the beak
    ex, ez = 6, 2
    ys = [y for (x, y, z) in vox if x == ex and z == ez]
    vox[(ex, min(ys), ez)] = EYE
    vox[(ex, max(ys), ez)] = EYE
    return vox


def wing(side):
    """Local to the pivot: spans outwards along side*Y, flat in XY."""
    vox = {}
    for j in range(WING_SPAN):
        t = j / (WING_SPAN - 1)
        lead = 3 - round(2.5 * t * t)                    # leading edge sweeps back near the tip
        chord = max(2, round(7 - 4.5 * t))
        y = j if side > 0 else -j - 1
        for i in range(chord):
            x = lead - i
            if j >= WING_SPAN - 3:
                c = DARK
            elif i == chord - 1:
                c = WHITE                                # pale trailing edge
            elif i == 0:
                c = GREY_LIGHT
            else:
                c = GREY
            vox[(x, y, 0)] = c
            if j < 5 and 0 < i < chord - 1:
                vox[(x, y, 1)] = GREY_LIGHT if i == 1 else GREY     # thicker by the shoulder
    return vox


def gull(mat, at=(0, 0, 0), flap=0.0):
    root = vk.empty("Gull", at)
    vk.build_mesh("Body", body(), mat, root, seed=5, jitter=0.03)
    for side, tag in ((-1, "L"), (1, "R")):
        piv = vk.empty("WingPivot" + tag, (SHOULDER[0] * vk.VOX, side * SHOULDER[1] * vk.VOX, SHOULDER[2] * vk.VOX), root)
        vk.build_mesh("Wing", wing(side), mat, piv, seed=9, jitter=0.03)
        piv.rotation_euler = (flap * side, 0, 0)
    return root


vk.reset()
gull(vk.material("Voxel"))
vk.export(os.path.join(MODELS, "gull_voxel.glb"))

# ---------------------------------------------------------------- review renders
vk.reset()
mat = vk.material("Voxel")
for i, flap in enumerate((0.8, 0.0, -0.8)):
    gull(mat, (i * 1.25 - 1.6, 0, 0), flap)
try:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "bee_voxel.glb"))
    bee = [o for o in bpy.context.scene.objects if o.name == "Bee"][0]
    bee.scale = (0.8, 0.8, 0.8)
    bee.location = (2.25, 0, 0)
    for o in bpy.context.scene.objects:
        if o.name.startswith("XEyes") or o.name.startswith("DeadEyes"):
            o.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "gull_side.png"), (0.0, -1.0, 0.13), (0.2, 0, 0.1), 5.4, 1500, 560)
pv.shoot(os.path.join(PREVIEW, "gull_3q.png"), (0.55, -1.0, 0.5), (0.2, 0, 0.1), 5.4, 1500, 760)
pv.shoot(os.path.join(PREVIEW, "gull_close.png"), (0.6, -1.0, 0.45), (-0.35, 0, 0.05), 1.5, 900, 800)
pv.shoot(os.path.join(PREVIEW, "gull_top.png"), (0.15, -0.5, 1.0), (-0.35, 0, 0.0), 1.5, 900, 800)
print("DONE voxel gull")
