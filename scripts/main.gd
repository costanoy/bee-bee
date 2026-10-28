extends Node2D

# Bee Bee — root game script. Everything (camera, bee, UI, ground/trees,
# obstacles, flowers, clouds) is built here by code rather than laid out by
# hand in the editor — see HANDOFF_Claude_Code.md section 2 for why.

# RESUMING is the 3-2-1 after "Resume": the tree is still frozen, and the
# pause button (or escape, or back) takes it back to the pause menu.
enum State { START, STARTING, PLAYING, PAUSED, DYING, GAMEOVER, RESUMING }

# Moments of a run, for whatever shows or plays something on them. Both come
# from on_flower_collected after the unlock check and the record line, so a
# listener can tell whether the same flower also won a bee
# (bees_won_this_run) or beat the record (score > record_at_run_start).
# `count` is the new score.
signal flower_collected(count: int)
# every MILESTONE_EVERY-th flower; the breather rows come right after it
signal milestone_reached(count: int)

const SCREEN_W := 400.0
# shortest view the layout is made for (16:9); see _ready
const MIN_SCREEN_H := 711.0

# Physics/gameplay constants ported verbatim from reference-prototype.html.
const OBSTACLE_SPACING := 190.0
# TEST — speed bump requested to see how a faster game feels. Previous
# (long-standing) values, to restore if this doesn't stick:
#   SCROLL_BASE := 78.0
#   SCROLL_MAX := 148.0
# TEST — raised again by 15% (was 90.0 / 170.0) after the game came out
# much easier on the phone: the bee had been given 15% more sideways speed
# (bee.gd H_SPEED) while the climb stayed the same, so every row left more
# time to spare. This puts the two back in their old proportion.
const SCROLL_BASE := 103.0
# Prototype's original ramp topped out at 165 (too punishing with mandatory
# flowers + shrinking gaps); 110 was too tame, 135 still felt easy.
# TEST — the top of the ramp eased (was 195.0, with gaps down to 93.6 and
# legs up to 200): at those values the game was reported as impossible, and
# tools/godot/bench_difficulty.gd agreed — even a near-perfect autopilot got
# through a minute of it in only 2 runs of 16. These three numbers (this,
# the narrowest gap in _spawn_row and MAX_LEG_HARD) were picked with that
# bench so the plateau is hard but always possible; see MAX_LEG_HARD.
const SCROLL_MAX := 180.0
# TEST — shortened from 50 so every run gets tense sooner; top speed and
# narrowest gap are unchanged, they're just reached earlier.
const DIFFICULTY_RAMP_TIME := 35.0
# The bees the player can fly. `score` is what a run has to reach to win the
# skin (0 = there from the start); the silver one is the hardest. `size`
# (hitbox and model) and `speed` (sideways speed) are relative to the base
# values in bee.gd, so a skin could fly differently; today every skin is
# purely cosmetic. `glow` draws the model unshaded.
# TEST — a lower ladder (was Rosy 25, Mint 60, Ice 100, Grape 150, Queen 220;
# Silver stays at 300, the hardest, as the user asked). With the old one the
# first bee came out of reach for a new or casual player (the bench's casual
# pilot never got to 25 in 240 runs) and 25 -> 60 was a cliff. Now the first
# one comes in a new player's first session and every step after it asks
# roughly twice as much. Old saves only gain: a record that covers a score
# counts as winning the bee (_bee_unlocked).
const BEE_SKINS := {
	"normal": {"name": "Bee", "score": 0, "model": "bee", "size": 1.0, "speed": 1.0, "glow": false},
	"rosy": {"name": "Rosy Bee", "score": 10, "model": "bee_voxel_rosy", "size": 1.0, "speed": 1.0, "glow": false},
	"mint": {"name": "Mint Bee", "score": 25, "model": "bee_voxel_mint", "size": 1.0, "speed": 1.0, "glow": false},
	"ice": {"name": "Ice Bee", "score": 50, "model": "bee_voxel_ice", "size": 1.0, "speed": 1.0, "glow": false},
	"grape": {"name": "Grape Bee", "score": 100, "model": "bee_voxel_grape", "size": 1.0, "speed": 1.0, "glow": false},
	"queen": {"name": "Queen Bee", "score": 175, "model": "bee_voxel_queen", "size": 1.0, "speed": 1.0, "glow": false},
	"shining": {"name": "Silver Bee", "score": 300, "model": "bee_voxel_shining", "size": 1.0, "speed": 1.0, "glow": true},
}
# menu order: easiest to hardest
const BEE_ORDER := ["normal", "rosy", "mint", "ice", "grape", "queen", "shining"]
const GOLD := Color(1, 0.82, 0.18)
# Widest sideways distance, at max difficulty, between a gap and the next
# flower or between a flower and the next gap (see _spawn_row).
# TEST — 150 (was 200.0). This was what made the top impossible rather than
# hard: a bee climbing at full scroll covers about 220 px a second sideways,
# and a row leaves it half a second per leg. At 200 a near-perfect autopilot
# survived a minute in 2 runs of 16 (13 of 16 even with the scroll back at
# 170); at 150 it survives every time, and one playing like a good player
# (five taps a second, 0.8 s of foresight) lasts a minute in 16 runs of 40
# with the scroll and gap as they are now — it managed none of 30 before.
const MAX_LEG_HARD := 150.0
# TEST — new: a row's legs are also capped by the scroll speed the row will
# be FLOWN at, not only by the difficulty when it is built. A row is built
# about a screen above the top edge and passed 7-9 s later, by when the ramp
# has moved on: a row built 22 s into a run allowed legs of 242 px and was
# flown at 170 px/s, the old "leg 200" set-up the user called impossible,
# right in the middle of the ramp and on the way to the first bees (the
# bench's death rate jumped from 2% to 31% per 10 s between 20 and 40 s).
# Holding leg x scroll to the plateau's (150 x 180) keeps the sideways speed
# a row asks for at what the plateau asks, all through the run; at the top
# of the ramp it gives MAX_LEG_HARD exactly, so the plateau is unchanged.
# Old line, to undo: `var max_leg: float = lerp(SCREEN_W, MAX_LEG_HARD, diff)`
# alone, without the minf() under it in _spawn_row.
const LEG_TIMES_SCROLL := MAX_LEG_HARD * SCROLL_MAX
# How far down the screen (a share of its height from the top edge) the bee
# usually is when it passes a row: what makes the lead from building a row to
# flying it depend on the screen. 0.75 gives back the 7-9 s the audit's probe
# measured on the bench's 711 px screen; a 19.5:9 phone (867 px) has about
# 10 s, so a fixed lead would have underestimated it there.
const ROW_MET_AT := 0.75
# TEST — three flowers in ten come up in the middle of the screen (asked
# for, to make a game that had become very hard a little easier). 0.0 gives
# every flower a place of its own again, as it always was.
const MIDDLE_FLOWER_CHANCE := 0.3
# TEST — new: easy rows. The first INTRO_ROWS rows of every run while the
# player's record is under INTRO_UNTIL_BEST, so a first run doesn't end in
# its first seconds (the bench's beginner lost 67% of runs in under 10 s),
# and BREATHER_ROWS rows right after every MILESTONE_EVERY-th flower, a
# short breath that gives a long run a shape without slowing the scroll.
# They take the middle-flower path: the flower in the middle of the screen
# and a wide gap (EASY_GAP) no more than EASY_GAP_SPREAD from it. Every row
# still holds exactly one flower. To undo: INTRO_ROWS 0 and BREATHER_ROWS 0.
const INTRO_ROWS := 6
const INTRO_UNTIL_BEST := 15
const MILESTONE_EVERY := 25
const BREATHER_ROWS := 2
const EASY_GAP := 185.0
const EASY_GAP_SPREAD := 70.0

# How long after the first flap the camera waits before it starts climbing
# (the bee itself is already flying/falling normally during this pause).
# Replays get the shorter one (TEST, was 1.0 for every run): by then the
# player already knows the controls and just wants back into the action.
const SCROLL_START_DELAY := 1.0
const REPLAY_SCROLL_START_DELAY := 0.5
# TEST — how long the dead bee falls before the game-over panel (was 1.4).
# Still long enough to watch the fall and the death shake land.
const DEATH_FALL_TIME := 0.8
# Short grace window after the first flap where falling off the bottom of
# the (still tightly-framed) cold-start view can't end the run — a rapid
# extra tap right after "Play Again" (e.g. an impatient double-press) could
# otherwise land as a flap with no follow-up, and the bee had barely any
# room to fall before being ruled "off-screen" against the ground-flush
# framing. Obstacle/flower rules are unaffected — nothing is close enough
# to matter this early anyway.
const FALL_DEATH_GRACE := 0.5

# Music sits under whatever else the game plays; the theme itself is
# mastered around -14.5 dBFS RMS, so this only trims it the rest of the way.
const MUSIC_VOLUME_DB := -5.0
# Muting by volume rather than stopping the player keeps the track running
# underneath, so unmuting picks up where the loop got to instead of
# snapping back to the top of the phrase.
const MUSIC_MUTED_DB := -80.0

const SFX_FLAP := preload("res://audio/sfx_flap.wav")
const SFX_COLLECT := preload("res://audio/sfx_collect.wav")
const SFX_HIT := preload("res://audio/sfx_hit.wav")
const SFX_RECORD := preload("res://audio/sfx_record.wav")
const SFX_UI_TAP := preload("res://audio/sfx_ui_tap.wav")
const SFX_NEAR_MISS := preload("res://audio/sfx_near_miss.wav")

# Levels live here rather than baked into the files so the mix can be
# balanced without re-rendering. The flap sits lowest by a wide margin:
# it fires on every single tap, and anything louder takes over the mix
# within one run.
# The flap was -18 while every tap played it twice (see _unhandled_input),
# which is about 3 dB louder than one; it plays once now, so the level moves
# up to keep the wingbeat as loud as it has always been on a phone.
const SFX_FLAP_DB := -15.0
const SFX_COLLECT_DB := -6.0
const SFX_HIT_DB := -3.0
const SFX_RECORD_DB := -5.0
const SFX_UI_DB := -13.0
const SFX_NEAR_MISS_DB := -7.0
# The cues added with the run's notices reuse those same files (no new
# audio, so no new licence to check). Set by measurement (ffmpeg ebur128,
# loudest 400 ms) against the music, which plays at about -17 LUFS: a pickup
# lands at -23 to -24, the near miss at -25, the record jingle at -20 mid-run
# and -16 at the game over, a button's click at -34.
# The countdown's tick is the button click, raised to about -27: clearly
# there over the music, still well under the game's own events.
const SFX_COUNTDOWN_DB := -6.0
# Every MILESTONE_EVERY-th flower: the pickup's own note an octave up, then
# the fifth above it, a short rising call (A5, E6) right after the pickup.
# About -22 and -23, a touch over a pickup and under the record jingle, which
# keeps its own meaning.
const SFX_MILESTONE_DB := -3.0
# [delay after the pickup in s, pitch of sfx_collect]
const MILESTONE_NOTES := [[0.09, 2.0], [0.2, 2.9966]]

# TEST — a "near miss" cue (screen shake + whoosh) when the bee grazes past
# a gap edge within this many px without hitting it, requested to see if
# that close-call thrill makes the game more addictive. Margin is on top
# of the bee's radius, i.e. how much closer than "just barely fits" still counts.
const NEAR_MISS_MARGIN := 8.0
const CAMERA_SHAKE_DURATION := 0.18
# TEST — 2 px (was 4.0): at 4 it was the death shake's (7 px) little brother
# and a close call read like a hit; at 2 it is a shiver, the whoosh carries it.
const CAMERA_SHAKE_MAGNITUDE := 2.0
# Death gets a bigger jolt than a near miss — it's the bigger event of the
# two. Reuses the same SFX_HIT that already plays on every game over; no
# second sound layered on top, just nudged up a touch (below) so it reads
# clearly alongside the new shake instead of blending into the fall.
const DEATH_SHAKE_DURATION := 0.3
const DEATH_SHAKE_MAGNITUDE := 7.0

# Enough voices that a flap, a pickup and a jingle can overlap without
# any of them being cut short.
const SFX_VOICES := 8

# Minor-pentatonic steps (A C D E G), the theme's own key. Each flower in
# a run lands one step higher before wrapping, so a good run reads as a
# rising figure rather than the same blip over and over.
const COLLECT_PITCH_STEPS := [1.0, 1.1892, 1.3348, 1.4983, 1.7818]

# Deep plum used for text outlines and UI backing — the UI's share of the
# art's tinted-ink look.
const UI_INK := Color(0.24, 0.13, 0.32)

# Everything the interface says. The game speaks Portuguese on a device set
# to Portuguese and English everywhere else (see `lang`). The bees keep
# their names in both. "record_word" is spelled in cubes on the record line,
# so it can only use the letters view3d.gd has glyphs for.
const TEXT := {
	"en": {
		"record": "Record: %d",
		"left": "LEFT",
		"right": "RIGHT",
		"game_over": "Game Over",
		"score": "Score",
		"best": "Record",
		"play_again": "Play Again",
		"paused": "Paused",
		"resume": "Resume",
		"restart": "Restart",
		"ad_privacy": "Ad privacy",
		"credits": "Credits",
		"choose_bee": "Choose your bee",
		"back": "Back",
		"selected": "Selected",
		"unlocked": "%s unlocked!",
		"died_hedge": "You hit the roses!",
		"died_flower": "You missed a flower!",
		"died_fall": "You fell!",
		"next_bee": "Next: %s",
		"next_goal": "%d flowers in one run",
		# a locked bee's card says the same as the chip, on two lines
		"goal_count": "%d flowers",
		"goal_count_1": "1 flower",
		"goal_run": "in one run",
		"to_go": "%d to go",
		"to_go_1": "1 to go",
		"use_it": "Use it",
		"previous_record": "Previous record: %d",
		"record_short": "%d short of your record!",
		"record_short_1": "1 short of your record!",
		"record_tied": "You tied your record!",
		"settings": "Settings",
		"music": "Music",
		"sounds": "Sounds",
		"vibration": "Vibration",
		"shake": "Shake",
		"record_word": "RECORD",
		"rule": "Take EVERY flower!",
		"record_beaten": "New record!",
		"milestone": "%d!",
		"phew": "Phew!",
	},
	"pt": {
		"record": "Recorde: %d",
		"left": "ESQUERDA",
		"right": "DIREITA",
		"game_over": "Fim de jogo",
		"score": "Pontos",
		"best": "Recorde",
		"play_again": "Jogar de novo",
		"paused": "Pausado",
		"resume": "Continuar",
		"restart": "Reiniciar",
		"ad_privacy": "Privacidade dos anúncios",
		"credits": "Créditos",
		"choose_bee": "Escolha sua abelha",
		"back": "Voltar",
		"selected": "Em uso",
		"unlocked": "%s liberada!",
		"died_hedge": "Bateu na roseira!",
		"died_flower": "Uma flor ficou para trás!",
		"died_fall": "Caiu!",
		"next_bee": "Próxima: %s",
		"next_goal": "%d flores numa partida",
		"goal_count": "%d flores",
		"goal_count_1": "1 flor",
		"goal_run": "numa partida",
		"to_go": "Faltam %d",
		"to_go_1": "Falta 1",
		"use_it": "Usar agora",
		"previous_record": "Recorde anterior: %d",
		"record_short": "Faltaram %d para o recorde!",
		"record_short_1": "Faltou 1 para o recorde!",
		"record_tied": "Igualou o recorde!",
		"settings": "Ajustes",
		"music": "Música",
		"sounds": "Efeitos",
		"vibration": "Vibração",
		"shake": "Tremor",
		"record_word": "RECORDE",
		"rule": "Pegue TODAS as flores!",
		"record_beaten": "Novo recorde!",
		"milestone": "%d!",
		"phew": "Ufa!",
	},
}
# For the tools that render screenshots in a given language; empty means
# follow the device.
static var forced_lang := ""
# For the tools, which run on a computer: a cut-out this tall, in the game's
# own pixels, as if the game were on a phone that has one. Negative: ask the
# device.
static var forced_cutout := -1.0
# How long a press of "Play Again" stays swallowed while an ad is supposed
# to be opening (see _on_restart_pressed).
const AD_LOCK_MSEC := 3000
# "Play Again" ignores presses for this long after the game-over screen
# comes up. The button appears right where the thumbs were tapping a moment
# before, and a tap already on its way would start the next run (or open an
# ad) before the player had seen the score.
const GAME_OVER_LOCK_MSEC := 450
# Where the top row of the interface sits, from the top edge: the record in
# the middle, the pause button in the corner, the score under them.
const RECORD_Y := 22.0
const PAUSE_Y := 18.0
const SCORE_Y := 92.0
# The most a camera cut-out may push that row down. A phone reporting more
# than this is reporting something else, and the row stays near the top.
const TOP_INSET_MAX := 48.0
# The corner button (the pause button in a run, the gear on the title and
# game-over screens) is a 48 plate, but it takes taps over CORNER_HIT more
# towards the top and right edges: 48 u is only about 43 dp on a 360 dp
# phone, under the 48 dp a finger needs. Growing it only towards the edges
# keeps it out of the right half's flapping.
const CORNER_PLATE := 48.0
const CORNER_HIT := 12.0
# The text links (credits, ad privacy) take taps over this height, though
# their text is about 22 tall: 54 u is 48 dp even on a 360 dp phone.
const LINK_H := 54.0

