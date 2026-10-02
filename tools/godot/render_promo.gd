extends SceneTree

# Renders the 30-second promo video (1080x1920, 60 fps) from the real game:
# every scene is the game itself running, flown by an autopilot that taps
# left and right like a player would, with the motion-design layer (titles,
# callouts, wipes, the bee line-up, the end card) drawn on top.
#
#   godot --path . --fixed-fps 60 --write-movie build/promo/audio.avi \
#         --resolution 540x960 --script tools/godot/render_promo.gd
#
# Run WITHOUT --headless; tools/build_promo.sh does all of it. The picture
# is saved here, frame by frame, from a viewport of the exact size wanted
# (build/promo/frames/); the movie writer is only there for the sound, which
# is the game's own effects, fired by what happens on screen. The music is
# laid over that afterwards (the scenes are cut to its bars: 160 BPM, so a
# bar is 90 frames).
#
# Add "-- --dry" to rehearse: no frames are written except a few stills
# (build/promo/stills/), and the autopilot's fate is printed.
#
# The save file is not touched on purpose, but a run that reaches a skin's
# score writes it; build_promo.sh keeps a copy and puts it back.

const FPS := 60
const SIZE := Vector2i(1080, 1920)
const LW := 400.0
const LH := 711.0
const TOTAL := 1800
const OUT := "res://build/promo/"

const INK := Color(0.24, 0.13, 0.32)
const GOLD := Color(1, 0.82, 0.18)

# scene boundaries, in frames
const T_PLAY := 180          # day
const T_DUSK := 540
const T_NIGHT := 810
const T_BEES := 1080
const T_ASK := 1350
const T_END := 1440
const WIPES := [T_PLAY, T_DUSK, T_NIGHT, T_END]
const STILLS := [20, 60, 130, 176, 186, 240, 330, 430, 520, 600, 700, 790, 880, 1000, 1070, 1120, 1200, 1300, 1380, 1436, 1470, 1560, 1650, 1760]

var dry := false
# rehearsal only: "--seeds=day,dusk,night" tries other layouts, and
# "--span=from,to" runs just part of the timeline
var seeds := [11, 5, 1]
var span := [0, TOTAL]
var comp: SubViewport
var game_vp: SubViewport
var game_view: TextureRect
var layer: Control
var dim: ColorRect
var wipe: Wipe
var ripples: Ripples
var g: Node2D
var sd: Node
var font: Font
var fx: Array = []
var f := -1
var deaths := 0

var bot: RefCounted
var bot_on := false


func _initialize() -> void:
	var autopilot: GDScript = load("res://tools/godot/autopilot.gd")
	if autopilot == null or not autopilot.can_instantiate():
		printerr("PROMO cannot load tools/godot/autopilot.gd")
		quit(1)
		return
	bot = autopilot.new()
	dry = OS.get_cmdline_user_args().has("--dry")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = Array(a.trim_prefix("--seeds=").split(",")).map(func(v): return int(v))
		elif a.begins_with("--span="):
			span = Array(a.trim_prefix("--span=").split(",")).map(func(v): return int(v))
	_run()


