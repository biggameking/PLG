#!/usr/bin/env bash
# Kinbound release packager — export presets -> dist/kinbound-<ver>-<plat>.zip
# Usage: tools/package.sh [windows|web|all]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/Volumes/17333023680/Godot/Godot.app/Contents/MacOS/Godot}"
VER="$(grep -o 'application/product_version="[^"]*"' export_presets.cfg | head -1 | cut -d'"' -f2 || true)"
VER="${VER:-$(grep -o 'version/name="[^"]*"' export_presets.cfg | head -1 | cut -d'"' -f2 || true)}"
VER="${VER:-0.0.0}"
WHAT="${1:-all}"
mkdir -p dist
git rev-parse --short HEAD > dist/build.txt # ties shipped bytes to a commit

pack_windows() {
	rm -rf export/windows && mkdir -p export/windows
	"$GODOT" --headless --path . --export-release "Windows Desktop (Steam)" export/windows/kinbound.exe
	# zip refreshes in place — stale entries from a previous build would survive
	rm -f "dist/kinbound-$VER-windows.zip"
	(cd export/windows && zip -qr "$ROOT/dist/kinbound-$VER-windows.zip" . -x '.*')
	echo "dist/kinbound-$VER-windows.zip"
}
pack_web() {
	rm -rf export/web && mkdir -p export/web
	"$GODOT" --headless --path . --export-release "Web" export/web/index.html
	rm -f "dist/kinbound-$VER-web.zip" # same stale-entry trap as the windows zip
	(cd export/web && zip -qr "$ROOT/dist/kinbound-$VER-web.zip" index.*)
	echo "dist/kinbound-$VER-web.zip"
}
pack_android_debug() {
	mkdir -p export/android
	"$GODOT" --headless --path . --export-debug "Android" "export/android/kinbound-$VER-debug.apk"
	cp "export/android/kinbound-$VER-debug.apk" dist/
	echo "dist/kinbound-$VER-debug.apk"
}
# Release-signing contract (audit-69 M3): the preset's package/signed=true
# resolves its identity from the EXPORTING MACHINE's Editor Settings —
# a release APK built on another box signs with a different key and becomes
# store-unupdatable. Rule: release keystores live OUTSIDE VCS; whoever owns
# the release pins `keystore/release`, `keystore/release_user`,
# `keystore/release_password` in their LOCAL export_presets.cfg or Editor
# Settings before running an --export-release Android build. The debug APK
# above is unsigned-by-design and safe to build anywhere.
pack_android_release() {
	# guarded: refuse to sign with ambient editor defaults — the operator
	# must have pinned the release keystore locally (see contract above).
	if ! grep -q 'keystore/release="[^"]' export_presets.cfg \
			&& [ -z "${GODOT_ANDROID_RELEASE_KEYSTORE:-}" ]; then
		echo "refusing release build: pin keystore/release in the preset" \
			"or set GODOT_ANDROID_RELEASE_KEYSTORE" >&2
		exit 3
	fi
	mkdir -p export/android
	"$GODOT" --headless --path . --export-release "Android" "export/android/kinbound-$VER-release.apk"
	cp "export/android/kinbound-$VER-release.apk" dist/
	echo "dist/kinbound-$VER-release.apk"
}
case "$WHAT" in
	windows) pack_windows ;;
	web) pack_web ;;
	android) pack_android_debug ;;
	android-release) pack_android_release ;;
	all) pack_windows; pack_web; pack_android_debug ;;
	*) echo "usage: $0 [windows|web|android|all]" >&2; exit 2 ;;
esac
(cd dist && shasum -a 256 kinbound-*.zip kinbound-*.apk 2>/dev/null > SHA256SUMS)
cat dist/SHA256SUMS
ls -lh dist/
