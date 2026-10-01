extends CharacterBody2D

# Physics values ported verbatim from reference-prototype.html — this is the
# validated, tuned feel. Do not adjust without re-testing against it.

const GRAVITY := 1500.0
const FLAP_VELOCITY := -480.0
const MAX_FALL := 700.0
# TEST — bumped for a faster-feeling bee, requested to see if it makes the
# game more addictive. Previous (validated, long-standing) value: 230.0.
const H_SPEED := 275.0
const H_DAMPING := 2.0
const BEE_R := 16.0
const SCREEN_W := 400.0

var facing := 1  # 1 = right, -1 = left
var physics_enabled := false
# Per-skin size and sideways speed (see main.gd BEE_SKINS); the constants
# above are the normal bee's.
var radius := BEE_R
var h_speed := H_SPEED
var _circle: CircleShape2D
var _flap_scale_base: float
var _dead_scale_base: float

var sprite: AnimatedSprite2D

# Wing-flap frames, in playback order (wings down -> wings up). Per spec
# 4.1, this animation plays once per flap — on the moment of the tap, not
# looping continuously while airborne — so the last frame (wings up) is
# also used as the resting pose between taps.
const FLAP_FRAMES := [
	"res://art/bee_flap_0.png",
	"res://art/bee_flap_1.png",
	"res://art/bee_flap_2.png",
	"res://art/bee_flap_3.png",
]
const FLAP_FPS := 22.0
const DEAD_TEXTURE := "res://art/bee_dead.png"

# Content-box width inside each source canvas (see obstacle/flower scripts
# for the same technique) — kept separate per art source since the dead
# pose comes from a differently-sized canvas than the flap frames.
const FLAP_CONTENT_W := 494.0
const DEAD_CONTENT_W := 558.0

const PixelArt := preload("res://scripts/pixel_art.gd")
const PrerenderedArt := preload("res://scripts/prerendered_art.gd")

var flap_scale_mag: float
var dead_scale_mag: float
var flap_is_pixel := false
var dead_is_pixel := false
var rest_frame := 0


func _ready() -> void:
	var shape := CollisionShape2D.new()
	_circle = CircleShape2D.new()
	_circle.radius = radius
	shape.shape = _circle
	add_child(shape)

	var visual_span := BEE_R * 2.6

	# Each set (flap cycle, dead pose) picks the first complete source among
	# the 3D renders, the pixel art, and the original art. The pixel flap
	# only switches once all four frames exist — a half-swapped cycle would
	# jump between two art styles every tap. The 3D beat has its own,
	# longer frame count: however many consecutive frames are on disk.
	var fps := FLAP_FPS
	var flap_frames: Array = _frame_run(PrerenderedArt)
	if not flap_frames.is_empty():
		flap_scale_mag = visual_span / PrerenderedArt.BEE_CONTENT_W
		fps = PrerenderedArt.FLAP_FPS
	else:
		flap_frames = _frame_set(PixelArt, FLAP_FRAMES.size())
		flap_is_pixel = not flap_frames.is_empty()
		if flap_is_pixel:
			flap_scale_mag = PixelArt.SCALE
		else:
			flap_frames = FLAP_FRAMES.map(func(p): return load(p))
			flap_scale_mag = visual_span / FLAP_CONTENT_W

	var dead_tex := PrerenderedArt.texture("bee_dead.png")
	if dead_tex:
		dead_scale_mag = visual_span / PrerenderedArt.BEE_CONTENT_W
	else:
		dead_tex = PixelArt.texture("bee_dead.png")
		dead_is_pixel = dead_tex != null
		if dead_is_pixel:
			dead_scale_mag = PixelArt.SCALE
		else:
			dead_tex = load(DEAD_TEXTURE)
			dead_scale_mag = visual_span / DEAD_CONTENT_W

	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("flap")
	sprite_frames.set_animation_loop("flap", false)
	sprite_frames.set_animation_speed("flap", fps)
	for tex in flap_frames:
		sprite_frames.add_frame("flap", tex)
	rest_frame = flap_frames.size() - 1

	sprite_frames.add_animation("dead")
	sprite_frames.set_animation_loop("dead", false)
	sprite_frames.add_frame("dead", dead_tex)

	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = sprite_frames
	sprite.animation = "flap"
	sprite.frame = rest_frame
	add_child(sprite)

	sprite.scale = Vector2.ONE * flap_scale_mag
	PixelArt.apply_filter(sprite, flap_is_pixel)
	_flap_scale_base = flap_scale_mag
	_dead_scale_base = dead_scale_mag


