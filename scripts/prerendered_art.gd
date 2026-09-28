extends RefCounted

# TEST — 3D models built in Blender and pre-rendered to sprites by
# tools/blender/make_3d_assets.py. A file in art/3d/ takes
# priority over both the pixel and the original art; deleting the folder's
# PNGs reverts to whatever was there before.

const DIR := "res://art/3d/"

# Bee renders share one fixed ortho camera on a 256px canvas. The rest
# pose's full content width (antenna tip to stinger) is ~211px; it's sized
# as if it were 185 so the body reads as big as the old, chunkier bee.
const BEE_CONTENT_W := 185.0
# 8-frame wingbeat -> ~0.25s per tap, about the old 4-frame beat's length.
const FLAP_FPS := 32.0


static func texture(file_name: String) -> Texture2D:
	var path := DIR + file_name
	if ResourceLoader.exists(path):
		return load(path)
	return null
