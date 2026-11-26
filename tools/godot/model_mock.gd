extends SceneTree

# Bee Bee "game view" mock: draws a scene of hedges, flowers, the bee, clouds,
# a gull, the start scenery or the night sky exactly the way
# scripts/view3d.gd draws the game (camera, sky, fog, sun, ambient, tone
# mapping, glow, night gain), with GLB models loaded at run time from
# --models (default: the project's models/ folder; no import needed; a model
# missing from --models comes from that folder), so model sets and lighting
# can be compared.
#
#   APPDATA=<scratch dir> timeout 900 "$G" --path "$P" --audio-driver Dummy \
#     --script tools/godot/model_mock.gd -- --out=DIR [--models=DIR] \
#     [--scene=play|title_hills|title_city|night_sky] [--light=new|old] [--hedge=new|old] \
#     [--tod=day,dusk,night] [--w=1080 --h=2400] [--msaa=2] [--lods=1] [--zoom=1]
#
# Run WITHOUT --headless. Writes <scene>_<tod>.png per time of day (play:
# day, dusk, night; the titles: day; night_sky: night) and, for play,
# play_zoom_day.png and play_zoom_night.png: two panels at the pixel density
# of a camera with a third of the FOV, seen from the game camera's own
# position (same perspective as in the game), top aimed at the second
# hedge's gap, bottom at the bee. Prints the triangle count of every model.
#
# --light=new is the art audit's renderer change (constants NEW_* below, to
# be copied into view3d.gd); --light=old is view3d.gd as it is today.
# --hedge=new lays whole, unstretched tiles outward from the gap: an end cap
# at each gap when the model set has hedge_voxel_cap_l.glb and
# hedge_voxel_cap_r.glb (cap_l's origin is its gap-side edge, the right end
# of the left bar, and it extends to -x; cap_r's origin is the left end of
# the right bar and it extends to +x; the tiles butt against the far side of
# the cap's bounding box, snapped to the cube grid), then tiles until past
# the bar's end 80 px beyond the screen edge. --hedge=old stretches the
# tiles to fill each bar, as view3d.gd does today.
#
# Extra scenes for checking the mock against the real game:
# --scene=qa_play_day|qa_night|qa_title_city|qa_title_hills draws the exact
# state tools/godot/qa_shots.gd photographs (dumped by
# a layout dump from outside the project, via --layout);
# --scene=calib draws flat swatches of known colours on the play plane and
# prints what their front and top faces come out as on screen.
# --tune=key:0.65:0.36,amb:0.37:0.31,haze:0.3:0.6,refl:0,glow:1.2,gain:1.7,hgain:1.3
# overrides any of the NEW_* numbers below ([day, night] pairs), for tuning.

const QA_LAYOUTS := "res://tools/godot/qa_layouts.json"
const PX := 40.0
const FOV := 50.0
const CAM_PITCH := 7.0
const SCREEN_W := 400.0
const VOX := 0.04
const HEDGE_VARIANTS := ["hedge_voxel_a", "hedge_voxel_b", "hedge_voxel_c"]
const HEDGE_TILE_W := 0.96
const SKY_DAY := [Color(0.10, 0.36, 0.74), Color(0.27, 0.56, 0.86)]
const SKY_DUSK := [Color(0.30, 0.26, 0.60), Color(0.98, 0.58, 0.46)]
const SKY_NIGHT := [Color(0.04, 0.05, 0.16), Color(0.14, 0.14, 0.36)]
const STAR_SPAN := 180.0
const GULL_DEPTH := -7.0
const GULL_HAZE := 0.5
const CITY_HAZE := 0.16
const CELESTIAL_DEPTH := -6.0
const BACKDROP_DEPTH := 95.0
const SUN_HEIGHT := 4.7
const GROUND_DEPTH := 19.9       # main.gd: the cold-start view reaches this far under the grass

# ------------------------------------------------------------------ lighting
# Today (view3d.gd setup/_sync_sky): key light from the upper left, raking
# across the scene; the sky's own colours as ambient. Front faces got N.L
# 0.43 and most of their light from the cyan sky, which greyed and tinted
# them (the bee's yellow 1.0,0.74,0.10 showed as 0.89,0.78,0.24).
const OLD_KEY_ROT := Vector3(-42, -55, 0)
const OLD_KEY_ENERGY := [1.25, 0.6]           # [day, night], lerped by darkness
const OLD_AMBIENT_ENERGY := [0.9, 0.8]        # AMBIENT_SOURCE_SKY
const OLD_NIGHT_GAIN := 1.7                   # flowers and bee

