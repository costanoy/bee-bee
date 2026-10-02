extends Node

# Autoload singleton — persists progress between sessions via ConfigFile
# under user://. Registered in project.godot's [autoload] section directly
# (no editor Project Settings step needed).

const SAVE_PATH := "user://bee_bee_save.cfg"
# Mirror copy, only overwritten right after a successful primary save — a
# fallback if the primary file is ever caught mid-write (app killed, OS
# swap, disk hiccup) and comes back corrupted/unparsable. user:// itself
# already survives Play Store updates (Android only clears it on uninstall
# or an explicit "clear data"), so this only guards against write
# corruption, not update loss.
const BACKUP_PATH := "user://bee_bee_save.cfg.bak"

var seen_tutorial := false
var best_score := 0
# Skins won by reaching their score in a run (main.gd BEE_SKINS). A skin
# also counts as unlocked whenever best_score already covers it, so this
# only matters for the moment between winning one mid-run and the run's end.
var unlocked_bees: Array = []
var selected_bee := "normal"  # a key of main.gd BEE_SKINS
var music_muted := false
var sfx_muted := false
var vibration := true


func _ready() -> void:
	load_data()


func load_data() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	# ConfigFile.load() only errors on missing/unreadable files — malformed
	# content (partial write cut off mid-save) can still return OK with an
	# empty/incomplete result, so also check a known key actually made it
	# in before trusting the primary file.
	if err != OK or not config.has_section_key("save", "best_score"):
		err = config.load(BACKUP_PATH)
	if err == OK:
		seen_tutorial = config.get_value("save", "seen_tutorial", false)
		best_score = config.get_value("save", "best_score", 0)
		unlocked_bees = config.get_value("save", "unlocked_bees", [])
		# saves from before there were several skins only knew the silver bee
		if config.get_value("save", "shining_bee_unlocked", false) and not unlocked_bees.has("shining"):
			unlocked_bees.append("shining")
		selected_bee = config.get_value("save", "selected_bee", "normal")
		music_muted = config.get_value("save", "music_muted", false)
		sfx_muted = config.get_value("save", "sfx_muted", false)
		vibration = config.get_value("save", "vibration", true)


func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("save", "seen_tutorial", seen_tutorial)
	config.set_value("save", "best_score", best_score)
	config.set_value("save", "unlocked_bees", unlocked_bees)
	config.set_value("save", "selected_bee", selected_bee)
	config.set_value("save", "music_muted", music_muted)
	config.set_value("save", "sfx_muted", sfx_muted)
	config.set_value("save", "vibration", vibration)
	if config.save(SAVE_PATH) == OK:
		config.save(BACKUP_PATH)
