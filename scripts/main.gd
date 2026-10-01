extends Node2D

# Bee Bee — root game script. Everything (camera, bee, UI, ground/trees,
# obstacles, flowers, clouds) is built here by code rather than laid out by
# hand in the editor — see HANDOFF_Claude_Code.md section 2 for why.

enum State { START, STARTING, PLAYING, PAUSED, DYING, GAMEOVER }

const SCREEN_W := 400.0
# shortest view the layout is made for (16:9); see _ready
const MIN_SCREEN_H := 711.0

# Physics/gameplay constants ported verbatim from reference-prototype.html.
const OBSTACLE_SPACING := 190.0
# TEST — speed bump requested to see how a faster game feels. Previous
# (long-standing) values, to restore if this doesn't stick:
#   SCROLL_BASE := 78.0
#   SCROLL_MAX := 148.0
# TEST — raised again by 15% (was 90.0 / 170.0) after the game came out
# much easier on the phone: the bee had been given 15% more sideways speed
# (bee.gd H_SPEED) while the climb stayed the same, so every row left more
# time to spare. This puts the two back in their old proportion.
const SCROLL_BASE := 103.0
# Prototype's original ramp topped out at 165 (too punishing with mandatory
# flowers + shrinking gaps); 110 was too tame, 135 still felt easy.
const SCROLL_MAX := 195.0
# TEST — shortened from 50 so every run gets tense sooner; top speed and
# narrowest gap are unchanged, they're just reached earlier.
const DIFFICULTY_RAMP_TIME := 35.0
# The bees the player can fly. `score` is what a run has to reach to win the
# skin (0 = there from the start); the silver one is the hardest. `size`
# (hitbox and model) and `speed` (sideways speed) are relative to the base
# values in bee.gd, so a skin could fly differently; today every skin is
# purely cosmetic. `glow` draws the model unshaded.
const BEE_SKINS := {
	"normal": {"name": "Bee", "score": 0, "model": "bee", "size": 1.0, "speed": 1.0, "glow": false},
	"rosy": {"name": "Rosy Bee", "score": 25, "model": "bee_voxel_rosy", "size": 1.0, "speed": 1.0, "glow": false},
	"mint": {"name": "Mint Bee", "score": 60, "model": "bee_voxel_mint", "size": 1.0, "speed": 1.0, "glow": false},
	"ice": {"name": "Ice Bee", "score": 100, "model": "bee_voxel_ice", "size": 1.0, "speed": 1.0, "glow": false},
	"grape": {"name": "Grape Bee", "score": 150, "model": "bee_voxel_grape", "size": 1.0, "speed": 1.0, "glow": false},
	"queen": {"name": "Queen Bee", "score": 220, "model": "bee_voxel_queen", "size": 1.0, "speed": 1.0, "glow": false},
	"shining": {"name": "Silver Bee", "score": 300, "model": "bee_voxel_shining", "size": 1.0, "speed": 1.0, "glow": true},
}
# menu order: easiest to hardest
const BEE_ORDER := ["normal", "rosy", "mint", "ice", "grape", "queen", "shining"]
const GOLD := Color(1, 0.82, 0.18)
# Widest sideways distance, at max difficulty, between a gap and the next
# flower or between a flower and the next gap (see _spawn_row).
const MAX_LEG_HARD := 200.0

# How long after the first flap the camera waits before it starts climbing
# (the bee itself is already flying/falling normally during this pause).
# Replays get the shorter one (TEST, was 1.0 for every run): by then the
# player already knows the controls and just wants back into the action.
const SCROLL_START_DELAY := 1.0
const REPLAY_SCROLL_START_DELAY := 0.5
# TEST — how long the dead bee falls before the game-over panel (was 1.4).
# Still long enough to watch the fall and the death shake land.
const DEATH_FALL_TIME := 0.8
# Short grace window after the first flap where falling off the bottom of
# the (still tightly-framed) cold-start view can't end the run — a rapid
# extra tap right after "Play Again" (e.g. an impatient double-press) could
# otherwise land as a flap with no follow-up, and the bee had barely any
# room to fall before being ruled "off-screen" against the ground-flush
# framing. Obstacle/flower rules are unaffected — nothing is close enough
# to matter this early anyway.
const FALL_DEATH_GRACE := 0.5

# Music sits under whatever else the game plays; the theme itself is
# mastered around -14.5 dBFS RMS, so this only trims it the rest of the way.
const MUSIC_VOLUME_DB := -5.0
# Muting by volume rather than stopping the player keeps the track running
# underneath, so unmuting picks up where the loop got to instead of
# snapping back to the top of the phrase.
const MUSIC_MUTED_DB := -80.0

const SFX_FLAP := preload("res://audio/sfx_flap.wav")
const SFX_COLLECT := preload("res://audio/sfx_collect.wav")
const SFX_HIT := preload("res://audio/sfx_hit.wav")
const SFX_RECORD := preload("res://audio/sfx_record.wav")
const SFX_UI_TAP := preload("res://audio/sfx_ui_tap.wav")
const SFX_NEAR_MISS := preload("res://audio/sfx_near_miss.wav")

# Levels live here rather than baked into the files so the mix can be
# balanced without re-rendering. The flap sits lowest by a wide margin:
# it fires on every single tap, and anything louder takes over the mix
# within one run.
const SFX_FLAP_DB := -18.0
const SFX_COLLECT_DB := -6.0
const SFX_HIT_DB := -3.0
const SFX_RECORD_DB := -5.0
const SFX_UI_DB := -13.0
const SFX_NEAR_MISS_DB := -7.0

# TEST — a "near miss" cue (screen shake + whoosh) when the bee grazes past
# a gap edge within this many px without hitting it, requested to see if
# that close-call thrill makes the game more addictive. Margin is on top
# of the bee's radius, i.e. how much closer than "just barely fits" still counts.
const NEAR_MISS_MARGIN := 8.0
const CAMERA_SHAKE_DURATION := 0.18
const CAMERA_SHAKE_MAGNITUDE := 4.0
# Death gets a bigger jolt than a near miss — it's the bigger event of the
# two. Reuses the same SFX_HIT that already plays on every game over; no
# second sound layered on top, just nudged up a touch (below) so it reads
# clearly alongside the new shake instead of blending into the fall.
const DEATH_SHAKE_DURATION := 0.3
const DEATH_SHAKE_MAGNITUDE := 7.0

# Enough voices that a flap, a pickup and a jingle can overlap without
# any of them being cut short.
const SFX_VOICES := 8

# Minor-pentatonic steps (A C D E G), the theme's own key. Each flower in
# a run lands one step higher before wrapping, so a good run reads as a
# rising figure rather than the same blip over and over.
const COLLECT_PITCH_STEPS := [1.0, 1.1892, 1.3348, 1.4983, 1.7818]

# Deep plum used for text outlines and UI backing — the UI's share of the
# art's tinted-ink look.
const UI_INK := Color(0.24, 0.13, 0.32)

