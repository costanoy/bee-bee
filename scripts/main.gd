extends Node2D

# Bee Bee — root game script. Everything (camera, bee, UI, ground/trees,
# obstacles, flowers, clouds) is built here by code rather than laid out by
# hand in the editor — see HANDOFF_Claude_Code.md section 2 for why.

enum State { START, STARTING, PLAYING, PAUSED, DYING, GAMEOVER }

const SCREEN_W := 400.0

# Physics/gameplay constants ported verbatim from reference-prototype.html.
const OBSTACLE_SPACING := 190.0
# TEST — speed bump requested to see how a faster game feels. Previous
# (long-standing) values, to restore if this doesn't stick:
#   SCROLL_BASE := 78.0
#   SCROLL_MAX := 148.0
const SCROLL_BASE := 90.0
# Prototype's original ramp topped out at 165 (too punishing with mandatory
# flowers + shrinking gaps); 110 was too tame, 135 still felt easy.
const SCROLL_MAX := 170.0
# TEST — shortened from 50 so every run gets tense sooner; top speed and
# narrowest gap are unchanged, they're just reached earlier.
const DIFFICULTY_RAMP_TIME := 35.0
# The bees the player can fly, in menu order. `size` (hitbox and model) and
# `speed` (sideways speed) are relative to the normal bee; `glow` draws the
# model unshaded.
# TEST — the silver bee is smaller and faster, asked for together with the
# skin. size 1.0 / speed 1.0 would make it a purely cosmetic skin again.
const BEE_SKINS := {
	"normal": {"name": "Bee", "trait": "The classic", "model": "bee", "icon": "res://art/ui/bee_normal.png",
			"size": 1.0, "speed": 1.0, "glow": false},
	"shining": {"name": "Silver Bee", "trait": "Smaller & faster", "model": "bee_shining",
			"icon": "res://art/ui/bee_silver.png", "size": 0.8, "speed": 1.15, "glow": true},
}
const BEE_ORDER := ["normal", "shining"]
const GOLD := Color(1, 0.82, 0.18)
# Widest sideways distance, at max difficulty, between a gap and the next
# flower or between a flower and the next gap (see _spawn_row).
const MAX_LEG_HARD := 200.0

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
# mastered around -15.5 dBFS RMS, so this only trims it the rest of the way.
const MUSIC_VOLUME_DB := -6.0
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
const SFX_FLAP_DB := -16.0
const SFX_COLLECT_DB := -7.0
const SFX_HIT_DB := -3.0
const SFX_RECORD_DB := -5.0
const SFX_UI_DB := -12.0
const SFX_NEAR_MISS_DB := -10.0

# TEST — a "near miss" cue (screen shake + whoosh) when the bee grazes past
# a gap edge within this many px without hitting it, requested to see if
# that close-call thrill makes the game more addictive. Margin is on top
# of the bee's radius, i.e. how much closer than "just barely fits" still counts.
const NEAR_MISS_MARGIN := 8.0
const CAMERA_SHAKE_DURATION := 0.18
const CAMERA_SHAKE_MAGNITUDE := 4.0
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

# Clouds and gulls are scenery, so they dim with the sky; left pure white
# they glow against the night like cut-outs. Obstacles and flowers stay
# untinted on purpose — they're what the player has to read at speed.
const NIGHT_DECOR_TINT := Color(0.52, 0.57, 0.74)
# Deep plum used for text outlines and UI backing — the UI's share of the
# art's tinted-ink look.
const UI_INK := Color(0.24, 0.13, 0.32)
const DAY_CLOUD_ALPHA := 0.55
const NIGHT_CLOUD_ALPHA := 0.45

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

const ObstacleScript := preload("res://scripts/obstacle.gd")
const FlowerScript := preload("res://scripts/flower.gd")
const CloudScript := preload("res://scripts/cloud.gd")
const SeagullScript := preload("res://scripts/seagull.gd")
const SkyScript := preload("res://scripts/sky.gd")
const PrerenderedArt := preload("res://scripts/prerendered_art.gd")
const View3DScript := preload("res://scripts/view3d.gd")
# Real-time 3D view (view3d.gd) on top of the unchanged 2D simulation;
# false brings back the 2D sprites.
const USE_3D_VIEW := true
const BeeScript := preload("res://scripts/bee.gd")

# Ground/trees content bounding boxes inside their source canvases (see
# scripts for the other assets' equivalents) — used once, to frame the
# cold-start scene precisely instead of eyeballing it.
const GROUND_CANVAS_W := 1568.0
const GROUND_GRASS_Y0 := 416.0
const GROUND_GRASS_Y1 := 494.0
const TREES_CANVAS_W := 1568.0
const TREES_BOTTOM_Y := 636.0
# The mountain (with its own sun) now lives in sky.gd instead — a
# screen-space horizon element that sinks slowly as the bee climbs
# rather than a world sprite that scrolls away at the normal 1:1 rate.

var state: State = State.START
# The stretch mode is keep_width: the world is always 400 wide, and a phone
# taller than 1:2 (nearly all of them) shows more sky instead of black bars.
# So the visible height is only known at runtime.
var screen_h := 800.0
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
var score := 0
var dying_timer := 0.0
var record_line: Node2D

