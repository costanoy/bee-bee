extends Node

# Score-driven background crossfade (spec 4.9). Progression is keyed off
# SCORE, not height/time, so the background gradient itself is a
# screen-fixed layer (a CanvasLayer behind everything). The celestial
# bodies (sun/moon/Jupiter/UFO) are NOT part of this layer — they're
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

const SUN_SCORE := 20
const MOON_SCORE := 100
const JUPITER_SCORE := 200
const SHIP_SCORE := 250
const SHINING_BEE_SCORE := 300

var layer: CanvasLayer
var start_rect: TextureRect
var day_rect: TextureRect
var fade_rect: TextureRect
var night_rect: TextureRect

var sun_spawned := false
var moon_spawned := false
var jupiter_spawned := false
var ship_spawned := false
var shining_bee_unlocked := false

signal stars_should_spawn  # score >= 75, repeats forever — no-op until star sprites exist
signal sun_spawn_requested
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


func _make_bg_rect(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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

	_check_triggers(score)


func darkness(score: int) -> float:
	# 0 in full day, 1 in full night, across the same window the backdrop
	# crossfades over.
	return clamp((score - DAY_TO_FADE_START) / (FADE_TO_NIGHT_END - DAY_TO_FADE_START), 0.0, 1.0)


func _check_triggers(score: int) -> void:
	if score >= SUN_SCORE and not sun_spawned:
		sun_spawned = true
		sun_spawn_requested.emit()
	if score >= DAY_TO_FADE_START:
		stars_should_spawn.emit()
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
	sun_spawned = false
	moon_spawned = false
	jupiter_spawned = false
	ship_spawned = false
