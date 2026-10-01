#!/usr/bin/env bash
# Builds the public test site into build/site/ (a plain static folder):
#   index.html, assets/   the landing page, copied from site/
#   play/                 the game exported for the browser ("Web" preset)
#   BeeBee.apk            a release-signed APK for sideloading ("Android" preset)
#
# Run from Git Bash, in the project folder:   bash tools/build_site.sh
#
# The APK is signed with the same key as the Play bundle (see
# tools/build_release.sh for where it lives). Its size is printed at the
# end: if it changes, update the "53 MB" in site/index.html.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/Vinicius Costa/Desktop/Apps/Godot_v4.7.1-stable_win64.exe}"
KEYS="../Bee Bee - chaves"
[ -f "$KEYS/beebee-release.keystore" ] || { echo "signing key not found in $KEYS"; exit 1; }

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(cd "$KEYS" && pwd -W)/beebee-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="beebee"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$KEYS/senha.txt")"

rm -rf build/site
mkdir -p build/site/play /c/jtmp
"$GODOT" --headless --path . --export-release "Web" build/site/play/index.html
# Gradle needs a short temp path on Windows.
TEMP='C:\jtmp' TMP='C:\jtmp' "$GODOT" --headless --path . --export-release "Android" build/site/BeeBee.apk
cp -r site/index.html site/assets build/site/
ls -la build/site build/site/play