var obstacles: Array = []
var flowers: Array = []
var clouds: Array = []
var seagulls: Array = []
var celestials: Array = []

var bee: CharacterBody2D
var music: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var collect_step := 0
var physics_ticks_since_reset := 0
var camera: Camera2D
var sky: Node
var ground_sprite: Sprite2D
var trees_sprite: Sprite2D

var ui_font: Font

var score_label: Label
var record_label: Label
var direction_hint: Control
var start_screen: Control
var play_button: TextureButton
var game_over_screen: Control
var final_score_label: Label
var final_best_label: Label
var restart_button: Button
var new_record_badge: Label
var record_pulse: Tween
var pause_button: Button
var pause_screen: Control
var music_note: Control
var music_slash: Control
var view3d: Node3D
var applied_bee_skin := ""
var bee_menu: Control
var bee_notice: Control
var bee_cards := {}                      # skin id -> its card's nodes in the bee menu
var bee_button_icons: Array[TextureRect] = []


func _ready() -> void:
	screen_h = get_viewport_rect().size.y

	# Inter (SIL OFL 1.1, see fonts/Inter-OFL.txt) at its extra-bold weight:
	# a round, chunky face that sits with the 3D candy-toy art, where the
	# old pixel arcade font clashed.
	var inter := FontVariation.new()
	inter.base_font = load("res://fonts/Inter.woff2")
	inter.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	ui_font = inter

	sky = SkyScript.new()
	add_child(sky)
	sky.shining_bee_unlock_requested.connect(_on_shining_bee_unlock_requested)
	sky.moon_spawn_requested.connect(_on_moon_spawn_requested)
	sky.jupiter_spawn_requested.connect(_on_jupiter_spawn_requested)
	sky.ship_spawn_requested.connect(_on_ship_spawn_requested)
	# Stars are self-contained inside sky.gd (fixed screen-space scatter,
	# faded with the same night crossfade) — nothing to wire up here.

	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	camera.enabled = true
	camera.make_current()

	bee = CharacterBody2D.new()
	bee.set_script(BeeScript)
	bee.z_index = 10
	add_child(bee)

	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		# UI taps fire from the pause menu while the tree is frozen, so the
		# pool has to keep running through a pause just like the music does.
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		sfx_pool.append(voice)

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
	music.play()
	_apply_music_mute()

	_reset_to_ground_scene()

	# Everything the player sees of the world is drawn in 3D by view3d.gd,
	# which mirrors this node's 2D simulation. The 2D world (and the 2D sky
	# layer) stays in the tree purely as simulation; the UI layers are
	# CanvasLayers and aren't affected by hiding it.
	if USE_3D_VIEW:
		var view := View3DScript.new()
		add_child(view)
		view.setup(self)
		view3d = view
		_apply_bee_skin()
		visible = false
		sky.layer.visible = false

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


func _notification(what: int) -> void:
	match what:
		# A call, the home button or the notification shade pulled down
		# mid-run would otherwise leave the bee falling with nobody at the
		# controls, or dropped into a fall the moment the app comes back.
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if state == State.PLAYING:
				_on_pause_pressed()
		# quit_on_go_back is off in project.godot, so back no longer kills
		# the app mid-run: it pauses a run, resumes a paused one, and only
		# leaves from the screens where there's nothing to lose.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match state:
				State.PLAYING:
					_on_pause_pressed()
				State.PAUSED:
					_on_resume_pressed()
				State.START, State.GAMEOVER:
					if bee_menu.visible:
						_on_bee_menu_closed()
					else:
						get_tree().quit()


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
	if ground_sprite:
		ground_sprite.queue_free()
		ground_sprite = null
	if trees_sprite:
		trees_sprite.queue_free()
		trees_sprite = null


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

	var ground_y := 0.0
	var ground_scale: float = SCREEN_W / GROUND_CANVAS_W

	# Only the sunset-mountain background variant (sky.reset_run(), just
	# above, is what rolls the pick) pairs with a tree line behind the
	# ground — the city variant's own skyline already reads as the
	# ground-level backdrop, so a second tree sprite would just clash.
	if sky.mountain_has_trees:
		trees_sprite = Sprite2D.new()
		trees_sprite.texture = load(PrerenderedArt.path("trees.png"))
		trees_sprite.centered = false
		var trees_scale: float = SCREEN_W / TREES_CANVAS_W
		trees_sprite.scale = Vector2.ONE * trees_scale
		trees_sprite.position = Vector2(0.0, ground_y - TREES_BOTTOM_Y * trees_scale)
		trees_sprite.z_index = -1
		add_child(trees_sprite)

	ground_sprite = Sprite2D.new()
	ground_sprite.texture = load(PrerenderedArt.path("ground.png"))
	ground_sprite.centered = false
	ground_sprite.scale = Vector2.ONE * ground_scale
	# Align world y=0 with the TOP edge of the grass (GROUND_GRASS_Y0) —
	# the actual surface the bee should stand on — not the middle of the
	# grass+dirt band, which left the bee visibly sunk into the ground.
	ground_sprite.position = Vector2(0.0, ground_y - GROUND_GRASS_Y0 * ground_scale)
	add_child(ground_sprite)

	_apply_bee_skin()
	bee.reset_bee(Vector2(SCREEN_W / 2.0, ground_y - bee.radius))
	world_moving = false
	scrolling_started = false
	launch_timer = 0.0
	time_since_first_flap = 0.0
	camera_shake_time = 0.0

	# Frame the cold-start camera so the ground graphic's own bottom edge
	# sits flush with the bottom of the screen (no floating gap beneath it).
	var ground_bottom_world: float = ground_sprite.position.y + GROUND_GRASS_Y1 * ground_scale
	camera_y = ground_bottom_world - screen_h
	camera.position = Vector2(0.0, camera_y)

	elapsed = 0.0
	score = 0
	dying_timer = 0.0
	# obstacles start comfortably above the ground/trees so they don't
	# overlap the cold-start framing.
	highest_spawn_y = -200.0
	last_gap_x = SCREEN_W / 2.0   # the bee starts centred on the ground
	rows_spawned = 0

	has_tapped_once = SaveData.seen_tutorial
	hint_alpha = 0.0 if SaveData.seen_tutorial else 1.0
	direction_hint.modulate.a = hint_alpha
	direction_hint.visible = hint_alpha > 0.0

	_update_score_label()
	record_label.text = "Record: %d" % SaveData.best_score

	for i in range(6):
		_spawn_row()