# New (art audit, renderer 1, 2, 3 and 10), to be copied into view3d.gd.
# The sky, fog and tone mapping (FILMIC) are untouched, so the sky looks
# exactly as today. Tuned with --scene=calib so that a vertex colour shows
# close to its authored value on a front face by day (sRGB, authored -> on
# screen): bee yellow 1.0,0.74,0.10 -> 0.92,0.77,0.13; grey 0.50 -> 0.54;
# hedge green 0.22,0.52,0.24 -> 0.25,0.57,0.25; flower red 0.88,0.16,0.20 ->
# 0.85,0.18,0.22; plum ink 0.24,0.13,0.32 -> 0.25,0.14,0.34; white -> 0.92
# (filmic's shoulder: brighter light would lift the mid-tones more than it
# whitens the whites).
# Key light turned toward the front: fronts are the main lit plane (N.L
# 0.71), tops stay bright (0.57), left sides 0.41 and right sides fall into
# shade, so cubes read clearly from the camera.
const NEW_KEY_ROT := Vector3(-35, -30, 0)
# Key light energy, lerped from day to night by darkness. Colour as today:
# Color(1.0, 0.96, 0.88).lerp(Color(0.66, 0.74, 1.0), d). Lower than the
# audit's first guess (0.9, 0.55): without the sky's ambient and its
# reflections in the mix, that washed every mid-tone out (grey 0.50 -> 0.62).
const NEW_KEY_ENERGY := [0.65, 0.36]
# Ambient from a colour instead of the sky (AMBIENT_SOURCE_COLOR): white
# blended toward the sky's horizon colour by NEW_AMBIENT_HAZE, lerped day to
# night, so the scene takes a little of the hour's colour without the cyan
# cast; and the energy, lerped day to night. By day the warm key and the
# cool ambient add up to a neutral white.
const NEW_AMBIENT_HAZE := [0.3, 0.6]
const NEW_AMBIENT_ENERGY := [0.37, 0.31]
# Specular reflections of the sky (Environment.reflected_light_source): 0.0
# switches them off (REFLECTION_SOURCE_DISABLED), 1.0 keeps them
# (REFLECTION_SOURCE_BG). Kept, they lift every dark and saturated colour
# toward cyan (bee yellow's blue 0.10 -> 0.23, plum ink 0.32 -> 0.41), the
# same cast the sky's ambient gave; the materials are rough, so nothing
# else is lost.
const NEW_REFLECTIONS := 0.0
# Glow as today (intensity 0.4), but only what is brighter than this blooms:
# the sun, the city's windows, emissive effects. Lit faces now stay under
# 1.0 (they reached about 1.07 before), and nothing but light sources should
# ever bloom.
const NEW_GLOW_HDR_THRESHOLD := 1.2
# Night gains (albedo multiplied past 1 as darkness goes 0.4 -> 1, the
# formula view3d.gd uses for the flowers): flowers and bee as today, and now
# the hedges too, which were muddy against the navy sky. At full night a
# front then shows (authored -> on screen) hedge green 0.22,0.52,0.24 ->
# 0.14,0.41,0.24, flower red -> 0.80,0.14,0.28, bee yellow -> 0.87,0.75,0.14.
const NEW_NIGHT_GAIN := 1.7
const NEW_HEDGE_NIGHT_GAIN := 1.3

