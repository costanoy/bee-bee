extends SceneTree

# Measures how survivable the game is at a given point of its difficulty
# ramp, by letting the autopilot (autopilot.gd) play it many times over.
#
#   godot --headless --path . --fixed-fps 60 --script tools/godot/bench_difficulty.gd -- [options]
#
#   --runs=N       layouts to try (default 12)
#   --secs=N       how long a run has to last to count as survived (default 45)
#   --elapsed=N    seconds into a run to play at; the ramp tops out at
#                  DIFFICULTY_RAMP_TIME, so the default (100) is full difficulty
#   --dec=N --depth=N   how often the autopilot may tap and how far it looks
#                  ahead. The defaults (6 and 8: five taps a second at most,
#                  0.8 s of foresight) stand in for a good player; 4 and 13
#                  are close to the best that can be done.
#
# What it is for: a row the best autopilot cannot get through is a row no
# player can, so its survival rate separates "hard" from "impossible" when
# tuning SCROLL_*, the gap width and MAX_LEG_HARD in main.gd. It says nothing
# about how the game feels; that still takes a person.
#
# The save file is not written: a run only saves on a record or a new skin,
# and the bench keeps the record out of reach.

var g: Node2D
var sd: Node
var bot: RefCounted = load("res://tools/godot/autopilot.gd").new()
var opt := {"runs": 12, "secs": 45, "elapsed": 100, "dec": 6, "depth": 8}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2 and opt.has(kv[0]):
			opt[kv[0]] = int(kv[1])
	_run()


func _run() -> void:
	await process_frame          # the save file is read on the first frame
	sd = root.get_node("SaveData")
	sd.best_score = 100000
	sd.unlocked_bees = ["rosy", "mint", "ice", "grape", "queen", "shining"]
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
	sd.vibration = false
	g = Node2D.new()
	g.set_script(load("res://scripts/main.gd"))
	root.add_child(g)
	for i in 6:
		await process_frame
	bot.dec = opt["dec"]
	bot.depth = opt["depth"]

	var limit: int = opt["secs"] * 60
	var times := []
	var rows := []
	for run in opt["runs"]:
		_stage(1000 + run)
		var start_score: int = g.score
		var t := 0
		while t < limit:
			paused = false
			if g.state == g.State.PAUSED:
				g.state = g.State.PLAYING
			if g.state != g.State.PLAYING:
				break
			var act: int = bot.step(g)
			if act != 0:
				g.bee.flap(act)
			await physics_frame
			t += 1
		times.append(t / 60.0)
		rows.append(g.score - start_score)
	var survived := times.filter(func(v): return v >= opt["secs"] - 0.01).size()
	var mean := 0.0
	for v in times:
		mean += v / times.size()
	times.sort()
	print("BENCH scroll %.0f gap %.1f | autopilot dec %d depth %d | survived %d/%d runs of %d s | mean %.1f s, median %.1f s, worst %.1f s | flowers %s" % [
		g._current_scroll_speed(), _gap(), opt["dec"], opt["depth"], survived, times.size(), opt["secs"],
		mean, times[times.size() / 2], times[0], str(rows)])
	quit()


func _gap() -> float:
	return g.obstacles[-1].gap_width if g.obstacles.size() > 0 else 0.0


# A run already in full swing, as in render_promo.gd.
func _stage(rng_seed: int) -> void:
	seed(rng_seed)
	g._start_fresh_run()
	g.score = 150
	g.elapsed = float(opt["elapsed"])
	g.camera_y -= 3000.0
	while g.highest_spawn_y > g.camera_y - g.screen_h:
		g._spawn_row()
	var want_y: float = g.camera_y + g.screen_h * 0.52
	var target = null
	for fl in g.flowers:
		if target == null or absf(fl.position.y - want_y) < absf(target.position.y - want_y):
			target = fl
	var side := -1.0 if target.position.x > 200.0 else 1.0
	g.bee.position = target.position + Vector2(46.0 * side, 52.0)
	for fl in g.flowers.duplicate():
		if fl.position.y > g.bee.position.y + 30.0:
			g.flowers.erase(fl)
			fl.queue_free()
	if g.record_line:
		g.record_line.queue_free()
		g.record_line = null
	g.world_moving = true
	g.scrolling_started = true
	g.time_since_first_flap = 1.0
	g.has_tapped_once = true
	g.bee.physics_enabled = true
	g.bee.velocity = Vector2(-side * 290.0, -440.0)
	# the moon and the others are scenery; no need to raise them every run
	g.sky.moon_spawned = true
	g.sky.jupiter_spawned = true
	g.sky.ship_spawned = true
	bot.reset()
