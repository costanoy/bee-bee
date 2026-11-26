# Bee Bee — style guide: "Storybook shapes, pop contrast"

The art direction is the audit's *Toybox honey garden*. It takes the storybook
prototype's chunky, rounded, friendly shapes and gives them pop's contrast,
so they read at phone size. Every asset script follows this guide and builds
with the shared kit, `tools/blender/voxel_kit.py` (`import voxel_kit as vk`).

Every number below was measured, not guessed. The palette went through the
game's own look (`kit_check/calib`, see section 9), and the recipe was proved
on a demo bush tile through the game mock (section 8).

---

## 1. Layers and roles

| layer | assets | job | value / saturation |
|---|---|---|---|
| **gameplay** (play plane, z 0) | bee, flowers, hedges | must be read in a glance | highest saturation, darkest darks, ink accents, crisp lit top edges |
| **mid** (z -2 to -7, sky bodies at -6) | clouds, gulls, moon, Jupiter, UFO | depth and mood | lighter, softer, hazed toward the horizon (game-side tint 15-50%) |
| **far** (z -95 and beyond) | backdrops, sun, stars, far cloud banks | place and time of day | low contrast, fogged, no inks, no darks |

- **Danger** has a dark value and a spiky silhouette: the hedge (dark green body, plum ink underside, thorns).
- **Reward** is bright, warm colour with a warm-white sticker rim: the flowers.
- **The hero** is warm honey yellow, with white catchlights and the biggest face on screen: the bee.
- **The UI ink** is `UI_INK = (0.24, 0.13, 0.32)` (`scripts/main.gd:140`, the plum outline of the UI text). In the world it is the ink of the gameplay layer: bee stripes, the eye, antennae, thorn feet, the hedge's underside line. Author it as `INK = (0.22, 0.08, 0.19)`, which shows on screen as UI_INK (section 3).

## 2. Hard rules (numbers)

