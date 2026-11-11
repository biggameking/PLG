#!/bin/sh
# S1 acceptance: no Palworld-identifying term may survive in shipped files
# (src/, prototype/, locale/, store/, project.godot, export_presets.cfg).
# docs/ and tools/ test fixtures legitimately contain old ids as migration
# payloads — tools/ is excluded from the PCK by the preset exclude_filter.
cd "$(dirname "$0")/.."
PAT='palworld|palapagos|paldium|paldeck|palbox|pal_sphere|pal_egg|pal_bait|pal_fluid|lamball|anubis|jetragon|chikipi|frostallion|paladius|necromus|cremis|daedream|mozzarina|cattiva|elphidran|quivern|suzaku|jormuntide|blazamut|astegon|lifmunk|foxparks|pengullet|penking|relaxaurus|grizzbolt|eikthyrdeer|rayne syndicate|帕鲁'
SCOPE="src/ prototype/ locale/ store/ project.godot export_presets.cfg"
HITS=$(rg -io "$PAT" $SCOPE -g '!migrate.gd' -g '!rename_ip.py' | wc -l | tr -d ' ')
if [ "$HITS" -eq 0 ]; then echo "IP CHECK: CLEAN"; else echo "IP CHECK: $HITS hits"; rg -io "$PAT" $SCOPE -g '!migrate.gd' -g '!rename_ip.py' | head -20; exit 1; fi
