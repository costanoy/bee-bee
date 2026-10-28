#!/usr/bin/env bash
# Runs the game's behaviour checks (tools/godot/test_game.gd and
# test_features.gd), in English and in Portuguese. From Git Bash, in the
# project folder:   bash tools/test.sh
#
# The game writes its save file while the checks play it, so the player's
# own save is set aside first and put back afterwards, even if the run is
# stopped halfway (Ctrl-C) or a check gets stuck.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/Vinicius Costa/Desktop/Apps/Godot_v4.7.1-stable_win64.exe}"
# A full run takes about 20 s. A script that errors before its quit() never
# exits on its own, so each run is cut off after this many seconds.
RUN_TIMEOUT="${RUN_TIMEOUT:-300}"
SAVE="$APPDATA/Godot/app_userdata/Bee Bee/bee_bee_save.cfg"
KEEP="$(mktemp -d)"
[ -f "$SAVE" ] && cp "$SAVE" "$KEEP/save.cfg"
[ -f "$SAVE.bak" ] && cp "$SAVE.bak" "$KEEP/save.cfg.bak"

put_back() {
	[ -f "$KEEP/save.cfg" ] && cp "$KEEP/save.cfg" "$SAVE"
	[ -f "$KEEP/save.cfg.bak" ] && cp "$KEEP/save.cfg.bak" "$SAVE.bak"
	rm -rf "$KEEP"
}
trap put_back EXIT
trap 'exit 130' INT TERM

status=0
for lang in en pt; do
	for checks in test_game test_features; do
		out=$(timeout "$RUN_TIMEOUT" "$GODOT" --headless --path . --fixed-fps 60 --script tools/godot/$checks.gd -- --lang=$lang 2>&1)
		code=$?
		echo "$out" | grep -E "FAIL|TESTS|SCRIPT ERROR|Parse Error"
		[ $code -eq 124 ] && echo "TIMEOUT $checks $lang (stuck for ${RUN_TIMEOUT} s, likely an error before quit())"
		echo "$out" | grep -q "TESTS done, failures: 0" || status=1
	done
done

[ $status -eq 0 ] && echo "all checks passed" || echo "SOME CHECKS FAILED"
exit $status