# The game-over screen: its board and chip are this wide (whole cubes).
const GO_W := 276.0
# The score counts up from 0 in this long, with a tick on its steps (one at
# most every COUNT_UP_GAP), all inside GAME_OVER_LOCK_MSEC, so "Play Again"
# is never kept waiting by it. The tick is the button click, up through the
# pickup's own scale, at about -29 LUFS: under the game's events (a pickup
# is -23 to -24), over the click of a button (-34).
const COUNT_UP_TIME := 0.4
const COUNT_UP_GAP := 0.05
const SFX_COUNT_DB := -8.0
# How the board comes in: a fade, and the board growing from this.
const GO_FADE_IN := 0.18
const GO_GROW_FROM := 0.9
# A run that ends this close under the record says how close ("Faltaram 3
# para o recorde!"): within NEAR_RECORD_MIN flowers, or NEAR_RECORD_SHARE
# of the record if that is more.
const NEAR_RECORD_MIN := 5
const NEAR_RECORD_SHARE := 0.25
# The goal chip's progress bar: this many blocks of two cubes, a cube apart.
const GOAL_BAR_BLOCKS := 12
# On the title, the air between the bee waiting on the grass and the Play
# button over it (_fit_title_to_bee).
const TITLE_BEE_CLEAR := 8.0

# The run's one slot for messages (_notify): a plate in the top row, where
# the record readout is, which it covers while it is up. Everything a run
# announces goes through it, one at a time, so nothing ever covers the top
# of the play area, where the next hedges come in (the old bee banner, a
# 300x72 plate at y 172, hid about 650 px of rows at top speed). Kept
# clear of the pause button in the corner.
const NOTICE_Y := 13.0
const NOTICE_H := 42.0
const NOTICE_MAX_W := 264.0
const NOTICE_PAD := 9.0
const NOTICE_GAP := 6.0
const NOTICE_ICON := 34.0
const NOTICE_FONT := 26
const NOTICE_IN := 0.18
const NOTICE_OUT := 0.2
# What the slot can say, most important first. A notice at least as
# important as the one up takes its place at once; a less important one
# waits its turn, and is dropped if it has waited longer than `stale` (a
# "25!" shown two seconds late is about a moment gone). `hold` is how long
# it stays up. The bee's was a 4 s banner (0.25 in, 3.2 up, 0.6 out).
const NOTICE_KINDS := {
	"bee": {"priority": 3, "hold": 2.2, "stale": 6.0},
	"milestone": {"priority": 2, "hold": 0.5, "stale": 1.0},
}
# The rule a new player doesn't expect, on a plate in the same slot: on the
# first run, again on a run after one lost to a missed flower, and on every
# run while the record is under RULE_UNTIL_BEST (a player who never got
# that far may have missed it). It stays until the run's RULE_UNTIL_FLOWER-th
# flower; a run that ends before then shows it again next time.
const RULE_UNTIL_FLOWER := 3
const RULE_UNTIL_BEST := 3
# "Resume" counts 3-2-1 before the world moves again, this long a step.
const COUNTDOWN_STEP := 0.45
# The digits of the score are big, and a flower (or the bee) going behind
# them was hidden: they fade to this while one is there.
const SCORE_BEHIND_ALPHA := 0.4
# A near miss says so beside the bee ("Ufa!"), rising this far as it fades.
const PHEW_RISE := 26.0
const PHEW_TIME := 0.5
# Buzz lengths, in ms, for the moments that had none.
const MILESTONE_BUZZ_MS := 50
const NEAR_MISS_BUZZ_MS := 10

# Icons are drawn as pixel grids rather than imported art, so they match
# the game's own resolution instead of being scaled-down smooth shapes.
const ICON_PAUSE := [
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
]
const ICON_NOTE := [
	"...XXXXXXX.",
	"...XXXXXXX.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	".XXX...XXX.",
	"XXXXX.XXXXX",
	"XXXXX.XXXXX",
	".XXX...XXX.",
]
const ICON_SOUND := [
	"....X......",
	"...XX..X...",
	"..XXX...X..",
	"XXXXX.X..X.",
	"XXXXX..X.X.",
	"XXXXX..X.X.",
	"XXXXX..X.X.",
	"XXXXX.X..X.",
	"..XXX...X..",
	"...XX..X...",
	"....X......",
]
const ICON_PLAY := [
	"XX.......",
	"XXXX.....",
	"XXXXXX...",
	"XXXXXXXX.",
	"XXXXXXXXX",
	"XXXXXXXX.",
	"XXXXXX...",
	"XXXX.....",
	"XX.......",
]
# points right; the left one is the same rows mirrored
const ICON_ARROW := [
	"......X....",
	"......XX...",
	"XXXXXXXXX..",
	"XXXXXXXXXX.",
	"XXXXXXXXXXX",
	"XXXXXXXXXX.",
	"XXXXXXXXX..",
	"......XX...",
	"......X....",
]
const ICON_VIBRATE := [
	"...XXXXX...",
	"...X...X...",
	"...X...X...",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"...X...X...",
	"...X.X.X...",
	"...XXXXX...",
]
const ICON_TROPHY := [
	"XXXXXXXXXXX",
	"X.XXXXXXX.X",
	"X.XXXXXXX.X",
	".XXXXXXXXX.",
	"..XXXXXXX..",
	"...XXXXX...",
	"....XXX....",
	".....X.....",
	".....X.....",
	"...XXXXX...",
	"..XXXXXXX..",
]
const ICON_SLASH := [
	"X..........",
	"XX.........",
	".XX........",
	"..XX.......",
	"...XX......",
	"....XX.....",
	".....XX....",
	"......XX...",
	".......XX..",
	"........XX.",
	".........XX",
]
# the settings (the corner of the title and game-over screens)
const ICON_GEAR := [
	"....XXX....",
	".XX.XXX.XX.",
	".XXXXXXXXX.",
	"..XXXXXXX..",
	"XXXX...XXXX",
	"XXXX...XXXX",
	"XXXX...XXXX",
	"..XXXXXXX..",
	".XXXXXXXXX.",
	".XX.XXX.XX.",
	"....XXX....",
]
# the screen shake switch: a picture in a frame, with the marks of a jolt
const ICON_SHAKE := [
	"..XXXXXXX..",
	"..X.....X..",
	"X.X.....X.X",
	"X.X..X..X.X",
	"..X.XXX.X..",
	"X.XXXXXXX.X",
	"X.XXXXXXX.X",
	"..XXXXXXX..",
]
# over a locked bee in the bee menu
const ICON_LOCK := [
	"..XXX..",
	".XX.XX.",
	".X...X.",
	"XXXXXXX",
	"XXX.XXX",
	"XXX.XXX",
	"XXXXXXX",
]
# The settings' switches, in their order on screen: the save's setting each
# one flips, its icon and its caption.
const TOGGLES := [
	{"id": "music", "icon": ICON_NOTE, "text": "music"},
	{"id": "sound", "icon": ICON_SOUND, "text": "sounds"},
	{"id": "vibration", "icon": ICON_VIBRATE, "text": "vibration"},
	{"id": "shake", "icon": ICON_SHAKE, "text": "shake"},
]
const TOGGLE_SIDE := 57.0
const TOGGLE_GAP := 12.0
# A locked bee is a flat silhouette in this colour (it was the icon tinted
# almost black, 1.6:1 on the card, and tinted rather than flat: the queen
# showed brown, the grape purple). About 3.4:1 on the card's face.
const SILHOUETTE := Color(0.58, 0.48, 0.74)
# The flower, as the game's own five-petal one seen from the front: P petal,
# L the lit rim of the upper petals, C the cream centre, c its golden dot.
const ICON_FLOWER := [
	"...LLL...",
	"..LPPPL..",
	"LL.PPP.LL",
	"LPPPPPPPL",
	"PPPCCCPPP",
	".PPCcCPP.",
	"..PCCCP..",
	".PPP.PPP.",
	".PP...PP.",
]
# [petal, lit rim] per flower kind, from tools/blender/make_voxel_flower.py
const FLOWER_ICON_COLORS := {
	"red": [Color(1.0, 0.20, 0.26), Color(1.0, 0.52, 0.52)],
	"yellow": [Color(1.0, 0.88, 0.10), Color(1.0, 0.97, 0.55)],
	"blue": [Color(0.30, 0.52, 1.0), Color(0.62, 0.80, 1.0)],
}
const FLOWER_ICON_CENTRE := [Color(1.0, 0.70, 0.14), Color(0.86, 0.42, 0.06)]

const ObstacleScript := preload("res://scripts/obstacle.gd")
const FlowerScript := preload("res://scripts/flower.gd")
const CloudScript := preload("res://scripts/cloud.gd")
const SeagullScript := preload("res://scripts/seagull.gd")
const SkyScript := preload("res://scripts/sky.gd")
const AdsScript := preload("res://scripts/ads.gd")
const LeaderboardScript := preload("res://scripts/leaderboard.gd")
const View3DScript := preload("res://scripts/view3d.gd")
const VoxelPlate := preload("res://scripts/voxel_plate.gd")
const VoxelLogo := preload("res://scripts/voxel_logo.gd")
const Licenses := preload("res://scripts/licenses.gd")
# One cube of the interface's grid, in UI pixels: every plate is a whole
# number of these, about two of the world's cubes across.
const UI_CELL := 3.0
const BeeScript := preload("res://scripts/bee.gd")

# How far below the grass line (world y = 0, where the bee stands) the
# cold-start view reaches: the strip of earth under the grass.
const GROUND_DEPTH := 19.9

var state: State = State.START
var lang := "en"
# The stretch mode is keep_width: the world is always 400 wide, and a phone
# taller than 1:2 (nearly all of them) shows more sky instead of black bars.
# So the visible height is only known at runtime.
var screen_h := 800.0
var top_inset := 0.0
var world_moving := false
var scrolling_started := false
var launch_timer := 0.0
var time_since_first_flap := 0.0
var has_finished_a_run := false
var has_tapped_once := false
var hint_alpha := 0.0

var elapsed := 0.0
var camera_y := 0.0
var camera_shake_time := 0.0
var camera_shake_total := 0.0
var camera_shake_magnitude := 0.0
var highest_spawn_y := 0.0
var last_gap_x := 0.0
var rows_spawned := 0
# Set when a run is laid out (_reset_to_ground_scene), for the whole run:
# `first_run` while the player has never flown (the tutorial's run; it stays
# true after the first flap saves seen_tutorial), `new_player_run` while the
# record is under INTRO_UNTIL_BEST (the run opens with intro rows).
var first_run := false
var new_player_run := false
var score := 0
var dying_timer := 0.0
# What ended the run ("hedge", "flower" or "fall"); the game-over screen says it.
var death_cause := ""
# The record as it stood when the run began: the run may save a new one
# before it ends (on a pause), and the game-over screen still has to know
# it was beaten.
var record_at_run_start := 0
var bees_won_this_run: Array = []
# Marks the height of the flower that breaks the record; view3d.gd draws it.
var record_line: Node2D
var record_word_on_left := true

var obstacles: Array = []
var flowers: Array = []
var clouds: Array = []
var seagulls: Array = []
var celestials: Array = []

var bee: CharacterBody2D
var music: AudioStreamPlayer
var ads: Node
var leaderboard: Node
# "Play Again" was pressed and an ad is up: the run starts when it closes.
var restart_after_ad := false
var restart_lock_msec := 0
var game_over_msec := 0
var sfx_pool: Array[AudioStreamPlayer] = []
var collect_step := 0
var physics_ticks_since_reset := 0
var camera: Camera2D
var sky: Node
# Bumped every time a fresh start scene is built; view3d.gd rebuilds the
# ground, trees and far backdrop whenever it changes.
var scenery_id := 0

var ui_font: Font

var score_label: Label
var record_label: Label
var direction_hint: Control
var start_screen: Control
var play_button: Button
var game_over_screen: Control
# The game-over board (go_board, in go_stack with the goal chip): the title,
# what ended the run, the score and the record, and a line about the record.
var go_stack: Control
var go_board: Control
var go_title: Label
var go_rule: ColorRect
var score_caption: Label
var best_caption: Label
var col_divider: ColorRect
var final_score_label: Label
var final_best_label: Label
var death_label: Label
var record_note: Label
# The chip under the board: a Button, which only takes taps when it offers to
# put on a bee won in the run (goal_equip, that bee's id).
var goal_chip: Button
var goal_plate: Control
var goal_icon: TextureRect
var goal_title: Label
var goal_hint: Label
var goal_bar: Control
var goal_left: Label
var goal_go: Control
var goal_equip := ""
var score_pop: Tween
var restart_button: Button
# What the game over's lock holds back, dimmed until it lets go.
var go_bottom: Array[Button] = []
var go_ready := false
var go_enter: Tween
var count_tween: Tween
var count_shown := 0
var count_ticks := 0
var count_last_tick := 0.0
# The "New record!" caption over the score, on a board that beat it.
var new_record_badge: Label
var record_pulse: Tween
var pause_button: Button
var pause_screen: Control
# The settings panel the gear opens from the title and the game over. Its
# switches and the pause menu's are built by one function (_build_toggle_row)
# and kept in step by toggle_views: setting id -> one entry per copy. The
# names below are the pause menu's copy.
var settings_screen: Control
var settings_privacy: Button
var settings_credits: Button
var gear_buttons: Array[Button] = []
var toggle_views := {}
var music_note: Control
var music_slash: Control
var sound_icon: Control
var sound_slash: Control
var vibrate_icon: Control
var vibrate_slash: Control
var shake_icon: Control
var shake_slash: Control
var privacy_button: Button
var credits_button: Button
var credits_screen: Control
var credits_title: Label
var credits_scroll: ScrollContainer
var credits_box: VBoxContainer
var silhouette_mat: ShaderMaterial
var view3d: Node3D
var applied_bee_skin := ""
var bee_menu: Control
# The run's notice slot (_notify): one plate, its content rebuilt for each
# notice. `notice_now` is the entry it shows ({} when the record readout is
# uncovered), `notice_queue` the ones waiting their turn.
var notice: Control
var notice_icon: TextureRect
var notice_flowers: Array[Control] = []
var notice_title: Label
var notice_now := {}
var notice_queue: Array = []
var notice_tween: Tween
# The rule plate (RULE_UNTIL_FLOWER): due for the next run, and up in this one.
var rule_due := false
var rule_on := false
# The record readout turns into "New record!" once the run passes it; when
# that happens under a notice, its little jump waits for the notice to go.
var record_pop_due := false
var record_pop: Tween
var record_fade: Tween
# The score at which this run last won a bee, and last played the record
# jingle, so a milestone on the same flower doesn't pile its own on top.
var bee_won_at := -1
var jingle_at := -1
var countdown_label: Label
var countdown_tween: Tween
var countdown_ticks := 0
var phew_label: Label
var phew_tween: Tween
# Points at the flower a run was lost to, at the bottom edge, from the fall
# until the next run.
var lost_marker: Control
var lost_blink := 0.0
var hint_line: Control
var title_row: Array[Control] = []    # the title's Play button and the buttons beside it
var bee_cards := {}                    # skin id -> its card's nodes in the bee menu
var bee_button_icons: Array[TextureRect] = []


