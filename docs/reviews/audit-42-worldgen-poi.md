# Audit-42 — World Generation & POI Semantics (S89)

Cold-lens audit of `world.gd`/`game.gd` worldgen: POI placement, decor passes,
aquatic spawns, and the save/load decor lane. Verdict: **2 MED + 7 LOW**, all
resolved this stage. Suite: 942 checks, 0 failures (1 seed-conditional skip —
the second grotto chamber legitimately doesn't fit every terrain roll).

## MED — campaign POIs validated solidity, not reachability

Every placement gate used `world.blocked()` — "is this cell free?" — but never
"can the player walk HERE from spawn?". A coherent door on a cliff-locked
plateau walls the campaign before grapple/birds exist.

**Fix** — `game.poi_reach()`: a seeded, memoized flood-fill from `world.spawn`
through the REAL movement predicate (`blocked(to, from)` — elevation steps
included). Computed once per seed at the top of `spawn_lairs`, before any POI
writes structures, so the set reflects natural terrain only. Gates added:

- lair arena centre must be in the reach set
- grotto centre must be in the reach set (pre-seal — the ring is what closes it)
- legendary-den centre must be in the reach set
- spire south-door approach `(tx, ty+3)` must be in the reach set — on BOTH the
  strict/relaxed candidate loop and the 20000-try last-resort path (a stray
  spire still owes the campaign a real door)

Wild kin are NOT gated — an unreachable plateau pack is a reward for
flight/grapple, not a wall.

## MED — an empty lair pool aborted the campaign tail

`spawn_lairs` ran `pool[rng.int_range(0, -1)]` on an empty zone-3 pool and,
worse, `return`ed before `spawn_legendary_den`/`spawn_grotto`/`spawn_pact_spires`
/`spawn_nests`/`spawn_waypoints` — one trimmed species table silently deleted
the entire campaign spine.

**Fix** — the pool is position-independent, so it's computed once up front:
zone-3 `acq_pool` with a zone-2 fallback; the `while` loop gains
`not lair_pool.is_empty()` so an empty pool SKIPS lairs but still runs the
whole POI tail. `pick_wild_species([])` now returns `""`; all four callers
(spawn_wild, migration ring, replica roll, cage captive) skip on `""` instead
of minting `SPECIES[""]` ghosts. `summon_raid` got the same empty-pool refusal
(it keeps the sigil — the horn refuses, it doesn't consume).

## LOW — side effects ran before pool checks (debris rings)

- `spawn_grotto` sealed its rock ring, THEN checked the zone-3 pool — an empty
  pool left an unbreakable-looking empty chamber on the minimap. Pool check now
  precedes the seal.
- `spawn_legendary_den` planted its torch ring before checking `LEGENDARY_DEN` —
  an heir-less ring was pure debris. Same reorder.
- Cage captive: `pick_wild_species(pool)` result is checked `!= ""` before the
  captive dict is written — a cage that can't hold a species holds nothing.

## LOW — `blocked_swim(x,y,x,y)` was a no-op for spawn validation

`blocked`/`blocked_swim` return "open" early when `i == fi` — the same-cell
movement question — so `world.blocked_swim(x,y,x,y)` always said open, and both
`spawn_wild` and `tick_migration` believed they were validating water cells.
New `world.swim_open(x,y)` checks water tile + `Decor.NONE` + no solid
structure in one call; both call sites switched.

## LOW — the cleared spawn cell could re-grow decor

`generate()` cleared spawn-cell decor once, but the berry/ore pass ran AFTER
and could plant on the landing cell. The clear now re-runs after that pass —
decor AND stale hp budget both zeroed.

## LOW — relaxed spire placement could overwrite water/structures

`_place_spire`'s rock ring wrote unconditionally; the strict path pre-verified
the rim but the relaxed zone-2 and last-resort paths didn't. Ring writes now
skip water cells and structure cells — the ring breaks rather than drowns a
lake or eats a neighbouring POI. Regression check scans every placed spire's
ring: no water cell may wear rock.

## LOW — decor bytes unclamped on the main load path

`decor_snapshot_apply` (net path) always clamped off-enum bytes to NONE;
`load_game` didn't — a forged save byte reached `harvest_cell`'s literal match.
Load now duplicates the array and clamps `> STUMP → NONE`, matching the wire
contract. Assertion: byte 99 at index 0 loads as `Decor.NONE`.

## LOW — spawn-cell assertion + landing contract

New checks pin: the reach set covers spawn; every spire door approach is
reachable; no spire ring drowns water; `pick_wild_species([]) == ""`; a real
water cell passes `swim_open` while the landing cell is dry AND decor-free.

## Out of scope (deferred / by design)

- Wall-blind melee & alpha aggro (no line-of-sight) — combat design decision,
  flagged in audit-40/41 as INFO; re-evaluate if ranged kiting proves abusive.
- Day/night influencing seeded species CONTENT — consumption-stable; time-based
  position decisions would break replay determinism and stay out.

## Evidence

- 942 checks / 0 failures / 1 skip (`grotto room 2` — seed didn't fit a second
  chamber; same conditional skip class as prior stages).
- 9 new assertions listed above; all PASS.
- Determinism preserved: `regen replays the same grotto r1=r2` still PASS —
  gates filter candidates by index in the same lane, so identical seeds replay
  identical worlds.
