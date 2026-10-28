extends Control

# A block for the UI, drawn on the interface's own cube grid so buttons and
# panels look cut from the same cubes as the world: an outline with one-cube
# stepped corners, a lit top edge, and a darker band below for the block's
# side. Pressing it sinks the face onto that band.
#
# Nothing here overlaps when drawn, so the whole plate can be faded with
# modulate without the layers showing through each other.

const PALETTES := {
	"honey": {
		"face": Color(0.98, 0.76, 0.20), "light": Color(1.0, 0.91, 0.52),
		"side": Color(0.78, 0.46, 0.10), "ink": Color(0.24, 0.13, 0.32),
	},
	"green": {
		"face": Color(0.36, 0.78, 0.36), "light": Color(0.62, 0.92, 0.55),
		"side": Color(0.17, 0.52, 0.27), "ink": Color(0.24, 0.13, 0.32),
	},
	# Outlined in white rather than ink: these sit over the sky, which is
	# nearly the ink's own colour at night.
	"dark": {
		"face": Color(0.29, 0.17, 0.40), "light": Color(0.43, 0.29, 0.57),
		"side": Color(0.16, 0.08, 0.23), "ink": Color(1.0, 1.0, 1.0),
	},
	# the dark block lit up: the card of the bee in use
	"lit": {
		"face": Color(0.42, 0.27, 0.56), "light": Color(0.60, 0.45, 0.74),
		"side": Color(0.22, 0.12, 0.31), "ink": Color(1.0, 1.0, 1.0),
	},
}

var cell := 3.0
var side_cells := 2
var colors: Dictionary = PALETTES["honey"]
var ink: Color
var pressed := false:
	set(value):
		pressed = value
		queue_redraw()


func setup(palette: String, plate_size: Vector2, cell_size := 3.0, side := 2) -> void:
	colors = PALETTES[palette]
	ink = colors["ink"]
	cell = cell_size
	side_cells = side
	size = plate_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ink(color: Color) -> void:
	ink = color
	queue_redraw()


# Another palette, keeping the ink as it was set.
func set_palette(palette: String) -> void:
	colors = PALETTES[palette]
	queue_redraw()


# How far the face drops while pressed.
func _sink() -> float:
	return (side_cells - 1) * cell if pressed and side_cells > 1 else 0.0


func _side_h() -> float:
	return minf(side_cells, 1) * cell if pressed else side_cells * cell


# The top face, inside the outline — where a button's label or icon sits.
# Follows the press.
func face_rect() -> Rect2:
	var top := _sink()
	return Rect2(cell, top + cell, size.x - 2.0 * cell, size.y - top - 2.0 * cell - _side_h())


func _draw() -> void:
	var c := cell
	var top := _sink()
	var w := size.x
	var h := size.y - top
	var face := face_rect()

	# a soft shadow on whatever is behind, one cube below the block
	draw_rect(Rect2(c, size.y, w - 2.0 * c, c), Color(0.1, 0.05, 0.15, 0.28))

	draw_rect(Rect2(c, top, w - 2.0 * c, c), ink)
	draw_rect(Rect2(c, top + h - c, w - 2.0 * c, c), ink)
	draw_rect(Rect2(0, top + c, c, h - 2.0 * c), ink)
	draw_rect(Rect2(w - c, top + c, c, h - 2.0 * c), ink)

	draw_rect(Rect2(face.position, Vector2(face.size.x, c)), colors["light"])
	draw_rect(Rect2(face.position + Vector2(0, c), face.size - Vector2(0, c)), colors["face"])
	draw_rect(Rect2(Vector2(face.position.x, face.end.y), Vector2(face.size.x, _side_h())), colors["side"])
