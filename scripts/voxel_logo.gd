extends Control

# The "Bee Bee" title as two rows of honey blocks: every letter is a grid of
# cubes with a lit top edge, a darker side showing below it and an ink
# outline, the same construction as the UI's plates (voxel_plate.gd). Drawn
# by code so it stays sharp on any screen.

const LETTER_B := [
	"XXXXXXXXX..",
	"XXXXXXXXXX.",
	"XXXXXXXXXXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXXXXXXXXX.",
	"XXXXXXXXXX.",
	"XXXXXXXXXXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXX.....XXX",
	"XXXXXXXXXXX",
	"XXXXXXXXXX.",
	"XXXXXXXXX..",
]
# Holes are at least three cubes tall: the side of the bar above fills two
# of them (DEPTH), and the letter stops reading once a hole closes up.
const LETTER_E := [
	".XXXXXXXX.",
	"XXXXXXXXXX",
	"XXXXXXXXXX",
	"XXX....XXX",
	"XXX....XXX",
	"XXX....XXX",
	"XXXXXXXXXX",
	"XXXXXXXXXX",
	"XXX.......",
	"XXX.......",
	"XXX.......",
	"XXX....XXX",
	"XXXXXXXXXX",
	"XXXXXXXXXX",
	".XXXXXXXX.",
]
const WORD := [LETTER_B, LETTER_E, LETTER_E]
const LETTER_GAP := 1
const WORD_GAP := 12             # the bee flies in this gap
const DEPTH := 2                 # cubes of side showing under each letter

const FACE := Color(1.0, 0.79, 0.17)
const LIGHT := Color(1.0, 0.93, 0.56)
const SIDE := Color(0.80, 0.46, 0.08)
const INK := Color(0.24, 0.13, 0.32)

var cell := 4.0
var face := {}                   # Vector2i -> true, in cubes
var side := {}
var outline := {}
# centre of the gap between the words, at the height of the letters' tops
var gap_anchor := Vector2.ZERO


# `px_scale`: the screen's pixels per interface unit, when known. The cubes
# are then a whole number of those pixels (the nearest to target_w, and at
# most 5% wider), so every cube, outline and lit edge is drawn the same
# thickness; otherwise a whole number of units.
func setup(target_w: float, px_scale := 0.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows: int = LETTER_B.size()
	var x := 1                    # one cube of margin for the outline
	var gap_x := 0.0
	for w in 2:
		for glyph in WORD:
			var top: int = 1 + rows - glyph.size()       # letters share a baseline
			for gy in glyph.size():
				var row: String = glyph[gy]
				for gx in row.length():
					if row[gx] == "X":
						face[Vector2i(x + gx, top + gy)] = true
			x += (glyph[0] as String).length() + LETTER_GAP
		x -= LETTER_GAP
		if w == 0:
			gap_x = x + WORD_GAP / 2.0
			x += WORD_GAP
	var cols := x + 1

	for p in face:
		for d in range(1, DEPTH + 1):
			var q: Vector2i = p + Vector2i(0, d)
			if not face.has(q):
				side[q] = true
	for group in [face, side]:
		for p in group:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var q: Vector2i = p + Vector2i(dx, dy)
					if not face.has(q) and not side.has(q):
						outline[q] = true

	cell = floorf(target_w / cols)
	if px_scale > 0.0 and target_w * px_scale / cols >= 2.0:
		var px := roundf(target_w * px_scale / cols)
		if px * cols / px_scale > target_w * 1.05:
			px -= 1.0
		cell = px / px_scale
	size = Vector2(cols * cell, (rows + DEPTH + 2) * cell)
	gap_anchor = Vector2(gap_x * cell, cell)
	queue_redraw()


func _draw() -> void:
	_draw_cells(outline, INK)
	_draw_cells(side, SIDE)
	var lit := {}
	var flat := {}
	for p in face:
		if face.has(p + Vector2i(0, -1)):
			flat[p] = true
		else:
			lit[p] = true
	_draw_cells(flat, FACE)
	_draw_cells(lit, LIGHT)


# Horizontal runs of cubes collapse into one rect each.
func _draw_cells(cells: Dictionary, color: Color) -> void:
	for p in cells:
		if cells.has(p + Vector2i(-1, 0)):
			continue
		var run := 1
		while cells.has(p + Vector2i(run, 0)):
			run += 1
		draw_rect(Rect2(p.x * cell, p.y * cell, run * cell, cell), color)
