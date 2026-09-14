extends Node

# Score-driven background crossfade (spec 4.9). Progression is keyed off
# SCORE, not height/time, so the background gradient itself is a
# screen-fixed layer (a CanvasLayer behind everything). The celestial
# bodies (sun/moon/Jupiter/UFO) are NOT part of this layer — they're
# spawned by main.gd as static world-space objects that scroll down and
# off-screen as the bee climbs, same as clouds, just without the drift.
# This script only decides *when* (via signals) and lets main.gd own the
# actual sprite/positioning since it already tracks camera_y.

const NIGHT_RAMP_START := 75.0
const NIGHT_RAMP_END := 200.0

const SUN_SCORE := 20

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

	var t1: float = clamp((score - NIGHT_RAMP_START) / ((NIGHT_RAMP_END - NIGHT_RAMP_START) * 0.5), 0.0, 1.0)
	var t2: float = clamp((score - (NIGHT_RAMP_START + NIGHT_RAMP_END) * 0.5) / ((NIGHT_RAMP_END - NIGHT_RAMP_START) * 0.5), 0.0, 1.0)

	day_rect.modulate.a = 1.0 - t1
	fade_rect.modulate.a = clamp(t1 - t2, 0.0, 1.0)
	night_rect.modulate.a = t2

	_check_triggers(score)


func _check_triggers(score: int) -> void:
	if score >= SUN_SCORE and not sun_spawned:
		sun_spawned = true
		sun_spawn_requested.emit()
	if score >= 75:
		stars_should_spawn.emit()
	if score >= 150 and not moon_spawned:
		moon_spawned = true
		moon_spawn_requested.emit()
	if score >= 250 and not jupiter_spawned:
		jupiter_spawned = true
		jupiter_spawn_requested.emit()
	if score >= 400 and not ship_spawned:
		ship_spawned = true
		ship_spawn_requested.emit()
	if score >= 500 and not shining_bee_unlocked:
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
