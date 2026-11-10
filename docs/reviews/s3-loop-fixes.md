# S3 gameplay corrections — external review (commit 47587b0)

Reviewer: fresh-context subagent, read-only code audit.

## CRITICAL findings and resolutions

| # | Finding | Fix |
|---|---|
| C1 | Legendaries sat in the ordinary zone pools — the hatch filter was one gate on a dozen leaks: wild spawns (incl. alpha/lucky herds), boss lairs, den honor guards, merchant black-market, cage rescues, migrations, raid rosters, gauntlet waves, fishing, and three breed combos all produced catchable or ownable legends | Single canonical gate `acquirable()` + `acq_pool()` (game.gd:~653); every spawn site routed through it — raids filter LEGENDARY only (Iron Pact humans are intended raiders); den/grotto/sigil bosses still pick LEGENDARY_DEN deliberately |
| C2 | The "no humans" egg filter checked `spec.get("body")` — a key the ironpact species don't carry (their body lives in `SpeciesData.BODY` via `body_of()`); the smoke check reused the same wrong predicate and could never fail | `hatch_pool` now uses `acquirable()` → `body_of()`; smoke asserts invariants against data (den list, `body_of`, `BREED_COMBOS.values()`), not against the production predicate |
| C3 | `BREED_COMBOS` output 3 legendaries (`wyrmhoof`, `vermtrot`, `scalcrest`) plus 3 humans (`terrkin` ×2, `shadesmith`) | Outputs retargeted to non-legendary same-element species (noctfang/grithoof/ripwrith/frostfang/sparkhaunt); hatch gates the resolved child through `acquirable()` as belt-and-braces |

## LOW findings and resolutions

| # | Finding | Fix |
|---|---|
| L1 | Peaceful toggle froze an armed raid silently (`raid_warned` stayed true) | Disabling raids now pins `raid_t` via `RAID_WARN_T + 1` and clears `raid_warned`/`raid_theme`; threshold shares the `RAID_WARN_T` const |
| L2 | `pal_state_pack` didn't send `boss` — clients saw den bosses as ordinary kin (label and orb-immunity only cosmetic-server-side) | Wire shape extended; `spawn_net_pal` restores `boss` from index 7 |
| L3 | `spec.get("boss")` dead code, `legendary_orb` name drift | Accepted: dead guard is harmless; orb stays "best orb" |

## Process lessons (durable)

1. Enumerate before you gate — list every creation site, then place one canonical pool.
2. Smoke checks assert invariants against DATA, never reuse the production predicate (tautological tests certify nothing).
3. Filter fields must exist — prefer existing accessors when the data has two representations.
4. Toggles own their state transitions — armed flags must be defined on re-enable.
