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
# writes to the real save file. The player's save is read first and put back
# at the end; tools/test.sh does the same from outside, in case a run stops
# before it gets there.

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


# A resume counts 3-2-1 before the run goes on (main.gd _on_resume_pressed):
# waits it out, a little longer at most.
func resumed() -> void:
	var guard := 0
	while g.state == g.State.RESUMING and guard < 200:
		await process_frame
		guard += 1


func voices() -> int:
	var n := 0
	for v in g.sfx_pool:
		if v.playing:
			n += 1
	return n


# Waits until no sound is playing, so a count of voices means what it says.
# This waits on the clock, not on a number of frames: a sound lasts real
# time, while a headless run takes its frames as fast as the machine allows
# and can go through hundreds of them before a wingbeat has finished.
func silence() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while voices() > 0 and Time.get_ticks_msec() < deadline:
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
	# a record short of the first bee, so the game over has one to name
	sd.best_score = 5
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true
	# the wingbeat checks count voices: a player who muted the effects would fail them
	sd.sfx_muted = false
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
	await silence()                       # let the button's own click sound finish
	var before := voices()
	var t := InputEventScreenTouch.new()
	t.position = Vector2(300, 400)
	t.pressed = true
	Input.parse_input_event(t)
	await frames(2)
	ok(voices() - before == 1, "a touch plays the wingbeat once (voices +%d)" % (voices() - before))
	ok(g.bee.velocity.x > 0.0 and g.bee.facing == 1, "touch on the right flaps right")
	await silence()
	await fresh()                         # the bee has fallen out of the first run by now
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
	ok(g.state == g.State.RESUMING and paused, "escape resumes a paused game: first a 3-2-1, still frozen")
	await resumed()
	ok(g.state == g.State.PLAYING and not paused, "  then the run goes on")

	# ------------------------------------------------ the sound switch
	await key(KEY_P)
	await silence()
	g._on_sound_toggle_pressed()
	ok(sd.sfx_muted and g.sound_slash.visible, "the sound switch turns the effects off")
	await silence()
	var quiet := voices()
	g._play_sfx(g.SFX_COLLECT, -6.0)
	ok(voices() == quiet, "and nothing plays while they are off")
	g._on_sound_toggle_pressed()
	ok(not sd.sfx_muted and not g.sound_slash.visible and voices() == quiet + 1, "switching them back on clicks")

	# ------------------------------------------------ credits
	g._on_credits_pressed()
	await frames(2)
	ok(g.credits_screen.visible and g.credits_box.get_child_count() > 50, "the credits open from the pause menu (%d blocks)" % g.credits_box.get_child_count())
	var shown := ""
	for c in g.credits_box.get_children():
		shown += c.text + " "
	for needed in ["Godot Engine", "Permission is hereby granted", "SIL OPEN FONT LICENSE", "Poing Studios", "FreeType", "AndroidX", "Kotlin", "Google Mobile Ads SDK", "Apache License"]:
		ok(shown.contains(needed), "the credits mention '%s'" % needed)
	await key(KEY_ESCAPE)
	ok(not g.credits_screen.visible and g.state == g.State.PAUSED, "escape closes the credits and stays paused")
	g._on_credits_pressed()
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	ok(not g.credits_screen.visible and g.state == g.State.PAUSED, "so does the back button")
	g._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await resumed()
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

	# ------------------------------------------------ a flower about to be lost blinks
	await fresh()
	var low = g.flowers[0]
	var high = g.flowers[1]
	g.camera_y = low.position.y - g.screen_h + 60.0      # 60 px from the bottom edge
	g.bee.position = Vector2(200, g.camera_y + 300.0)
	var seen_low := {}
	var seen_high := {}
	for i in 40:
		await process_frame
		seen_low[g.view3d.mirrors[low.get_instance_id()].visible] = true
		seen_high[g.view3d.mirrors[high.get_instance_id()].visible] = true
	ok(seen_low.size() == 2, "a flower near the bottom edge blinks")
	ok(seen_high.size() == 1 and seen_high.has(true), "one higher up does not")

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

	# ------------------------------------------------ flowers in the middle of the screen
	await fresh()
	g.elapsed = 100.0                      # full difficulty, where a leg may be shortest
	seed(7)
	var first: int = g.flowers.size()
	for i in 400:
		g._spawn_row()
	var in_middle := 0
	var drawn := 0                         # rows left to chance: not intro or breather rows
	var furthest := 0.0                    # from one of them to the gap before it or after it
	for i in range(first, g.flowers.size()):
		if not g._is_easy_row(i + 1):
			drawn += 1
		if not is_equal_approx(g.flowers[i].position.x, g.SCREEN_W / 2.0):
			continue
		if not g._is_easy_row(i + 1):
			in_middle += 1
		furthest = maxf(furthest, absf(g.obstacles[i - 1].gap_x - g.SCREEN_W / 2.0))
		furthest = maxf(furthest, absf(g.obstacles[i].gap_x - g.SCREEN_W / 2.0))
	ok(in_middle > drawn * 0.24 and in_middle < drawn * 0.36, "about three flowers in ten come up in the middle of the screen (%d of %d)" % [in_middle, drawn])
	ok(furthest <= g.MAX_LEG_HARD, "and no gap before or after one of them is out of reach (%.0f px at most)" % furthest)

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
	ok(g.goal_chip.visible and g.goal_title.text == g._t("next_bee") % "Rosy Bee" and g.goal_hint.text == g._t("next_goal") % g.BEE_SKINS["rosy"]["score"],
			"and names the next bee: '%s' / '%s'" % [g.goal_title.text, g.goal_hint.text])

	# keyboard restart — but not in the first instant, when a tap meant for
	# the run could still be on its way
	g._on_restart_pressed()
	ok(g.state == g.State.GAMEOVER, "'play again' ignores a press in the first instant of the game-over screen")
	g.game_over_msec -= 1000
	await key(KEY_ENTER)
	ok(g.state == g.State.PLAYING and g.score == 0, "enter on game over starts a new run")

	# ------------------------------------------------ a bee won in the run, then dying at once
	g._flap(1)
	await ticks(2)
	var rosy_at: int = g.BEE_SKINS["rosy"]["score"]
	g.score = rosy_at
	g._check_bee_unlocks()
	ok(g.notice.visible and g.notice_now.get("kind") == "bee", "reaching %d shows the unlock notice" % rosy_at)
	g._trigger_game_over("hedge")
	g.dying_timer = 99.0
	await ticks(3)
	ok(not g.notice.visible and g.notice_now.is_empty(), "the notice is gone once the game-over screen is up")
	ok(g.goal_title.text == g._t("unlocked") % "Rosy Bee", "the chip says the bee was won: '%s'" % g.goal_title.text)
	ok(g.new_record_badge.visible and sd.best_score == rosy_at, "a record is still a record (best %d)" % sd.best_score)
	g._on_bee_menu_pressed()
	ok(not g.bee_menu.visible, "the bee button waits out the game over's first instant too")
	g.game_over_msec -= 1000
	g._show_bee_notice("rosy")
	g._on_bee_menu_pressed()
	ok(not g.notice.visible and g.bee_menu.visible, "opening the bee menu puts the notice away")
	g._on_bee_menu_closed()

	# ------------------------------------------------ ad lock expires
	g.game_over_msec -= 1000
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
	await resumed()
	g.score = 41
	g._trigger_game_over("fall")
	g.dying_timer = 99.0
	await ticks(3)
	ok(g.new_record_badge.visible and sd.best_score == 41, "and the game over still counts it as new (best %d)" % sd.best_score)

	# ------------------------------------------------ the tutorial stays out of the pause menu
	await fresh()
	g.hint_alpha = 1.0                     # as on a first run, before its first flap
	g.has_tapped_once = false
	g.direction_hint.modulate.a = 1.0
	g.direction_hint.visible = true
	g._on_pause_pressed()
	ok(g.state == g.State.PAUSED and not g.direction_hint.visible, "the tutorial arrows are put away behind the pause menu")
	g._on_resume_pressed()
	ok(g.state == g.State.PLAYING and g.direction_hint.visible, "and come back when the run resumes")
	g.hint_alpha = 0.0
	g.has_tapped_once = true
	g.direction_hint.visible = false

	# ------------------------------------------------ the top row clears a camera cut-out
	ok(g.top_inset == 0.0 and g.record_label.position.y == g.RECORD_Y, "with no cut-out the top row stays where it was")
	Main.forced_cutout = 40.0
	g._apply_top_inset()
	var pause_plate: Control = g.pause_button.get_meta("plate")
	ok(is_equal_approx(pause_plate.get_global_rect().position.y, 40.0) and g.record_label.position.y > 40.0,
			"under a 40 px cut-out the pause button starts at %.0f and the record at %.0f" % [pause_plate.get_global_rect().position.y, g.record_label.position.y])
	var gears_follow := true
	for gear in g.gear_buttons:
		gears_follow = gears_follow and is_equal_approx(gear.position.y, g.pause_button.position.y)
	ok(gears_follow, "and so do the settings' gears, in the same corner")
	ok(is_equal_approx(g.score_label.position.y - g.record_label.position.y, g.SCORE_Y - g.RECORD_Y), "and the score moves down with them")
	Main.forced_cutout = 10.0
	g._apply_top_inset()
	ok(g.top_inset == 0.0, "a cut-out smaller than the row's own margin moves nothing")
	Main.forced_cutout = 900.0
	g._apply_top_inset()
	ok(g.top_inset == g.TOP_INSET_MAX, "a nonsense cut-out is capped (%.0f)" % g.top_inset)
	Main.forced_cutout = -1.0
	g._apply_top_inset()
	ok(g.top_inset == 0.0, "and a computer has none")

	# ------------------------------------------------ every string fits where it goes
	var f: Font = g.ui_font
	# the game over's board (inside its outline), a column of it, the chip's
	# text beside its bee (less the "go" arrow, when there is one), what is
	# left of the chip beside the bar, a bee card's face, a switch's caption
	var board_w: float = g.GO_W - 2.0 * g.UI_CELL
	var col_w: float = g.score_caption.size.x
	var chip_text: float = g.goal_title.size.x
	var chip_go: float = g.goal_go.position.x - g.goal_title.position.x - 4.0
	var bar_left: float = g.goal_left.size.x
	var card_w: float = g.bee_cards["normal"]["status"].size.x
	var caption_w: float = g.TOGGLE_SIDE + g.TOGGLE_GAP
	# the longest bee name, which is what a chip saying it is measured against
	var longest_bee := ""
	for id in g.BEE_ORDER:
		var bee_name: String = g.BEE_SKINS[id]["name"]
		if f.get_string_size(bee_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x > f.get_string_size(longest_bee, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x:
			longest_bee = bee_name
	var fits := [
		["record", 22, 400.0, [9999]], ["left", 20, 120.0, []], ["right", 20, 120.0, []],
		["game_over", 48, board_w, []], ["score", 22, col_w, []], ["best", 22, col_w, []],
		["play_again", 34, 216.0, []], ["paused", 52, 392.0, []], ["resume", 34, 216.0, []],
		["restart", 34, 216.0, []], ["ad_privacy", 22, 380.0, []], ["credits", 22, 380.0, []], ["choose_bee", 38, 392.0, []],
		["back", 34, 216.0, []], ["selected", 17, card_w, []], ["selected", 17, chip_text, []],
		["goal_count", 17, card_w, [300]], ["goal_count_1", 17, card_w, []], ["goal_run", 15, card_w, []],
		["unlocked", 22, chip_go, [longest_bee]], ["use_it", 17, chip_go, []],
		["died_hedge", 22, board_w, []], ["died_flower", 22, board_w, []], ["died_fall", 22, board_w, []],
		["next_bee", 22, chip_text, [longest_bee]], ["next_goal", 17, chip_text, [300]],
		["to_go", 17, bar_left, [300]], ["to_go_1", 17, bar_left, []],
		["record_beaten", 26, board_w, []], ["previous_record", 18, board_w, [300]],
		["record_short", 18, board_w, [300]], ["record_short_1", 18, board_w, []], ["record_tied", 18, board_w, []],
		["settings", 52, 392.0, []], ["music", 18, caption_w, []], ["sounds", 18, caption_w, []],
		["vibration", 18, caption_w, []], ["shake", 18, caption_w, []],
		# the run's notice slot: its plate at its widest, less the padding and
		# what goes beside the title (a bee; one flower; a flower each side)
		["unlocked", g.NOTICE_FONT, g.NOTICE_MAX_W - 2.0 * g.NOTICE_PAD - g.NOTICE_ICON - g.NOTICE_GAP, [longest_bee]],
		["rule", g.NOTICE_FONT, g.NOTICE_MAX_W - 2.0 * g.NOTICE_PAD - g.ICON_FLOWER[0].length() * g.UI_CELL - g.NOTICE_GAP, []],
		["milestone", g.NOTICE_FONT, g.NOTICE_MAX_W - 2.0 * g.NOTICE_PAD - 2.0 * (g.ICON_FLOWER[0].length() * g.UI_CELL + g.NOTICE_GAP), [300]],
		["record_beaten", 22, 260.0, []], ["phew", 26, 80.0, []],
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
	# and the slot sizes each plate to what it says: never past its widest,
	# which keeps it clear of the pause button
	# (measured as _layout_notice sizes it, in whole cubes, before it caps
	# the plate at NOTICE_MAX_W; then where the laid-out content ends on the
	# plate, which that cap would hide)
	ok((g.SCREEN_W + g.NOTICE_MAX_W) / 2.0 <= g.pause_button.position.x - 3.0,
			"the notice slot at its widest is clear of the pause button")
	for entry in [g._rule_entry(), {"title": g._t("unlocked") % longest_bee, "icon": g.notice_icon.texture},
			{"title": g._t("milestone") % 300, "flowers": 2}]:
		var plate_w: float = ceilf((g._notice_inner_width(entry) + 2.0 * g.NOTICE_PAD) / g.UI_CELL) * g.UI_CELL
		g._layout_notice(entry)
		var face_end: float = g.notice.face_rect().end.x
		var last_end: float = g.notice_title.position.x + f.get_string_size(entry["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, g.NOTICE_FONT).x
		if entry.get("flowers", 0) == 2:
			last_end = g.notice_flowers[1].position.x + g.notice_flowers[1].size.x
		ok(plate_w <= g.NOTICE_MAX_W and last_end <= face_end,
				"the notice '%s' fits its slot (%d of %d px; ends at %d of the face's %d)" % [entry["title"], plate_w, g.NOTICE_MAX_W, last_end, face_end])
	g._clear_notices()
	for ch in g._t("record_word"):
		ok(g.view3d.GLYPHS.has(ch), "the record line can spell '%s'" % ch)

	# ------------------------------------------------ a number, in the singular when it is one
	var plurals := {
		"en": [["to_go", 1, "1 to go"], ["to_go", 5, "5 to go"], ["record_short", 1, "1 short of your record!"],
				["record_short", 3, "3 short of your record!"], ["goal_count", 1, "1 flower"], ["goal_count", 10, "10 flowers"]],
		"pt": [["to_go", 1, "Falta 1"], ["to_go", 5, "Faltam 5"], ["record_short", 1, "Faltou 1 para o recorde!"],
				["record_short", 3, "Faltaram 3 para o recorde!"], ["goal_count", 1, "1 flor"], ["goal_count", 10, "10 flores"]],
	}
	for row in plurals[g.lang]:
		ok(g._tn(row[0], row[1]) == row[2], "%d with '%s' reads '%s' ('%s')" % [row[1], row[0], row[2], g._tn(row[0], row[1])])

	restore_save()
	print("TESTS done, failures: ", fails)
	quit()