# Icons are drawn as pixel grids rather than imported art, so they match
# the game's own resolution instead of being scaled-down smooth shapes.
const ICON_PAUSE := [
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
	"XX.XX",
]
const ICON_NOTE := [
	"...XXXXXXX.",
	"...XXXXXXX.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	"...X.....X.",
	".XXX...XXX.",
	"XXXXX.XXXXX",
	"XXXXX.XXXXX",
	".XXX...XXX.",
]
const ICON_PLAY := [
	"XX.......",
	"XXXX.....",
	"XXXXXX...",
	"XXXXXXXX.",
	"XXXXXXXXX",
	"XXXXXXXX.",
	"XXXXXX...",
	"XXXX.....",
	"XX.......",
]
# points right; the left one is the same rows mirrored
const ICON_ARROW := [
	"......X....",
	"......XX...",
	"XXXXXXXXX..",
	"XXXXXXXXXX.",
	"XXXXXXXXXXX",
	"XXXXXXXXXX.",
	"XXXXXXXXX..",
	"......XX...",
	"......X....",
]
const ICON_VIBRATE := [
	"...XXXXX...",
	"...X...X...",
	"...X...X...",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"X..X...X..X",
	"...X...X...",
	"...X.X.X...",
	"...XXXXX...",
]
const ICON_TROPHY := [
	"XXXXXXXXXXX",
	"X.XXXXXXX.X",
	"X.XXXXXXX.X",
	".XXXXXXXXX.",
	"..XXXXXXX..",
	"...XXXXX...",
	"....XXX....",
	".....X.....",
	".....X.....",
	"...XXXXX...",
	"..XXXXXXX..",
]
const ICON_SLASH := [
	"X..........",
	"XX.........",
	".XX........",
	"..XX.......",
	"...XX......",
	"....XX.....",
	".....XX....",
	"......XX...",
	".......XX..",
	"........XX.",
	".........XX",
]

const ObstacleScript := preload("res://scripts/obstacle.gd")
const FlowerScript := preload("res://scripts/flower.gd")
const CloudScript := preload("res://scripts/cloud.gd")
const SeagullScript := preload("res://scripts/seagull.gd")
const SkyScript := preload("res://scripts/sky.gd")
const AdsScript := preload("res://scripts/ads.gd")
const LeaderboardScript := preload("res://scripts/leaderboard.gd")
const View3DScript := preload("res://scripts/view3d.gd")
const VoxelPlate := preload("res://scripts/voxel_plate.gd")
const VoxelLogo := preload("res://scripts/voxel_logo.gd")
# One cube of the interface's grid, in UI pixels: every plate is a whole
# number of these, about two of the world's cubes across.
const UI_CELL := 3.0
const BeeScript := preload("res://scripts/bee.gd")

# How far below the grass line (world y = 0, where the bee stands) the
# cold-start view reaches: the strip of earth under the grass.
const GROUND_DEPTH := 19.9

var state: State = State.START
# The stretch mode is keep_width: the world is always 400 wide, and a phone
# taller than 1:2 (nearly all of them) shows more sky instead of black bars.
# So the visible height is only known at runtime.
var screen_h := 800.0
var world_moving := false
var scrolling_started := false
var launch_timer := 0.0
var time_since_first_flap := 0.0
var has_finished_a_run := false
var has_tapped_once := false
var hint_alpha := 0.0

var elapsed := 0.0
var camera_y := 0.0
var camera_shake_time := 0.0
var camera_shake_total := 0.0
var camera_shake_magnitude := 0.0
var highest_spawn_y := 0.0
var last_gap_x := 0.0
var rows_spawned := 0
var score := 0
var dying_timer := 0.0
# Marks the height of the flower that breaks the record; view3d.gd draws it.
var record_line: Node2D
var record_word_on_left := true

var obstacles: Array = []
var flowers: Array = []
var clouds: Array = []
var seagulls: Array = []
var celestials: Array = []

var bee: CharacterBody2D
var music: AudioStreamPlayer
var ads: Node
var leaderboard: Node
# "Play Again" was pressed and an ad is up: the run starts when it closes.
var restart_after_ad := false
var sfx_pool: Array[AudioStreamPlayer] = []
var collect_step := 0
var physics_ticks_since_reset := 0
var camera: Camera2D
var sky: Node
# Bumped every time a fresh start scene is built; view3d.gd rebuilds the
# ground, trees and far backdrop whenever it changes.
var scenery_id := 0

var ui_font: Font

var score_label: Label
var record_label: Label
var direction_hint: Control
var start_screen: Control
var play_button: Button
var game_over_screen: Control
var final_score_label: Label
var final_best_label: Label
var restart_button: Button
var new_record_badge: Label
var record_pulse: Tween
var pause_button: Button
var pause_screen: Control
var music_note: Control
var music_slash: Control
var vibrate_icon: Control
var vibrate_slash: Control
var privacy_button: Button
var view3d: Node3D
var applied_bee_skin := ""
var bee_menu: Control
var bee_notice: Control
var bee_notice_icon: TextureRect
var bee_notice_title: Label
var bee_cards := {}                      # skin id -> its card's nodes in the bee menu
var bee_button_icons: Array[TextureRect] = []


func _ready() -> void:
	# The layout needs a screen at least 16:9 tall. On anything squatter (a
	# tablet, a foldable opened flat) keep_width would leave too little
	# height for the menus and for reading the next row, so there the game
	# keeps a 16:9 column in the middle with bars at the sides instead.
	var window := get_window()
	if float(window.size.y) / maxf(1.0, window.size.x) < MIN_SCREEN_H / SCREEN_W:
		window.content_scale_size = Vector2i(int(SCREEN_W), int(MIN_SCREEN_H))
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	screen_h = get_viewport_rect().size.y

	# Jersey 10 (SIL OFL 1.1, see fonts/Jersey10-OFL.txt): a chunky pixel
	# face, so the text is made of squares like the voxel world behind it.
	ui_font = load("res://fonts/Jersey10-Regular.ttf")

	sky = SkyScript.new()
	add_child(sky)
	sky.moon_spawn_requested.connect(_on_moon_spawn_requested)
	sky.jupiter_spawn_requested.connect(_on_jupiter_spawn_requested)
	sky.ship_spawn_requested.connect(_on_ship_spawn_requested)
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	camera.enabled = true
	camera.make_current()

	bee = CharacterBody2D.new()
	bee.set_script(BeeScript)
	add_child(bee)

	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		# UI taps fire from the pause menu while the tree is frozen, so the
		# pool has to keep running through a pause just like the music does.
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		sfx_pool.append(voice)

	leaderboard = LeaderboardScript.new()
	add_child(leaderboard)
	leaderboard.start()

	_build_ui()

	# One continuous loop across menu, run and game over — restarting it per
	# run would clip the phrase mid-bar on every death. Nothing here repeats
	# it in code: the WAV is imported with loop mode Forward, so the repeat
	# is gapless inside the audio server.
	music = AudioStreamPlayer.new()
	music.stream = preload("res://audio/music_theme.wav")
	# Pausing the game freezes the whole tree, so the player has to opt out
	# of that or the track would cut off the moment the menu opens.
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	music.play()

	ads = AdsScript.new()
	add_child(ads)
	# an ad plays its own sound, and the music would run on underneath it
	ads.ad_opened.connect(func(): music.stream_paused = true)
	ads.ad_closed.connect(_on_ad_closed)
	ads.start()
	_apply_music_mute()

	_reset_to_ground_scene()

	# Everything the player sees of the world is drawn in 3D by view3d.gd,
	# which mirrors this node's 2D simulation every frame.
	view3d = View3DScript.new()
	add_child(view3d)
	view3d.setup(self)
	_apply_bee_skin()

	state = State.START
	start_screen.visible = true
	start_screen.modulate.a = 1.0
	game_over_screen.visible = false
	# The title screen keeps the record (worth seeing before a run) but not
	# the live score, a "0" that otherwise sits right on top of the logo.
	score_label.visible = false
	# The tutorial arrows belong to the ground scene, not the title — on
	# top of it they cut straight through the logo and the Play button.
	# They fade in with the title's fade-out instead.
	direction_hint.visible = false