# ------------------------------------------------------------------ layouts
# play: today's mock layout (view px, y down from the top of the view, the
# camera at y 0) plus a gull. Rows are [obstacle y, gap centre, gap width].
const PLAY := {
	"cam_top": 0.0,
	"rows": [[150.0, 110.0, 120.0], [420.0, 290.0, 120.0], [690.0, 190.0, 110.0]],
	"flowers": [["red", 160.0, 300.0], ["yellow", 300.0, 575.0], ["blue", 110.0, 840.0]],
	"clouds": [["cloud_voxel_a", 70.0, 230.0], ["cloud_voxel_c", 330.0, 520.0]],
	"gulls": [[318.0, 352.0, false]],
	"bee": [230.0, 760.0, 1, 0.0],
	"tods": ["day", "dusk", "night"],
}
# The start scene as main.gd _reset_to_ground_scene builds it (dumped from
# the real game with qa_shots.gd's seed 5): the cold-start camera, the bee
# standing on the grass, the first rows, and what view3d.gd _sync_scenery
# adds (ground, trees for the hills, the backdrop at -95 with its base slab,
# the sun hung behind).
const TITLE := {
	"cam_top": "start",   # main.gd: camera_y = GROUND_DEPTH - screen_h
	"start": true, "rows_spawned": 6, "last_gap_x": 148.491807892919,
	"rows": [[-390.0, 246.194735527039, 168.6], [-580.0, 213.096211457253, 168.6],
		[-770.0, 159.420493084192, 168.6], [-960.0, 149.043695190549, 168.6]],
	"flowers": [["blue", 200.031188964844, -281.597930908203], ["red", 363.885986328125, -495.358612060547],
		["red", 270.284698486328, -663.167541503906], ["blue", 32.5029067993164, -869.327270507813]],
	"clouds": [[70.6005817651749, 190.636535644531, -428.441375732422], [73.7107998132706, 260.691314697266, -589.101623535156],
		[52.5730195641518, 235.675903320313, -803.376647949219]],
	"bee": [200.0, -12.8, 1, 0.0],
	"wing": 0.25,
	"tods": ["day"],
}
# The night sky: the three bodies at their game depth, stars, two rows.
const NIGHT_SKY := {
	"cam_top": 0.0,
	"rows": [[300.0, 250.0, 110.0], [650.0, 140.0, 110.0]],
	"celestials": [["moon", 110.0, 170.0], ["jupiter", 285.0, 480.0], ["ufo", 270.0, 790.0]],
	"tods": ["night"],
}

var fallback_dir := ProjectSettings.globalize_path("res://models")
var opt := {"models": "", "out": "", "w": "1080", "h": "2400", "lods": "1", "msaa": "2",
	"light": "new", "hedge": "new", "scene": "play", "tod": "", "layout": QA_LAYOUTS, "zoom": "1", "tune": ""}
var sv: SubViewport
var scene: Node3D
var cam: Camera3D
var zcam: Camera3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun_light: DirectionalLight3D
var stars: MultiMeshInstance3D
var star_mat: StandardMaterial3D
var templates := {}
var flower_mats: Array = []
var bee_mats: Array = []
var hedge_mats: Array = []
var gull_mats: Array = []
var city_mat: StandardMaterial3D
var sun_disc: Node3D
var sun_mat: StandardMaterial3D
var sun_y0 := 0.0
var calib: Array = []            # [name, colour, front point, top point]
var lay := {}
var cam_top := 0.0
var screen_h := 800.0
var out := ""
var new_light := true
# the NEW_* numbers in use: the constants, or --tune=name:day:night,... while tuning
var tune := {"key": NEW_KEY_ENERGY, "amb": NEW_AMBIENT_ENERGY, "haze": NEW_AMBIENT_HAZE,
	"refl": [NEW_REFLECTIONS], "glow": [NEW_GLOW_HDR_THRESHOLD], "gain": [NEW_NIGHT_GAIN], "hgain": [NEW_HEDGE_NIGHT_GAIN]}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and opt.has(kv[0]):
			opt[kv[0]] = kv[1]
	if opt["models"] == "":
		opt["models"] = fallback_dir
	out = opt["out"].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	new_light = opt["light"] != "old"
	for t: String in (opt["tune"] as String).split(",", false):
		var parts: PackedStringArray = t.split(":")
		var vals := []
		for v in parts.slice(1):
			vals.append(float(v))
		tune[parts[0]] = vals
		print("MOCK tune ", parts[0], " = ", vals)
	var w := int(opt["w"])
	var h := int(opt["h"])
	await process_frame

	sv = SubViewport.new()
	sv.size = Vector2i(w, h)
	sv.size_2d_override = Vector2i(400, roundi(400.0 * h / w))
	sv.size_2d_override_stretch = true
	sv.msaa_3d = {"1": Viewport.MSAA_DISABLED, "2": Viewport.MSAA_2X, "4": Viewport.MSAA_4X, "8": Viewport.MSAA_8X}.get(opt["msaa"], Viewport.MSAA_2X)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = true
	root.add_child(sv)
	screen_h = roundi(400.0 * h / w)   # main.gd screen_h = the 2D viewport height
	scene = Node3D.new()
	sv.add_child(scene)

	lay = _layout(opt["scene"])
	cam_top = GROUND_DEPTH - screen_h if lay.get("cam_top") is String else float(lay.get("cam_top", 0.0))
	print("MOCK scene %s light %s hedge %s msaa %s models %s" % [opt["scene"], opt["light"], opt["hedge"], opt["msaa"], opt["models"]])
	_setup_world()
	_build_layout()
	await process_frame

	var tods: Array = lay["tods"] if opt["tod"] == "" else Array(opt["tod"].split(","))
	for tod in tods:
		_set_darkness({"day": 0.0, "dusk": 0.5, "night": 1.0}.get(tod, lay.get("darkness", 0.0)))
		sv.size = Vector2i(w, h)
		cam.make_current()
		# the sky's light (ambient, old; reflections, both) needs ~100 frames
		# to settle after a change
		for k in 150:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.save_png(out + opt["scene"] + "_" + tod + ".png")
		print("MOCK shot ", opt["scene"], "_", tod)
		if calib.size() > 0:
			_measure(img, tod)
		if lay.has("zoom") and opt["zoom"] == "1" and tod != "dusk":
			await _zoom_shot(opt["scene"] + "_zoom_" + tod, w, h)
	print("MOCK wrote ", out)
	for t in templates.values():
		t.free()
	sv.queue_free()
	await process_frame
	quit()


