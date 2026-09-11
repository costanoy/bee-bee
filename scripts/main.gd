extends Node2D

# Bee Bee — root game script. Everything (camera, bee, UI, ground/trees,
# obstacles, flowers, clouds) is built here by code rather than laid out by
# hand in the editor — see HANDOFF_Claude_Code.md section 2 for why.

enum State { START, STARTING, PLAYING, DYING, GAMEOVER }

const SCREEN_W := 400.0
const SCREEN_H := 800.0

# Physics/gameplay constants ported verbatim from reference-prototype.html.
const OBSTACLE_SPACING := 190.0
const SCROLL_BASE := 78.0
const SCROLL_MAX := 165.0
const DIFFICULTY_RAMP_TIME := 50.0
const BEE_R := 16.0

# How long after the first flap the camera waits before it starts climbing
# (the bee itself is already flying/falling normally during this pause).
const SCROLL_START_DELAY := 1.0

const ObstacleScript := preload("res://scripts/obstacle.gd")
const FlowerScript := preload("res://scripts/flower.gd")
const CloudScript := preload("res://scripts/cloud.gd")
const SkyScript := preload("res://scripts/sky.gd")
const BeeScript := preload("res://scripts/bee.gd")

# Ground/trees content bounding boxes inside their source canvases (see
# scripts for the other assets' equivalents) — used once, to frame the
# cold-start scene precisely instead of eyeballing it.
const GROUND_CANVAS_W := 1176.0
const GROUND_GRASS_Y0 := 212.0
const GROUND_GRASS_Y1 := 266.0
const TREES_CANVAS_W := 1568.0
const TREES_BOTTOM_Y := 636.0

var state: State = State.START
var world_moving := false
var scrolling_started := false
var launch_timer := 0.0
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

var bee: CharacterBody2D
var camera: Camera2D
var sky: Node
var ground_sprite: Sprite2D
var trees_sprite: Sprite2D

var pixel_font: FontFile

var score_label: Label
var record_label: Label
var direction_hint: Control
var start_screen: Control
var play_button: Button
var game_over_screen: Control
var final_score_label: Label
var final_best_label: Label
var restart_button: Button


func _ready() -> void:
	# Placeholder-era plain Label/Button text (spec 3.2/4.10) — swapped for
	# a real pixel font (Press Start 2P, OFL-licensed, via Google Fonts)
	# instead of the default UI font. Antialiasing/subpixel positioning off
	# so it renders crisp instead of blurry at these small sizes.
	pixel_font = load("res://fonts/PressStart2P-Regular.ttf")
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	pixel_font.oversampling = 1.0

	sky = SkyScript.new()
	add_child(sky)
	sky.shining_bee_unlock_requested.connect(_on_shining_bee_unlock_requested)
	# Moon/Jupiter/UFO sprites are owned and faded in entirely inside sky.gd.
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

	_build_ui()

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
		o.queue_free()
	for f in flowers:
		f.queue_free()
	for c in clouds:
		c.queue_free()
	obstacles.clear()
	flowers.clear()
	clouds.clear()
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

	var ground_y := 0.0
	var grass_center_local: float = (GROUND_GRASS_Y0 + GROUND_GRASS_Y1) / 2.0
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
	ground_sprite.position = Vector2(0.0, ground_y - grass_center_local * ground_scale)
	add_child(ground_sprite)

	bee.reset_bee(Vector2(SCREEN_W / 2.0, ground_y - BEE_R))
	world_moving = false
	scrolling_started = false
	launch_timer = 0.0

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

	if score < 75 and randf() < 0.6:
		var cloud := Sprite2D.new()
		cloud.set_script(CloudScript)
		cloud.position = Vector2(randf() * SCREEN_W, y - randf() * 60.0)
		cloud.z_index = -1
		add_child(cloud)
		cloud.setup()
		clouds.append(cloud)


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

	if bee.position.y - BEE_R > screen_bottom:
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
	score += 1
	_update_score_label()


func on_bee_hit_obstacle() -> void:
	_trigger_game_over()


func _trigger_game_over() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	dying_timer = 0.0
	bee.die()
	# The bee keeps falling under its own gravity — no impact effect, no
	# reposition. Tested and decided explicitly (spec 4.7): any collision FX
	# made the moment feel worse. Only the face/pose changes to the dead
	# sprite; the fall itself is untouched.


