# S117 — real two-process multiplayer session

**Verdict**: HOST 9/9 + JOIN 7/7, two seeds back-to-back
(41447, 6292). Real ENet processes, real input events, no stubs.

Evidence: `s117-net-guest.png` (guest ghost on host, "Player … joined"),
`s117-net-chop.png` (remote ghost beside the tree, `thwack` floater),
`s117-net-gone.png` (post-disconnect frame — ghost gone, cell felled to
stump).

## What the gates actually prove

| Gate | Evidence shape |
|---|---|
| host binds :7777 / guest ghost lands | `is_host`, `ghosts.keys()` non-empty |
| ghost tracks guest movement | guest writes its own landing pos to `net_walk_claim.txt`; host ghost `net_pos` must land <3.0 of the claim — not merely "moved" |
| harvest target received | joiner writes the cell BEFORE swinging; host snapshots hp/decor baseline first |
| guest harvest_req chops the host cell | real LMB → `player.melee()` → `try_harvest` → `is_client()` → `harvest_req` rpc; host hp 30→20 on that exact cell |
| decor_delta echoes the felled tree | 3+ real swings fell it; the host's `mark_decor`/`dirty_decor_pack` flips the CLIENT's replica to stump (decor=7) — the sync path back |
| spoofed 50-tile claim refused | guest teleports +50 tiles and lets the 20Hz sender ship it; host ghost never gets within 15 of the claim (drift 0.0) |
| out-of-reach harvest_req refused | guest rpcs a far decor cell directly; host cell hp/decor unchanged |
| disconnect frees ghost + tag | `ghosts` and `peer_tags` both empty for the peer id |

## Bugs the harness caught in ITSELF (fixed this stage)

- **Diagonal stand chopped air**: `try_harvest` picks the dominant-axis
  cell — facing (0.707, 0.707) from a diagonal stand hit the orthogonal
  neighbor, not the tree. The relay DID reach the host; the aim was
  wrong. Stand spots are now orthogonal-only.
- **Held-key walk could push a wall**: spawn rings wall off directions
  per-seed. Walk leg now tries D/S/A/W and keeps the first that moves
  >1.0 tile (measured displacement, not a guess).
- **Wild-kin interference**: a kin inside melee reach eats the swing
  (`hit_any` short-circuits harvest). Stand candidates now require a
  kin-free 2.0 ring.
- **Stale ghost ref**: `Invalid access … previously freed` when the
  guest disconnected mid-await. Host re-reads `ghosts.get(gid)` every
  iteration.
- **Tree hp 30 needs 3 hits**: `decor_delta` only fires on the felling
  transition — one chop left decor unchanged and the echo gate honestly
  failed until the swing budget covered the fell.
- Marker artifacts (`net_walk_*.txt`, `net_host_out.txt`) are now
  gitignored; both sides wipe markers at boot so an aborted run can't
  prime the next.

## Runbook

```
godot --path . -s tools/net_walk_host.gd   # windowed (shots need texture)
godot --path . -s tools/net_walk_join.gd   # after host binds
# verdicts: tools/net_host_out.txt, tools/net_join_out.txt
```

## audit-67 cold review — NEEDS-FIX → all fixed, re-verified ×2 seeds

| # | Finding | Fix |
|---|---|---|
| HIGH-1 | join harness set `state="play"` BEFORE `join()` — `net.join()` `save_game()`s any non-title state, and `is_client()` is still false at that instant → the throwaway boot world serialized over the REAL save (`shot_net_join.gd` had the same bug) | stay in `"title"` — `_arrive_guest` flips to play on world_sync; both harnesses fixed |
| HIGH-2 | "spoofed claim refused" passed VACUOUSLY on phase-marker timeout (`spoof_claim=(-1,-1)` → `reached=false` → PASS) | gate requires `marker_seen`; ghost-freed fallback no longer feeds the verdict |
| MED-3 | far-harvest gate silently SKIPPED on marker timeout (no line, "0 failures") | missing marker now emits a FAIL; preconditions `decor != NONE`, ghost `gdist > 4.0`, `net_walk_far_fired.txt` race check |
| MED-4 | spoof verdict was a single endpoint sample — raced the return-home blink | `ever_reached` polled across the whole window |
| MED-5 | far baseline could snapshot post-mutation | joiner delays 2000ms + writes a "fired" marker the host asserts absent at baseline |
| MED-6 | movement tolerance could pass on zero tracked movement | host requires `dist(claim)<3.0 AND dist(pos0)>1.0` |
| MED-7 | far cell picked vs `player.pos`, but `net_harvest` judges `ghost.net_pos` — a refused return-home could leave the "far" cell inside the ring → false-FAIL | cell must be >4.0 from BOTH home and the harvest stand; host asserts `gdist > 4.0` and reports it |
| MED-8 | `net_host_state.txt` never deleted; stale all-PASS outputs indistinguishable; `net_join_out.txt` collided with `net_join.gd`'s | host wipes all markers+outputs at boot; join output renamed `net_walk_join_out.txt`; joiner deletes its own out |
| LOW-9 | `for i in 900` frame window lies at non-60fps | wall-clock `_wait_ms` loops |
| LOW-10 | dead `_tap_key` | removed |
| LOW-11 | `_gate("far harvest_req fired", true)` tautological | gates on `is_client()` |
| LOW-12 | `ghosts.keys()[0]` arbitrary with a stray second client | land gate asserts `size() == 1` |
| LOW-13 | tag teardown vacuous if hello never bound | `tag_seen` captured at land; gate proves release |
| LOW-14 | spoof ±50 could be refused at the bounds check before the bucket | free-cell scan over 8 candidate offsets (run 99145 used -50) |

Harness self-fix after re-run: wandering wild kin (and the trader) inside
melee reach eat the swing via `hit_any` — selection buffer raised to 3.5
(+merchant), and each swing waits out any kin that drifts inside 1.55.
