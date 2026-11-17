# audit-66 — S113/S114/S115 harness deep re-review

**Verdict**: NEEDS-FIX → 5 MED + 12 LOW, all fixed and re-verified.
Delayed-return cold agent; static-only analysis (no exec), flagged
assumptions verified by re-running every harness after the fixes.

## MED — all fixed

1. **`raid_walkthrough.gd` dead disjunct**: `item_count("ancient_relic")`
   — the id never existed; boss currency is `ancient_part` (2-4 to
   inventory via `_kill_loot`). → `ancient_part`; first live run showed
   `part=6` proving the inventory lane, not just spec-table drops.
2. **`save_walkthrough.gd` F5-existence gate vacuous**: passed whenever
   any save existed. → md5 of the save bytes before/after the key tap.
3. **Corrupt-save gate lacked a canary**: `state == "title"` alone would
   pass a post-validation reject that left the world half-rebuilt. →
   `day = 55` canary asserted alongside title state.
4. **Parse-pin blind spot** (`smoke_test.gd`): a renamed/deleted harness
   emits a different signature than SCRIPT ERROR → pin passed vacuously.
   → `FileAccess.file_exists` added to the same check.
5. **Save backup was RAM-only**: a mid-run crash would eat the real save.
   → spill to `user://savegame.plg.savbak` at boot; restore from disk.

## Fixes that caught live bugs in the fix run itself

- **6-entry message ring**: baseline-index scanning `range(base, size)`
  read nothing once the buffer was full (audit-66's own suggestion,
  wrong for a bounded ring). → assert `load_arm > t` (the real arm
  field) + scan only the buffer tail.
- **Fresh uids on load**: `find_pal(pal_uid)` is permanently null after
  reload — `party_idx` maps positionally and new pals mint new uids.
  → roster gate asserts `party[0]` resolves to species+mode, not the
  dead uid.

## LOW — fixed

- ROADMAP "F5"/"16 门" → F1 is the shipped binding; count is 15 gates
  + 1 conditional binding guard.
- `CONTINUE resumes` gained the tod assert (99.0 poke was dead weight).
- `_fight_spot` return cell now verified `blocked`; warden pick prefers
  a boss with a reachable+los spot (grotto wardens spawn sealed in
  rock rings — first `q.boss` isn't a reachability promise).
- `_world_px` restores the elevation term (`elev_at`), matching
  loop_walkthrough's projection.
- `_stand_spot` rejects spots past the interact probes' reach
  (2.2 struct / 2.4 merchant) instead of returning a cell E can't use.

## Accepted notes

- atk_cd resets and hp caps are disclosed fixture assists; gates prove
  mechanics, not fight balance — recorded, not a defect.
- Shared scaffold duplication (~40%) across 5 harnesses is real; a
  `wt_common` base-class extraction is a candidate stage, deferred —
  the drift bugs are fixed in place first.
- get_var ERROR log on the corrupt blob is the expected fail-closed
  rejection path, not a crash.

## Re-verification

SAVE-LOOP 0 failures · RAID-LOOP 0 failures · ECON-LOOP 0 failures ·
smoke **1004 checks, 0 failures, 0 skipped**.