func _run() -> void:
	# The save file is read on the first frame; anything set before that
	# (the music switched off, above all) would be overwritten by it.
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "stills"))
	sd = root.get_node("SaveData")
	sd.best_score = 128
	sd.unlocked_bees = []
	sd.selected_bee = "normal"
	sd.seen_tutorial = true
	sd.music_muted = true        # the track is laid over the finished video
	sd.vibration = false
	font = load("res://fonts/Jersey10-Regular.ttf")

	comp = SubViewport.new()
	comp.size = SIZE
	comp.size_2d_override = Vector2i(int(LW), int(LH))
	comp.size_2d_override_stretch = true
	comp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(comp)

	game_vp = SubViewport.new()
	game_vp.size = SIZE
	game_vp.size_2d_override = Vector2i(int(LW), int(LH))
	game_vp.size_2d_override_stretch = true
	game_vp.msaa_3d = Viewport.MSAA_4X
	game_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	comp.add_child(game_vp)
	g = Node2D.new()
	g.set_script(load("res://scripts/main.gd"))
	game_vp.add_child(g)
	# The light the sky casts on the scene normally catches up with a change
	# of sky over a hundred frames or so — fine in a run, where the sky
	# turns slowly, but here the time of day jumps at every cut.
	g.view3d.env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	g.view3d.env.sky.process_mode = Sky.PROCESS_MODE_REALTIME

	game_view = TextureRect.new()
	game_view.texture = game_vp.get_texture()
	game_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	game_view.size = Vector2(LW, LH)
	game_view.pivot_offset = Vector2(LW, LH) / 2.0
	comp.add_child(game_view)

	dim = ColorRect.new()
	dim.color = Color(0.13, 0.07, 0.20, 0.0)
	dim.size = Vector2(LW, LH)
	comp.add_child(dim)
	ripples = Ripples.new()
	ripples.size = Vector2(LW, LH)
	comp.add_child(ripples)
	layer = Control.new()
	layer.size = Vector2(LW, LH)
	comp.add_child(layer)
	wipe = Wipe.new()
	wipe.size = Vector2(LW, LH)
	comp.add_child(wipe)

	# what the window shows while it works
	var preview := TextureRect.new()
	preview.texture = comp.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)

	# The game pauses itself when its window loses focus, which would freeze
	# a scene mid-take; undone before the physics step so no tick is lost.
	physics_frame.connect(_keep_running)

	for i in 8:
		await process_frame
	_stage_title()
	_build_timeline()
	for i in 6:
		await process_frame

	print("PROMO first frame at engine frame ", Engine.get_process_frames())
	for i in range(span[0], span[1]):
		f = i
		_keep_running()
		_direct()
		_bot()
		_animate()
		await RenderingServer.frame_post_draw
		if not dry:
			comp.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(OUT + "frames/f%05d.jpg" % f), 0.94)
		elif STILLS.has(f):
			comp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "stills/s%05d.png" % f))
		if bot_on and g.state != g.State.PLAYING and g.state != g.State.PAUSED:
			deaths += 1
			if deaths == 1:
				print("PROMO autopilot died at frame ", f, " score ", g.score, " bee ", g.bee.position - Vector2(0, g.camera_y), " vel ", g.bee.velocity)
				for o in g.obstacles:
					if absf(o.position.y - g.bee.position.y) < 120.0:
						print("   row y ", o.position.y - g.camera_y, " gap ", o.gap_x - o.gap_width / 2.0, " .. ", o.gap_x + o.gap_width / 2.0)
				for fl in g.flowers:
					print("   flower ", fl.position - Vector2(0, g.camera_y))
	print("PROMO done: seeds ", seeds, " span ", span, " deaths ", deaths, " final score ", g.score)
	quit()


func _keep_running() -> void:
	paused = false
	if g.state == g.State.PAUSED:
		g.state = g.State.PLAYING
		g.pause_screen.visible = false
		g.pause_button.visible = false


# ------------------------------------------------------------------ staging
func _stage_title() -> void:
	bot_on = false
	seed(4)
	sd.selected_bee = "normal"
	g._start_fresh_run()
	g.state = g.State.START
	g.sky.backdrop = "hills"
	g.scenery_id += 1
	g._apply_bee_skin()
	g.start_screen.visible = false
	g.pause_button.visible = false
	g._set_hud_visible(false)


# A moment of a run, as in render_store_shots.gd, but left running: `climb`
# px above the start, the bee rising under a flower, the world scrolling.
func _stage_run(score: int, elapsed: float, skin: String, climb: float, rng_seed: int, best: int) -> void:
	seed(rng_seed)
	sd.best_score = best
	sd.selected_bee = skin
	if not sd.unlocked_bees.has(skin):
		sd.unlocked_bees.append(skin)
	g._start_fresh_run()
	g.sky.backdrop = "hills"
	g.scenery_id += 1
	g._apply_bee_skin()
	g.score = score
	g.elapsed = elapsed
	g.camera_y -= climb
	while g.highest_spawn_y > g.camera_y - g.screen_h:
		g._spawn_row()
	g._update_score_label()
	# A run that is already past the moon's score (or Jupiter's, or the
	# UFO's) saw it long ago: without this they would all rise again at once.
	g.sky.moon_spawned = g.score >= g.sky.MOON_SCORE
	g.sky.jupiter_spawned = g.score >= g.sky.JUPITER_SCORE
	g.sky.ship_spawned = g.score >= g.sky.SHIP_SCORE
	var want_y: float = g.camera_y + g.screen_h * 0.52
	var target = null
	for fl in g.flowers:
		if target == null or absf(fl.position.y - want_y) < absf(target.position.y - want_y):
			target = fl
	# caught just after a tap towards the flower, from the side with more room
	var side := -1.0 if target.position.x > 200.0 else 1.0
	g.bee.position = target.position + Vector2(46.0 * side, 52.0)
	g.bee.facing = -int(side)
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
	g.pause_button.visible = false
	g.record_label.visible = false
	bot_on = true
	bot.reset()


