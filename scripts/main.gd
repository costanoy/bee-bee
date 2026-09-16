extends Node2D

# Bee Bee — root game script. Everything (camera, bee, UI, ground/trees,
# obstacles, flowers, clouds) is built here by code rather than laid out by
# hand in the editor — see HANDOFF_Claude_Code.md section 2 for why.

enum State { START, STARTING, PLAYING, PAUSED, DYING, GAMEOVER }

const SCREEN_W := 400.0
const SCREEN_H := 800.0

# Physics/gameplay constants ported verbatim from reference-prototype.html.
const OBSTACLE_SPACING := 190.0
const SCROLL_BASE := 78.0
# Prototype's original ramp topped out at 165 (too punishing with mandatory
# flowers + shrinking gaps); 110 was too tame, 135 still felt easy.
const SCROLL_MAX := 148.0
const DIFFICULTY_RAMP_TIME := 50.0
const BEE_R := 16.0

# How long after the first flap the camera waits before it starts climbing
# (the bee itself is already flying/falling normally during this pause).
const SCROLL_START_DELAY := 1.0
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
const SFX_GAME_OVER := preload("res://audio/sfx_game_over.wav")
const SFX_RECORD := preload("res://audio/sfx_record.wav")
const SFX_UI_TAP := preload("res://audio/sfx_ui_tap.wav")

# Levels live here rather than baked into the files so the mix can be
# balanced without re-rendering. The flap sits lowest by a wide margin:
# it fires on every single tap, and anything louder takes over the mix
# within one run.
const SFX_FLAP_DB := -16.0
const SFX_COLLECT_DB := -7.0
const SFX_HIT_DB := -5.0
const SFX_GAME_OVER_DB := -6.0
const SFX_RECORD_DB := -5.0
const SFX_UI_DB := -12.0

# Enough voices that a flap, a pickup and a jingle can overlap without
# any of them being cut short.
const SFX_VOICES := 8

# Minor-pentatonic steps (A C D E G), the theme's own key. Each flower in
# a run lands one step higher before wrapping, so a good run reads as a
# rising figure rather than the same blip over and over.
const COLLECT_PITCH_STEPS := [1.0, 1.1892, 1.3348, 1.4983, 1.7818]

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
const BeeScript := preload("res://scripts/bee.gd")

# Ground/trees content bounding boxes inside their source canvases (see
# scripts for the other assets' equivalents) — used once, to frame the
# cold-start scene precisely instead of eyeballing it.
const GROUND_CANVAS_W := 1568.0
const GROUND_GRASS_Y0 := 416.0
const GROUND_GRASS_Y1 := 494.0
const TREES_CANVAS_W := 1568.0
const TREES_BOTTOM_Y := 636.0

var state: State = State.START
var world_moving := false
var scrolling_started := false
var launch_timer := 0.0
var time_since_first_flap := 0.0
var has_tapped_once := false
var hint_alpha := 0.0

var elapsed := 0.0
var camera_y := 0.0
var highest_spawn_y := 0.0
var score := 0
var dying_timer := 0.0

var obstacles: Array = []
var flowers: Array = []
var clouds: Array = []
var seagulls: Array = []
var celestials: Array = []

var bee: CharacterBody2D
var music: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var collect_step := 0
var camera: Camera2D
var sky: Node
var ground_sprite: Sprite2D
var trees_sprite: Sprite2D

var pixel_font: FontFile

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


