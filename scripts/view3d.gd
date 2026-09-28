extends Node3D

# The game drawn in real-time 3D. Gameplay is untouched — main.gd still
# simulates everything in its 400-px-wide 2D plane (physics, collisions,
# spawning, difficulty) — and this node mirrors that state every frame into
# a low-poly scene: same x/y on the plane z=0, plus real depth, light,
# shadow and a perspective camera (so far-away scenery gets its parallax
# for free instead of being faked). The 2D world is hidden; the 2D UI stays.
#
# Models: models/*.glb, built by tools/blender/make_lowpoly_models.py.

const PX := 40.0                 # game px per 3D unit (the screen is 10 units wide)
const FOV := 50.0
const BEE_SCALE := 0.8
const FLOWER_SCALE := 1.25
const CAM_PITCH := 7.0           # degrees, looking slightly down onto the play plane
const HEDGE_VARIANTS := ["hedge_a", "hedge_b", "hedge_c"]
const BACKDROP_DEPTH := 95.0     # far enough to scroll at ~1/5 of the climb rate
const SUN_Y := 26.0

const SKY_DAY := [Color(0.30, 0.60, 0.95), Color(0.72, 0.88, 1.0)]
const SKY_DUSK := [Color(0.30, 0.26, 0.60), Color(0.98, 0.58, 0.46)]
const SKY_NIGHT := [Color(0.04, 0.05, 0.16), Color(0.14, 0.14, 0.36)]

var main: Node2D
var models := {}
var cam: Camera3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun_light: DirectionalLight3D
var stars: MultiMeshInstance3D
var star_mat: StandardMaterial3D

var mirrors := {}                # 2D node instance id -> Node3D
var bee3d: Node3D
var wing_l: Node3D
var wing_r: Node3D
var dead_eyes: Node3D
var live_eyes: Array[Node3D] = []
var bee_yaw := 0.0
var bee_roll_x := 0.0
var idle_time := 0.0

var sun_disc: MeshInstance3D
var sun_mat: StandardMaterial3D
var ground_for: Object           # the ground Sprite2D this scenery was built for
var scenery: Node3D
var record3d: Node3D
var record_for: Object


func setup(p_main: Node2D) -> void:
	main = p_main
	for f in ["bee", "hedge_a", "hedge_b", "hedge_c", "flower_red", "flower_yellow", "flower_blue",
			"cloud_a", "cloud_b", "gull", "moon", "jupiter", "ufo", "ground", "tree_round", "tree_pine",
			"backdrop_hills", "backdrop_city"]:
		models[f] = load("res://models/%s.glb" % f)

	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	# depth haze: the far backdrop fades into the horizon colour, the
	# gameplay plane (~24 units away) stays crisp
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 220.0
	env.fog_density = 0.55
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-42, -55, 0)   # from the upper left, raking across the scene
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	# No shadows: everything sits on one plane with only sky behind it, so
	# they'd barely show, and a shadow pass roughly doubles the draw cost on
	# a phone.
	sun_light.shadow_enabled = false
	sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun_light)

	_build_bee()
	_build_stars()


# ------------------------------------------------------------------ helpers
func _cam_dist() -> float:
	return (main.screen_h / PX / 2.0) / tan(deg_to_rad(FOV / 2.0))



func to3(p: Vector2, z := 0.0) -> Vector3:
	return Vector3((p.x - main.SCREEN_W / 2.0) / PX, -p.y / PX, z)


func spawn(model: String, parent: Node = self) -> Node3D:
	var n: Node3D = models[model].instantiate()
	parent.add_child(n)
	return n


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


# ------------------------------------------------------------------ per-frame sync
func _process(delta: float) -> void:
	if main == null:
		return
	_sync_camera()
	_sync_sky()
	_sync_scenery()
	_sync_obstacles()
	_sync_flowers(delta)
	_sync_decor(delta)
	_sync_record_line()
	_sync_bee(delta)


func _sync_camera() -> void:
	var dist := _cam_dist()
	var c: Vector2 = main.camera.position        # top-left of the 2D view, shake included
	var centre := Vector3(c.x / PX, -(c.y + main.screen_h / 2.0) / PX, 0)
	# Tilted slightly down so the tops of the hedges show. Everything that
	# collides lives on the same plane, so the tilt can't make a hit look
	# like a miss; the plane just reads as a slightly receding stage.
	var pitch := deg_to_rad(CAM_PITCH)
	cam.rotation.x = -pitch
	cam.position = centre + Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	# stars ride with the camera: an endless sky, however high the climb
	stars.position = cam.position + Vector3(0, 0, -180)


