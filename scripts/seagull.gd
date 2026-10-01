extends Node2D

# Purely decorative, same spirit as cloud.gd — drifts across the screen and
# gets culled off-screen. view3d.gd draws the voxel gull and flaps its wings.

var drift_speed := 0.0
var facing_left := false


func setup() -> void:
	var direction := 1.0 if randf() < 0.5 else -1.0
	drift_speed = (18.0 + randf() * 14.0) * direction
	facing_left = direction < 0.0


func _process(delta: float) -> void:
	position.x += drift_speed * delta
