extends AnimatedSprite2D

# Purely decorative, same spirit as cloud.gd — drifts across the screen and
# gets culled off-screen. Unlike the bee's flap (one-shot, per tap), this
# loops continuously since a gull in flight never stops flapping.

const SHEET := "res://art/seagull_sheet.png"
# Hand-measured regions in the sprite sheet — the source frames aren't on a
# clean grid, so each region is its own rect rather than a sliced grid.
const FRAME_RECTS := [
	Rect2(30, 10, 488, 438),     # wings up
	Rect2(1120, 160, 518, 288),  # wings mid-stroke
	Rect2(1166, 818, 438, 198),  # wings tucked
	Rect2(48, 798, 458, 258),    # wings rising
]
# Tallest frame (wings up) — the common scale reference so every frame
# shares one consistent scale factor (their silhouettes naturally differ
# in size frame to frame, same as a real wingbeat).
const CONTENT_H := 438.0

var drift_speed := 0.0


func setup() -> void:
	var sheet: Texture2D = load(SHEET)
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("fly")
	sprite_frames.set_animation_loop("fly", true)
	sprite_frames.set_animation_speed("fly", 8.0)
	for rect in FRAME_RECTS:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = rect
		sprite_frames.add_frame("fly", atlas)

	self.sprite_frames = sprite_frames
	play("fly")

	var visual_span: float = 55.0 + randf() * 20.0
	scale = Vector2.ONE * (visual_span / CONTENT_H)

	var direction := 1.0 if randf() < 0.5 else -1.0
	drift_speed = (18.0 + randf() * 14.0) * direction
	flip_h = direction < 0.0
	modulate.a = 0.9


func _process(delta: float) -> void:
	position.x += drift_speed * delta