func _sync_sky() -> void:
	var d: float = main.sky.darkness(main.elapsed)
	var top: Color
	var horizon: Color
	if d < 0.5:
		top = SKY_DAY[0].lerp(SKY_DUSK[0], d * 2.0)
		horizon = SKY_DAY[1].lerp(SKY_DUSK[1], d * 2.0)
	else:
		top = SKY_DUSK[0].lerp(SKY_NIGHT[0], (d - 0.5) * 2.0)
		horizon = SKY_DUSK[1].lerp(SKY_NIGHT[1], (d - 0.5) * 2.0)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	# a level camera sees the sky's lower hemisphere too — keep it the
	# horizon colour, and haze distant scenery into that same colour
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon
	env.fog_light_color = horizon
	# night stays bright enough to read the flowers — they're the goal
	sun_light.light_energy = lerpf(1.25, 0.6, d)
	sun_light.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.66, 0.74, 1.0), d)
	env.ambient_light_energy = lerpf(0.9, 0.8, d)
	# the sun sets: sinks and fades out as the sky turns
	if sun_disc:
		sun_disc.position.y = SUN_Y - d * 70.0
		sun_mat.albedo_color.a = clampf(1.0 - d * 2.2, 0.0, 1.0)
		sun_disc.visible = sun_mat.albedo_color.a > 0.01
	star_mat.albedo_color.a = clampf((d - 0.45) * 2.0, 0.0, 1.0)


# The ground, trees and far backdrop are rebuilt whenever main.gd builds a
# fresh start scene (every run), since the backdrop variant is re-rolled.
func _sync_scenery() -> void:
	if main.ground_sprite == ground_for:
		return
	ground_for = main.ground_sprite
	if scenery:
		scenery.queue_free()
	scenery = Node3D.new()
	add_child(scenery)
	if ground_for == null:
		return
	var ground := spawn("ground", scenery)
	ground.position = Vector3(0, 0, 0)          # grass top at world y=0, where the bee stands
	var rng := RandomNumberGenerator.new()
	rng.seed = main.rows_spawned * 7919 + int(main.last_gap_x * 13.0)
	if main.trees_sprite:
		var x := -8.0
		while x < 8.0:
			var t := spawn("tree_round" if rng.randf() < 0.6 else "tree_pine", scenery)
			var s := rng.randf_range(0.85, 1.25)
			t.scale = Vector3.ONE * s
			t.position = Vector3(x, 0, rng.randf_range(-2.4, -1.4))
			t.rotation.y = rng.randf_range(0, TAU)
			x += rng.randf_range(0.9, 1.5)
	var hills: bool = main.sky.mountain_has_trees
	var back := spawn("backdrop_hills" if hills else "backdrop_city", scenery)
	# Sink the backdrop so, from the cold-start camera, its foot lines up
	# just above the near grass: seen through a level perspective camera, a
	# point at depth d appears pulled towards the view centre by D/(D+d).
	var dist := _cam_dist()
	var cam_y: float = -(main.camera_y + main.screen_h / 2.0) / PX + sin(deg_to_rad(CAM_PITCH)) * dist
	var foot_y: float = cam_y + (0.35 - cam_y) * (dist + BACKDROP_DEPTH) / dist
	back.position = Vector3(0, foot_y + 1.5, -BACKDROP_DEPTH)
	# A tall slab under the backdrop: with a level camera, anything below
	# the backdrop's own foot would otherwise show bare sky between it and
	# the near ground. This way the whole horizon sinks away as one piece
	# while the bee climbs, and only sky is left above it.
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160, 90, 2)
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.40, 0.70, 0.40) if hills else Color(0.46, 0.72, 0.46)
	base.material_override = bmat
	base.position = Vector3(0, foot_y - 45.0 + 0.5, -BACKDROP_DEPTH + 4.0)
	scenery.add_child(base)
	# a glowing sun hung behind everything
	var sun := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 7.0
	sm.height = 14.0
	sm.radial_segments = 20
	sm.rings = 10
	sun.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.88, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.35)
	mat.emission_energy_multiplier = 1.6
	mat.disable_fog = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sun.material_override = mat
	sun.position = Vector3(14, SUN_Y, -BACKDROP_DEPTH - 40)
	sun.name = "Sun"
	scenery.add_child(sun)
	sun_disc = sun
	sun_mat = mat