func _layout(name: String) -> Dictionary:
	var l := {}
	if name == "play":
		l = PLAY.duplicate(true)
		l["zoom"] = true
	elif name == "title_hills" or name == "title_city":
		l = TITLE.duplicate(true)
		l["backdrop"] = name.trim_prefix("title_")
	elif name == "night_sky":
		l = NIGHT_SKY.duplicate(true)
	elif name == "calib":
		l = {"cam_top": 0.0, "calib": true, "tods": ["day", "dusk", "night"]}
	elif name.begins_with("qa_"):
		var all = JSON.parse_string(FileAccess.get_file_as_string(opt["layout"]))
		var d: Dictionary = all[name] if all.has(name) else all[name.trim_prefix("qa_")]
		l = d.duplicate(true)
		l["cam_top"] = d["camera_y"]
		l["start"] = name.begins_with("qa_title")
		l["tods"] = ["day"] if d["darkness"] < 0.25 else (["night"] if d["darkness"] > 0.75 else ["dusk"])
		l["bee_model"] = "bee_voxel" if d["skin"] == "normal" else "bee_voxel_" + d["skin"]
		l["wing"] = 0.25 if l["start"] else 0.8
	else:
		push_error("MOCK unknown scene " + name)
	return l


# ------------------------------------------------------------------ models
func _model_path(name: String) -> String:
	var p: String = opt["models"].trim_suffix("/") + "/" + name + ".glb"
	if FileAccess.file_exists(p):
		return p
	return fallback_dir + "/" + name + ".glb"


func _has_own(name: String) -> bool:
	return FileAccess.file_exists(opt["models"].trim_suffix("/") + "/" + name + ".glb")


func _template(name: String) -> Node3D:
	if templates.has(name):
		return templates[name]
	var path := _model_path(name)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("MOCK cannot load %s (%d)" % [path, err])
		return null
	if opt["lods"] == "1":
		# the editor import generates LODs (meshes/generate_lods=true); do the same
		for gm: GLTFMesh in state.get_meshes():
			if gm.mesh:
				gm.mesh.generate_lods(60.0, 25.0, [])
	var n: Node3D = doc.generate_scene(state)
	# view3d.gd _use_vertex_colours
	var tris := 0
	for m: MeshInstance3D in _meshes(n):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true
			var arr: Array = m.mesh.surface_get_arrays(i)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	print("MOCK model %s tris %d  <- %s" % [name, tris, path])
	templates[name] = n
	return n


func _spawn(name: String, parent: Node) -> Node3D:
	var n: Node3D = _template(name).duplicate()
	parent.add_child(n)
	return n


func _materials_of(name: String) -> Array:
	var outm := []
	for m: MeshInstance3D in _meshes(_template(name)):
		for i in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not outm.has(mat):
				outm.append(mat)
	return outm


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


# merged AABB of a model in its own root space
func _aabb(n: Node, xf := Transform3D.IDENTITY) -> AABB:
	var box := AABB()
	var first := true
	var here := xf
	if n is Node3D and n != _aabb_root:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		box = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var cb := _aabb(c, here)
		if cb.size == Vector3.ZERO and cb.position == Vector3.ZERO:
			continue
		box = cb if first else box.merge(cb)
		first = false
	return box


var _aabb_root: Node = null


func _model_aabb(name: String) -> AABB:
	_aabb_root = _template(name)
	return _aabb(_aabb_root)


# ------------------------------------------------------------------ world (view3d.gd setup/_sync_*)
# 2D world px -> 3D (view3d.gd to3)
func to3(p: Vector2, z := 0.0) -> Vector3:
	return Vector3((p.x - SCREEN_W / 2.0) / PX, -p.y / PX, z)