func _direct() -> void:
	match f:
		179:
			_stage_run(3, 10.0, "normal", 150.0, seeds[0], 128)
		539:
			# the sunset at its height: the score and the time of a real run
			_stage_run(146, 162.0, "queen", 2400.0, seeds[1], 240)
		809:
			# One flower short of Jupiter's score, in the deep twilight a real
			# run has by then: it rises alone, as it does in the game (the moon
			# came a hundred flowers earlier).
			_stage_run(199, 219.0, "shining", 5200.0, seeds[2], 320)
		1439:
			_stage_title()
	# the camera eases in on the title, and drifts in on the end card
	var zoom := 1.0
	if f < T_PLAY:
		zoom = lerpf(1.16, 1.0, _ease_out(f / 170.0))
	elif f >= T_END:
		zoom = lerpf(1.0, 1.07, (f - T_END) / float(TOTAL - T_END))
	game_view.scale = Vector2.ONE * zoom
	# the line-up dims the run that keeps going behind it
	var a := 0.0
	if f >= T_BEES and f < T_END + 2:
		a = clampf((f - T_BEES) / 14.0, 0.0, 1.0) * 0.8
	dim.color.a = a
	ripples.visible = f >= T_PLAY and f < T_DUSK
	# wipes: covered for a few frames around each cut, while the scene changes
	var q := 0.0
	for c in WIPES:
		if f >= c - 13 and f <= c + 13:
			if f < c - 3:
				q = (f - (c - 13)) / 10.0
			elif f <= c + 3:
				q = 1.0
			else:
				q = 1.0 + (f - (c + 3)) / 10.0
			if f == c - 13:
				g._play_sfx(g.SFX_NEAR_MISS, -4.0, 0.8)
	wipe.q = q
	wipe.queue_redraw()


# ------------------------------------------------------------------ autopilot
# tools/godot/autopilot.gd decides; this taps, with the sound and the ring.
func _bot() -> void:
	if not bot_on or g.state != g.State.PLAYING:
		return
	var act: int = bot.step(g)
	if act != 0:
		g.bee.flap(act)
		g._play_sfx(g.SFX_FLAP, g.SFX_FLAP_DB, randf_range(0.92, 1.08))
		ripples.tap(act)


