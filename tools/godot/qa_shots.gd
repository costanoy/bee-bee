extends SceneTree

# QA screenshots of every screen of the game, at a phone's real resolution,
# for checking the layout by eye: the title (city and hills), the first
# run's arrows, a run by day, a bee won, the moon at dusk, the night sky, the
# record line, the pause menu, the credits, both kinds of game over and the
# bee menu.
#
#   godot --path . --audio-driver Dummy --script tools/godot/qa_shots.gd -- --lang=pt --w=1080 --h=2400 --out=C:/somewhere
#   godot --path . --audio-driver Dummy --resolution 600x800 --script tools/godot/qa_shots.gd -- --tablet=1 --out=...
#
# Run WITHOUT --headless. --tablet draws in the window itself instead of an
# offscreen phone screen, so the game sees a tablet-shaped window and keeps
# its 16:9 column. The player's save file is put back at the end.

const SAVE_FILES := ["user://bee_bee_save.cfg", "user://bee_bee_save.cfg.bak"]

var sv: SubViewport
var vp: Viewport
var g: Node2D
var sd: Node
var out := ""
var kept := {}


func _init() -> void:
	var opt := {"lang": "pt", "w": "1080", "h": "2400", "out": "", "tablet": "0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and opt.has(kv[0]):
			opt[kv[0]] = kv[1]
	out = opt["out"].trim_suffix("/") + "/"
	await process_frame
	for path in SAVE_FILES:
		kept[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.forced_lang = opt["lang"]
	DirAccess.make_dir_recursive_absolute(out)
	sd = root.get_node("SaveData")
	sd.best_score = 20
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
	sd.sfx_muted = true
	sd.vibration = false
	seed(5)

	g = Node2D.new()
	g.set_script(main_script)
	if opt["tablet"] == "1":
		vp = root
		root.add_child(g)
	else:
		var w := int(opt["w"])
		var h := int(opt["h"])
		sv = SubViewport.new()
		sv.size = Vector2i(w, h)
		sv.size_2d_override = Vector2i(400, roundi(400.0 * h / w))
		sv.size_2d_override_stretch = true
		sv.msaa_3d = Viewport.MSAA_4X
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sv)
		sv.add_child(g)
		vp = sv
	for k in 6:
		await process_frame
	print("QA screen_h ", g.screen_h, " window ", root.size, " content_scale ", root.content_scale_size)

	# ---- title, both backdrops
	_scenery("city")
	await _shot("01_title_city", 14, false)
	_scenery("hills")
	await _shot("02_title_hills", 14, false)

	# ---- a first run's arrows
	g._on_bee_menu_closed()
	g._start_fresh_run()
	g.hint_alpha = 1.0
	g.has_tapped_once = false
	g.direction_hint.modulate.a = 1.0
	g.direction_hint.visible = true
	await _shot("03_tutorial", 14)
	g.hint_alpha = 0.0
	g.has_tapped_once = true
	g.direction_hint.visible = false

	# ---- by day, then a bee won mid-run
	await _stage(12, 14.0, "city", "normal", 900.0, 11)
	await _shot("04_play_day")
	await _stage(25, 30.0, "hills", "normal", 2400.0, 12)
	g._check_bee_unlocks()
	await _shot("05_bee_won", 20)

	# ---- the moon into the sunset, then the night
	await _stage(101, 160.0, "hills", "rosy", 3000.0, 6)
	g.sky.moon_spawned = false
	g.sky.check_triggers(g.score)
	g.celestials[-1].position = Vector2(292.0, g.camera_y + 250.0)
	await _shot("06_dusk_moon", 150)
	await _stage(252, 276.0, "city", "rosy", 5200.0, 9)
	g.sky.jupiter_spawned = false
	g.sky.ship_spawned = false
	g.sky.check_triggers(g.score)
	g.celestials[-2].position = Vector2(110.0, g.camera_y + 230.0)
	g.celestials[-1].position = Vector2(300.0, g.camera_y + 420.0)
	await _shot("07_night", 150)

	# ---- the record line, a few flowers short of the record
	sd.best_score = 20
	await _stage(18, 24.0, "city", "rosy", 3420.0, 4)
	if g.record_line == null:
		g._spawn_record_line(g.camera_y + g.screen_h * 0.3, 300.0)
	else:
		g.record_line.position.y = g.camera_y + g.screen_h * 0.3
	await _shot("08_record_line", 30)

	# ---- pause menu and credits
	g._on_pause_pressed()
	await _shot("09_pause", 10, false)
	g._on_credits_pressed()
	await _shot("10_credits", 10, false)
	g.credits_screen.visible = false
	g._on_resume_pressed()

	# ---- game over without a record (next bee), and with one
	sd.best_score = 20
	sd.unlocked_bees = ["rosy"]
	await _stage(9, 12.0, "hills", "rosy", 900.0, 3)
	g._trigger_game_over("flower")
	g.dying_timer = 99.0
	await _shot("11_game_over", 30, false)
	sd.unlocked_bees = []
	await _stage(26, 30.0, "city", "normal", 2600.0, 8)
	g._check_bee_unlocks()
	g._trigger_game_over("hedge")
	g.dying_timer = 99.0
	await _shot("12_game_over_record", 30, false)

	# ---- the bee menu
	sd.best_score = 130
	sd.unlocked_bees = []
	sd.selected_bee = "mint"
	g._apply_bee_skin()
	g._on_bee_menu_pressed()
	await _shot("13_bee_menu", 20, false)
	g._on_bee_menu_closed()

	for path in SAVE_FILES:
		var data = kept.get(path)
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
	print("QA wrote ", out)
	quit()


func _scenery(backdrop: String) -> void:
	g.sky.backdrop = backdrop
	g.scenery_id += 1


# A moment of a run: `climb` px above the start, the bee just under a flower.
func _stage(score: int, elapsed: float, backdrop: String, skin: String, climb: float, rng_seed: int) -> void:
	seed(rng_seed)
	sd.selected_bee = skin
	if not sd.unlocked_bees.has(skin) and skin != "normal":
		sd.unlocked_bees.append(skin)
	paused = false
	g.state = g.State.GAMEOVER
	g._start_fresh_run()
	_scenery(backdrop)
	g._apply_bee_skin()
	g.score = score
	g.elapsed = elapsed
	g.camera_y -= climb
	while g.highest_spawn_y > g.camera_y - g.screen_h:
		g._spawn_row()
	g._update_score_label()
	g.sky.moon_spawned = true
	g.sky.jupiter_spawned = true
	g.sky.ship_spawned = true
	var want_y: float = g.camera_y + g.screen_h * 0.6
	var target = null
	for f in g.flowers:
		if target == null or absf(f.position.y - want_y) < absf(target.position.y - want_y):
			target = f
	var side := -1.0 if target.position.x > 200.0 else 1.0
	g.bee.position = target.position + Vector2(34.0 * side, 44.0)
	g.bee.position.x = clampf(g.bee.position.x, 40.0, 360.0)
	g.bee.facing = -int(side)
	g.bee.tilt = 0.28 * -side
	for f in g.flowers.duplicate():
		if f.position.y > g.bee.position.y + 30.0:
			g.flowers.erase(f)
			f.queue_free()
	if g.record_line and g.record_line.position.y > g.camera_y + 60.0:
		g.record_line.queue_free()
		g.record_line = null
	for k in 3:
		await process_frame


# `frames` to wait first; the sky's light takes ~100 frames to catch up after
# a jump in the time of day.
func _shot(name: String, frames := 14, playing := true) -> void:
	for k in frames:
		if playing:
			paused = false
			g.state = g.State.PLAYING
			g.pause_screen.visible = false
			g.pause_button.visible = true
			if k == frames - 4:
				g.bee._flap_time = 0.0
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
