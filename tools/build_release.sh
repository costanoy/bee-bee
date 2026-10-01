#!/usr/bin/env bash
# Builds the signed release bundle for Google Play:
#   build/android/beebee-release.aab
#
# Run from Git Bash, in the project folder:   bash tools/build_release.sh
#
# The signing key lives OUTSIDE the repository, in "../Bee Bee - chaves":
#   beebee-release.keystore   the key (alias "beebee")
#   senha.txt                 its password
# Lose that folder and the game can no longer be updated on Google Play
# without asking Google to reset the upload key. Keep a backup of it.
#
# The "Android Release" preset in export_presets.cfg (not in git) holds the
# rest: bundle format, both ARM architectures, version code and name. Raise
# version/code there by one for every upload to Google Play.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/Vinicius Costa/Desktop/Apps/Godot_v4.7.1-stable_win64.exe}"
KEYS="../Bee Bee - chaves"
[ -f "$KEYS/beebee-release.keystore" ] || { echo "signing key not found in $KEYS"; exit 1; }

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(cd "$KEYS" && pwd -W)/beebee-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="beebee"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$KEYS/senha.txt")"

# Gradle needs a short temp path on Windows.
mkdir -p /c/jtmp
TEMP='C:\jtmp' TMP='C:\jtmp' "$GODOT" --headless --path . --export-release "Android Release" build/android/beebee-release.aab
ls -la build/android/beebee-release.aab
