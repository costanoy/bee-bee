extends Node

# The run's clock for the sky: how dark it is, which far backdrop this run
# gets, and when the one-off sky events fire. It draws nothing — view3d.gd
# reads darkness() and `backdrop` and paints the sky, sun, stars and horizon.
#
# The celestial bodies (moon/Jupiter/UFO) are spawned by main.gd as static
# world-space objects that scroll down and off-screen as the bee climbs,
# same as clouds, just without the drift. This script only decides *when*
# (via signals), since main.gd already tracks camera_y.

# The day->night crossfade runs on elapsed SCROLL TIME, not score. Every
# flower is mandatory, so score is really just "how many rows you've
# passed" — tying the sky's own darkness to that made it read as "the
# light dims because I picked a flower," which isn't what nightfall is
# supposed to mean, and it isn't a choice the player is making anyway.
# Time is unconnected to how the run is going, and stretched over minutes
# the change is barely visible from one moment to the next — the "suave e
# pouco perceptível" this was asked to be.
#
# TEST — 60 to 260 s (was 90 to 480). At the old pace the sky only began to
# turn at about 78 flowers, was at its sunset at about 250 and reached night
# at about 445 — a score almost no run gets to, so the night, its stars and
# two thirds of the dusk were never seen, and the moon (100 flowers) rose in
# plain daylight. Now the sky starts to warm at about 50 flowers, the moon
# rises into the sunset, Jupiter (200) into deep twilight and the UFO (250)
# into the night. The whole change still takes over three minutes.
const DAY_TO_DUSK_START := 60.0
const DUSK_TO_NIGHT_END := 260.0

const MOON_SCORE := 100
const JUPITER_SCORE := 200
const SHIP_SCORE := 250

# The far backdrop, re-rolled every run: the city skyline, or hills and
# mountains — the only one that gets a line of trees behind the ground,
# since the city's own buildings already read as that.
const BACKDROPS := ["city", "hills"]

var backdrop := "city"

var moon_spawned := false
var jupiter_spawned := false
var ship_spawned := false

signal moon_spawn_requested
signal jupiter_spawn_requested
signal ship_spawn_requested


func darkness(elapsed_time: float) -> float:
	# 0 in full day, 1 in full night.
	return clamp((elapsed_time - DAY_TO_DUSK_START) / (DUSK_TO_NIGHT_END - DAY_TO_DUSK_START), 0.0, 1.0)


func check_triggers(score: int) -> void:
	if score >= MOON_SCORE and not moon_spawned:
		moon_spawned = true
		moon_spawn_requested.emit()
	if score >= JUPITER_SCORE and not jupiter_spawned:
		jupiter_spawned = true
		jupiter_spawn_requested.emit()
	if score >= SHIP_SCORE and not ship_spawned:
		ship_spawned = true
		ship_spawn_requested.emit()


func reset_run() -> void:
	# Spec 4.9: these are "evento único NA PARTIDA" — one-time per RUN, not
	# per app session — so every fresh run needs to see them again.
	moon_spawned = false
	jupiter_spawned = false
	ship_spawned = false
	backdrop = BACKDROPS[randi() % BACKDROPS.size()]
