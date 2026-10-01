#!/usr/bin/env bash
# Builds the 30-second promo video: build/promo/BeeBee-promo.mp4
# (1080x1920, 60 fps). Run from Git Bash, in the project folder:
#
#   bash tools/build_promo.sh
#
# tools/godot/render_promo.gd plays the scenes in the real game and writes
# the picture frame by frame and the game's own sound effects; this script
# then lays the music under them (store/promo/music.wav, the full 30-second
# track the in-game loop was cut from, whose last four bars are the ending)
# and encodes the result. Takes a few minutes; a game window stays open
# meanwhile.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/Vinicius Costa/Desktop/Apps/Godot_v4.7.1-stable_win64.exe}"
SAVE="$APPDATA/Godot/app_userdata/Bee Bee/bee_bee_save.cfg"
mkdir -p build/promo/frames
touch build/.gdignore

# A take that reaches a skin's score would write it to the save file.
[ -f "$SAVE" ] && cp "$SAVE" build/promo/save_backup.cfg
"$GODOT" --path . --fixed-fps 60 --write-movie build/promo/audio.avi --resolution 540x960 \
	--script tools/godot/render_promo.gd 2>&1 | tee build/promo/render.log | grep PROMO
[ -f build/promo/save_backup.cfg ] && cp build/promo/save_backup.cfg "$SAVE"
grep -q "deaths 0 " build/promo/render.log || { echo "the autopilot died during a take: see render_promo.gd (--dry, --seeds)"; exit 1; }

# The movie writer starts with the engine; the first frame of the video is
# the engine frame the script printed.
LEAD=$(grep -o "first frame at engine frame [0-9]*" build/promo/render.log | grep -o "[0-9]*$")
OFFSET=$(python -c "print($LEAD / 60.0)")
ffmpeg -v error -y -framerate 60 -i build/promo/frames/f%05d.jpg -ss "$OFFSET" -i build/promo/audio.avi -i store/promo/music.wav \
	-filter_complex "[1:a]volume=1.6[sfx];[2:a]volume=0.62[music];[music][sfx]amix=inputs=2:normalize=0,alimiter=limit=0.84:level=disabled[a]" \
	-map 0:v -map "[a]" -t 30 -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -r 60 \
	-c:a aac -b:a 192k -movflags +faststart build/promo/BeeBee-promo.mp4
ls -la build/promo/BeeBee-promo.mp4