func _notification(what: int) -> void:
	match what:
		# A call, the home button or the notification shade pulled down
		# mid-run would otherwise leave the bee falling with nobody at the
		# controls, or dropped into a fall the moment the app comes back.
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if state == State.PLAYING:
				_on_pause_pressed()
		# quit_on_go_back is off in project.godot, so back no longer kills
		# the app mid-run: it pauses a run, resumes a paused one, and only
		# leaves from the screens where there's nothing to lose.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match state:
				State.PLAYING:
					_on_pause_pressed()
				State.PAUSED:
					_on_resume_pressed()
				State.START, State.GAMEOVER:
					if bee_menu.visible:
						_on_bee_menu_closed()
					else:
						get_tree().quit()


# ------------------------------------------------------------------
# World (re)generation
# ------------------------------------------------------------------

func _clear_world() -> void:
	for o in obstacles:
		o.queue_free()
	for f in flowers:
		# queue_free() is deferred to end-of-frame — stop it detecting the
		# bee in the meantime.
		f.monitoring = false
		f.queue_free()
	for c in clouds:
		c.queue_free()
	for g in seagulls:
		g.queue_free()
	for c in celestials:
		c.queue_free()
	obstacles.clear()
	flowers.clear()
	clouds.clear()
	seagulls.clear()
	celestials.clear()
	if record_line:
		record_line.queue_free()
		record_line = null


func _reset_to_ground_scene() -> void:
	# Builds a fresh grounded start: bee resting on the ground, world
	# regenerated. Used both at app cold-start and on every "Play Again"
	# after a game over. Per spec 4.8, the one thing this must NOT do is
	# re-randomize the world that's already visible behind the start screen
	# the very first time the player presses Play — callers handle that by
	# only calling this once before that first press.
	_clear_world()
	sky.reset_run()
	collect_step = 0
	physics_ticks_since_reset = 0

	scenery_id += 1

	_apply_bee_skin()
	# the grass line is world y = 0
	bee.reset_bee(Vector2(SCREEN_W / 2.0, -bee.radius))
	world_moving = false
	scrolling_started = false
	launch_timer = 0.0
	time_since_first_flap = 0.0
	camera_shake_time = 0.0

	# Frame the cold-start camera so the bottom of the ground sits flush with
	# the bottom of the screen.
	camera_y = GROUND_DEPTH - screen_h
	camera.position = Vector2(0.0, camera_y)

	elapsed = 0.0
	score = 0
	dying_timer = 0.0
	# obstacles start comfortably above the ground/trees so they don't
	# overlap the cold-start framing.
	highest_spawn_y = -200.0
	last_gap_x = SCREEN_W / 2.0   # the bee starts centred on the ground
	rows_spawned = 0

	has_tapped_once = SaveData.seen_tutorial
	hint_alpha = 0.0 if SaveData.seen_tutorial else 1.0
	direction_hint.modulate.a = hint_alpha
	direction_hint.visible = hint_alpha > 0.0

	_update_score_label()
	record_label.text = "Record: %d" % SaveData.best_score

	for i in range(6):
		_spawn_row()


func _spawn_row() -> void:
	var y: float = highest_spawn_y - OBSTACLE_SPACING
	highest_spawn_y = y

	var diff: float = _difficulty()
	# TEST — 6.4 px narrower at every difficulty (was 175.0 - diff * 75.0).
	# The bee's hitbox went from 16 to 12.8 px in radius, which in effect
	# widened every gap by that much; this gives back the old free space
	# around the bee.
	var gap_width: float = 168.6 - diff * 75.0
	var margin: float = gap_width / 2.0 + 24.0
	var flower_clear: float = gap_width / 2.0 + 20.0

	# The climb goes previous gap -> this row's flower -> this row's gap, and
	# at top speed there's only ~0.55s per leg. Fully random placement could
	# put a flower on the far side of both gaps, a sideways run past what the
	# bee can physically make in that time (~1 row in 35 at max speed), so
	# each leg is capped, tightening with difficulty. Measured against the
	# bee's own flap physics, the worst row at the cap is ~130% of its
	# sustained sideways speed (was 213%), while the average still asks for
	# nearly half of it.
	var max_leg: float = lerp(SCREEN_W, MAX_LEG_HARD, diff)
	var gap_x: float
	var fx: float
	for _attempt in 64:
		gap_x = margin + randf() * (SCREEN_W - margin * 2.0)
		fx = 30.0 + randf() * (SCREEN_W - 60.0)
		if abs(fx - gap_x) < flower_clear:
			continue
		if abs(fx - last_gap_x) <= max_leg and abs(fx - gap_x) <= max_leg:
			break
	if abs(fx - gap_x) < flower_clear:
		fx = gap_x - flower_clear if gap_x - flower_clear >= 30.0 else gap_x + flower_clear
	last_gap_x = gap_x

	var obstacle := Node2D.new()
	obstacle.set_script(ObstacleScript)
	obstacle.position = Vector2(0, y)
	add_child(obstacle)
	obstacle.setup(gap_x, gap_width)
	obstacles.append(obstacle)

	var fy: float = y + OBSTACLE_SPACING / 2.0 + (randf() * 40.0 - 20.0)

	var flower := Area2D.new()
	flower.set_script(FlowerScript)
	flower.position = Vector2(fx, fy)
	add_child(flower)
	flower.setup()
	flowers.append(flower)

	# Every row carries exactly one mandatory flower, collected in order, so
	# row N's flower is always the one that takes the score to N — the row
	# numbered best+1 holds the flower that breaks the record.
	rows_spawned += 1
	if SaveData.best_score > 0 and rows_spawned == SaveData.best_score + 1:
		_spawn_record_line(fy, fx)

	# Clouds keep appearing through the night, just less often once the sky
	# has started turning.
	var cloud_chance: float = 0.85 if score < 50 else 0.35
	if randf() < cloud_chance:
		var cloud := Node2D.new()
		cloud.set_script(CloudScript)
		cloud.position = Vector2(randf() * SCREEN_W, y - randf() * 60.0)
		add_child(cloud)
		cloud.setup()
		clouds.append(cloud)

	if score < 75 and randf() < 0.15:
		var gull := Node2D.new()
		gull.set_script(SeagullScript)
		gull.position = Vector2(randf() * SCREEN_W, y - randf() * 80.0)
		add_child(gull)
		gull.setup()
		seagulls.append(gull)


func _spawn_record_line(y: float, flower_x: float) -> void:
	record_line = Node2D.new()
	record_line.position = Vector2(0.0, y)
	add_child(record_line)
	# the word RECORD goes on the side away from the flower, so the two never overlap
	record_word_on_left = flower_x > SCREEN_W / 2.0


# Dropping the marker is the cue: view3d.gd flashes the line it was drawing
# and lets it go.
func _flash_record_line() -> void:
	record_line.queue_free()
	record_line = null


# ------------------------------------------------------------------
# Update loop
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	physics_ticks_since_reset += 1
	match state:
		State.PLAYING:
			_update_playing(delta)
		State.DYING:
			_update_dying(delta)
		_:
			pass

	# camera_y itself only moves inside _update_playing's scroll branch, so
	# re-deriving the base position here every frame is a no-op outside
	# PLAYING — which is exactly "frozen" during DYING, letting a shake
	# (near miss or death) jitter around that fixed point without drifting.
	camera.position = Vector2(0.0, camera_y)
	_apply_camera_shake(delta)

	sky.check_triggers(score)


func _start_camera_shake(duration: float, magnitude: float) -> void:
	camera_shake_time = duration
	camera_shake_total = duration
	camera_shake_magnitude = magnitude


