# audit-32 — mid-game progression sweep (context-free review + fixes)

Scope: the kinbox → mission 2-10 → base economy → zone 2/3 → first boss →
spires → gauntlet → crown → accord chain. Lens: progression reachability
and exploit surfaces, same probe method as audit-30 but one arc later.

## Findings and dispositions

| # | Severity | Finding | Disposition |
|---|----------|---------|-------------|
| C1 | Critical | `gauntlet_sigil` had no first source — awarded only inside `tick_gauntlet`'s own reward loop, but required to *start* the trial. Mission 10, the sigil reward chain, the Wildmere Accord, and the 6th party slot were all unreachable. | **Fixed.** `record_spire()` pays 1 sigil per broken spire (idempotent — a doubled call can't mint two). Merchant stock carries a 10% `gauntlet_sigil` listing at 120g as a gold-path fallback. |
| H1 | High | Gauntlet raiders rode the generic 240s stale-raider sweep — kiting a wave until it timed out decremented `gauntlet["left"]` and paid the trial for free. | **Fixed.** The sweep skips `has_meta("gauntlet")` kin; `tick_gauntlet()` reconciles `left` against live raiders each tick — shrink to truth, void on empty, never silent-pay. |
| H2 | High | Ranch parentage was FIFO over a shared `kin_egg` id — a wild egg could claim a queued pairing, and a real bred egg could lose it. | **Fixed.** New item id `bred_kin_egg`; ranch lays it, `deposit_egg`/`egg_req_remote` claim parentage only for it. Legacy saves: `kin_egg` inside a ranch store migrates to `bred_kin_egg` on load (only pairings ever write a ranch store). |
| M4 | Medium | Automated production stores were hostage to a staffed hauler — no hauler, no output. | **Fixed.** Host E on any automated site empties the store into the bag (overflow follows `add_item` spill rules); guests get a refusal — replica stores never drain locally. |
| M2 | Medium | A spire that failed strict AND relaxed placement silently never spawned — campaign could ship uncompletable on a cursed seed. | **Fixed.** Third fallback pass: any free standable cell *with a valid door approach*; a spire that still can't place logs a loud warning, not a silent hole. |
| M1 | Medium | Spires were invisible on the map — the campaign spine had no trail. | **Fixed.** `spire_pos` recorded at worldgen, serialized as `spos` (tag-validated, in-bounds coercion), self-heals by guardian derivation on pre-spos saves, and pings violet on the minimap over charted ground (hollow once broken). |
| L1 | Low | Relaxed placement could seat a guardian behind a cliff — the south door opening onto unclimbable rock gates the first boss. | **Fixed.** All three passes now require `(tx,ty+3)` unblocked at matching elevation; smoke asserts the invariant over every placed spire. |
| — | Info | Mission polling, kinbox anchors, KO/death persistence, spire save validation, ancient-part/lumenite sources, merchant bypasses | Verified robust, no change. |
| — | Info | Caught gauntlet kin counting as cleared | **Kept by design** — capture neutralizes the threat and event bosses are uncatchable, so the wave boss must still be killed. |

## New regression coverage (16 checks)

- broken spire pays sigil / re-record pays once / worldgen leaves a spire
- merchant briefcase can carry a sigil (bounded 400-roll probe)
- stale-raider sweep spares gauntlet kin / still clears a plain raider
- `left` reconciles to live count / deserted field voids / real clear pays
- wild egg can't claim ranch blood / bred egg claims its bloodline
- keeper empties a stockpile with E / guest can't drain the replica store
- `spos` rides the save, forged tags/cells die
- every spire door opens onto walkable same-elev ground

Suite: **858 checks, 0 failures, 1 skipped** (known worldgen-conditional
grotto chamber). Balance sim: 0 failures.

## Evidence

- `tools/shot_s76.gd` → `/tmp/plg-s76-map.png` (+ zoom): five violet spire
  pings on charted ground, one hollow (broken), gold X, orange player dot.

## Guide

Field Guide Vol. IX documents the spire → sigil → gauntlet → crown →
accord arc in both languages.

## Process lessons folded into AGENTS.md

- rule 116: progression items need a *first source* audit — trace every
  gating item from world to reward, not just within its own loop.
- Loads that bypass `place_pois` must repopulate non-structure POI state
  (`spire_pos`) from the save or by derivation — rule 25's checklist
  extended in practice.

## audit-32 recheck (context-free review) — findings and fixes

An independent pass over the diff surfaced four real defects plus fixture
hygiene debt. All fixed and asserted:

| # | Sev | Finding | Fix |
|---|-----|---------|-----|
| R1 | Medium | `spos` wrote `Vector2i` values; the loader demanded `is Array` — every real save's markers were silently dropped (only live-guardian derivation hid it; broken-spire markers lost) | `save_game` serializes `{tag: [x, y]}`; assertion now round-trips the REAL writer's output with a guardian-impossible sentinel |
| R3 | Medium | E-stockpile list missed six producing sites: apiary, fish_trap, sphere_factory, sphere_factory_2, compost_bin, expedition_post — they fell through to the kinbox panel | match arm extended; every site with a `store` output answers E |
| R4 | Medium | relaxed + fallback passes never checked the door cell `(tx,ty+2)` — a sealed guardian could still spawn | both passes now run the real movement predicate `blocked(x, y, from)` on door cell AND approach; the suite's door invariant asserts the same predicate |
| — | Low | a wave spawning zero raiders at `MAX_PALS` auto-advanced waves → free clear | `gauntlet_next_wave` rolls the wave back when nothing spawned — retries, never scores an empty wave |
| — | Low | `spires_done`/`spire_pos` never reached clients → no hollow markers on guest maps | `env_sync` carries a spire bitmask (2Hz, covers join AND mid-run breaks); mask decode asserted + revoke asserted; disconnect clears replica marks |
| — | Low | guests could buy `boss_sigil`/`gauntlet_sigil` — dead items in a guest bag | `buy_remote` refuses host-only items with a `note_remote` explanation |
| — | Low | `bred_kin_egg` missing from `ITEM_WT` | 5.0 wt like its wild sibling |
| — | Low | items.ts generator drift: 17 items existed only in items.gd (pre-existing, deepened by the egg split) | all 17 ported back to the .ts source + stale sigil desc synced |

Fixture hygiene (P-class): ranch-stall check read the retired `kin_egg` id
(vacuous post-rename → now reads `bred_kin_egg`); `egg_parents`/`mission_flags`
/`is_host` mutations now snapshot + restore instead of blanket-wipe; the
crafted-save fixture is complemented by a real `save_game()→load_game()`
round-trip (a fixture dict shaped like nothing the writer emits certifies
nothing — rule 28/114 in practice).

Verified: **860 checks, 0 failures, 1 skipped** (worldgen-conditional
grotto chamber, pre-existing); balance sim 0 failures.

### Post-recheck addition (self-audit while probing the endgame chain)

Demolishing a loaded incubator destroyed the egg *and* its claimed
bloodline row — `demolish_at`/`raze_structure`/`net_demolish` all
refunded `store` but never `egg_inc`. All three removal paths now
recover the egg (host demolish → bag refund; structure raze + guest
demolish → ground drop), mapping `egg_inc` back to its item id
(huge flag → `huge_kin_egg`, pair → `bred_kin_egg`, else `kin_egg`).
Asserted: `razing an incubator refunds the egg`. 862 checks, 0
failures.
