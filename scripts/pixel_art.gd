extends RefCounted

# Hand-drawn replacements for the original art live in art/pixel/, drawn
# 1:1 on a single grid where one art pixel = SCALE game px, and each one
# takes over from the old texture the moment its file exists. Assets
# without a pixel version yet keep their old art and scale, so the swap
# can happen one sprite at a time. Sizes per asset: art/pixel_templates/.

const SCALE := 2.0
const DIR := "res://art/pixel/"


# The pixel version of `file_name`, or null if it hasn't been drawn yet.
static func texture(file_name: String) -> Texture2D:
	var path := DIR + file_name
	if ResourceLoader.exists(path):
		return load(path)
	return null


# Nearest-neighbour so every art pixel stays a crisp block; the old,
# heavily downscaled art still wants the project's default smoothing.
static func apply_filter(item: CanvasItem, is_pixel: bool) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if is_pixel else CanvasItem.TEXTURE_FILTER_PARENT_NODE
