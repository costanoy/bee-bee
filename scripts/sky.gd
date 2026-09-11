extends Node

# Score-driven background crossfade + celestial bodies (spec 4.9): sun,
# moon, Jupiter and the UFO all have real art now; only stars are still a
# no-op stub (sprite not made yet). Progression is keyed off SCORE, not
# height/time, so the background is a screen-fixed layer (a CanvasLayer
# behind everything) rather than something that scrolls with the world.

const SCREEN_W := 400.0
const SCREEN_H := 800.0

# Score window over which day -> fade -> night crossfades (handoff only pins
# the start point at 75; the width is a reasonable tunable default).
const NIGHT_RAMP_START := 75.0
const NIGHT_RAMP_END := 200.0

const SUN_SCORE := 20

var layer: CanvasLayer
var start_rect: TextureRect
var day_rect: TextureRect
var fade_rect: TextureRect
var night_rect: TextureRect
var sun_sprite: Sprite2D
var moon_sprite: Sprite2D
var jupiter_sprite: Sprite2D
var ufo_sprite: Sprite2D

var sun_spawned := false
var moon_spawned := false
var jupiter_spawned := false
var ship_spawned := false
var shining_bee_unlocked := false

signal stars_should_spawn  # score >= 75, repeats forever — no-op until star sprites exist
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

	# Sun/moon sit above the backgrounds but are still part of this same
	# screen-fixed layer (behind gameplay). Each fades in with the alpha of
	# the background it belongs to, so the sun recedes as night comes in
	# and the moon only really shows once night has actually arrived.
	sun_sprite = _make_celestial_sprite("res://art/sun.png", 597.0, 80.0, Vector2(300.0, 130.0))
	moon_sprite = _make_celestial_sprite("res://art/moon.png", 435.0, 70.0, Vector2(100.0, 130.0))
	# Jupiter/UFO are later, one-time night-sky arrivals (spec 4.9) — same
	# screen-fixed treatment, faded in with the night backdrop like the moon.
	jupiter_sprite = _make_celestial_sprite("res://art/jupiter.png", 690.0, 90.0, Vector2(320.0, 210.0))
	ufo_sprite = _make_celestial_sprite("res://art/ufo.png", 492.0, 70.0, Vector2(160.0, 90.0))


func _make_bg_rect(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.clip_contents = true
	layer.add_child(rect)
	return rect


func _make_celestial_sprite(path: String, content_dim: float, visual_dim: float, pos: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.scale = Vector2.ONE * (visual_dim / content_dim)
	sprite.position = pos
	sprite.modulate.a = 0.0
	layer.add_child(sprite)
	return sprite


func update(delta: float, is_start_phase: bool, score: int) -> void:
	var target_start: float = 1.0 if is_start_phase else 0.0
	start_rect.modulate.a = move_toward(start_rect.modulate.a, target_start, delta * 2.0)

	var t1: float = clamp((score - NIGHT_RAMP_START) / ((NIGHT_RAMP_END - NIGHT_RAMP_START) * 0.5), 0.0, 1.0)
	var t2: float = clamp((score - (NIGHT_RAMP_START + NIGHT_RAMP_END) * 0.5) / ((NIGHT_RAMP_END - NIGHT_RAMP_START) * 0.5), 0.0, 1.0)

	day_rect.modulate.a = 1.0 - t1
	fade_rect.modulate.a = clamp(t1 - t2, 0.0, 1.0)
	night_rect.modulate.a = t2

	if score >= SUN_SCORE:
		sun_spawned = true

	_check_triggers(score)

	sun_sprite.modulate.a = day_rect.modulate.a if sun_spawned else 0.0
	moon_sprite.modulate.a = night_rect.modulate.a if moon_spawned else 0.0
	jupiter_sprite.modulate.a = night_rect.modulate.a if jupiter_spawned else 0.0
	ufo_sprite.modulate.a = night_rect.modulate.a if ship_spawned else 0.0


func _check_triggers(score: int) -> void:
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
