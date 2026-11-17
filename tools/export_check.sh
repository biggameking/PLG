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
	# an artifact existing does not mean the run was clean
	if grep -q "ERROR:" "$OUT/log-$name.txt"; then
		echo "FAIL $name log has ERROR lines (see $OUT/log-$name.txt)"
		fails=$((fails + 1))
	fi
}

rm -f "$OUT/web"/index.* # stale bundle siblings must not satisfy the check
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
# apk must be a whole zip, not a partial write — signature was verified
# manually in S111 (apksigner); integrity is the automatable half
if [ -s "$OUT/android/Kinbound-debug.apk" ] \
	&& ! unzip -t "$OUT/android/Kinbound-debug.apk" > /dev/null 2>&1; then
	echo "FAIL android artifact fails zip integrity"; fails=$((fails + 1))
fi
if [ -s "$OUT/android/Kinbound-debug.apk" ] \
	&& ! unzip -l "$OUT/android/Kinbound-debug.apk" | grep -q "META-INF/.*\.RSA\|META-INF/.*\.SF"; then
	echo "FAIL android artifact carries no signature block"; fails=$((fails + 1))
fi
echo "==== EXPORT: $fails failures ===="
exit $fails