1. **Grid.** Use one cube size per layer: `vk.VOX = 0.04` on the play plane (z 0 to -10), 0.2 for the backdrops at z -95 and 0.3 for the sun. A new far layer at depth z uses `0.04 × (24 + |z|) / 24` (the camera is about 24 u from the play plane), rounded to a tidy size: 0.08 at about -24, 0.12 at -48, 0.2 at -95.
2. **No scaling, no rotation** of voxel models, by the game or by the script. The game will stop stretching hedge tiles and will lay whole tiles outward from end caps at each gap.
3. **Feature size.** Any feature that must read is at least **3×3 cubes**: an eye 5×6 or bigger, a rose 5×5 or bigger (6-8 across is better), a thorn with a 3-wide foot and 3 cubes tall, a cheek 3×2 or bigger, a stripe 3 wide. One cube is about 4.3 phone px, so design in 2×2 "macro cubes".
4. **Single cubes are accents only**: catchlights, a thorn's tip, rims, one highlight cube on a rose. `vk.islands(vox, 4)` on the design colours (before the gradient) lists the patches smaller than 2×2 that are left over.
5. **No per-cube random jitter on gameplay assets** (`vk.build` defaults to `jitter=0`). Vary colour on purpose instead: per puff, per band or per patch (`vk.patch(p, 2)`). Mid and far layers should vary in patches too, so their faces merge.
6. **Hues.** Gameplay colours stay out of the sky's blue band (the day sky shows at hue 204-210°): no sky-blue anything. The blue flower is periwinkle (246° on screen). The three flowers are clearly **red / lemon yellow / periwinkle**. The bee's honey (45° on screen) stays apart from the lemon flower (57°).
7. **Value targets on screen** (Rec. 709 luma of the sRGB pixels, as the audit measures; `kit_check/luma.py`):
   - Day sky: 0.58-0.64 (the audit's 0.63 is the frame's most common sky colour).
   - Hedge median by day: **0.35-0.40**. Today's hedge is 0.594, storybook 0.618, pop 0.547, diorama 0.592; the kit demo tile is **0.364**.
   - The rest of the gameplay layer stands off the sky by at least 0.15 luma, or by 30° or more of hue at high saturation (red 0.36 and periwinkle 0.51 are both far from the sky's hue).
   - At night (sky 0.15-0.18) the hedge needs the game-side gain of section 10. Without it, its body sits at the sky's own value.
8. **Day, dusk and night.** Check every gameplay colour in all three: the tables below give all three. Roses must stay warm against the peach dusk sky: they show at hue 4° at dusk, the sky at 355°, so they read by saturation and value.
9. **Silhouettes.** Danger is spiky, reward is round with a rim, the hero is round with a face. The hedge body must never be thinner than ±7 cubes round the band centre, and its visual edge stays within 2-5 px of the hitbox (body ±8 to ±9 cubes, thorns to ±11).

## 3. What the renderer does to a colour

The game draws vertex colours lit by a key light and a **blue sky ambient**, plus the sky's specular sheen, glow and Filmic. Measured on flat swatches through the game's own world (`kit_check/calib`):

- **The floor.** By day, authored black shows as about **(0.11, 0.16, 0.22)**: the sky's specular sheen and glow lift every dark. Authored 0.10 in a channel shows as 0.15 (r), 0.18 (g) or 0.24 (b). The darkest a gameplay colour can look by day is a slate (luma about 0.16), so the ink is authored redder and darker than UI_INK (`INK = (0.22, 0.08, 0.19)` shows as (0.24, 0.16, 0.32)).
- **The ceiling.** Authored white shows as **(0.89, 0.93, 1.00)**. Red never goes above 0.89 by day.
- **The blue lift.** Darks turn bluer. The hedge green authored at hue 141° shows at 157° unless its blue is kept low: author greens with **blue at 0.10-0.23**, never 0.25 or more.
- **Dusk and night.** At dusk everything warms (the dusk curve lifts red), and at night it all drops to about half. The flowers and the bee get the night gain (×1.7); the hedges don't, yet (section 10).
- **The model.** A 1D curve per channel predicts the screen colour to within **0.006 by day** and 0.012 at dusk and night, so `kit_check/calib/invert.py` turns a wanted on-screen colour into the value to author.
- **Consequence.** Blender's studio previews (`vk.Preview`) show the authored colours under a white key light. Gameplay assets look darker and warmer there than in the game. Judge colour in the game mock, and judge shape and paint in the previews.
- **If view3d's light, ambient, tonemap or materials change**, these numbers change. Re-run the calibration (section 9) and re-invert the targets: the on-screen columns below are the targets to keep.

## 4. Palette

Authored values (sRGB, written as-is into the `Col` layer) are followed by what the game shows (sRGB, with luma in brackets). All of them were measured in one calibration run: `kit_check/calib/screen_v3.json`, `table_v3.md`.

**The sky behind the play field**, measured in that same run: day (0.28, 0.63, 0.91), luma 0.58; dusk (0.91, 0.63, 0.65), luma 0.69; night (0.13, 0.13, 0.39), luma 0.15. The view3d constants are `SKY_DAY` (0.10, 0.36, 0.74) / (0.27, 0.56, 0.86), `SKY_DUSK` (0.30, 0.26, 0.60) / (0.98, 0.58, 0.46) and `SKY_NIGHT` (0.04, 0.05, 0.16) / (0.14, 0.14, 0.36) (top / horizon).

### Hedge (danger)
A deep, rich green body with a lit yellow-green lip, a plum ink underside, coral-pink roses and plum thorns with warm-white tips. The night column assumes the game-side gain of 1.5 recommended in section 10; the value without it is in brackets.

| name | authored sRGB | day | dusk | night, gain 1.5 |
|---|---|---|---|---|
| H_LIP (top rim, crowns) | 0.49, 0.77, 0.23 | 0.51, 0.80, 0.36 (0.70) | 0.62, 0.70, 0.26 (0.65) | 0.34, 0.62, 0.27 (0.54) (no gain: 0.35) |
| H_LIGHT | 0.25, 0.56, 0.19 | 0.27, 0.63, 0.32 (0.53) | 0.36, 0.53, 0.22 (0.47) | 0.15, 0.45, 0.22 (0.37) (no gain: 0.23) |
| **H_BASE** (the median) | 0.13, 0.45, 0.17 | 0.15, 0.46, 0.27 (0.38) | 0.23, 0.38, 0.19 (0.33) | 0.06, 0.31, 0.16 (0.24) (no gain: 0.15) |
| H_SHADE | 0.07, 0.34, 0.15 | 0.14, 0.35, 0.26 (0.30) | 0.21, 0.29, 0.18 (0.26) | 0.03, 0.22, 0.14 (0.17) (no gain: 0.11) |
| H_DEEP (crevices, low) | 0.03, 0.19, 0.09 | 0.11, 0.24, 0.24 (0.22) | 0.19, 0.20, 0.15 (0.19) | 0.03, 0.13, 0.11 (0.11) (no gain: 0.07) |
| H_INK (underside line) | 0.20, 0.08, 0.17 | 0.23, 0.16, 0.31 (0.19) | 0.31, 0.13, 0.21 (0.17) | 0.11, 0.03, 0.20 (0.06) (no gain: 0.05) |
| R_HI (one cube per rose) | 1.00, 0.77, 0.57 | 0.89, 0.80, 0.74 (0.81) | 0.98, 0.70, 0.58 (0.75) | 0.72, 0.62, 0.67 (0.65) (no gain: 0.42) |
| R_LIGHT (outer petals) | 1.00, 0.54, 0.40 | 0.89, 0.60, 0.56 (0.66) | 0.98, 0.51, 0.42 (0.60) | 0.72, 0.43, 0.47 (0.50) (no gain: 0.32) |
| **R_BASE** (coral pink) | 1.00, 0.37, 0.40 | 0.89, 0.44, 0.44 (0.54) | 0.98, 0.36, 0.32 (0.49) | 0.72, 0.29, 0.35 (0.39) (no gain: 0.25) |
| R_DEEP (swirl) | 0.81, 0.23, 0.21 | 0.78, 0.29, 0.34 (0.40) | 0.88, 0.24, 0.24 (0.37) | 0.60, 0.16, 0.24 (0.26) (no gain: 0.16) |
| R_HEART | 0.61, 0.10, 0.15 | 0.62, 0.18, 0.27 (0.28) | 0.73, 0.14, 0.19 (0.27) | 0.44, 0.06, 0.16 (0.15) (no gain: 0.11) |
| SEPAL (calyx, buds) | 0.38, 0.67, 0.17 | 0.39, 0.72, 0.31 (0.62) | 0.50, 0.62, 0.21 (0.57) | 0.25, 0.55, 0.20 (0.46) (no gain: 0.29) |
| INK (thorn foot) | 0.22, 0.08, 0.19 | 0.24, 0.16, 0.32 (0.19) | 0.33, 0.13, 0.22 (0.18) | 0.13, 0.03, 0.22 (0.07) (no gain: 0.05) |
| THORN (neck) | 0.42, 0.19, 0.25 | 0.44, 0.24, 0.39 (0.29) | 0.55, 0.20, 0.27 (0.28) | 0.28, 0.13, 0.30 (0.17) (no gain: 0.10) |
| THORN_TIP | 1.00, 0.90, 0.64 | 0.89, 0.88, 0.80 (0.88) | 0.98, 0.79, 0.65 (0.82) | 0.72, 0.72, 0.73 (0.72) (no gain: 0.48) |

- **Area shares** that keep the median in 0.35-0.40 are roughly 10% lip, 15% light, 40% base, 25% shade, 5% deep and 5% ink line, plus roses and thorns (an estimate from the swatch values). The demo tile, painted by recipe step 2, measures 0.364 by day, 0.323 at dusk and 0.150 at night without gain.
- **Roses vs the red flower.** The roses are coral-pink and lighter (0.54); the red flower is a true red (0.36) with a warm-white rim and a golden centre. Never paint a rose in the flower reds.
- **Thorns.** A 3-wide INK foot resting on the edge, a 2-wide THORN neck, then a single THORN_TIP, hooked to one side. They poke up from the top edge and down from the bottom edge (2-3 cubes out of the band, tips at ±11 cubes at most). The end caps carry 2-3 thorns pointing into the gap and a rounded end with an ink rim (`vk.rim(side="right"/"left", colour=INK, amount=0.7)` or `vk.outline`).

### Bee (hero)
The night column is what the game shows today, with the bee's night gain of 1.7.

| name | authored sRGB | day | dusk | night, gain 1.7 |
|---|---|---|---|---|
| Y_RIM (top rim) | 1.00, 0.92, 0.45 | 0.89, 0.89, 0.62 (0.87) | 0.98, 0.80, 0.47 (0.82) | 0.79, 0.80, 0.61 (0.78) |
| Y_LIGHT | 1.00, 0.80, 0.23 | 0.89, 0.82, 0.36 (0.80) | 0.98, 0.72, 0.26 (0.74) | 0.79, 0.72, 0.32 (0.70) |
| **Y_BASE** (honey) | 1.00, 0.68, 0.09 | 0.89, 0.73, 0.24 (0.73) | 0.98, 0.63, 0.15 (0.67) | 0.79, 0.62, 0.14 (0.62) |
| Y_SHADE | 0.98, 0.56, 0.08 | 0.88, 0.63, 0.22 (0.65) | 0.97, 0.53, 0.14 (0.60) | 0.78, 0.52, 0.10 (0.55) |
| Y_DEEP (belly, bottom rim) | 0.94, 0.44, 0.08 | 0.86, 0.50, 0.22 (0.56) | 0.95, 0.42, 0.14 (0.51) | 0.76, 0.40, 0.10 (0.46) |
| COLLAR (butter, not cream) | 1.00, 0.80, 0.33 | 0.89, 0.82, 0.47 (0.81) | 0.98, 0.72, 0.35 (0.75) | 0.79, 0.72, 0.45 (0.71) |
| INK (stripes, antennae) | 0.22, 0.08, 0.19 | 0.24, 0.16, 0.32 (0.19) | 0.33, 0.13, 0.22 (0.18) | 0.16, 0.06, 0.25 (0.10) |
| STRIPE_SHEEN (stripe top rim) | 0.38, 0.23, 0.35 | 0.39, 0.29, 0.50 (0.33) | 0.50, 0.24, 0.36 (0.30) | 0.30, 0.20, 0.48 (0.24) |
| STRIPE_DEEP (stripe underside) | 0.13, 0.05, 0.14 | 0.16, 0.15, 0.27 (0.16) | 0.24, 0.13, 0.18 (0.16) | 0.08, 0.06, 0.19 (0.07) |
| KNOB_LIGHT (antenna knob lit cube) | 0.49, 0.32, 0.44 | 0.51, 0.38, 0.60 (0.42) | 0.62, 0.31, 0.46 (0.39) | 0.40, 0.28, 0.60 (0.33) |
| EYE | 0.07, 0.05, 0.09 | 0.13, 0.16, 0.24 (0.16) | 0.21, 0.13, 0.15 (0.15) | 0.06, 0.06, 0.14 (0.06) |
| EYE_GLINT (low plum gloss) | 0.40, 0.28, 0.45 | 0.41, 0.34, 0.62 (0.37) | 0.52, 0.27, 0.47 (0.34) | 0.32, 0.24, 0.61 (0.29) |
| CATCHLIGHT | 1.00, 1.00, 1.00 | 0.89, 0.93, 1.00 | — | — |
| CHEEK (rosy) | 1.00, 0.40, 0.40 | 0.89, 0.46, 0.56 (0.56) | 0.98, 0.38, 0.42 (0.51) | 0.79, 0.36, 0.55 (0.47) |
| CHEEK_LIGHT | 1.00, 0.56, 0.51 | 0.89, 0.63, 0.67 (0.69) | 0.98, 0.53, 0.53 (0.63) | 0.79, 0.52, 0.68 (0.59) |
| MOUTH | 0.49, 0.08, 0.17 | 0.51, 0.15, 0.30 (0.24) | 0.62, 0.13, 0.21 (0.24) | 0.40, 0.06, 0.24 (0.14) |
| WING (alpha about 0.7) | 0.90, 0.97, 1.00 | 0.84, 0.92, 1.00 (0.91) | 0.93, 0.83, 0.89 (0.86) | 0.73, 0.83, 1.00 (0.82) |
| WING_RIM (alpha about 0.9) | 1.00, 0.99, 1.00 | 0.89, 0.93, 1.00 (0.93) | 0.98, 0.84, 0.89 (0.88) | 0.79, 0.84, 1.00 (0.84) |

- **The eye** is big and glossy, on the side the camera sees (the game shows only the side): 5×6 cubes or more of EYE, a **2×2 white catchlight** in its upper front corner, one more white glint cube low on the opposite side, and an EYE_GLINT patch low in the eye.
- **The cheek** is 3×2 or more, below and behind the eye.
- **The body** is chubby and hugs the hitbox (belly at -8 cubes, head top at about +8). The stripes are INK, 3 cubes wide, with a STRIPE_SHEEN top rim.
- **Wings** are near-white with a white rim, so they read against any sky. The hinge must look right at about 0.25 rad.
- **The skins** keep the same values and contrast, with the hue swapped. The silver skin stays unshaded, through glow().

### Flowers (reward)
The petals are soft stickers with a warm-white rim (PAPER) and a bright centre. The night column is what the game shows today, with the flowers' night gain of 1.7. **The flowers were approved by the user as they are, so the hue changes here (periwinkle, a truer red, a lemon yellow) are a proposal for the user.**

| name | authored sRGB | day | dusk | night, gain 1.7 |
|---|---|---|---|---|
| RED_LIGHT | 1.00, 0.38, 0.28 | 0.89, 0.44, 0.42 (0.54) | 0.98, 0.36, 0.31 (0.49) | 0.79, 0.34, 0.39 (0.44) |
| **RED** | 1.00, 0.16, 0.14 | 0.89, 0.22, 0.27 (0.36) | 0.98, 0.18, 0.19 (0.35) | 0.79, 0.13, 0.19 (0.27) |
| RED_DEEP | 0.66, 0.05, 0.11 | 0.66, 0.16, 0.24 (0.28) | 0.77, 0.13, 0.15 (0.27) | 0.55, 0.06, 0.14 (0.17) |
| RED_SEAM | 0.51, 0.05, 0.10 | 0.53, 0.15, 0.24 (0.24) | 0.64, 0.13, 0.15 (0.24) | 0.42, 0.06, 0.14 (0.14) |
| YEL_LIGHT | 1.00, 0.93, 0.35 | 0.89, 0.90, 0.50 (0.87) | 0.98, 0.81, 0.36 (0.81) | 0.79, 0.81, 0.48 (0.78) |
| **YELLOW** (lemon) | 1.00, 0.86, 0.11 | 0.89, 0.86, 0.24 (0.82) | 0.98, 0.76, 0.15 (0.77) | 0.79, 0.76, 0.14 (0.72) |
| YEL_DEEP | 0.98, 0.62, 0.08 | 0.88, 0.68, 0.22 (0.69) | 0.97, 0.58, 0.14 (0.63) | 0.78, 0.57, 0.10 (0.58) |
| YEL_SEAM | 0.84, 0.49, 0.08 | 0.80, 0.56, 0.22 (0.58) | 0.90, 0.47, 0.14 (0.53) | 0.69, 0.45, 0.10 (0.48) |
| PERI_LIGHT | 0.71, 0.62, 1.00 | 0.70, 0.68, 1.00 (0.71) | 0.81, 0.58, 0.89 (0.65) | 0.59, 0.57, 1.00 (0.61) |
| **PERI** (the blue flower) | 0.49, 0.40, 1.00 | 0.51, 0.46, 1.00 (0.51) | 0.62, 0.38, 0.89 (0.47) | 0.40, 0.36, 1.00 (0.42) |
| PERI_DEEP | 0.33, 0.23, 0.72 | 0.34, 0.29, 0.86 (0.34) | 0.44, 0.24, 0.71 (0.31) | 0.25, 0.20, 0.87 (0.26) |
| PERI_SEAM | 0.25, 0.16, 0.55 | 0.27, 0.22, 0.72 (0.26) | 0.36, 0.18, 0.56 (0.24) | 0.19, 0.13, 0.72 (0.18) |
| PAPER (sticker rim) | 1.00, 0.90, 0.64 | 0.89, 0.88, 0.80 (0.88) | 0.98, 0.79, 0.65 (0.82) | 0.79, 0.79, 0.81 (0.79) |
| PAPER_SHADE (rim, lower edge) | 0.94, 0.77, 0.55 | 0.86, 0.80, 0.72 (0.80) | 0.95, 0.70, 0.56 (0.74) | 0.76, 0.69, 0.72 (0.71) |
| CENTRE_LIGHT | 1.00, 0.77, 0.23 | 0.89, 0.80, 0.36 (0.79) | 0.98, 0.70, 0.26 (0.73) | 0.79, 0.70, 0.32 (0.69) |
| CENTRE (red and blue flowers) | 1.00, 0.56, 0.08 | 0.89, 0.63, 0.22 (0.65) | 0.98, 0.53, 0.14 (0.60) | 0.79, 0.52, 0.10 (0.55) |
| CENTRE_RING | 0.94, 0.42, 0.08 | 0.86, 0.48, 0.22 (0.54) | 0.95, 0.40, 0.14 (0.50) | 0.76, 0.38, 0.10 (0.44) |
| COCOA (yellow flower centre) | 0.51, 0.24, 0.11 | 0.53, 0.29, 0.24 (0.34) | 0.64, 0.24, 0.15 (0.31) | 0.42, 0.20, 0.14 (0.24) |
| COCOA_RING | 0.36, 0.16, 0.11 | 0.38, 0.22, 0.24 (0.25) | 0.48, 0.18, 0.15 (0.24) | 0.28, 0.13, 0.14 (0.16) |
| LEAF_LIGHT | 0.51, 0.80, 0.23 | 0.53, 0.82, 0.36 (0.72) | 0.64, 0.72, 0.26 (0.67) | 0.42, 0.72, 0.32 (0.63) |
| LEAF | 0.29, 0.60, 0.17 | 0.31, 0.66, 0.31 (0.56) | 0.40, 0.56, 0.21 (0.50) | 0.22, 0.56, 0.24 (0.46) |
| LEAF_DEEP | 0.12, 0.40, 0.15 | 0.16, 0.46, 0.27 (0.38) | 0.24, 0.38, 0.19 (0.33) | 0.08, 0.36, 0.19 (0.29) |

- **The yellow flower's centre is cocoa, not orange.** An orange centre made it read orange at phone size (the pop prototype's finding).
- **Flower leaves** are brighter than the hedge (LEAF 0.56 against H_BASE 0.38), so a flower never reads as part of a hedge.
- **Burst colours** in flower.gd KINDS should match the petal base on screen: red (0.89, 0.22, 0.27), yellow (0.89, 0.86, 0.24) and periwinkle (0.51, 0.46, 1.0). Today's violet burst for the blue flower doesn't match.