func _spawn_row() -> void:
	var y: float = highest_spawn_y - OBSTACLE_SPACING
	highest_spawn_y = y

	var diff: float = _difficulty()
	var gap_width: float = 175.0 - diff * 75.0
	var margin: float = gap_width / 2.0 + 24.0
	var flower_clear: float = gap_width / 2.0 + 20.0

	# The climb goes previous gap -> this row's flower -> this row's gap, and
	# at top speed there's only ~0.55s per leg. Fully random placement could
	# put a flower on the far side of both gaps, a sideways run past what the
	# bee can physically make in that time (~1 row in 35 at max speed), so
	# each leg is capped, tightening with difficulty. Measured against the
	# bee's own flap physics, the worst row at the cap is ~130% of its
	# sustained sideways speed (was 213%), while the average still asks for
	# nearly half of it.
	var max_leg: float = lerp(SCREEN_W, MAX_LEG_HARD, diff)
	var gap_x: float
	var fx: float
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
		move_child(record_line, flower.get_index())

	# Clouds keep appearing through the night, just less often once the sky
	# has started turning (day->fade now begins at score 50 — see sky.gd).
	var cloud_chance: float = 0.85 if score < 50 else 0.35
	if randf() < cloud_chance:
		var cloud := Sprite2D.new()
		cloud.set_script(CloudScript)
		cloud.position = Vector2(randf() * SCREEN_W, y - randf() * 60.0)
		cloud.z_index = -1
		add_child(cloud)
		cloud.setup()
		cloud.self_modulate = _decor_tint()
		cloud.modulate.a = lerp(DAY_CLOUD_ALPHA, NIGHT_CLOUD_ALPHA, sky.darkness(elapsed))
		clouds.append(cloud)

	if score < 75 and randf() < 0.15:
		var gull := AnimatedSprite2D.new()
		gull.set_script(SeagullScript)
		gull.position = Vector2(randf() * SCREEN_W, y - randf() * 80.0)
		gull.z_index = -1
		add_child(gull)
		gull.setup()
		gull.self_modulate = _decor_tint()
		seagulls.append(gull)


const RECORD_LINE_COLOR := Color(1.0, 0.82, 0.25, 0.8)
const RECORD_DASH_W := 10.0
const RECORD_DASH_GAP := 6.0
const RECORD_DASH_H := 2.0


func _spawn_record_line(y: float, flower_x: float) -> void:
	record_line = Node2D.new()
	record_line.position = Vector2(0.0, y)
	add_child(record_line)

	var x := 0.0
	while x < SCREEN_W:
		var dash := ColorRect.new()
		dash.color = RECORD_LINE_COLOR
		dash.position = Vector2(x, -RECORD_DASH_H / 2.0)
		dash.size = Vector2(min(RECORD_DASH_W, SCREEN_W - x), RECORD_DASH_H)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		record_line.add_child(dash)
		x += RECORD_DASH_W + RECORD_DASH_GAP

	# Label goes on the side away from the flower so the two never overlap.
	var label := _make_label("RECORD", 10, RECORD_LINE_COLOR)
	label.size = Vector2(90.0, 14.0)
	label.position.y = -16.0
	if flower_x > SCREEN_W / 2.0:
		label.position.x = 6.0
	else:
		label.position.x = SCREEN_W - 96.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	record_line.add_child(label)


func _flash_record_line() -> void:
	var line := record_line
	record_line = null
	var tween := create_tween()
	tween.tween_property(line, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.08)
	tween.tween_property(line, "modulate", Color(1.8, 1.8, 1.8, 0.0), 0.5)
	tween.tween_callback(line.queue_free)