func _mirror(node: Object, build: Callable) -> Node3D:
	var id := node.get_instance_id()
	if not mirrors.has(id):
		mirrors[id] = build.call(node)
	return mirrors[id]


func _prune(alive: Dictionary) -> void:
	for id in mirrors.keys():
		if not alive.has(id):
			var n: Node3D = mirrors[id]
			mirrors.erase(id)
			n.queue_free()


func _sync_obstacles() -> void:
	var alive := {}
	for o in main.obstacles:
		if not is_instance_valid(o):
			continue
		alive[o.get_instance_id()] = true
		_mirror(o, _build_hedge_row)
	for f in main.flowers:
		if is_instance_valid(f):
			alive[f.get_instance_id()] = true
	for group in [main.clouds, main.seagulls, main.celestials]:
		for n in group:
			if is_instance_valid(n):
				alive[n.get_instance_id()] = true
	# collected flowers leave main.flowers but live on for their burst
	for id in mirrors.keys():
		var n = instance_from_id(id)
		if n != null and is_instance_valid(n) and n is Area2D:
			alive[id] = true
	_prune(alive)


func _build_hedge_row(o) -> Node3D:
	var row := Node3D.new()
	add_child(row)
	var band_mid: float = o.position.y + 11.0     # obstacle.gd THICK / 2
	row.position = to3(Vector2(main.SCREEN_W / 2.0, band_mid))
	var gap_left: float = o.gap_x - o.gap_width / 2.0
	var gap_right: float = o.gap_x + o.gap_width / 2.0
	# bars run well past the screen edges: the tilted camera shows a little
	# more of the plane's width near the top of the screen
	for bar in [[-80.0, gap_left], [gap_right, main.SCREEN_W + 80.0]]:
		var x1: float = bar[0]
		var x2: float = bar[1]
		if x2 <= x1 + 1.0:
			continue
		var width_u: float = (x2 - x1) / PX
		var n := maxi(1, int(ceil(width_u)))
		var seg_w := width_u / n
		for i in n:
			var h := spawn(HEDGE_VARIANTS[randi() % HEDGE_VARIANTS.size()], row)
			h.scale = Vector3(seg_w, 1, 1)
			h.position = Vector3((x1 - main.SCREEN_W / 2.0) / PX + i * seg_w, 0, 0)
	return row


func _sync_flowers(delta: float) -> void:
	for f in main.flowers:
		if not is_instance_valid(f):
			continue
		var m := _mirror(f, _build_flower)
		m.position = to3(f.position, 0.1)
		# a gentle sway rather than a full spin, which turned them edge-on
		m.rotation.y = sin(idle_time * 1.8 + f.sway_phase) * 0.55
	# collected: the 2D sprite is hidden while its burst plays
	for id in mirrors.keys():
		var n = instance_from_id(id)
		if n is Area2D and is_instance_valid(n) and not n.sprite.visible:
			var m: Node3D = mirrors[id]
			if m.visible:
				m.visible = false
				_burst(m.position, n.burst_color)


func _build_flower(f) -> Node3D:
	var path: String = f.sprite.texture.resource_path
	var model := "flower_red"
	if "yellow" in path:
		model = "flower_yellow"
	elif "blue" in path:
		model = "flower_blue"
	var n := spawn(model)
	n.scale = Vector3.ONE * FLOWER_SCALE
	return n


