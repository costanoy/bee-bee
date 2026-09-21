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
const REST_FRAME_INDEX := 3
const DEAD_TEXTURE := "res://art/bee_dead.png"

# Content-box width inside each source canvas (see obstacle/flower scripts
# for the same technique) — kept separate per art source since the dead
# pose comes from a differently-sized canvas than the flap frames.
const FLAP_CONTENT_W := 494.0
const DEAD_CONTENT_W := 558.0

var flap_scale_mag: float
var dead_scale_mag: float


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BEE_R
	shape.shape = circle
	add_child(shape)

	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("flap")
	sprite_frames.set_animation_loop("flap", false)
	sprite_frames.set_animation_speed("flap", 22.0)
	for path in FLAP_FRAMES:
		sprite_frames.add_frame("flap", load(path))

	sprite_frames.add_animation("dead")
	sprite_frames.set_animation_loop("dead", false)
	sprite_frames.add_frame("dead", load(DEAD_TEXTURE))

	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = sprite_frames
	sprite.animation = "flap"
	sprite.frame = REST_FRAME_INDEX
	add_child(sprite)

	var visual_span := BEE_R * 2.6
	flap_scale_mag = visual_span / FLAP_CONTENT_W
	dead_scale_mag = visual_span / DEAD_CONTENT_W
	sprite.scale = Vector2.ONE * flap_scale_mag


func _physics_process(delta: float) -> void:
	if not physics_enabled:
		return

	velocity.y += GRAVITY * delta
	if velocity.y > MAX_FALL:
		velocity.y = MAX_FALL

	velocity.x *= exp(-H_DAMPING * delta)

	move_and_slide()

	if position.x < BEE_R:
		position.x = BEE_R
		velocity.x = abs(velocity.x) * 0.4
	elif position.x > SCREEN_W - BEE_R:
		position.x = SCREEN_W - BEE_R
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
	velocity.x = direction * H_SPEED
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


func reset_bee(start_position: Vector2) -> void:
	position = start_position
	velocity = Vector2.ZERO
	facing = 1
	sprite.stop()
	sprite.animation = "flap"
	sprite.frame = REST_FRAME_INDEX
	sprite.scale = Vector2(flap_scale_mag * -facing, flap_scale_mag)
	sprite.rotation = 0.0
	physics_enabled = false