func _ready() -> void:
	# Placeholder-era plain Label/Button text (spec 3.2/4.10) — swapped for
	# a real arcade font (Karmatic Arcade, 1001fonts FFC license — free for
	# commercial/embedded use) instead of the default UI font. Antialiasing/
	# subpixel positioning off so it renders crisp instead of blurry at
	# these small sizes.
	pixel_font = load("res://fonts/KarmaticArcade.ttf")
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	pixel_font.oversampling = 1.0

	sky = SkyScript.new()
	add_child(sky)
	sky.shining_bee_unlock_requested.connect(_on_shining_bee_unlock_requested)
	sky.sun_spawn_requested.connect(_on_sun_spawn_requested)
	sky.moon_spawn_requested.connect(_on_moon_spawn_requested)
	sky.jupiter_spawn_requested.connect(_on_jupiter_spawn_requested)
	sky.ship_spawn_requested.connect(_on_ship_spawn_requested)
	# Stars are the one extension point still pending (no sprite yet).

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

	state = State.START
	start_screen.visible = true
	start_screen.modulate.a = 1.0
	game_over_screen.visible = false


# ------------------------------------------------------------------
# World (re)generation
# ------------------------------------------------------------------

func _clear_world() -> void:
	for o in obstacles:
		# queue_free() is deferred to end-of-frame — stop it from detecting
		# overlaps immediately (the bee's respawn position could land right
		# on top of where an old run's obstacle still physically sits for
		# the rest of this frame).
		o.monitoring = false
		o.queue_free()
	for f in flowers:
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
	if ground_sprite:
		ground_sprite.queue_free()
		ground_sprite = null
	if trees_sprite:
		trees_sprite.queue_free()
		trees_sprite = null


func _reset_to_ground_scene() -> void:
	# Builds a fresh grounded start: bee resting on the ground, trees behind
	# it, world regenerated. Used both at app cold-start and on every
	# "Play Again" after a game over. Per spec 4.8, the one thing this must
	# NOT do is re-randomize the world that's already visible behind the
	# start screen the very first time the player presses Play — callers
	# handle that by only calling this once before that first press.
	_clear_world()
	sky.reset_run()
	collect_step = 0

	var ground_y := 0.0
	var ground_scale: float = SCREEN_W / GROUND_CANVAS_W

	trees_sprite = Sprite2D.new()
	trees_sprite.texture = load("res://art/trees.png")
	trees_sprite.centered = false
	var trees_scale: float = SCREEN_W / TREES_CANVAS_W
	trees_sprite.scale = Vector2.ONE * trees_scale
	trees_sprite.position = Vector2(0.0, ground_y - TREES_BOTTOM_Y * trees_scale)
	trees_sprite.z_index = -1
	add_child(trees_sprite)

	ground_sprite = Sprite2D.new()
	ground_sprite.texture = load("res://art/ground.png")
	ground_sprite.centered = false
	ground_sprite.scale = Vector2.ONE * ground_scale
	# Align world y=0 with the TOP edge of the grass (GROUND_GRASS_Y0) —
	# the actual surface the bee should stand on — not the middle of the
	# grass+dirt band, which left the bee visibly sunk into the ground.
	ground_sprite.position = Vector2(0.0, ground_y - GROUND_GRASS_Y0 * ground_scale)
	add_child(ground_sprite)

	bee.reset_bee(Vector2(SCREEN_W / 2.0, ground_y - BEE_R))
	world_moving = false
	scrolling_started = false
	launch_timer = 0.0
	time_since_first_flap = 0.0

	# Frame the cold-start camera so the ground graphic's own bottom edge
	# sits flush with the bottom of the screen (no floating gap beneath it).
	var ground_bottom_world: float = ground_sprite.position.y + GROUND_GRASS_Y1 * ground_scale
	camera_y = ground_bottom_world - SCREEN_H
	camera.position = Vector2(0.0, camera_y)

	elapsed = 0.0
	score = 0
	dying_timer = 0.0
	# obstacles start comfortably above the ground/trees so they don't
	# overlap the cold-start framing.
	highest_spawn_y = -200.0

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
	var gap_x: float = margin + randf() * (SCREEN_W - margin * 2.0)

	var obstacle := Area2D.new()
	obstacle.set_script(ObstacleScript)
	obstacle.position = Vector2(0, y)
	add_child(obstacle)
	obstacle.setup(gap_x, gap_width)
	obstacles.append(obstacle)

	var fx: float
	while true:
		fx = 30.0 + randf() * (SCREEN_W - 60.0)
		if abs(fx - gap_x) >= gap_width / 2.0 + 20.0:
			break
	var fy: float = y + OBSTACLE_SPACING / 2.0 + (randf() * 40.0 - 20.0)

	var flower := Area2D.new()
	flower.set_script(FlowerScript)
	flower.position = Vector2(fx, fy)
	add_child(flower)
	flower.setup()
	flowers.append(flower)

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
		clouds.append(cloud)

	if score < 75 and randf() < 0.15:
		var gull := AnimatedSprite2D.new()
		gull.set_script(SeagullScript)
		gull.position = Vector2(randf() * SCREEN_W, y - randf() * 80.0)
		gull.z_index = -1
		add_child(gull)
		gull.setup()
		seagulls.append(gull)