func _ready() -> void:
	# The layout needs a screen at least 16:9 tall. On anything squatter (a
	# tablet, a foldable opened flat) keep_width would leave too little
	# height for the menus and for reading the next row, so there the game
	# keeps a 16:9 column in the middle with bars at the sides instead.
	var window := get_window()
	if float(window.size.y) / maxf(1.0, window.size.x) < MIN_SCREEN_H / SCREEN_W:
		window.content_scale_size = Vector2i(int(SCREEN_W), int(MIN_SCREEN_H))
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	screen_h = get_viewport_rect().size.y
	if TEXT.has(forced_lang):
		lang = forced_lang
	else:
		lang = "pt" if OS.get_locale_language() == "pt" else "en"

	# Jersey 10 (SIL OFL 1.1, see fonts/Jersey10-OFL.txt): a chunky pixel
	# face, so the text is made of squares like the voxel world behind it.
	ui_font = load("res://fonts/Jersey10-Regular.ttf")

	sky = SkyScript.new()
	add_child(sky)
	sky.moon_spawn_requested.connect(_on_moon_spawn_requested)
	sky.jupiter_spawn_requested.connect(_on_jupiter_spawn_requested)
	sky.ship_spawn_requested.connect(_on_ship_spawn_requested)
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	camera.enabled = true
	camera.make_current()

	bee = CharacterBody2D.new()
	bee.set_script(BeeScript)
	add_child(bee)

	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		# UI taps fire from the pause menu while the tree is frozen, so the
		# pool has to keep running through a pause just like the music does.
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		sfx_pool.append(voice)

	leaderboard = LeaderboardScript.new()
	add_child(leaderboard)
	leaderboard.start()

	_build_ui()

	# One continuous loop across menu, run and game over — restarting it per
	# run would clip the phrase mid-bar on every death. Nothing here repeats
	# it in code: the WAV is imported with loop mode Forward, so the repeat
	# is gapless inside the audio server.
	music = AudioStreamPlayer.new()
	music.stream = preload("res://audio/music_theme.wav")
	# Pausing the game freezes the whole tree, so the player has to opt out
	# of that or the track would cut off the moment the menu opens.
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	# The audio server mixes on its own thread, so a player who turned the
	# music off would hear a buffer of it at full volume if the mute came
	# after play() (on Android, ads.start() below sits in between).
	_apply_music_mute()
	music.play()

	ads = AdsScript.new()
	add_child(ads)
	# an ad plays its own sound, and the music would run on underneath it
	ads.ad_opened.connect(func(): music.stream_paused = true)
	ads.ad_closed.connect(_on_ad_closed)
	ads.start()

	flower_collected.connect(_on_flower_count)
	milestone_reached.connect(_on_milestone)
	rule_due = SaveData.best_score < RULE_UNTIL_BEST
	_reset_to_ground_scene()

	# Everything the player sees of the world is drawn in 3D by view3d.gd,
	# which mirrors this node's 2D simulation every frame.
	view3d = View3DScript.new()
	add_child(view3d)
	view3d.setup(self)
	_apply_bee_skin()
	_fit_title_to_bee()

	state = State.START
	start_screen.visible = true
	start_screen.modulate.a = 1.0
	game_over_screen.visible = false
	# The title screen keeps the record (worth seeing before a run) but not
	# the live score, a "0" that otherwise sits right on top of the logo.
	score_label.visible = false
	# The tutorial arrows belong to the ground scene, not the title — on
	# top of it they cut straight through the logo and the Play button.
	# They fade in with the title's fade-out instead.
	direction_hint.visible = false


func _t(key: String) -> String:
	return TEXT[lang][key]


# A text with a number in it, in the singular when the number is 1 and the
# table has a "<key>_1" for it: "Falta 1" / "Faltam 2", "1 flor" / "2 flores".
func _tn(key: String, n: int) -> String:
	if n == 1 and TEXT[lang].has(key + "_1"):
		return TEXT[lang][key + "_1"]
	return TEXT[lang][key] % n


# The game draws edge to edge, under the phone's camera cut-out, and the top
# row of the interface is exactly where cut-outs are: the record in the
# middle of the top edge, the pause button in its corner. This is how far
# down the row has to go to clear one, in the game's own pixels. The row
# already keeps PAUSE_Y from the edge, so only a cut-out taller than that
# moves it, and a screen without one leaves everything where it was.
func _cutout_shift() -> float:
	var cutout := forced_cutout
	if cutout < 0.0:
		# Only a phone can say. On a computer the "safe area" is the desktop
		# minus its taskbar, which has nothing to do with this window.
		if not OS.has_feature("mobile"):
			return 0.0
		var px_per_unit := float(get_window().size.y) / maxf(1.0, screen_h)
		cutout = float(DisplayServer.get_display_safe_area().position.y) / maxf(0.01, px_per_unit)
	return clampf(cutout - PAUSE_Y, 0.0, TOP_INSET_MAX)


func _apply_top_inset() -> void:
	top_inset = _cutout_shift()
	record_label.position.y = RECORD_Y + top_inset
	score_label.position.y = SCORE_Y + top_inset
	# (the buttons' tap areas reach CORNER_HIT above their plates)
	pause_button.position.y = PAUSE_Y + top_inset - CORNER_HIT
	for gear in gear_buttons:
		gear.position.y = pause_button.position.y
	# the tutorial's centre line starts under the score, wherever that went
	hint_line.position.y = top_inset
	if notice.visible and not (notice_tween != null and notice_tween.is_running()):
		notice.position.y = NOTICE_Y + top_inset


func _notification(what: int) -> void:
	match what:
		# A call, the home button or the notification shade pulled down
		# mid-run would otherwise leave the bee falling with nobody at the
		# controls, or dropped into a fall the moment the app comes back.
		# (and in the middle of a resume's countdown, which would otherwise
		# finish and drop the bee into a run with nobody watching)
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if state == State.PLAYING or state == State.RESUMING:
				_on_pause_pressed()
		# quit_on_go_back is off in project.godot, so back no longer kills
		# the app mid-run: it pauses a run, resumes a paused one, and only
		# leaves from the screens where there's nothing to lose.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match state:
				State.PLAYING, State.RESUMING:
					_on_pause_pressed()
				State.PAUSED:
					if credits_screen.visible:
						credits_screen.visible = false
					else:
						_on_resume_pressed()
				State.START, State.GAMEOVER:
					if not _close_top_menu():
						get_tree().quit()


# Back (or escape) on the title or the game over closes whatever is open
# over it, the top one first: the credits over the settings, the settings,
# the bee menu. False when nothing was.
func _close_top_menu() -> bool:
	if credits_screen.visible:
		credits_screen.visible = false
	elif settings_screen.visible:
		_on_settings_closed()
	elif bee_menu.visible:
		_on_bee_menu_closed()
	else:
		return false
	return true


# ------------------------------------------------------------------
# World (re)generation
# ------------------------------------------------------------------

func _clear_world() -> void:
	for o in obstacles:
		o.queue_free()
	for f in flowers:
		# queue_free() is deferred to end-of-frame — stop it detecting the
		# bee in the meantime.
		f.monitoring = false
		f.queue_free()
	for c in clouds:
		c.queue_free()
	for g in seagulls:
		g.queue_free()
	for c in celestials:
		c.queue_free()
	obstacles.clear()
	flowers.clear()
	clouds.clear()
	seagulls.clear()
	celestials.clear()
	if record_line:
		record_line.queue_free()
		record_line = null


func _reset_to_ground_scene() -> void:
	# Builds a fresh grounded start: bee resting on the ground, world
	# regenerated. Used both at app cold-start and on every "Play Again"
	# after a game over. Per spec 4.8, the one thing this must NOT do is
	# re-randomize the world that's already visible behind the start screen
	# the very first time the player presses Play — callers handle that by
	# only calling this once before that first press.
	_clear_world()
	sky.reset_run()
	collect_step = 0
	physics_ticks_since_reset = 0

	scenery_id += 1

	_apply_bee_skin()
	# the grass line is world y = 0
	bee.reset_bee(Vector2(SCREEN_W / 2.0, -bee.radius))
	world_moving = false
	scrolling_started = false
	launch_timer = 0.0
	time_since_first_flap = 0.0
	camera_shake_time = 0.0

	# Frame the cold-start camera so the bottom of the ground sits flush with
	# the bottom of the screen.
	camera_y = GROUND_DEPTH - screen_h
	camera.position = Vector2(0.0, camera_y)

	elapsed = 0.0
	score = 0
	dying_timer = 0.0
	death_cause = ""
	record_at_run_start = SaveData.best_score
	bees_won_this_run = []
	# obstacles start comfortably above the ground/trees so they don't
	# overlap the cold-start framing.
	highest_spawn_y = -200.0
	last_gap_x = SCREEN_W / 2.0   # the bee starts centred on the ground
	rows_spawned = 0
	first_run = not SaveData.seen_tutorial
	new_player_run = SaveData.best_score < INTRO_UNTIL_BEST

	has_tapped_once = SaveData.seen_tutorial
	hint_alpha = 0.0 if SaveData.seen_tutorial else 1.0
	direction_hint.modulate.a = hint_alpha
	direction_hint.visible = hint_alpha > 0.0

	_update_score_label()
	record_label.text = _t("record") % SaveData.best_score
	record_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	record_pop_due = false
	score_label.modulate.a = 1.0
	bee_won_at = -1
	jingle_at = -1
	_clear_notices()
	if phew_tween != null and phew_tween.is_valid():
		phew_tween.kill()
	phew_label.visible = false
	lost_marker.visible = false
	# the run the tutorial is for always gets the rule; it is put up when the
	# run starts (_show_rule_if_due), not behind the title screen
	if first_run:
		rule_due = true

	for i in range(6):
		_spawn_row()


func _spawn_row() -> void:
	var y: float = highest_spawn_y - OBSTACLE_SPACING
	highest_spawn_y = y

	var diff: float = _difficulty()
	# TEST — 6.4 px narrower at every difficulty (was 175.0 - diff * 75.0).
	# The bee's hitbox went from 16 to 12.8 px in radius, which in effect
	# widened every gap by that much; this gives back the old free space
	# around the bee.
	# TEST — narrowest gap 97 (was 93.6, from `diff * 75.0`), eased together
	# with the top scroll speed; see SCROLL_MAX.
	var gap_width: float = 168.6 - diff * 71.6
	var margin: float = gap_width / 2.0 + 24.0
	var flower_clear: float = gap_width / 2.0 + 20.0

	# The climb goes previous gap -> this row's flower -> this row's gap, and
	# at top speed there's only ~0.55s per leg. Fully random placement could
	# put a flower on the far side of both gaps, a sideways run past what the
	# bee can physically make in that time (~1 row in 35 at max speed), so
	# each leg is capped, tightening with difficulty. (The figures above
	# date from a slower game; the cap itself is now set by measurement, see
	# MAX_LEG_HARD.)
	var max_leg: float = lerp(SCREEN_W, MAX_LEG_HARD, diff)
	# TEST — and by the speed the row will be flown at (see LEG_TIMES_SCROLL)
	max_leg = minf(max_leg, LEG_TIMES_SCROLL / _scroll_speed_when_met(y))
	var gap_x: float
	var fx: float
	# this row's flower is the one that takes the score to `row`
	var row: int = rows_spawned + 1
	if _is_easy_row(row):
		# TEST — intro and breather rows (see INTRO_ROWS): a wide gap near the
		# middle, the flower in the middle, within a short hop of either gap.
		gap_width = maxf(gap_width, EASY_GAP)
		gap_x = SCREEN_W / 2.0 + randf_range(-EASY_GAP_SPREAD, EASY_GAP_SPREAD)
		fx = SCREEN_W / 2.0
	elif randf() < MIDDLE_FLOWER_CHANCE:
		# The flower in the middle of the screen and the gap wherever it
		# falls, even right over the flower: these are the easy rows. There
		# is no leg to check either, the middle being within reach of any gap.
		gap_x = margin + randf() * (SCREEN_W - margin * 2.0)
		fx = SCREEN_W / 2.0
	else:
		for _attempt in 64:
			gap_x = margin + randf() * (SCREEN_W - margin * 2.0)
			fx = 30.0 + randf() * (SCREEN_W - 60.0)
			if abs(fx - gap_x) < flower_clear:
				continue
			if abs(fx - last_gap_x) <= max_leg and abs(fx - gap_x) <= max_leg:
				break
		if abs(fx - gap_x) < flower_clear:
			fx = gap_x - flower_clear if gap_x - flower_clear >= 30.0 else gap_x + flower_clear
	last_gap_x = gap_x

	var obstacle := Node2D.new()
	obstacle.set_script(ObstacleScript)
	obstacle.position = Vector2(0, y)
	add_child(obstacle)
	obstacle.setup(gap_x, gap_width)
	obstacles.append(obstacle)

	var fy: float = y + OBSTACLE_SPACING / 2.0 + (randf() * 40.0 - 20.0)

	var flower := Area2D.new()
	flower.set_script(FlowerScript)
	flower.position = Vector2(fx, fy)
	add_child(flower)
	flower.setup()
	flowers.append(flower)

	# Every row carries exactly one mandatory flower, collected in order, so
	# row N's flower is always the one that takes the score to N — the row
	# numbered best+1 holds the flower that breaks the record.
	rows_spawned += 1
	if SaveData.best_score > 0 and rows_spawned == SaveData.best_score + 1:
		_spawn_record_line(fy, fx)

	# Clouds keep appearing through the night, just less often once the sky
	# has started turning.
	var cloud_chance: float = 0.85 if score < 50 else 0.35
	if randf() < cloud_chance:
		var cloud := Node2D.new()
		cloud.set_script(CloudScript)
		cloud.position = Vector2(randf() * SCREEN_W, y - randf() * 60.0)
		add_child(cloud)
		cloud.setup()
		clouds.append(cloud)

	if score < 75 and randf() < 0.15:
		var gull := Node2D.new()
		gull.set_script(SeagullScript)
		gull.position = Vector2(randf() * SCREEN_W, y - randf() * 80.0)
		add_child(gull)
		gull.setup()
		seagulls.append(gull)


# The scroll speed by the time the bee meets a row whose hedge is at `row_y`:
# once the camera has climbed until that hedge is ROW_MET_AT of the way down
# the screen. The ramp is a steady acceleration (SCROLL_BASE to SCROLL_MAX in
# DIFFICULTY_RAMP_TIME), so over a climb d the speed goes from v0 to
# sqrt(v0^2 + 2 a d).
func _scroll_speed_when_met(row_y: float) -> float:
	var v0: float = _current_scroll_speed()
	var climb: float = maxf(0.0, camera_y + screen_h * ROW_MET_AT - row_y)
	var accel: float = (SCROLL_MAX - SCROLL_BASE) / DIFFICULTY_RAMP_TIME
	return minf(SCROLL_MAX, sqrt(v0 * v0 + 2.0 * accel * climb))


# Rows numbered from 1, as the flowers they hold: the intro rows of a new
# player's run, and the breathers right after every MILESTONE_EVERY-th flower.
func _is_easy_row(row: int) -> bool:
	if new_player_run and row <= INTRO_ROWS:
		return true
	return row > MILESTONE_EVERY and (row - 1) % MILESTONE_EVERY < BREATHER_ROWS


func _spawn_record_line(y: float, flower_x: float) -> void:
	record_line = Node2D.new()
	record_line.position = Vector2(0.0, y)
	add_child(record_line)
	# the word RECORD goes on the side away from the flower, so the two never overlap
	record_word_on_left = flower_x > SCREEN_W / 2.0


# Dropping the marker is the cue: view3d.gd flashes the line it was drawing
# and lets it go.
func _flash_record_line() -> void:
	record_line.queue_free()
	record_line = null


# ------------------------------------------------------------------
# Update loop
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	physics_ticks_since_reset += 1
	match state:
		State.PLAYING:
			_update_playing(delta)
		State.DYING:
			_update_dying(delta)
		_:
			pass

	# camera_y itself only moves inside _update_playing's scroll branch, so
	# re-deriving the base position here every frame is a no-op outside
	# PLAYING — which is exactly "frozen" during DYING, letting a shake
	# (near miss or death) jitter around that fixed point without drifting.
	camera.position = Vector2(0.0, camera_y)
	_apply_camera_shake(delta)

	sky.check_triggers(score)


func _process(delta: float) -> void:
	_fade_score_over_things(delta)
	if state == State.GAMEOVER and game_over_screen.visible:
		_show_game_over_lock()
	if lost_marker.visible:
		# the lost flower's marker blinks through the fall, as a flower about
		# to be lost does (view3d.gd), and holds still on the game over
		lost_blink += delta
		lost_marker.modulate.a = 1.0 if state != State.DYING or fmod(lost_blink * 6.0, 1.0) < 0.6 else 0.0


# The score's digits are big, and a flower passing behind them was hidden
# (or the bee, up by the top edge): while one is there they fade, enough to
# see it through them and still read the number.
func _fade_score_over_things(delta: float) -> void:
	if not score_label.visible or (state != State.PLAYING and state != State.DYING):
		score_label.modulate.a = 1.0
		return
	var w: float = ui_font.get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var digits := Rect2(SCREEN_W / 2.0 - w / 2.0 - 4.0, score_label.position.y + 6.0, w + 8.0, 54.0)
	var behind := _circle_in_rect(_screen_pos(bee.position), bee.radius, digits)
	for f in flowers:
		if behind:
			break
		behind = _circle_in_rect(_screen_pos(f.position, 0.1), FlowerScript.FLOWER_R, digits)
	var want := SCORE_BEHIND_ALPHA if behind else 1.0
	score_label.modulate.a = move_toward(score_label.modulate.a, want, delta * 6.0)


func _circle_in_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return c.distance_squared_to(closest) < r * r


func _start_camera_shake(duration: float, magnitude: float) -> void:
	# the settings' "Shake" switch, for whoever the jolts bother
	if not SaveData.screen_shake:
		return
	camera_shake_time = duration
	camera_shake_total = duration
	camera_shake_magnitude = magnitude


func _apply_camera_shake(delta: float) -> void:
	if camera_shake_time <= 0.0:
		return
	camera_shake_time = max(0.0, camera_shake_time - delta)
	var t: float = camera_shake_time / camera_shake_total if camera_shake_total > 0.0 else 0.0
	var mag: float = camera_shake_magnitude * t
	camera.position += Vector2(randf_range(-mag, mag), randf_range(-mag, mag))


