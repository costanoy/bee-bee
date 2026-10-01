extends Node

# The online leaderboard, through Google Play Games Services: Google hosts
# the scores and the screen that lists them, so there is no server or
# database of ours. The player signs in with their Play Games profile.
#
# SWITCHED OFF until the game exists in the Play Console. While it is off
# nothing here runs and the trophy buttons stay hidden. To switch it on:
#   1. Play Console > Play Games Services: create the project and one
#      leaderboard ("higher is better"), and add both signing keys' SHA-1.
#   2. Put the leaderboard's id in LEADERBOARD_ID below.
#   3. project.godot, [editor_plugins]: add
#      "res://addons/GodotPlayGameServices/plugin.cfg" to `enabled`.
#   4. export_presets.cfg, Android preset options: set
#      godot_play_game_services/game_id to the Play Games project id (digits).
const LEADERBOARD_ID := ""

var available := false
var signed_in := false
var _sign_in: PlayGamesSignInClient
var _boards: PlayGamesLeaderboardsClient
var _show_after_sign_in := false


func start() -> void:
	if LEADERBOARD_ID == "" or OS.get_name() != "Android":
		return
	if not Engine.has_singleton("GodotPlayGameServices"):
		return
	if GodotPlayGameServices.initialize() != GodotPlayGameServices.PlayGamesPluginError.OK:
		return
	available = true
	# created after initialize(): they hook the plugin's signals when added
	_sign_in = PlayGamesSignInClient.new()
	add_child(_sign_in)
	_boards = PlayGamesLeaderboardsClient.new()
	add_child(_boards)
	_sign_in.user_authenticated.connect(_on_authenticated)
	# Play Games signs returning players in by itself at launch; this asks
	# how that went.
	_sign_in.is_authenticated()


func _on_authenticated(is_authenticated: bool) -> void:
	signed_in = is_authenticated
	if not signed_in:
		_show_after_sign_in = false
		return
	# a record made while signed out still counts
	submit(SaveData.best_score)
	if _show_after_sign_in:
		_show_after_sign_in = false
		_boards.show_leaderboard(LEADERBOARD_ID)


# Google keeps only a player's best, so sending every run's score is fine.
func submit(score: int) -> void:
	if available and signed_in and score > 0:
		_boards.submit_score(LEADERBOARD_ID, score)


# Opens Google's leaderboard screen, asking the player to sign in first if
# they haven't.
func show() -> void:
	if not available:
		return
	if signed_in:
		_boards.show_leaderboard(LEADERBOARD_ID)
	else:
		_show_after_sign_in = true
		_sign_in.sign_in()
