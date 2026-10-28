extends SceneTree

# QA screenshots of every screen of the game, at a phone's real resolution,
# for checking the layout by eye: the title (city and hills), the first
# run's arrows, a run by day, a bee won, the moon at dusk, the night sky, the
# record line, the pause menu, the credits, both kinds of game over and the
# bee menu; then what a run says as it goes: the rule plate (first run, and a
# run after one lost to a flower), the resume's countdown, a milestone, a bee
# and a milestone on one flower, the record readout once passed, a near
# miss's "Ufa!", a flower lost (the fall, then the game over), a flower behind
# the score, and a notice under the pause menu.
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

	# ---- the rule plate: a first launch, arrows and all
	sd.best_score = 0
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = false
	seed(5)
	paused = false
	g.state = g.State.GAMEOVER
	g._start_fresh_run()
	_scenery("hills")
	g._apply_bee_skin()
	await _shot("14_rule_first_run", 24)
	sd.seen_tutorial = true
	# ...and in flight, on a run after one lost to a missed flower
	sd.best_score = 20
	g.rule_due = true
	await _stage(1, 3.0, "city", "normal", 420.0, 21)
	await _shot("15_rule_in_flight", 24)
	g.rule_due = false

	# ---- the resume's countdown: the menu gone, the world still frozen
	await _stage(12, 14.0, "hills", "rosy", 900.0, 11)
	g.world_moving = true
	g.has_tapped_once = true
	g.bee.physics_enabled = false
	g._on_pause_pressed()
	for k in 4:
		await process_frame
	g._on_resume_pressed()
	await _shot("16_countdown", 12, false)
	g._stop_countdown()
	g._finish_resume()

	# ---- a milestone on its own, "50!"
	sd.best_score = 60
	sd.unlocked_bees = ["rosy", "mint", "ice"]
	await _stage(49, 40.0, "hills", "mint", 2400.0, 12)
	await _settle()
	g.on_flower_collected(g.flowers[0])
	await _shot("17_milestone", 12)

	# ---- Mint, the 25th flower and the record all at once: the bee has the slot
	sd.best_score = 20
	sd.unlocked_bees = ["rosy"]
	await _stage(20, 30.0, "city", "normal", 2400.0, 8)
	await _settle()
	g.on_flower_collected(g.flowers[0])
	await process_frame
	g.score = 24
	g.on_flower_collected(g.flowers[0])
	await _shot("18_bee_and_milestone", 14)
	# ...and once it has gone, the record readout says the record is passed
	await _shot("19_record_passed", 170)

	# ---- a near miss
	sd.unlocked_bees = ["rosy", "mint"]
	await _stage(31, 32.0, "hills", "mint", 2800.0, 15)
	g._trigger_near_miss()
	await _shot("20_phew", 6)

	# ---- a flower lost: the arrow over it while the bee falls, then the game over
	sd.best_score = 20
	await _stage(9, 12.0, "hills", "rosy", 900.0, 3)
	var lost = g.flowers[0]
	g.camera_y = lost.position.y - g.FlowerScript.FLOWER_R - g.screen_h - 2.0
	g.bee.position = Vector2(clampf(lost.position.x + 70.0, 40.0, 360.0), g.camera_y + g.screen_h * 0.62)
	g.bee.physics_enabled = false
	g.world_moving = true
	paused = false
	await physics_frame
	await physics_frame
	await _shot("21_flower_lost", 1, false)
	g.dying_timer = 99.0
	await _shot("22_flower_lost_game_over", 40, false)

	# ---- a flower behind the score's digits
	await _stage(14, 16.0, "city", "rosy", 1100.0, 31)
	var hid = g.flowers[-1]
	for fl in g.flowers:
		var y: float = fl.position.y - g.camera_y
		if y > 60.0 and y < 300.0:
			hid = fl
	hid._base_x = g.SCREEN_W / 2.0 + 14.0
	var want_y: float = g.score_label.position.y + 34.0
	for k in 4:
		g.camera_y += g.view3d.screen_pos_for(hid.position, Vector2(0.0, g.camera_y), 0.1).y - want_y
		await process_frame
	while g.highest_spawn_y > g.camera_y - g.screen_h:
		g._spawn_row()
	g.bee.position.y = g.camera_y + g.screen_h * 0.62
	await _shot("23_flower_behind_score", 20)

	# ---- a bee's notice, then the pause menu over it
	sd.best_score = 20
	sd.unlocked_bees = ["rosy"]
	await _stage(25, 30.0, "hills", "normal", 2400.0, 12)
	g._check_bee_unlocks()
	for k in 16:
		await process_frame
	g._on_pause_pressed()
	await _shot("24_pause_over_notice", 6, false)
	g._on_resume_pressed()

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


# A pickup needs the bee's contacts to be trusted again after a reset
# (main.gd _bee_contacts_trustworthy): two physics ticks.
func _settle() -> void:
	for k in 3:
		await physics_frame


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