func _update_playing(delta: float) -> void:
	if has_tapped_once and hint_alpha > 0.0:
		hint_alpha = max(0.0, hint_alpha - delta * 2.5)
		direction_hint.modulate.a = hint_alpha
		if hint_alpha <= 0.0:
			direction_hint.visible = false

	if not world_moving:
		return

	time_since_first_flap += delta
	bee.ceiling_y = camera_y + bee.radius

	if not scrolling_started:
		launch_timer += delta
		var start_delay: float = REPLAY_SCROLL_START_DELAY if has_finished_a_run else SCROLL_START_DELAY
		if launch_timer >= start_delay:
			scrolling_started = true
	else:
		elapsed += delta

		camera_y -= _current_scroll_speed() * delta

		while highest_spawn_y > camera_y - screen_h:
			_spawn_row()

	# The bee is already flying/falling under normal physics from the first
	# flap onward, camera frozen or not — so the usual rules (missed
	# obstacle, missed flower, falling past the bottom of what's currently
	# visible) apply the whole time, same as they did before the 1s pause
	# existed. The pause only delays the camera's own climb.
	var screen_bottom := camera_y + screen_h
	var bottom_cull := screen_bottom + 200.0
	for o in obstacles.duplicate():
		if o.position.y > bottom_cull:
			obstacles.erase(o)
			o.queue_free()
	for c in clouds.duplicate():
		if c.position.y > bottom_cull or c.position.x > SCREEN_W + 150.0 or c.position.x < -150.0:
			clouds.erase(c)
			c.queue_free()
	for g in seagulls.duplicate():
		if g.position.y > bottom_cull or g.position.x > SCREEN_W + 150.0 or g.position.x < -150.0:
			seagulls.erase(g)
			g.queue_free()
	for c in celestials.duplicate():
		if c.position.y > bottom_cull:
			celestials.erase(c)
			c.queue_free()
	if record_line and record_line.position.y > bottom_cull:
		record_line.queue_free()
		record_line = null

	# Every flower is mandatory — letting one scroll off the bottom
	# uncollected ends the run, same as hitting an obstacle (spec change:
	# missing a flower is now a game-over condition, not just a missed point).
	# Only once it is *entirely* gone, though, matching the bee's own rule:
	# half a flower still on screen is still reachable, and dying to it
	# reads as the game cheating.
	for f in flowers:
		if f.position.y - FlowerScript.FLOWER_R > screen_bottom:
			_trigger_game_over("flower", f)
			return

	for o in obstacles:
		var band_top: float = o.position.y
		var band_bottom: float = band_top + ObstacleScript.THICK
		var in_band: bool = bee.position.y + bee.radius >= band_top and bee.position.y - bee.radius <= band_bottom
		if in_band:
			var gap_left: float = o.gap_x - o.gap_width / 2.0
			var gap_right: float = o.gap_x + o.gap_width / 2.0
			var clearance := INF
			if gap_left > 0.0:
				clearance = _circle_rect_clearance(bee.position, bee.radius, Vector2(0.0, band_top), Vector2(gap_left, band_bottom))
			if gap_right < SCREEN_W:
				clearance = min(clearance, _circle_rect_clearance(bee.position, bee.radius, Vector2(gap_right, band_top), Vector2(SCREEN_W, band_bottom)))
			if clearance < 0.0:
				_trigger_game_over("hedge")
				return
			# Track the closest the bee gets to either bar while it's in this
			# row's band — checked once the bee has fully cleared it, below.
			o.near_miss_min_clearance = min(o.near_miss_min_clearance, clearance)
		elif not o.near_miss_checked and o.near_miss_min_clearance <= NEAR_MISS_MARGIN:
			o.near_miss_checked = true
			_trigger_near_miss()

	if time_since_first_flap >= FALL_DEATH_GRACE and bee.position.y - bee.radius > screen_bottom:
		_trigger_game_over("fall")


func _circle_rect_clearance(circle_center: Vector2, radius: float, rect_min: Vector2, rect_max: Vector2) -> float:
	# Standard circle-vs-AABB distance: find the closest point on the rect to
	# the circle's center. Negative means overlap (a hit) — this treats the
	# bee as the circle it actually looks like, instead of the square
	# bounding box the old check used, which let corners of the invisible
	# hitbox clip the roseira before the round bee visually touched
	# it. The actual (non-negative) distance doubles as the near-miss
	# clearance so both checks share one geometry test.
	var closest := Vector2(
		clamp(circle_center.x, rect_min.x, rect_max.x),
		clamp(circle_center.y, rect_min.y, rect_max.y)
	)
	return circle_center.distance_to(closest) - radius


func _trigger_near_miss() -> void:
	_start_camera_shake(CAMERA_SHAKE_DURATION, CAMERA_SHAKE_MAGNITUDE)
	_play_sfx(SFX_NEAR_MISS, SFX_NEAR_MISS_DB)
	# The shake alone read like being hit; the word says it was the good kind.
	_vibrate(NEAR_MISS_BUZZ_MS)
	_show_phew()