func _cam_dist() -> float:
	return (screen_h / PX / 2.0) / tan(deg_to_rad(FOV / 2.0))


func _setup_world() -> void:
	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 400.0
	scene.add_child(cam)
	var dist := _cam_dist()
	var centre := Vector3(0.0, -(cam_top + screen_h / 2.0) / PX, 0)
	var pitch := deg_to_rad(CAM_PITCH)
	cam.rotation.x = -pitch
	cam.position = centre + Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.make_current()

	zcam = Camera3D.new()
	zcam.far = 400.0
	scene.add_child(zcam)

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	if new_light:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = tune["amb"][0]
		env.glow_hdr_threshold = tune["glow"][0]
		if tune["refl"][0] < 0.5:
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = OLD_AMBIENT_ENERGY[0]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 220.0
	env.fog_density = 0.55
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = NEW_KEY_ROT if new_light else OLD_KEY_ROT
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	sun_light.shadow_enabled = false
	sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	scene.add_child(sun_light)

	_build_stars()
	var sky_y := cam.position.y - fposmod(cam.position.y, STAR_SPAN)
	stars.position = Vector3(cam.position.x, sky_y, cam.position.z - 180.0)


func _set_darkness(d: float) -> void:
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
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon
	env.fog_light_color = horizon
	for mat in gull_mats:
		mat.albedo_color = Color.WHITE.lerp(horizon, GULL_HAZE)
	if city_mat:
		city_mat.albedo_color = Color.WHITE.lerp(horizon, CITY_HAZE)
	var night := clampf((d - 0.4) / 0.6, 0.0, 1.0)
	var gain := lerpf(1.0, tune["gain"][0] if new_light else OLD_NIGHT_GAIN, night)
	for mat in flower_mats:
		mat.albedo_color = Color(gain, gain, gain)
	for mat in bee_mats:
		mat.albedo_color = Color(gain, gain, gain)
	var hgain := lerpf(1.0, tune["hgain"][0], night) if new_light else 1.0
	for mat in hedge_mats:
		mat.albedo_color = Color(hgain, hgain, hgain)
	sun_light.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.66, 0.74, 1.0), d)
	if new_light:
		sun_light.light_energy = lerpf(tune["key"][0], tune["key"][1], d)
		env.ambient_light_color = Color.WHITE.lerp(horizon, lerpf(tune["haze"][0], tune["haze"][1], d))
		env.ambient_light_energy = lerpf(tune["amb"][0], tune["amb"][1], d)
	else:
		sun_light.light_energy = lerpf(OLD_KEY_ENERGY[0], OLD_KEY_ENERGY[1], d)
		env.ambient_light_energy = lerpf(OLD_AMBIENT_ENERGY[0], OLD_AMBIENT_ENERGY[1], d)
	if sun_disc:
		sun_disc.position.y = sun_y0 - d * 70.0
		sun_mat.albedo_color.a = clampf(1.0 - d * 2.2, 0.0, 1.0)
		sun_disc.visible = sun_mat.albedo_color.a > 0.01
	star_mat.albedo_color.a = clampf((d - 0.45) * 2.0, 0.0, 1.0)
	stars.visible = star_mat.albedo_color.a > 0.0


func _build_stars() -> void:
	const STAR_VOX := 0.34
	const SQUARES := 140
	const CROSSES := 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var patch: Array[Transform3D] = []
	for i in SQUARES:
		var side := 2.0 if rng.randf_range(0.5, 1.4) > 1.08 else 1.0
		patch.append(Transform3D(Basis().scaled(Vector3.ONE * side),
			Vector3(rng.randf_range(-60, 60), rng.randf_range(-STAR_SPAN / 2.0, STAR_SPAN / 2.0), 0)))
	for i in CROSSES:
		var at := Vector3(rng.randf_range(-60, 60), rng.randf_range(-STAR_SPAN / 2.0, STAR_SPAN / 2.0), 0).snappedf(STAR_VOX)
		patch.append(Transform3D(Basis().scaled(Vector3(3, 1, 1)), at))
		patch.append(Transform3D(Basis().scaled(Vector3(1, 3, 1)), at))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * STAR_VOX
	mm.mesh = cube
	mm.instance_count = patch.size() * 3
	for copy in 3:
		for i in patch.size():
			mm.set_instance_transform(copy * patch.size() + i, patch[i].translated(Vector3(0, (copy - 1) * STAR_SPAN, 0)))
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.albedo_color = Color(1, 1, 0.95, 0)
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.material_override = star_mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(stars)


