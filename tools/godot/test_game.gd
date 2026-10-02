extends SceneTree

# Behaviour checks for the game: input, the rules that end a run, the
# game-over screen, the menus, and that every piece of interface text fits
# where it goes in each language.
#
#   bash tools/test.sh          (runs this in English and in Portuguese)
#
# or, by hand:
#   godot --headless --path . --fixed-fps 60 --script tools/godot/test_game.gd -- --lang=pt
#
# The game saves as it goes (a record kept on pause, a bee won), so this
# writes to the real save file; tools/test.sh puts the player's save back.

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


func ticks(n: int) -> void:
	for i in n:
		paused = false
		await physics_frame


func frames(n: int) -> void:
	for i in n:
		await process_frame


func voices() -> int:
	var n := 0
	for v in g.sfx_pool:
		if v.playing:
			n += 1
	return n


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


func fresh() -> void:
	paused = false
	g.restart_after_ad = false
	g.state = g.State.GAMEOVER
	g._start_fresh_run()
	await ticks(3)


func _run() -> void:
	await process_frame
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
	sd.vibration = false
	g = Node2D.new()
	g.set_script(Main)
	root.add_child(g)
	await frames(8)
	print("TESTS lang=", g.lang)

	# ------------------------------------------------ keyboard: start
	await key(KEY_SPACE)
	ok(g.state == g.State.PLAYING, "space on the title starts the run")

	# ------------------------------------------------ one touch, one flap
	await frames(20)                      # let the button's own click sound finish
	var before := voices()
	var t := InputEventScreenTouch.new()
	t.position = Vector2(300, 400)
	t.pressed = true
	Input.parse_input_event(t)
	await frames(2)
	ok(voices() - before == 1, "a touch plays the wingbeat once (voices +%d)" % (voices() - before))
	ok(g.bee.velocity.x > 0.0 and g.bee.facing == 1, "touch on the right flaps right")
	await frames(20)
	before = voices()
	var m := InputEventMouseButton.new()
	m.position = Vector2(80, 400)
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	g._unhandled_input(m)
	await frames(2)
	var em := InputEventMouseButton.new()
	em.position = Vector2(300, 400)
	em.button_index = MOUSE_BUTTON_LEFT
	em.pressed = true
	em.device = InputEvent.DEVICE_ID_EMULATION
	g._unhandled_input(em)
	ok(g.bee.facing == -1, "a mouse click made up from a touch is ignored")
	ok(voices() - before == 1 and g.bee.facing == -1, "a real mouse click on the left flaps left, once (voices +%d, facing %d, device %d, state %d)" % [voices() - before, g.bee.facing, m.device, g.state])

	# ------------------------------------------------ keyboard: flap, pause, resume
	await fresh()
	await key(KEY_RIGHT)
	ok(g.world_moving and g.bee.facing == 1, "right arrow flaps right")
	await key(KEY_A)
	ok(g.bee.facing == -1, "A flaps left")
	await key(KEY_ESCAPE)
	ok(g.state == g.State.PAUSED and paused, "escape pauses")
	await key(KEY_ESCAPE)
	ok(g.state == g.State.PLAYING and not paused, "escape resumes a paused game")

	# ------------------------------------------------ credits
	await key(KEY_P)
	g._on_credits_pressed()
	await frames(2)
	ok(g.credits_screen.visible and g.credits_box.get_child_count() > 50, "the credits open from the pause menu (%d blocks)" % g.credits_box.get_child_count())
	var shown := ""
	for c in g.credits_box.get_children():
		shown += c.text + " "
	for needed in ["Godot Engine", "Permission is hereby granted", "SIL OPEN FONT LICENSE", "Poing Studios", "FreeType"]:
		ok(shown.contains(needed), "the credits mention '%s'" % needed)
	await key(KEY_ESCAPE)
	ok(not g.credits_screen.visible and g.state == g.State.PAUSED, "escape closes the credits and stays paused")
	g._on_credits_pressed()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(not g.credits_screen.visible and g.state == g.State.PAUSED, "so does the back button")
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(g.state == g.State.PLAYING, "and back again resumes")

	# ------------------------------------------------ ceiling
	await fresh()
	g._flap(1)
	await ticks(2)
	g.bee.position.y = g.camera_y - 300.0
	g.bee.velocity.y = -480.0
	await ticks(3)
	ok(g.bee.position.y >= g.camera_y + g.bee.radius - 0.01, "the bee is held at the top edge (%.1f px below it)" % (g.bee.position.y - g.camera_y))
	ok(g.bee.velocity.y >= 0.0, "and stops rising there")

	# ------------------------------------------------ death causes
	await fresh()
	g._flap(1)
	await ticks(2)
	g.bee.position = Vector2(200, g.camera_y + g.screen_h + 80.0)
	g.time_since_first_flap = 5.0
	await ticks(2)
	ok(g.death_cause == "fall" and g.state != g.State.PLAYING, "falling off the bottom: cause 'fall' (%s)" % g.death_cause)

	await fresh()
	g._flap(1)
	await ticks(2)
	var o = g.obstacles[0]
	g.bee.velocity = Vector2.ZERO
	g.bee.position = Vector2(clampf(o.gap_x + o.gap_width, 20.0, 380.0), o.position.y + 11.0)
	if absf(g.bee.position.x - o.gap_x) < o.gap_width / 2.0:
		g.bee.position.x = clampf(o.gap_x - o.gap_width, 20.0, 380.0)
	g.camera_y = o.position.y - g.screen_h * 0.5
	await ticks(2)
	ok(g.death_cause == "hedge", "inside a hedge: cause 'hedge' (%s)" % g.death_cause)

	await fresh()
	g._flap(1)
	await ticks(2)
	g.scrolling_started = true
	g.bee.physics_enabled = false          # held still while the world moves past
	g.bee.position = Vector2(200, g.camera_y + g.screen_h * 0.5)
	var guard := 0
	while g.state == g.State.PLAYING and guard < 600:
		g.camera_y -= 12.0
		g.bee.position.y = g.camera_y + g.screen_h * 0.5
		# keep clear of hedges: the test is about the flower left behind
		for ob in g.obstacles:
			if absf(ob.position.y + 11.0 - g.bee.position.y) < 40.0:
				g.bee.position.x = ob.gap_x
		guard += 1
		await ticks(1)
	ok(g.death_cause == "flower", "a flower left behind: cause 'flower' (%s)" % g.death_cause)

	# ------------------------------------------------ the game-over screen
	g.dying_timer = 99.0
	await ticks(3)
	ok(g.state == g.State.GAMEOVER and g.game_over_screen.visible, "the run ends in the game-over screen")
	ok(g.death_label.text == g._t("died_flower"), "it says what happened: '%s'" % g.death_label.text)
	ok(g.goal_chip.visible and g.goal_title.text == g._t("next_bee") % "Rosy Bee", "and names the next bee: '%s' / '%s'" % [g.goal_title.text, g.goal_hint.text])

	# keyboard restart
	await key(KEY_ENTER)
	ok(g.state == g.State.PLAYING and g.score == 0, "enter on game over starts a new run")

	# ------------------------------------------------ a bee won in the run, then dying at once
	g._flap(1)
	await ticks(2)
	g.score = 25
	g._check_bee_unlocks()
	ok(g.bee_notice.visible, "reaching 25 shows the unlock notice")
	g._trigger_game_over("hedge")
	g.dying_timer = 99.0
	await ticks(3)
	ok(not g.bee_notice.visible, "the notice is gone once the game-over screen is up")
	ok(g.goal_title.text == g._t("unlocked") % "Rosy Bee", "the chip says the bee was won: '%s'" % g.goal_title.text)
	ok(g.new_record_badge.visible and sd.best_score == 25, "a record is still a record (best %d)" % sd.best_score)
	g._show_bee_notice("rosy")
	g._on_bee_menu_pressed()
	ok(not g.bee_notice.visible and g.bee_menu.visible, "opening the bee menu puts the notice away")
	g._on_bee_menu_closed()

	# ------------------------------------------------ ad lock expires
	g.restart_after_ad = true
	g.restart_lock_msec = Time.get_ticks_msec()
	g._on_restart_pressed()
	ok(g.state == g.State.GAMEOVER, "'play again' is swallowed while an ad is opening")
	g.restart_lock_msec = Time.get_ticks_msec() - 5000
	g._on_restart_pressed()
	ok(g.state == g.State.PLAYING and not g.restart_after_ad, "but not for ever: after a few seconds it starts the run")

	# ------------------------------------------------ record kept on pause
	await ticks(3)
	g._flap(1)
	g.score = 40
	g._on_pause_pressed()
	ok(sd.best_score == 40, "pausing above the record saves it (best %d)" % sd.best_score)
	g._on_resume_pressed()
	g.score = 41
	g._trigger_game_over("fall")
	g.dying_timer = 99.0
	await ticks(3)
	ok(g.new_record_badge.visible and sd.best_score == 41, "and the game over still counts it as new (best %d)" % sd.best_score)

	# ------------------------------------------------ every string fits where it goes
	var f: Font = g.ui_font
	var fits := [
		["record", 22, 400.0, [9999]], ["left", 20, 120.0, []], ["right", 20, 120.0, []],
		["game_over", 56, 392.0, []], ["score", 22, 126.0, []], ["best", 22, 126.0, []],
		["play_again", 34, 216.0, []], ["paused", 52, 392.0, []], ["resume", 34, 216.0, []],
		["restart", 34, 216.0, []], ["ad_privacy", 22, 380.0, []], ["credits", 22, 380.0, []], ["choose_bee", 38, 392.0, []],
		["back", 34, 216.0, []], ["selected", 16, 106.0, []], ["pick", 16, 106.0, []],
		["locked", 16, 106.0, [300]], ["unlocked", 26, 220.0, ["Silver Bee"]], ["unlocked_hint", 18, 220.0, []],
		["unlocked", 22, 190.0, ["Silver Bee"]], ["unlocked_hint", 17, 190.0, []],
		["died_hedge", 24, 392.0, []], ["died_flower", 24, 392.0, []], ["died_fall", 24, 392.0, []],
		["next_bee", 22, 190.0, ["Queen Bee"]], ["next_goal", 17, 190.0, [300]],
	]
	for row in fits:
		var text: String = g._t(row[0])
		if row[3].size() > 0:
			text = text % row[3]
		var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, row[1]).x
		ok(w <= row[2], "'%s' fits (%d of %d px at size %d)" % [text, w, row[2], row[1]])
		for ch in text:
			if not f.has_char(ch.unicode_at(0)):
				ok(false, "the font has no glyph for '%s' in '%s'" % [ch, text])
	for ch in g._t("record_word"):
		ok(g.view3d.GLYPHS.has(ch), "the record line can spell '%s'" % ch)

	print("TESTS done, failures: ", fails)
	quit()