### Clouds (mid layer)
Opaque, as the audit recommends: no alpha streaks and no overdraw. White tops, a lavender belly (never grey), and the back left out. The night column has no gain.

| name | authored sRGB | day | dusk | night |
|---|---|---|---|---|
| C_TOP | 1.00, 0.99, 1.00 | 0.89, 0.93, 1.00 (0.93) | 0.98, 0.84, 0.89 (0.88) | 0.48, 0.53, 0.75 (0.54) |
| C_BODY | 0.94, 0.93, 0.95 | 0.86, 0.90, 0.99 (0.90) | 0.95, 0.81, 0.86 (0.84) | 0.45, 0.50, 0.73 (0.50) |
| C_LAV (shadow lavender) | 0.78, 0.71, 0.87 | 0.76, 0.75, 0.95 (0.77) | 0.86, 0.65, 0.82 (0.71) | 0.36, 0.36, 0.67 (0.39) |
| C_UNDER | 0.66, 0.60, 0.78 | 0.66, 0.66, 0.90 (0.68) | 0.77, 0.56, 0.76 (0.62) | 0.30, 0.31, 0.61 (0.33) |

- **Inside the cloud**, keep the luma range at 0.25 or less (0.93 down to 0.68 by day): soft, never inked.
- **Haze is done game-side**, like the gulls: about 0.15 toward the horizon by day and 0.4 at night (audit). Do not bake it in.

