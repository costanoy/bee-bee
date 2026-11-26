"""Bee Bee — the UFO (a night-sky event) as voxel art.

  blender --background --factory-startup --python make_voxel_ufo.py -- <models_dir> <preview_dir>

A toy flying saucer: a plump pearl-lilac lens with a round bumper all
the way round, mint on top and a deep plum-navy band below (the saucer's
one strong dark, which gives it punch against any sky) studded with
butter and pink lamps, a warm gold trim where the glass dome sits, and a
soft mint glow underneath. Inside the see-through dome, with a white rim
at its foot and a glint ring near its top, a friendly bright lime alien
with a face on both sides (the saucer spins, so it never shows the back
of a head): a big round head, big 3x3 plum eyes with white catchlights,
a little smile, rosy cheeks and two antennae with round knobs. Built at
its in-game size (about 2 units = 48 cubes across) and used unscaled. The game spins it and draws it
unshaded, so the hull is painted all the way round and lit from straight
above (the one light that stays put while it turns): a pale deck, a
deeper underside. Hull, alien and dome are separate meshes under one
root; the dome carries its transparency in its vertex colours like the
bee's wings, on its own single-sided "VoxelGlass" material.
Exports ufo_voxel.glb and review renders in the colours the game shows
(with the voxel bee for scale).
"""
import bpy, math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import voxel_kit as vk

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODELS, PREVIEW = ARGS[0], ARGS[1]
os.makedirs(MODELS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

# The game draws the sky bodies unshaded, through its Filmic tone mapping:
# a stored value s shows on screen as SCREEN(s), the same by day, at dusk
# and at night (measured per channel on grey swatches in the game's look).
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


R = 24.0                     # hull radius in cubes
# the hull's profile: radius by row, from the glow underneath up to the deck
PROFILE = {-7: 6.5, -6: 11.5, -5: 15.5, -4: 18.5, -3: 20.8, -2: 22.4, -1: 23.4, 0: 24.0, 1: 24.0,
           2: 23.4, 3: 20.5, 4: 17.5, 5: 14.0}

# on screen, lit from above: deck, side, underside; row -1, in the
# bumper's shadow, a step deeper than the underside below it
HULL = {5: (0.88, 0.86, 0.98), 4: (0.82, 0.80, 0.96), 3: (0.76, 0.73, 0.93), -1: (0.52, 0.48, 0.80),
        -2: (0.63, 0.60, 0.87), -3: (0.57, 0.54, 0.83), -4: (0.51, 0.48, 0.79), -5: (0.45, 0.42, 0.74),
        -6: (0.39, 0.36, 0.68), -7: (0.34, 0.31, 0.62)}
# the bumper: a mint top row, then a deep plum-navy band (the lower half,
# rows 0 and 1) that carries the lamps
BUMPER = {2: (0.56, 0.90, 0.80), 1: (0.20, 0.16, 0.40), 0: (0.20, 0.16, 0.40)}
LAMPS = [(1.0, 0.95, 0.66), (1.0, 0.80, 0.86)]        # butter and pink, in turn
TRIM = (0.98, 0.86, 0.56)                              # gold, round the dome's foot
GLOW = (0.78, 1.0, 0.92)                               # the mint glow underneath
GLOW_RING = (0.56, 0.90, 0.84)
GLASS = (0.70, 0.74, 0.94)                             # a lilac tint: white glass washes the alien out
GLASS_RIM = (1.0, 1.0, 1.0, 0.85)                      # the white rim at the bubble's foot
GLASS_GLINT = (1.0, 1.0, 1.0, 0.6)                     # the thin glint ring round its very top
GLASS_ALPHA = 0.30                                      # still see-through enough for the alien to read
ALIEN = [(0.62, 0.94, 0.30), (0.72, 0.99, 0.36), (0.80, 1.0, 0.44), (0.88, 1.0, 0.58)]   # by height
EYE = (0.10, 0.04, 0.15)                               # a deep plum: the glass lifts it to the UI ink
CATCHLIGHT = (1.0, 1.0, 1.0)
EYE_WHITE = (0.98, 0.97, 1.0)
CHEEK = (1.0, 0.62, 0.66)
MOUTH = (0.56, 0.24, 0.40)
KNOB = (1.0, 0.74, 0.82)
N_LAMPS = 12

DOME_Z, DOME_R = 5, 12.0


def hull():
    vox = {}
    n = int(R) + 1
    for z, r in PROFILE.items():
        for x in range(-n, n):
            for y in range(-n, n):
                d = math.hypot(x + 0.5, y + 0.5)
                if d > r:
                    continue
                a = math.atan2(y + 0.5, x + 0.5)
                if z in BUMPER:
                    c = BUMPER[z]
                    # round lamps on the bumper: 4 cubes wide, 2 tall
                    k = round(a / (2 * math.pi / N_LAMPS))
                    if z in (0, 1) and abs(a - k * 2 * math.pi / N_LAMPS) * R < 2.1 and d > R - 1.5:
                        c = LAMPS[k % 2]
                elif z == 5 and d > DOME_R - 1.2 and d < DOME_R + 1.0:
                    c = TRIM
                elif z == -7:
                    c = GLOW if d < 4.0 else GLOW_RING
                elif z == -6 and d < 7.5:
                    c = GLOW_RING
                else:
                    c = HULL[z]
                vox[(x, y, z)] = glow(c)
    return vox


def in_dome(x, y, z):
    return z > DOME_Z and (x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - DOME_Z) ** 2 <= DOME_R ** 2


def dome():
    """A glass bubble on the hull's deck: one cube thick, built with its
    inside as solid, so it has only its outer faces. Single-sided, the far
    wall is never drawn and the alien is seen through one layer of glass."""
    vox = {}
    n = int(DOME_R) + 1
    for x in range(-n, n):
        for y in range(-n, n):
            for z in range(DOME_Z + 1, DOME_Z + n + 1):
                d = math.sqrt((x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - DOME_Z) ** 2)
                if DOME_R - 1.0 < d <= DOME_R:
                    # the white rim along the bubble's lowest row, and a thin
                    # glint ring round its top row (a filled cap read as a
                    # tuft). Both are rings round the axis, so they stay put
                    # while the saucer spins.
                    top = DOME_R - (z + 0.5 - DOME_Z) < 1.0
                    c = GLASS_RIM if z == DOME_Z + 1 else (
                        GLASS_GLINT if top and math.hypot(x + 0.5, y + 0.5) > 2.2 else GLASS)
                    vox[(x, y, z)] = glow(c)
    return vox


def alien():
    vox = {}
    # a big round head on the saucer's axis, its chin one cube above the
    # deck (clear of the dome's white foot)
    z0 = DOME_Z + 1
    hz = z0 + 3.5
    for c in vk.ellipsoid(0.0, 0.0, hz, 6.0, 5.0, 3.8):
        if c[2] > z0:
            vox[c] = ALIEN[min(3, max(0, int((c[2] + 0.5 - (hz - 3.8)) / 2.0)))]
    front = vk.front(vox)
    back = {}
    for (x, y, z) in vox:
        back[(x, z)] = max(back.get((x, z), y), y)
    # the face, as (x, z, colour) seen from the camera side (-Y): two big
    # 3x3 plum eyes, each with a white catchlight in its upper left; a
    # little smile; rosy cheeks under the eyes' outer corners
    face = []
    for x0 in (-4, 1):
        for x in range(x0, x0 + 3):
            for z in range(z0 + 3, z0 + 6):
                face.append((x, z, CATCHLIGHT if (x, z) == (x0, z0 + 5) else EYE))
    face += [(-1, z0 + 1, MOUTH), (0, z0 + 1, MOUTH), (-2, z0 + 2, MOUTH), (1, z0 + 2, MOUTH)]
    face += [(x, z0 + 2, CHEEK) for x in (-5, -4, 3, 4)]
    # ... and the same face on the back, turned half round about the axis,
    # (x, y) -> (-1 - x, -1 - y), so the spinning saucer always shows one
    for x, z, c in face:
        for p in ((x, front.get((x, z)), z), (-1 - x, back.get((-1 - x, z)), z)):
            if p[1] is None:
                continue
            # a cube of head over a feature at the edge of the crown (nothing
            # above it): seen from just above, the tops of the far face's
            # eyes showed there as dark dots
            if (p[0], z + 1) not in front:
                vox[(p[0], p[1], z + 1)] = vox[p]
            vox[p] = c
    # two antennae with round knobs, centred on the head's axis, so they
    # look the same from both sides
    top = max(z for (_, _, z) in vox)
    for x in (-2, 1):
        for y in (-1, 0):
            vox[(x, y, top + 1)] = ALIEN[3]
    for x0 in (-3, 1):
        for x in (x0, x0 + 1):
            for y in (-1, 0):
                for z in (top + 2, top + 3):
                    vox[(x, y, z)] = KNOB
    for (x, y, z) in vox:          # all of it inside the glass
        assert math.sqrt((x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5 - DOME_Z) ** 2) < DOME_R - 1.0, (x, y, z)
    return {p: glow(c) for p, c in vox.items()}


def glass_material():
    # single-sided, so the far wall of the bubble doesn't show through the near one
    m = vk.material("VoxelGlass", alpha=GLASS_ALPHA, rough=0.2)
    m.use_backface_culling = True
    return m


def in_game_colours(root):
    """For the review renders: every mesh under root shows its colours as
    the game shows them (unshaded: an emission of the screen colour; the
    glass keeps its transparency)."""
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
        for m in ob.data.materials:
            nt = m.node_tree
            nt.nodes.clear()
            a = nt.nodes.new("ShaderNodeVertexColor")
            a.layer_name = "Col"
            e = nt.nodes.new("ShaderNodeEmission")
            t = nt.nodes.new("ShaderNodeBsdfTransparent")
            mx = nt.nodes.new("ShaderNodeMixShader")
            o = nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(a.outputs["Color"], e.inputs["Color"])
            nt.links.new(a.outputs["Alpha"], mx.inputs["Fac"])
            nt.links.new(t.outputs["BSDF"], mx.inputs[1])
            nt.links.new(e.outputs["Emission"], mx.inputs[2])
            nt.links.new(mx.outputs["Shader"], o.inputs["Surface"])


def ufo(at=(0, 0, 0)):
    root = vk.empty("UFO", at)
    solid = vk.material("Voxel", rough=0.5)
    # no painted face light (faces=None): seen from below or above, the
    # hull's terraces would show it as rings
    vk.build("Hull", hull(), solid, root, faces=None)
    vk.build("Alien", alien(), solid, root, faces=None)
    vk.build("Dome", dome(), glass_material(), root, faces=None, alpha=GLASS_ALPHA, solid=in_dome)
    return root


vk.reset()
root = ufo()
vk.report("ufo", root, budget=8000)
for o in root.children:
    vk.report("  " + o.name, o)
vk.export(os.path.join(MODELS, "ufo_voxel.glb"))

# ---------------------------------------------------------------- review renders
in_game_colours(root)
bee_glb = os.path.join(MODELS, "bee_voxel.glb")
if not os.path.exists(bee_glb):
    bee_glb = "C:/jtmp/bb/before/models/bee_voxel.glb"
try:
    bpy.ops.import_scene.gltf(filepath=bee_glb)
    bee = [b for b in bpy.context.scene.objects if b.name == "Bee"][0]
    bee.scale = (1.0, 1.0, 1.0)
    bee.location = (1.75, 0, -0.1)
    for b in bpy.context.scene.objects:
        if b.name.startswith("XEyes") or b.name.startswith("DeadEyes"):
            b.hide_render = True
except Exception as e:
    print("no bee for scale:", e)
pv = vk.Preview()
pv.shoot(os.path.join(PREVIEW, "ufo_front.png"), (0.0, -1.0, 0.13), (0.45, 0, 0.15), 3.6, 1100, 620)
root.rotation_euler = (0, 0, 0.75)              # as the game mock shows it
pv.shoot(os.path.join(PREVIEW, "ufo_turned.png"), (0.0, -1.0, 0.13), (0, 0, 0.2), 2.4, 800, 620)
root.rotation_euler = (0, 0, 0)
pv.shoot(os.path.join(PREVIEW, "ufo_close.png"), (0.0, -1.0, 0.13), (0, 0, 0.35), 1.2, 800, 620)
root.rotation_euler = (0, 0, math.pi)           # half way round: the alien's other face
pv.shoot(os.path.join(PREVIEW, "ufo_close_back.png"), (0.0, -1.0, 0.13), (0, 0, 0.35), 1.2, 800, 620)
root.rotation_euler = (0, 0, 0)
pv.shoot(os.path.join(PREVIEW, "ufo_3q.png"), (0.5, -1.0, 0.5), (0, 0, 0.15), 2.6, 800, 620)
pv.shoot(os.path.join(PREVIEW, "ufo_under.png"), (0.4, -1.0, -0.6), (0, 0, 0.0), 2.6, 800, 620)
print("DONE voxel ufo")
