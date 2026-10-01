extends Node3D

# The game drawn in real-time 3D. Gameplay is untouched — main.gd still
# simulates everything in its 400-px-wide 2D plane (physics, collisions,
# spawning, difficulty) — and this node mirrors that state every frame into
# a low-poly scene: same x/y on the plane z=0, plus real depth, light,
# shadow and a perspective camera (so far-away scenery gets its parallax
# for free instead of being faked). The 2D world is hidden; the 2D UI stays.
#
# Models: models/*.glb, built by tools/blender/make_lowpoly_models.py —
# being replaced one by one by voxel-art versions (make_voxel_*.py); `voxel`
# maps a model slot to its voxel file once that asset is approved.

const PX := 40.0                 # game px per 3D unit (the screen is 10 units wide)
const FOV := 50.0
# The bee models are built at their in-game size on the world's cube grid
# (make_voxel_bee.py), so they're drawn unscaled.
const BEE_SCALE := 1.0
const FLOWER_SCALE := 1.0        # voxel flowers are built at their in-game size
const CAM_PITCH := 7.0           # degrees, looking slightly down onto the play plane
# voxel hedge tiles (make_voxel_hedge.py): 24 cubes = 0.96 units wide
const HEDGE_VARIANTS := ["hedge_voxel_a", "hedge_voxel_b", "hedge_voxel_c"]
const HEDGE_TILE_W := 0.96
var voxel := {
	"bee": "bee_voxel",
	"flower_red": "flower_voxel_red",
	"flower_yellow": "flower_voxel_yellow",
	"flower_blue": "flower_voxel_blue",
	"gull": "gull_voxel",
	"ground": "ground_voxel",
	"moon": "moon_voxel",
	"jupiter": "jupiter_voxel",
	"ufo": "ufo_voxel",
	"backdrop_hills": "backdrop_voxel_hills",
	"backdrop_city": "backdrop_voxel_city",
	"sun": "sun_voxel",
}
const VOX := 0.04                # the world's cube size (tools/blender/voxel_kit.py VOX)
const RECORD_WORD := "RECORD"
# 5x7 cube letters for the record line
const GLYPHS := {
	"R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
	"E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
	"C": [".XXXX", "X....", "X....", "X....", "X....", "X....", ".XXXX"],
	"O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"D": ["XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."],
}
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
# hedge tile models and the width (3D units) of one tile
var hedge_models: Array = HEDGE_VARIANTS
var hedge_seg_w := HEDGE_TILE_W
var flower_scale := FLOWER_SCALE
var bee3d: Node3D
var bee_scale := BEE_SCALE
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
	for f in ["bee", "hedge_voxel_a", "hedge_voxel_b", "hedge_voxel_c", "flower_red", "flower_yellow", "flower_blue",
			"cloud_voxel_a", "cloud_voxel_b", "cloud_voxel_c", "gull", "moon", "jupiter", "ufo", "ground",
			"tree_voxel_round_a", "tree_voxel_round_b", "tree_voxel_round_c",
			"tree_voxel_pine_a", "tree_voxel_pine_b", "tree_voxel_pine_c",
			"backdrop_hills", "backdrop_city", "sun"]:
		models[f] = load("res://models/%s.glb" % voxel.get(f, f))

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
	if voxel.has(model) or model.contains("voxel"):
		_use_vertex_colours(n)
	return n


# Voxel models carry their colour per cube as vertex colours; Godot's glTF
# import leaves vertex_color_use_as_albedo off, which renders them white.
func _use_vertex_colours(n: Node) -> void:
	for m: MeshInstance3D in _meshes(n):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true


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
			# Voxel trees come in three sizes per kind and are never scaled or
			# turned: either would break the shared cube grid, and their backs
			# aren't modelled.
			var kind := "round" if rng.randf() < 0.6 else "pine"
			var t := spawn("tree_voxel_%s_%s" % [kind, ["a", "b", "c"][rng.randi() % 3]], scenery)
			t.position = Vector3(snappedf(x, 0.04), 0, snappedf(rng.randf_range(-2.4, -1.4), 0.04))
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
	# A glowing sun hung behind everything: the voxel sun's flat disc, with a
	# material made here rather than the model's own, so it can fade out as
	# the sun sets (its colours come from the model's vertex colours).
	var sun := MeshInstance3D.new()
	var sun_model: Node3D = models["sun"].instantiate()
	sun.mesh = (_meshes(sun_model)[0] as MeshInstance3D).mesh
	sun_model.free()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
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
		var n := maxi(1, int(ceil(width_u / hedge_seg_w)))
		var seg_w := width_u / n
		for i in n:
			var h := spawn(hedge_models[randi() % hedge_models.size()], row)
			h.scale = Vector3(seg_w / hedge_seg_w, 1, 1)
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
	n.scale = Vector3.ONE * flower_scale
	return n


# A flower's pickup burst: cubes of two exact grid sizes (two cubes across
# and one), never scaled in between, the small ones in a lighter tint.
func _burst(at: Vector3, color: Color) -> void:
	for spec in [[10, 0.08, color], [8, 0.04, color.lightened(0.45)]]:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = spec[0]
		p.lifetime = 0.55
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0, -4, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * spec[1]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[2]
		mat.emission_enabled = true
		mat.emission = spec[2]
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
		var m := _mirror(c, _build_cloud)
		m.position = to3(c.position, -2.2)
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