### Mid layer: gulls and sky bodies (not calibrated; check them in the mock)
- **Gull.** Keep today's palette (WHITE 0.98, 0.98, 1.0; GREY 0.62, 0.69, 0.82; DARK 0.20, 0.22, 0.30) and its role as background (the user's request). Optional: a warmer beak (1.00, 0.62, 0.14) and a 1-cube white rim on the wing's leading edge. The game hazes it by 50% (GULL_HAZE).
- **Sky bodies** are drawn unshaded, so their palette goes through glow() (c^2.2) as today. These design colours (before glow) are cooler and less saturated (0.35 or less) than the flowers, so they stop competing with them:
  - Moon: lit (0.94, 0.94, 0.90), mid (0.84, 0.85, 0.90), crater (0.70, 0.71, 0.84), dark limb (0.56, 0.58, 0.76).
  - Jupiter: cream (0.93, 0.87, 0.76), sand (0.88, 0.78, 0.64), tan (0.80, 0.66, 0.54), rust (0.72, 0.50, 0.44), spot (0.78, 0.46, 0.40), poles (0.66, 0.64, 0.74).
  - Sun: body (1.0, 0.93, 0.68), cells (1.0, 0.88, 0.58), lower-right edge (1.0, 0.78, 0.48), rays (1.0, 0.86, 0.50). Use fewer, bigger cells than today's mottling.
  - The game should haze them about 0.2 toward the horizon (audit).

