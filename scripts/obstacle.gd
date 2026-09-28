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

const PixelArt := preload("res://scripts/pixel_art.gd")
const PrerenderedArt := preload("res://scripts/prerendered_art.gd")

static var rose_texture: Texture2D = load("res://art/rose_bush.png")
# Replacement versions: horizontally tileable strips, repeated to any bar
# width. The 3D render (a test) wins over the pixel one.
static var pixel_texture: Texture2D = PixelArt.texture("rose_bush.png")
static var prerendered_texture: Texture2D = PrerenderedArt.texture("rose_bush.png")

var gap_x: float
var gap_width: float

# Tracked by main.gd's collision pass while the bee is transiting this
# row, to fire a one-time "near miss" cue (screen shake + whoosh) if it
# grazed a bar edge without hitting it. INF until the bee actually enters
# the row's vertical band at least once.
var near_miss_min_clearance := INF
var near_miss_checked := false


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
	if prerendered_texture:
		# 3D render: same full visual height as the original art
		_add_tiled_bar(prerendered_texture, VISUAL_H / prerendered_texture.get_height(), false, x1, x2, width)
		return
	if pixel_texture:
		_add_tiled_bar(pixel_texture, PixelArt.SCALE, true, x1, x2, width)
		return

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


# A horizontally tiling strip repeated to the bar's width.
func _add_tiled_bar(tex: Texture2D, tex_scale: float, is_pixel: bool, x1: float, x2: float, width: float) -> void:
	var tile_w: int = tex.get_width()
	var tile_h: int = tex.get_height()
	# Whole texels only, rounded up — then anchored at the gap-side end so
	# the rounding spills off-screen instead of into the gap.
	var tex_w: float = ceil(width / tex_scale)
	var drawn_w: float = tex_w * tex_scale
	var left: float = x1 if x1 > 0.0 else x2 - drawn_w

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(randi() % tile_w, 0, tex_w, tile_h)
	sprite.scale = Vector2.ONE * tex_scale
	sprite.position = Vector2(left, (THICK - tile_h * tex_scale) / 2.0)
	PixelArt.apply_filter(sprite, is_pixel)
	add_child(sprite)
