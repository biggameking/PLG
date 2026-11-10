#!/bin/sh
# S1 acceptance: no Palworld-identifying term may survive in shipped files.
# Returns 0 + CLEAN when the old lexicon is fully gone.
cd "$(dirname "$0")/.."
HITS=$(rg -io 'palworld|palapagos|paldium|paldeck|palbox|pal_sphere|pal_egg|pal_bait|pal_fluid|lamball|anubis|jetragon|chikipi|frostallion|paladius|necromus|cremis|daedream|mozzarina|cattiva|elphidran|quivern|suzaku|jormuntide|blazamut|astegon|lifmunk|foxparks|pengullet|penking|relaxaurus|grizzbolt|eikthyrdeer|rayne syndicate' \
  -g '!*.import' -g '!migrate.gd' -g '!rename_ip.py' -g '!check_ip.sh' -g '!*.png' -g '!ROADMAP.md' | wc -l)
if [ "$HITS" -eq 0 ]; then echo "IP CHECK: CLEAN"; else echo "IP CHECK: $HITS hits"; fi