func _decor_tint() -> Color:
	# Set once at spawn: the fade to night takes minutes, so a cloud's tint
	# never visibly lags in the few seconds it's on screen.
	return Color.WHITE.lerp(NIGHT_DECOR_TINT, sky.darkness(elapsed))


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

	sky.update(delta, state == State.START or state == State.STARTING, elapsed, score, camera_y)


func _start_camera_shake(duration: float, magnitude: float) -> void:
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
			_trigger_game_over()
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
				_trigger_game_over()
				return
			# Track the closest the bee gets to either bar while it's in this
			# row's band — checked once the bee has fully cleared it, below.
			o.near_miss_min_clearance = min(o.near_miss_min_clearance, clearance)
		elif not o.near_miss_checked and o.near_miss_min_clearance <= NEAR_MISS_MARGIN:
			o.near_miss_checked = true
			_trigger_near_miss()

	if time_since_first_flap >= FALL_DEATH_GRACE and bee.position.y - bee.radius > screen_bottom:
		_trigger_game_over()


func _circle_rect_clearance(circle_center: Vector2, radius: float, rect_min: Vector2, rect_max: Vector2) -> float:
	# Standard circle-vs-AABB distance: find the closest point on the rect to
	# the circle's center. Negative means overlap (a hit) — this treats the
	# bee as the circle it actually looks like, instead of the square
	# bounding box the old check used, which let corners of the invisible
	# hitbox clip the roseira before the round bee sprite visually touched
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
	if record_line and score == SaveData.best_score + 1:
		_flash_record_line()


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


func _trigger_game_over() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	dying_timer = 0.0
	pause_button.visible = false
	_start_camera_shake(DEATH_SHAKE_DURATION, DEATH_SHAKE_MAGNITUDE)
	_play_sfx(SFX_HIT, SFX_HIT_DB)
	bee.die()
	# The bee keeps falling under its own gravity — no impact effect, no
	# reposition. Tested and decided explicitly (spec 4.7): any collision FX
	# made the moment feel worse. Only the face/pose changes to the dead
	# sprite; the fall itself is untouched.


func _end_game() -> void:
	state = State.GAMEOVER
	has_finished_a_run = true
	bee.physics_enabled = false

	var beat_record := score > SaveData.best_score
	if beat_record:
		SaveData.best_score = score
		SaveData.save_data()
		_play_sfx(SFX_RECORD, SFX_RECORD_DB)

	final_score_label.text = "Score: %d" % score
	final_best_label.text = "Record: %d" % SaveData.best_score
	record_label.text = "Record: %d" % SaveData.best_score
	if beat_record:
		_show_new_record_badge()
	else:
		_hide_new_record_badge()
	# The game-over panel carries its own score and record, so the in-run
	# HUD above it would just print both a second time.
	_set_hud_visible(false)
	game_over_screen.visible = true


func _set_hud_visible(on: bool) -> void:
	score_label.visible = on
	record_label.visible = on


