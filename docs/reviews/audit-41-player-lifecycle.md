# Audit 41 — player lifecycle & survival systems

**Lens:** the last un-audited player-facing mechanics cluster — death/respawn,
hunger/stamina/SAN, meals/buffs, perks/statues, settings persistence, audio
routing, corpse-bag lifecycle.
**Method:** fresh context-free subagent source audit → all findings verified →
fixes shipped with real-path smoke assertions.
**Result:** 3 MED, 4 LOW, 8 INFO → all actionable items closed. 932 checks,
0 failures; SIM: 0 failures.

## Findings → fixes

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | **MED** | `soul_boost` never rode `pal_state_pack` — replica mirrors sat at 0, so guest infuse quotes charged `1+stale` instead of `1+real` (mini() receipt-cap made the under-charge permanent; burst clicks compounded it) | soul_boost is pack field [13] → spawn shape [12]; `spawn_net_pal` + `pal_sync` live-update consume it; drift-heals every 2Hz tick |
| 2 | **MED** | `perks`/`stat_pts` loaded with `_i()` but no 0-5 clamp — the one progression dict without a boundary check; forged `"hp":9999` → ~120k max_hp, 800× melee | `perks[pk] = clampi(…, 0, 5)` — the grant cap now binds the load path too |
| 3 | **MED** | `equip` set wear to full `dur` unconditionally — unequip→re-equip was a free repair, bypassing the paid `repair_quote_for` economy | `wear_by_id` dict on Game: unequip banks wear under the item id, equip resumes it, `break_*` erases it; serialized as `"wearmap"` with ITEMS-whitelist + finite coercion |
| 4 | LOW | guests could loot host corpse bags — `mine` wasn't on the wire and `take_drop` never checked it (comment claimed owner-only) | `take_drop` refuses `mine` rows — owner + haulers only |
| 5 | LOW | corpse-bag scatter (up to 1.2 cells) could land inside solid terrain → permanently unreachable, permanently occupying a drop slot | scatter routes through `nearest_free` |
| 6 | LOW | MAX_DROPS backstop evicted `drops.front()` when all 400 slots were mine-flagged — "never a corpse bag" was false under saturation | all-mine saturation now refuses the new drop instead of eating a grave |
| 7 | LOW | `raze_structure` kinbox branch hard-reset `kinbox_pos` while an outpost survived — dead code today (1hp floor) but a maintenance trap | `_kinbox_anchor_gone(cells)` helper — one promote/forget rule for demolish, net teardown, and raid raze |
| 8 | INFO | forged `hp:0` loaded a walking-dead player (floored at 0) | floor is now 1 — honest saves always write >0 |
| 9 | INFO | `player.hunger` (satiety, 100→0) vs `Kin.hunger` (accumulates 0→100) share a name with opposite polarity — copy-paste footgun | polarity hazard documented at the field decl |
| — | INFO | dead `from:` param on `hurt_player`, dead `san:15` field on cake, unreachable respawn guard in `skill_hit`, unclamped `xp_gain` on the trusted-authority lane | documented, no change — nil player impact |

## Verified safe (spot-checked, no defect)

- Single death funnel: melee / skill mirror / direct `skill_hit` all route
  through `apply_player_damage`; environmental DoT floors at 1hp
- `respawn_player`: guests skip the spill, mount release coherent on both
  sides, `death_marks` capped at 3, `nearest_free` spiral r≤7
- Starvation→KO→box→revive loop stable (audit-35/39 fixes hold); box-mode
  kin skip `tick_needs` entirely
- Meal replace-not-stack semantics; `player_status` wire whitelist; perk
  grant/refund caps; `capture_level` consumed only through clamped
  `catch_chance`
- Settings — every persisted key reaches a consumer (buses, locale, touch,
  fullscreen, raid gate); `load_settings` coerces per key
- Audio — fixed 8-player pool, lazily-cached synth streams, `audio_live`
  gate, crossfade + `net_danger` mirror all wired
- Starvation/box/revive, worker SAN/hunger/sleep gates consistent across
  all six call sites

## Smoke assertions added

- `soul_boost rides the wire` + `the replica prices infusions honestly`
- `forged perks clamp at the door` + `a dead-man save can't walk in at zero`
- `re-equipping is not a repair` (wear=7.0 survives the round trip)
- `a guest can't loot a corpse bag` + `...but the plain bag pays out`
- `a full-mine flood can't eat a grave`
- `a razed anchor promotes its outpost` + `...and the last box leaves no anchor`