# ------------------------------------------------------------------
# Update loop
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.PLAYING:
			_update_playing(delta)
		State.DYING:
			_update_dying(delta)
		_:
			pass

	sky.update(delta, state == State.START or state == State.STARTING, score)


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
		if launch_timer >= SCROLL_START_DELAY:
			scrolling_started = true
	else:
		elapsed += delta

		camera_y -= _current_scroll_speed() * delta
		camera.position = Vector2(0.0, camera_y)

		while highest_spawn_y > camera_y - SCREEN_H:
			_spawn_row()

	# The bee is already flying/falling under normal physics from the first
	# flap onward, camera frozen or not — so the usual rules (missed
	# obstacle, missed flower, falling past the bottom of what's currently
	# visible) apply the whole time, same as they did before the 1s pause
	# existed. The pause only delays the camera's own climb.
	var screen_bottom := camera_y + SCREEN_H
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

	# Every flower is mandatory — letting one scroll off the bottom
	# uncollected ends the run, same as hitting an obstacle (spec change:
	# missing a flower is now a game-over condition, not just a missed point).
	for f in flowers:
		if f.position.y > screen_bottom:
			_trigger_game_over()
			return

	for o in obstacles:
		var band_top: float = o.position.y
		var band_bottom: float = band_top + ObstacleScript.THICK
		if bee.position.y + BEE_R < band_top or bee.position.y - BEE_R > band_bottom:
			continue  # cheap reject before the precise per-bar circle test

		var gap_left: float = o.gap_x - o.gap_width / 2.0
		var gap_right: float = o.gap_x + o.gap_width / 2.0
		var hit := false
		if gap_left > 0.0:
			hit = _circle_hits_rect(bee.position, BEE_R, Vector2(0.0, band_top), Vector2(gap_left, band_bottom))
		if not hit and gap_right < SCREEN_W:
			hit = _circle_hits_rect(bee.position, BEE_R, Vector2(gap_right, band_top), Vector2(SCREEN_W, band_bottom))
		if hit:
			_trigger_game_over()
			return

	if time_since_first_flap >= FALL_DEATH_GRACE and bee.position.y - BEE_R > screen_bottom:
		_trigger_game_over()


func _circle_hits_rect(circle_center: Vector2, radius: float, rect_min: Vector2, rect_max: Vector2) -> bool:
	# Standard circle-vs-AABB test: find the closest point on the rect to
	# the circle's center and check if it's within the radius. This treats
	# the bee as the circle it actually looks like, instead of the square
	# bounding box the old check used — which let corners of the invisible
	# hitbox clip the roseira before the round bee sprite visually touched it.
	var closest := Vector2(
		clamp(circle_center.x, rect_min.x, rect_max.x),
		clamp(circle_center.y, rect_min.y, rect_max.y)
	)
	return circle_center.distance_squared_to(closest) < radius * radius


