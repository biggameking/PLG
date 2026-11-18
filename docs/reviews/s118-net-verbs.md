# S118 — multiplayer verb acceptance (real two-process session)

Date: 2025-11-18. Harnesses: `tools/net_verbs_host.gd` + `tools/net_verbs_join.gd`
(two real Godot processes on ENet :7777, marker files for ordered baselines).

## Gates

**HOST 16/0** across seeds (85934, 53937, 85138, 2871 …):

- host binds :7777 / guest ghost lands / `hello` tag binds
- guest ready claim → fixture pins (weak `catchable()` bait + 500hp tank on
  LOS-clear cells, `PROCESS_MODE_DISABLED`)
- `sphere_catch` → `net_catch` → kin joins `remote_parties[tag]` under the
  guest's **stable owner_tag** (`rp 0→1`), leaves the wilds (`mode=partner`)
- build marker → `build_req` → structure planted with `placed_tag == guest tag`
- far `sphere_catch` refused (proximity ring, `d≈108` measured)
- locked `build_req` refused — forged wire for a sid the host never unlocked
- far `pal_hit` refused (8.0 ghost ring)
- **forged `pal_hit` clamped**: 1e9 claim → `bound*1.3` honest ceiling
  (measured `hits=1 max_drop=171 ≤250`)
- disconnect frees ghost + `peer_tags` row; the caught kin **orphans under
  the tag** in `bench`/`box` — roster survives the keeper

**JOIN 16/0**:

- host marker/seed sync, host ghost visible, held-key walk
- fixture pins received, weak replica synced by `net_id`
- real aim→click orb flight → catch ledger +1 ("You caught …")
- `net_unlocked` converges with the host's tech (`torch` row visible/picked
  through the real build panel `B` key + `click_rects`)
- `place_structure` hold pays → `build_done` settles spent; struct_sync echoes
- **denied builds refund their holds**: two >9-ring `build_req`s →
  `pay_rej` → wood/fiber return to EXACTLY `w0/f0`, `pending_pays` empty
- locked wire sent; far catch+hit wires sent
- forged `pal_hit` wire: re-sends until replica hp confirms a landing
  (unreliable lane), observed base 500 → applied

## REAL defects found & fixed this stage

| Defect | Root cause | Fix |
|---|---|---|
| **Guest tech tree desync** | `unl_send` rides the *unreliable* env_sync diff — `unl_sig` advances at send time, so ONE dropped datagram desynced `net_unlocked` **permanently** (observed live: `send unl=7` → client stuck at 6 forever) | new reliable `unl_sync` rpc fired alongside the diff; env payload kept as a hint |
| **Guest decor desync** | `decor_delta` was the only send-once *unreliable* delta channel — `dirty_decor_pack()` drains the dirty set at send time; a lost packet = ghost trees/stumps forever | `decor_delta` → `reliable` |

Harness lessons (all hardened, not papered):

- `String.split()` → `PackedStringArray` — `is Array` never matches (pin parse)
- `PackedStringArray` pin contents: weak must pass `catchable()` itself
  (nearest-wild picked alphas/den heirs and burned every honest throw)
- `Iso.from_screen` inverts at the **player's** elev — projecting the target
  at its own tile elev moved the click a terrace off (silent no-pick, no orb
  spent, no message)
- marker intent ≠ landing cell: `mouse_tile` can honestly resolve a cell
  over — assert `placed_tag`/new-structure-delta, not the marker's exact cell
- `build_bkt` token bucket: probes inside a 0.7s window get refused+refunded
  like real play — refund probes use deterministic >9-ring deny instead
- `pal_hit` is unreliable → re-send until replica-hp confirms, never blind
  multi-send (stacked clamped hits batch into one frame and fake an
  unclamped 471 read — actually three honest ~157 landings)
- per-hit semantics: gate measures largest single-frame drop, not the total

## Evidence

- `s118-verb-catch.png` — host view: guest catch logged, ghost + roster strip
- `s118-verb-build.png` — host view: `Player … built Torch`, lit torch beside
  the guest ghost, `placed_tag` = guest tag
- `s118-verb-gone.png` — post-disconnect: ghost gone, orphan roster kept

smoke: **1008 checks, 0 failures, 0 skipped** (parse pins cover both harnesses)
