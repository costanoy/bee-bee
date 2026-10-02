"""Bee Bee — checks an Android build before it goes anywhere.

  python tools/check_android_build.py [file.apk|file.aab ...]

With no arguments it checks the three builds the project makes:
  build/android/beebee-debug.apk     (the "Android" preset, debug)
  build/site/BeeBee.apk              (the "Android" preset, release-signed, for the site)
  build/android/beebee-release.aab   (the "Android Release" preset, for Google Play)

What it looks at, and why:
  * every 64-bit native library is laid out for 16 KB memory pages (Google
    Play refuses apps that target Android 15 or later and are not);
  * the manifest calls the app a game. As anything else, Android 16 ignores
    the portrait lock on tablets and foldables, and launchers file it away
    from the games;
  * the Android backup is allowed, so the record and the bees survive a
    change of phone;
  * package name, version and the Android versions it declares, printed to
    be read before an upload (Google Play refuses a version code it has
    already seen).

These come from export_presets.cfg, which is not in git: this is the way to
notice that the editor rewrote it.

APK manifests are read with aapt2 from the Android SDK; the bundle's
manifest is read directly.
"""
import glob
import os
import struct
import subprocess
import sys
import zipfile

DEFAULTS = [
    "build/android/beebee-debug.apk",
    "build/site/BeeBee.apk",
    "build/android/beebee-release.aab",
]
PACKAGE = "com.beebeegame.beebee"
PAGE_16K = 0x4000


def load_alignments(data):
    """The alignment of each loadable segment of an ELF file."""
    if data[:4] != b"\x7fELF":
        return None
    is64 = data[4] == 2
    if is64:
        (phoff,) = struct.unpack_from("<Q", data, 0x20)
        entsize, count = struct.unpack_from("<HH", data, 0x36)
    else:
        (phoff,) = struct.unpack_from("<I", data, 0x1C)
        entsize, count = struct.unpack_from("<HH", data, 0x2A)
    out = []
    for i in range(count):
        off = phoff + i * entsize
        if struct.unpack_from("<I", data, off)[0] != 1:      # PT_LOAD
            continue
        out.append(struct.unpack_from("<Q", data, off + 0x30)[0] if is64
                   else struct.unpack_from("<I", data, off + 0x1C)[0])
    return out


def check_libraries(z):
    problems = []
    found = 0
    for info in z.infolist():
        if not info.filename.endswith(".so"):
            continue
        aligns = load_alignments(z.read(info))
        if aligns is None:
            continue
        found += 1
        if "64" in info.filename and any(a < PAGE_16K for a in aligns):
            problems.append("%s is not aligned for 16 KB pages" % info.filename)
    return found, problems


# ---- the bundle's manifest: protobuf (aapt2's XmlNode), read by hand

def fields(buf):
    i = 0
    while i < len(buf):
        key = 0
        shift = 0
        while True:
            b = buf[i]
            i += 1
            key |= (b & 0x7F) << shift
            shift += 7
            if b < 0x80:
                break
        number, wire = key >> 3, key & 7
        if wire == 0:
            while buf[i] >= 0x80:
                i += 1
            i += 1
            yield number, None
        elif wire == 2:
            size = 0
            shift = 0
            while True:
                b = buf[i]
                i += 1
                size |= (b & 0x7F) << shift
                shift += 7
                if b < 0x80:
                    break
            yield number, buf[i:i + size]
            i += size
        elif wire == 1:
            i += 8
            yield number, None
        elif wire == 5:
            i += 4
            yield number, None
        else:
            return


def walk_node(buf, out):
    for number, value in fields(buf):
        if number == 1 and value is not None:                # element
            name = ""
            attrs = {}
            children = []
            for n, v in fields(value):
                if v is None:
                    continue
                if n == 3:
                    name = v.decode("utf-8", "replace")
                elif n == 4:
                    key = val = ""
                    for an, av in fields(v):
                        if av is None:
                            continue
                        if an == 2:
                            key = av.decode("utf-8", "replace")
                        elif an == 3:
                            val = av.decode("utf-8", "replace")
                    attrs[key] = val
                elif n == 5:
                    children.append(v)
            out.setdefault(name, attrs)
            for child in children:
                walk_node(child, out)