func _show_new_record_badge() -> void:
	# "Record: n" is centred in a full-width label, so the text itself
	# starts wherever its own width puts it — measure with the label's own
	# font so the badge can't drift if that label is ever restyled.
	var font: Font = final_best_label.get_theme_font("font")
	var font_size: int = final_best_label.get_theme_font_size("font")
	var text_w: float = font.get_string_size(
		final_best_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Centre badge + text as one line; parking the badge beside text that
	# stayed centred on its own pushed the whole line ~28px left of the
	# score beneath it. The 8px gap also absorbs the pulse's growth.
	const GAP := 8.0
	var group_left: float = (SCREEN_W - (new_record_badge.size.x + GAP + text_w)) / 2.0
	new_record_badge.position = Vector2(group_left, final_best_label.position.y)
	var text_left: float = group_left + new_record_badge.size.x + GAP
	final_best_label.position.x = text_left - (SCREEN_W - text_w) / 2.0
	new_record_badge.scale = Vector2.ONE
	new_record_badge.visible = true

	if record_pulse != null and record_pulse.is_valid():
		record_pulse.kill()
	# Bound to the badge rather than to this node so it keeps its own
	# process mode — the UI layer runs through a pause, this script doesn't.
	record_pulse = new_record_badge.create_tween().set_loops()
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE * 1.16, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _hide_new_record_badge() -> void:
	new_record_badge.visible = false
	final_best_label.position.x = 0.0
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
	SaveData.seen_tutorial = true
	SaveData.save_data()

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
	_start_fresh_run()


func _start_fresh_run() -> void:
	# Every fresh run — first launch, replay after a game over, or restart
	# from the pause menu — starts the same way: bee grounded, waiting for
	# the real first flap.
	_reset_to_ground_scene()
	state = State.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	# The badge rides along with the hidden screen, but its loop would keep
	# ticking for the whole next run if it isn't stopped here.
	_hide_new_record_badge()
	pause_button.visible = true
	_set_hud_visible(true)


func _on_pause_pressed() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	pause_button.visible = false
	pause_screen.visible = true
	# Freezing the tree is what actually stops the run: the bee's physics,
	# the drifting clouds and gulls and their wing animations all advance
	# on their own, so gating this script alone would leave the world alive
	# behind the menu.
	get_tree().paused = true


func _on_resume_pressed() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	pause_screen.visible = false
	state = State.PLAYING
	pause_button.visible = true


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
	music_slash.visible = SaveData.music_muted
	music_note.modulate = Color(1, 1, 1, 0.4) if SaveData.music_muted else Color.WHITE


func _update_score_label() -> void:
	score_label.text = "%d" % score


func _on_shining_bee_unlock_requested() -> void:
	# sky.gd asks again every session (its own flag isn't saved); only the
	# first time ever is news.
	if SaveData.shining_bee_unlocked:
		return
	SaveData.shining_bee_unlocked = true
	SaveData.save_data()
	_refresh_bee_menu()
	_show_bee_notice()


# ------------------------------------------------------------------
# Bee skins
# ------------------------------------------------------------------

func _current_bee_skin() -> String:
	var id: String = SaveData.selected_bee
	if not BEE_SKINS.has(id) or (id == "shining" and not SaveData.shining_bee_unlocked):
		return "normal"
	return id


func _apply_bee_skin() -> void:
	var id := _current_bee_skin()
	var skin: Dictionary = BEE_SKINS[id]
	bee.apply_skin(skin["size"], skin["speed"])
	if view3d and applied_bee_skin != id:
		applied_bee_skin = id
		view3d.set_bee_skin(skin["model"], skin["size"], skin["glow"])
	# a bee waiting on the ground keeps its feet on the grass at its new size
	if state == State.START and not world_moving:
		bee.position.y = -bee.radius


func _show_bee_notice() -> void:
	_play_sfx(SFX_RECORD, SFX_RECORD_DB)
	bee_notice.visible = true
	bee_notice.modulate.a = 0.0
	# Bound to the notice itself so it keeps running if the run gets paused.
	var tw := bee_notice.create_tween()
	tw.tween_property(bee_notice, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(bee_notice, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): bee_notice.visible = false)


func _on_bee_menu_pressed() -> void:
	if state != State.START and state != State.GAMEOVER:
		return
	_refresh_bee_menu()
	# The screen it opened from steps aside: its logo or score would
	# otherwise sit right behind the menu's title and cards.
	start_screen.visible = false
	game_over_screen.visible = false
	bee_menu.visible = true


func _on_bee_menu_closed() -> void:
	bee_menu.visible = false
	start_screen.visible = state == State.START
	game_over_screen.visible = state == State.GAMEOVER


func _on_bee_card_pressed(id: String) -> void:
	if id == "shining" and not SaveData.shining_bee_unlocked:
		return
	if SaveData.selected_bee != id:
		SaveData.selected_bee = id
		SaveData.save_data()
		_apply_bee_skin()
	_refresh_bee_menu()


func _refresh_bee_menu() -> void:
	var current := _current_bee_skin()
	for id in bee_cards:
		var card: Dictionary = bee_cards[id]
		var locked: bool = id == "shining" and not SaveData.shining_bee_unlocked
		var selected: bool = id == current
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UI_INK, 0.84)
		style.set_corner_radius_all(18)
		style.set_border_width_all(4 if selected else 3)
		style.border_color = GOLD if selected else Color(1, 1, 1, 0.4 if locked else 0.8)
		for s in ["normal", "hover", "pressed"]:
			card["button"].add_theme_stylebox_override(s, style)
		# a locked bee shows as a dark silhouette
		card["icon"].modulate = Color(0.08, 0.06, 0.14, 0.85) if locked else Color.WHITE
		card["trait"].text = "?" if locked else BEE_SKINS[id]["trait"]
		var status: Label = card["status"]
		if locked:
			status.text = "Score %d to unlock" % SkyScript.SHINING_BEE_SCORE
		else:
			status.text = "Selected" if selected else "Tap to select"
		status.add_theme_color_override("font_color", GOLD if selected else Color(1, 1, 1, 0.85))
	for icon in bee_button_icons:
		icon.texture = load(BEE_SKINS[current]["icon"])


# ------------------------------------------------------------------
# Celestial bodies (moon/Jupiter/UFO) — static world-space objects,
# same as a cloud but without the drift: they spawn once near the top of
# the current view and just sit there, so the climb naturally scrolls
# them down and off the bottom of the screen.
# ------------------------------------------------------------------

func _spawn_celestial(path: String, content_w: float, visual_w: float, y_offset_above_view: float) -> void:
	if state != State.PLAYING:
		return
	var body := Sprite2D.new()
	body.texture = load(path)
	body.scale = Vector2.ONE * (visual_w / content_w)
	# Spawn ABOVE the current view (camera_y is the screen's top edge) so it
	# scrolls into sight as the bee keeps climbing, instead of popping into
	# the middle of whatever's already on screen.
	body.position = Vector2(80.0 + randf() * (SCREEN_W - 160.0), camera_y - y_offset_above_view)
	body.z_index = -1
	add_child(body)
	celestials.append(body)


