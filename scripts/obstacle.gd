extends Node2D

# A roseira: two bars (left and right of a gap), created by main.gd. It is
# only data — main.gd tests the bee against gap_x, gap_width and THICK
# directly each tick, so there are no physics shapes here, and view3d.gd
# builds the voxel hedge from the same three numbers.

const THICK := 22.0

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
