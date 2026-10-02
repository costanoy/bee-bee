#!/usr/bin/env bash
# Builds the public test site (https://beebee.cyberhat.com.br, on Hostinger)
# into build/site/, a plain static folder, and zips it as build/BeeBee-site.zip:
#   index.html, assets/   the landing page, copied from site/ (its "%APK_MB%"
#                         becomes the size of the APK that was just built)
#   privacidade.html      the privacy policy, from store/privacy_policy.md
#   .htaccess             MIME types, compression and caching for the host
#   play/                 the game exported for the browser ("Web" preset)
#   BeeBee.apk            a release-signed APK for sideloading ("Android" preset)
#
# Run from Git Bash, in the project folder:   bash tools/build_site.sh
#
# The APK is signed with the same key as the Play bundle (see
# tools/build_release.sh for where it lives).
#
# The page's pictures and trailer are not made here: after re-rendering the
# store screenshots or the promo video, run tools/make_site_assets.py first.
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
cp -r site/.htaccess site/assets build/site/
APK_MB=$(python -c "import os; print(round(os.path.getsize('build/site/BeeBee.apk') / 1e6))")
sed "s/%APK_MB%/$APK_MB/g" site/index.html > build/site/index.html
python tools/make_privacy_page.py build/site/privacidade.html
# Godot scans build/ like any other folder and leaves .import files next to
# the exported icons; .gdignore stops that, and the strays are not shipped.
touch build/.gdignore
find build/site -name "*.import" -delete
# One archive to upload and extract in the site's folder on the host.
rm -f build/BeeBee-site.zip
python -c "
import os, zipfile
z = zipfile.ZipFile('build/BeeBee-site.zip', 'w', zipfile.ZIP_DEFLATED)
for d, _, fs in os.walk('build/site'):
    for f in fs:
        p = os.path.join(d, f)
        z.write(p, os.path.relpath(p, 'build/site'), zipfile.ZIP_STORED if f.endswith(('.apk', '.webp', '.png')) else zipfile.ZIP_DEFLATED)
z.close()"
ls -la build/site build/site/play build/BeeBee-site.zip
