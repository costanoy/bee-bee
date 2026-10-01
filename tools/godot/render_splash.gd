extends SceneTree

# Renders the boot splash: the voxel "Bee Bee" title with the bee hovering
# between the words, on a transparent square. project.godot shows it fitted
# to the screen over a sky-blue background (application/boot_splash/*).
#
#   godot --path . --audio-driver Dummy --script tools/godot/render_splash.gd
#
# Writes art/ui/splash.png. Run it again if the logo or the bee changes,
# then --import.

const SIZE := 1200
const LOGO_W := 940.0


func _init() -> void:
	await process_frame
	var sv := SubViewport.new()
	sv.size = Vector2i(SIZE, SIZE)
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)

	var logo: Control = load("res://scripts/voxel_logo.gd").new()
	logo.setup(LOGO_W)
	logo.position = (Vector2(SIZE, SIZE) - logo.size) / 2.0
	sv.add_child(logo)

	# same proportions as the title screen (main.gd _build_start_screen)
	var k := LOGO_W / 344.0
	var bee := TextureRect.new()
	bee.texture = load("res://art/ui/bee_normal.png")
	bee.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bee.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bee.size = Vector2.ONE * 74.0 * k
	bee.position = logo.position + logo.gap_anchor - Vector2(37.0, 40.0) * k
	sv.add_child(bee)

	for i in 4:
		await process_frame
	sv.get_texture().get_image().save_png("res://art/ui/splash.png")
	print("wrote art/ui/splash.png")
	quit()
