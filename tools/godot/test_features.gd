extends SceneTree

# Checks for what tools/godot/test_game.gd leaves alone: the models and
# sounds, the difficulty ramp (and the leg cap up the ramp), the easy rows
# (a new player's intro rows, the breathers after every 25th flower), the sky (its clock, the moon, Jupiter and the
# UFO, the two backdrops), the bees (unlocks, the bee menu, every model), the
# record line, near misses, a real flower pickup, the pause menu's switches,
# the back button and leaving the app, the first run's tutorial, the
# settings panel and its gear, the game-over screen (its count-up and lock,
# the record line, the goal chip's bar and "Use it"), the title's layout,
# the size of every button, how often ads come, and the save file.
#
#   bash tools/test.sh          (runs this in English and in Portuguese)
#
# or, by hand:
#   godot --headless --path . --fixed-fps 60 --script tools/godot/test_features.gd -- --lang=pt
#
# Like test_game.gd it writes to the real save file, and puts the player's
# back at the end.

const SAVE_FILES := ["user://bee_bee_save.cfg", "user://bee_bee_save.cfg.bak"]

var kept := {}
var g: Node2D
var sd: Node
var fails := 0
var Main: GDScript


func _initialize() -> void:
	_run()


func ok(cond: bool, what: String) -> void:
	if cond:
		print("  PASS ", what)
	else:
		fails += 1
		print("  FAIL ", what)


# Physics frames. The tree is left as the game set it (fresh() unpauses):
# forcing it unpaused here made every "not paused" check after it moot.
func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := InputEventKey.new()
	u.keycode = code
	u.pressed = false
	Input.parse_input_event(u)
	await frames(1)