func _on_moon_spawn_requested() -> void:
	_spawn_celestial(PrerenderedArt.path("moon.png"), 435.0, 80.0, 120.0)


func _on_jupiter_spawn_requested() -> void:
	_spawn_celestial(PrerenderedArt.path("jupiter.png"), 690.0, 100.0, 140.0)


func _on_ship_spawn_requested() -> void:
	_spawn_celestial(PrerenderedArt.path("ufo.png"), 492.0, 80.0, 100.0)


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return

	var pos: Vector2
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return

	var screen_width: float = get_viewport_rect().size.x
	var direction := -1 if pos.x < screen_width / 2.0 else 1

	if not world_moving:
		world_moving = true
		bee.physics_enabled = true
	bee.flap(direction)
	# Taps come fast and in bursts; an identical sample every time reads as
	# a stuck machine gun, so each one is detuned slightly.
	_play_sfx(SFX_FLAP, SFX_FLAP_DB, randf_range(0.92, 1.08))
	has_tapped_once = true


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

	record_label = _make_label("Record: 0", 15, Color(1, 1, 1, 0.8))
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_label.position = Vector2(0, 24)
	record_label.size = Vector2(SCREEN_W, 24)
	ui_layer.add_child(record_label)

	score_label = _make_label("0", 40, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(0, 104)
	score_label.size = Vector2(SCREEN_W, 56)
	ui_layer.add_child(score_label)

	direction_hint = _build_direction_hint()
	ui_layer.add_child(direction_hint)

	pause_button = _make_icon_button(_build_pixel_icon(ICON_PAUSE, 4.0, Color.WHITE), 46.0)
	pause_button.position = Vector2(SCREEN_W - pause_button.size.x - 14, 18)
	pause_button.visible = false
	pause_button.pressed.connect(_on_pause_pressed)
	ui_layer.add_child(pause_button)

	start_screen = _build_start_screen()
	ui_layer.add_child(start_screen)

	pause_screen = _build_pause_screen()
	ui_layer.add_child(pause_screen)

	game_over_screen = _build_game_over_screen()
	ui_layer.add_child(game_over_screen)

	bee_notice = _build_bee_notice()
	ui_layer.add_child(bee_notice)

	# last, so it opens over the start and game-over screens
	bee_menu = _build_bee_menu()
	ui_layer.add_child(bee_menu)
	_refresh_bee_menu()


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
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 4))
	label.add_theme_color_override("font_shadow_color", Color(UI_INK, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _build_direction_hint() -> Control:
	var hint := Control.new()
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# dashed centerline
	var dash_h := 14.0
	var gap_h := 10.0
	var y := 0.0
	while y < screen_h:
		var dash := ColorRect.new()
		dash.color = Color(1, 1, 1, 0.55)
		dash.position = Vector2(SCREEN_W / 2.0 - 2, y)
		dash.size = Vector2(4, dash_h)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_child(dash)
		y += dash_h + gap_h

	_add_hint_side(hint, SCREEN_W * 0.25, -1, "LEFT")
	_add_hint_side(hint, SCREEN_W * 0.75, 1, "RIGHT")

	return hint


func _add_hint_side(parent: Control, cx: float, dir: int, text: String) -> void:
	var mid_y := screen_h * 0.5

	var arrow := Polygon2D.new()
	var pts := PackedVector2Array([
		Vector2(-20, -8), Vector2(4, -8), Vector2(4, -20),
		Vector2(24, 0), Vector2(4, 20), Vector2(4, 8), Vector2(-20, 8),
	])
	for i in range(pts.size()):
		pts[i] = Vector2(pts[i].x * dir, pts[i].y)
	arrow.polygon = pts
	arrow.color = Color(1, 1, 1, 0.85)
	arrow.position = Vector2(cx, mid_y)
	parent.add_child(arrow)

	var label := _make_label(text, 13, Color(1, 1, 1, 0.85))
	label.position = Vector2(cx - 60, mid_y + 34)
	label.size = Vector2(120, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _build_start_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# source is a 1344x768 canvas; the actual logo art is an 822x254
	# content box inside it.
	var logo := Sprite2D.new()
	var logo_atlas := AtlasTexture.new()
	logo_atlas.atlas = load(PrerenderedArt.path("logo.png"))
	logo_atlas.region = Rect2(264, 264, 822, 254)
	logo.texture = logo_atlas
	var logo_visual_w := 320.0
	logo.scale = Vector2.ONE * (logo_visual_w / 822.0)
	# Anchored to the bottom like the world behind it (the ground sits flush
	# with the bottom edge, rows stack up from there), so on taller phones
	# the logo keeps the same slot between rows instead of a row running
	# straight through it. Floored so short screens don't push it under the
	# record label.
	logo.position = Vector2(SCREEN_W / 2.0, maxf(140.0, screen_h - 660.0))
	screen.add_child(logo)

	# source is a 768x768 canvas; the actual button art is a 418x320 content
	# box inside it.
	play_button = _make_image_button(PrerenderedArt.path("play_button.png"), Rect2(174, 224, 418, 320), 110.0)
	play_button.position = Vector2(SCREEN_W / 2.0 - play_button.size.x / 2.0, screen_h - 140)
	play_button.pressed.connect(_on_play_pressed)
	_add_press_feedback(play_button)
	screen.add_child(play_button)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(26, play_button.position.y + (play_button.size.y - bee_button.size.y) / 2.0)
	screen.add_child(bee_button)

	return screen


# Opens the bee menu; shows the bee currently in use. One sits on the start
# screen and one on the game-over screen, so a freshly unlocked bee can be
# picked without restarting the app.
func _make_bee_button() -> Button:
	var icon := _make_bee_icon(_current_bee_skin(), 50.0)
	bee_button_icons.append(icon)
	var btn := _make_icon_button(icon, 62.0)
	btn.pressed.connect(_on_bee_menu_pressed)
	return btn


func _make_bee_icon(id: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(BEE_SKINS[id]["icon"])
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

	var top := screen_h * 0.2
	var title := _make_label("Choose your bee", 24, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top)
	title.size = Vector2(SCREEN_W, 44)
	screen.add_child(title)

	const CARD := Vector2(164, 216)
	const GAP := 16.0
	var left := (SCREEN_W - (CARD.x * BEE_ORDER.size() + GAP * (BEE_ORDER.size() - 1))) / 2.0
	for i in BEE_ORDER.size():
		var card := _make_bee_card(BEE_ORDER[i], CARD)
		card.position = Vector2(left + i * (CARD.x + GAP), top + 70)
		screen.add_child(card)

	var back := _make_text_button("Back")
	back.position = Vector2(SCREEN_W / 2.0 - 115, top + 70 + CARD.y + 34)
	back.pressed.connect(_on_bee_menu_closed)
	screen.add_child(back)

	return screen


func _make_bee_card(id: String, card_size: Vector2) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = card_size
	btn.size = card_size
	btn.pressed.connect(_on_bee_card_pressed.bind(id))
	_add_tap_sound(btn)

	var icon := _make_bee_icon(id, 132.0)
	icon.position = Vector2((card_size.x - 132.0) / 2.0, 8)
	btn.add_child(icon)

	var rows := {}
	for row in [["name", BEE_SKINS[id]["name"], 16, 140.0], ["trait", "", 11, 164.0], ["status", "", 12, 186.0]]:
		var label := _make_label(row[1], row[2], Color.WHITE if row[0] == "name" else Color(1, 1, 1, 0.75))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(0, row[3])
		label.size = Vector2(card_size.x, 22)
		btn.add_child(label)
		rows[row[0]] = label

	bee_cards[id] = {"button": btn, "icon": icon, "trait": rows["trait"], "status": rows["status"]}
	return btn


# A banner for the moment the silver bee is won (score 300, first time ever).
func _build_bee_notice() -> Control:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = Vector2(300, 68)
	panel.position = Vector2((SCREEN_W - panel.size.x) / 2.0, 172)
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_INK, 0.88)
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = GOLD
	panel.add_theme_stylebox_override("panel", style)

	var icon := _make_bee_icon("shining", 60.0)
	icon.position = Vector2(8, 4)
	panel.add_child(icon)

	var title := _make_label("Silver Bee unlocked!", 16, GOLD)
	title.position = Vector2(74, 9)
	title.size = Vector2(220, 26)
	panel.add_child(title)

	var hint := _make_label("Pick it in the bee menu", 11, Color(1, 1, 1, 0.9))
	hint.position = Vector2(74, 38)
	hint.size = Vector2(220, 20)
	panel.add_child(hint)

	return panel


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

	var title := _make_label("Paused", 28, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, screen_h * 0.26)
	title.size = Vector2(SCREEN_W, 50)
	screen.add_child(title)

	var resume_button := _make_text_button("Resume")
	resume_button.position = Vector2(SCREEN_W / 2.0 - 115, screen_h * 0.41)
	resume_button.pressed.connect(_on_resume_pressed)
	screen.add_child(resume_button)

	var pause_restart_button := _make_text_button("Restart")
	pause_restart_button.position = Vector2(SCREEN_W / 2.0 - 115, screen_h * 0.41 + 86)
	pause_restart_button.pressed.connect(_on_pause_restart_pressed)
	screen.add_child(pause_restart_button)

	music_note = _build_pixel_icon(ICON_NOTE, 4.0, Color.WHITE)
	var music_button := _make_icon_button(music_note, 58.0)
	music_button.position = Vector2(
		SCREEN_W / 2.0 - music_button.size.x / 2.0, screen_h * 0.41 + 200)
	music_button.pressed.connect(_on_music_toggle_pressed)
	screen.add_child(music_button)

	music_slash = _build_pixel_icon(ICON_SLASH, 4.0, Color.WHITE)
	music_slash.position = music_note.position
	music_slash.visible = false
	music_button.add_child(music_slash)

	return screen


func _build_pixel_icon(rows: Array, cell: float, color: Color) -> Control:
	# Horizontal runs of set pixels collapse into one rect each, so a glyph
	# costs a handful of nodes instead of one per pixel.
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols: int = (rows[0] as String).length()
	icon.size = Vector2(cols * cell, rows.size() * cell)
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < cols:
			if row[x] != "X":
				x += 1
				continue
			var run := 1
			while x + run < cols and row[x + run] == "X":
				run += 1
			var block := ColorRect.new()
			block.color = color
			block.position = Vector2(x * cell, y * cell)
			block.size = Vector2(run * cell, cell)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.add_child(block)
			x += run
	return icon


func _make_icon_button(icon: Control, side: float) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(side, side)
	btn.size = btn.custom_minimum_size

	# No plate art exists at this shape, and the in-game one sits over live
	# gameplay, so these carry their own backing instead.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_INK, 0.55)
	style.set_corner_radius_all(int(side * 0.3))
	style.set_border_width_all(3)
	style.border_color = Color(1, 1, 1, 0.8)
	style.shadow_color = Color(UI_INK, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", style)

	var style_hover: StyleBoxFlat = style.duplicate()
	style_hover.bg_color = Color(UI_INK, 0.68)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed: StyleBoxFlat = style.duplicate()
	style_pressed.bg_color = Color(UI_INK.lightened(0.25), 0.72)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	icon.position = ((btn.size - icon.size) / 2.0).floor()
	btn.add_child(icon)
	_add_tap_sound(btn)
	return btn


func _build_game_over_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false

	var title := _make_label("Game Over", 28, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, screen_h * 0.32)
	title.size = Vector2(SCREEN_W, 50)
	screen.add_child(title)

	final_best_label = _make_label("Record: 0", 15, Color(1, 0.88, 0.4))
	final_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_best_label.position = Vector2(0, screen_h * 0.32 + 56)
	final_best_label.size = Vector2(SCREEN_W, 26)
	screen.add_child(final_best_label)

	# Sized to its own glyphs rather than given a fixed box, because it gets
	# parked hard against the left edge of the centred "Record: n" text and
	# any slack would read as a crooked gap.
	new_record_badge = _make_label("NEW", 15, Color(1, 0.82, 0.18))
	new_record_badge.size = Vector2(
		ui_font.get_string_size("NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 26)
	new_record_badge.pivot_offset = new_record_badge.size / 2.0
	new_record_badge.visible = false
	screen.add_child(new_record_badge)

	final_score_label = _make_label("Score: 0", 22, Color(1, 0.88, 0.4))
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.position = Vector2(0, screen_h * 0.32 + 86)
	final_score_label.size = Vector2(SCREEN_W, 36)
	screen.add_child(final_score_label)

	restart_button = _make_text_button("Play Again")
	restart_button.position = Vector2(SCREEN_W / 2.0 - 115, screen_h - 146)
	restart_button.pressed.connect(_on_restart_pressed)
	screen.add_child(restart_button)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(14, restart_button.position.y + 2)
	screen.add_child(bee_button)

	return screen


func _make_image_button(path: String, content_rect: Rect2, visual_w: float) -> TextureButton:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = content_rect

	var btn := TextureButton.new()
	btn.texture_normal = atlas
	btn.focus_mode = Control.FOCUS_NONE
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	var visual_h := visual_w * (content_rect.size.y / content_rect.size.x)
	btn.custom_minimum_size = Vector2(visual_w, visual_h)
	btn.size = btn.custom_minimum_size
	_add_tap_sound(btn)
	return btn


func _add_tap_sound(btn: BaseButton) -> void:
	# Wired in the factories rather than at each call site, so every button
	# in the game clicks without anyone having to remember to ask for it.
	btn.pressed.connect(func(): _play_sfx(SFX_UI_TAP, SFX_UI_DB))


func _add_press_feedback(btn: BaseButton) -> void:
	# Mobile has no real hover state, but a tap should still feel
	# responsive — shrink/darken slightly for as long as it's held down,
	# same idea as a hover/active state, and snap back on release.
	btn.pivot_offset = btn.size / 2.0
	btn.button_down.connect(func():
		btn.scale = Vector2.ONE * 0.92
		btn.modulate = Color(0.82, 0.82, 0.82)
	)
	btn.button_up.connect(func():
		btn.scale = Vector2.ONE
		btn.modulate = Color.WHITE
	)


func _make_text_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(230, 66)
	btn.size = Vector2(230, 66)
	btn.add_theme_font_override("font", ui_font)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color(0.1, 0.16, 0.07))

	# Plate art, cropped to its content box (768x768 canvas, content is a
	# 598x262 box inside it) — same technique as the other assets. Only one
	# image exists so hover/pressed reuse it with a modulate tint instead
	# of separate art.
	var plate: Texture2D = load(PrerenderedArt.path("button_plate.png"))
	var style := StyleBoxTexture.new()
	style.texture = plate
	style.region_rect = Rect2(84, 252, 598, 262)
	btn.add_theme_stylebox_override("normal", style)

	var style_hover: StyleBoxTexture = style.duplicate()
	style_hover.modulate_color = Color(1.08, 1.08, 1.08)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed: StyleBoxTexture = style.duplicate()
	style_pressed.modulate_color = Color(0.82, 0.82, 0.82)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	_add_tap_sound(btn)
	return btn
