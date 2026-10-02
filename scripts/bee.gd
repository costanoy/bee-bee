extends CharacterBody2D

# The bee's physics. It has no picture of its own: view3d.gd draws the voxel
# model and poses it from `facing`, `tilt`, `dead` and the wingbeat clock.
#
# Physics values ported verbatim from reference-prototype.html — this is the
# validated, tuned feel. Do not adjust without re-testing against it.

const GRAVITY := 1500.0
const FLAP_VELOCITY := -480.0
const MAX_FALL := 700.0
# TEST — a faster bee, bumped twice on request: 230.0 (validated,
# long-standing) -> 275.0 -> 316.0 (another 15%, asked for together with
# the smaller bee below).
const H_SPEED := 316.0
const H_DAMPING := 2.0
# TEST — a smaller bee (hitbox and looks), asked for with the speed bump
# above. Previous (validated, long-standing) value: 16.0. The voxel model
# (tools/blender/make_voxel_bee.py) is built to match this size.
const BEE_R := 12.8
const SCREEN_W := 400.0
# One wingbeat per tap (spec 4.1: on the moment of the tap, not looping
# while airborne); between taps the wings rest.
const FLAP_DURATION := 0.25

var facing := 1  # 1 = right, -1 = left
# The top of what the camera shows, kept up to date by main.gd while a run
# is on. The bee stops there instead of flying out of view: rows exist above
# the screen before they scroll into it, and a bee that outran the camera
# used to die against a hedge nobody could see.
var ceiling_y := -INF
var physics_enabled := false
# Per-skin size and sideways speed (see main.gd BEE_SKINS); the constants
# above are the normal bee's.
var radius := BEE_R
var h_speed := H_SPEED
var _circle: CircleShape2D

# Sideways lean plus nose-down pitch, in radians, as seen facing right.
var tilt := 0.0
var dead := false
# seconds since the last tap; the wingbeat is over once it passes FLAP_DURATION
var _flap_time := FLAP_DURATION


func _ready() -> void:
	var shape := CollisionShape2D.new()
	_circle = CircleShape2D.new()
	_circle.radius = radius
	shape.shape = _circle
	add_child(shape)


# `size` scales the bee's hitbox and `speed` its sideways speed, both
# relative to the normal bee.
func apply_skin(size: float, speed: float) -> void:
	radius = BEE_R * size
	h_speed = H_SPEED * speed
	_circle.radius = radius


func _process(delta: float) -> void:
	_flap_time += delta


func is_flapping() -> bool:
	return not dead and _flap_time < FLAP_DURATION


# 0 at the tap, 1 when the wingbeat is over.
func flap_progress() -> float:
	return clampf(_flap_time / FLAP_DURATION, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not physics_enabled:
		return

	velocity.y += GRAVITY * delta
	if velocity.y > MAX_FALL:
		velocity.y = MAX_FALL

	velocity.x *= exp(-H_DAMPING * delta)

	move_and_slide()

	if position.y < ceiling_y:
		position.y = ceiling_y
		velocity.y = maxf(velocity.y, 0.0)

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
	tilt = lean + dive


func flap(direction: int) -> void:
	velocity.y = FLAP_VELOCITY
	velocity.x = direction * h_speed
	facing = direction
	_flap_time = 0.0


func die() -> void:
	# The bee keeps falling under normal gravity/rotation (spec 4.7 — no
	# impact effect, no reposition); only its face and pose change.
	dead = true


func reset_bee(start_position: Vector2) -> void:
	position = start_position
	velocity = Vector2.ZERO
	facing = 1
	ceiling_y = -INF
	dead = false
	tilt = 0.0
	_flap_time = FLAP_DURATION
	physics_enabled = false
