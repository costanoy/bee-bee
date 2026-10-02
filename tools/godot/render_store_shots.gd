extends SceneTree

# Renders the Google Play screenshots (1080x2160) from the real game: each
# shot stages a moment (score, time of day, skin, height) and captures it.
#
#   godot --path . --audio-driver Dummy --script tools/godot/render_store_shots.gd -- --lang=pt
#   godot --path . --audio-driver Dummy --script tools/godot/render_store_shots.gd -- --lang=en
#
# Writes store/screenshots/pt-BR/ or en-US/, one set per language of the
# store listing, and store/backdrop.png (the title scene with no interface,
# which tools/make_feature_graphic.py builds on). Run WITHOUT --headless.
#
# The save file is never written: record, unlocks and skin are changed in
# memory only, and the one shot that ends a run is staged so that the game
# finds nothing new to save.
#
# Scores and times go together: the sky runs on the clock of the run, so
# each shot is given the time a run really takes to reach that score.

const DIRS := {"pt": "pt-BR", "en": "en-US"}

var sv: SubViewport
var g: Node2D
var sd: Node
var out := ""


func _init() -> void:
	var lang := "pt"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	load("res://scripts/main.gd").forced_lang = lang
	out = "res://store/screenshots/%s/" % DIRS.get(lang, lang)
	await process_frame          # the save file is read on the first frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	sd = root.get_node("SaveData")
	sd.best_score = 128
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
	sd.vibration = false
	seed(21)

	sv = SubViewport.new()
	sv.size = Vector2i(1080, 2160)
	sv.size_2d_override = Vector2i(400, 800)
	sv.size_2d_override_stretch = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	g = Node2D.new()
	g.set_script(load("res://scripts/main.gd"))
	sv.add_child(g)

	# the title scene with no interface, over the hills: the feature graphic
	_scenery("hills")
	g.start_screen.visible = false
	g.record_label.visible = false
	g.bee.position.x = -200.0
	await _shot("../../backdrop", 20)
	g.bee.position.x = 200.0
	g.start_screen.visible = true
	g.record_label.visible = true

	# 1. the title, over the city
	_scenery("city")
	await _shot("01_title", 12)

	# 2. early in a run, the ground still in view
	await _stage(7, 12.0, "hills", "normal", 150.0, 11)
	await _shot("02_play_day")

	# 3. the moon rising into the first colours of the sunset
	await _stage(101, 114.0, "hills", "ice", 3000.0, 6)
	g._on_moon_spawn_requested()
	g.celestials[-1].position = Vector2(292.0, g.camera_y + 250.0)
	await _shot("03_play_moonrise", 150)

	# 4. the sunset at its height, the queen flying
	sd.best_score = 240
	await _stage(146, 162.0, "hills", "queen", 3000.0, 5)
	await _shot("04_play_dusk", 150)

	# 5. night, a visitor in the sky, the silver bee
	sd.best_score = 320
	await _stage(252, 276.0, "hills", "shining", 5200.0, 9)
	g._on_ship_spawn_requested()
	g.celestials[-1].position = Vector2(104.0, g.camera_y + 300.0)
	await _shot("05_play_night", 150)

	# 6. the bees to unlock
	sd.best_score = 128
	sd.unlocked_bees = []
	sd.selected_bee = "ice"
	g._start_fresh_run()
	g.state = g.State.START
	g.start_screen.visible = true
	g.pause_button.visible = false
	g._set_hud_visible(false)
	g.record_label.visible = true
	_scenery("city")
	g._apply_bee_skin()
	g._on_bee_menu_pressed()
	await _shot("06_bees", 150, false)
	g._on_bee_menu_closed()

	# 7. a new record. The record is put in memory before the run ends, so
	# the game finds nothing to save; the run still knows it began below it.
	sd.best_score = 130
	await _stage(131, 150.0, "hills", "ice", 3000.0, 14)
	for k in 150:
		paused = false
		await process_frame
	sd.best_score = 131
	g.state = g.State.PLAYING
	g._trigger_game_over("hedge")
	g.dying_timer = 99.0
	g.bee.physics_enabled = false
	await _shot("07_record", 40, false)

	print("wrote the screenshots to ", out)
	quit()


func _scenery(backdrop: String) -> void:
	g.sky.backdrop = backdrop
	g.scenery_id += 1


# A moment of a run: `climb` px above the start, the bee just under a flower.
func _stage(score: int, elapsed: float, backdrop: String, skin: String, climb: float, rng_seed: int) -> void:
	seed(rng_seed)
	sd.selected_bee = skin
	if not sd.unlocked_bees.has(skin):
		sd.unlocked_bees.append(skin)
	g._start_fresh_run()
	_scenery(backdrop)
	g._apply_bee_skin()
	g.score = score          # before the rows spawn: clouds and gulls depend on it
	g.elapsed = elapsed
	g.camera_y -= climb
	while g.highest_spawn_y > g.camera_y - g.screen_h:
		g._spawn_row()
	g._update_score_label()
	# the sky's events are placed by the shots that want them
	g.sky.moon_spawned = true
	g.sky.jupiter_spawned = true
	g.sky.ship_spawned = true

	# the bee flies up at the flower nearest the lower middle of the screen
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
	# everything below it has been collected already
	for f in g.flowers.duplicate():
		if f.position.y > g.bee.position.y + 30.0:
			g.flowers.erase(f)
			f.queue_free()
	if g.record_line and g.record_line.position.y > g.camera_y + 60.0:
		g.record_line.queue_free()
		g.record_line = null
	for k in 3:
		await process_frame


# `frames` to wait first. The light the sky casts on the scene takes a
# hundred frames or so to catch up after a jump in the time of day, so the
# shots that change it wait that long (a shot taken at once comes out lit by
# the sky of the shot before).
func _shot(name: String, frames := 14, playing := true) -> void:
	for k in frames:
		paused = false
		if playing and g.state != g.State.START:
			g.state = g.State.PLAYING
			g.pause_screen.visible = false
			g.pause_button.visible = true
			# mid-wingbeat
			if k == frames - 4:
				g.bee._flap_time = 0.0
		await process_frame
	await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