# One voxel model per cloud size (large / medium / small), used unscaled:
# stretching a single model would give clouds cubes of different sizes.
func _build_cloud(c) -> Node3D:
	var span: float = c.scale.x * 538.0     # cloud.gd CONTENT_W: its width in game px
	var n := spawn("cloud_voxel_a" if span >= 65.0 else ("cloud_voxel_b" if span >= 55.0 else "cloud_voxel_c"))
	# The clouds are see-through. Writing depth as they draw (their cubes are
	# stored nearest-first) keeps a cloud's own inner steps from blending in
	# behind its front as streaks.
	for m: MeshInstance3D in _meshes(n):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return n


# Bodies in the night sky shine by themselves instead of being lit by the
# scene: under the dim night light a turning voxel ball goes grey and the
# steps on its dark side show up as thin black streaks.
func _glowing(n: Node3D) -> Node3D:
	for m: MeshInstance3D in _meshes(n):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return n


func _build_celestial(b) -> Node3D:
	var path: String = b.texture.resource_path
	if "moon" in path:
		return _glowing(spawn("moon"))
	if "jupiter" in path:
		return _glowing(spawn("jupiter"))     # modelled at its in-game size
	return _glowing(spawn("ufo"))             # modelled at its in-game size


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


# The record line in voxels: dashes six cubes long and four apart, and the
# word RECORD spelled out in cubes with a dark drop shadow one cube down and
# to the right. Like the 2D line it mirrors, the word sits on the side away
# from the record flower.
func _build_record_line() -> Node3D:
	var line := Node3D.new()
	add_child(line)
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.84, 0.3)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = main.UI_INK
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(6 * VOX, VOX, VOX)
	var x := -5.0
	while x < 5.0:
		var dash := MeshInstance3D.new()
		dash.mesh = dash_mesh
		dash.material_override = gold
		dash.position = Vector3(x + 3 * VOX, 0, 0)
		line.add_child(dash)
		x += 10 * VOX

	var cells: Array[Vector3] = []
	for i in RECORD_WORD.length():
		var rows: Array = GLYPHS[RECORD_WORD[i]]
		for r in rows.size():
			for c in (rows[r] as String).length():
				if rows[r][c] == "X":
					cells.append(Vector3((i * 6 + c + 0.5) * VOX, (rows.size() - r - 0.5) * VOX, 0))
	var word_w := (RECORD_WORD.length() * 6 - 1) * VOX
	# the 2D line's own label is its last child, already placed on the free side
	var label_2d: Control = main.record_line.get_child(main.record_line.get_child_count() - 1)
	var on_left: bool = label_2d.position.x < main.SCREEN_W / 2.0
	var origin := Vector3(-4.85 if on_left else 4.85 - word_w, 3 * VOX, 0)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * VOX
	for layer in [[ink, Vector3(VOX, -VOX, -VOX)], [gold, Vector3.ZERO]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cube
		mm.instance_count = cells.size()
		for k in cells.size():
			mm.set_instance_transform(k, Transform3D(Basis(), origin + cells[k] + layer[1]))
		var word := MultiMeshInstance3D.new()
		word.multimesh = mm
		word.material_override = layer[0]
		line.add_child(word)
	return line


# ------------------------------------------------------------------ bee
# Swaps the bee for another skin (main.gd BEE_SKINS): `model` is its slot in
# `models`, `size` scales it against the normal bee, `glow` draws it unshaded.
func set_bee_skin(model: String, size: float, glow: bool) -> void:
	if bee3d:
		bee3d.queue_free()
	live_eyes.clear()
	bee_scale = BEE_SCALE * size
	# skins other than the one in use are only loaded when picked
	if not models.has(model):
		models[model] = load("res://models/%s.glb" % model)
	_build_bee(model)
	if glow:
		_glowing(bee3d)


func _build_bee(model := "bee") -> void:
	bee3d = spawn(model)
	bee3d.scale = Vector3.ONE * bee_scale
	wing_l = bee3d.find_child("WingPivotL", true, false)
	wing_r = bee3d.find_child("WingPivotR", true, false)
	dead_eyes = bee3d.find_child("DeadEyes", true, false)
	var eyes: Node3D = bee3d.find_child("LiveEyes", true, false)
	if eyes:
		live_eyes.append(eyes)
	else:
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
		bee3d.scale = Vector3(bee_scale * (1.0 + squash), bee_scale * (1.0 - squash), bee_scale)
	else:
		bee3d.scale = Vector3.ONE * bee_scale
	wing_l.rotation.x = wing
	wing_r.rotation.x = -wing


# Stars are cubes too. They sit 180 units behind the camera, where a cube of
# STAR_VOX lands on screen at the size of one world cube; every star is
# exactly one or two of those across, and a few bigger ones are crosses.
func _build_stars() -> void:
	const STAR_VOX := 0.34
	const SQUARES := 140
	const CROSSES := 12
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * STAR_VOX
	mm.mesh = cube
	mm.instance_count = SQUARES + CROSSES * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in SQUARES:
		var side := 2.0 if rng.randf_range(0.5, 1.4) > 1.08 else 1.0
		var t := Transform3D(Basis().scaled(Vector3.ONE * side),
			Vector3(rng.randf_range(-60, 60), rng.randf_range(-90, 90), 0))
		mm.set_instance_transform(i, t)
	for i in CROSSES:
		var at := Vector3(rng.randf_range(-60, 60), rng.randf_range(-90, 90), 0).snappedf(STAR_VOX)
		mm.set_instance_transform(SQUARES + i * 2, Transform3D(Basis().scaled(Vector3(3, 1, 1)), at))
		mm.set_instance_transform(SQUARES + i * 2 + 1, Transform3D(Basis().scaled(Vector3(1, 3, 1)), at))
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.albedo_color = Color(1, 1, 0.95, 0)
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.material_override = star_mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)
