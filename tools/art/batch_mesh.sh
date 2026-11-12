#!/bin/bash
# Batch-render all generated mesh_cfg_gen species through their source blends.
# Usage: bash tools/art/batch_mesh.sh
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
  if blender -b "$PWD/src/$blend" -P render_src_asset.py -- "$sid" >"/tmp/mesh_$sid.log" 2>&1; then
    n=$((n+1)); echo "ok $sid"
  else
    fail=$((fail+1)); echo "FAIL $sid (see /tmp/mesh_$sid.log)"
  fi
done < /tmp/mesh_batch_list.txt
echo "batch done: $n ok, $fail failed"
