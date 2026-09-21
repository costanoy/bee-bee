extends Node

# The celestial bodies (moon/Jupiter/UFO) are NOT part of this layer —
# they're spawned by main.gd as static world-space objects that scroll
# down and off-screen as the bee climbs, same as clouds, just without the
# drift. This script only decides *when* (via signals) and lets main.gd
# own the actual sprite/positioning since it already tracks camera_y.

# The day->night crossfade runs on elapsed SCROLL TIME, not score. Every
# flower is mandatory, so score is really just "how many rows you've
# passed" — tying the sky's own darkness to that made it read as "the
# light dims because I picked a flower," which isn't what nightfall is
# supposed to mean, and it isn't a choice the player is making anyway.
# Time is unconnected to how the run is going, and stretched this wide
# (6.5 minutes end to end) the change is barely visible minute to minute
# — exactly the "suave e pouco perceptível" this was asked to be.
const DAY_TO_DUSK_START := 90.0
const DAY_TO_DUSK_END := 270.0
const DUSK_TO_NIGHT_START := 270.0
const DUSK_TO_NIGHT_END := 480.0

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
# A handful visible ALL the time, day included — outside stars_layer so
# they aren't caught by its night-only fade. The big field above still
# only comes in at dusk; these just keep a few stars around by daylight.
const DAY_STAR_COUNT := 5

# The mountain (with its own painted sun) sits at "the horizon" — a
# screen-space element, not a world sprite, so it doesn't scroll away at
# the normal 1:1 rate the way ground/trees do. It's a ground-covering
# backdrop, not a floating object: full screen width with its bottom
# edge flush against the true bottom of the viewport (that varies by
# device under keep_width, so it's measured at runtime, not a constant),
# so no blue shows below or beside it — only the open sky above the peak
# is meant to show through. It creeps DOWN the screen as the bee climbs,
# at a fraction of the real climb rate, sinking fully below view over a
# couple thousand px — gradual enough to watch happen, unlike a normal
# foreground element's quick few-hundred-px scroll off. Also fades out
# across the DAY_TO_DUSK window as a backstop, so it's never still
# hanging around once night visibly begins even if a run barely climbs.
const MOUNTAIN_CANVAS_W := 768.0
const MOUNTAIN_CANVAS_H := 920.0
const MOUNTAIN_PARALLAX := 0.2

var mountain_scale := 1.0
var mountain_base_top_y := 0.0

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

var day_star_nodes: Array[Node] = []
var day_star_phases: Array[float] = []
var day_star_speeds: Array[float] = []

var mountain: Sprite2D
var mountain_ref_camera_y := 0.0
var mountain_ref_set := false

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

	# Fills the width exactly (400 / canvas width) and sits with its
	# bottom edge flush against the ACTUAL viewport bottom — keep_width
	# stretch means that's not always 800, so it's read at runtime rather
	# than assumed, same reasoning as the star scatter below.
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	mountain_scale = 400.0 / MOUNTAIN_CANVAS_W
	mountain_base_top_y = viewport_h - MOUNTAIN_CANVAS_H * mountain_scale

	mountain = Sprite2D.new()
	mountain.texture = load("res://art/mountain_day.png")
	mountain.centered = false
	mountain.scale = Vector2.ONE * mountain_scale
	mountain.position = Vector2(0.0, mountain_base_top_y)
	layer.add_child(mountain)

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

	# Direct children of `layer`, not `stars_layer` — that Control's own
	# alpha is what the night fade animates, so anything inside it is
	# invisible by day regardless of its own modulate.
	for i in DAY_STAR_COUNT:
		var pos := Vector2(randf() * size.x, randf() * size.y)
		var star := _make_dot(pos)
		layer.add_child(star)
		day_star_nodes.append(star)
		day_star_phases.append(randf() * TAU)
		day_star_speeds.append(1.4 + randf() * 1.8)


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


func update(delta: float, is_start_phase: bool, elapsed_time: float, score: int, camera_y: float) -> void:
	var target_start: float = 1.0 if is_start_phase else 0.0
	start_rect.modulate.a = move_toward(start_rect.modulate.a, target_start, delta * 2.0)

	var t1: float = clamp((elapsed_time - DAY_TO_DUSK_START) / (DAY_TO_DUSK_END - DAY_TO_DUSK_START), 0.0, 1.0)
	var t2: float = clamp((elapsed_time - DUSK_TO_NIGHT_START) / (DUSK_TO_NIGHT_END - DUSK_TO_NIGHT_START), 0.0, 1.0)

	day_rect.modulate.a = 1.0 - t1
	fade_rect.modulate.a = clamp(t1 - t2, 0.0, 1.0)
	night_rect.modulate.a = t2

	# Captured lazily rather than in reset_run(), which fires before
	# main.gd has settled on this run's actual cold-start camera_y — first
	# call after a reset just adopts whatever camera_y it sees as "no
	# climb yet" and every later call measures against that.
	if not mountain_ref_set:
		mountain_ref_camera_y = camera_y
		mountain_ref_set = true
	var climbed: float = mountain_ref_camera_y - camera_y
	mountain.position.y = mountain_base_top_y + MOUNTAIN_PARALLAX * climbed
	mountain.modulate.a = 1.0 - t1

	# Tied to the same t2 that drives the night backdrop, so stars are
	# always exactly as visible as the sky they're sitting in front of —
	# no separate fade window to keep in sync.
	stars_layer.modulate.a = t2
	sky_time += delta
	if t2 > 0.0:
		for i in star_nodes.size():
			var twinkle: float = 0.55 + 0.45 * sin(sky_time * star_speeds[i] + star_phases[i])
			star_nodes[i].modulate.a = twinkle
	# The day stars twinkle the same way at all times, day included — sky_time
	# already advances unconditionally above so this stays in sync with them.
	for i in day_star_nodes.size():
		var twinkle: float = 0.55 + 0.45 * sin(sky_time * day_star_speeds[i] + day_star_phases[i])
		day_star_nodes[i].modulate.a = twinkle

	_check_triggers(score)


func darkness(elapsed_time: float) -> float:
	# 0 in full day, 1 in full night, across the same window the backdrop
	# crossfades over.
	return clamp((elapsed_time - DAY_TO_DUSK_START) / (DUSK_TO_NIGHT_END - DAY_TO_DUSK_START), 0.0, 1.0)


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
	mountain_ref_set = false