# ------------------------------------------------------------------ layout
# Positions in `lay` are main.gd's 2D world px; `cam_top` is main.camera_y
# (the top of the view).
func _build_layout() -> void:
	if lay.get("calib", false):
		_build_calib()
		return
	if lay.get("start", false):
		_build_scenery()
	_build_hedges()

	for f in lay.get("flowers", []):
		var fl := _spawn("flower_voxel_" + f[0], scene)
		fl.position = to3(Vector2(f[1], f[2]), 0.1)
		for mat in _materials_of("flower_voxel_" + f[0]):
			if not flower_mats.has(mat):
				flower_mats.append(mat)

	for c in lay.get("clouds", []):
		# view3d.gd _build_cloud: a model per size, picked by the cloud's span
		var model: String = c[0] if c[0] is String else (
			"cloud_voxel_a" if c[0] >= 65.0 else ("cloud_voxel_b" if c[0] >= 55.0 else "cloud_voxel_c"))
		var cl := _spawn(model, scene)
		cl.position = to3(Vector2(c[1], c[2]), -2.2)
		for m: MeshInstance3D in _meshes(cl):
			for i in m.mesh.get_surface_count():
				var mat: Material = m.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	for g in lay.get("gulls", []):
		var gl := _spawn("gull_voxel", scene)
		gl.position = to3(Vector2(g[0], g[1]), GULL_DEPTH)
		gl.rotation.y = PI if g[2] else 0.0
		var gwl: Node3D = gl.find_child("WingPivotL", true, false)
		var gwr: Node3D = gl.find_child("WingPivotR", true, false)
		if gwl: gwl.rotation.x = 0.5
		if gwr: gwr.rotation.x = -0.5
		gull_mats = _materials_of("gull_voxel")

	for b in lay.get("celestials", []):
		var cb := _spawn(b[0] + "_voxel", scene)
		cb.position = to3(Vector2(b[1], b[2]), CELESTIAL_DEPTH)
		cb.rotation.y = 0.75
		# view3d.gd _glowing: sky bodies shine by themselves
		for m: MeshInstance3D in _meshes(cb):
			for i in m.mesh.get_surface_count():
				var mat: Material = m.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if lay.has("bee"):
		var bp: Array = lay["bee"]
		var model: String = lay.get("bee_model", "bee_voxel")
		var bee := _spawn(model, scene)
		bee.position = to3(Vector2(bp[0], bp[1]), 0.15)
		# view3d.gd _sync_bee: yaw by facing, lean by tilt
		bee.rotation = Vector3(0.0, 0.0 if bp[2] > 0 else PI, -bp[3] * bp[2])
		bee_mats = _materials_of(model)
		var wing: float = lay.get("wing", 0.8)
		var wl: Node3D = bee.find_child("WingPivotL", true, false)
		var wr: Node3D = bee.find_child("WingPivotR", true, false)
		var de: Node3D = bee.find_child("DeadEyes", true, false)
		var le: Node3D = bee.find_child("LiveEyes", true, false)
		if wl: wl.rotation.x = wing
		else: push_error("MOCK bee has no WingPivotL")
		if wr: wr.rotation.x = -wing
		else: push_error("MOCK bee has no WingPivotR")
		if de: de.visible = false
		else: push_error("MOCK bee has no DeadEyes")
		if le: le.visible = true
		else: push_error("MOCK bee has no LiveEyes")


