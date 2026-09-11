extends Node

# Autoload singleton — persists progress between sessions via ConfigFile
# under user://. Registered in project.godot's [autoload] section directly
# (no editor Project Settings step needed).

const SAVE_PATH := "user://bee_bee_save.cfg"

var seen_tutorial := false
var best_score := 0
var shining_bee_unlocked := false
var selected_bee := "normal"  # "normal" | "shining" — only "normal" has a sprite so far


func _ready() -> void:
	load_data()


func load_data() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err == OK:
		seen_tutorial = config.get_value("save", "seen_tutorial", false)
		best_score = config.get_value("save", "best_score", 0)
		shining_bee_unlocked = config.get_value("save", "shining_bee_unlocked", false)
		selected_bee = config.get_value("save", "selected_bee", "normal")


func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("save", "seen_tutorial", seen_tutorial)
	config.set_value("save", "best_score", best_score)
	config.set_value("save", "shining_bee_unlocked", shining_bee_unlocked)
	config.set_value("save", "selected_bee", selected_bee)
	config.save(SAVE_PATH)
