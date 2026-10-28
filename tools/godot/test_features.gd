extends SceneTree

# Checks for what tools/godot/test_game.gd leaves alone: the models and
# sounds, the difficulty ramp, the sky (its clock, the moon, Jupiter and the
# UFO, the two backdrops), the bees (unlocks, the bee menu, every model), the
# record line, near misses, a real flower pickup, the pause menu's switches,
# the back button and leaving the app, the first run's tutorial, how often
# ads come, and the save file.
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
	g = Node2D.new()
	g.set_script(Main)
	root.add_child(g)
	await frames(8)
	print("TESTS features lang=", g.lang)
	ok(g.music.playing and g.music.volume_db == g.MUSIC_MUTED_DB, "a player who turned the music off gets it muted from the start")

	await _assets()
	await _difficulty()
	await _sky()
	await _backdrops()
	await _bees()
	await _record_line()
	await _near_miss()
	await _pickup()
	await _pause_menu()
	await _back_and_focus()
	await _tutorial()
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
	sd.best_score = 10
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	g._apply_bee_skin()
	await end_run()
	g._on_bee_menu_pressed()
	ok(g.bee_menu.visible and not g.game_over_screen.visible, "the bee menu opens from the game-over screen")
	ok(g.bee_cards["normal"]["status"].text == g._t("selected"), "the bee in use says so")
	ok(g.bee_cards["rosy"]["status"].text == g._t("locked") % 25, "a locked bee shows the score it takes ('%s')" % g.bee_cards["rosy"]["status"].text)
	g._on_bee_card_pressed("rosy")
	ok(sd.selected_bee == "normal", "and can't be picked")
	g._on_bee_menu_closed()
	ok(not g.bee_menu.visible and g.game_over_screen.visible, "closing the menu brings the game-over screen back")

	await fresh()
	g._flap(1)
	for s in range(1, 301):
		g.score = s
		g._check_bee_unlocks()
	ok(sd.unlocked_bees == ["rosy", "mint", "ice", "grape", "queen", "shining"], "every bee is won at its score, in order (%s)" % [sd.unlocked_bees])
	ok(g.bee_notice.visible and g.bee_notice_title.text == g._t("unlocked") % "Silver Bee", "the notice names the last one won")
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
	ok(g.bee_notice.visible, "a bee won shows its banner")
	g._on_pause_pressed()
	ok(not g.bee_notice.visible, "which leaves when the game pauses, off the 'Paused' title")
	g._on_pause_restart_pressed()
	await ticks(1)
	ok(not g.bee_notice.visible, "a bee's banner doesn't carry over into a restart from the pause menu")
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
	g._on_bee_menu_pressed()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(not g.bee_menu.visible and g.game_over_screen.visible and g.state == g.State.GAMEOVER, "back closes the bee menu, back to the game over")
	g._on_bee_menu_pressed()
	await key(KEY_ESCAPE)
	ok(not g.bee_menu.visible and g.game_over_screen.visible, "and so does escape, on a computer")
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
	ok(not g.world_moving, "and the bee waits on the grass for the first tap")
	g._on_pause_pressed()
	g._on_pause_restart_pressed()
	await ticks(2)
	ok(g.direction_hint.visible and g.hint_alpha == 1.0 and not sd.seen_tutorial, "a restart from the pause menu before flying keeps the arrows")
	g._flap(-1)
	ok(sd.seen_tutorial, "the first flap is what marks the tutorial as seen")
	await ticks(30)
	ok(not g.direction_hint.visible and g.state == g.State.PLAYING, "the arrows go once it has flown")


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
	sd.seen_tutorial = true
	sd.save_data()
	sd.best_score = 0
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.sfx_muted = false
	sd.vibration = true
	sd.load_data()
	ok(sd.best_score == 77 and sd.unlocked_bees == ["rosy"] and sd.selected_bee == "rosy" and sd.sfx_muted and not sd.vibration,
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
	sd.sfx_muted = false
	sd.vibration = false