func _build_hedges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var caps: bool = opt["hedge"] != "old" and _has_own("hedge_voxel_cap_l") and _has_own("hedge_voxel_cap_r")
	# the tile-side edge of each cap, from its origin (the gap edge), in px
	var cap_l_px := 0.0
	var cap_r_px := 0.0
	if caps:
		var bl := _model_aabb("hedge_voxel_cap_l")
		var br := _model_aabb("hedge_voxel_cap_r")
		cap_l_px = snappedf(bl.position.x, VOX) * PX
		cap_r_px = snappedf(br.end.x, VOX) * PX
		print("MOCK caps: left x %.3f..%.3f u, right x %.3f..%.3f u; tiles butt at %.1f / %.1f px from the gap" % [
			bl.position.x, bl.end.x, br.position.x, br.end.x, cap_l_px, cap_r_px])
	var used := {}
	for r in lay.get("rows", []):
		var row := Node3D.new()
		scene.add_child(row)
		var band_mid: float = r[0] + 11.0     # obstacle.gd THICK / 2
		row.position = to3(Vector2(SCREEN_W / 2.0, band_mid))
		var gap_left: float = r[1] - r[2] / 2.0
		var gap_right: float = r[1] + r[2] / 2.0
		if opt["hedge"] == "old":
			# view3d.gd _build_hedge_row today: each bar split into equal
			# tiles stretched to fill it
			for bar in [[-80.0, gap_left], [gap_right, SCREEN_W + 80.0]]:
				var x1: float = bar[0]
				var x2: float = bar[1]
				if x2 <= x1 + 1.0:
					continue
				var width_u: float = (x2 - x1) / PX
				var n := maxi(1, int(ceil(width_u / HEDGE_TILE_W)))
				var seg_w := width_u / n
				for i in n:
					var model: String = HEDGE_VARIANTS[rng.randi() % HEDGE_VARIANTS.size()]
					var hgt := _spawn(model, row)
					used[model] = true
					hgt.scale = Vector3(seg_w / HEDGE_TILE_W, 1, 1)
					hgt.position = Vector3((x1 - SCREEN_W / 2.0) / PX + i * seg_w, 0, 0)
			continue
		# whole tiles, laid outward from the gap (or from its end cap) until
		# past the bar's far end
		var left_from := gap_left
		var right_from := gap_right
		if caps:
			var cl := _spawn("hedge_voxel_cap_l", row)
			cl.position = Vector3((gap_left - SCREEN_W / 2.0) / PX, 0, 0)
			var cr := _spawn("hedge_voxel_cap_r", row)
			cr.position = Vector3((gap_right - SCREEN_W / 2.0) / PX, 0, 0)
			left_from = gap_left + cap_l_px
			right_from = gap_right + cap_r_px
			used["hedge_voxel_cap_l"] = true
			used["hedge_voxel_cap_r"] = true
		var tile_px := HEDGE_TILE_W * PX
		var x := left_from
		while x > -80.0:
			x -= tile_px
			var model: String = HEDGE_VARIANTS[rng.randi() % HEDGE_VARIANTS.size()]
			_spawn(model, row).position = Vector3((x - SCREEN_W / 2.0) / PX, 0, 0)
			used[model] = true
		x = right_from
		while x < SCREEN_W + 80.0:
			var model: String = HEDGE_VARIANTS[rng.randi() % HEDGE_VARIANTS.size()]
			_spawn(model, row).position = Vector3((x - SCREEN_W / 2.0) / PX, 0, 0)
			used[model] = true
			x += tile_px
	for model in used:
		for mat in _materials_of(model):
			if not hedge_mats.has(mat):
				hedge_mats.append(mat)


# view3d.gd _sync_scenery: ground, trees (hills), backdrop with its base slab
# and the sun, placed for the cold-start camera
func _build_scenery() -> void:
	var hills: bool = lay.get("backdrop", "hills") == "hills"
	_spawn("ground_voxel", scene).position = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lay["rows_spawned"]) * 7919 + int(float(lay["last_gap_x"]) * 13.0)
	if hills:
		var x := -8.0
		while x < 8.0:
			var kind := "round" if rng.randf() < 0.6 else "pine"
			var t := _spawn("tree_voxel_%s_%s" % [kind, ["a", "b", "c"][rng.randi() % 3]], scene)
			t.position = Vector3(snappedf(x, 0.04), 0, snappedf(rng.randf_range(-2.4, -1.4), 0.04))
			x += rng.randf_range(0.9, 1.5)
	var back := _spawn("backdrop_voxel_hills" if hills else "backdrop_voxel_city", scene)
	city_mat = null
	if not hills:
		for m: MeshInstance3D in _meshes(back):
			var street := String(m.name).begins_with("City")
			if not street and not String(m.name).begins_with("Windows"):
				continue
			for i in m.mesh.get_surface_count():
				var mat: Material = m.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.disable_fog = true
					if street:
						city_mat = mat
	var dist := _cam_dist()
	var cam_y: float = -(cam_top + screen_h / 2.0) / PX + sin(deg_to_rad(CAM_PITCH)) * dist
	var foot_y: float = cam_y + (0.35 - cam_y) * (dist + BACKDROP_DEPTH) / dist
	back.position = Vector3(0, foot_y + 1.5, -BACKDROP_DEPTH)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160, 90, 2)
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.40, 0.70, 0.40) if hills else Color(0.46, 0.72, 0.46)
	base.material_override = bmat
	base.position = Vector3(0, foot_y - 45.0 + 0.5, -BACKDROP_DEPTH + 4.0)
	scene.add_child(base)
	var sun: Node3D = _template("sun_voxel").duplicate()
	var ball: Node3D = sun.find_child("Ball", true, false)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.35)
	mat.emission_energy_multiplier = 0.35 if ball else 1.6
	mat.disable_fog = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if ball:
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	for m: MeshInstance3D in _meshes(sun):
		m.material_override = mat
	var start_cam_y: float = -(GROUND_DEPTH - screen_h / 2.0) / PX + sin(deg_to_rad(CAM_PITCH)) * dist
	sun_y0 = start_cam_y + (SUN_HEIGHT - start_cam_y) * (dist + BACKDROP_DEPTH + 40.0) / dist
	sun.position = Vector3(14, sun_y0, -BACKDROP_DEPTH - 40)
	scene.add_child(sun)
	sun_disc = sun
	sun_mat = mat


