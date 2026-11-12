# Audit 40 — boss / spire / gauntlet / raid / endgame mechanics

**Lens:** the last un-audited major gameplay surface — spire guardians, pact
phase transitions, gauntlet trials, den respawns, raid waves, legendary heirs,
Crowned/Accord reachability.
**Method:** fresh context-free subagent source audit → every finding verified
against production code → fixes shipped with real-path smoke assertions.
**Result:** 1 HIGH, 4 MED, 4 LOW/review items → all closed. 922 checks, 0
failures, 0 skipped; `SIM: 0 failures`.

## Findings → fixes

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | **HIGH** | `load_game` clamped saved `hp` against the pre-bonus `max_hp`, then `apply_bonuses()` re-derived the real max — every alpha/boss/star/lucky/soul-boosted kin silently lost its multiplier share of HP on each reload (an 8x guardian relogged at 1/8 health; could also flip a boss's phase state) | hp is captured raw and clamped **after** `apply_bonuses()`; missing field heals full under the real max. Pattern follows `Kin.condense()` |
| 2 | MED | `take_dps()` never checked the 50% phase gate — burn/poison could carry a boss straight to death without `enter_phase_two()` | the gate is shared: any damage path crossing the threshold with hp > 0 fires phase 2 (symmetric damage rule, rule 40) |
| 3 | MED | mid-gauntlet save/load could strand a boss-flagged raider forever — uncatchable, permanent, sleep-blocking (`danger_active`) | the 240s raider sweep now retires any wild raider when no trial is live; while a trial lives it still spares gauntlet kin. Sweep extracted to `tick_raider_sweep()` so tests drive the real rule |
| 4 | MED | a phase-2 boss that de-aggros and leashes home stayed `phase == 2` → `danger_active()` + drone music forever | danger now requires engagement (`aggro >= 0 or aggro_pid > 0`); a dormant enraged boss is quiet until it re-engages. Phase itself persists — re-engaging resumes the pact, no reset exploit |
| 5 | LOW | raid spawn loops and `summon_raid()` could append past `MAX_PALS` (the cap is also a CPU guard) | spawn loop breaks at cap; the horn refuses with a logged reason |
| 6 | LOW | a guardian whose `spire_tag` was empty (pre-stag save, forged row) could be killed with no progress — permanent Crowned/Accord wall | position fallback: an untagged boss dead within 8 cells of an unclaimed spire records that tag |
| 7 | LOW | `raid_t` and per-kin `rt0` were not range-coerced on load — negative `rt0` produced raiders that never expire, huge `raid_t` fired raids mid-load | `raid_t` clamped [0,600]; `rt0` clamped [0,600] before subtracting from `t` |
| 8 | review | `crowned` was `saved_flag AND all_tags` — a merged/corrupted flag could dethrone a finished campaign | `crowned` now **re-derives** from `spires_done.size() >= SPIRE_DEFS.size()` — same forge-resistance (tags must still validate) plus self-healing |
| 9 | review | repeated catch → KO-overflow → rewild → re-kill could stack duplicate `boss_respawns` rows → twin heirs from one den | den dedup: same sid within 4 cells of an existing queued row refuses the append |
| 10 | review | phase-2 adds inherit the boss's species; legendary-species adds were permanent + uncatchable litter | adds now carry `raid` + `raid_t0` — the sweep retires them like any temporary invader; catchability still answers to `acquirable()` unchanged |
| 11 | nit | comment claimed all raiders stay catchable — ironpact humans are not | comment corrected (`ownable=false`) |

## Smoke assertions added/updated

- `a flagged kin keeps its hp across the load` — alpha+boss kin at 0.6 hp
  fraction round-trips; the old order would land ~0.1
- `DoT triggers the phase gate` — `take_dps` across 50% fires phase 2
- `an orphaned raid boss is swept` / `a live trial keeps its raiders`
- updated sweep fixture: `spares gauntlet kin` (live trial), `clears a plain
  raider`, **new** `an orphaned gauntlet raider retires`
- `a dormant phase-2 boss adds no danger` / `an engaged phase-2 boss is danger`
- `the horn refuses at MAX_PALS`
- `an untagged guardian still records its spire`
- `hostile raid_t coerced on load` / `a negative rt0 can't pin a raider`
- `the crown re-derives from the ruins` (forged save: 5 tags + crowned:false
  → crowned)

## Design notes

- **Phase-2 persists by design** — only the *danger signal* is engagement-
  gated. Resetting to phase 1 on leash would allow hp-threshold re-farming of
  the phase transition and contradicts the "enraged stays enraged" fiction.
- **Mid-gauntlet save policy**: trial state itself isn't serialized; the
  survivor side-effects (live raiders) are now bounded by the same sweep that
  retires any invader — no orphaned permanents, no phantom rewards.
- **Coordinate-system note for fixtures** (carried from audit-37): `structures`
  keys, `kinbox_pos`, `spire_pos` are tile coords (Vector2i); `pos`/`home` are
  world coords — fixtures must convert or the proximity gates never see them.
