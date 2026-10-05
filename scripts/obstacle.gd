extends Node2D

# A roseira, created by main.gd: either a hedge right across the screen with
# a gap in it, or one that grows in the middle of the screen and leaves a way
# past on each side. It is only data — main.gd tests the bee against `bars`
# and THICK directly each tick, so there are no physics shapes here, and
# view3d.gd builds the voxel hedge from the same numbers.

const THICK := 22.0
const SCREEN_W := 400.0

# The solid stretches of the row, each [left x, right x], from left to right.
var bars: Array = []

# Tracked by main.gd's collision pass while the bee is transiting this
# row, to fire a one-time "near miss" cue (screen shake + whoosh) if it
# grazed a bar edge without hitting it. INF until the bee actually enters
# the row's vertical band at least once.
var near_miss_min_clearance := INF
var near_miss_checked := false


# Two bars, one in from each side of the screen, with a gap between them.
func setup(gap_x: float, gap_width: float) -> void:
	bars = [[0.0, gap_x - gap_width / 2.0], [gap_x + gap_width / 2.0, SCREEN_W]]


# One bar in the middle of the screen, `width` across, open on both sides.
func setup_middle(width: float) -> void:
	bars = [[(SCREEN_W - width) / 2.0, (SCREEN_W + width) / 2.0]]


# The ways through the row, each [left x, right x], from left to right.
func gaps() -> Array:
	var ways := []
	var x := 0.0
	for bar in bars:
		if bar[0] > x:
			ways.append([x, bar[0]])
		x = bar[1]
	if x < SCREEN_W:
		ways.append([x, SCREEN_W])
	return ways