# ------------------------------------------------------------------ calibration
# Swatches of known sRGB colours: boxes on the play plane (1 x 1 u, 2 u
# deep so their tops show), low on the screen, coloured the way a voxel GLB
# is (linear vertex colours, a material with vertex_color_use_as_albedo and
# roughness 0.65), each taking the night gain of its kind. _measure prints
# what their front and top faces come out as.
const SWATCHES := [["bee_yellow", Color(1.0, 0.74, 0.10), "bee"], ["hedge_green", Color(0.22, 0.52, 0.24), "hedge"],
	["rose_coral", Color(0.96, 0.42, 0.48), "hedge"], ["flower_red", Color(0.88, 0.16, 0.20), "flower"],
	["flower_blue", Color(0.30, 0.36, 0.90), "flower"], ["white", Color(1, 1, 1), "bee"],
	["plum_ink", Color(0.24, 0.13, 0.32), "bee"], ["grey_50", Color(0.5, 0.5, 0.5), "flower"]]


func _build_calib() -> void:
	for i in SWATCHES.size():
		var s: Array = SWATCHES[i]
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 2)
		var arr := bm.get_mesh_arrays()
		var cols := PackedColorArray()
		cols.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.fill((s[1] as Color).srgb_to_linear())
		arr[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.65
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var at := to3(Vector2(50.0 + (i % 4) * 100.0, screen_h * (0.62 if i < 4 else 0.82)))
		mi.position = at
		scene.add_child(mi)
		calib.append([s[0], s[1], at + Vector3(0, 0, 1.0), at + Vector3(0, 0.5, 0.3)])
		({"bee": bee_mats, "hedge": hedge_mats, "flower": flower_mats}[s[2]] as Array).append(mat)


func _measure(img: Image, tod: String) -> void:
	var k := float(img.get_width()) / SCREEN_W
	for c in calib:
		var line := "MOCK calib %s %-11s authored %s" % [tod, c[0], _rgb(c[1])]
		for which in [["front", c[2]], ["top", c[3]]]:
			var p: Vector2 = cam.unproject_position(which[1]) * k
			var acc := Color(0, 0, 0)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					acc += img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1))
			line += "  %s %s" % [which[0], _rgb(acc / 25.0)]
		print(line)


func _rgb(c: Color) -> String:
	return "(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]


# ------------------------------------------------------------------ zoom
# Two panels (top: the second hedge's gap; bottom: the bee), each from the
# game camera's position, at the pixel density of FOV/3 over the full height.
func _zoom_shot(name: String, w: int, h: int) -> void:
	var pw := roundi(h * 2.0 / 3.0)
	var ph := h / 2
	var half := atan(tan(deg_to_rad(FOV / 3.0 / 2.0)) * float(ph) / float(h))
	zcam.fov = rad_to_deg(half * 2.0)
	zcam.position = cam.position
	var img := Image.create(pw, ph * 2, false, Image.FORMAT_RGBA8)
	var r2: Array = lay["rows"][1]
	var bp: Array = lay["bee"]
	var targets := [to3(Vector2(r2[1], r2[0] + 11.0), 0.0), to3(Vector2(bp[0], bp[1]), 0.15)]
	sv.size = Vector2i(pw, ph)
	zcam.make_current()
	for t in targets.size():
		zcam.look_at_from_position(cam.position, targets[t], Vector3.UP)
		for k in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		var part := sv.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(0, 0, pw, ph), Vector2i(0, ph * t))
	img.save_png(out + name + ".png")
	print("MOCK shot ", name)
	sv.size = Vector2i(w, h)
	cam.make_current()
