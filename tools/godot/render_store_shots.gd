extends SceneTree

# Renders the Google Play screenshots (1080x2160) into store/screenshots/,
# from the real game: each shot stages a moment (score, time of day, skin,
# height) and captures it.
#
#   godot --path . --audio-driver Dummy --script tools/godot/render_store_shots.gd
#
# Run WITHOUT --headless. The save file is never written: unlocks, record
# and skin are changed in memory only.

const OUT := "res://store/screenshots/"

var sv: SubViewport
var g: Node2D
var sd: Node


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	sd = root.get_node("SaveData")
	sd.best_score = 128
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
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

	# 1. the title — and the same view with no UI, the backdrop that
	# tools/make_feature_graphic.py builds the store's feature graphic on
	_scenery("hills")
	await _shot("01_title", 20)
	g.start_screen.visible = false
	g.record_label.visible = false
	g.bee.position.x = -200.0
	await _shot("../backdrop", 4)
	g.bee.position.x = 200.0
	g.start_screen.visible = true
	g.record_label.visible = true

	# 2. early in a run, the ground still in view
	await _stage(7, 20.0, "hills", "normal", 150.0, 11)
	await _shot("02_play_day")

	# 3. dusk over the city, the queen flying
	sd.best_score = 240
	await _stage(88, 265.0, "city", "queen", 190.0, 5)
	await _shot("03_play_dusk")

	# 4. night, with the moon and Jupiter out, the silver bee
	sd.best_score = 320
	await _stage(214, 640.0, "hills", "shining", 5200.0, 9)
	g._on_moon_spawn_requested()
	g.celestials[-1].position = Vector2(292.0, g.camera_y + 250.0)
	g._on_jupiter_spawn_requested()
	g.celestials[-1].position = Vector2(96.0, g.camera_y + 560.0)
	await _shot("04_play_night")

	# 5. the bees to unlock
	sd.best_score = 128
	sd.selected_bee = "ice"
	g._start_fresh_run()
	g.state = g.State.START
	g.start_screen.visible = true
	g.pause_button.visible = false
	g._set_hud_visible(false)
	g.record_label.visible = true
	_scenery("hills")
	g._apply_bee_skin()
	g._on_bee_menu_pressed()
	await _shot("05_bees", 8, false)
	g._on_bee_menu_closed()

	# 6. a new record
	sd.best_score = 130
	await _stage(131, 60.0, "city", "ice", 230.0, 14)
	g.bee.die()
	g.state = g.State.GAMEOVER
	g.pause_button.visible = false
	g._set_hud_visible(false)
	g.final_score_label.text = "131"
	g.final_best_label.text = "131"
	g._show_new_record_badge()
	g.game_over_screen.visible = true
	await _shot("06_record", 26, false)

	print("wrote 6 screenshots to store/screenshots/")
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
	sv.get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)
