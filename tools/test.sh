#!/usr/bin/env bash
# Runs the game's behaviour checks (tools/godot/test_game.gd), in English and
# in Portuguese. From Git Bash, in the project folder:   bash tools/test.sh
#
# The game writes its save file while the checks play it, so the player's
# own save is set aside first and put back afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/Vinicius Costa/Desktop/Apps/Godot_v4.7.1-stable_win64.exe}"
SAVE="$APPDATA/Godot/app_userdata/Bee Bee/bee_bee_save.cfg"
KEEP="$(mktemp -d)"
[ -f "$SAVE" ] && cp "$SAVE" "$KEEP/save.cfg"
[ -f "$SAVE.bak" ] && cp "$SAVE.bak" "$KEEP/save.cfg.bak"

status=0
for lang in en pt; do
	out=$("$GODOT" --headless --path . --fixed-fps 60 --script tools/godot/test_game.gd -- --lang=$lang 2>&1)
	echo "$out" | grep -E "FAIL|TESTS|SCRIPT ERROR|Parse Error"
	echo "$out" | grep -q "TESTS done, failures: 0" || status=1
done

[ -f "$KEEP/save.cfg" ] && cp "$KEEP/save.cfg" "$SAVE"
[ -f "$KEEP/save.cfg.bak" ] && cp "$KEEP/save.cfg.bak" "$SAVE.bak"
[ $status -eq 0 ] && echo "all checks passed" || echo "SOME CHECKS FAILED"
exit $status
