extends Node2D

# A roseira: two bars (left and right of a gap), created entirely by code
# from main.gd. Purely visual — main.gd tests the bee against gap_x,
# gap_width and THICK directly each tick, so there are no physics shapes
# here. The visual is a crop of the rose-bush band, scaled UNIFORMLY (same
# factor on both axes) — never stretched on one axis only, which is what
# flattens the roses into distorted-looking ovals.

const THICK := 22.0
const SCREEN_W := 400.0

# source is a 1152x480 canvas; the actual rose/vine band only occupies
# y=[144,334] (190px tall) inside it.
const CONTENT_Y := 144.0
const CONTENT_H := 190.0
# Visual thickness of the drawn bush, uniformly scaled down from the 80px
# native content height — a bit bigger than the thin collision band still
# reads better than squeezing it to exactly THICK, but the native size was
# too big.
const VISUAL_H := 34.0

static var rose_texture: Texture2D = load("res://art/rose_bush.png")

var gap_x: float
var gap_width: float


func setup(p_gap_x: float, p_gap_width: float) -> void:
	gap_x = p_gap_x
	gap_width = p_gap_width

	var gap_left := gap_x - gap_width / 2.0
	var gap_right := gap_x + gap_width / 2.0

	_add_bar(0.0, gap_left)
	_add_bar(gap_right, SCREEN_W)


func _add_bar(x1: float, x2: float) -> void:
	if x2 <= x1:
		return
	var width := x2 - x1

	var sprite := Sprite2D.new()
	sprite.texture = rose_texture
	sprite.centered = false
	sprite.region_enabled = true

	var scale_factor: float = VISUAL_H / CONTENT_H
	var tex_w: float = rose_texture.get_width()
	var crop_w: float = min(width / scale_factor, tex_w)
	var max_offset: float = tex_w - crop_w
	var offset_x: float = randf() * max_offset

	sprite.region_rect = Rect2(offset_x, CONTENT_Y, crop_w, CONTENT_H)
	sprite.scale = Vector2.ONE * scale_factor
	# center the (taller) visual on the (thinner) collision band
	sprite.position = Vector2(x1, (THICK - VISUAL_H) / 2.0)
	add_child(sprite)
