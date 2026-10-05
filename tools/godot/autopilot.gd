extends RefCounted

# An autopilot for the bee, for the tools that need the game played without
# a person: the promo video (render_promo.gd) and the difficulty bench
# (bench_difficulty.gd).
#
# It looks about a second ahead over every sensible sequence of taps (none,
# left or right, every `dec` ticks, never two in a row), simulating the
# bee's own physics against the hedges and flowers actually on screen, and
# takes the first tap of the best one. Losing is failing to finish, so the
# search treats a hit, a missed flower or a fall as the worst outcomes.
#
# It reads the game's state and never changes it: the caller taps.

const G := 1500.0
const MAX_FALL := 700.0
const FLAP_V := -480.0
const DT := 1.0 / 60.0
const LW := 400.0
# how far from the end of a hedge in the middle it aims to pass
const SIDE_ROOM := 40.0

var dec := 4                 # ticks between decisions
var depth := 13              # decisions looked ahead
var damp := exp(-2.0 * DT)
var tick := 0
var flapped := false
var p_rows: Array = []
var p_fl: Array = []
var p_r := 12.8
var p_flower_r := 14.0
var p_hs := 316.0
var p_cam := 0.0
var p_scroll := 0.0
var p_h := 711.0


func reset() -> void:
	tick = 0
	flapped = false


# Call once per physics tick while a run is on. Returns -1 or 1 on the ticks
# where the bee should be tapped left or right, 0 otherwise.
func step(g: Node) -> int:
	tick += 1
	if tick % dec != 0:
		return 0
	if flapped:
		flapped = false
		return 0
	var act := plan(g)
	flapped = act != 0
	return act


func plan(g: Node) -> int:
	var b = g.bee
	p_r = b.radius
	p_flower_r = g.FlowerScript.FLOWER_R
	p_hs = b.h_speed
	p_cam = g.camera_y
	p_scroll = g._current_scroll_speed() if g.scrolling_started else 0.0
	p_h = g.screen_h
	p_rows = []
	for o in g.obstacles:
		if is_instance_valid(o) and o.position.y < b.position.y + 80.0 and o.position.y > b.position.y - 560.0:
			# [top, its solid bars, where to aim in each way through it]
			p_rows.append([o.position.y, o.bars, o.gaps().map(_aim)])
	p_rows.sort_custom(func(a, c): return a[0] > c[0])
	p_fl = []
	for fl in g.flowers:
		if is_instance_valid(fl) and not fl.collected and fl.position.y > b.position.y - 560.0:
			p_fl.append(fl.position)
	var best := -INF
	var best_act := 0
	for act in [0, -1, 1]:
		var v := _search(depth, b.position.x, b.position.y, b.velocity.x, b.velocity.y, act, 0, 0, 0, 99.0)
		if v > best:
			best = v
			best_act = act
	return best_act


# Where to aim in a way through a row, as a stretch of x. For a gap between
# two bars that is its middle. Beside a hedge in the middle the way runs to
# the edge of the screen, which does no harm, so anywhere that keeps
# SIDE_ROOM from the hedge will do.
func _aim(way: Array) -> Array:
	if way[0] <= 0.0 or way[1] >= LW:
		var lo: float = way[0] + (p_r if way[0] <= 0.0 else SIDE_ROOM)
		var hi: float = way[1] - (p_r if way[1] >= LW else SIDE_ROOM)
		if lo <= hi:
			return [lo, hi]
	var mid: float = (way[0] + way[1]) / 2.0
	return [mid, mid]


func _search(depth: int, x: float, y: float, vx: float, vy: float, act: int, mask: int, flaps: int, tick: int, clear: float) -> float:
	if act != 0:
		vy = FLAP_V
		vx = act * p_hs
		flaps += 1
	var rr := p_r + 2.0
	var rr2 := rr * rr
	var pick := (p_r + p_flower_r - 5.0) * (p_r + p_flower_r - 5.0)
	for k in dec:
		vy = minf(vy + G * DT, MAX_FALL)
		vx *= damp
		x += vx * DT
		y += vy * DT
		if x < p_r:
			x = p_r
			vx = absf(vx) * 0.4
		elif x > LW - p_r:
			x = LW - p_r
			vx = -absf(vx) * 0.4
		tick += 1
		var screen_top := p_cam - p_scroll * DT * tick
		# The game holds the bee at the top edge of the screen (bee.gd), where
		# that edge was before this tick's scroll: main.gd sets the ceiling
		# and only then moves the camera. Taking the edge as it is after the
		# scroll put the bee a tick higher than it really gets, enough for it
		# to plan a pass over a hedge just coming into view and land on it.
		var ceiling := screen_top + p_scroll * DT + p_r
		if y < ceiling:
			y = ceiling
			vy = maxf(vy, 0.0)
		var bottom := screen_top + p_h
		if y - p_r > bottom:
			return -1e6 + tick * 10.0
		for row in p_rows:
			var top: float = row[0]
			if y + rr < top or y - rr > top + 22.0:
				continue
			var ny := clampf(y, top, top + 22.0)
			var dy := y - ny
			var dx := INF
			for bar in row[1]:
				dx = minf(dx, absf(x - clampf(x, bar[0], bar[1])))
			var d2 := dx * dx + dy * dy
			if d2 < rr2:
				return -1e6 + tick * 10.0
			clear = minf(clear, sqrt(d2) - p_r)
		for i in p_fl.size():
			if mask & (1 << i):
				continue
			var fp: Vector2 = p_fl[i]
			var ddx := x - fp.x
			var ddy := y - fp.y
			if ddx * ddx + ddy * ddy <= pick:
				mask |= 1 << i
			elif fp.y - p_flower_r > bottom:
				return -1e6 + tick * 10.0
	if depth > 1:
		var best := _search(depth - 1, x, y, vx, vy, 0, mask, flaps, tick, clear)
		if act == 0:
			best = maxf(best, _search(depth - 1, x, y, vx, vy, -1, mask, flaps, tick, clear))
			best = maxf(best, _search(depth - 1, x, y, vx, vy, 1, mask, flaps, tick, clear))
		return best
	# how good this place is to have reached
	var val := -flaps * 14.0
	var row_above = null
	for row in p_rows:
		if row[0] + 22.0 < y - p_r:
			row_above = row
			break
	var low = null
	for i in p_fl.size():
		if mask & (1 << i):
			val += 600.0
		elif low == null or p_fl[i].y > low.y:
			low = p_fl[i]
	# a flower left under a hedge the bee is already past is as good as lost
	for i in p_fl.size():
		if not (mask & (1 << i)):
			for row in p_rows:
				if row[0] > y and p_fl[i].y > row[0]:
					val -= 3000.0
					break
	var tx := x
	if low != null and (row_above == null or low.y > row_above[0]):
		tx = low.x
		val -= absf(y - (low.y + 20.0)) * 0.5
	elif row_above != null:
		# the nearest way through it
		tx = INF
		for aim in row_above[2]:
			var ax := clampf(x, aim[0], aim[1])
			if absf(x - ax) < absf(x - tx):
				tx = ax
	val -= absf(x - tx) * 1.6
	var cam_end := p_cam - p_scroll * DT * tick
	val -= absf(y - (cam_end + p_h * 0.46)) * 0.9
	if y < cam_end + 90.0:
		val -= (cam_end + 90.0 - y) * 6.0
	if clear < 10.0:
		val -= (10.0 - clear) * 25.0
	return val