func _burst(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -4, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mesh.material = mat
	p.mesh = mesh
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _sync_decor(delta: float) -> void:
	idle_time += delta
	for c in main.clouds:
		if not is_instance_valid(c):
			continue
		var m := _mirror(c, func(n): return spawn("cloud_a" if n.get_instance_id() % 2 == 0 else "cloud_b"))
		m.position = to3(c.position, -2.2)
		m.scale = Vector3.ONE * (c.scale.x * 538.0 / 80.0)
	for g in main.seagulls:
		if not is_instance_valid(g):
			continue
		var m := _mirror(g, func(n): return spawn("gull"))
		m.position = to3(g.position, -1.2)
		m.rotation.y = PI if g.flip_h else 0.0
		var a := sin(idle_time * 9.0 + g.get_instance_id() % 7) * 0.9
		for side in ["L", "R"]:
			var w: Node3D = m.find_child("WingPivot" + side, true, false)
			if w:
				w.rotation.x = a * (1.0 if side == "L" else -1.0)
	for b in main.celestials:
		if not is_instance_valid(b):
			continue
		var m := _mirror(b, _build_celestial)
		m.position = to3(b.position, -6.0)
		m.rotation.y += delta * 0.3


func _build_celestial(b) -> Node3D:
	var path: String = b.texture.resource_path
	if "moon" in path:
		return spawn("moon")
	if "jupiter" in path:
		var j := spawn("jupiter")
		j.scale = Vector3.ONE * 1.25
		return j
	var u := spawn("ufo")
	u.scale = Vector3.ONE * 0.7
	return u


func _sync_record_line() -> void:
	var rl = main.record_line
	if rl != record_for:
		if record3d:
			var old := record3d
			var tw := create_tween()
			tw.tween_property(old, "scale", Vector3(1.0, 3.0, 1.0), 0.1)
			tw.tween_property(old, "scale", Vector3(1.0, 0.01, 1.0), 0.35)
			tw.tween_callback(old.queue_free)
			record3d = null
		record_for = rl
		if rl != null:
			record3d = _build_record_line()
	if record3d and is_instance_valid(rl):
		record3d.position = to3(Vector2(main.SCREEN_W / 2.0, rl.position.y), 0.45)


func _build_record_line() -> Node3D:
	var line := Node3D.new()
	add_child(line)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.84, 0.3)
	var x := -5.0
	while x < 5.0:
		var dash := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.26, 0.05, 0.05)
		dash.mesh = bm
		dash.material_override = mat
		dash.position = Vector3(x + 0.13, 0, 0)
		line.add_child(dash)
		x += 0.4
	var label := Label3D.new()
	label.text = "RECORD"
	label.font = main.ui_font
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.84, 0.3)
	label.outline_modulate = main.UI_INK
	label.outline_size = 16
	label.position = Vector3(-4.2, 0.22, 0)
	line.add_child(label)
	return line


# ------------------------------------------------------------------ bee
func _build_bee() -> void:
	bee3d = spawn("bee")
	bee3d.scale = Vector3.ONE * BEE_SCALE
	wing_l = bee3d.find_child("WingPivotL", true, false)
	wing_r = bee3d.find_child("WingPivotR", true, false)
	dead_eyes = bee3d.find_child("DeadEyes", true, false)
	for n in bee3d.find_children("Eye*", "", true, false):
		live_eyes.append(n)
	for n in bee3d.find_children("Shine*", "", true, false):
		live_eyes.append(n)


func _sync_bee(delta: float) -> void:
	var b = main.bee
	bee3d.position = to3(b.position, 0.15)
	var dead: bool = b.sprite.animation == "dead"
	dead_eyes.visible = dead
	for e in live_eyes:
		e.visible = not dead

	# turn to face the way the last tap sent it (a real turn, not a flip)
	var target_yaw := 0.0 if b.facing > 0 else PI
	bee_yaw = lerp_angle(bee_yaw, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	# roll belly-up on death
	bee_roll_x = lerpf(bee_roll_x, PI if dead else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var lean: float = -b.sprite.rotation * b.facing
	bee3d.rotation = Vector3(bee_roll_x, bee_yaw, lean)

	# wingbeat: the 2D flap animation (hidden) is the clock — one full
	# down-and-up stroke per tap, with a soft hover flutter in between
	var wing := 0.25 + sin(idle_time * 7.0) * 0.12
	if dead:
		wing = 1.6
	elif b.sprite.animation == "flap" and b.sprite.is_playing():
		var frames: int = b.sprite.sprite_frames.get_frame_count("flap")
		var t: float = (b.sprite.frame + b.sprite.frame_progress) / frames
		wing = 0.25 + sin(t * PI) * 1.55
		var squash := sin(t * PI) * 0.08
		bee3d.scale = Vector3(BEE_SCALE * (1.0 + squash), BEE_SCALE * (1.0 - squash), BEE_SCALE)
	else:
		bee3d.scale = Vector3.ONE * BEE_SCALE
	wing_l.rotation.x = wing
	wing_r.rotation.x = -wing


func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 4
	sm.rings = 2
	mm.mesh = sm
	mm.instance_count = 140
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var t := Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.4)),
			Vector3(rng.randf_range(-60, 60), rng.randf_range(-90, 90), 0))
		mm.set_instance_transform(i, t)
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.albedo_color = Color(1, 1, 0.95, 0)
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.material_override = star_mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)
