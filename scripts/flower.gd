extends Area2D

# A collectible flower. Created entirely by code from main.gd.

const FLOWER_R := 14.0

# Each texture's own content-box width inside its canvas — not all three
# share the same canvas size/padding (the blue one is a different source
# than red/yellow), so each needs its own reference width to scale correctly.
static var textures: Array = [
	{"tex": load("res://art/flower_red.png"), "content_w": 694.0},
	{"tex": load("res://art/flower_yellow.png"), "content_w": 120.0},
	{"tex": load("res://art/flower_blue.png"), "content_w": 346.0},
]

var sway_phase := 0.0
var _time := 0.0
var _base_x := 0.0

var sprite: Sprite2D


func setup() -> void:
	sway_phase = randf() * TAU
	_base_x = position.x

	sprite = Sprite2D.new()
	add_child(sprite)
	var entry: Dictionary = textures[randi() % textures.size()]
	sprite.texture = entry["tex"]
	var visual_span := FLOWER_R * 2.1
	sprite.scale = Vector2.ONE * (visual_span / entry["content_w"])

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
	var sway := sin(_time * 2.0 + sway_phase) * 3.0
	position.x = _base_x + sway


func play_collect_effect() -> void:
	monitoring = false
	sprite.visible = false

	var particles := CPUParticles2D.new()
	particles.position = Vector2.ZERO
	particles.amount = 10
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 200.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 5.0
	particles.color = Color(1.0, 0.82, 0.25)
	add_child(particles)
	particles.emitting = true

	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)
