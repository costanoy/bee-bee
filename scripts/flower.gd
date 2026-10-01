extends Area2D

# A collectible flower. Created entirely by code from main.gd. It has no
# picture of its own: view3d.gd draws the voxel model for its `kind`.

const FLOWER_R := 14.0

# [kind (view3d.gd's flower_<kind> model), colour of its pickup burst]
const KINDS := [
	["red", Color(0.94, 0.2, 0.2)],
	["yellow", Color(1.0, 0.82, 0.25)],
	["blue", Color(0.35, 0.2, 0.95)],
]

var sway_phase := 0.0
var _time := 0.0
var _base_x := 0.0

var kind := "red"
var burst_color := Color(1.0, 0.82, 0.25)
# Set when the bee picks it up; the node lingers half a second after that so
# view3d.gd can play its burst where the flower was.
var collected := false


func setup() -> void:
	sway_phase = randf() * TAU
	_base_x = position.x

	var entry: Array = KINDS[randi() % KINDS.size()]
	kind = entry[0]
	burst_color = entry[1]

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FLOWER_R
	shape.shape = circle
	add_child(shape)

	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: Node) -> void:
	if get_parent().has_method("on_flower_collected"):
		get_parent().on_flower_collected(self)


func _process(delta: float) -> void:
	_time += delta
	# halved on request (was * 3.0): a target that holds still reads better
	var sway := sin(_time * 2.0 + sway_phase) * 1.5
	position.x = _base_x + sway


func play_collect_effect() -> void:
	# Reached from inside body_entered, and Godot refuses a direct write to
	# monitoring during that callback — it errors and leaves it on, so the
	# picked flower would keep detecting for the half second it lingers
	# here for its burst.
	set_deferred("monitoring", false)
	collected = true

	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)