func _update_dying(delta: float) -> void:
	dying_timer += delta
	if bee.position.y - BEE_R > camera_y + SCREEN_H or dying_timer > 1.4:
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
	flowers.erase(flower)
	flower.play_collect_effect()
	_play_sfx(SFX_COLLECT, SFX_COLLECT_DB, COLLECT_PITCH_STEPS[collect_step])
	collect_step = (collect_step + 1) % COLLECT_PITCH_STEPS.size()
	score += 1
	_update_score_label()


func on_bee_hit_obstacle(obstacle: Area2D) -> void:
	# An obstacle can still be mid-queue_free (deletion is deferred to end
	# of frame) when a fresh run repositions the bee right on top of where
	# it used to be — without this check, that stale, already-cleared
	# obstacle could still fire a real game over on a brand new run.
	if not obstacles.has(obstacle):
		return
	_trigger_game_over()


func _trigger_game_over() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	dying_timer = 0.0
	pause_button.visible = false
	_play_sfx(SFX_HIT, SFX_HIT_DB)
	bee.die()
	# The bee keeps falling under its own gravity — no impact effect, no
	# reposition. Tested and decided explicitly (spec 4.7): any collision FX
	# made the moment feel worse. Only the face/pose changes to the dead
	# sprite; the fall itself is untouched.


func _end_game() -> void:
	state = State.GAMEOVER
	bee.physics_enabled = false

	var beat_record := score > SaveData.best_score
	if beat_record:
		SaveData.best_score = score
		SaveData.save_data()
		_play_sfx(SFX_RECORD, SFX_RECORD_DB)
	else:
		_play_sfx(SFX_GAME_OVER, SFX_GAME_OVER_DB)

	final_score_label.text = "Score: %d" % score
	final_best_label.text = "Record: %d" % SaveData.best_score
	record_label.text = "Record: %d" % SaveData.best_score
	if beat_record:
		_show_new_record_badge()
	else:
		_hide_new_record_badge()
	game_over_screen.visible = true