func _end_game() -> void:
	state = State.GAMEOVER
	bee.physics_enabled = false

	if score > SaveData.best_score:
		SaveData.best_score = score
		SaveData.save_data()

	final_score_label.text = "Score: %d" % score
	final_best_label.text = "Record: %d" % SaveData.best_score
	record_label.text = "Record: %d" % SaveData.best_score
	game_over_screen.visible = true


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
	# Every fresh run — first launch or replay after a game over — starts
	# the same way: bee grounded, waiting for the real first flap.
	_reset_to_ground_scene()
	state = State.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false


func _update_score_label() -> void:
	score_label.text = "Score: %d" % score


func _on_shining_bee_unlock_requested() -> void:
	SaveData.shining_bee_unlocked = true
	SaveData.save_data()


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
	has_tapped_once = true


# ------------------------------------------------------------------
# UI construction (all procedural — see spec 3.2/4.10: real fonts/logo/
# bitmap labels arrive later, placeholder Label/Button nodes stand in).
# ------------------------------------------------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	score_label = _make_label("Score: 0", 20, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(0, 24)
	score_label.size = Vector2(SCREEN_W, 40)
	ui_layer.add_child(score_label)

	record_label = _make_label("Record: 0", 11, Color(1, 1, 1, 0.8))
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_label.position = Vector2(0, 66)
	record_label.size = Vector2(SCREEN_W, 24)
	ui_layer.add_child(record_label)

	direction_hint = _build_direction_hint()
	ui_layer.add_child(direction_hint)

	start_screen = _build_start_screen()
	ui_layer.add_child(start_screen)

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

	var label := _make_label(text, 10, Color(1, 1, 1, 0.85))
	label.position = Vector2(cx - 60, mid_y + 34)
	label.size = Vector2(120, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _build_start_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := _make_label("Bee Bee", 26, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 90)
	title.size = Vector2(SCREEN_W, 60)
	screen.add_child(title)

	play_button = _make_round_button()
	play_button.position = Vector2(SCREEN_W / 2.0 - 42, SCREEN_H - 140)
	play_button.pressed.connect(_on_play_pressed)
	screen.add_child(play_button)

	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(-10, -16), Vector2(-10, 16), Vector2(16, 0)])
	tri.color = Color(0.1, 0.16, 0.07)
	tri.position = Vector2(44, 42)
	play_button.add_child(tri)

	return screen


func _build_game_over_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false

	var title := _make_label("Game Over", 22, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, SCREEN_H * 0.32)
	title.size = Vector2(SCREEN_W, 50)
	screen.add_child(title)

	final_score_label = _make_label("Score: 0", 13, Color(1, 0.88, 0.4))
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.position = Vector2(0, SCREEN_H * 0.32 + 56)
	final_score_label.size = Vector2(SCREEN_W, 30)
	screen.add_child(final_score_label)

	final_best_label = _make_label("Record: 0", 13, Color(1, 0.88, 0.4))
	final_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_best_label.position = Vector2(0, SCREEN_H * 0.32 + 90)
	final_best_label.size = Vector2(SCREEN_W, 30)
	screen.add_child(final_best_label)

	restart_button = _make_text_button("Play Again")
	restart_button.position = Vector2(SCREEN_W / 2.0 - 90, SCREEN_H * 0.32 + 150)
	restart_button.pressed.connect(_on_restart_pressed)
	screen.add_child(restart_button)

	return screen


func _make_round_button() -> Button:
	var btn := Button.new()
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(84, 84)
	btn.size = Vector2(84, 84)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.808, 0.239)
	style.set_corner_radius_all(42)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	btn.add_theme_stylebox_override("normal", style)

	var style_hover := style.duplicate()
	style_hover.bg_color = Color(1.0, 0.87, 0.4)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style.duplicate()
	style_pressed.bg_color = Color(0.9, 0.7, 0.15)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	return btn


func _make_text_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(180, 52)
	btn.size = Vector2(180, 52)
	btn.add_theme_font_override("font", pixel_font)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.1, 0.16, 0.07))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.808, 0.239)
	style.set_corner_radius_all(26)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	btn.add_theme_stylebox_override("normal", style)

	var style_hover := style.duplicate()
	style_hover.bg_color = Color(1.0, 0.87, 0.4)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style.duplicate()
	style_pressed.bg_color = Color(0.9, 0.7, 0.15)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	return btn