func _apply_camera_shake(delta: float) -> void:
	if camera_shake_time <= 0.0:
		return
	camera_shake_time = max(0.0, camera_shake_time - delta)
	var t: float = camera_shake_time / camera_shake_total if camera_shake_total > 0.0 else 0.0
	var mag: float = camera_shake_magnitude * t
	camera.position += Vector2(randf_range(-mag, mag), randf_range(-mag, mag))


func _update_playing(delta: float) -> void:
	if has_tapped_once and hint_alpha > 0.0:
		hint_alpha = max(0.0, hint_alpha - delta * 2.5)
		direction_hint.modulate.a = hint_alpha
		if hint_alpha <= 0.0:
			direction_hint.visible = false

	if not world_moving:
		return

	time_since_first_flap += delta

	if not scrolling_started:
		launch_timer += delta
		var start_delay: float = REPLAY_SCROLL_START_DELAY if has_finished_a_run else SCROLL_START_DELAY
		if launch_timer >= start_delay:
			scrolling_started = true
	else:
		elapsed += delta

		camera_y -= _current_scroll_speed() * delta

		while highest_spawn_y > camera_y - screen_h:
			_spawn_row()

	# The bee is already flying/falling under normal physics from the first
	# flap onward, camera frozen or not — so the usual rules (missed
	# obstacle, missed flower, falling past the bottom of what's currently
	# visible) apply the whole time, same as they did before the 1s pause
	# existed. The pause only delays the camera's own climb.
	var screen_bottom := camera_y + screen_h
	var bottom_cull := screen_bottom + 200.0
	for o in obstacles.duplicate():
		if o.position.y > bottom_cull:
			obstacles.erase(o)
			o.queue_free()
	for c in clouds.duplicate():
		if c.position.y > bottom_cull or c.position.x > SCREEN_W + 150.0 or c.position.x < -150.0:
			clouds.erase(c)
			c.queue_free()
	for g in seagulls.duplicate():
		if g.position.y > bottom_cull or g.position.x > SCREEN_W + 150.0 or g.position.x < -150.0:
			seagulls.erase(g)
			g.queue_free()
	for c in celestials.duplicate():
		if c.position.y > bottom_cull:
			celestials.erase(c)
			c.queue_free()
	if record_line and record_line.position.y > bottom_cull:
		record_line.queue_free()
		record_line = null

	# Every flower is mandatory — letting one scroll off the bottom
	# uncollected ends the run, same as hitting an obstacle (spec change:
	# missing a flower is now a game-over condition, not just a missed point).
	# Only once it is *entirely* gone, though, matching the bee's own rule:
	# half a flower still on screen is still reachable, and dying to it
	# reads as the game cheating.
	for f in flowers:
		if f.position.y - FlowerScript.FLOWER_R > screen_bottom:
			_trigger_game_over()
			return

	for o in obstacles:
		var band_top: float = o.position.y
		var band_bottom: float = band_top + ObstacleScript.THICK
		var in_band: bool = bee.position.y + bee.radius >= band_top and bee.position.y - bee.radius <= band_bottom
		if in_band:
			var gap_left: float = o.gap_x - o.gap_width / 2.0
			var gap_right: float = o.gap_x + o.gap_width / 2.0
			var clearance := INF
			if gap_left > 0.0:
				clearance = _circle_rect_clearance(bee.position, bee.radius, Vector2(0.0, band_top), Vector2(gap_left, band_bottom))
			if gap_right < SCREEN_W:
				clearance = min(clearance, _circle_rect_clearance(bee.position, bee.radius, Vector2(gap_right, band_top), Vector2(SCREEN_W, band_bottom)))
			if clearance < 0.0:
				_trigger_game_over()
				return
			# Track the closest the bee gets to either bar while it's in this
			# row's band — checked once the bee has fully cleared it, below.
			o.near_miss_min_clearance = min(o.near_miss_min_clearance, clearance)
		elif not o.near_miss_checked and o.near_miss_min_clearance <= NEAR_MISS_MARGIN:
			o.near_miss_checked = true
			_trigger_near_miss()

	if time_since_first_flap >= FALL_DEATH_GRACE and bee.position.y - bee.radius > screen_bottom:
		_trigger_game_over()


func _circle_rect_clearance(circle_center: Vector2, radius: float, rect_min: Vector2, rect_max: Vector2) -> float:
	# Standard circle-vs-AABB distance: find the closest point on the rect to
	# the circle's center. Negative means overlap (a hit) — this treats the
	# bee as the circle it actually looks like, instead of the square
	# bounding box the old check used, which let corners of the invisible
	# hitbox clip the roseira before the round bee visually touched
	# it. The actual (non-negative) distance doubles as the near-miss
	# clearance so both checks share one geometry test.
	var closest := Vector2(
		clamp(circle_center.x, rect_min.x, rect_max.x),
		clamp(circle_center.y, rect_min.y, rect_max.y)
	)
	return circle_center.distance_to(closest) - radius


func _trigger_near_miss() -> void:
	_start_camera_shake(CAMERA_SHAKE_DURATION, CAMERA_SHAKE_MAGNITUDE)
	_play_sfx(SFX_NEAR_MISS, SFX_NEAR_MISS_DB)


func _update_dying(delta: float) -> void:
	dying_timer += delta
	if bee.position.y - bee.radius > camera_y + screen_h or dying_timer > DEATH_FALL_TIME:
		_end_game()


func _current_scroll_speed() -> float:
	return SCROLL_BASE + (SCROLL_MAX - SCROLL_BASE) * _difficulty()


func _difficulty() -> float:
	return clamp(elapsed / DIFFICULTY_RAMP_TIME, 0.0, 1.0)


func on_flower_collected(flower: Area2D) -> void:
	if state != State.PLAYING:
		return
	if not flowers.has(flower):
		return
	if not _bee_contacts_trustworthy():
		return
	flowers.erase(flower)
	flower.play_collect_effect()
	_play_sfx(SFX_COLLECT, SFX_COLLECT_DB, COLLECT_PITCH_STEPS[collect_step])
	collect_step = (collect_step + 1) % COLLECT_PITCH_STEPS.size()
	score += 1
	_update_score_label()
	_check_bee_unlocks()
	if record_line and score == SaveData.best_score + 1:
		_flash_record_line()


func _bee_contacts_trustworthy() -> bool:
	# Flower pickups come from the physics server, which lags a teleport: a
	# reset moves the bee, but the server only adopts the new position at
	# the *end* of its next step — after that step has already tested every
	# flower against the old one, and those results arrive at the start of
	# the step after. For those two ticks a reported overlap describes where
	# the last run ended, and since rows regenerate at the same heights, a
	# new flower on that spot would collect itself. Gated on ticks rather
	# than the first flap because a tap in the same frame as "Play Again"
	# flaps before any step runs. (Obstacles don't need this: they're tested
	# directly against the bee's node position in _update_playing.)
	return physics_ticks_since_reset >= 2


func _trigger_game_over() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	dying_timer = 0.0
	pause_button.visible = false
	_start_camera_shake(DEATH_SHAKE_DURATION, DEATH_SHAKE_MAGNITUDE)
	_play_sfx(SFX_HIT, SFX_HIT_DB)
	_vibrate(70)
	bee.die()
	# The bee keeps falling under its own gravity — no impact effect, no
	# reposition. Tested and decided explicitly (spec 4.7): any collision FX
	# made the moment feel worse. Only the face/pose changes; the fall itself
	# is untouched.