# "Ufa!" in gold beside the bee: pops up, rises a little and fades, about
# half a second. Above the bee, or under it when the bee is up by the score.
func _show_phew() -> void:
	var at := _screen_pos(bee.position)
	var side := 1.0 if at.x < SCREEN_W / 2.0 else -1.0
	var above := at.y > SCORE_Y + top_inset + 110.0
	var x := clampf(at.x + side * 30.0 - phew_label.size.x / 2.0, 4.0, SCREEN_W - 4.0 - phew_label.size.x)
	var y := at.y - 50.0 if above else at.y + 18.0
	if phew_tween != null and phew_tween.is_valid():
		phew_tween.kill()
	phew_label.position = Vector2(x, y)
	phew_label.scale = Vector2.ONE * 0.6
	phew_label.modulate.a = 1.0
	phew_label.visible = true
	# bound to the label, which freezes with the run (a pause mid-pop holds it)
	phew_tween = phew_label.create_tween()
	phew_tween.tween_property(phew_label, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	phew_tween.parallel().tween_property(phew_label, "position:y", y - PHEW_RISE, PHEW_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	phew_tween.parallel().tween_property(phew_label, "modulate:a", 0.0, PHEW_TIME * 0.6).set_delay(PHEW_TIME * 0.4)
	phew_tween.tween_callback(func(): phew_label.visible = false)


# Where a point of the 2D simulation shows on the screen, in the interface's
# coordinates. The 3D view is tilted, so the two drift apart towards the
# edges (by some 25 px at the bottom of a phone screen).
func _screen_pos(p: Vector2, z := 0.0) -> Vector2:
	if view3d == null:
		return p - camera.position
	return view3d.cam.unproject_position(view3d.to3(p, z))


func _update_dying(delta: float) -> void:
	dying_timer += delta
	if bee.position.y - bee.radius > camera_y + screen_h or dying_timer > DEATH_FALL_TIME:
		_end_game()


func _current_scroll_speed() -> float:
	return SCROLL_BASE + (SCROLL_MAX - SCROLL_BASE) * _difficulty()


func _difficulty() -> float:
	return clamp(elapsed / DIFFICULTY_RAMP_TIME, 0.0, 1.0)


func on_flower_collected(flower: Area2D) -> void:
	if state != State.PLAYING:
		return
	if not flowers.has(flower):
		return
	if not _bee_contacts_trustworthy():
		return
	flowers.erase(flower)
	flower.play_collect_effect()
	_play_sfx(SFX_COLLECT, SFX_COLLECT_DB, COLLECT_PITCH_STEPS[collect_step])
	collect_step = (collect_step + 1) % COLLECT_PITCH_STEPS.size()
	score += 1
	_update_score_label()
	_pop_score()
	_check_bee_unlocks()
	if score == record_at_run_start + 1:
		_show_record_beaten()
	if record_line and score == SaveData.best_score + 1:
		_flash_record_line()
		# passing the record is worth hearing at once, not only at game over
		# (unless the same flower just won a bee, whose jingle is already on)
		if bee_won_at != score:
			_play_sfx(SFX_RECORD, SFX_RECORD_DB - 4.0)
			_vibrate(60)
			jingle_at = score
	flower_collected.emit(score)
	if score % MILESTONE_EVERY == 0:
		milestone_reached.emit(score)


func _bee_contacts_trustworthy() -> bool:
	# Flower pickups come from the physics server, which lags a teleport: a
	# reset moves the bee, but the server only adopts the new position at
	# the *end* of its next step — after that step has already tested every
	# flower against the old one, and those results arrive at the start of
	# the step after. For those two ticks a reported overlap describes where
	# the last run ended, and since rows regenerate at the same heights, a
	# new flower on that spot would collect itself. Gated on ticks rather
	# than the first flap because a tap in the same frame as "Play Again"
	# flaps before any step runs. (Obstacles don't need this: they're tested
	# directly against the bee's node position in _update_playing.)
	return physics_ticks_since_reset >= 2


# `lost` is the flower the run was lost to, for a "flower" death (the tools
# that end a run by hand leave it out, and get no marker).
func _trigger_game_over(cause: String, lost: Area2D = null) -> void:
	if state != State.PLAYING:
		return
	death_cause = cause
	state = State.DYING
	dying_timer = 0.0
	pause_button.visible = false
	_start_camera_shake(DEATH_SHAKE_DURATION, DEATH_SHAKE_MAGNITUDE)
	_play_sfx(SFX_HIT, SFX_HIT_DB)
	_vibrate(70)
	bee.die()
	# The bee keeps falling under its own gravity — no impact effect, no
	# reposition. Tested and decided explicitly (spec 4.7): any collision FX
	# made the moment feel worse. Only the face/pose changes; the fall itself
	# is untouched.
	if cause == "flower":
		# the rule comes back for the next run
		rule_due = true
		if lost != null:
			_show_lost_marker(lost)


# An arrow over the flower the run was lost to, pointing down at it, at its
# x on the bottom edge (where the top of the flower still shows). Not an
# effect on the death itself (spec 4.7 above): it only says which flower it
# was, which the game over then puts in words. It blinks through the fall
# and stays, still, on the game-over screen, below its buttons.
func _show_lost_marker(f: Area2D) -> void:
	# from where the camera is this tick (view3d's own trails it by a frame)
	var at: Vector2 = f.position - Vector2(0.0, camera_y)
	if view3d != null:
		at = view3d.screen_pos_for(f.position, Vector2(0.0, camera_y), 0.1)
	lost_marker.position = Vector2(
		roundf(clampf(at.x, 22.0, SCREEN_W - 22.0) - lost_marker.size.x / 2.0),
		roundf(clampf(at.y - 20.0, screen_h * 0.75, screen_h - 4.0) - lost_marker.size.y))
	lost_marker.modulate.a = 1.0
	lost_marker.visible = true
	lost_blink = 0.0


func _end_game() -> void:
	state = State.GAMEOVER
	has_finished_a_run = true
	bee.physics_enabled = false

	var beat_record := score > record_at_run_start
	_keep_record()
	if beat_record:
		_play_sfx(SFX_RECORD, SFX_RECORD_DB)
		_vibrate(160)
	leaderboard.submit(score)

	game_over_msec = Time.get_ticks_msec()
	_fill_game_over(beat_record)
	# The game-over panel carries its own score and record, so the in-run
	# HUD above it would just print both a second time.
	_set_hud_visible(false)
	# ...and its own word about a bee won in this run (the goal chip)
	_clear_notices()
	game_over_screen.visible = true
	_enter_game_over()
	ads.run_finished()


# Saves the record the moment it is known to be beaten for good: at the end
# of the run, and whenever the run is paused — a paused game can be closed or
# killed without ever reaching its game over.
func _keep_record() -> void:
	if score > SaveData.best_score:
		SaveData.best_score = score
		SaveData.save_data()


# Everything the game-over screen says about the run that just ended.
func _fill_game_over(beat_record: bool) -> void:
	final_best_label.text = "%d" % SaveData.best_score
	record_label.text = _t("record") % SaveData.best_score
	death_label.text = _t("died_" + death_cause) if death_cause != "" else ""
	record_note.text = _record_note(beat_record)
	if beat_record:
		_show_new_record_badge()
	else:
		_hide_new_record_badge()
	_refresh_goal_chip()
	_layout_game_over(beat_record)
	_count_up(beat_record)


# The line under the score: a record beaten says what it was ("26 | 26" said
# nothing), and a run that ended just under it says by how much.
func _record_note(beat_record: bool) -> String:
	if beat_record:
		return _t("previous_record") % record_at_run_start if record_at_run_start > 0 else ""
	var best: int = SaveData.best_score
	if score <= 0 or best <= 0:
		return ""
	var short := best - score
	if short == 0:
		return _t("record_tied")
	if short <= maxi(NEAR_RECORD_MIN, ceili(best * NEAR_RECORD_SHARE)):
		return _tn("record_short", short)
	return ""


# The board's rows, top to bottom: the title, the cause, a rule, then the
# score and the record side by side, or the score alone under "New record!"
# when it beat the record (the record is the same number), and the record
# line if there is one. The board takes the height of what it shows, and the
# board and the chip are centred between the top row and the buttons.
func _layout_game_over(beat_record: bool) -> void:
	var w := GO_W
	var col_w := (w - 2.0 * UI_CELL) / 2.0
	death_label.visible = death_label.text != ""
	score_caption.visible = not beat_record
	best_caption.visible = not beat_record
	col_divider.visible = not beat_record
	final_best_label.visible = not beat_record
	if beat_record:
		_set_font_size(final_score_label, 60)
		final_score_label.add_theme_color_override("font_color", GOLD)
		final_score_label.position = Vector2(0, 120)
		final_score_label.size = Vector2(w, 62)
	else:
		_set_font_size(final_score_label, 50)
		final_score_label.add_theme_color_override("font_color", Color.WHITE)
		final_score_label.position = Vector2(UI_CELL, 124)
		final_score_label.size = Vector2(col_w, 54)
	final_score_label.pivot_offset = final_score_label.size / 2.0
	var bottom := 182.0
	record_note.visible = record_note.text != ""
	if record_note.visible:
		bottom = record_note.position.y + 24.0
	# down to the face's bottom edge: the side band and the outline under it
	var h := ceilf((bottom + 3.0 * UI_CELL) / UI_CELL) * UI_CELL
	go_board.size = Vector2(w, h)
	go_board.queue_redraw()
	var total := h
	if goal_chip.visible:
		goal_chip.position.y = h + 12.0
		total = goal_chip.position.y + goal_chip.size.y
	var top := 64.0 + top_inset
	var room_end := restart_button.position.y - 18.0
	var y := maxf(top, roundf((top + room_end - total) / 2.0))
	go_stack.position = Vector2(floorf((SCREEN_W - w) / 2.0), y)
	go_stack.size = Vector2(w, total)
	go_stack.pivot_offset = go_stack.size / 2.0


func _set_font_size(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", maxi(5, roundi(font_size / 4.5)))


# The screen comes in rather than popping up: it fades in while the board
# grows into place, all well inside the lock against stray taps
# (GAME_OVER_LOCK_MSEC), which _show_game_over_lock shows on the buttons.
func _enter_game_over() -> void:
	if go_enter != null and go_enter.is_valid():
		go_enter.kill()
	go_ready = false
	_show_game_over_lock()
	game_over_screen.modulate.a = 0.0
	go_stack.scale = Vector2.ONE * GO_GROW_FROM
	# bound to the screen, on the interface's layer, which runs through a pause
	go_enter = game_over_screen.create_tween()
	go_enter.tween_property(game_over_screen, "modulate:a", 1.0, GO_FADE_IN)
	go_enter.parallel().tween_property(go_stack, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Taps the game over isn't taking yet: in its first instant, and while an ad
# is opening (see _on_restart_pressed).
func _game_over_locked() -> bool:
	var now := Time.get_ticks_msec()
	if now - game_over_msec < GAME_OVER_LOCK_MSEC:
		return true
	return restart_after_ad and now - restart_lock_msec < AD_LOCK_MSEC


# While the lock holds, the buttons where the thumbs were tapping are dimmed
# and take no taps (a press used to click and do nothing); when it lets go
# they light up with a little jump, which says "now".
func _show_game_over_lock() -> void:
	var locked := _game_over_locked()
	for b in go_bottom:
		b.disabled = locked
	for gear in gear_buttons:
		if game_over_screen.is_ancestor_of(gear):
			gear.disabled = locked
	goal_chip.disabled = locked or goal_equip == ""
	if locked:
		go_ready = false
		for b in go_bottom:
			b.modulate.a = 0.5
	elif not go_ready:
		go_ready = true
		for b in go_bottom:
			b.modulate.a = 1.0
		restart_button.pivot_offset = restart_button.size / 2.0
		restart_button.scale = Vector2.ONE * 1.08
		var pop := restart_button.create_tween()
		pop.tween_property(restart_button, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# The score counts up from 0 (COUNT_UP_TIME, easing out), ticking up the
# pickup's scale as it goes, and lands with a jump. A record beaten fills
# the chip's bar from where the record was, at the same time.
func _count_up(beat_record: bool) -> void:
	if count_tween != null and count_tween.is_valid():
		count_tween.kill()
	count_shown = 0
	count_ticks = 0
	count_last_tick = -1.0
	final_score_label.text = "0"
	final_score_label.scale = Vector2.ONE
	if score <= 0:
		return
	count_tween = final_score_label.create_tween()
	count_tween.tween_method(_count_step, 0.0, 1.0, COUNT_UP_TIME)
	if beat_record and goal_bar.visible:
		var to: float = goal_bar.value
		goal_bar.value = clampf(float(record_at_run_start) / goal_bar.get_meta("need"), 0.0, to)
		count_tween.parallel().tween_property(goal_bar, "value", to, COUNT_UP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	count_tween.tween_callback(_count_done)


func _count_step(p: float) -> void:
	var shown := mini(score, roundi((1.0 - (1.0 - p) * (1.0 - p)) * score))
	if shown == count_shown:
		return
	count_shown = shown
	final_score_label.text = "%d" % shown
	var t := p * COUNT_UP_TIME
	if t - count_last_tick < COUNT_UP_GAP:
		return
	count_last_tick = t
	# up the pentatonic steps a flower climbs, an octave higher every five
	var steps: int = COLLECT_PITCH_STEPS.size()
	var pitch: float = COLLECT_PITCH_STEPS[count_ticks % steps] * pow(2.0, count_ticks / steps)
	_play_sfx(SFX_UI_TAP, SFX_COUNT_DB, minf(pitch, 3.0))
	count_ticks += 1


func _count_done() -> void:
	count_shown = score
	final_score_label.text = "%d" % score
	final_score_label.scale = Vector2.ONE * 1.2
	var pop := final_score_label.create_tween()
	pop.tween_property(final_score_label, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# The chip under the board: a bee won in this run, which one tap puts on, or
# else the next one to win, what it takes and how far the record has got
# (a bar, and "Faltam N"). It gives the next run a goal — without it the
# skins are only ever seen by someone who opens the bee menu.
func _refresh_goal_chip() -> void:
	goal_equip = ""
	goal_bar.visible = false
	goal_left.visible = false
	goal_go.visible = false
	goal_chip.visible = false
	if not bees_won_this_run.is_empty():
		var won: String = bees_won_this_run[-1]
		var in_use := _current_bee_skin() == won
		goal_plate.set_ink(GOLD)
		goal_icon.texture = load(_bee_icon_path(won))
		_set_silhouette(goal_icon, false)
		goal_title.text = _t("unlocked") % BEE_SKINS[won]["name"]
		goal_title.add_theme_color_override("font_color", GOLD)
		goal_hint.text = _t("selected") if in_use else _t("use_it")
		goal_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.88) if in_use else GOLD)
		goal_go.visible = not in_use
		goal_equip = "" if in_use else won
		_size_block_button(goal_chip, Vector2(GO_W, 66))
		goal_chip.visible = true
	else:
		for id in BEE_ORDER:
			if _bee_unlocked(id):
				continue
			var need: int = BEE_SKINS[id]["score"]
			goal_plate.set_ink(Color.WHITE)
			goal_icon.texture = load(_bee_icon_path(id))
			_set_silhouette(goal_icon, true)
			goal_title.text = _t("next_bee") % BEE_SKINS[id]["name"]
			goal_title.add_theme_color_override("font_color", Color.WHITE)
			goal_hint.text = _t("next_goal") % need
			goal_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
			goal_bar.set_meta("need", need)
			goal_bar.value = clampf(float(SaveData.best_score) / need, 0.0, 1.0)
			goal_bar.visible = true
			goal_left.text = _tn("to_go", need - SaveData.best_score)
			goal_left.visible = true
			_size_block_button(goal_chip, Vector2(GO_W, 87))
			goal_chip.visible = true
			break
	goal_chip.disabled = goal_equip == "" or _game_over_locked()


# The chip's "Use it": the bee won in the run goes on at once, without the
# bee menu (it took three taps).
func _on_goal_chip_pressed() -> void:
	if state != State.GAMEOVER or goal_equip == "" or _game_over_locked():
		return
	_play_sfx(SFX_UI_TAP, SFX_UI_DB)
	_select_bee(goal_equip)
	_refresh_goal_chip()
	goal_chip.pivot_offset = goal_chip.size / 2.0
	goal_chip.scale = Vector2.ONE * 1.06
	var pop := goal_chip.create_tween()
	pop.tween_property(goal_chip, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_hud_visible(on: bool) -> void:
	score_label.visible = on
	record_label.visible = on


func _show_new_record_badge() -> void:
	new_record_badge.scale = Vector2.ONE
	new_record_badge.visible = true

	if record_pulse != null and record_pulse.is_valid():
		record_pulse.kill()
	# Bound to the badge rather than to this node so it keeps its own
	# process mode — the UI layer runs through a pause, this script doesn't.
	record_pulse = new_record_badge.create_tween().set_loops()
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE * 1.08, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _hide_new_record_badge() -> void:
	new_record_badge.visible = false
	if record_pulse != null and record_pulse.is_valid():
		record_pulse.kill()
	record_pulse = null


# ------------------------------------------------------------------
# Screen flow
# ------------------------------------------------------------------

func _on_play_pressed() -> void:
	# Guards against a rapid double-tap firing this twice (e.g. the second
	# tap landing before the button visually/logically goes away) and
	# re-running the transition or reset mid-flight.
	if state != State.START:
		return
	if not SaveData.seen_tutorial:
		_begin_first_time_transition()
	else:
		_begin_playing()


func _begin_first_time_transition() -> void:
	state = State.STARTING
	# seen_tutorial is saved by the first flap (_flap), not here: a first
	# run restarted from the pause menu, or an app closed, before flying
	# would otherwise lose the arrows for good.

	direction_hint.modulate.a = 0.0
	direction_hint.visible = hint_alpha > 0.0
	var tween := create_tween()
	tween.tween_property(start_screen, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(direction_hint, "modulate:a", hint_alpha, 1.0)
	tween.tween_callback(func():
		start_screen.visible = false
		start_screen.modulate.a = 1.0
		_begin_playing()
	)


func _begin_playing() -> void:
	state = State.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	pause_button.visible = true
	_set_hud_visible(true)
	_show_rule_if_due()
	# world_moving/bee.physics_enabled stay false here on the cold-start
	# path — spec 4.3: gravity only turns on at the real first flap
	# ("decolar" = "primeiro flap" = "início da partida", spec 4.3).


func _on_restart_pressed() -> void:
	# Guard against a rapid multi-tap re-entering this while a run is
	# already live (reported bug: mashing "play again" could occasionally
	# leave the bee looking dead right at the start of the new run) — only
	# a press from an actual game-over screen should ever reset anything.
	if state != State.GAMEOVER:
		return
	# Not in the screen's first instant (GAME_OVER_LOCK_MSEC). And while an
	# ad is opening, further presses are swallowed — but only for a few
	# seconds. If the ad never reports back (it failed without saying so), a
	# lock without an expiry would leave this button dead for good; a real ad
	# covers the button for longer than the lock lasts anyway.
	if _game_over_locked():
		return
	# Between runs is the one place an ad may appear, and only every few
	# runs (ads.gd). The new run then waits for the ad to close; it starts
	# with the bee on the ground either way, so nothing is lost to the ad.
	if not restart_after_ad and ads.show_between_runs():
		restart_after_ad = true
		restart_lock_msec = Time.get_ticks_msec()
		return
	_start_fresh_run()


func _on_ad_closed() -> void:
	music.stream_paused = false
	if restart_after_ad:
		restart_after_ad = false
		if state == State.GAMEOVER:
			_start_fresh_run()


func _start_fresh_run() -> void:
	# Every fresh run — first launch, replay after a game over, or restart
	# from the pause menu — starts the same way: bee grounded, waiting for
	# the real first flap.
	_reset_to_ground_scene()
	state = State.PLAYING
	# normally cleared by the ad closing; here in case it never said it did
	restart_after_ad = false
	music.stream_paused = false
	start_screen.visible = false
	game_over_screen.visible = false
	# The badge rides along with the hidden screen, but its loop would keep
	# ticking for the whole next run if it isn't stopped here.
	_hide_new_record_badge()
	# (a bee's notice won just before a restart from the pause menu went with
	# the old run, in _reset_to_ground_scene)
	# The bee menu can be opened from the game over while an ad is opening
	# (or the credits from the pause menu), and the run would start under it.
	bee_menu.visible = false
	settings_screen.visible = false
	credits_screen.visible = false
	pause_button.visible = true
	_set_hud_visible(true)
	_show_rule_if_due()


func _on_pause_pressed() -> void:
	# a resume's countdown can be paused again too: back, escape, the button
	if state != State.PLAYING and state != State.RESUMING:
		return
	_stop_countdown()
	state = State.PAUSED
	# The run's notice slot (and an "Ufa!") are drawn under the menu's dim
	# with the rest of the run's HUD, and freeze with the run: what they say
	# is still there after the resume. (The old banner sat right across the
	# "Paused" title and had to be put away.)
	_keep_record()
	pause_button.visible = false
	_place_links(privacy_button, credits_button)
	pause_screen.visible = true
	_fade_in(pause_screen)
	# The tutorial arrows sit right where the menu's buttons are, and showed
	# through from behind them when a first run was paused before its first
	# flap.
	direction_hint.visible = false
	# Freezing the tree is what actually stops the run: the bee's physics,
	# the drifting clouds and gulls and their wing animations all advance
	# on their own, so gating this script alone would leave the world alive
	# behind the menu.
	get_tree().paused = true


# Resuming went straight back to the run, with the bee in mid-air and the
# thumb still on the button in the middle of the screen: about a second of
# falling was gone before the first tap. The menu goes, and a 3-2-1 with a
# tick on every number gives the thumbs time to get back to the sides; the
# world stays frozen until it ends. A run that has not flown yet has nothing
# to lose and resumes at once.
func _on_resume_pressed() -> void:
	if state != State.PAUSED:
		return
	pause_screen.visible = false
	credits_screen.visible = false
	if not world_moving:
		_finish_resume()
		return
	state = State.RESUMING
	pause_button.visible = true
	countdown_ticks = 0
	countdown_label.visible = true
	_countdown_step(3)
	# bound to the label, which keeps running while the tree is frozen
	countdown_tween = countdown_label.create_tween()
	for n in [2, 1]:
		countdown_tween.tween_interval(COUNTDOWN_STEP)
		countdown_tween.tween_callback(_countdown_step.bind(n))
	countdown_tween.tween_interval(COUNTDOWN_STEP)
	countdown_tween.tween_callback(_finish_resume)


func _countdown_step(n: int) -> void:
	countdown_label.text = "%d" % n
	countdown_label.scale = Vector2.ONE * 1.5
	countdown_label.modulate.a = 1.0
	var pop := countdown_label.create_tween()
	pop.tween_property(countdown_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(countdown_label, "modulate:a", 0.55, COUNTDOWN_STEP - 0.22)
	# the last one a fifth higher, so the rhythm says when it goes
	_play_sfx(SFX_UI_TAP, SFX_COUNTDOWN_DB, 1.5 if n == 1 else 1.0)
	countdown_ticks += 1


func _finish_resume() -> void:
	if state != State.PAUSED and state != State.RESUMING:
		return
	_stop_countdown()
	get_tree().paused = false
	pause_screen.visible = false
	credits_screen.visible = false
	direction_hint.visible = hint_alpha > 0.0
	state = State.PLAYING
	pause_button.visible = true


func _stop_countdown() -> void:
	if countdown_tween != null and countdown_tween.is_valid():
		countdown_tween.kill()
	countdown_tween = null
	countdown_label.visible = false


func _on_pause_restart_pressed() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	pause_screen.visible = false
	_start_fresh_run()


func _on_music_toggle_pressed() -> void:
	SaveData.music_muted = not SaveData.music_muted
	SaveData.save_data()
	_apply_music_mute()


func _play_sfx(stream: AudioStream, volume_db: float, pitch := 1.0) -> void:
	if SaveData.sfx_muted:
		return
	for voice in sfx_pool:
		if voice.playing:
			continue
		voice.stream = stream
		voice.volume_db = volume_db
		voice.pitch_scale = pitch
		voice.play()
		return
	# Every voice busy: dropping this one is better than cutting off a
	# sound that's already audible.


func _apply_music_mute() -> void:
	music.volume_db = MUSIC_MUTED_DB if SaveData.music_muted else MUSIC_VOLUME_DB
	_show_toggle("music", not SaveData.music_muted)


func _on_sound_toggle_pressed() -> void:
	SaveData.sfx_muted = not SaveData.sfx_muted
	SaveData.save_data()
	_apply_sound_setting()
	# the button's own click was swallowed if the effects were off when it
	# was pressed; turning them back on should be heard
	if not SaveData.sfx_muted:
		_play_sfx(SFX_UI_TAP, SFX_UI_DB)


func _apply_sound_setting() -> void:
	_show_toggle("sound", not SaveData.sfx_muted)


func _on_vibration_toggle_pressed() -> void:
	SaveData.vibration = not SaveData.vibration
	SaveData.save_data()
	_apply_vibration_setting()
	_vibrate(40)


func _apply_vibration_setting() -> void:
	_show_toggle("vibration", SaveData.vibration)


func _on_shake_toggle_pressed() -> void:
	SaveData.screen_shake = not SaveData.screen_shake
	SaveData.save_data()
	_show_toggle("shake", SaveData.screen_shake)
	# switched on, the switches themselves give a little jolt, as a sample
	if SaveData.screen_shake:
		for v in toggle_views["shake"]:
			_nudge(v["button"], 2.0)


func _on_toggle_pressed(id: String) -> void:
	match id:
		"music":
			_on_music_toggle_pressed()
		"sound":
			_on_sound_toggle_pressed()
		"vibration":
			_on_vibration_toggle_pressed()
		"shake":
			_on_shake_toggle_pressed()


# Every copy of a switch (the pause menu's, the settings panel's) shows its
# setting the same way. On: a gold outline, as the bee in use has in the bee
# menu. Off: a white one, the icon faded and struck through, the caption dim.
func _show_toggle(id: String, on: bool) -> void:
	for v in toggle_views.get(id, []):
		v["slash"].visible = not on
		v["icon"].modulate = Color.WHITE if on else Color(1, 1, 1, 0.4)
		v["plate"].set_ink(GOLD if on else Color(1, 1, 1, 0.5))
		v["caption"].add_theme_color_override("font_color", Color.WHITE if on else Color(1, 1, 1, 0.6))


# A sideways shake, there and back in 0.2 s: "no" on a locked bee's card,
# and the shake switch's own sample.
func _nudge(c: Control, by := 3.0) -> void:
	if c.has_meta("nudge"):
		var old: Tween = c.get_meta("nudge")
		if old.is_valid():
			old.kill()
		c.position.x = c.get_meta("nudge_x")
	var x0 := c.position.x
	c.set_meta("nudge_x", x0)
	var t := c.create_tween()
	c.set_meta("nudge", t)
	for dx in [by, -by, by * 0.66, 0.0]:
		t.tween_property(c, "position:x", x0 + dx, 0.05)


# A short buzz for the moments that matter (death, a new record, a new
# bee); does nothing on devices without a vibrator.
func _vibrate(ms: int) -> void:
	if SaveData.vibration:
		Input.vibrate_handheld(ms)


func _update_score_label() -> void:
	score_label.text = "%d" % score


# The score jumps a little with every flower.
func _pop_score() -> void:
	if score_pop != null and score_pop.is_valid():
		score_pop.kill()
	score_label.scale = Vector2.ONE * 1.25
	score_pop = score_label.create_tween()
	score_pop.tween_property(score_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------
# Bee skins
# ------------------------------------------------------------------

func _bee_unlocked(id: String) -> bool:
	return SaveData.best_score >= BEE_SKINS[id]["score"] or SaveData.unlocked_bees.has(id)


# Called on every flower: a skin is won the moment the run reaches its
# score, not when the run ends, so dying right after still keeps it.
func _check_bee_unlocks() -> void:
	for id in BEE_ORDER:
		if score >= BEE_SKINS[id]["score"] and not _bee_unlocked(id):
			SaveData.unlocked_bees.append(id)
			SaveData.save_data()
			bees_won_this_run.append(id)
			bee_won_at = score
			_refresh_bee_menu()
			_show_bee_notice(id)


func _current_bee_skin() -> String:
	var id: String = SaveData.selected_bee
	if not BEE_SKINS.has(id) or not _bee_unlocked(id):
		return "normal"
	return id


func _apply_bee_skin() -> void:
	var id := _current_bee_skin()
	var skin: Dictionary = BEE_SKINS[id]
	bee.apply_skin(skin["size"], skin["speed"])
	# the very first call comes from _ready, before the 3D view exists
	if view3d and applied_bee_skin != id:
		applied_bee_skin = id
		view3d.set_bee_skin(skin["model"], skin["size"], skin["glow"])
	# a bee waiting on the ground keeps its feet on the grass at its new size
	if state == State.START and not world_moving:
		bee.position.y = -bee.radius


# A bee won mid-run: its jingle, a buzz, and its name in the notice slot.
# Only the name: where to pick it ("in the bee menu") is the game-over
# chip's to say.
func _show_bee_notice(id: String) -> void:
	_play_sfx(SFX_RECORD, SFX_RECORD_DB)
	_vibrate(120)
	_notify({"kind": "bee", "title": _t("unlocked") % BEE_SKINS[id]["name"],
			"icon": load(_bee_icon_path(id)), "ink": GOLD, "color": GOLD})


# Every MILESTONE_EVERY-th flower (main's own milestone_reached): "25!"
# between two flowers in the slot, two quick notes, one short buzz. Under a
# second, all of it. A bee won on the same flower has the moment to itself
# (25, 50, 100, 175 and 300 are bees too), and on a flower that also beat
# the record the jingle is heard rather than both.
func _on_milestone(count: int) -> void:
	if bee_won_at == count:
		return
	if jingle_at != count:
		for note in MILESTONE_NOTES:
			get_tree().create_timer(note[0], false).timeout.connect(
					_play_sfx.bind(SFX_COLLECT, SFX_MILESTONE_DB, note[1]))
		_vibrate(MILESTONE_BUZZ_MS)
	_notify({"kind": "milestone", "title": _t("milestone") % count, "flowers": 2,
			"ink": GOLD, "color": GOLD})


# main's own flower_collected: the rule plate has done its job by the run's
# RULE_UNTIL_FLOWER-th flower.
func _on_flower_count(count: int) -> void:
	if rule_on and count >= RULE_UNTIL_FLOWER:
		rule_on = false
		rule_due = false
		if notice_now.get("kind") == "rule":
			_notice_leave()


func _show_rule_if_due() -> void:
	if not rule_due or rule_on:
		return
	rule_on = true
	if notice_now.is_empty():
		_notice_display(_rule_entry())


func _rule_entry() -> Dictionary:
	return {"kind": "rule", "priority": 1, "hold": -1.0, "stale": INF, "title": _t("rule"),
			"flowers": 1, "ink": Color.WHITE, "color": Color.WHITE}


# Once the run passes the record, the readout over the score says so, in
# gold, for the rest of the run (it used to keep the old record's number).
func _show_record_beaten() -> void:
	record_label.text = _t("record_beaten")
	record_label.add_theme_color_override("font_color", GOLD)
	if notice_now.is_empty():
		_pop_record()
	else:
		record_pop_due = true


func _pop_record() -> void:
	record_pop_due = false
	if record_pop != null and record_pop.is_valid():
		record_pop.kill()
	record_label.pivot_offset = record_label.size / 2.0
	record_label.scale = Vector2.ONE * 1.3
	record_pop = record_label.create_tween()
	record_pop.tween_property(record_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------
# The notice slot
# ------------------------------------------------------------------

# Puts something in the run's notice slot. `entry`: "kind" (a NOTICE_KINDS
# key), "title", and optionally "icon" (a texture, for a bee), "flowers" (1:
# a flower before the title, 2: one each side), "ink" (the plate's outline)
# and "color" (the title's).
func _notify(entry: Dictionary) -> void:
	entry.merge(NOTICE_KINDS[entry["kind"]])
	entry["at"] = physics_ticks_since_reset
	if notice_now.is_empty() or notice_now["priority"] <= entry["priority"]:
		_notice_display(entry)
		return
	notice_queue.append(entry)
	notice_queue.sort_custom(func(a, b):
		return a["priority"] > b["priority"] or (a["priority"] == b["priority"] and a["at"] < b["at"]))


func _notice_display(entry: Dictionary) -> void:
	# a notice cut off on its way out had already taken the next one off the
	# queue; that one waits again
	if notice_now.has("next"):
		notice_queue.push_front(notice_now["next"])
	_kill_notice_tween()
	notice_now = entry
	_layout_notice(entry)
	notice.visible = true
	notice.position.y = -NOTICE_H - 8.0
	notice_tween = notice.create_tween()
	notice_tween.tween_property(notice, "position:y", NOTICE_Y + top_inset, NOTICE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_record_label(0.0, NOTICE_IN * 0.6)
	if entry["hold"] >= 0.0:
		notice_tween.tween_interval(entry["hold"])
		notice_tween.tween_callback(_notice_leave)


# The notice up goes, and the next one comes: the most important that is
# still fresh, else the rule if it is up, else the record readout again.
func _notice_leave() -> void:
	var next := {}
	var tick_s := 1.0 / Engine.physics_ticks_per_second
	while not notice_queue.is_empty():
		var waiting: Dictionary = notice_queue.pop_front()
		if (physics_ticks_since_reset - waiting["at"]) * tick_s <= waiting["stale"]:
			next = waiting
			break
	if next.is_empty() and rule_on and notice_now.get("kind") != "rule":
		next = _rule_entry()
	_kill_notice_tween()
	# leaving: anything that comes in now takes the slot straight away
	notice_now = {"kind": "leaving", "priority": -1}
	if not next.is_empty() and next["kind"] != "rule":
		notice_now["next"] = next
	notice_tween = notice.create_tween()
	notice_tween.tween_property(notice, "position:y", -NOTICE_H - 8.0, NOTICE_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if next.is_empty():
		notice_tween.tween_callback(_notice_idle)
	else:
		notice_tween.tween_callback(func():
			notice_now.erase("next")
			_notice_display(next))


func _notice_idle() -> void:
	notice_now = {}
	notice.visible = false
	_fade_record_label(1.0, 0.15)
	if record_pop_due:
		_pop_record()


# The record readout steps aside while the slot covers it (by its alpha: the
# tools that hide it for a screenshot set `visible`, which this leaves alone).
func _fade_record_label(to: float, time: float) -> void:
	if record_fade != null and record_fade.is_valid():
		record_fade.kill()
	record_fade = record_label.create_tween()
	record_fade.tween_property(record_label, "modulate:a", to, time)


# The slot belongs to the run: the game over, the bee menu and a new run
# start with it empty (left up, the old banner sat across the "Game Over"
# title on short screens and between the cards of the bee menu).
func _clear_notices() -> void:
	_kill_notice_tween()
	notice_queue.clear()
	notice_now = {}
	rule_on = false
	notice.visible = false
	if record_fade != null and record_fade.is_valid():
		record_fade.kill()
	record_label.modulate.a = 1.0


func _kill_notice_tween() -> void:
	if notice_tween != null and notice_tween.is_valid():
		notice_tween.kill()
	notice_tween = null


# How wide the content of a notice is, padding left out: what comes before
# the title (a bee or a flower), the title, and a flower after it.
func _notice_inner_width(entry: Dictionary) -> float:
	var flower_w: float = ICON_FLOWER[0].length() * UI_CELL
	var flowers: int = entry.get("flowers", 0)
	var w: float = ui_font.get_string_size(entry["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, NOTICE_FONT).x
	if entry.get("icon") != null:
		w += NOTICE_ICON + NOTICE_GAP
	elif flowers > 0:
		w += flower_w + NOTICE_GAP
	if flowers == 2:
		w += flower_w + NOTICE_GAP
	return w


# Sizes the plate to its content (in whole cubes of the grid) and lays the
# content out across it, centred on the screen.
func _layout_notice(entry: Dictionary) -> void:
	var inner := _notice_inner_width(entry)
	var w := minf(NOTICE_MAX_W, ceilf((inner + NOTICE_PAD * 2.0) / UI_CELL) * UI_CELL)
	notice.setup("dark", Vector2(w, NOTICE_H), UI_CELL)
	notice.set_ink(entry.get("ink", Color.WHITE))
	notice.position.x = floorf((SCREEN_W - w) / 2.0)
	var mid: float = notice.face_rect().get_center().y
	var x := floorf((w - inner) / 2.0)
	var tex: Texture2D = entry.get("icon")
	var flowers: int = entry.get("flowers", 0)
	notice_icon.visible = tex != null
	notice_flowers[0].visible = tex == null and flowers > 0
	notice_flowers[1].visible = flowers == 2
	if tex != null:
		notice_icon.texture = tex
		notice_icon.position = Vector2(x, floorf(mid - NOTICE_ICON / 2.0))
		x += NOTICE_ICON + NOTICE_GAP
	elif flowers > 0:
		notice_flowers[0].position = Vector2(x, floorf(mid - notice_flowers[0].size.y / 2.0))
		x += notice_flowers[0].size.x + NOTICE_GAP
	var text_w: float = ui_font.get_string_size(entry["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, NOTICE_FONT).x
	notice_title.text = entry["title"]
	notice_title.add_theme_color_override("font_color", entry.get("color", Color.WHITE))
	notice_title.position = Vector2(x, floorf(mid - notice_title.size.y / 2.0))
	notice_title.size.x = text_w + 2.0
	x += text_w + NOTICE_GAP
	if flowers == 2:
		notice_flowers[1].position = Vector2(x, floorf(mid - notice_flowers[1].size.y / 2.0))
	notice.queue_redraw()


func _on_bee_menu_pressed() -> void:
	if state != State.START and state != State.GAMEOVER:
		return
	# Not in the game over's first instant (the button is where a thumb was
	# tapping), nor while Play Again's ad is opening: the run starts when it
	# closes.
	if state == State.GAMEOVER and _game_over_locked():
		return
	if restart_after_ad and Time.get_ticks_msec() - restart_lock_msec < AD_LOCK_MSEC:
		return
	_clear_notices()
	_refresh_bee_menu()
	# The screen it opened from steps aside: its logo or score would
	# otherwise sit right behind the menu's title and cards.
	start_screen.visible = false
	game_over_screen.visible = false
	bee_menu.visible = true
	_fade_in(bee_menu)


func _on_bee_menu_closed() -> void:
	bee_menu.visible = false
	start_screen.visible = state == State.START
	game_over_screen.visible = state == State.GAMEOVER
	# a bee picked in the menu may be the one the chip offered
	if state == State.GAMEOVER:
		_refresh_goal_chip()


# A card tapped: a bee that has been won goes on (with the button's click);
# a locked one shakes its head, with a lower click and a short buzz, instead
# of doing nothing at all.
func _on_bee_card_pressed(id: String) -> void:
	if not _bee_unlocked(id):
		var card: Dictionary = bee_cards[id]
		_nudge(card["button"])
		_play_sfx(SFX_UI_TAP, SFX_UI_DB, 0.6)
		_vibrate(20)
		return
	_play_sfx(SFX_UI_TAP, SFX_UI_DB)
	_select_bee(id)


func _select_bee(id: String) -> void:
	if SaveData.selected_bee != id:
		SaveData.selected_bee = id
		SaveData.save_data()
		_apply_bee_skin()
	_refresh_bee_menu()


# Won and in use: the lit face and a gold outline, "Em uso" in gold. Won:
# the card alone, the bee's name. Locked: a flat silhouette with a lock, and
# what it takes, worded as the game-over chip words it ("175 flores" /
# "numa partida").
func _refresh_bee_menu() -> void:
	var current := _current_bee_skin()
	for id in bee_cards:
		var card: Dictionary = bee_cards[id]
		var locked: bool = not _bee_unlocked(id)
		var selected: bool = id == current
		card["plate"].set_palette("lit" if selected else "dark")
		card["plate"].set_ink(GOLD if selected else Color(1, 1, 1, 0.45 if locked else 0.9))
		_set_silhouette(card["icon"], locked)
		card["lock"].visible = locked
		card["name"].add_theme_color_override("font_color", Color(1, 1, 1, 0.75) if locked else Color.WHITE)
		var status: Label = card["status"]
		var run: Label = card["run"]
		run.visible = locked
		if locked:
			status.text = _tn("goal_count", BEE_SKINS[id]["score"])
		else:
			status.text = _t("selected") if selected else ""
		status.add_theme_color_override("font_color", GOLD)
	for icon in bee_button_icons:
		icon.texture = load(_bee_icon_path(current))


# A bee not won yet is drawn as its outline only, in one flat colour
# (SILHOUETTE), by a small shader that keeps the icon's alpha.
func _set_silhouette(icon: TextureRect, on: bool) -> void:
	if silhouette_mat == null:
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
uniform vec4 fill : source_color;
void fragment() {
	COLOR = vec4(fill.rgb, fill.a * texture(TEXTURE, UV).a);
}"""
		silhouette_mat = ShaderMaterial.new()
		silhouette_mat.shader = shader
		silhouette_mat.set_shader_parameter("fill", SILHOUETTE)
	icon.material = silhouette_mat if on else null
	icon.modulate = Color.WHITE


# ------------------------------------------------------------------
# The settings panel
# ------------------------------------------------------------------

# The gear on the title and the game over: the switches, the credits and the
# ad privacy, which used to be only in the pause menu (that is, mid-run).
func _on_settings_pressed() -> void:
	if state != State.START and state != State.GAMEOVER:
		return
	if state == State.GAMEOVER and _game_over_locked():
		return
	_place_links(settings_privacy, settings_credits)
	start_screen.visible = false
	game_over_screen.visible = false
	settings_screen.visible = true
	_fade_in(settings_screen)


func _on_settings_closed() -> void:
	settings_screen.visible = false
	credits_screen.visible = false
	start_screen.visible = state == State.START
	game_over_screen.visible = state == State.GAMEOVER


# The ad-privacy link only where the law asks for a way back to the consent
# choices (ads.gd); the credits link under it, or in its place.
func _place_links(privacy: Button, credits: Button) -> void:
	privacy.visible = ads.privacy_options_required()
	credits.position.y = privacy.position.y + (LINK_H if privacy.visible else 0.0)


# A menu coming up fades in over a moment instead of popping.
func _fade_in(c: Control, time := 0.12) -> void:
	if c.has_meta("fade"):
		var old: Tween = c.get_meta("fade")
		if old.is_valid():
			old.kill()
	c.modulate.a = 0.0
	var t := c.create_tween()
	c.set_meta("fade", t)
	t.tween_property(c, "modulate:a", 1.0, time)


# ------------------------------------------------------------------
# Celestial bodies (moon/Jupiter/UFO) — static world-space objects,
# same as a cloud but without the drift: they spawn once near the top of
# the current view and just sit there, so the climb naturally scrolls
# them down and off the bottom of the screen.
# ------------------------------------------------------------------

# `kind` is the model view3d.gd draws for it: "moon", "jupiter" or "ufo".
func _spawn_celestial(kind: String, y_offset_above_view: float) -> void:
	if state != State.PLAYING:
		return
	var body := Node2D.new()
	body.set_meta("kind", kind)
	# Spawn ABOVE the current view (camera_y is the screen's top edge) so it
	# scrolls into sight as the bee keeps climbing, instead of popping into
	# the middle of whatever's already on screen.
	body.position = Vector2(80.0 + randf() * (SCREEN_W - 160.0), camera_y - y_offset_above_view)
	add_child(body)
	celestials.append(body)


func _on_moon_spawn_requested() -> void:
	_spawn_celestial("moon", 120.0)


func _on_jupiter_spawn_requested() -> void:
	_spawn_celestial("jupiter", 140.0)


func _on_ship_spawn_requested() -> void:
	_spawn_celestial("ufo", 100.0)


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return

	var pos: Vector2
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		# A real mouse only. The engine also turns every touch into a mouse
		# click of its own (that is how the buttons work by touch); taking
		# both flapped twice per tap, which played the wingbeat doubled and
		# used two of the sound voices each time.
		pos = event.position
	else:
		return

	var screen_width: float = get_viewport_rect().size.x
	_flap(-1 if pos.x < screen_width / 2.0 else 1)


func _flap(direction: int) -> void:
	if not world_moving:
		world_moving = true
		bee.physics_enabled = true
	bee.flap(direction)
	if not SaveData.seen_tutorial:
		SaveData.seen_tutorial = true
		SaveData.save_data()
	# Taps come fast and in bursts; an identical sample every time reads as
	# a stuck machine gun, so each one is detuned slightly.
	_play_sfx(SFX_FLAP, SFX_FLAP_DB, randf_range(0.92, 1.08))
	has_tapped_once = true


# Keys, for the browser and desktop builds: the arrows or A and D flap,
# space or enter presses the green button on screen, escape or P pauses, or
# closes whatever menu is open, as the back button does on a phone.
func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_LEFT, KEY_A:
			if state == State.PLAYING:
				_flap(-1)
		KEY_RIGHT, KEY_D:
			if state == State.PLAYING:
				_flap(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if bee_menu.visible or credits_screen.visible or settings_screen.visible:
				return
			match state:
				State.START:
					play_button.pressed.emit()
				State.GAMEOVER:
					restart_button.pressed.emit()
				State.PAUSED:
					_on_resume_pressed()
		KEY_ESCAPE, KEY_P:
			match state:
				State.PLAYING, State.RESUMING:
					_on_pause_pressed()
				State.PAUSED:
					if credits_screen.visible:
						credits_screen.visible = false
					else:
						_on_resume_pressed()
				State.START, State.GAMEOVER:
					_close_top_menu()


# Keys come through this node rather than through main.gd's own input,
# because it has to keep listening while the tree is paused (to resume).
class KeyRelay extends Node:
	signal pressed(event: InputEventKey)

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			pressed.emit(event)


# A progress bar on the interface's grid: blocks of two cubes, a cube apart,
# in a trough. `value` (0 to 1) fills it a cube at a time, and anything above
# 0 shows at least one.
class VoxelBar extends Control:
	var blocks := 12
	var cell := 3.0
	var trough: Color
	var empty: Color
	var full: Color
	var value := 0.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()

	func setup(p_blocks: int, p_cell: float, p_trough: Color, p_empty: Color, p_full: Color) -> void:
		blocks = p_blocks
		cell = p_cell
		trough = p_trough
		empty = p_empty
		full = p_full
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2((blocks * 3 + 1) * cell, 4.0 * cell)

	func filled_cells() -> int:
		var cells := blocks * 2
		if value <= 0.0:
			return 0
		return clampi(floori(value * cells), 1, cells)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), trough)
		var lit := filled_cells()
		for i in blocks * 2:
			var x := cell + (i / 2) * 3.0 * cell + (i % 2) * cell
			draw_rect(Rect2(x, cell, cell, 2.0 * cell), full if i < lit else empty)


# ------------------------------------------------------------------
# UI construction (all procedural — see spec 3.2/4.10: real fonts/logo/
# bitmap labels arrive later, placeholder Label/Button nodes stand in).
# ------------------------------------------------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	# Pausing stops the whole scene tree, this layer included — without
	# opting out, the pause menu would freeze the instant it appeared and
	# none of its buttons would ever respond.
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	var keys := KeyRelay.new()
	ui_layer.add_child(keys)
	keys.pressed.connect(_on_key)

	record_label = _make_label(_t("record") % 0, 22, Color(1, 1, 1, 0.9))
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_label.position = Vector2(0, RECORD_Y)
	record_label.size = Vector2(SCREEN_W, 26)
	ui_layer.add_child(record_label)

	score_label = _make_label("0", 64, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(0, SCORE_Y)
	score_label.size = Vector2(SCREEN_W, 68)
	score_label.pivot_offset = score_label.size / 2.0
	ui_layer.add_child(score_label)

	# A digit's glyph and its outline are rasterised the first time they are
	# drawn, at this size, which lands on whichever pickup first needs it.
	# Drawing all ten once at start-up, all but invisible, gets it done early.
	var digits := _make_label("0123456789", 64, Color.WHITE)
	digits.modulate.a = 0.01
	digits.position = score_label.position
	ui_layer.add_child(digits)
	get_tree().create_timer(1.0).timeout.connect(digits.queue_free)

	direction_hint = _build_direction_hint()
	ui_layer.add_child(direction_hint)

	# The run's notices, the near miss's word and the lost flower's marker sit
	# with the HUD, under the pause menu (drawn before it, so its dim covers
	# them). They freeze with the run: what they are in the middle of waits
	# for the resume, instead of running out behind the menu.
	notice = _build_notice()
	ui_layer.add_child(notice)
	phew_label = _make_label(_t("phew"), 26, GOLD)
	phew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phew_label.size = Vector2(80, 30)
	phew_label.pivot_offset = phew_label.size / 2.0
	phew_label.process_mode = Node.PROCESS_MODE_PAUSABLE
	phew_label.visible = false
	ui_layer.add_child(phew_label)
	lost_marker = _build_lost_marker()
	ui_layer.add_child(lost_marker)

	pause_button = _make_corner_button(_build_pixel_icon(ICON_PAUSE, 3.0, Color.WHITE))
	pause_button.visible = false
	pause_button.pressed.connect(_on_pause_pressed)
	ui_layer.add_child(pause_button)
	_apply_top_inset()
	# Asked again once the window has settled: a phone may not have its
	# cut-out to report on the very first frame.
	get_tree().create_timer(0.6).timeout.connect(_apply_top_inset)

	start_screen = _build_start_screen()
	ui_layer.add_child(start_screen)

	pause_screen = _build_pause_screen()
	ui_layer.add_child(pause_screen)

	game_over_screen = _build_game_over_screen()
	ui_layer.add_child(game_over_screen)

	# last, so it opens over the start and game-over screens
	bee_menu = _build_bee_menu()
	ui_layer.add_child(bee_menu)
	_refresh_bee_menu()

	settings_screen = _build_settings_screen()
	ui_layer.add_child(settings_screen)

	# over the pause menu and the settings, which both open it
	credits_screen = _build_credits_screen()
	ui_layer.add_child(credits_screen)

	# The resume's 3-2-1, over everything (the pause menu has gone by then).
	countdown_label = _make_label("3", 96, Color.WHITE)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.size = Vector2(160, 110)
	countdown_label.position = Vector2((SCREEN_W - countdown_label.size.x) / 2.0, screen_h * 0.4 - countdown_label.size.y / 2.0)
	countdown_label.pivot_offset = countdown_label.size / 2.0
	countdown_label.visible = false
	ui_layer.add_child(countdown_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Tinted ink outline, same idea as the art's per-material outlines,
	# plus a soft drop so text still reads over busy scenery.
	label.add_theme_color_override("font_outline_color", UI_INK)
	label.add_theme_constant_override("outline_size", maxi(5, roundi(font_size / 4.5)))
	label.add_theme_color_override("font_shadow_color", Color(UI_INK, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _build_direction_hint() -> Control:
	var hint := Control.new()
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dashed centerline, from under the score down: it used to start at the
	# top edge and ran through the score and the top row (now where the rule
	# plate is). _apply_top_inset moves it down with that row.
	hint_line = Control.new()
	hint_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(hint_line)
	var dash_h := 14.0
	var gap_h := 10.0
	var y := SCORE_Y + 72.0
	while y < screen_h:
		var dash := ColorRect.new()
		dash.color = Color(1, 1, 1, 0.55)
		dash.position = Vector2(SCREEN_W / 2.0 - 2, y)
		dash.size = Vector2(4, dash_h)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint_line.add_child(dash)
		y += dash_h + gap_h

	_add_hint_side(hint, SCREEN_W * 0.25, -1, _t("left"))
	_add_hint_side(hint, SCREEN_W * 0.75, 1, _t("right"))

	return hint


func _add_hint_side(parent: Control, cx: float, dir: int, text: String) -> void:
	var mid_y := screen_h * 0.5

	var rows := []
	for row in ICON_ARROW:
		rows.append(row if dir > 0 else (row as String).reverse())
	var arrow := _build_pixel_icon(rows, 4.0, Color(1, 1, 1, 0.9))
	arrow.position = Vector2(cx, mid_y) - arrow.size / 2.0
	parent.add_child(arrow)

	var label := _make_label(text, 20, Color(1, 1, 1, 0.9))
	label.position = Vector2(cx - 60, mid_y + 30)
	label.size = Vector2(120, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _build_start_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The logo's cubes are a whole number of the screen's own pixels (at
	# 4.3 u a cube, they came out 11 or 12 px at 1080 wide, and the outlines
	# and lit edges with them), and so is where it starts.
	var px := get_viewport().get_final_transform()
	var logo := VoxelLogo.new()
	logo.setup(344.0, px.x.x)
	# Anchored to the bottom like the world behind it (the ground sits flush
	# with the bottom edge, rows stack up from there), so on taller phones
	# the logo keeps the same slot between rows instead of a row running
	# straight through it. On a screen too short for that slot (it would go
	# under the record label) it takes the gap one row lower: clamping it
	# instead put a 16:9 screen's logo right on a row of hedges. (666: the
	# middle of the slot, the bee over the logo taken into account; it was
	# 660, a few units from the row under it.)
	var centre := screen_h - 666.0
	if centre < 140.0:
		centre += OBSTACLE_SPACING
	logo.position = _snap_to_pixels(Vector2((SCREEN_W - logo.size.x) / 2.0, centre - logo.size.y / 2.0), px)
	screen.add_child(logo)

	# The bee in use hovers between the two words, so the title shows the
	# skin that is about to fly.
	var logo_bee := _make_bee_icon(_current_bee_skin(), 74.0)
	bee_button_icons.append(logo_bee)
	var bee_home: Vector2 = logo.position + logo.gap_anchor - Vector2(37.0, 40.0)
	logo_bee.position = bee_home
	screen.add_child(logo_bee)
	var bob := logo_bee.create_tween().set_loops()
	bob.tween_property(logo_bee, "position:y", bee_home.y - 7.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(logo_bee, "position:y", bee_home.y, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	play_button = _make_block_button("green", Vector2(126, 84), 3)
	var play_icon := _build_pixel_icon(ICON_PLAY, 5.0, Color.WHITE)
	var play_face: Control = play_button.get_meta("content")
	play_icon.position = ((play_face.size - play_icon.size) / 2.0 + Vector2(2, 0)).floor()
	play_face.add_child(play_icon)
	# high enough to leave the bee waiting on the grass in view
	play_button.position = Vector2(SCREEN_W / 2.0 - play_button.size.x / 2.0, screen_h - 166)
	play_button.pressed.connect(_on_play_pressed)
	screen.add_child(play_button)
	# a slow breath, so the one thing to tap on this screen asks for it
	play_button.pivot_offset = play_button.size / 2.0
	var breath := play_button.create_tween().set_loops()
	breath.tween_property(play_button, "scale", Vector2.ONE * 1.06, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(play_button, "scale", Vector2.ONE, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(26, play_button.position.y + (play_button.size.y - bee_button.size.y) / 2.0)
	screen.add_child(bee_button)

	var trophy_button := _make_leaderboard_button()
	trophy_button.position = Vector2(SCREEN_W - 26 - trophy_button.size.x, bee_button.position.y)
	screen.add_child(trophy_button)
	title_row = [play_button, bee_button, trophy_button]

	screen.add_child(_make_gear_button())
	return screen


# Where a point of the interface lands on a whole pixel of the screen.
func _snap_to_pixels(p: Vector2, px: Transform2D) -> Vector2:
	var s := px.x.x
	if s < 1.0:
		return p.round()
	return ((p * s + px.origin).round() - px.origin) / s


# The Play button stands over the ground, and the bee waiting on the grass
# showed half hidden under it on a tall screen (the 3D view's tilt draws the
# bottom of the world higher up than the 2D plane has it, the more so the
# taller the screen). The title's bottom row goes up until the bee is clear.
func _fit_title_to_bee() -> void:
	var bee_top: float = view3d.screen_pos_for(
			bee.position - Vector2(0.0, bee.radius * 2.0), Vector2(0.0, camera_y)).y
	# the button breathes 6% bigger, and casts a cube of shadow under it
	var play_bottom := play_button.position.y + play_button.size.y * 1.03 + UI_CELL
	var lift := ceilf(maxf(0.0, play_bottom - (bee_top - TITLE_BEE_CLEAR)))
	for c in title_row:
		c.position.y -= lift


# The settings' gear, in the corner where a run has its pause button.
func _make_gear_button() -> Button:
	var gear := _make_corner_button(_build_pixel_icon(ICON_GEAR, 3.0, Color.WHITE))
	gear.pressed.connect(_on_settings_pressed)
	gear_buttons.append(gear)
	return gear


# The corner's 48 plate, which takes taps CORNER_HIT further towards the top
# and right edges, in the pause button's place (see CORNER_HIT).
func _make_corner_button(icon: Control) -> Button:
	var btn := _make_block_button("dark", Vector2(CORNER_PLATE, CORNER_PLATE), 2, true, Vector2(CORNER_HIT, CORNER_HIT))
	var face: Control = btn.get_meta("content")
	icon.position = ((face.size - icon.size) / 2.0).floor()
	face.add_child(icon)
	btn.position = Vector2(SCREEN_W - CORNER_PLATE - 14.0, PAUSE_Y + top_inset - CORNER_HIT)
	return btn


# Opens the online leaderboard. Hidden while leaderboard.gd is switched off.
func _make_leaderboard_button() -> Button:
	var btn := _make_icon_button(_build_pixel_icon(ICON_TROPHY, 3.0, GOLD), 63.0)
	btn.visible = leaderboard.available
	btn.pressed.connect(func(): leaderboard.show())
	return btn


# Opens the bee menu; shows the bee currently in use. One sits on the start
# screen and one on the game-over screen, so a freshly unlocked bee can be
# picked without restarting the app.
func _make_bee_button() -> Button:
	var icon := _make_bee_icon(_current_bee_skin(), 50.0)
	bee_button_icons.append(icon)
	var btn := _make_icon_button(icon, 63.0)
	btn.pressed.connect(_on_bee_menu_pressed)
	return btn


# Rendered from the models by tools/godot/render_bee_icons.gd.
func _bee_icon_path(id: String) -> String:
	return "res://art/ui/bee_%s.png" % id


func _make_bee_icon(id: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(_bee_icon_path(id))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(side, side)
	return icon


func _build_bee_menu() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)

	var top := maxf(64.0, screen_h * 0.2 - 30.0)
	var title := _make_label(_t("choose_bee"), 38, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top - 2)
	title.size = Vector2(SCREEN_W, 44)
	screen.add_child(title)

	# Three to a row; a last row that isn't full is centred, which leaves the
	# silver bee alone at the bottom like a trophy.
	const CARD := Vector2(114, 138)
	const GAP := 9.0
	const COLS := 3
	var row_count := ceili(BEE_ORDER.size() / float(COLS))
	for i in BEE_ORDER.size():
		var row := i / COLS
		var in_row := mini(COLS, BEE_ORDER.size() - row * COLS)
		var left := (SCREEN_W - (CARD.x * in_row + GAP * (in_row - 1))) / 2.0
		var card := _make_bee_card(BEE_ORDER[i], CARD)
		card.position = Vector2(left + (i % COLS) * (CARD.x + GAP), top + 54 + row * (CARD.y + GAP))
		screen.add_child(card)

	var back := _make_text_button(_t("back"))
	back.position = Vector2(
		(SCREEN_W - back.size.x) / 2.0, top + 54 + row_count * (CARD.y + GAP) + 9)
	back.pressed.connect(_on_bee_menu_closed)
	screen.add_child(back)

	return screen


func _make_bee_card(id: String, card_size: Vector2) -> Button:
	# its click is _on_bee_card_pressed's, which has a different one for "no"
	var btn := _make_block_button("dark", card_size, 2, false)
	btn.pressed.connect(_on_bee_card_pressed.bind(id))
	var face: Control = btn.get_meta("content")

	var icon := _make_bee_icon(id, 76.0)
	icon.position = Vector2(floorf((face.size.x - 76.0) / 2.0), -2)
	face.add_child(icon)
	# a lock over a bee still to be won, at the icon's lower right
	var lock := _build_pixel_icon(ICON_LOCK, UI_CELL, Color.WHITE)
	lock.position = Vector2(face.size.x - lock.size.x - 9.0, 48.0)
	face.add_child(lock)

	var name_label := _make_label(BEE_SKINS[id]["name"], 20, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 70)
	name_label.size = Vector2(face.size.x, 22)
	face.add_child(name_label)

	# "Em uso" on the bee in use; on a locked one what it takes, on two lines
	var status := _make_label("", 17, GOLD)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.position = Vector2(0, 92)
	status.size = Vector2(face.size.x, 18)
	face.add_child(status)
	var run := _make_label(_t("goal_run"), 15, Color(1, 1, 1, 0.8))
	run.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run.position = Vector2(0, 109)
	run.size = Vector2(face.size.x, 16)
	face.add_child(run)

	bee_cards[id] = {"button": btn, "plate": btn.get_meta("plate"), "icon": icon, "lock": lock,
			"name": name_label, "status": status, "run": run}
	return btn


# The run's notice slot (_notify): a dark plate in the top row, sized to
# whatever it says, with a bee's icon or a flower or two beside the title.
func _build_notice() -> Control:
	var plate := VoxelPlate.new()
	plate.setup("dark", Vector2(NOTICE_MAX_W, NOTICE_H), UI_CELL)
	plate.position = Vector2((SCREEN_W - plate.size.x) / 2.0, NOTICE_Y)
	plate.process_mode = Node.PROCESS_MODE_PAUSABLE
	plate.visible = false

	notice_icon = _make_bee_icon("normal", NOTICE_ICON)
	plate.add_child(notice_icon)
	for i in 2:
		var flower := _build_flower_icon("red", UI_CELL)
		plate.add_child(flower)
		notice_flowers.append(flower)
	notice_title = _make_label("", NOTICE_FONT, GOLD)
	notice_title.size = Vector2(NOTICE_MAX_W, 30)
	plate.add_child(notice_title)
	return plate


# A flower of the given kind (red, yellow, blue) on the interface's grid.
func _build_flower_icon(kind: String, cell: float) -> Control:
	var petal: Array = FLOWER_ICON_COLORS[kind]
	return _build_pixel_art(ICON_FLOWER, cell, {"P": petal[0], "L": petal[1],
			"C": FLOWER_ICON_CENTRE[0], "c": FLOWER_ICON_CENTRE[1]})


# The lost flower's marker (_show_lost_marker): a white arrow pointing down,
# the tutorial's arrow turned. Only that: on a 16:9 screen the room between
# "Play Again" and the bottom edge, over the lost flower, takes no more.
func _build_lost_marker() -> Control:
	var down := []
	for x in (ICON_ARROW[0] as String).length():
		var col := ""
		for row in ICON_ARROW:
			col += (row as String)[x]
		down.append(col)
	var marker := _build_pixel_icon(down, UI_CELL, Color.WHITE)
	marker.size.y += UI_CELL               # its shadow, one cube under it
	marker.visible = false
	return marker


func _build_pause_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	# The game-over screen deliberately leaves the world undimmed (spec 4.7),
	# but pause is a different message: the run is suspended, not finished,
	# and the menu has to stay readable over whatever happened to be on
	# screen when the player tapped.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)

	var title := _make_label(_t("paused"), 52, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, screen_h * 0.26)
	title.size = Vector2(SCREEN_W, 56)
	screen.add_child(title)

	var resume_button := _make_text_button(_t("resume"), "green")
	resume_button.position = Vector2((SCREEN_W - resume_button.size.x) / 2.0, screen_h * 0.41)
	resume_button.pressed.connect(_on_resume_pressed)
	screen.add_child(resume_button)

	# Two button heights' worth of air under "Resume" (it was 20 u, and a
	# slip onto "Restart" ends a run, maybe a record one).
	var pause_restart_button := _make_text_button(_t("restart"))
	pause_restart_button.position = Vector2((SCREEN_W - pause_restart_button.size.x) / 2.0,
			resume_button.position.y + resume_button.size.y + 40.0)
	pause_restart_button.pressed.connect(_on_pause_restart_pressed)
	screen.add_child(pause_restart_button)

	var links := _build_settings_block(screen, pause_restart_button.position.y + pause_restart_button.size.y + 26.0)
	privacy_button = links[0]
	credits_button = links[1]
	return screen


# The settings panel, from the gear on the title and the game over: the same
# switches and links as the pause menu (_build_settings_block), and Back.
func _build_settings_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)

	# where the pause menu has "Paused", so the two read as one menu
	var title := _make_label(_t("settings"), 52, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, screen_h * 0.26)
	title.size = Vector2(SCREEN_W, 56)
	screen.add_child(title)

	var links := _build_settings_block(screen, title.position.y + 90.0)
	settings_privacy = links[0]
	settings_credits = links[1]

	var back := _make_text_button(_t("back"))
	back.position = Vector2((SCREEN_W - back.size.x) / 2.0, settings_privacy.position.y + 2.0 * LINK_H + 16.0)
	back.pressed.connect(_on_settings_closed)
	screen.add_child(back)
	return screen


# The switches in a row, each with its name under it, and under them the
# ad-privacy and credits links: one build for the pause menu and the
# settings panel. Returns [privacy link, credits link].
func _build_settings_block(screen: Control, y: float) -> Array:
	var n := TOGGLES.size()
	var left := floorf((SCREEN_W - (TOGGLE_SIDE * n + TOGGLE_GAP * (n - 1))) / 2.0)
	for i in n:
		var spec: Dictionary = TOGGLES[i]
		var id: String = spec["id"]
		var icon := _build_pixel_icon(spec["icon"], 3.0, Color.WHITE)
		var btn := _make_icon_button(icon, TOGGLE_SIDE)
		btn.position = Vector2(left + i * (TOGGLE_SIDE + TOGGLE_GAP), y)
		btn.pressed.connect(_on_toggle_pressed.bind(id))
		screen.add_child(btn)
		var slash := _build_pixel_icon(ICON_SLASH, 3.0, Color.WHITE)
		var face: Control = btn.get_meta("content")
		slash.position = ((face.size - slash.size) / 2.0).floor()
		face.add_child(slash)
		var caption := _make_label(_t(spec["text"]), 18, Color.WHITE)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(btn.position.x - TOGGLE_GAP / 2.0, y + TOGGLE_SIDE + 4.0)
		caption.size = Vector2(TOGGLE_SIDE + TOGGLE_GAP, 20)
		screen.add_child(caption)
		if not toggle_views.has(id):
			toggle_views[id] = []
			match id:
				"music":
					music_note = icon
					music_slash = slash
				"sound":
					sound_icon = icon
					sound_slash = slash
				"vibration":
					vibrate_icon = icon
					vibrate_slash = slash
				"shake":
					shake_icon = icon
					shake_slash = slash
		toggle_views[id].append({"button": btn, "plate": btn.get_meta("plate"), "icon": icon,
				"slash": slash, "caption": caption})
	_show_toggle("music", not SaveData.music_muted)
	_apply_sound_setting()
	_apply_vibration_setting()
	_show_toggle("shake", SaveData.screen_shake)

	# Only shown where privacy law requires a way back to the ad-consent
	# choices (see ads.gd); elsewhere there is nothing to choose, and the
	# credits take its place (_place_links).
	var links_y := y + TOGGLE_SIDE + 4.0 + 20.0 + 6.0
	var privacy := _make_link_button(_t("ad_privacy"))
	privacy.position = Vector2((SCREEN_W - privacy.size.x) / 2.0, links_y)
	privacy.visible = false
	privacy.pressed.connect(func(): ads.show_privacy_options())
	screen.add_child(privacy)

	var credits := _make_link_button(_t("credits"))
	credits.position = Vector2((SCREEN_W - credits.size.x) / 2.0, links_y)
	credits.pressed.connect(_on_credits_pressed)
	screen.add_child(credits)
	return [privacy, credits]


# Credits and licence notices, opened from the pause menu and the settings.
# The text itself is licenses.gd's; it is only put together the first time
# the screen is opened, as most players never will.
func _build_credits_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	var fill := ColorRect.new()
	fill.color = Color(0.11, 0.06, 0.16, 0.97)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(fill)

	credits_title = _make_label(_t("credits"), 44, Color.WHITE)
	credits_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_title.size = Vector2(SCREEN_W, 50)
	screen.add_child(credits_title)

	credits_scroll = ScrollContainer.new()
	credits_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(credits_scroll)
	credits_box = VBoxContainer.new()
	credits_box.custom_minimum_size.x = SCREEN_W - 40.0 - 14.0
	credits_box.add_theme_constant_override("separation", 9)
	credits_scroll.add_child(credits_box)
	_place_credits()

	var back := _make_text_button(_t("back"))
	back.position = Vector2((SCREEN_W - back.size.x) / 2.0, screen_h - 90)
	back.pressed.connect(func(): credits_screen.visible = false)
	screen.add_child(back)
	return screen


# The title starts under the camera's cut-out, as the run's top row does
# (top_inset is only known once the window has settled, so this is redone
# whenever the screen opens).
func _place_credits() -> void:
	credits_title.position = Vector2(0, 34.0 + top_inset)
	credits_scroll.position = Vector2(20, 98.0 + top_inset)
	credits_scroll.size = Vector2(SCREEN_W - 40, screen_h - 98.0 - 108.0 - top_inset)


func _on_credits_pressed() -> void:
	if credits_box.get_child_count() == 0:
		for block in Licenses.blocks(lang):
			var heading: bool = block[0]
			var label := Label.new()
			label.text = block[1]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = credits_box.custom_minimum_size.x
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if heading:
				# headings in the game's own face, the small print in the
				# engine's plain one, which stays readable at that size
				label.add_theme_font_override("font", ui_font)
				label.add_theme_font_size_override("font_size", 26)
				label.add_theme_color_override("font_color", GOLD)
			else:
				label.add_theme_font_size_override("font_size", 12)
				label.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
			credits_box.add_child(label)
	_place_credits()
	credits_scroll.scroll_vertical = 0
	credits_screen.visible = true


# A plain line of text that can be tapped, for the minor entries of the
# menus. As wide as its text, so the caller can centre it, and LINK_H tall,
# a finger's height, whatever the size of its text.
func _make_link_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", ui_font)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	btn.size = Vector2(ui_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0, LINK_H)
	_add_tap_sound(btn)
	return btn


func _build_pixel_icon(rows: Array, cell: float, color: Color) -> Control:
	return _build_pixel_art(rows, cell, {"X": color}, color.a)


# The same for a picture of several colours: `palette` maps each letter of
# the rows to its colour, and a dot is left empty.
func _build_pixel_art(rows: Array, cell: float, palette: Dictionary, shadow_alpha := 1.0) -> Control:
	# Horizontal runs of set pixels collapse into one rect each, so a glyph
	# costs a handful of nodes instead of one per pixel.
	# Drawn twice: an ink copy one cube lower first, as the glyph's shadow.
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols: int = (rows[0] as String).length()
	icon.size = Vector2(cols * cell, rows.size() * cell)
	for shadow in [true, false]:
		for y in rows.size():
			var row: String = rows[y]
			var x := 0
			while x < cols:
				if not palette.has(row[x]):
					x += 1
					continue
				# the shadow is one run across every colour; the picture a
				# run per colour
				var run := 1
				while x + run < cols and palette.has(row[x + run]) and (shadow or row[x + run] == row[x]):
					run += 1
				var block := ColorRect.new()
				block.color = Color(UI_INK, shadow_alpha) if shadow else palette[row[x]]
				block.position = Vector2(x * cell, y * cell + (cell if shadow else 0.0))
				block.size = Vector2(run * cell, cell)
				block.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.add_child(block)
				x += run
	return icon


# A button that is one voxel_plate.gd block: tapping it sinks the block's
# face, and whatever was added to its "content" node (meta) rides down with
# it. The Button itself draws nothing.
# `reach`: how much further the button takes taps than its block shows,
# towards the right (x) and the top (y), as the corner's button does.
func _make_block_button(palette: String, btn_size: Vector2, side_cells := 2, tap_sound := true,
		reach := Vector2.ZERO) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = btn_size + reach
	btn.size = btn_size + reach
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())

	var plate := VoxelPlate.new()
	plate.setup(palette, btn_size, UI_CELL, side_cells)
	plate.position = Vector2(0.0, reach.y)
	btn.add_child(plate)

	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.position = plate.position + plate.face_rect().position
	content.size = plate.face_rect().size
	btn.add_child(content)

	btn.set_meta("plate", plate)
	btn.set_meta("content", content)
	btn.button_down.connect(func():
		plate.pressed = true
		content.position = plate.position + plate.face_rect().position
	)
	btn.button_up.connect(func():
		plate.pressed = false
		content.position = plate.position + plate.face_rect().position
	)
	if tap_sound:
		_add_tap_sound(btn)
	return btn


# A block button made another size (the goal chip, which is taller with its
# progress bar): the block, its face and what is on it follow.
func _size_block_button(btn: Button, btn_size: Vector2) -> void:
	var plate: Control = btn.get_meta("plate")
	var content: Control = btn.get_meta("content")
	btn.custom_minimum_size = btn_size
	btn.size = btn_size
	plate.size = btn_size
	plate.queue_redraw()
	content.position = plate.position + plate.face_rect().position
	content.size = plate.face_rect().size


func _make_icon_button(icon: Control, side: float) -> Button:
	var btn := _make_block_button("dark", Vector2(side, side))
	var face: Control = btn.get_meta("content")
	icon.position = ((face.size - icon.size) / 2.0).floor()
	face.add_child(icon)
	return btn


func _build_game_over_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false

	# The board and the chip move and grow in together (_enter_game_over);
	# _layout_game_over puts them in place for each run.
	go_stack = Control.new()
	go_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(go_stack)

	# One board holds it all: the title and what ended the run used to sit on
	# the world itself, undimmed (spec 4.7, still so), where the flowers in
	# the middle of the screen came up right behind them.
	go_board = VoxelPlate.new()
	go_board.setup("dark", Vector2(GO_W, 216), UI_CELL)
	go_stack.add_child(go_board)
	var w := GO_W
	var col_w := (w - 2.0 * UI_CELL) / 2.0

	go_title = _make_label(_t("game_over"), 48, Color.WHITE)
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_title.position = Vector2(0, 9)
	go_title.size = Vector2(w, 50)
	go_board.add_child(go_title)

	# What ended the run, in a line under the title. That every flower
	# counts is the one rule a new player doesn't expect, and dying to it
	# with no word of explanation reads as the game being broken.
	death_label = _make_label("", 22, Color(1, 1, 1, 0.92))
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.position = Vector2(0, 58)
	death_label.size = Vector2(w, 26)
	go_board.add_child(death_label)

	go_rule = ColorRect.new()
	go_rule.color = VoxelPlate.PALETTES["dark"]["light"]
	go_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_rule.position = Vector2(6.0 * UI_CELL, 90)
	go_rule.size = Vector2(w - 12.0 * UI_CELL, UI_CELL)
	go_board.add_child(go_rule)

	# The run's score and the record side by side...
	col_divider = ColorRect.new()
	col_divider.color = VoxelPlate.PALETTES["dark"]["light"]
	col_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_divider.position = Vector2(UI_CELL + col_w - UI_CELL / 2.0, 105)
	col_divider.size = Vector2(UI_CELL, 69)
	go_board.add_child(col_divider)
	var captions := []
	var values := []
	for i in 2:
		var caption := _make_label([_t("score"), _t("best")][i], 22, Color(1, 1, 1, 0.8))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(UI_CELL + col_w * i, 99)
		caption.size = Vector2(col_w, 26)
		go_board.add_child(caption)
		captions.append(caption)
		var value := _make_label("0", 50, Color.WHITE if i == 0 else GOLD)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.position = Vector2(UI_CELL + col_w * i, 124)
		value.size = Vector2(col_w, 54)
		go_board.add_child(value)
		values.append(value)
	score_caption = captions[0]
	best_caption = captions[1]
	final_score_label = values[0]
	final_best_label = values[1]

	# ...or, when the run beat the record, the score alone under this, in gold
	# (side by side they only said "26 | 26")
	new_record_badge = _make_label(_t("record_beaten"), 26, GOLD)
	new_record_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_record_badge.position = Vector2(0, 96)
	new_record_badge.size = Vector2(w, 30)
	new_record_badge.pivot_offset = new_record_badge.size / 2.0
	new_record_badge.visible = false
	go_board.add_child(new_record_badge)

	# the record beaten, or how close the run came to it (_record_note)
	record_note = _make_label("", 18, Color(1, 1, 1, 0.85))
	record_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_note.position = Vector2(0, 183)
	record_note.size = Vector2(w, 22)
	go_board.add_child(record_note)

	goal_chip = _make_block_button("dark", Vector2(w, 87), 2, false)
	goal_chip.pressed.connect(_on_goal_chip_pressed)
	go_stack.add_child(goal_chip)
	goal_plate = goal_chip.get_meta("plate")
	var chip: Control = goal_chip.get_meta("content")
	goal_icon = _make_bee_icon("normal", 48.0)
	goal_icon.position = Vector2(5, 3)
	chip.add_child(goal_icon)
	goal_title = _make_label("", 22, Color.WHITE)
	goal_title.position = Vector2(59, 3)
	goal_title.size = Vector2(205, 24)
	chip.add_child(goal_title)
	goal_hint = _make_label("", 17, Color(1, 1, 1, 0.88))
	goal_hint.position = Vector2(59, 27)
	goal_hint.size = Vector2(205, 20)
	chip.add_child(goal_hint)
	goal_bar = VoxelBar.new()
	goal_bar.setup(GOAL_BAR_BLOCKS, UI_CELL, VoxelPlate.PALETTES["dark"]["side"],
			VoxelPlate.PALETTES["dark"]["light"], GOLD)
	goal_bar.position = Vector2(59, 54)
	chip.add_child(goal_bar)
	goal_left = _make_label("", 17, Color(1, 1, 1, 0.88))
	goal_left.position = Vector2(goal_bar.position.x + goal_bar.size.x + 8.0, goal_bar.position.y - 5.0)
	goal_left.size = Vector2(chip.size.x - goal_left.position.x - 4.0, 20)
	chip.add_child(goal_left)
	# "go": the chip can be tapped
	goal_go = _build_pixel_icon(ICON_PLAY, 2.0, GOLD)
	goal_go.position = Vector2(chip.size.x - goal_go.size.x - 9.0, 18)
	chip.add_child(goal_go)

	restart_button = _make_text_button(_t("play_again"), "green")
	restart_button.position = Vector2((SCREEN_W - restart_button.size.x) / 2.0, screen_h - 146)
	restart_button.pressed.connect(_on_restart_pressed)
	screen.add_child(restart_button)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(14, restart_button.position.y + 2)
	screen.add_child(bee_button)
	go_bottom = [restart_button, bee_button]

	var trophy_button := _make_leaderboard_button()
	trophy_button.position = Vector2(SCREEN_W - 14 - trophy_button.size.x, bee_button.position.y)
	screen.add_child(trophy_button)

	screen.add_child(_make_gear_button())
	return screen


func _add_tap_sound(btn: BaseButton) -> void:
	# Wired in the factories rather than at each call site, so every button
	# in the game clicks without anyone having to remember to ask for it.
	# Not a button that is off (a key can still press one): it does nothing.
	btn.pressed.connect(func():
		if not btn.disabled:
			_play_sfx(SFX_UI_TAP, SFX_UI_DB))


# Green for the action that starts or continues a run, honey for the rest.
func _make_text_button(text: String, palette := "honey") -> Button:
	var btn := _make_block_button(palette, Vector2(228, 66), 3)
	var face: Control = btn.get_meta("content")
	var label := _make_label(text, 34, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = face.size
	face.add_child(label)
	return btn
