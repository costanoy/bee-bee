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


# The seagull's four frames share one crop (so the body holds still);
# this is its height scaled so the bird comes out about as big as before.
const GULL_CONTENT_H := 170.0


# res:// path of `file_name`: the 3D render if there is one, otherwise the
# original art. Every render is fitted into the original's canvas and
# content box (tools/blender/conform.py), so no scale constant changes.
static func path(file_name: String) -> String:
	var p := DIR + file_name
	return p if ResourceLoader.exists(p) else "res://art/" + file_name


static func texture(file_name: String) -> Texture2D:
	var path := DIR + file_name
	if ResourceLoader.exists(path):
		return load(path)
	return null
