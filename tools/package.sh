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
case "$WHAT" in
	windows) pack_windows ;;
	web) pack_web ;;
	all) pack_windows; pack_web ;;
	*) echo "usage: $0 [windows|web|all]" >&2; exit 2 ;;
esac
(cd dist && shasum -a 256 kinbound-*.zip > SHA256SUMS)
cat dist/SHA256SUMS
ls -lh dist/
