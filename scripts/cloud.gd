extends Sprite2D

# Purely decorative. Spawned by main.gd alongside obstacle rows while
# score < 75 (spec: clouds stop spawning at the day->night transition, but
# existing ones are left to drift off naturally).

static var cloud_texture: Texture2D = load("res://art/cloud.png")

var drift_speed := 0.0


func setup() -> void:
	texture = cloud_texture
	# 768x768 canvas, actual cloud content is only ~652px wide inside it.
	const CONTENT_W := 652.0
	var visual_span: float = 45.0 + randf() * 30.0
	scale = Vector2.ONE * (visual_span / CONTENT_W)
	var direction := 1.0 if randf() < 0.5 else -1.0
	drift_speed = (6.0 + randf() * 10.0) * direction
	flip_h = direction < 0.0
	modulate.a = 0.85


func _process(delta: float) -> void:
	position.x += drift_speed * delta