# ------------------------------------------------------------------ motion design
func _label(text: String, px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(5, roundi(px / 4.5)))
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _text_w(text: String, px: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


# A block of text lines centred on `at`, optionally on one of the game's own
# voxel plates. Returns the node to animate; its pivot is its centre.
func _card(lines: Array, at: Vector2, plate := "") -> Control:
	var w := 0.0
	var h := 0.0
	for ln in lines:
		w = maxf(w, _text_w(ln[0], ln[1]))
		h += ln[1] * 0.95
	var pad := Vector2(26.0, 14.0) if plate != "" else Vector2.ZERO
	var box := Control.new()
	box.size = Vector2(w, h) + pad * 2.0 + Vector2(0, 6.0 if plate != "" else 0.0)
	box.size = (box.size / 3.0).ceil() * 3.0
	box.position = (at - box.size / 2.0).round()
	box.pivot_offset = box.size / 2.0
	if plate != "":
		var p: Control = load("res://scripts/voxel_plate.gd").new()
		p.setup(plate, box.size, 3.0)
		box.add_child(p)
	var y := pad.y
	for ln in lines:
		var l := _label(ln[0], ln[1], ln[2] if ln.size() > 2 else Color.WHITE)
		l.position = Vector2(0, y - ln[1] * 0.06)
		l.size = Vector2(box.size.x, ln[1])
		box.add_child(l)
		y += ln[1] * 0.95
	layer.add_child(box)
	box.visible = false
	return box


# Shows `node` from frame t0 to t1: pops in with an overshoot, bobs a little
# while it stays, drops away at the end. `sound` plays as it lands.
func _show(node: Control, t0: int, t1: int, sound = null, db := -8.0, pitch := 1.0) -> void:
	fx.append({"n": node, "t0": t0, "t1": t1, "pos": node.position, "sfx": sound, "db": db, "pitch": pitch})


func _ease_out(a: float) -> float:
	a = clampf(a, 0.0, 1.0)
	return 1.0 - pow(1.0 - a, 3.0)


func _back_out(a: float) -> float:
	a = clampf(a, 0.0, 1.0)
	return 1.0 + 2.70158 * pow(a - 1.0, 3.0) + 1.70158 * pow(a - 1.0, 2.0)


func _animate() -> void:
	for e in fx:
		var n: Control = e["n"]
		if f < int(e["t0"]) or f > int(e["t1"]) + 9:
			n.visible = false
			continue
		n.visible = true
		if f == int(e["t0"]) and e["sfx"] != null:
			g._play_sfx(e["sfx"], e["db"], e["pitch"])
		var t0: int = e["t0"]
		var t1: int = e["t1"]
		var a: float = (f - t0) / 14.0
		var out: float = clampf((f - t1) / 9.0, 0.0, 1.0)
		var s := _back_out(a) * (1.0 - out * 0.35)
		n.scale = Vector2.ONE * maxf(s, 0.001)
		n.modulate.a = clampf(a * 3.0, 0.0, 1.0) * (1.0 - out)
		n.rotation = sin((f - t0) * 0.07) * 0.012 + (1.0 - clampf(a, 0.0, 1.0)) * -0.12
		var home: Vector2 = e["pos"]
		n.position = home + Vector2(0, sin((f - t0) * 0.09) * 2.0 + out * 26.0)
	ripples.step()


func _logo(width: float, centre: Vector2) -> Control:
	var img: Image = load("res://art/ui/splash.png").get_image()
	var tex := AtlasTexture.new()
	tex.atlas = load("res://art/ui/splash.png")
	tex.region = Rect2(img.get_used_rect())
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2(width, width * tex.region.size.y / tex.region.size.x)
	r.position = centre - r.size / 2.0
	r.pivot_offset = r.size / 2.0
	layer.add_child(r)
	r.visible = false
	return r


func _build_timeline() -> void:
	var tap = g.SFX_UI_TAP
	var note = g.SFX_COLLECT
	var steps: Array = g.COLLECT_PITCH_STEPS

	# --- title
	_show(_logo(344.0, Vector2(200, 170)), 3, 160, note, -6.0, 1.0)
	_show(_card([["SUBA SEM PARAR", 46]], Vector2(200, 330), "honey"), 45, 160, tap, -6.0)
	_show(_card([["E NÃO PERCA", 40], ["NENHUMA FLOR", 40]], Vector2(200, 430), "honey"), 90, 160, tap, -6.0, 1.2)

	# --- day: how it's played
	_show(_card([["TOQUE NA ESQUERDA", 38], ["OU NA DIREITA", 38]], Vector2(200, 615), "honey"), T_PLAY + 16, 345, tap, -6.0)
	_show(_card([["PASSE PELAS", 38], ["ROSEIRAS", 52, GOLD]], Vector2(200, 615), "dark"), 360, T_DUSK - 18, tap, -6.0, 1.2)
	# --- dusk
	_show(_card([["PEGUE TODAS", 40], ["AS FLORES", 54, GOLD]], Vector2(200, 615), "dark"), T_DUSK + 16, T_NIGHT - 18, tap, -6.0)
	# --- night
	_show(_card([["DO DIA", 44], ["ATÉ A NOITE", 54, GOLD]], Vector2(200, 615), "dark"), T_NIGHT + 16, T_BEES - 14, tap, -6.0, 1.2)

	# --- the seven bees, one per beat
	_show(_card([["7 ABELHAS", 72, GOLD], ["PARA DESBLOQUEAR", 36]], Vector2(200, 112)), T_BEES + 4, T_ASK - 10, tap, -6.0)
	var bees := [["normal", "Bee", "início"], ["rosy", "Rosy", "25 pontos"], ["mint", "Mint", "60 pontos"],
			["ice", "Ice", "100 pontos"], ["grape", "Grape", "150 pontos"], ["queen", "Queen", "220 pontos"],
			["shining", "Silver", "300 pontos"]]
	for k in bees.size():
		var centre := Vector2(200, 596) if k == 6 else Vector2(78 + (k % 3) * 122, 268 + (k / 3) * 164)
		var card := Control.new()
		card.size = Vector2(114, 150)
		card.position = centre - card.size / 2.0
		card.pivot_offset = card.size / 2.0
		var p: Control = load("res://scripts/voxel_plate.gd").new()
		p.setup("dark", card.size, 3.0)
		card.add_child(p)
		var icon := TextureRect.new()
		icon.texture = load("res://art/ui/bee_%s.png" % bees[k][0])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = Vector2(92, 92)
		icon.position = Vector2(11, 6)
		card.add_child(icon)
		var name := _label(bees[k][1], 30, GOLD if k == 6 else Color.WHITE)
		name.position = Vector2(0, 92)
		name.size = Vector2(114, 30)
		card.add_child(name)
		var pts := _label(bees[k][2], 19, Color(0.86, 0.80, 0.95))
		pts.position = Vector2(0, 119)
		pts.size = Vector2(114, 20)
		card.add_child(pts)
		layer.add_child(card)
		card.visible = false
		_show(card, T_BEES + 22 + roundi(k * 22.5), T_ASK - 10 + k, note, -7.0, steps[k % steps.size()] * (2.0 if k >= 5 else 1.0))
	_show(_card([["QUAL É O SEU", 62], ["RECORDE?", 96, GOLD]], Vector2(200, 340)), T_ASK, T_END - 16, g.SFX_RECORD, -5.0)

	# --- end card
	_show(_logo(352.0, Vector2(200, 150)), T_END + 12, TOTAL + 60, note, -6.0, 1.0)
	_show(_card([["JOGUE GRÁTIS", 60]], Vector2(200, 318), "green"), T_END + 90, TOTAL + 60, tap, -6.0)
	_show(_card([["beebee.cyberhat.com.br", 37], ["Android e navegador", 25, Color(0.86, 0.80, 0.95)]], Vector2(200, 418), "dark"), T_END + 180, TOTAL + 60, tap, -6.0, 1.2)


# ------------------------------------------------------------------ drawn layers
# The cut between scenes: the screen fills with honey blocks along a
# diagonal, and empties the same way once the next scene is in place.
class Wipe extends Control:
	const CELL := 44.5
	var q := 0.0

	func _draw() -> void:
		if q <= 0.0 or q >= 2.0:
			return
		var cols := int(ceil(size.x / CELL))
		var rows := int(ceil(size.y / CELL))
		for cy in rows:
			for cx in cols:
				var d := (cx + cy) / float(cols + rows) * 0.5
				var s := clampf(q * 1.5 - d, 0.0, 1.0) if q <= 1.0 else 1.0 - clampf((q - 1.0) * 1.5 - d, 0.0, 1.0)
				if s <= 0.0:
					continue
				var side := CELL * s + (1.0 if s >= 1.0 else 0.0)
				var c := Vector2(cx + 0.5, cy + 0.5) * CELL
				var col := Color(0.98, 0.76, 0.20) if (cx + cy) % 2 == 0 else Color(1.0, 0.84, 0.30)
				draw_rect(Rect2(c - Vector2.ONE * side / 2.0, Vector2.ONE * side), col)


# A ring where the "finger" lands each time the autopilot taps, so the
# controls explain themselves.
class Ripples extends Control:
	var taps: Array = []

	func tap(side: int) -> void:
		taps.append([Vector2(96.0 if side < 0 else 304.0, 500.0), 0])

	func step() -> void:
		for t in taps:
			t[1] += 1
		taps = taps.filter(func(t): return t[1] < 22)
		queue_redraw()

	func _draw() -> void:
		for t in taps:
			var a: float = t[1] / 22.0
			var r := lerpf(14.0, 52.0, 1.0 - pow(1.0 - a, 2.0))
			draw_circle(t[0], r, Color(1, 1, 1, 0.22 * (1.0 - a)))
			draw_arc(t[0], r, 0.0, TAU, 40, Color(1, 1, 1, 0.9 * (1.0 - a)), 5.0, true)
			draw_circle(t[0], 11.0 * (1.0 - a * 0.5), Color(1, 1, 1, 0.85 * (1.0 - a)))