func _end_game() -> void:
	state = State.GAMEOVER
	has_finished_a_run = true
	bee.physics_enabled = false

	var beat_record := score > SaveData.best_score
	if beat_record:
		SaveData.best_score = score
		SaveData.save_data()
		_play_sfx(SFX_RECORD, SFX_RECORD_DB)
		_vibrate(160)
	leaderboard.submit(score)

	final_score_label.text = "%d" % score
	final_best_label.text = "%d" % SaveData.best_score
	record_label.text = "Record: %d" % SaveData.best_score
	if beat_record:
		_show_new_record_badge()
	else:
		_hide_new_record_badge()
	# The game-over panel carries its own score and record, so the in-run
	# HUD above it would just print both a second time.
	_set_hud_visible(false)
	game_over_screen.visible = true
	ads.run_finished()


func _set_hud_visible(on: bool) -> void:
	score_label.visible = on
	record_label.visible = on


func _show_new_record_badge() -> void:
	new_record_badge.scale = Vector2.ONE
	new_record_badge.visible = true

	if record_pulse != null and record_pulse.is_valid():
		record_pulse.kill()
	# Bound to the badge rather than to this node so it keeps its own
	# process mode — the UI layer runs through a pause, this script doesn't.
	record_pulse = new_record_badge.create_tween().set_loops()
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE * 1.16, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	record_pulse.tween_property(new_record_badge, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _hide_new_record_badge() -> void:
	new_record_badge.visible = false
	if record_pulse != null and record_pulse.is_valid():
		record_pulse.kill()
	record_pulse = null


# ------------------------------------------------------------------
# Screen flow
# ------------------------------------------------------------------

func _on_play_pressed() -> void:
	# Guards against a rapid double-tap firing this twice (e.g. the second
	# tap landing before the button visually/logically goes away) and
	# re-running the transition or reset mid-flight.
	if state != State.START:
		return
	if not SaveData.seen_tutorial:
		_begin_first_time_transition()
	else:
		_begin_playing()


func _begin_first_time_transition() -> void:
	state = State.STARTING
	SaveData.seen_tutorial = true
	SaveData.save_data()

	direction_hint.modulate.a = 0.0
	direction_hint.visible = hint_alpha > 0.0
	var tween := create_tween()
	tween.tween_property(start_screen, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(direction_hint, "modulate:a", hint_alpha, 1.0)
	tween.tween_callback(func():
		start_screen.visible = false
		start_screen.modulate.a = 1.0
		_begin_playing()
	)


func _begin_playing() -> void:
	state = State.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	pause_button.visible = true
	_set_hud_visible(true)
	# world_moving/bee.physics_enabled stay false here on the cold-start
	# path — spec 4.3: gravity only turns on at the real first flap
	# ("decolar" = "primeiro flap" = "início da partida", spec 4.3).


func _on_restart_pressed() -> void:
	# Guard against a rapid multi-tap re-entering this while a run is
	# already live (reported bug: mashing "play again" could occasionally
	# leave the bee looking dead right at the start of the new run) — only
	# a press from an actual game-over screen should ever reset anything.
	if state != State.GAMEOVER or restart_after_ad:
		return
	# Between runs is the one place an ad may appear, and only every few
	# runs (ads.gd). The new run then waits for the ad to close; it starts
	# with the bee on the ground either way, so nothing is lost to the ad.
	if ads.show_between_runs():
		restart_after_ad = true
		return
	_start_fresh_run()


func _on_ad_closed() -> void:
	music.stream_paused = false
	if restart_after_ad:
		restart_after_ad = false
		if state == State.GAMEOVER:
			_start_fresh_run()


func _start_fresh_run() -> void:
	# Every fresh run — first launch, replay after a game over, or restart
	# from the pause menu — starts the same way: bee grounded, waiting for
	# the real first flap.
	_reset_to_ground_scene()
	state = State.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	# The badge rides along with the hidden screen, but its loop would keep
	# ticking for the whole next run if it isn't stopped here.
	_hide_new_record_badge()
	pause_button.visible = true
	_set_hud_visible(true)


func _on_pause_pressed() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	pause_button.visible = false
	privacy_button.visible = ads.privacy_options_required()
	pause_screen.visible = true
	# Freezing the tree is what actually stops the run: the bee's physics,
	# the drifting clouds and gulls and their wing animations all advance
	# on their own, so gating this script alone would leave the world alive
	# behind the menu.
	get_tree().paused = true


func _on_resume_pressed() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	pause_screen.visible = false
	state = State.PLAYING
	pause_button.visible = true


func _on_pause_restart_pressed() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	pause_screen.visible = false
	_start_fresh_run()


func _on_music_toggle_pressed() -> void:
	SaveData.music_muted = not SaveData.music_muted
	SaveData.save_data()
	_apply_music_mute()


func _play_sfx(stream: AudioStream, volume_db: float, pitch := 1.0) -> void:
	for voice in sfx_pool:
		if voice.playing:
			continue
		voice.stream = stream
		voice.volume_db = volume_db
		voice.pitch_scale = pitch
		voice.play()
		return
	# Every voice busy: dropping this one is better than cutting off a
	# sound that's already audible.


func _apply_music_mute() -> void:
	music.volume_db = MUSIC_MUTED_DB if SaveData.music_muted else MUSIC_VOLUME_DB
	music_slash.visible = SaveData.music_muted
	music_note.modulate = Color(1, 1, 1, 0.4) if SaveData.music_muted else Color.WHITE


func _on_vibration_toggle_pressed() -> void:
	SaveData.vibration = not SaveData.vibration
	SaveData.save_data()
	_apply_vibration_setting()
	_vibrate(40)


func _apply_vibration_setting() -> void:
	vibrate_slash.visible = not SaveData.vibration
	vibrate_icon.modulate = Color.WHITE if SaveData.vibration else Color(1, 1, 1, 0.4)


# A short buzz for the moments that matter (death, a new record, a new
# bee); does nothing on devices without a vibrator.
func _vibrate(ms: int) -> void:
	if SaveData.vibration:
		Input.vibrate_handheld(ms)


func _update_score_label() -> void:
	score_label.text = "%d" % score


# ------------------------------------------------------------------
# Bee skins
# ------------------------------------------------------------------

func _bee_unlocked(id: String) -> bool:
	return SaveData.best_score >= BEE_SKINS[id]["score"] or SaveData.unlocked_bees.has(id)


# Called on every flower: a skin is won the moment the run reaches its
# score, not when the run ends, so dying right after still keeps it.
func _check_bee_unlocks() -> void:
	for id in BEE_ORDER:
		if score >= BEE_SKINS[id]["score"] and not _bee_unlocked(id):
			SaveData.unlocked_bees.append(id)
			SaveData.save_data()
			_refresh_bee_menu()
			_show_bee_notice(id)


func _current_bee_skin() -> String:
	var id: String = SaveData.selected_bee
	if not BEE_SKINS.has(id) or not _bee_unlocked(id):
		return "normal"
	return id


func _apply_bee_skin() -> void:
	var id := _current_bee_skin()
	var skin: Dictionary = BEE_SKINS[id]
	bee.apply_skin(skin["size"], skin["speed"])
	# the very first call comes from _ready, before the 3D view exists
	if view3d and applied_bee_skin != id:
		applied_bee_skin = id
		view3d.set_bee_skin(skin["model"], skin["size"], skin["glow"])
	# a bee waiting on the ground keeps its feet on the grass at its new size
	if state == State.START and not world_moving:
		bee.position.y = -bee.radius


func _show_bee_notice(id: String) -> void:
	_play_sfx(SFX_RECORD, SFX_RECORD_DB)
	_vibrate(120)
	bee_notice_icon.texture = load(_bee_icon_path(id))
	bee_notice_title.text = "%s unlocked!" % BEE_SKINS[id]["name"]
	bee_notice.visible = true
	bee_notice.modulate.a = 0.0
	if bee_notice.has_meta("tween") and bee_notice.get_meta("tween").is_valid():
		bee_notice.get_meta("tween").kill()
	# Bound to the notice itself so it keeps running if the run gets paused.
	var tw := bee_notice.create_tween()
	bee_notice.set_meta("tween", tw)
	tw.tween_property(bee_notice, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(bee_notice, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): bee_notice.visible = false)


func _on_bee_menu_pressed() -> void:
	if state != State.START and state != State.GAMEOVER:
		return
	_refresh_bee_menu()
	# The screen it opened from steps aside: its logo or score would
	# otherwise sit right behind the menu's title and cards.
	start_screen.visible = false
	game_over_screen.visible = false
	bee_menu.visible = true


func _on_bee_menu_closed() -> void:
	bee_menu.visible = false
	start_screen.visible = state == State.START
	game_over_screen.visible = state == State.GAMEOVER


func _on_bee_card_pressed(id: String) -> void:
	if not _bee_unlocked(id):
		return
	if SaveData.selected_bee != id:
		SaveData.selected_bee = id
		SaveData.save_data()
		_apply_bee_skin()
	_refresh_bee_menu()


func _refresh_bee_menu() -> void:
	var current := _current_bee_skin()
	for id in bee_cards:
		var card: Dictionary = bee_cards[id]
		var locked: bool = not _bee_unlocked(id)
		var selected: bool = id == current
		card["plate"].set_ink(GOLD if selected else Color(1, 1, 1, 0.45 if locked else 0.9))
		# a locked bee shows as a dark silhouette
		card["icon"].modulate = Color(0.08, 0.06, 0.14, 0.85) if locked else Color.WHITE
		var status: Label = card["status"]
		if locked:
			status.text = "Score %d" % BEE_SKINS[id]["score"]
		else:
			status.text = "Selected" if selected else "Tap to pick"
		status.add_theme_color_override("font_color", GOLD if selected else Color(1, 1, 1, 0.85))
	for icon in bee_button_icons:
		icon.texture = load(_bee_icon_path(current))


# ------------------------------------------------------------------
# Celestial bodies (moon/Jupiter/UFO) — static world-space objects,
# same as a cloud but without the drift: they spawn once near the top of
# the current view and just sit there, so the climb naturally scrolls
# them down and off the bottom of the screen.
# ------------------------------------------------------------------

# `kind` is the model view3d.gd draws for it: "moon", "jupiter" or "ufo".
func _spawn_celestial(kind: String, y_offset_above_view: float) -> void:
	if state != State.PLAYING:
		return
	var body := Node2D.new()
	body.set_meta("kind", kind)
	# Spawn ABOVE the current view (camera_y is the screen's top edge) so it
	# scrolls into sight as the bee keeps climbing, instead of popping into
	# the middle of whatever's already on screen.
	body.position = Vector2(80.0 + randf() * (SCREEN_W - 160.0), camera_y - y_offset_above_view)
	add_child(body)
	celestials.append(body)


func _on_moon_spawn_requested() -> void:
	_spawn_celestial("moon", 120.0)


func _on_jupiter_spawn_requested() -> void:
	_spawn_celestial("jupiter", 140.0)


func _on_ship_spawn_requested() -> void:
	_spawn_celestial("ufo", 100.0)


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return

	var pos: Vector2
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return

	var screen_width: float = get_viewport_rect().size.x
	var direction := -1 if pos.x < screen_width / 2.0 else 1

	if not world_moving:
		world_moving = true
		bee.physics_enabled = true
	bee.flap(direction)
	# Taps come fast and in bursts; an identical sample every time reads as
	# a stuck machine gun, so each one is detuned slightly.
	_play_sfx(SFX_FLAP, SFX_FLAP_DB, randf_range(0.92, 1.08))
	has_tapped_once = true


# ------------------------------------------------------------------
# UI construction (all procedural — see spec 3.2/4.10: real fonts/logo/
# bitmap labels arrive later, placeholder Label/Button nodes stand in).
# ------------------------------------------------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	# Pausing stops the whole scene tree, this layer included — without
	# opting out, the pause menu would freeze the instant it appeared and
	# none of its buttons would ever respond.
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	record_label = _make_label("Record: 0", 22, Color(1, 1, 1, 0.9))
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_label.position = Vector2(0, 22)
	record_label.size = Vector2(SCREEN_W, 26)
	ui_layer.add_child(record_label)

	score_label = _make_label("0", 64, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(0, 92)
	score_label.size = Vector2(SCREEN_W, 68)
	ui_layer.add_child(score_label)

	# A digit's glyph and its outline are rasterised the first time they are
	# drawn, at this size, which lands on whichever pickup first needs it.
	# Drawing all ten once at start-up, all but invisible, gets it done early.
	var digits := _make_label("0123456789", 64, Color.WHITE)
	digits.modulate.a = 0.01
	digits.position = score_label.position
	ui_layer.add_child(digits)
	get_tree().create_timer(1.0).timeout.connect(digits.queue_free)

	direction_hint = _build_direction_hint()
	ui_layer.add_child(direction_hint)

	pause_button = _make_icon_button(_build_pixel_icon(ICON_PAUSE, 3.0, Color.WHITE), 48.0)
	pause_button.position = Vector2(SCREEN_W - pause_button.size.x - 14, 18)
	pause_button.visible = false
	pause_button.pressed.connect(_on_pause_pressed)
	ui_layer.add_child(pause_button)

	start_screen = _build_start_screen()
	ui_layer.add_child(start_screen)

	pause_screen = _build_pause_screen()
	ui_layer.add_child(pause_screen)

	game_over_screen = _build_game_over_screen()
	ui_layer.add_child(game_over_screen)

	bee_notice = _build_bee_notice()
	ui_layer.add_child(bee_notice)

	# last, so it opens over the start and game-over screens
	bee_menu = _build_bee_menu()
	ui_layer.add_child(bee_menu)
	_refresh_bee_menu()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Tinted ink outline, same idea as the art's per-material outlines,
	# plus a soft drop so text still reads over busy scenery.
	label.add_theme_color_override("font_outline_color", UI_INK)
	label.add_theme_constant_override("outline_size", maxi(5, roundi(font_size / 4.5)))
	label.add_theme_color_override("font_shadow_color", Color(UI_INK, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _build_direction_hint() -> Control:
	var hint := Control.new()
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# dashed centerline
	var dash_h := 14.0
	var gap_h := 10.0
	var y := 0.0
	while y < screen_h:
		var dash := ColorRect.new()
		dash.color = Color(1, 1, 1, 0.55)
		dash.position = Vector2(SCREEN_W / 2.0 - 2, y)
		dash.size = Vector2(4, dash_h)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_child(dash)
		y += dash_h + gap_h

	_add_hint_side(hint, SCREEN_W * 0.25, -1, "LEFT")
	_add_hint_side(hint, SCREEN_W * 0.75, 1, "RIGHT")

	return hint


func _add_hint_side(parent: Control, cx: float, dir: int, text: String) -> void:
	var mid_y := screen_h * 0.5

	var rows := []
	for row in ICON_ARROW:
		rows.append(row if dir > 0 else (row as String).reverse())
	var arrow := _build_pixel_icon(rows, 4.0, Color(1, 1, 1, 0.9))
	arrow.position = Vector2(cx, mid_y) - arrow.size / 2.0
	parent.add_child(arrow)

	var label := _make_label(text, 20, Color(1, 1, 1, 0.9))
	label.position = Vector2(cx - 60, mid_y + 30)
	label.size = Vector2(120, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _build_start_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var logo := VoxelLogo.new()
	logo.setup(344.0)
	# Anchored to the bottom like the world behind it (the ground sits flush
	# with the bottom edge, rows stack up from there), so on taller phones
	# the logo keeps the same slot between rows instead of a row running
	# straight through it. Floored so short screens don't push it under the
	# record label.
	logo.position = Vector2(
		(SCREEN_W - logo.size.x) / 2.0, maxf(140.0, screen_h - 660.0) - logo.size.y / 2.0)
	screen.add_child(logo)

	# The bee in use hovers between the two words, so the title shows the
	# skin that is about to fly.
	var logo_bee := _make_bee_icon(_current_bee_skin(), 74.0)
	bee_button_icons.append(logo_bee)
	var bee_home: Vector2 = logo.position + logo.gap_anchor - Vector2(37.0, 40.0)
	logo_bee.position = bee_home
	screen.add_child(logo_bee)
	var bob := logo_bee.create_tween().set_loops()
	bob.tween_property(logo_bee, "position:y", bee_home.y - 7.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(logo_bee, "position:y", bee_home.y, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	play_button = _make_block_button("green", Vector2(126, 84), 3)
	var play_icon := _build_pixel_icon(ICON_PLAY, 5.0, Color.WHITE)
	var play_face: Control = play_button.get_meta("content")
	play_icon.position = ((play_face.size - play_icon.size) / 2.0 + Vector2(2, 0)).floor()
	play_face.add_child(play_icon)
	# high enough to leave the bee waiting on the grass in view
	play_button.position = Vector2(SCREEN_W / 2.0 - play_button.size.x / 2.0, screen_h - 166)
	play_button.pressed.connect(_on_play_pressed)
	screen.add_child(play_button)
	# a slow breath, so the one thing to tap on this screen asks for it
	play_button.pivot_offset = play_button.size / 2.0
	var breath := play_button.create_tween().set_loops()
	breath.tween_property(play_button, "scale", Vector2.ONE * 1.06, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(play_button, "scale", Vector2.ONE, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(26, play_button.position.y + (play_button.size.y - bee_button.size.y) / 2.0)
	screen.add_child(bee_button)

	var trophy_button := _make_leaderboard_button()
	trophy_button.position = Vector2(SCREEN_W - 26 - trophy_button.size.x, bee_button.position.y)
	screen.add_child(trophy_button)

	return screen


# Opens the online leaderboard. Hidden while leaderboard.gd is switched off.
func _make_leaderboard_button() -> Button:
	var btn := _make_icon_button(_build_pixel_icon(ICON_TROPHY, 3.0, GOLD), 63.0)
	btn.visible = leaderboard.available
	btn.pressed.connect(func(): leaderboard.show())
	return btn


# Opens the bee menu; shows the bee currently in use. One sits on the start
# screen and one on the game-over screen, so a freshly unlocked bee can be
# picked without restarting the app.
func _make_bee_button() -> Button:
	var icon := _make_bee_icon(_current_bee_skin(), 50.0)
	bee_button_icons.append(icon)
	var btn := _make_icon_button(icon, 63.0)
	btn.pressed.connect(_on_bee_menu_pressed)
	return btn


# Rendered from the models by tools/godot/render_bee_icons.gd.
func _bee_icon_path(id: String) -> String:
	return "res://art/ui/bee_%s.png" % id


func _make_bee_icon(id: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(_bee_icon_path(id))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(side, side)
	return icon


func _build_bee_menu() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)

	var top := maxf(64.0, screen_h * 0.2 - 30.0)
	var title := _make_label("Choose your bee", 38, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top - 2)
	title.size = Vector2(SCREEN_W, 44)
	screen.add_child(title)

	# Three to a row; a last row that isn't full is centred, which leaves the
	# silver bee alone at the bottom like a trophy.
	const CARD := Vector2(114, 132)
	const GAP := 9.0
	const COLS := 3
	var row_count := ceili(BEE_ORDER.size() / float(COLS))
	for i in BEE_ORDER.size():
		var row := i / COLS
		var in_row := mini(COLS, BEE_ORDER.size() - row * COLS)
		var left := (SCREEN_W - (CARD.x * in_row + GAP * (in_row - 1))) / 2.0
		var card := _make_bee_card(BEE_ORDER[i], CARD)
		card.position = Vector2(left + (i % COLS) * (CARD.x + GAP), top + 54 + row * (CARD.y + GAP))
		screen.add_child(card)

	var back := _make_text_button("Back")
	back.position = Vector2(
		(SCREEN_W - back.size.x) / 2.0, top + 54 + row_count * (CARD.y + GAP) + 9)
	back.pressed.connect(_on_bee_menu_closed)
	screen.add_child(back)

	return screen


func _make_bee_card(id: String, card_size: Vector2) -> Button:
	var btn := _make_block_button("dark", card_size)
	btn.pressed.connect(_on_bee_card_pressed.bind(id))
	var face: Control = btn.get_meta("content")

	var icon := _make_bee_icon(id, 84.0)
	icon.position = Vector2((face.size.x - 84.0) / 2.0, 0)
	face.add_child(icon)

	var name_label := _make_label(BEE_SKINS[id]["name"], 20, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 76)
	name_label.size = Vector2(face.size.x, 22)
	face.add_child(name_label)

	var status := _make_label("", 16, Color(1, 1, 1, 0.85))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.position = Vector2(0, 98)
	status.size = Vector2(face.size.x, 20)
	face.add_child(status)

	bee_cards[id] = {"plate": btn.get_meta("plate"), "icon": icon, "status": status}
	return btn


# A banner for the moment a run wins a new bee (_check_bee_unlocks).
func _build_bee_notice() -> Control:
	var panel := VoxelPlate.new()
	panel.setup("dark", Vector2(300, 72), UI_CELL)
	panel.set_ink(GOLD)
	panel.position = Vector2((SCREEN_W - panel.size.x) / 2.0, 172)
	panel.visible = false

	bee_notice_icon = _make_bee_icon("normal", 60.0)
	bee_notice_icon.position = Vector2(8, 3)
	panel.add_child(bee_notice_icon)

	bee_notice_title = _make_label("", 26, GOLD)
	bee_notice_title.position = Vector2(74, 6)
	bee_notice_title.size = Vector2(220, 28)
	panel.add_child(bee_notice_title)

	var hint := _make_label("Pick it in the bee menu", 18, Color(1, 1, 1, 0.9))
	hint.position = Vector2(74, 35)
	hint.size = Vector2(220, 22)
	panel.add_child(hint)

	return panel


func _build_pause_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	# The game-over screen deliberately leaves the world undimmed (spec 4.7),
	# but pause is a different message: the run is suspended, not finished,
	# and the menu has to stay readable over whatever happened to be on
	# screen when the player tapped.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)

	var title := _make_label("Paused", 52, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, screen_h * 0.26)
	title.size = Vector2(SCREEN_W, 56)
	screen.add_child(title)

	var resume_button := _make_text_button("Resume", "green")
	resume_button.position = Vector2((SCREEN_W - resume_button.size.x) / 2.0, screen_h * 0.41)
	resume_button.pressed.connect(_on_resume_pressed)
	screen.add_child(resume_button)

	var pause_restart_button := _make_text_button("Restart")
	pause_restart_button.position = Vector2((SCREEN_W - pause_restart_button.size.x) / 2.0, screen_h * 0.41 + 86)
	pause_restart_button.pressed.connect(_on_pause_restart_pressed)
	screen.add_child(pause_restart_button)

	music_note = _build_pixel_icon(ICON_NOTE, 3.0, Color.WHITE)
	var music_button := _make_icon_button(music_note, 57.0)
	music_button.position = Vector2(
		SCREEN_W / 2.0 - music_button.size.x / 2.0, screen_h * 0.41 + 200)
	music_button.pressed.connect(_on_music_toggle_pressed)
	screen.add_child(music_button)

	music_slash = _build_pixel_icon(ICON_SLASH, 3.0, Color.WHITE)
	music_slash.position = music_note.position
	music_slash.visible = false
	music_note.get_parent().add_child(music_slash)

	vibrate_icon = _build_pixel_icon(ICON_VIBRATE, 3.0, Color.WHITE)
	var vibrate_button := _make_icon_button(vibrate_icon, 57.0)
	vibrate_button.pressed.connect(_on_vibration_toggle_pressed)
	screen.add_child(vibrate_button)
	vibrate_slash = _build_pixel_icon(ICON_SLASH, 3.0, Color.WHITE)
	vibrate_slash.position = vibrate_icon.position
	vibrate_icon.get_parent().add_child(vibrate_slash)
	_apply_vibration_setting()
	# the two toggles side by side under the buttons
	music_button.position.x = SCREEN_W / 2.0 - music_button.size.x - 9.0
	vibrate_button.position = Vector2(SCREEN_W / 2.0 + 9.0, music_button.position.y)

	# Only shown where privacy law requires a way back to the ad-consent
	# choices (see ads.gd); elsewhere there is nothing to choose.
	privacy_button = Button.new()
	privacy_button.text = "Ad privacy"
	privacy_button.flat = true
	privacy_button.focus_mode = Control.FOCUS_NONE
	privacy_button.add_theme_font_override("font", ui_font)
	privacy_button.add_theme_font_size_override("font_size", 22)
	privacy_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	privacy_button.size = Vector2(160, 36)
	privacy_button.position = Vector2((SCREEN_W - 160.0) / 2.0, music_button.position.y + 76)
	privacy_button.visible = false
	privacy_button.pressed.connect(func(): ads.show_privacy_options())
	_add_tap_sound(privacy_button)
	screen.add_child(privacy_button)

	return screen


func _build_pixel_icon(rows: Array, cell: float, color: Color) -> Control:
	# Horizontal runs of set pixels collapse into one rect each, so a glyph
	# costs a handful of nodes instead of one per pixel.
	# Drawn twice: an ink copy one cube lower first, as the glyph's shadow.
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols: int = (rows[0] as String).length()
	icon.size = Vector2(cols * cell, rows.size() * cell)
	for layer in [[Color(UI_INK, color.a), cell], [color, 0.0]]:
		for y in rows.size():
			var row: String = rows[y]
			var x := 0
			while x < cols:
				if row[x] != "X":
					x += 1
					continue
				var run := 1
				while x + run < cols and row[x + run] == "X":
					run += 1
				var block := ColorRect.new()
				block.color = layer[0]
				block.position = Vector2(x * cell, y * cell + layer[1])
				block.size = Vector2(run * cell, cell)
				block.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.add_child(block)
				x += run
	return icon


# A button that is one voxel_plate.gd block: tapping it sinks the block's
# face, and whatever was added to its "content" node (meta) rides down with
# it. The Button itself draws nothing.
func _make_block_button(palette: String, btn_size: Vector2, side_cells := 2) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = btn_size
	btn.size = btn_size
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())

	var plate := VoxelPlate.new()
	plate.setup(palette, btn_size, UI_CELL, side_cells)
	btn.add_child(plate)

	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.position = plate.face_rect().position
	content.size = plate.face_rect().size
	btn.add_child(content)

	btn.set_meta("plate", plate)
	btn.set_meta("content", content)
	btn.button_down.connect(func():
		plate.pressed = true
		content.position = plate.face_rect().position
	)
	btn.button_up.connect(func():
		plate.pressed = false
		content.position = plate.face_rect().position
	)
	_add_tap_sound(btn)
	return btn


func _make_icon_button(icon: Control, side: float) -> Button:
	var btn := _make_block_button("dark", Vector2(side, side))
	var face: Control = btn.get_meta("content")
	icon.position = ((face.size - icon.size) / 2.0).floor()
	face.add_child(icon)
	return btn


func _build_game_over_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false

	var top := screen_h * 0.3
	var title := _make_label("Game Over", 56, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, top)
	title.size = Vector2(SCREEN_W, 60)
	screen.add_child(title)

	# The run's score and the record side by side on one board.
	var board := VoxelPlate.new()
	board.setup("dark", Vector2(258, 114), UI_CELL)
	board.position = Vector2((SCREEN_W - board.size.x) / 2.0, top + 74)
	screen.add_child(board)
	var face := board.face_rect()
	var col_w := face.size.x / 2.0

	var divider := ColorRect.new()
	divider.color = VoxelPlate.PALETTES["dark"]["light"]
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.position = Vector2(face.position.x + col_w - UI_CELL / 2.0, face.position.y + 15)
	divider.size = Vector2(UI_CELL, face.size.y - 27)
	board.add_child(divider)

	var values := []
	for i in 2:
		var caption := _make_label(["Score", "Record"][i], 22, Color(1, 1, 1, 0.8))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = face.position + Vector2(col_w * i, 10)
		caption.size = Vector2(col_w, 26)
		board.add_child(caption)
		var value := _make_label("0", 50, Color.WHITE if i == 0 else GOLD)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.position = face.position + Vector2(col_w * i, 36)
		value.size = Vector2(col_w, 54)
		board.add_child(value)
		values.append(value)
	final_score_label = values[0]
	final_best_label = values[1]

	# Pinned over the board's top-right corner, on the record's side.
	new_record_badge = _make_label("NEW!", 28, GOLD)
	new_record_badge.size = Vector2(
		ui_font.get_string_size("NEW!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x, 32)
	new_record_badge.pivot_offset = new_record_badge.size / 2.0
	new_record_badge.position = Vector2(
		board.position.x + board.size.x - new_record_badge.size.x * 0.7, board.position.y - 18)
	new_record_badge.rotation = deg_to_rad(10.0)
	new_record_badge.visible = false
	screen.add_child(new_record_badge)

	restart_button = _make_text_button("Play Again", "green")
	restart_button.position = Vector2((SCREEN_W - restart_button.size.x) / 2.0, screen_h - 146)
	restart_button.pressed.connect(_on_restart_pressed)
	screen.add_child(restart_button)

	var bee_button := _make_bee_button()
	bee_button.position = Vector2(14, restart_button.position.y + 2)
	screen.add_child(bee_button)

	var trophy_button := _make_leaderboard_button()
	trophy_button.position = Vector2(SCREEN_W - 14 - trophy_button.size.x, bee_button.position.y)
	screen.add_child(trophy_button)

	return screen


func _add_tap_sound(btn: BaseButton) -> void:
	# Wired in the factories rather than at each call site, so every button
	# in the game clicks without anyone having to remember to ask for it.
	btn.pressed.connect(func(): _play_sfx(SFX_UI_TAP, SFX_UI_DB))


# Green for the action that starts or continues a run, honey for the rest.
func _make_text_button(text: String, palette := "honey") -> Button:
	var btn := _make_block_button(palette, Vector2(228, 66), 3)
	var face: Control = btn.get_meta("content")
	var label := _make_label(text, 34, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = face.size
	face.add_child(label)
	return btn
