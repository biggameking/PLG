#!/bin/bash
# Batch-render all 50 structure sprites — mirrors batch_mesh.sh:
# --python-exit-code on both stages so a Blender-side exception can't
# report a false "ok", per-id logs under render/logs/, WARN surfacing.
cd "$(dirname "$0")" || exit 1
mkdir -p render/logs
IDS=$(python3 -c "
import re
s=open('render_structure.py').read()
print(' '.join(re.findall(r'\"(\w+)\":\s*\{\"build\"',s)))")
fail=0
for sid in $IDS; do
  blender --factory-startup -b --python-exit-code 1 \
    -P render_structure.py -- "$sid" > "render/logs/$sid.log" 2>&1 || {
      echo "FAIL render $sid"; tail -5 "render/logs/$sid.log"; fail=1; continue; }
  python3 post_structure.py "$sid" >> "render/logs/$sid.log" 2>&1 || {
      echo "FAIL post $sid"; tail -5 "render/logs/$sid.log"; fail=1; continue; }
  grep -i "warn" "render/logs/$sid.log" | head -3
done
[ $fail -eq 0 ] && echo "batch: all ok" || echo "batch: FAILURES above"
exit $fail
