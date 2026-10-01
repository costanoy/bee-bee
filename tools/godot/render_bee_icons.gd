extends SceneTree

# Renders the bee menu's icons from the bee models, so the menu shows each
# skin exactly as the game draws it (the silver one unshaded, like in play).
#
#   godot --path . --audio-driver Dummy --script tools/godot/render_bee_icons.gd
#
# Writes art/ui/bee_normal.png and art/ui/bee_silver.png (256x256,
# transparent). Run it again whenever a bee model changes, then --import.

const SIZE := 256
const BEES := [
	["bee_voxel", "bee_normal", false],
	["bee_voxel_shining", "bee_silver", true],
]


func _init() -> void:
	await process_frame
	for entry in BEES:
		var sv := SubViewport.new()
		sv.size = Vector2i(SIZE, SIZE)
		sv.transparent_bg = true
		sv.own_world_3d = true
		sv.msaa_3d = Viewport.MSAA_4X
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sv)

		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.86, 0.90, 1.0)
		env.ambient_light_energy = 0.75
		var we := WorldEnvironment.new()
		we.environment = env
		sv.add_child(we)

		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, -55, 0)      # same angle as the game's
		sun.light_color = Color(1.0, 0.96, 0.88)
		sv.add_child(sun)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.05
		# a little to the front-right and above, so the face and both wings show
		cam.position = Vector3(0.9, 0.55, 3.0)
		sv.add_child(cam)
		cam.look_at(Vector3(0.02, 0.12, 0.0))

		var bee: Node3D = load("res://models/%s.glb" % entry[0]).instantiate()
		sv.add_child(bee)
		for n in bee.find_children("DeadEyes", "", true, false):
			n.visible = false
		for side in ["L", "R"]:
			var pivot: Node3D = bee.find_child("WingPivot" + side, true, false)
			pivot.rotation.x = 0.3 if side == "L" else -0.3
		for m in bee.find_children("*", "MeshInstance3D", true, false):
			for i in m.mesh.get_surface_count():
				var mat: Material = m.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.vertex_color_use_as_albedo = true
					if entry[2]:
						mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		for k in 4:
			await process_frame
		var img := sv.get_texture().get_image()
		img.save_png("res://art/ui/%s.png" % entry[1])
		print("wrote art/ui/%s.png" % entry[1])
		sv.queue_free()
	quit()
