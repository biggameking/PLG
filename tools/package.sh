#!/usr/bin/env bash
# Kinbound release packager — export presets -> dist/kinbound-<ver>-<plat>.zip
# Usage: tools/package.sh [windows|web|all]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/Volumes/17333023680/Godot/Godot.app/Contents/MacOS/Godot}"
VER="$(rg -o 'version/name="[^"]+"' export_presets.cfg | head -1 | cut -d'"' -f2)"
VER="${VER:-0.0.0}"
WHAT="${1:-all}"
mkdir -p dist

pack_windows() {
	"$GODOT" --headless --path . --export-release "Windows Desktop (Steam)" export/windows/kinbound.exe
	(cd export/windows && zip -q "$ROOT/dist/kinbound-$VER-windows.zip" kinbound.exe)
	echo "dist/kinbound-$VER-windows.zip"
}
pack_web() {
	"$GODOT" --headless --path . --export-release "Web" export/web/index.html
	(cd export/web && zip -qr "$ROOT/dist/kinbound-$VER-web.zip" .)
	echo "dist/kinbound-$VER-web.zip"
}
case "$WHAT" in
	windows) pack_windows ;;
	web) pack_web ;;
	all) pack_windows; pack_web ;;
	*) echo "usage: $0 [windows|web|all]" >&2; exit 2 ;;
esac
ls -lh dist/