# `size` scales the bee (hitbox and sprite) and `speed` its sideways speed,
# both relative to the normal bee.
func apply_skin(size: float, speed: float) -> void:
	radius = BEE_R * size
	h_speed = H_SPEED * speed
	_circle.radius = radius
	flap_scale_mag = _flap_scale_base * size
	dead_scale_mag = _dead_scale_base * size
	var mag := dead_scale_mag if sprite.animation == "dead" else flap_scale_mag
	sprite.scale = Vector2(mag * -facing, mag)


# bee_flap_0..n-1 from `source`, or empty unless every frame exists.
func _frame_set(source, count: int) -> Array:
	var frames := []
	for i in count:
		var tex: Texture2D = source.texture("bee_flap_%d.png" % i)
		if tex == null:
			return []
		frames.append(tex)
	return frames


# bee_flap_0, _1, ... from `source` for as long as they keep existing.
func _frame_run(source) -> Array:
	var frames := []
	var tex: Texture2D = source.texture("bee_flap_0.png")
	while tex:
		frames.append(tex)
		tex = source.texture("bee_flap_%d.png" % frames.size())
	return frames


func _physics_process(delta: float) -> void:
	if not physics_enabled:
		return

	velocity.y += GRAVITY * delta
	if velocity.y > MAX_FALL:
		velocity.y = MAX_FALL

	velocity.x *= exp(-H_DAMPING * delta)

	move_and_slide()

	if position.x < radius:
		position.x = radius
		velocity.x = abs(velocity.x) * 0.4
	elif position.x > SCREEN_W - radius:
		position.x = SCREEN_W - radius
		velocity.x = -abs(velocity.x) * 0.4

	# Sideways lean from the prototype (validated, keep as-is) plus an extra
	# nose-down pitch that grows with fall speed — the coast/glide between
	# taps should visibly dip forward, not just go level as the sideways
	# lean decays.
	var lean: float = clamp(velocity.x / 300.0, -0.5, 0.5)
	var dive: float = clamp(velocity.y / MAX_FALL, 0.0, 1.0) * 0.35
	sprite.rotation = lean + dive


func flap(direction: int) -> void:
	velocity.y = FLAP_VELOCITY
	velocity.x = direction * h_speed
	facing = direction
	# the flap art faces left natively (unflipped) — mirror it to face right.
	sprite.scale = Vector2(flap_scale_mag * -facing, flap_scale_mag)
	# play() alone won't rewind to frame 0 if "flap" was already the
	# assigned animation (e.g. sitting stopped on its last/rest frame) —
	# force frame 0 explicitly so every tap restarts the flap from the top.
	sprite.frame = 0
	sprite.play("flap")


func die() -> void:
	# Swaps to the dead-bee pose; the bee keeps falling under normal
	# gravity/rotation (spec 4.7 — no impact effect, no reposition), only
	# the face/pose changes.
	sprite.stop()
	sprite.animation = "dead"
	sprite.frame = 0
	sprite.scale = Vector2(dead_scale_mag * -facing, dead_scale_mag)
	PixelArt.apply_filter(sprite, dead_is_pixel)


func reset_bee(start_position: Vector2) -> void:
	position = start_position
	velocity = Vector2.ZERO
	facing = 1
	sprite.stop()
	sprite.animation = "flap"
	sprite.frame = rest_frame
	sprite.scale = Vector2(flap_scale_mag * -facing, flap_scale_mag)
	PixelArt.apply_filter(sprite, flap_is_pixel)
	sprite.rotation = 0.0
	physics_enabled = false
