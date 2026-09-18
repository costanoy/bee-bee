extends Node

# Score-driven background crossfade (spec 4.9). Progression is keyed off
# SCORE, not height/time, so the background gradient itself is a
# screen-fixed layer (a CanvasLayer behind everything). The celestial
# bodies (moon/Jupiter/UFO) are NOT part of this layer — they're
# spawned by main.gd as static world-space objects that scroll down and
# off-screen as the bee climbs, same as clouds, just without the drift.
# This script only decides *when* (via signals) and lets main.gd own the
# actual sprite/positioning since it already tracks camera_y.

# Wide, gradual ramp — since every flower is mandatory, score climbs
# steadily just from normal play, so a narrow window made the sky change
# feel fast/abrupt. Stretched way out for a slow, smooth fade instead.
const DAY_TO_FADE_START := 50.0
const DAY_TO_FADE_END := 90.0
const FADE_TO_NIGHT_START := 90.0
const FADE_TO_NIGHT_END := 130.0

const MOON_SCORE := 100
const JUPITER_SCORE := 200
const SHIP_SCORE := 250
const SHINING_BEE_SCORE := 300

# The flat bg_day/bg_night fills (each is a single solid color, confirmed by
# sampling the actual files) left the sky reading as an empty void once the
# sparse, slow-drifting clouds weren't around — worse at night, which had
# nothing else at all. Stars are the fix: a fixed scatter across the screen
# (this layer doesn't scroll with the camera, same as the color fills
# behind it), most just a single pixel-art dot, a few a small sparkle glyph
# for variety, all fading in and out in lockstep with the night backdrop
# itself so there's no separate threshold to tune.
const STAR_COUNT := 34
const SPARKLE_COUNT := 6
const SPARKLE_GLYPH := [
	".X.",
	"XXX",
	".X.",
]

var layer: CanvasLayer
var start_rect: TextureRect
var day_rect: TextureRect
var fade_rect: TextureRect
var night_rect: TextureRect

var stars_layer: Control
var star_nodes: Array[Node] = []
var star_phases: Array[float] = []
var star_speeds: Array[float] = []
var sky_time := 0.0

var moon_spawned := false
var jupiter_spawned := false
var ship_spawned := false
var shining_bee_unlocked := false

signal moon_spawn_requested
signal jupiter_spawn_requested
signal ship_spawn_requested
signal shining_bee_unlock_requested


func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = -10
	add_child(layer)

	start_rect = _make_bg_rect("res://art/bg_start.png")
	day_rect = _make_bg_rect("res://art/bg_day.png")
	fade_rect = _make_bg_rect("res://art/bg_fade.png")
	night_rect = _make_bg_rect("res://art/bg_night.png")

	day_rect.modulate.a = 1.0
	fade_rect.modulate.a = 0.0
	night_rect.modulate.a = 0.0
	start_rect.modulate.a = 1.0

	_build_stars()


func _build_stars() -> void:
	stars_layer = Control.new()
	stars_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	stars_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars_layer.modulate.a = 0.0
	layer.add_child(stars_layer)

	# The viewport isn't guaranteed to be exactly 800 tall (keep_width
	# stretch shows more sky on taller phones), so scatter across whatever
	# height is actually visible rather than a fixed constant.
	var size: Vector2 = get_viewport().get_visible_rect().size

	for i in STAR_COUNT + SPARKLE_COUNT:
		var pos := Vector2(randf() * size.x, randf() * size.y)
		var is_sparkle: bool = i >= STAR_COUNT
		var star: Control = _make_sparkle(pos) if is_sparkle else _make_dot(pos)
		stars_layer.add_child(star)
		star_nodes.append(star)
		star_phases.append(randf() * TAU)
		star_speeds.append(1.4 + randf() * 1.8)


func _make_dot(pos: Vector2) -> Control:
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1)
	dot.size = Vector2.ONE * (1.0 if randf() < 0.6 else 2.0)
	dot.position = pos
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _make_sparkle(pos: Vector2) -> Control:
	# Same pixel-grid technique as the pause menu's icons — a plus-shaped
	# glyph reads as a glint rather than just a bigger dot.
	const CELL := 2.0
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = pos
	for y in SPARKLE_GLYPH.size():
		var row: String = SPARKLE_GLYPH[y]
		for x in row.length():
			if row[x] != "X":
				continue
			var px := ColorRect.new()
			px.color = Color(1, 1, 1)
			px.position = Vector2(x * CELL, y * CELL)
			px.size = Vector2.ONE * CELL
			px.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.add_child(px)
	return icon


func _make_bg_rect(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# TextureRect's default expand_mode treats the texture's own pixel size
	# as a floor under the anchors, so the full-rect anchors below only
	# ever won when a background happened to be smaller than the screen in
	# both axes. Every background so far was a flat fill or gradient, so
	# being cropped to the wrong (oversized) rect was never visible; the
	# first background with real content in it (a painted mountain
	# narrower and taller than the viewport) showed only a sliver of the
	# art in one corner instead of a centered cover-crop. Ignoring the
	# texture size lets stretch_mode actually govern the final size.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.clip_contents = true
	layer.add_child(rect)
	return rect


func update(delta: float, is_start_phase: bool, score: int) -> void:
	var target_start: float = 1.0 if is_start_phase else 0.0
	start_rect.modulate.a = move_toward(start_rect.modulate.a, target_start, delta * 2.0)

	var t1: float = clamp((score - DAY_TO_FADE_START) / (DAY_TO_FADE_END - DAY_TO_FADE_START), 0.0, 1.0)
	var t2: float = clamp((score - FADE_TO_NIGHT_START) / (FADE_TO_NIGHT_END - FADE_TO_NIGHT_START), 0.0, 1.0)

	day_rect.modulate.a = 1.0 - t1
	fade_rect.modulate.a = clamp(t1 - t2, 0.0, 1.0)
	night_rect.modulate.a = t2

	# Tied to the same t2 that drives the night backdrop, so stars are
	# always exactly as visible as the sky they're sitting in front of —
	# no separate fade window to keep in sync.
	stars_layer.modulate.a = t2
	if t2 > 0.0:
		sky_time += delta
		for i in star_nodes.size():
			var twinkle: float = 0.55 + 0.45 * sin(sky_time * star_speeds[i] + star_phases[i])
			star_nodes[i].modulate.a = twinkle

	_check_triggers(score)


func darkness(score: int) -> float:
	# 0 in full day, 1 in full night, across the same window the backdrop
	# crossfades over.
	return clamp((score - DAY_TO_FADE_START) / (FADE_TO_NIGHT_END - DAY_TO_FADE_START), 0.0, 1.0)


func _check_triggers(score: int) -> void:
	if score >= MOON_SCORE and not moon_spawned:
		moon_spawned = true
		moon_spawn_requested.emit()
	if score >= JUPITER_SCORE and not jupiter_spawned:
		jupiter_spawned = true
		jupiter_spawn_requested.emit()
	if score >= SHIP_SCORE and not ship_spawned:
		ship_spawned = true
		ship_spawn_requested.emit()
	if score >= SHINING_BEE_SCORE and not shining_bee_unlocked:
		shining_bee_unlocked = true
		shining_bee_unlock_requested.emit()


func reset_run() -> void:
	# Spec 4.9: these are "evento único NA PARTIDA" — one-time per RUN, not
	# per app session — so every fresh run needs to see them again.
	# shining_bee_unlocked stays untouched: that unlock is permanent.
	moon_spawned = false
	jupiter_spawned = false
	ship_spawned = false
