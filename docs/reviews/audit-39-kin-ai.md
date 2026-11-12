# audit-39 — kin AI behavior loops — CLOSED

Cold foreground audit of `src/kin.gd` + `src/game.gd` job/haul/sleep/expedition/
aggro machinery. 1 High + 2 Medium + 6 Low + 3 Info; the verified-clean list
(demolish-mid-work, kill/box transitions, sleep wake/KO paths, aggro clearing,
mount unbind battery) holds.

## Fixed

- **High — expedition kin KO'd mid-trip died as wild fauna.** `kill_pal`'s
  `owned` list omitted `"expedition"`: the invisible gatherer (pos stays at the
  post — "off-map" is visual only) could be bitten by a raid targeter and was
  freed with wild-loot drops, no box, no log. `expedition` now lands in the
  owned lane: KO → box + revive timer. The post's exp timer already gates on
  `mode == "expedition"` so a boxed pal is never "returned".
- **Medium — returned gatherers lost their job on the next save.** Departure
  hygiene drops the kin from `workers[]`; `return_expedition` never relinked
  it, so the save wrote `job: null`. The post now re-claims its berth on
  return (crew cap 4 honored; a filled berth clears `job_site` and lets
  `tick_assign` repost the kin honestly).
- **Medium — hauler froze forever with an undeliverable carry.** No chest
  capacity → early return, no wander, no feedback; unreachable chest →
  `step_toward` ground against the wall until starvation KO re-dropped the
  goods into the same loop. Now: no-capacity holds the goods but wanders and
  raises a throttled "nowhere to stash" floater; `carry_hold_t` (90s) gives up
  honestly — the goods land as a real drop at its feet.
- **Low — manual assign pinned cargo.** `assign_worker`/`assign_remote` now
  empty the paw first (host's bag / `give_remote` for guests).
- **Low — KO didn't clear `berserk_t`** — a redeployed kin resumed its
  rampage. KO now zeroes it alongside statuses/stun.
- **Low — load path could over-crew a site.** The job re-link now honors the
  same workers≤4 cap `find_work_site` enforces.
- **Low (perf) — three per-frame scans throttled.** `find_foe` (O(pals) per
  base kin per frame), `nearest_bed_cell` and the training-dummy sweep
  (O(structures) each) now ride 0.4s caches; the structure scans key on
  `_struct_gen`, the foe cache re-validates `hp>0`/`mode=="wild"` on reuse so
  a KO'd raider can't be chased mid-box.

## Deliberately documented (not changed)

- Expedition pals don't appear in `pal_state_pack` (clients reconcile them
  away) — cosmetic wire gap; the post's `exp_uid` resolves on return.
- Guest-owned field pals have no food path (can't raid the host bag) —
  co-op design gap, retract-to-bench is the remedy.
- SAN recovery ignores proximity ("any bed anywhere comforts all") —
  soft-locks berserk once a bed exists; likely intent, contradicts the
  comment — noted, not reversed.
- Timid kin flee the host even when a guest provoked (cosmetic).

## Coverage

6 new pins: expedition-KO→box, berth relink, stall-wander, give-up drop,
KO-clears-rampage (plus the existing depart/return round-trip). Suite:
`911 checks, 0 failures, 1 skipped`; SIM 0; SIM-ECO 0.
