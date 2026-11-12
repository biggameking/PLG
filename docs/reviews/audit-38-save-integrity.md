# audit-38 — save integrity & hostile input — VERIFIED CLEAN

Lens: `user://savegame.plg` is untrusted input. `load_game` (game.gd ~4390-4900)
consumes a hand-craftable `store_var` dict; `Migrate.save_dict` runs first.
Threat model: crash, free power beyond self-cheat, or smuggled state that
breaks later ticks. Solo save-editing is out of scope (unsigned local file by
definition — the gates exist to keep corrupt/migrated/hostile *shapes* from
bricking the load or poisoning runtime).

## Verdict: no must-fix findings

The path is launch-grade already — every field class has a dedicated guard:

- **Door checks**: dict type, required-field presence, `v > SAVE_VER` refusal,
  `_fin(seed)` before the typed `generate()` parameter, per-field type gate.
- **Roster (kin/party/rparties)**: species whitelist → `ownable()` gate on all
  non-wild modes (forged ironpact/human rows rejected) → mode whitelist →
  position OOB re-anchor → per-stat clamps (lv 1-60, hp, talent, star ≤4 —
  pow overflow guarded, san, hunger, soul_boost ≤10, bounty ≤999, phase 1-2)
  → flag coercion (raid only on wild, fav/alpha/boss real-bool only,
  ailment/stance/sex/passives/extra_skills whitelists, carry shape).
- **Derived flags can't be forged**: `crowned` re-derives from
  `spires_done.size() >= SPIRE_DEFS`; `accord` re-derives from crown + EX seal
  + heir ledger; `dex_full` re-derives from the catch ledger. A bare `true`
  in the save means nothing without the seals.
- **Structures**: cell-key parse, sid whitelist, OOB footprint refusal,
  texture fallback, hp/timer/fert/exp clamps, `store` count floor,
  `egg_parents`/`egg_inc` pair normalization + owner-column cap +
  MAX_EGG_QUEUE, `cap`/`captive`/`mimic`/`loot` shape checks.
- **Collections bounded at load**: MAX_STRUCTURES, MAX_RESPAWNS,
  MAX_CRAFT_QUEUE, MAX_REMOTE_TAGS, MAX_EXTRA_BOXES, mission_flags 64-cap,
  party dedup + cap, remote-party uid dedup.
- **Migrate is guard-first**: every container `is`-checked before iteration;
  `rid()` is total on foreign types.
- **Player**: pos OOB/blocked re-anchor (softlock refusal), vitals clamped,
  max_hp re-derived, meal buffs key-whitelisted + clamped, equip per-slot
  whitelist with wear clamps.

## Info-level notes (not defects)

- `items` counts floor at 0 but have no ceiling — a forged save can carry
  2^60 of anything. Self-cheat only; float64/int64 consumers don't overflow.
- `catch_counts` is the ledger the Accord re-derives from — a forged save CAN
  write every LEGENDARY_DEN species and grant itself the seals. Again
  self-cheat; the re-derivation correctly stops *migrated* saves from lying.
- `merchant_deaths` clamps to 0..100 — a fresh exploit window opens at
  deaths≥8 regardless (floor of 4g stays). Bounded, documented.

## Process note

Two background cold-audit subagents ran ~25min and returned fragmented/empty
final reports — the audit's enumeration work happened but its written verdict
never landed. This report is therefore the maintainer's own line-by-line walk
of every load section (door → collections → structures → roster → player),
which found the surface already clean. Lesson recorded in devrules: for
audit-report tasks prefer foreground subagents or require the agent to write
its findings to a file — background completions truncate reports.