### Far layer: backdrops, far cloud banks
- **Low contrast.** Within one backdrop the luma range is at most 0.2, leaving out the snow and the lit windows. Saturation is 0.45 or less, there are no inks, and nothing is darker than luma 0.35. Paint the light (lit tops, shaded sides) as the backdrops do today. The depth fog and the CITY_HAZE tint do the haze.
- **The base slab colour is fixed** by view3d: (0.40, 0.60, 0.14) for both backdrops. The backdrop's foot must match it.
- **Optional far cloud banks** (z -25 to -50, cubes per rule 1): top (0.86, 0.90, 1.00), belly (0.74, 0.78, 0.94). They must never be brighter than the clouds; let the fog act on them.

## 5. The shading recipe (no shadows, no SSAO in the game)

Paint in this order. Every pass takes a `{cell: colour}` dict and returns a new one (`vk.gradient`, `vk.rim`), so accents painted afterward are left alone.

1. **Shape**, chunky and round. Union round puffs with `vk.blob(puffs, keep=...)`, which gives each cell the normal of its puff, or use `vk.ellipsoid` sets. Rounded clumps should be 6-8 cubes or more; no per-cube noise.
2. **Painted light per puff.** Light each puff as its own ball from `vk.PAINT_LIGHT` (above, a little left and in front, like the game's key). Then snap it to bands, so the colour comes in flat patches that merge:
   `ramp(TONES, vk.posterize(vk.lit(n) * 0.9 - 0.3, 4, -0.6, 0.6))`, with TONES = `[(-0.6, DEEP), (-0.2, SHADE), (0.2, BASE), (0.6, LIGHT)]`. The -0.3 bias puts a straight-on front face (lit 0.5) on BASE: the base is the median.
3. **Vertical gradient** over the whole asset: `vk.gradient(vox, top=+0.08, bottom=-0.20, z0=..., z1=...)`. These are value changes, hue-shifted by `vk.shade`. Pass fixed z0/z1 for tiles and sets (every hedge tile and cap uses the same pair).
4. **Lit top rim.** One cube along the top silhouette: `vk.rim(vox, "top", colour=LIP)` with the asset's lightest tone (H_LIP, Y_RIM), or `k=+0.25` (shade) if it has none.
5. **Dark bottom rim.** One cube along the bottom silhouette. Gameplay assets use ink: on the hedge `vk.rim(vox, "bottom", colour=H_INK)`, on others `colour=INK, amount=0.6`. Mid-layer assets use `k=-0.30` instead (no ink).
6. **Accents** come after the passes, so the passes don't touch them: roses, thorns, eyes, catchlights, cheeks.
7. **Build** with `vk.build(..., ao=vk.AO(), skip=vk.NO_BACK)`, whose defaults are the recipe:
   - **Painted face light** `vk.FACE_LIGHT`: tops +0.10 (crisp lit top edges), undersides -0.16, ±X sides -0.04, fronts 0.
   - **AO only in concave crevices**: strength 0.28, radius 3 cubes, from concavity 0.11 to 0.26, in 4 steps. The measure is how concave the shape is within 3 cubes. Measured on test shapes: balls of radius 4-8, a 10×5×7 ellipsoid and a hedge-like pill stay at or below 0.12, so they never get any (this is what striped the audit's test), while the creases between puffs, under a clump and in a cup reach 0.15-0.28. Use AO only on shapes with real creases (the hedge between puffs, the flower's cup, under the bee's head). Pass `ao=None` on smooth single forms (cloud puffs, the moon).
   - **No jitter.**
   - **Merging.** Same-colour faces merge into watertight polygons with no T-junctions (section 7).

`vk.shade(c, k)` is the palette helper behind all of this. k is the change in value (-0.2 = 20% darker). Lights turn up to 12° toward warm yellow (50°) and shadows toward blue-violet (255°): a yellow's shadow goes orange, a green's goes teal, a red's goes crimson. A blue's lights turn toward violet, never into the sky band. Shadows also gain saturation, and lights that run out of headroom bleach toward white. The turn is kept small because the renderer already cools the darks. `vk.tones(base)` and `vk.hue_ramp(base)` give ramps built on it. Use the palette tables for the main tones and `shade` for the steps in between.

```python
import voxel_kit as vk

TONES = [(-0.6, H_DEEP), (-0.2, H_SHADE), (0.2, H_BASE), (0.6, H_LIGHT)]
shp = vk.blob(PUFFS, keep=lambda x, y, z: 0 <= x < TILE and -8 <= z <= 7 and y <= 2)
vox = {p: vk.ramp(TONES, vk.posterize(vk.lit(n) * 0.9 - 0.3, 4, -0.6, 0.6)) for p, n in shp.items()}
vox = vk.gradient(vox, top=0.08, bottom=-0.20, z0=-8, z1=7)
vox = vk.rim(vox, "top", colour=H_LIP)
vox = vk.rim(vox, "bottom", colour=H_INK)
add_roses(vox); add_thorns(vox)                       # accents last
nb = lambda x, y, z: not (0 <= x < TILE) and (x % TILE, y, z) in vox   # the next tile over
o = vk.build("Hedge", vox, vk.material("Voxel"), root, occluders=nb, skip=vk.NO_BACK, ao=vk.AO())
vk.report("hedge a", root, budget=2000)
```

## 6. Faces, origins, tiles

- **Skip back faces** (`skip=vk.NO_BACK`) on everything that never turns: hedge tiles and caps, flowers (their sway is only ±0.2 rad), clouds, the far cloud banks. Use `vk.NO_BACK_UNDER` for things on the ground (trees, backdrops). Don't skip anything on models that turn: the bee (yaw π, rolls when dead), the gull, the moon, Jupiter, the UFO and the sun's Ball. **Hedge undersides must stay**: rows above the camera's eye show them.
- **Tiles** are periodic in TILE = 24. Keep the shape and paint the same in the shared edge columns, pass the neighbouring tile as `solid=` (no seam walls, where the next tile is always there) or as `occluders=` (AO runs on across the seam while the end wall stays, where a bar may end). Use fixed `z0/z1` for the gradient.
- **Contracts** (origins, node names, sizes, hitboxes) are in the art audit: `C:/jtmp/bb/audit/audit.json`, key "art" → "contracts". Keep the node names view3d looks up: WingPivotL/R, LiveEyes, DeadEyes, Sparkles, Ball, City*, Windows*.

## 7. Building, budgets, checks

**Builders.**
- `vk.build` is for every new asset. It merges same-colour faces and inserts the corners of the neighbouring faces into each merged polygon, so the mesh has **no T-junctions**. T-junctions open hairline cracks of sky in the game: `build_mesh_merged` leaves 3,405 in today's ground and 2,124 in the sun.
- Watertight merging costs some triangles: today's ground cells give 9,154 with `build_mesh_merged` and 14,373 with `vk.build`. `merge="loose"` skips the inserted corners (as `build_mesh_merged` does), for big surfaces with nothing behind them to show through. On a hedge-like tile with AO, merging takes 2,298 triangles (unmerged) down to 1,725.
- `vk.build_mesh` and `vk.build_mesh_merged` are unchanged, for the old scripts.

**Budgets** (triangles, per file; `check_glb.py` knows them by file name):

| asset | budget | today |
|---|---|---|
| hedge tile (hedge_voxel_a/b/c) | ≤ 2000 | 4,624-4,668 |
| hedge end cap (hedge_voxel_cap_*) | ≤ 1000 | — |
| bee, per skin (bee_voxel*.glb, all meshes incl. wings and both eye sets) | ≤ 5000 | 3,852 (queen 4,120, silver 4,180) |
| flower, each | ≤ 2500 | 2,920 |
| clouds a / b / c | ≤ 2000 / 1500 / 1000 | 5,036 / 3,752 / 2,308 |
| gull | ≤ 1500 | 1,644 |
| tree, each | ≤ 2500 | 4.7k-9.4k |
| ground | ≤ 10000 | 9,154 |
| moon / Jupiter / UFO | ≤ 8000 each | 13,838 / 18,202 / 8,362 |
| sun | ≤ 6000 | 11,220 |
| backdrops, each | ≤ 10000 | 9,670 city / 8,446 hills |

**How to check.**
1. **In the make script**, call `vk.report("hedge a", root, budget=2000)` after building. It prints `TRIS ...` and flags OVER. It counts every mesh parented under the objects given, so pass the root.
2. **On the exported files**, run `python tools/blender/check_glb.py <models_dir or files> [--vox 0.2]`. Per file it prints triangles against the budget, the box in cubes, grid alignment, T-junctions, back-facing triangles, materials and the colour range in sRGB, and it exits 1 if a file is over budget or has T-junctions.
   - The vertex count isn't budgeted, but merged builds also keep it low.
   - The wing, eye and overlay meshes show "off grid" on purpose; that is a warning, not a failure.
3. **In the game look**, run the shared mock in an empty project (so nothing touches the game's folder), then the luma check:
   ```
   APPDATA=C:/jtmp/bb/appdata-<you> timeout 900 "$G" --path C:/jtmp/bb/art/kit_check/calib/proj --audio-driver Dummy \
     --script tools/godot/model_mock.gd -- --models=<your models dir> --out=C:/jtmp/bb/art/mock/<asset>
   python C:/jtmp/bb/art/kit_check/luma.py <out>/day.png <out>/dusk.png <out>/night.png
   ```
   The mock falls back to today's models for anything your folder lacks. It uses end caps when `hedge_voxel_cap_l/_r` exist.
4. **Previews.** Use `vk.Preview(game_like=True)` to judge paint and AO without EEVEE's own shadows and AO, which the game doesn't have. Shoot the game view as `direction (0, -1, 0.12)`.

## 8. Proof (kit_check)

- **The old API is unchanged.** `make_voxel_hedge.py`, `make_voxel_cloud.py` and `make_voxel_ground.py`, run with this kit in place of the project's, export **byte-identical GLBs**. All seven files also match `C:/jtmp/bb/before/models`, and the preview PNGs are pixel-identical.
- **The demo.** `kit_check/make_voxel_kit_demo.py` is a rounded bush garland tile built with the recipe and this palette.
  - It has 1,985 triangles (budget 2000) and 0 T-junctions.
  - The step-by-step renders are in `C:/jtmp/bb/art/previews/kit_demo/`: `recipe_steps.png`, `final_close.png`, `final_3q.png` and `final_under.png`.
  - Through the game mock (`C:/jtmp/bb/art/mock/kit_demo/`), its median luma is 0.364 by day against today's 0.594 (`cmp_zoom_day.png` compares today, storybook, pop and the demo).
  - It is a demo only. The hedge agent should make the real hedge: bigger and more roses, end caps.

## 9. Calibration tools (kit_check/calib)

Re-run these whenever view3d's light, ambient, tonemap or materials change. They take about 3 minutes.

1. Write the colours as `[[name, [r, g, b]], ...]`, then build the swatches: `blender ... --python make_swatches.py -- <dir> <palette.json>`.
2. Render them: `APPDATA=... timeout 900 "$G" --path C:/jtmp/bb/art/kit_check/calib/proj --audio-driver Dummy --script calib.gd -- --dir=<dir>`. This draws every swatch with the world of view3d (as copied by game_mock.gd) at day, dusk and night. It also draws variants: no specular, and night gains of 1.3 / 1.5 / 1.7.
3. Read the results:
   - `python analyse.py <dir>` prints every colour.
   - `python table.py <dir>` prints the tables above.
   - `python fit.py <dir>` fits the per-channel curves.
   - `python invert.py <dir> targets.json out.json` turns wanted on-screen colours into authored ones.

## 10. Notes for the game code (for the lead; not done by the kit)

1. **Hedge night gain.** Add the hedge materials to a gain list like `flower_mats`, at about **1.5** at full night. Without it, the hedge body shows at the night sky's own value (0.15 against 0.15). With 1.5 it is 0.24, with its lip at 0.54 and the ink line at 0.06 against the sky's 0.15. A gain of 1.3 gives 0.20.
2. **Optional: darker darks on the gameplay layer.** Set `metallic_specular = 0.0` and `roughness = 1.0` on the hedge, bee and flower materials (in `_use_vertex_colours`, or just for those models). Measured by day, the floor drops away:
   - INK (0.24, 0.16, 0.32) → (0.20, 0.03, 0.23)
   - EYE luma 0.16 → 0.04
   - H_BASE (0.15, 0.46, 0.27) → (0.06, 0.43, 0.15)
   - RED (0.89, 0.22, 0.27) → (0.89, 0.14, 0.15)

   That is exactly "the gameplay layer has the darkest darks", with the mid and far layers keeping the hazy sky sheen. If it is adopted, re-run section 9 for the gameplay colours: their authored values must change.
3. **Light and ambient changes** (the audit's suggestions) move every number in section 4. Re-run section 9 and re-invert the on-screen targets.
4. **From the audit, still to do:** stop the hedge X-stretch (view3d.gd:509) and lay whole tiles from the end caps outward; MSAA 2x; and voxel import flags `generate_lods=false`, `create_shadow_meshes=false`, `ensure_tangents=false`.
