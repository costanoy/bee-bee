extends Node2D

# Purely decorative. Spawned by main.gd alongside obstacle rows; drifts
# sideways until it leaves the screen. view3d.gd picks the voxel cloud model
# from `span`.

var drift_speed := 0.0
# width in game px
var span := 60.0


func setup() -> void:
	span = 45.0 + randf() * 30.0
	var direction := 1.0 if randf() < 0.5 else -1.0
	drift_speed = (6.0 + randf() * 10.0) * direction


func _process(delta: float) -> void:
	position.x += drift_speed * delta
