#!/bin/bash
# Batch-render all generated mesh_cfg_gen species through their source blends.
# Usage: bash tools/art/batch_mesh.sh
# Exit codes: 0 = all rendered+posted clean (warnings still reported),
# 1 = empty species list, 2 = one or more species failed.
set -u
cd "$(dirname "$0")"
python3 - <<'EOF' > /tmp/mesh_batch_list.txt
import sys, os
sys.path.insert(0, ".")
from mesh_cfg_gen import CFG_EXT
for sid, cfg in CFG_EXT.items():
    print(sid + "|" + cfg["blend"])
EOF
n=0; fail=0
while IFS='|' read -r sid blend; do
  if blender --python-exit-code 1 -b "$PWD/src/$blend" -P render_src_asset.py -- "$sid" >"/tmp/mesh_$sid.log" 2>&1; then
    if python3 post_kin.py "$sid" >"/tmp/mesh_post_$sid.log" 2>&1; then
      n=$((n+1)); echo "ok $sid"
    else
      fail=$((fail+1)); echo "FAIL(post) $sid (see /tmp/mesh_post_$sid.log)"
    fi
  else
    fail=$((fail+1)); echo "FAIL $sid (see /tmp/mesh_$sid.log)"
  fi
  # WARN-quality degradations (eyeless/static/mat_map misses) still count ok —
  # surface them so they can't hide inside the success tally
  if grep -q "WARN" "/tmp/mesh_$sid.log"; then
    echo "  WARN $sid: $(grep 'WARN' "/tmp/mesh_$sid.log" | head -3 | tr '\n' '|')"
  fi
done < /tmp/mesh_batch_list.txt
[ "$n" -eq 0 ] && [ "$fail" -eq 0 ] && { echo "EMPTY LIST — mesh_cfg_gen broken"; exit 1; }
echo "batch done: $n ok, $fail failed"
[ "$fail" -gt 0 ] && exit 2
exit 0