func _show_new_record_badge() -> void:
	# "Record: n" is centred in a full-width label, so the text itself
	# starts wherever its own width puts it — measure with the label's own
	# font so the badge can't drift if that label is ever restyled.
	var font: Font = final_best_label.get_theme_font("font")
	var font_size: int = final_best_label.get_theme_font_size("font")
	var text_w: float = font.get_string_size(
		final_best_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	new_record_badge.position = Vector2(
		(SCREEN_W - text_w) / 2.0 - new_record_badge.size.x - 8.0,
		final_best_label.position.y)
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

	var tween := create_tween()
	tween.tween_property(start_screen, "modulate:a", 0.0, 1.0)
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
	SaveData.shining_bee_unlocked = true
	SaveData.save_data()


# ------------------------------------------------------------------
# Celestial bodies (sun/moon/Jupiter/UFO) — static world-space objects,
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


func _on_sun_spawn_requested() -> void:
	_spawn_celestial("res://art/sun.png", 597.0, 90.0, 120.0)


func _on_moon_spawn_requested() -> void:
	_spawn_celestial("res://art/moon.png", 435.0, 80.0, 120.0)


func _on_jupiter_spawn_requested() -> void:
	_spawn_celestial("res://art/jupiter.png", 690.0, 100.0, 140.0)


func _on_ship_spawn_requested() -> void:
	_spawn_celestial("res://art/ufo.png", 492.0, 80.0, 100.0)


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
	score_label.position = Vector2(0, 56)
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


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _build_direction_hint() -> Control:
	var hint := Control.new()
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# dashed centerline
	var dash_h := 14.0
	var gap_h := 10.0
	var y := 0.0
	while y < SCREEN_H:
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
	var mid_y := SCREEN_H * 0.5

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
	logo_atlas.atlas = load("res://art/logo.png")
	logo_atlas.region = Rect2(264, 264, 822, 254)
	logo.texture = logo_atlas
	var logo_visual_w := 320.0
	logo.scale = Vector2.ONE * (logo_visual_w / 822.0)
	logo.position = Vector2(SCREEN_W / 2.0, 140.0)
	screen.add_child(logo)

	# source is a 768x768 canvas; the actual button art is a 418x320 content
	# box inside it.
	play_button = _make_image_button("res://art/play_button.png", Rect2(174, 224, 418, 320), 110.0)
	play_button.position = Vector2(SCREEN_W / 2.0 - play_button.size.x / 2.0, SCREEN_H - 140)
	play_button.pressed.connect(_on_play_pressed)
	_add_press_feedback(play_button)
	screen.add_child(play_button)

	return screen


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
	title.position = Vector2(0, SCREEN_H * 0.26)
	title.size = Vector2(SCREEN_W, 50)
	screen.add_child(title)

	var resume_button := _make_text_button("Resume")
	resume_button.position = Vector2(SCREEN_W / 2.0 - 115, SCREEN_H * 0.41)
	resume_button.pressed.connect(_on_resume_pressed)
	screen.add_child(resume_button)

	var pause_restart_button := _make_text_button("Restart")
	pause_restart_button.position = Vector2(SCREEN_W / 2.0 - 115, SCREEN_H * 0.41 + 86)
	pause_restart_button.pressed.connect(_on_pause_restart_pressed)
	screen.add_child(pause_restart_button)

	music_note = _build_pixel_icon(ICON_NOTE, 4.0, Color.WHITE)
	var music_button := _make_icon_button(music_note, 58.0)
	music_button.position = Vector2(
		SCREEN_W / 2.0 - music_button.size.x / 2.0, SCREEN_H * 0.41 + 200)
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
	style.bg_color = Color(0, 0, 0, 0.42)
	style.set_corner_radius_all(9)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.5)
	btn.add_theme_stylebox_override("normal", style)

	var style_hover: StyleBoxFlat = style.duplicate()
	style_hover.bg_color = Color(0, 0, 0, 0.55)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed: StyleBoxFlat = style.duplicate()
	style_pressed.bg_color = Color(0.25, 0.25, 0.25, 0.65)
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
	title.position = Vector2(0, SCREEN_H * 0.32)
	title.size = Vector2(SCREEN_W, 50)
	screen.add_child(title)

	final_best_label = _make_label("Record: 0", 15, Color(1, 0.88, 0.4))
	final_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_best_label.position = Vector2(0, SCREEN_H * 0.32 + 56)
	final_best_label.size = Vector2(SCREEN_W, 26)
	screen.add_child(final_best_label)

	# Sized to its own glyphs rather than given a fixed box, because it gets
	# parked hard against the left edge of the centred "Record: n" text and
	# any slack would read as a crooked gap.
	new_record_badge = _make_label("NEW", 15, Color(1, 0.82, 0.18))
	new_record_badge.size = Vector2(
		pixel_font.get_string_size("NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 26)
	new_record_badge.pivot_offset = new_record_badge.size / 2.0
	new_record_badge.visible = false
	screen.add_child(new_record_badge)

	final_score_label = _make_label("Score: 0", 22, Color(1, 0.88, 0.4))
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.position = Vector2(0, SCREEN_H * 0.32 + 86)
	final_score_label.size = Vector2(SCREEN_W, 36)
	screen.add_child(final_score_label)

	restart_button = _make_text_button("Play Again")
	restart_button.position = Vector2(SCREEN_W / 2.0 - 115, SCREEN_H - 146)
	restart_button.pressed.connect(_on_restart_pressed)
	screen.add_child(restart_button)

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
	btn.add_theme_font_override("font", pixel_font)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color(0.1, 0.16, 0.07))

	# Plate art, cropped to its content box (768x768 canvas, content is a
	# 598x262 box inside it) — same technique as the other assets. Only one
	# image exists so hover/pressed reuse it with a modulate tint instead
	# of separate art.
	var plate: Texture2D = load("res://art/button_plate.png")
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