def manifest_of_bundle(z):
    elements = {}
    walk_node(z.read("base/manifest/AndroidManifest.xml"), elements)
    m = elements.get("manifest", {})
    sdk = elements.get("uses-sdk", {})
    app = elements.get("application", {})
    return {
        "package": m.get("package", "?"),
        "versionCode": m.get("versionCode", "?"),
        "versionName": m.get("versionName", "?"),
        "minSdk": sdk.get("minSdkVersion", "?"),
        "targetSdk": sdk.get("targetSdkVersion", "?"),
        "game": app.get("appCategory") == "game" and app.get("isGame") == "true",
        "category": app.get("appCategory", "?"),
        "backup": app.get("allowBackup") == "true",
    }


# ---- an APK's manifest: binary XML, read with aapt2

def find_aapt2():
    roots = [os.environ.get("ANDROID_HOME", ""), os.environ.get("ANDROID_SDK_ROOT", ""),
             os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk")]
    for root in roots:
        found = sorted(glob.glob(os.path.join(root, "build-tools", "*", "aapt2*")))
        if root and found:
            return found[-1]
    return None


CATEGORIES = {"0": "game", "1": "audio", "2": "video", "3": "image", "4": "social",
              "5": "news", "6": "maps", "7": "productivity", "8": "accessibility"}


def manifest_of_apk(path, aapt2):
    def run(*args):
        return subprocess.run([aapt2, "dump", *args, path], capture_output=True, text=True,
                              encoding="utf-8", errors="replace").stdout

    badging = run("badging")
    tree = run("xmltree", "--file", "AndroidManifest.xml")

    def badge(key):
        mark = key + "='"
        i = badging.find(mark)
        return badging[i + len(mark):badging.index("'", i + len(mark))] if i >= 0 else "?"

    def attr(name):
        for line in tree.splitlines():
            if ":" + name + "(" in line and "=" in line:
                return line.rsplit("=", 1)[1].strip()
        return "?"

    category = CATEGORIES.get(attr("appCategory"), attr("appCategory"))
    return {
        "package": badge("package: name"),
        "versionCode": badge("versionCode"),
        "versionName": badge("versionName"),
        "minSdk": badge("minSdkVersion:").strip("'") if "minSdkVersion:'" not in badging
        else badging.split("minSdkVersion:'")[1].split("'")[0],
        "targetSdk": badging.split("targetSdkVersion:'")[1].split("'")[0] if "targetSdkVersion:'" in badging else "?",
        "game": category == "game" and attr("isGame") == "true",
        "category": category,
        "backup": attr("allowBackup") == "true",
    }


def main():
    paths = sys.argv[1:] or [p for p in DEFAULTS if os.path.exists(p)]
    if not paths:
        print("no build found; pass the path of an .apk or .aab")
        return 1
    aapt2 = find_aapt2()
    failed = False
    for path in paths:
        print(path, "(%.1f MB)" % (os.path.getsize(path) / 1e6))
        z = zipfile.ZipFile(path)
        problems = []
        libraries, lib_problems = check_libraries(z)
        problems += lib_problems
        info = None
        if path.endswith(".aab"):
            info = manifest_of_bundle(z)
        elif aapt2:
            info = manifest_of_apk(path, aapt2)
        else:
            print("  aapt2 not found (Android SDK build-tools): manifest not checked")
        if info:
            print("  %s  version %s (code %s)  Android SDK %s to %s" % (
                info["package"], info["versionName"], info["versionCode"], info["minSdk"], info["targetSdk"]))
            if info["package"] != PACKAGE:
                problems.append("package is %s, expected %s" % (info["package"], PACKAGE))
            if not info["game"]:
                problems.append("declared as '%s', not as a game (package/app_category in the preset)" % info["category"])
            if not info["backup"]:
                problems.append("Android backup not allowed (user_data_backup/allow in the preset)")
        print("  %d native libraries, 16 KB pages: %s" % (libraries, "ok" if not lib_problems else "NOT ok"))
        if info:
            print("  declared as a game: %s    backup allowed: %s" % (
                "yes" if info["game"] else "NO", "yes" if info["backup"] else "NO"))
        for p in problems:
            print("  PROBLEM:", p)
        failed = failed or bool(problems)
    print("all good" if not failed else "PROBLEMS FOUND")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
