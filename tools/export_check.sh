#!/bin/bash
# S111 export gate — exercises every export preset for real.
# Usage: tools/export_check.sh [outdir]   (default /tmp/plg-export)
# Pass criteria per preset:
#   Windows Desktop (Steam) -> PE32+ exe, nonzero size
#   Web                     -> index.html + index.wasm + index.pck
#   Android (debug)         -> signed APK (release needs the owner keystore — out of scope)
# Any failure prints FAIL and exits 1.
set -u
GODOT="/Volumes/17333023680/Godot/Godot.app/Contents/MacOS/Godot"
OUT="${1:-/tmp/plg-export}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT/web" "$OUT/android"
fails=0

run() { # name preset outfile mode
	local name="$1" preset="$2" file="$3" mode="$4"
	rm -f "$file"
	"$GODOT" --headless --path "$ROOT" "$mode" "$preset" "$file" \
		> "$OUT/log-$name.txt" 2>&1
	if [ -s "$file" ]; then
		echo "PASS $name -> $file ($(stat -f%z "$file") bytes)"
	else
		echo "FAIL $name (see $OUT/log-$name.txt)"
		fails=$((fails + 1))
	fi
}

run windows "Windows Desktop (Steam)" "$OUT/Kinbound.exe" --export-release
run web "Web" "$OUT/web/index.html" --export-release
run android "Android" "$OUT/android/Kinbound-debug.apk" --export-debug

# web bundle completeness — the shell alone is not a game
if [ -s "$OUT/web/index.html" ]; then
	for f in index.wasm index.pck index.js; do
		if [ ! -s "$OUT/web/$f" ]; then
			echo "FAIL web bundle missing $f"; fails=$((fails + 1))
		fi
	done
fi
# exe must actually be a PE binary, not a stray file
if [ -s "$OUT/Kinbound.exe" ] && ! file "$OUT/Kinbound.exe" | grep -q "PE32+"; then
	echo "FAIL windows artifact is not PE32+"; fails=$((fails + 1))
fi
echo "==== EXPORT: $fails failures ===="
exit $fails
