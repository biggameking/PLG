# Audit-43 — Combat Spatial Integrity (S90)

Cold-lens audit of every combat verb against terrain: melee, bites, slams,
novas, lunges, orbs, partner actives, deploys, and the host-side wire claims
that mirror them. Verdict: **2 HIGH + 6 MED + 4 LOW**, all resolved this
stage. Suite: ~953 checks, 0 failures across four consecutive seeded runs.

## The core defect — walls only walled movement

`world.blocked()` governed walking and, partially, projectile flight — but
every *non-projectile* combat verb resolved on distance alone. A boss sealed
behind the audit-42 rock-ring arena was still biteable, meleeable, slam-able,
nova-able, orb-able, and deployable-through. The ring was décor, not cover.

**Fix** — one shared predicate, `World.los_clear(a, b)`: a segment march at
~8 samples/cell rejecting out-of-bounds cells, decor, solid structures and
unramped elevation steps — the same wall set `blocked()` enforces.
Endpoint cells are exempt from content checks: a wall is what sits BETWEEN
two bodies, and entities (fixtures, teleports, respawns) can stand on cells
they could never walk into. The elevation-step check still applies to the
edge pairs — a sheer face is a wall even at point blank.

Aggro/detection scans stay distance-only by design — spotting through a
wall is fine, hitting through one is not.

## HIGH — every damaging verb now honours the ring

- `Player.melee` refuses per-victim on `los_clear` (and the merchant-swing
  clause got the same gate).
- All five kin bite lanes gated: wild→player, raid→base defenders,
  kin→kin, partner→wild, and the `pact_slam` pile per victim (player,
  guest ghosts and parked pals alike).
- Burst/nova victims filtered on `los_clear(caster, victim)` — a sealed
  arena's warden can't blizzard you through its own ring.
- Lunge resolves the dash, then re-checks `los_clear(caster.pos, tpos)` —
  a refused dash can't land the hit either.
- Bespoke partner actives (`run_partner_skill` for cindlump/sprigmelt/
  briargoo/corlmite) require the mark inside weapon reach AND on a clear
  line from the *pal* — plus per-victim LoS inside the cone. A blind mark
  reports `false` (no cast), not a misleading fallback log.
- Shadelump's Dream Chaser respects the same rule (kin.gd:1825/1829).

## HIGH — the wire can't walk through walls either

- `pal_hit`: the ghost→target segment must be sight-clear — a forged
  swing respects the same wall an honest one does.
- `net_catch` / `sphere_catch`: the guest's orb claims roll only on a
  clear line; the *host's own* `throw_sphere` click-scan kept its 9-tile
  honest-arm bound.
- `sync_pos`: claims landing inside `blocked()` cells are refused —
  water cells exempt (a mounted swimmer's position is legitimate), every
  other solid is a teleport exploit.
- `nearest_free` gained an optional deployer anchor: `send_out`,
  `r_send_out` and `dig_check` deploy on the visible side only.

## MED — orbs are projectiles, frame-steps are not teleports

- `tick_spheres(dt)` extracted (same tick_* pattern as raider sweep):
  the lobbed ball dies on decor, solid structures, out-of-bounds and
  uphill cells — lobbing over a sealed ring to bag what the ring locks
  in was free cheese.
- `update_projectiles` no longer checks only the current point: each
  bolt *marches* the travelled segment (≈4 samples per cell of travel),
  so a fast bolt on a slow frame can't hop a 1-cell wall between ticks.
  Walkable structures (spike floors) don't eat shots the way rock does.

## The regression cascade — what the fixtures taught

The first LoS run went 951 checks / 19 failures and every one traced to
fixture geometry, not engine regressions:

1. **Endpoint exemption** — ghosts/targets planted on the player's own
   cell made every same-position claim fail the interior-check version
   of `los_clear`. Exempting the bodies' own cells fixed ten checks at
   once *and* matches the semantic: the wall is the between, not the
   endpoints.
2. **`poi_reach()` walked-only BFS** — `can_enter` lets a barefoot player
   swim (no gear gate), so zone-3 pockets behind a strait vanished from
   the reach set and den/grotto placement starved on some seeds. The
   reach predicate is now walk ∪ `swim_open` (glider/grapple/mounts stay
   gear-gated out).
3. **Positive-control discipline** — "the wall drops, the hit lands" is
   only meaningful if the lane was provably clear *before* the rock and
   the target *survives* the hit: a 1-hp fixture player ate the nova,
   respawned at a kinbox, and every later wall check silently ran in a
   different location. The fixture now probes a real two-cell lane
   (clear decor → `los_clear` → restore), tops up hp, and passes the
   player *entity* to `tackle` (`skill_hit` fails closed on a bare
   Vector2 — the old check measured nothing).
4. **Landing-cell honesty** — `los_clear` exempts endpoints but the orb
   doesn't: a target standing inside decor kills the ball on arrival.
   Launcher fixtures now require a walkable landing cell, not just a
   sight line.

## Evidence

`==== 952-955 checks, 0 failures, 0-1 skipped ====` across four
consecutive seeded runs (the only skip is the seed-conditional second
grotto chamber). No new `ObjectDB instances were leaked` vs baseline.
