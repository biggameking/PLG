#!/bin/bash
# Batch-render all generated mesh_cfg_gen species through their source blends.
# Usage: bash tools/art/batch_mesh.sh
# Exit codes: 0 = all rendered+posted clean (warnings still reported),
# 1 = empty species list, 2 = one or more species failed.
set -u
cd "$(dirname "$0")"
TMP=$(mktemp -d /tmp/mesh_batch.XXXXXX)
python3 - <<EOF > "$TMP/list.txt"
import sys, os, re
sys.path.insert(0, ".")
from mesh_cfg_gen import CFG_EXT
for sid, cfg in CFG_EXT.items():
    print(sid + "|src/" + cfg["blend"])
# hand-tuned CFG entries live in render_src_asset.py — the blend only
# exists as a "# Xxx.blend" comment, so resolve basenames under src/.
# Include them so a hand-CFG regression can't slip past the batch tally
# (audit-53). fenjelly is the one comment-free entry → Sheep.blend.
blends = {}
for root, _, files in os.walk("src"):
    for f in files:
        if f.endswith(".blend"):
            blends[f] = os.path.join(root, f)
src = open("render_src_asset.py").read()
for sid, bname in re.findall(
        r'"([a-z0-9_]+)": \{\s*#\s*([A-Za-z0-9_]+\.blend)', src):
    if sid not in CFG_EXT and bname in blends:
        print(sid + "|" + blends[bname])
if "fenjelly" not in CFG_EXT:
    print("fenjelly|" + blends["Sheep.blend"])
EOF
n=0; fail=0
while IFS='|' read -r sid blend; do
  if blender --python-exit-code 1 -b "$PWD/$blend" -P render_src_asset.py -- "$sid" >"$TMP/$sid.log" 2>&1; then
    if python3 post_kin.py "$sid" >"$TMP/post_$sid.log" 2>&1; then
      n=$((n+1)); echo "ok $sid"
    else
      fail=$((fail+1)); echo "FAIL(post) $sid (see $TMP/post_$sid.log)"
    fi
  else
    fail=$((fail+1)); echo "FAIL $sid (see $TMP/$sid.log)"
  fi
  # WARN-quality degradations (eyeless/static/mat_map misses) still count ok —
  # surface them so they can't hide inside the success tally
  if grep -q "WARN" "$TMP/$sid.log"; then
    echo "  WARN $sid: $(grep 'WARN' "$TMP/$sid.log" | head -3 | tr '\n' '|')"
  fi
done < "$TMP/list.txt"
[ "$n" -eq 0 ] && [ "$fail" -eq 0 ] && { echo "EMPTY LIST — mesh_cfg_gen broken"; exit 1; }
echo "batch done: $n ok, $fail failed"
[ "$fail" -gt 0 ] && exit 2
exit 0