func keep_save() -> void:
	for path in SAVE_FILES:
		kept[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func restore_save() -> void:
	for path in SAVE_FILES:
		var data = kept.get(path)
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(data)
		f.close()


func fresh() -> void:
	paused = false
	g.restart_after_ad = false
	g.state = g.State.GAMEOVER
	g._start_fresh_run()
	await ticks(3)


# Waits until no sound is playing, so a sound about to be played finds a voice
# free (they last real time, and a headless run goes through its frames much
# faster than that; see test_game.gd).
func silence() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var busy := false
		for v in g.sfx_pool:
			busy = busy or v.playing
		if not busy:
			return
		await process_frame


# A run ended the quick way, straight onto the game-over screen.
func end_run(cause := "fall") -> void:
	g._trigger_game_over(cause)
	g.dying_timer = 99.0
	await ticks(2)
	g.game_over_msec -= 1000               # past the lock against stray taps


func _run() -> void:
	await process_frame
	keep_save()
	var lang := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	Main = load("res://scripts/main.gd")
	Main.forced_lang = lang
	sd = root.get_node("SaveData")
	sd.best_score = 10
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
	sd.sfx_muted = false
	sd.vibration = false
	sd.screen_shake = true
	g = Node2D.new()
	g.set_script(Main)
	root.add_child(g)
	await frames(8)
	print("TESTS features lang=", g.lang)
	ok(g.music.playing and g.music.volume_db == g.MUSIC_MUTED_DB, "a player who turned the music off gets it muted from the start")

	await _assets()
	await _difficulty()
	await _easy_rows()
	await _sky()
	await _backdrops()
	await _bees()
	await _record_line()
	await _near_miss()
	await _pickup()
	await _pause_menu()
	await _settings()
	await _back_and_focus()
	await _tutorial()
	await _rule_plate()
	await _notice_slot()
	await _record_readout()
	await _countdown()
	await _close_calls()
	await _game_over_screen()
	await _title_screen()
	await _touch_targets()
	await _ads()
	await _credits()
	await _save_file()

	restore_save()
	print("TESTS done, failures: ", fails)
	quit()


# ------------------------------------------------------------------ models and sounds
func _assets() -> void:
	for slot in g.view3d.models:
		ok(g.view3d.models[slot] != null, "model '%s' loads" % slot)
	for id in g.BEE_ORDER:
		ok(g.BEE_SKINS.has(id), "bee '%s' is described" % id)
		var model: String = g.BEE_SKINS[id]["model"]
		var path: String = "res://models/%s.glb" % g.view3d.voxel.get(model, model)
		ok(ResourceLoader.exists(path), "bee '%s' has its model (%s)" % [id, path.get_file()])
		ok(ResourceLoader.exists(g._bee_icon_path(id)), "bee '%s' has its icon" % id)
	for s: AudioStream in [g.SFX_FLAP, g.SFX_COLLECT, g.SFX_HIT, g.SFX_RECORD, g.SFX_UI_TAP, g.SFX_NEAR_MISS]:
		ok(s != null and s.get_length() > 0.0, "sound %s loads (%.2f s)" % [s.resource_path.get_file(), s.get_length()])
	var theme: AudioStream = g.music.stream
	ok(theme is AudioStreamWAV and theme.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the theme loops by itself")
	ok(g.music.playing, "the music is on from the title screen")


# ------------------------------------------------------------------ difficulty
func _difficulty() -> void:
	await fresh()
	g.elapsed = 0.0
	ok(is_equal_approx(g._current_scroll_speed(), g.SCROLL_BASE), "a run climbs at %.0f px/s at first" % g._current_scroll_speed())
	g.elapsed = g.DIFFICULTY_RAMP_TIME / 2.0
	ok(is_equal_approx(g._current_scroll_speed(), (g.SCROLL_BASE + g.SCROLL_MAX) / 2.0), "half way up the ramp, half way to the top speed")
	g.elapsed = 1000.0
	ok(is_equal_approx(g._current_scroll_speed(), g.SCROLL_MAX), "and never past %.0f px/s" % g.SCROLL_MAX)

	g.elapsed = 0.0
	g._spawn_row()
	var widest: float = g.obstacles[-1].gap_width
	g.elapsed = 1000.0
	g._spawn_row()
	var narrowest: float = g.obstacles[-1].gap_width
	ok(widest > narrowest and narrowest > 2.0 * (g.bee.radius + 30.0), "gaps narrow from %.0f to %.0f px, still wider than the bee" % [widest, narrowest])

	# Every row at the top of the ramp: the flower beside the gap (or in the
	# middle of the screen) and never further than a leg the bee can fly.
	seed(11)
	var first: int = g.obstacles.size()
	for i in 2000:
		g._spawn_row()
	var too_far := 0
	var in_gap := 0
	for i in range(first, g.obstacles.size()):
		var fx: float = g.flowers[i].position.x
		var gx: float = g.obstacles[i].gap_x
		var prev_gx: float = g.obstacles[i - 1].gap_x
		if is_equal_approx(fx, g.SCREEN_W / 2.0):
			continue
		if absf(fx - gx) > g.MAX_LEG_HARD + 0.01 or absf(fx - prev_gx) > g.MAX_LEG_HARD + 0.01:
			too_far += 1
		if absf(fx - gx) < g.obstacles[i].gap_width / 2.0 + 20.0 - 0.01:
			in_gap += 1
		if fx < 30.0 - 0.01 or fx > g.SCREEN_W - 30.0 + 0.01:
			too_far += 1
	ok(too_far == 0, "no flower out of reach in 2000 rows at full speed (%d)" % too_far)
	ok(in_gap == 0, "and none of them sits in the way of its gap (%d)" % in_gap)

	# Up the ramp, a row's legs are capped by the speed it is FLOWN at: the
	# world scrolled as in a run (the bee left out), each row's speed taken
	# when its hedge comes ROW_MET_AT of the way down the screen. On the
	# bench's screen and on a 19.5:9 phone's, whose longer lead is the point.
	var real_h: float = g.screen_h
	for h in [real_h, 867.0]:
		g.screen_h = h
		var seen := {"worst": 0.0, "widest_mid": 0.0, "met": 0}
		for run_seed in [5, 6, 7, 8]:
			seed(run_seed)
			await fresh()
			_scroll_a_minute(seen)
		ok(seen["met"] > 150 and seen["worst"] <= g.LEG_TIMES_SCROLL * 1.01,
				"screen %.0f px: no row up the ramp asks for more sideways speed than the plateau (%.0f of %.0f, %d rows)" % [h, seen["worst"], g.LEG_TIMES_SCROLL, seen["met"]])
		# flown at 158 px/s or faster, where rows capped by the difficulty of
		# 8 s earlier allowed legs of 210 to 280 px
		var at_25: float = g.SCROLL_BASE + (g.SCROLL_MAX - g.SCROLL_BASE) * 25.0 / g.DIFFICULTY_RAMP_TIME
		ok(seen["widest_mid"] > 0.0 and seen["widest_mid"] <= g.LEG_TIMES_SCROLL / at_25 + 0.5,
				"  the widest leg flown 25-35 s into a run is %.0f px (at most %.0f)" % [seen["widest_mid"], g.LEG_TIMES_SCROLL / at_25])
	g.screen_h = real_h
	await fresh()


# The world scrolled for a minute of a run as the game scrolls it (the bee
# left out), noting for every row the widest leg it asks for and the speed
# when its hedge has come ROW_MET_AT of the way down the screen.
func _scroll_a_minute(seen: Dictionary) -> void:
	var legs := {}                       # obstacle id -> widest leg its row asks for
	var dt := 1.0 / 60.0
	while g.elapsed < 60.0:
		g.elapsed += dt
		g.camera_y -= g._current_scroll_speed() * dt
		while g.highest_spawn_y > g.camera_y - g.screen_h:
			var prev_gx: float = g.last_gap_x
			g._spawn_row()
			legs[g.obstacles[-1].get_instance_id()] = maxf(absf(g.flowers[-1].position.x - prev_gx),
					absf(g.flowers[-1].position.x - g.obstacles[-1].gap_x))
		for o in g.obstacles:
			var id: int = o.get_instance_id()
			if legs.has(id) and o.position.y >= g.camera_y + g.screen_h * g.ROW_MET_AT:
				seen["worst"] = maxf(seen["worst"], legs[id] * g._current_scroll_speed())
				if g.elapsed > 25.0 and g.elapsed < 35.0:
					seen["widest_mid"] = maxf(seen["widest_mid"], legs[id])
				legs.erase(id)
				seen["met"] += 1


# ------------------------------------------------------------------ easy rows
func _easy_rows() -> void:
	# a new player's runs open with easy rows: wide gap near the middle, flower in the middle
	sd.best_score = g.INTRO_UNTIL_BEST - 1
	await fresh()
	var easy := 0
	for i in g.INTRO_ROWS:
		var o = g.obstacles[i]
		# the flowers have swayed by now (flower.gd, 1.5 px either way)
		if o.gap_width >= g.EASY_GAP - 0.01 and absf(o.gap_x - 200.0) <= g.EASY_GAP_SPREAD + 0.01 \
				and absf(g.flowers[i].position.x - 200.0) <= 1.6:
			easy += 1
	ok(g.new_player_run and g.INTRO_ROWS > 0 and easy == g.INTRO_ROWS, "with a record of %d a run opens with %d easy rows (%d)" % [sd.best_score, g.INTRO_ROWS, easy])
	ok(g.obstacles[g.INTRO_ROWS - 1].gap_width >= g.EASY_GAP - 0.01 and g.obstacles.size() == g.INTRO_ROWS, "  that is every row laid out before the first flap")
	g._spawn_row()
	ok(g.obstacles[-1].gap_width < g.EASY_GAP, "  and the next one is an ordinary row")
	sd.best_score = g.INTRO_UNTIL_BEST
	await fresh()
	var wide := 0
	for o in g.obstacles:
		if o.gap_width >= g.EASY_GAP - 0.01:
			wide += 1
	ok(not g.new_player_run and wide == 0, "with a record of %d the run starts on ordinary rows (%d wide)" % [sd.best_score, wide])

	# two breather rows after every 25th flower, at the same scroll speed
	seed(3)
	g.elapsed = 100.0
	while g.rows_spawned < 3 * g.MILESTONE_EVERY + 4:
		g._spawn_row()
	var wrong := []
	for i in g.obstacles.size():
		var row: int = i + 1
		var is_easy: bool = g.obstacles[i].gap_width >= g.EASY_GAP - 0.01 \
				and absf(g.obstacles[i].gap_x - 200.0) <= g.EASY_GAP_SPREAD + 0.01 and is_equal_approx(g.flowers[i].position.x, 200.0)
		var want: bool = row > g.MILESTONE_EVERY and (row - 1) % g.MILESTONE_EVERY < g.BREATHER_ROWS
		if is_easy != want:
			wrong.append(row)
	ok(g.BREATHER_ROWS > 0 and wrong.is_empty(), "rows 26-27, 51-52 and 76-77 are breathers, and no others (wrong: %s)" % [wrong])
	ok(is_equal_approx(g._current_scroll_speed(), g.SCROLL_MAX), "  the scroll keeps its speed through them")
	ok(g.obstacles.size() == g.flowers.size(), "  one flower to every row, breathers too")

	# the moments, for whatever shows them: every flower, and every 25th
	await fresh()
	var counts := []
	var milestones := []
	var on_flower := func(n: int): counts.append(n)
	var on_milestone := func(n: int): milestones.append(n)
	g.flower_collected.connect(on_flower)
	g.milestone_reached.connect(on_milestone)
	g._flap(1)
	g.score = g.MILESTONE_EVERY - 2
	for i in 3:
		g.on_flower_collected(g.flowers[0])
	g.flower_collected.disconnect(on_flower)
	g.milestone_reached.disconnect(on_milestone)
	ok(counts == [g.MILESTONE_EVERY - 1, g.MILESTONE_EVERY, g.MILESTONE_EVERY + 1],
			"flower_collected comes with every flower (%s)" % [counts])
	ok(milestones == [g.MILESTONE_EVERY], "milestone_reached only on the 25th (%s)" % [milestones])

	# the tutorial's run is known for the whole run, even after its first flap
	sd.seen_tutorial = false
	await fresh()
	ok(g.first_run, "a player who never flew gets a first run")
	g._flap(1)
	await ticks(1)
	ok(g.first_run and sd.seen_tutorial, "  still the first run after the first flap")
	await fresh()
	ok(not g.first_run, "  and the next run is not")
	sd.best_score = 10
	await fresh()


# ------------------------------------------------------------------ sky
func _sky() -> void:
	var sky = g.sky
	ok(sky.darkness(0.0) == 0.0 and sky.darkness(sky.DAY_TO_DUSK_START) == 0.0, "full day for the first %.0f s" % sky.DAY_TO_DUSK_START)
	ok(is_equal_approx(sky.darkness((sky.DAY_TO_DUSK_START + sky.DUSK_TO_NIGHT_END) / 2.0), 0.5), "dusk half way through")
	ok(sky.darkness(sky.DUSK_TO_NIGHT_END) == 1.0 and sky.darkness(9999.0) == 1.0, "night at %.0f s, and it stays night" % sky.DUSK_TO_NIGHT_END)

	await fresh()
	g.elapsed = 0.0
	await frames(2)
	ok(g.view3d.star_mat.albedo_color.a == 0.0, "no stars by day")
	ok(g.view3d.sun_disc.visible, "the sun is up by day")
	g.elapsed = sky.DUSK_TO_NIGHT_END
	await frames(2)
	ok(g.view3d.star_mat.albedo_color.a == 1.0, "stars at night")
	ok(not g.view3d.sun_disc.visible, "and the sun has set")

	# The stars belong to the sky, not to the glass of the screen: they stay
	# put in the world (their field only ever moved by whole repeats), so as
	# the bee climbs they slide down the screen with everything else, slower.
	var cam: Camera3D = g.view3d.cam
	var stars: Node3D = g.view3d.stars
	var span: float = g.view3d.STAR_SPAN
	var cam_from: float = cam.global_position.y
	var off_grid := 0
	var around := true
	for i in 30:
		g.camera_y -= 400.0
		await frames(1)
		var r := fposmod(stars.global_position.y, span)
		if minf(r, span - r) > 0.01:
			off_grid += 1
		around = around and absf(stars.global_position.y - cam.global_position.y) <= span
	ok(cam.global_position.y > cam_from + 250.0 and off_grid == 0,
			"the stars stay put in the sky while the bee climbs, so they slide down the screen (%d frames off)" % off_grid)
	ok(around, "and their field keeps around the camera, however high")
	g.camera_y += 12000.0

	await fresh()
	g.elapsed = 0.0
	for step in [[sky.MOON_SCORE, "moon"], [sky.JUPITER_SCORE, "jupiter"], [sky.SHIP_SCORE, "ufo"]]:
		var count: int = g.celestials.size()
		g.score = step[0] - 1
		await ticks(2)
		ok(g.celestials.size() == count, "nothing new in the sky at %d" % (step[0] - 1))
		g.score = step[0]
		await ticks(2)
		ok(g.celestials.size() == count + 1 and g.celestials[-1].get_meta("kind") == step[1], "the %s comes up at %d" % [step[1], step[0]])
		var body: Node2D = g.celestials[-1]
		ok(body.position.y < g.camera_y, "above the top of the screen, to scroll into view")
		await frames(2)
		ok(g.view3d.mirrors.has(body.get_instance_id()), "and is drawn")
	await ticks(5)
	ok(g.celestials.size() == 3, "each of them once a run (%d)" % g.celestials.size())
	await fresh()
	ok(g.celestials.is_empty() and not sky.moon_spawned, "a new run clears the sky and can have them all again")


# ------------------------------------------------------------------ backdrops
func _backdrops() -> void:
	var seen := {}
	var wrong := 0
	for i in 24:
		await fresh()
		await frames(1)
		var kind: String = g.sky.backdrop
		seen[kind] = true
		var trees := 0
		var backdrop := false
		for c in g.view3d.scenery.get_children():
			if c.scene_file_path.contains("tree_voxel"):
				trees += 1
			if c.scene_file_path.contains("backdrop_voxel_" + kind):
				backdrop = true
		if g.view3d.scenery_for != g.scenery_id or not backdrop:
			wrong += 1
		if (kind == "hills") != (trees > 0):
			wrong += 1
	ok(seen.has("city") and seen.has("hills"), "runs start in the city or the hills (%s)" % [seen.keys()])
	ok(wrong == 0, "each with its own backdrop, and trees only in the hills (%d wrong)" % wrong)


# ------------------------------------------------------------------ bees
func _bees() -> void:
	await fresh()
	# a record just short of the first bee, so every bee is still to be won
	sd.best_score = g.BEE_SKINS["rosy"]["score"] - 1
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	g._apply_bee_skin()
	await end_run()
	g._on_bee_menu_pressed()
	ok(g.bee_menu.visible and not g.game_over_screen.visible, "the bee menu opens from the game-over screen")
	var in_use: Dictionary = g.bee_cards["normal"]
	ok(in_use["status"].text == g._t("selected") and in_use["plate"].colors == g.VoxelPlate.PALETTES["lit"] and in_use["plate"].ink == g.GOLD,
			"the bee in use says so, on a lit card with a gold outline")
	var rosy: Dictionary = g.bee_cards["rosy"]
	var need: int = g.BEE_SKINS["rosy"]["score"]
	ok(rosy["status"].text == g._tn("goal_count", need) and rosy["run"].visible and rosy["run"].text == g._t("goal_run"),
			"a locked bee says what it takes, as the game over's chip does ('%s' / '%s')" % [rosy["status"].text, rosy["run"].text])
	ok(rosy["icon"].material == g.silhouette_mat and rosy["lock"].visible, "  as a silhouette, with a lock")
	var fill: Color = g.SILHOUETTE
	var face: Color = g.VoxelPlate.PALETTES["dark"]["face"]
	ok(_contrast(fill, face) >= 3.0, "  which reads on the card (%.1f:1, it was 1.6:1)" % _contrast(fill, face))
	await silence()
	var x0: float = rosy["button"].position.x
	g._on_bee_card_pressed("rosy")
	ok(sd.selected_bee == "normal", "and can't be picked")
	var moved := false
	var low_click := false
	for v in g.sfx_pool:
		low_click = low_click or (v.playing and v.pitch_scale < 1.0)
	for i in 6:
		await process_frame
		moved = moved or rosy["button"].position.x != x0
	await frames(12)
	ok(moved and rosy["button"].position.x == x0 and low_click, "  but a tap on it shakes its card, with a lower click, and puts it back")
	sd.best_score = need
	g._refresh_bee_menu()
	ok(rosy["status"].text == "" and not rosy["run"].visible and rosy["icon"].material == null and not rosy["lock"].visible,
			"a bee won and not in use shows its name alone, in its colours")
	sd.best_score = need - 1
	g._refresh_bee_menu()
	g._on_bee_menu_closed()
	ok(not g.bee_menu.visible and g.game_over_screen.visible, "closing the menu brings the game-over screen back")

	await fresh()
	g._flap(1)
	for s in range(1, 301):
		g.score = s
		g._check_bee_unlocks()
	ok(sd.unlocked_bees == ["rosy", "mint", "ice", "grape", "queen", "shining"], "every bee is won at its score, in order (%s)" % [sd.unlocked_bees])
	var hardest := ""
	for id in g.BEE_ORDER:
		if hardest == "" or g.BEE_SKINS[id]["score"] > g.BEE_SKINS[hardest]["score"]:
			hardest = id
	ok(hardest == "shining" and g.BEE_SKINS["shining"]["score"] == 300, "the silver bee stays the hardest, at 300")
	ok(g.notice_now.get("kind") == "bee" and g.notice_title.text == g._t("unlocked") % "Silver Bee", "the notice names the last one won")
	sd.load_data()
	ok(sd.unlocked_bees.size() == 6, "and they are in the save file at once, before the run ends")
	await end_run("hedge")
	ok(g.goal_title.text == g._t("unlocked") % "Silver Bee", "the game over shows the last bee won")
	g.bees_won_this_run = []
	g._refresh_goal_chip()
	ok(not g.goal_chip.visible, "with every bee won there is no next one to aim for")

	for id in g.BEE_ORDER:
		g._on_bee_card_pressed(id)
		await frames(2)
		var v = g.view3d
		ok(sd.selected_bee == id and g.applied_bee_skin == id, "picking '%s' puts it on" % id)
		ok(v.wing_l != null and v.wing_r != null and v.dead_eyes != null and not v.live_eyes.is_empty(),
				"'%s' has its wings and both pairs of eyes" % id)
		var coloured: bool = not v.bee_mats.is_empty()
		for m in v.bee_mats:
			coloured = coloured and m.vertex_color_use_as_albedo
		ok(coloured, "'%s' is drawn in its own colours" % id)
		ok(v.bee_glows == g.BEE_SKINS[id]["glow"], "'%s' glows only if it should" % id)
		ok(g.bee_cards[id]["status"].text == g._t("selected"), "its card says it is in use")
		var shown := true
		for icon in g.bee_button_icons:
			shown = shown and icon.texture.resource_path == g._bee_icon_path(id)
		ok(shown, "and the bee buttons show it")
		g.bee.dead = true
		await frames(2)
		var dead_face: bool = v.dead_eyes.visible
		for e in v.live_eyes:
			dead_face = dead_face and not e.visible
		g.bee.dead = false
		await frames(2)
		ok(dead_face and not v.dead_eyes.visible, "'%s' has a face for dying, and back" % id)
	ok(g.view3d.sparkles.size() > 0, "the silver bee sparkles (%d stars)" % g.view3d.sparkles.size())

	sd.unlocked_bees = []
	sd.best_score = 300
	ok(g._bee_unlocked("shining"), "a record that covers a bee counts as winning it")
	sd.best_score = 10
	ok(g._current_bee_skin() == "normal", "and a bee picked but no longer won falls back to the normal one")
	sd.selected_bee = "normal"
	g._apply_bee_skin()
	g._on_bee_menu_closed()


# ------------------------------------------------------------------ record line
func _record_line() -> void:
	sd.best_score = 3
	await fresh()
	ok(g.record_line != null, "with a record of 3 a record line is drawn")
	ok(g.record_line != null and is_equal_approx(g.record_line.position.y, g.flowers[3].position.y), "level with the 4th flower, the one that beats it")
	await frames(2)
	ok(g.view3d.record3d != null, "in cubes")
	for i in 3:
		g.on_flower_collected(g.flowers[0])
	ok(g.score == 3 and g.record_line != null, "still there at 3")
	# The 4th one flown into, so it is picked up inside the physics step as in
	# a real run: the 2D line is freed before view3d looks at it again.
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	g.bee.velocity = Vector2.ZERO
	var line3d = g.view3d.record3d
	var f = g.flowers[0]
	g.camera_y = f.position.y - g.screen_h * 0.5
	g.bee.position = f.position
	await ticks(4)
	ok(g.score == 4 and g.record_line == null, "and gone at 4")
	await frames(2)
	ok(g.view3d.record3d == null, "in 3D too")
	ok(is_instance_valid(line3d) and line3d.scale.y != 1.0, "where it flashes on its way out")
	sd.best_score = 0
	await fresh()
	ok(g.record_line == null, "no record line before there is a record")
	sd.best_score = 10


# ------------------------------------------------------------------ near miss
func _near_miss() -> void:
	await fresh()
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	g.bee.velocity = Vector2.ZERO
	var o = g.obstacles[0]
	g.camera_y = o.position.y - g.screen_h * 0.5
	g.camera_shake_time = 0.0
	g.bee.position = Vector2(o.gap_x - o.gap_width / 2.0 + g.bee.radius + 3.0, o.position.y + 11.0)
	await ticks(2)
	ok(g.state == g.State.PLAYING, "passing 3 px from a hedge is not a hit")
	ok(g.camera_shake_time == 0.0, "no shake until it is past")
	g.bee.position.y = o.position.y - 60.0
	await ticks(1)
	ok(g.camera_shake_time > 0.0 and o.near_miss_checked, "then the screen shakes: a near miss")
	ok(g.camera_shake_magnitude <= 2.0 and g.camera_shake_magnitude < g.DEATH_SHAKE_MAGNITUDE / 3.0,
			"  a shiver of %.0f px, nothing like the death shake's %.0f" % [g.camera_shake_magnitude, g.DEATH_SHAKE_MAGNITUDE])

	await fresh()
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	g.bee.velocity = Vector2.ZERO
	o = g.obstacles[0]
	g.camera_y = o.position.y - g.screen_h * 0.5
	g.camera_shake_time = 0.0
	g.bee.position = Vector2(o.gap_x, o.position.y + 11.0)
	await ticks(2)
	g.bee.position.y = o.position.y - 60.0
	await ticks(1)
	ok(g.state == g.State.PLAYING and g.camera_shake_time == 0.0, "the middle of a gap is a clean pass, no shake")


# ------------------------------------------------------------------ a real pickup
func _pickup() -> void:
	await fresh()
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	g.bee.velocity = Vector2.ZERO
	var f = g.flowers[0]
	g.camera_y = f.position.y - g.screen_h * 0.5
	g.bee.position = f.position
	await ticks(4)
	ok(g.score == 1 and not g.flowers.has(f) and f.collected, "flying into a flower picks it up (score %d)" % g.score)
	await frames(2)
	var m = g.view3d.mirrors.get(f.get_instance_id())
	ok(m != null and m.has_meta("burst") and not m.visible, "and it bursts into cubes")
	await ticks(45)
	ok(not is_instance_valid(f), "then it is gone")
	ok(g.state == g.State.PLAYING, "the run goes on")


# ------------------------------------------------------------------ pause menu
func _pause_menu() -> void:
	await fresh()
	ok(g.score_label.visible and g.record_label.visible and g.pause_button.visible, "a run shows the score, the record and the pause button")
	g._flap(1)
	await ticks(2)
	g.pause_button.pressed.emit()
	ok(g.state == g.State.PAUSED and g.pause_screen.visible and paused, "the pause button pauses")
	ok(not g.privacy_button.visible, "no ad-privacy entry where there are no ads")
	ok(is_equal_approx(g.credits_button.position.y, g.privacy_button.position.y), "so the credits take its place")
	var resume_rect := Rect2()
	var restart_rect := Rect2()
	for c in g.pause_screen.get_children():
		if c is Button and c.has_meta("content"):
			var words: Label = c.get_meta("content").get_child(0) if c.get_meta("content").get_child_count() > 0 and c.get_meta("content").get_child(0) is Label else null
			if words != null and words.text == g._t("resume"):
				resume_rect = c.get_global_rect()
			elif words != null and words.text == g._t("restart"):
				restart_rect = c.get_global_rect()
	ok(restart_rect.position.y - resume_rect.end.y >= 40.0, "'restart' is %.0f u under 'resume', out of a slip's way" % (restart_rect.position.y - resume_rect.end.y))
	var named := true
	for spec in g.TOGGLES:
		var v: Dictionary = g.toggle_views[spec["id"]][0]
		named = named and v["caption"].text == g._t(spec["text"]) and v["caption"].is_visible_in_tree()
	ok(named and g.TOGGLES.size() == 4, "the menu's four switches have their names under them")
	ok(g.privacy_button.position.y > g.toggle_views["music"][0]["caption"].get_global_rect().end.y, "  and the links come after them")
	var y: float = g.bee.position.y
	var cy: float = g.camera_y
	for i in 30:
		await physics_frame
	ok(g.bee.position.y == y and g.camera_y == cy, "nothing moves while paused")

	var was: bool = sd.music_muted
	g._on_music_toggle_pressed()
	ok(sd.music_muted != was and g.music_slash.visible == sd.music_muted, "the music switch flips")
	ok(g.music.volume_db == (g.MUSIC_MUTED_DB if sd.music_muted else g.MUSIC_VOLUME_DB), "and sets the volume (%.0f dB)" % g.music.volume_db)
	ok(g.music.playing, "the music keeps running underneath, to pick up where it was")
	g._on_music_toggle_pressed()
	ok(sd.music_muted == was, "and back")
	var vib: bool = sd.vibration
	g._on_vibration_toggle_pressed()
	ok(sd.vibration != vib and g.vibrate_slash.visible == not sd.vibration, "the vibration switch flips")
	g._on_vibration_toggle_pressed()
	ok(sd.vibration == vib, "and back")

	g.score = 7
	g._on_pause_restart_pressed()
	ok(not paused, "'restart' unpauses the game")
	await ticks(1)
	ok(g.state == g.State.PLAYING and g.score == 0 and not paused and not g.pause_screen.visible, "'restart' in the pause menu starts over")
	ok(not g.world_moving and g.bee.position.y < 0.0, "with the bee back on the grass")

	g._flap(1)
	await ticks(1)
	g.score = 25
	g._check_bee_unlocks()
	ok(g.notice.visible and g.notice_now.get("kind") == "bee", "a bee won shows its notice")
	await frames(20)                       # in its place, in the top row
	g._on_pause_pressed()
	var title_rect := Rect2()
	for c in g.pause_screen.get_children():
		if c is Label:
			title_rect = c.get_global_rect()
	ok(g.notice.get_index() < g.pause_screen.get_index() and not g.notice.get_global_rect().intersects(title_rect),
			"when the game pauses it stays under the menu's dim, nowhere near the 'Paused' title")
	var held: float = g.notice_tween.get_total_elapsed_time()
	await frames(30)
	ok(g.notice_tween.get_total_elapsed_time() == held, "  and waits there, frozen with the run")
	g._on_pause_restart_pressed()
	await ticks(1)
	ok(g.notice_now.get("kind") != "bee", "a bee's notice doesn't carry over into a restart from the pause menu")
	sd.unlocked_bees = []


# ------------------------------------------------------------------ back button, leaving the app
func _back_and_focus() -> void:
	await fresh()
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(g.state == g.State.PAUSED and paused, "leaving the app mid-run pauses it")
	g._on_resume_pressed()
	g._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ok(g.state == g.State.PAUSED, "so does the app being put away")
	g._on_resume_pressed()

	g._flap(1)
	g._trigger_game_over("fall")
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(g.state == g.State.DYING, "back does nothing while the bee falls")
	g.dying_timer = 99.0
	await ticks(2)
	ok(g.state == g.State.GAMEOVER, "the fall ends on the game-over screen")
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(g.state == g.State.GAMEOVER and not paused, "leaving the app there changes nothing")
	g.game_over_msec -= 1000
	g._on_bee_menu_pressed()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(not g.bee_menu.visible and g.game_over_screen.visible and g.state == g.State.GAMEOVER, "back closes the bee menu, back to the game over")
	g._on_bee_menu_pressed()
	await key(KEY_ESCAPE)
	ok(not g.bee_menu.visible and g.game_over_screen.visible, "and so does escape, on a computer")
	g.game_over_msec = Time.get_ticks_msec()
	await key(KEY_ENTER)
	ok(g.state == g.State.GAMEOVER, "a key on the game over waits out its first instant")


# ------------------------------------------------------------------ the first run
func _tutorial() -> void:
	sd.seen_tutorial = false
	await fresh()                          # the ground scene, as a first launch builds it
	g.state = g.State.START
	g.start_screen.visible = true
	g.game_over_screen.visible = false
	g.pause_button.visible = false
	g._set_hud_visible(false)
	ok(g.hint_alpha == 1.0 and not g.has_tapped_once, "a first run has its tutorial ready")
	g.play_button.pressed.emit()
	g.play_button.pressed.emit()           # an impatient double tap
	ok(g.state == g.State.STARTING and not sd.seen_tutorial, "play starts it, once")
	for i in 90:
		await process_frame
	ok(g.state == g.State.PLAYING and not g.start_screen.visible, "the title fades out into the run")
	ok(g.direction_hint.visible and g.direction_hint.modulate.a > 0.9, "the arrows show which side goes which way")
	var things := [[g._screen_pos(g.bee.position), g.bee.radius]]
	for fl in g.flowers:
		things.append([g._screen_pos(fl.position, 0.1), g.FlowerScript.FLOWER_R])
	var crossed := 0
	var hidden := 0
	for d in g.hint_line.get_children():
		if not d.visible:
			hidden += 1
			continue
		for t in things:
			if g._circle_in_rect(t[0], t[1], d.get_global_rect()):
				crossed += 1
	ok(crossed == 0 and hidden > 0, "  the dashed line gives way around the flowers and the bee (%d dashes hidden, %d crossing)" % [hidden, crossed])
	ok(not g.world_moving, "and the bee waits on the grass for the first tap")
	g._on_pause_pressed()
	g._on_pause_restart_pressed()
	await ticks(2)
	ok(g.direction_hint.visible and g.hint_alpha == 1.0 and not sd.seen_tutorial, "a restart from the pause menu before flying keeps the arrows")
	g._flap(-1)
	ok(sd.seen_tutorial, "the first flap is what marks the tutorial as seen")
	await ticks(30)
	ok(not g.direction_hint.visible and g.state == g.State.PLAYING, "the arrows go once it has flown")


# ------------------------------------------------------------------ the rule plate
func _rule_plate() -> void:
	sd.seen_tutorial = false
	sd.best_score = 10
	await fresh()
	ok(g.first_run and g.rule_on and g.notice_now.get("kind") == "rule" and g.notice_title.text == g._t("rule"),
			"the first run puts the rule up: '%s'" % g.notice_title.text)
	await frames(20)
	var plate: Rect2 = g.notice.get_global_rect()
	var score_top: float = g.score_label.position.y + 6.0
	var clear: bool = plate.end.y <= score_top and plate.end.x <= g.pause_button.position.x - 3.0 and plate.position.x >= 0.0
	for c in g.direction_hint.get_children():
		if c != g.hint_line and c.get_global_rect().intersects(plate):
			clear = false
	for d in g.hint_line.get_children():
		if d.get_global_rect().intersects(plate):
			clear = false
	ok(g.notice.visible and clear, "  in the top row: clear of the arrows, the score and the pause button (%s)" % plate)
	ok(g.record_label.modulate.a < 0.05, "  the record readout steps aside under it")
	for i in g.RULE_UNTIL_FLOWER - 1:
		g.on_flower_collected(g.flowers[0])
	ok(g.rule_on and g.notice_now.get("kind") == "rule", "  still up after %d flowers" % (g.RULE_UNTIL_FLOWER - 1))
	g.on_flower_collected(g.flowers[0])
	ok(not g.rule_on and not g.rule_due, "  and done with at flower %d" % g.RULE_UNTIL_FLOWER)
	await frames(30)
	ok(not g.notice.visible and g.record_label.modulate.a > 0.95, "  the record readout is back")

	sd.seen_tutorial = true                # as the run's first flap would have
	await fresh()
	ok(not g.rule_on and not g.notice.visible, "the next run starts without it")
	g._flap(1)
	await ticks(1)
	var lost = g.flowers[0]
	g.camera_y = lost.position.y - g.FlowerScript.FLOWER_R - g.screen_h - 2.0
	await ticks(2)
	ok(g.death_cause == "flower" and g.rule_due, "a run lost to a missed flower")
	await fresh()
	ok(g.rule_on and g.notice_now.get("kind") == "rule", "  puts the rule up again on the next one")
	g._flap(1)
	await end_run("hedge")
	await fresh()
	ok(g.rule_on, "  and so does the one after, if that one ended before flower %d" % g.RULE_UNTIL_FLOWER)
	g.rule_due = false
	sd.best_score = 200
	await fresh()
	g._flap(1)
	await ticks(1)
	lost = g.flowers[0]
	g.camera_y = lost.position.y - g.FlowerScript.FLOWER_R - g.screen_h - 2.0
	await ticks(2)
	ok(g.death_cause == "flower" and not g.rule_due, "a veteran (record 200) losing a flower does not get the beginner's rule back")
	await fresh()
	ok(not g.rule_on and g.record_label.text == g._t("record") % 200, "  and starts the next run with '%s'" % g.record_label.text)
	sd.best_score = 10
	g.rule_due = false
	await fresh()


# ------------------------------------------------------------------ the notice slot
func _notice_slot() -> void:
	sd.best_score = 10
	sd.unlocked_bees = []
	g.rule_due = false
	await fresh()                          # not flown: the world holds still for the checks
	# the 25th flower also wins Mint: one notice, the bee's, and its jingle alone
	g.score = g.BEE_SKINS["mint"]["score"] - 1
	g.on_flower_collected(g.flowers[0])
	ok(g.score % g.MILESTONE_EVERY == 0 and g.notice_now.get("kind") == "bee" and g.notice_queue.is_empty(),
			"a milestone on a bee's flower leaves the slot to the bee (%s, %d waiting)" % [g.notice_title.text, g.notice_queue.size()])
	await frames(6)
	var notes := 0
	for v in g.sfx_pool:
		if v.playing and v.stream == g.SFX_COLLECT and v.pitch_scale >= 2.0:
			notes += 1
	ok(notes == 0, "  and plays none of its notes")

	# a milestone of its own: "25!", two notes, under a second
	sd.unlocked_bees = ["rosy", "mint"]
	await fresh()
	await silence()
	g.score = g.MILESTONE_EVERY - 1
	g.on_flower_collected(g.flowers[0])
	ok(g.notice_now.get("kind") == "milestone" and g.notice_title.text == g._t("milestone") % g.MILESTONE_EVERY
			and g.notice_flowers[0].visible and g.notice_flowers[1].visible, "the %dth flower says '%s' between two flowers" % [g.MILESTONE_EVERY, g.notice_title.text])
	var heard := {}
	var shown := 0
	for i in 90:
		await process_frame
		if g.notice.visible:
			shown += 1
		for v in g.sfx_pool:
			if v.playing and v.stream == g.SFX_COLLECT and is_equal_approx(v.volume_db, g.SFX_MILESTONE_DB):
				heard[snappedf(v.pitch_scale, 0.01)] = true
	ok(heard.has(2.0) and heard.has(3.0), "  with the pickup's note an octave up, then a fifth above (%s)" % [heard.keys()])
	ok(shown > 20 and shown < 60, "  on screen for %.2f s, under one" % (shown / 60.0))
	ok(g.notice_now.is_empty() and g.record_label.modulate.a > 0.95, "  then the record readout is back")
	await fresh()
	await silence()
	g._flap(1)
	await ticks(1)
	g.score = 2 * g.MILESTONE_EVERY - 1
	g.on_flower_collected(g.flowers[0])
	g._trigger_game_over("hedge")       # a hedge right after the milestone
	var late := 0
	for i in 30:
		await process_frame
		for v in g.sfx_pool:
			if v.playing and v.stream == g.SFX_COLLECT and is_equal_approx(v.volume_db, g.SFX_MILESTONE_DB):
				late += 1
	ok(late == 0, "  a run that ends right after a milestone does not play its notes over the death")
	g.dying_timer = 99.0
	await ticks(2)
	await fresh()
	var slot: Rect2 = Rect2(g.notice.position, g.notice.size)
	ok(slot.end.y <= g.score_label.position.y + 6.0 and slot.end.x <= g.pause_button.position.x - 3.0,
			"  in the top row, above the score and clear of the pause button (%s)" % slot)

	# a more important one cuts in; a less important one waits its turn, if it is still fresh
	g._notify({"kind": "milestone", "title": "50!", "flowers": 2})
	g._show_bee_notice("ice")
	ok(g.notice_now.get("kind") == "bee" and g.notice_queue.is_empty(), "a bee cuts a milestone short")
	g._notify({"kind": "milestone", "title": "75!", "flowers": 2})
	ok(g.notice_now.get("kind") == "bee" and g.notice_queue.size() == 1, "  a milestone during a bee's notice waits")
	g._notice_leave()
	await frames(int(g.NOTICE_OUT * 60.0) + 3)
	ok(g.notice_now.get("kind") == "milestone" and g.notice_title.text == "75!", "  and comes once the bee's is done")
	g._show_bee_notice("grape")
	g._notify({"kind": "milestone", "title": "100!", "flowers": 2})
	await ticks(int(g.NOTICE_KINDS["milestone"]["stale"] * 60.0) + 5)
	g._notice_leave()
	await frames(int(g.NOTICE_OUT * 60.0) + 3)
	ok(g.notice_now.is_empty() and not g.notice.visible, "  unless it has gone stale by then")
	# the old banner hung over the hedges coming in; the slot is the top row
	g._show_bee_notice("shining")
	await frames(20)
	ok(Rect2(g.notice.position, g.notice.size).end.y <= g.score_label.position.y + 6.0, "the widest bee's notice stays in the top row too")
	await end_run()
	ok(g.notice_now.is_empty() and not g.notice.visible, "the game over clears the slot")
	sd.unlocked_bees = []
	sd.best_score = 10


# ------------------------------------------------------------------ the record readout
func _record_readout() -> void:
	sd.best_score = 3
	sd.unlocked_bees = ["rosy", "mint", "ice", "grape", "queen", "shining"]
	g.rule_due = false
	await fresh()
	ok(g.record_label.text == g._t("record") % 3, "a run starts with the record to beat: '%s'" % g.record_label.text)
	for i in 3:
		g.on_flower_collected(g.flowers[0])
	ok(g.record_label.text == g._t("record") % 3, "  level with it, still")
	g.on_flower_collected(g.flowers[0])
	var gold: Color = g.record_label.get_theme_color("font_color")
	ok(g.record_label.text == g._t("record_beaten") and gold.is_equal_approx(g.GOLD), "past it, the readout says '%s', in gold" % g.record_label.text)
	ok(g.record_pop != null and g.record_pop.is_valid(), "  with a little jump")
	g.on_flower_collected(g.flowers[0])
	ok(g.record_label.text == g._t("record_beaten"), "  for the rest of the run")
	await fresh()
	ok(g.record_label.text == g._t("record") % 3 and g.record_label.get_theme_color("font_color").is_equal_approx(Color(1, 1, 1, 0.9)),
			"  and a new run starts from the record again")
	# a first score is no record to celebrate
	sd.best_score = 0
	await fresh()
	g._flap(1)
	await ticks(1)
	g.on_flower_collected(g.flowers[0])
	ok(g.score == 1 and g.record_label.text == g._t("record") % 0 and not g.record_pop_due, "from a record of 0, the first flower is not 'New record!' ('%s')" % g.record_label.text)
	await silence()
	await end_run("fall")
	var jingle := false
	for v in g.sfx_pool:
		jingle = jingle or (v.playing and v.stream == g.SFX_RECORD)
	ok(sd.best_score == 1 and not g.new_record_badge.visible and not jingle and g.record_note.text == ""
			and g.final_best_label.visible, "  and its game over is the plain board, no jingle (best saved: %d)" % sd.best_score)
	sd.best_score = 3
	await fresh()
	# passed under a notice, the jump waits for the readout to come back
	g._show_bee_notice("rosy")
	g.score = 3
	g.on_flower_collected(g.flowers[0])
	ok(g.record_pop_due, "passed while a notice covers it, the jump waits")
	g._notice_leave()
	await frames(int(g.NOTICE_OUT * 60.0) + 3)
	ok(not g.record_pop_due and g.record_pop.is_valid(), "  for the notice to go")
	sd.unlocked_bees = []
	sd.best_score = 10
	await fresh()


# ------------------------------------------------------------------ the resume's countdown
func _countdown() -> void:
	g.rule_due = false
	await fresh()
	g._on_pause_pressed()
	g._on_resume_pressed()
	ok(g.state == g.State.PLAYING and not paused, "a run that hasn't flown yet resumes at once")
	g._flap(1)
	await ticks(2)
	g._on_pause_pressed()
	await frames(2)
	var y: float = g.bee.position.y
	var cy: float = g.camera_y
	await silence()
	g._on_resume_pressed()
	ok(g.state == g.State.RESUMING and paused and not g.pause_screen.visible and g.countdown_label.visible and g.countdown_label.text == "3",
			"resuming a run in flight counts down first: '%s'" % g.countdown_label.text)
	ok(g.pause_button.visible, "  with the pause button there to stop it")
	var tick := false
	for v in g.sfx_pool:
		tick = tick or (v.playing and v.stream == g.SFX_UI_TAP and is_equal_approx(v.volume_db, g.SFX_COUNTDOWN_DB))
	ok(tick and g.countdown_ticks == 1, "  a tick on each number")
	var cd := Rect2(g.countdown_label.position, g.countdown_label.size)
	var cd_clear: bool = not g._circle_in_rect(g._screen_pos(g.bee.position), g.bee.radius, cd)
	var fallback: bool = is_equal_approx(cd.get_center().x, g.SCREEN_W / 2.0)
	for fl in g.flowers:
		if not fallback and g._circle_in_rect(g._screen_pos(fl.position, 0.1), g.FlowerScript.FLOWER_R, cd):
			cd_clear = false
	var score_box := Rect2(0.0, g.score_label.position.y, g.SCREEN_W, g.score_label.size.y)
	ok(cd_clear and not cd.intersects(score_box) and not cd.intersects(g.pause_button.get_global_rect()),
			"  its digit is clear of the bee, the flowers, the score and the pause button (%s)" % cd)
	await frames(int(g.COUNTDOWN_STEP * 60.0) + 2)
	ok(g.countdown_label.text == "2" and g.bee.position.y == y and g.camera_y == cy, "  '2', and nothing has moved")
	await key(KEY_ESCAPE)
	ok(g.state == g.State.PAUSED and g.pause_screen.visible and not g.countdown_label.visible and paused, "escape during it goes back to the pause menu")
	g._on_resume_pressed()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(g.state == g.State.PAUSED and g.pause_screen.visible, "  so does back")
	g._on_resume_pressed()
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(g.state == g.State.PAUSED, "  and leaving the app")
	g._on_resume_pressed()
	var waited := 0
	while g.state == g.State.RESUMING and waited < 300:
		await process_frame
		waited += 1
	ok(g.state == g.State.PLAYING and not paused and not g.countdown_label.visible and g.countdown_ticks == 3,
			"3, 2, 1 and the run goes on, after %.2f s" % (waited / 60.0))
	ok(absf(waited / 60.0 - 3.0 * g.COUNTDOWN_STEP) < 0.1, "  which is %.2f s" % (3.0 * g.COUNTDOWN_STEP))
	await ticks(3)
	ok(g.bee.position.y != y, "  and the bee flies again")


# ------------------------------------------------------------------ near miss, a lost flower, the score's digits
func _close_calls() -> void:
	g.rule_due = false
	await fresh()
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	g.bee.velocity = Vector2.ZERO
	var o = g.obstacles[0]
	g.camera_y = o.position.y - g.screen_h * 0.5
	g.bee.position = Vector2(o.gap_x - o.gap_width / 2.0 + g.bee.radius + 3.0, o.position.y + 11.0)
	await ticks(2)
	g.bee.position.y = o.position.y - 60.0
	await ticks(1)
	await frames(1)
	var at: Vector2 = g._screen_pos(g.bee.position)
	var word: Vector2 = g.phew_label.position + g.phew_label.size / 2.0
	ok(g.phew_label.visible and g.phew_label.text == g._t("phew") and word.distance_to(at) < 90.0,
			"a near miss says '%s' beside the bee (%.0f px from it)" % [g.phew_label.text, word.distance_to(at)])
	var y0: float = g.phew_label.position.y
	await frames(15)
	ok(g.phew_label.position.y < y0, "  rising")
	await frames(30)
	ok(not g.phew_label.visible, "  and gone in about half a second")

	# a flower lost: the marker at its x on the bottom edge, blinking through the fall
	await fresh()
	g._flap(1)
	await ticks(1)
	g.bee.physics_enabled = false
	var lost = g.flowers[0]
	g.camera_y = lost.position.y - g.FlowerScript.FLOWER_R - g.screen_h - 2.0
	g.bee.position = Vector2(200.0, g.camera_y + g.screen_h * 0.4)
	await ticks(2)
	await frames(2)
	var lx: float = g.view3d.screen_pos_for(lost.position, Vector2(0.0, g.camera_y), 0.1).x
	var mark: Rect2 = g.lost_marker.get_global_rect()
	ok(g.state == g.State.DYING and g.lost_marker.visible, "a run lost to a flower points at it")
	ok(absf(mark.get_center().x - clampf(lx, 22.0, g.SCREEN_W - 22.0)) <= 1.0 and mark.end.y <= g.screen_h and mark.end.y > g.screen_h * 0.75,
			"  at its x (%.0f), on the bottom edge (%.0f to %.0f)" % [lx, mark.position.y, mark.end.y])
	var alphas := {}
	for i in 20:
		await process_frame
		alphas[g.lost_marker.modulate.a] = true
	ok(alphas.size() == 2, "  blinking while the bee falls")
	g.dying_timer = 99.0
	await ticks(2)
	await frames(2)
	var clear: bool = not mark.intersects(g.restart_button.get_global_rect())
	for c in g.game_over_screen.get_children():
		if c is Button and c.visible and c.get_global_rect().intersects(mark):
			clear = false
	ok(g.state == g.State.GAMEOVER and g.lost_marker.visible and g.lost_marker.modulate.a == 1.0 and clear,
			"  then still, on the game over, under its buttons")
	g.game_over_msec -= 1000
	g._on_restart_pressed()
	ok(not g.lost_marker.visible, "  and gone with the next run")

	# a flower behind the score's digits: they fade while it is there
	g.rule_due = false
	await fresh()
	var f = g.flowers[0]
	f._base_x = g.SCREEN_W / 2.0
	g.bee.position = Vector2(60.0, g.bee.position.y)
	var want_y: float = g.score_label.position.y + 32.0
	g.camera_y = f.position.y - want_y
	for k in 3:
		await ticks(1)
		await frames(1)
		g.camera_y += g._screen_pos(f.position, 0.1).y - want_y
	await ticks(1)
	await frames(15)
	ok(g.score_label.modulate.a <= 0.5 and is_equal_approx(g.score_label.modulate.a, g.SCORE_BEHIND_ALPHA), "a flower behind the score's digits fades them (to %.2f, flower at %s)" % [g.score_label.modulate.a, g._screen_pos(f.position, 0.1)])
	g.camera_y -= g.OBSTACLE_SPACING / 2.0     # half a row: between two flowers
	await ticks(1)
	await frames(15)
	ok(g.score_label.modulate.a == 1.0, "  and they come back once it has gone by")
	await fresh()


# ------------------------------------------------------------------ the settings panel
# The title screen again, over a fresh ground scene.
func title() -> void:
	await fresh()
	g.state = g.State.START
	g.start_screen.visible = true
	g.game_over_screen.visible = false
	g.pause_button.visible = false
	g._set_hud_visible(false)
	g._clear_notices()
	await frames(2)


func gear_on(screen: Control) -> Button:
	for gear in g.gear_buttons:
		if screen.is_ancestor_of(gear):
			return gear
	return null


func _settings() -> void:
	await title()
	var gear := gear_on(g.start_screen)
	var pause_plate: Control = g.pause_button.get_meta("plate")
	ok(gear != null and gear.is_visible_in_tree(), "the title has the settings' gear")
	ok(gear != null and gear.get_meta("plate").get_global_rect().is_equal_approx(pause_plate.get_global_rect()),
			"  in the corner where a run has its pause button")
	gear.pressed.emit()
	ok(g.settings_screen.visible and not g.start_screen.visible and g.state == g.State.START, "it opens the settings, over the title")
	var shown := true
	for spec in g.TOGGLES:
		var copies: Array = g.toggle_views[spec["id"]]
		shown = shown and copies.size() == 2 and copies[1]["button"].is_visible_in_tree() \
				and copies[1]["caption"].text == g._t(spec["text"])
	ok(shown, "with the pause menu's four switches, named (%s)" % ", ".join(g.TOGGLES.map(func(t): return g._t(t["text"]))))
	ok(not g.settings_privacy.visible and g.settings_credits.is_visible_in_tree()
			and is_equal_approx(g.settings_credits.position.y, g.settings_privacy.position.y), "  the credits, and no ad privacy where there are no ads")

	# one setting, two switches: flipped here, it shows in the pause menu
	var was: bool = sd.music_muted
	g.toggle_views["music"][1]["button"].pressed.emit()
	var both := true
	for v in g.toggle_views["music"]:
		both = both and v["slash"].visible == sd.music_muted and v["plate"].ink == (g.GOLD if not sd.music_muted else Color(1, 1, 1, 0.5))
	ok(sd.music_muted != was and both, "a switch flipped in the settings shows in both copies (gold on, struck through off)")
	ok(g.music.volume_db == (g.MUSIC_MUTED_DB if sd.music_muted else g.MUSIC_VOLUME_DB), "  and does what it says")
	g.toggle_views["music"][1]["button"].pressed.emit()
	ok(sd.music_muted == was, "  and back")

	# the screen shake switch, honoured by the camera
	g.toggle_views["shake"][1]["button"].pressed.emit()
	ok(not sd.screen_shake and g.shake_slash.visible, "the shake switch turns the screen shake off")
	g._start_camera_shake(g.DEATH_SHAKE_DURATION, g.DEATH_SHAKE_MAGNITUDE)
	ok(g.camera_shake_time == 0.0, "  and then nothing shakes, not even a death")
	sd.load_data()
	ok(not sd.screen_shake, "  it is kept in the save")
	g.toggle_views["shake"][1]["button"].pressed.emit()
	g._start_camera_shake(g.DEATH_SHAKE_DURATION, g.DEATH_SHAKE_MAGNITUDE)
	ok(sd.screen_shake and g.camera_shake_time > 0.0 and not g.shake_slash.visible, "  on again, it shakes")
	g.camera_shake_time = 0.0

	await key(KEY_SPACE)
	ok(g.state == g.State.START, "space doesn't start a run from under the settings")
	g.settings_credits.pressed.emit()
	await frames(2)
	ok(g.credits_screen.visible and g.settings_screen.visible, "the credits open from the settings")
	await key(KEY_ESCAPE)
	ok(not g.credits_screen.visible and g.settings_screen.visible, "escape closes the credits, back to the settings")
	await key(KEY_ESCAPE)
	ok(not g.settings_screen.visible and g.start_screen.visible and g.state == g.State.START, "  and again closes the settings, back to the title")
	gear.pressed.emit()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(not g.settings_screen.visible and g.start_screen.visible, "back closes them too (instead of leaving the app)")

	# on the game over, behind its lock
	await fresh()
	g._flap(1)
	g._trigger_game_over("fall")
	g.dying_timer = 99.0
	await ticks(2)
	await frames(1)
	gear = gear_on(g.game_over_screen)
	ok(gear != null and gear.is_visible_in_tree() and gear.disabled, "the game over has the gear, held in its first instant")
	g._on_settings_pressed()
	ok(not g.settings_screen.visible, "  where it doesn't open")
	g.game_over_msec -= 1000
	await frames(1)
	gear.pressed.emit()
	ok(not gear.disabled and g.settings_screen.visible and not g.game_over_screen.visible, "  then it does")
	await key(KEY_ESCAPE)
	ok(not g.settings_screen.visible and g.game_over_screen.visible and g.state == g.State.GAMEOVER, "  and closes back to the game over")

	await fresh()
	g._on_settings_pressed()
	ok(not g.settings_screen.visible, "no settings panel in the middle of a run (the pause menu has the switches)")


# ------------------------------------------------------------------ the game-over screen
# A run that ends with `final` flowers, the record being `best` when it began.
func ended_run(best: int, final: int, cause := "fall") -> void:
	sd.best_score = best
	await fresh()
	g._flap(1)
	await ticks(1)
	for s in range(1, final + 1):
		g.score = s
		g._check_bee_unlocks()
	g._trigger_game_over(cause)
	g.dying_timer = 99.0
	await ticks(2)


func _game_over_screen() -> void:
	sd.unlocked_bees = ["rosy"]
	sd.selected_bee = "normal"
	g.rule_due = false
	await ended_run(20, 17)
	ok(g.state == g.State.GAMEOVER and g.game_over_screen.visible, "a run of 17 under a record of 20 ends")
	ok(g.final_score_label.text.to_int() < 17, "  its score counting up from 0 ('%s' so far)" % g.final_score_label.text)
	ok(g.restart_button.disabled and g.restart_button.modulate.a < 1.0, "  'play again' held, and dimmed, while the lock holds")
	ok(g.game_over_screen.modulate.a < 1.0 and g.go_stack.scale.x < 1.0, "  the screen coming in, the board growing into place")
	ok(g.COUNT_UP_TIME * 1000.0 < g.GAME_OVER_LOCK_MSEC, "the count-up (%.0f ms) ends inside the lock (%d ms): it never holds 'play again' back" % [g.COUNT_UP_TIME * 1000.0, g.GAME_OVER_LOCK_MSEC])
	await frames(40)
	ok(g.final_score_label.text == "17" and g.count_ticks >= 3 and g.count_ticks <= 9,
			"  it gets to 17, ticking %d times" % g.count_ticks)
	ok(g.go_stack.scale == Vector2.ONE and g.game_over_screen.modulate.a == 1.0, "  and the screen is in")
	# (the lock is on the clock, and a headless run takes its frames faster)
	await silence()
	g.game_over_msec = Time.get_ticks_msec()
	await frames(1)
	var quiet := 0
	for v in g.sfx_pool:
		quiet += 1 if v.playing else 0
	g.restart_button.pressed.emit()
	var after := 0
	for v in g.sfx_pool:
		after += 1 if v.playing else 0
	ok(g.state == g.State.GAMEOVER and g.restart_button.disabled and after == quiet, "  a press while held does nothing, not even click")
	g.game_over_msec -= 1000
	await frames(2)
	ok(not g.restart_button.disabled and g.restart_button.modulate.a == 1.0, "once the lock lets go, 'play again' lights up")

	var board: Rect2 = g.go_board.get_global_rect()
	ok(board.encloses(g.go_title.get_global_rect()) and board.encloses(g.death_label.get_global_rect()),
			"the title and the cause are on the board, not on the world")
	ok(g.record_note.visible and g.record_note.text == g._tn("record_short", 3) and board.encloses(g.record_note.get_global_rect()),
			"3 short of the record, it says so: '%s'" % g.record_note.text)
	var stack: Rect2 = g.go_stack.get_global_rect()
	ok(stack.position.y >= 64.0 and stack.end.y <= g.restart_button.position.y - 12.0,
			"  board and chip between the top row and the buttons (%.0f to %.0f, buttons at %.0f)" % [stack.position.y, stack.end.y, g.restart_button.position.y])
	var need: int = g.BEE_SKINS["mint"]["score"]
	ok(g.goal_chip.visible and g.goal_bar.visible and g.goal_bar.filled_cells() == floori(20.0 / need * g.GOAL_BAR_BLOCKS * 2)
			and g.goal_left.text == g._tn("to_go", need - 20),
			"the chip shows the way to the next bee: a bar %d/%d full and '%s'" % [g.goal_bar.filled_cells(), g.GOAL_BAR_BLOCKS * 2, g.goal_left.text])
	ok(g.goal_chip.disabled and g.goal_equip == "", "  and takes no taps (there is nothing to put on)")
	ok(g.goal_icon.material == g.silhouette_mat, "  the bee to win shown as in the bee menu, a silhouette")

	# what the line says, and when it says nothing
	g.score = 19
	ok(g._record_note(false) == g._tn("record_short", 1), "1 short, in the singular: '%s'" % g._record_note(false))
	g.score = 20
	ok(g._record_note(false) == g._t("record_tied"), "the record equalled: '%s'" % g._record_note(false))
	g.score = 9
	ok(g._record_note(false) == "", "11 short of 20 says nothing")
	sd.best_score = 100
	g.score = 75
	ok(g._record_note(false) == g._tn("record_short", 25), "25 short of 100 is still close: '%s'" % g._record_note(false))
	g.score = 0
	ok(g._record_note(false) == "", "and a run with no flower says nothing")

	# the record beaten, a bee won in the run
	sd.unlocked_bees = ["rosy"]
	sd.selected_bee = "normal"
	await ended_run(20, 26, "hedge")
	await frames(40)
	ok(g.new_record_badge.visible and g.new_record_badge.text == g._t("record_beaten") and g.final_score_label.text == "26"
			and not g.final_best_label.visible and not g.score_caption.visible,
			"a record beaten: '%s' over the score alone (it showed '26 | 26')" % g.new_record_badge.text)
	ok(g.record_note.text == g._t("previous_record") % 20, "  and what the record was: '%s'" % g.record_note.text)
	ok(g.goal_title.text == g._t("unlocked") % "Mint Bee" and g.goal_hint.text == g._t("use_it") and g.goal_go.visible,
			"the chip offers the bee won: '%s' / '%s'" % [g.goal_title.text, g.goal_hint.text])
	g.game_over_msec = Time.get_ticks_msec()
	g.goal_chip.pressed.emit()
	ok(sd.selected_bee == "normal", "  not in the game over's first instant")
	g.game_over_msec -= 1000
	await frames(1)
	ok(not g.goal_chip.disabled, "  then it can be tapped")
	g.goal_chip.pressed.emit()
	var shown := true
	for icon in g.bee_button_icons:
		shown = shown and icon.texture.resource_path == g._bee_icon_path("mint")
	ok(sd.selected_bee == "mint" and g.applied_bee_skin == "mint" and shown, "  one tap puts it on (it took three, through the bee menu)")
	ok(g.goal_hint.text == g._t("selected") and g.goal_chip.disabled and not g.goal_go.visible, "  and the chip says so: '%s'" % g.goal_hint.text)
	sd.selected_bee = "normal"
	g._apply_bee_skin()
	sd.unlocked_bees = []
	sd.best_score = 10


# ------------------------------------------------------------------ the title screen
func _title_screen() -> void:
	sd.best_score = 10
	await title()
	var logo: Control = null
	for c in g.start_screen.get_children():
		if c.get_script() == g.VoxelLogo:
			logo = c
	var px: float = g.get_viewport().get_final_transform().x.x
	var cube_px: float = logo.cell * px
	ok(logo != null and (absf(cube_px - roundf(cube_px)) < 0.001 if cube_px >= 2.0 else logo.cell == floorf(logo.cell)),
			"the logo's cubes are a whole number of the screen's pixels (%.3f u, %.2f px)" % [logo.cell, cube_px])
	# the real whole-pixel branch, which a headless window never takes: a
	# 1080-wide phone (2.7), a 1440 one (3.6), 720 (1.8), a tablet (1.5)
	for scale in [2.7, 3.6, 1.8, 1.5]:
		var scratch: Control = g.VoxelLogo.new()
		scratch.setup(344.0, scale)
		var cpx: float = scratch.cell * scale
		ok(absf(cpx - roundf(cpx)) < 0.001 and cpx >= 2.0 and scratch.size.x <= 344.0 * 1.05,
				"  at %.1f px a unit too: %.3f u a cube = %.2f px, %.0f u wide" % [scale, scratch.cell, cpx, scratch.size.x])
		scratch.free()
	var top: float = logo.position.y
	var bottom: float = top + logo.size.y
	var clear := true
	for o in g.obstacles:
		var a: float = g.view3d.screen_pos_for(Vector2(0.0, o.position.y - 8.0), Vector2(0.0, g.camera_y)).y
		var b: float = g.view3d.screen_pos_for(Vector2(0.0, o.position.y + g.ObstacleScript.THICK + 8.0), Vector2(0.0, g.camera_y)).y
		clear = clear and (b < top or a > bottom)
	ok(clear, "no row of hedges runs through the logo on a %.0f-tall screen (logo at %.0f to %.0f)" % [g.screen_h, top, bottom])
	var bee_top: float = g.view3d.screen_pos_for(g.bee.position - Vector2(0.0, g.bee.radius * 2.0), Vector2(0.0, g.camera_y)).y
	var play_end: float = g.play_button.position.y + g.play_button.size.y * 1.03 + g.UI_CELL
	ok(bee_top - play_end >= g.TITLE_BEE_CLEAR, "the bee waiting on the grass is clear of the Play button (%.0f px between)" % (bee_top - play_end))


# ------------------------------------------------------------------ touch targets
# Every button a finger has to hit is at least 54 u across: 48 dp even on a
# 360 dp phone, where a unit is about 0.9 dp.
func _touch_targets() -> void:
	var small := []
	var counted := 0
	for screen in [g.start_screen, g.pause_screen, g.game_over_screen, g.settings_screen, g.bee_menu, g.credits_screen]:
		for b in screen.find_children("*", "Button", true, false):
			counted += 1
			if b.size.x < 54.0 or b.size.y < 54.0:
				small.append("%s %s" % [b.text if b.text != "" else b.name, b.size])
	for b in [g.pause_button]:
		counted += 1
		if b.size.x < 54.0 or b.size.y < 54.0:
			small.append("pause %s" % b.size)
	ok(small.is_empty(), "every one of the %d buttons takes taps over 54 u at least %s" % [counted, small])
	# the credits' title under a camera cut-out, as the run's top row
	var Main: GDScript = g.get_script()
	Main.forced_cutout = 40.0
	g._apply_top_inset()
	g._on_credits_pressed()
	ok(g.credits_title.position.y >= 40.0 and g.credits_scroll.get_global_rect().end.y <= g.screen_h - 90.0,
			"the credits' title starts under a 40 px cut-out (at %.0f)" % g.credits_title.position.y)
	g.credits_screen.visible = false
	Main.forced_cutout = -1.0
	g._apply_top_inset()


# WCAG contrast of two colours.
func _contrast(a: Color, b: Color) -> float:
	var la: float = _luma(a)
	var lb: float = _luma(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luma(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


# ------------------------------------------------------------------ ads
func _ads() -> void:
	var ads = g.ads
	ok(not ads._available and not ads.show_between_runs(), "no ads where AdMob doesn't run (this computer, the browser)")
	var now := Time.get_ticks_msec()
	var long_ago := now - int(ads.MIN_SECONDS_BETWEEN_ADS * 1000.0) - 1000
	ads._ad = InterstitialAd.new(1)
	ads._runs_since_ad = ads.RUNS_BETWEEN_ADS
	ads._last_ad_msec = now
	ok(not ads.show_between_runs(), "not in the first %.0f s, however many runs" % ads.MIN_SECONDS_BETWEEN_ADS)
	ads._last_ad_msec = long_ago
	ads._runs_since_ad = ads.RUNS_BETWEEN_ADS - 1
	ok(not ads.show_between_runs(), "not before %d runs" % ads.RUNS_BETWEEN_ADS)
	ads._runs_since_ad = ads.RUNS_BETWEEN_ADS
	ok(ads.show_between_runs() and ads._runs_since_ad == 0, "after %d runs and %.0f s, one is shown" % [ads.RUNS_BETWEEN_ADS, ads.MIN_SECONDS_BETWEEN_ADS])

	await fresh()
	ads._runs_since_ad = 0
	g._flap(1)
	await end_run()
	ok(ads._runs_since_ad == 1, "every run that ends is counted")
	ads._runs_since_ad = ads.RUNS_BETWEEN_ADS
	ads._last_ad_msec = long_ago
	g.restart_button.pressed.emit()
	ok(g.state == g.State.GAMEOVER and g.restart_after_ad, "'play again' with an ad due waits for the ad")
	g._on_bee_menu_pressed()
	ok(not g.bee_menu.visible, "the bee menu doesn't open while the ad opens")
	g.bee_menu.visible = true              # as if it had, in some other way
	ads.ad_opened.emit()
	ok(g.music.stream_paused, "the music stops under the ad")
	ads._finish()
	ok(g.state == g.State.PLAYING and not g.restart_after_ad and not g.music.stream_paused, "the run starts when it closes, music back on")
	ok(not g.bee_menu.visible, "with no menu left over it")
	ok(ads._ad == null and ads._runs_since_ad == 0, "and the count starts again")
	ads._ad = null
	ads._loading = false


# ------------------------------------------------------------------ credits
func _credits() -> void:
	await fresh()
	g._on_pause_pressed()
	g._on_credits_pressed()
	await frames(2)
	var lines: Array = []
	for c in g.credits_box.get_children():
		lines.append(c.text)
	var L = g.Licenses
	var own: Dictionary = L.OWN_LINES[g.lang]
	ok(lines[0] == "Bee Bee" and lines[1] == own["created"] % L.CREATOR, "the credits open with who made the game: '%s'" % lines[1])
	ok(lines[2] == own["owner"] % [L.YEAR, L.OWNER] and lines[2].contains("Cyberhat"), "and who owns it: '%s'" % lines[2])
	ok(lines.has(own["audio"]) and lines.has(own["android"]) and lines.has(own["third_party"]), "in the game's language (%s), the licences after them" % g.lang)
	g.credits_screen.visible = false
	g._on_resume_pressed()


# ------------------------------------------------------------------ save file
func _save_file() -> void:
	sd.best_score = 77
	sd.unlocked_bees = ["rosy"]
	sd.selected_bee = "rosy"
	sd.music_muted = true
	sd.sfx_muted = true
	sd.vibration = false
	sd.screen_shake = false
	sd.seen_tutorial = true
	sd.save_data()
	sd.best_score = 0
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.sfx_muted = false
	sd.vibration = true
	sd.screen_shake = true
	sd.load_data()
	ok(sd.best_score == 77 and sd.unlocked_bees == ["rosy"] and sd.selected_bee == "rosy" and sd.sfx_muted and not sd.vibration and not sd.screen_shake,
			"everything saved comes back")
	var f := FileAccess.open(SAVE_FILES[0], FileAccess.WRITE)
	f.store_string("[save]\nseen_tut")
	f.close()
	sd.best_score = 0
	sd.load_data()
	ok(sd.best_score == 77, "a save file cut off mid-write falls back on its copy (record %d)" % sd.best_score)
	var c := ConfigFile.new()
	c.set_value("save", "best_score", 5)
	c.set_value("save", "shining_bee_unlocked", true)
	c.save(SAVE_FILES[0])
	sd.load_data()
	ok(sd.best_score == 5 and sd.unlocked_bees.has("shining"), "a save from before the bee menu keeps its silver bee")
	ok(sd.screen_shake, "  and the screen shake, on, as it was before there was a switch for it")
	sd.sfx_muted = false
	sd.vibration = false
