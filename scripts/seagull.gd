extends AnimatedSprite2D

# Purely decorative, same spirit as cloud.gd — drifts across the screen and
# gets culled off-screen. Unlike the bee's flap (one-shot, per tap), this
# loops continuously since a gull in flight never stops flapping.

const SHEET := "res://art/seagull_sheet.png"
const PrerenderedArt := preload("res://scripts/prerendered_art.gd")
# Hand-measured regions in the sprite sheet — the source frames aren't on a
# clean grid, so each region is its own rect rather than a sliced grid.
# Numbered 1-4 in the sheet's own reading order (top-left, top-right,
# bottom-left, bottom-right).
const FRAME_RECTS := [
	Rect2(30, 10, 488, 438),     # 1: wings up
	Rect2(1120, 160, 518, 288),  # 2: wings mid-stroke
	Rect2(48, 798, 458, 258),    # 3: wings rising
	Rect2(1166, 818, 438, 198),  # 4: wings tucked
]
# Ping-pong playback: 1-2-3-4-3-2, then it loops back to 1 — giving
# 1-2-3-4-3-2-1-2-3-4-3-2-... as requested.
const PLAYBACK_ORDER := [0, 1, 2, 3, 2, 1]
# Tallest frame (wings up) — the common scale reference so every frame
# shares one consistent scale factor (their silhouettes naturally differ
# in size frame to frame, same as a real wingbeat).
const CONTENT_H := 438.0

var drift_speed := 0.0


func setup() -> void:
	# 3D renders come as four separate frames sharing one crop; the original
	# is a hand-measured sheet.
	var atlases: Array = []
	var content_h := CONTENT_H
	for i in FRAME_RECTS.size():
		var tex := PrerenderedArt.texture("seagull_%d.png" % i)
		if tex == null:
			atlases.clear()
			break
		atlases.append(tex)
	if not atlases.is_empty():
		content_h = PrerenderedArt.GULL_CONTENT_H
	else:
		var sheet: Texture2D = load(SHEET)
		for rect in FRAME_RECTS:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = rect
			atlases.append(atlas)

	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("fly")
	sprite_frames.set_animation_loop("fly", true)
	sprite_frames.set_animation_speed("fly", 5.0)
	for i in PLAYBACK_ORDER:
		sprite_frames.add_frame("fly", atlases[i])

	self.sprite_frames = sprite_frames
	play("fly")

	var visual_span: float = 20.0 + randf() * 8.0
	scale = Vector2.ONE * (visual_span / content_h)

	var direction := 1.0 if randf() < 0.5 else -1.0
	drift_speed = (18.0 + randf() * 14.0) * direction
	flip_h = direction < 0.0
	modulate.a = 0.9


func _process(delta: float) -> void:
	position.x += drift_speed * delta
