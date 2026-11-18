# audit-71 — e8824f4 cold review (post-audit-70 fixes)

Scope: `_sync_chunk` slot-map in src/net.gd, save .tmp/.bak chain + apply_binds
in src/game.gd, rebind clash scan in src/hud.gd, package.sh Android guard,
smoke epoch/save pins, walkthrough window pins. Verified against current tree;
commit message not trusted.

Verdict: **NEEDS-FIX** — one HIGH (the `_def_key_evts` snapshot is poisoned on
every `reload_current_scene`, so the commit's own "alternates survive" claim
breaks on the normal quit-to-title path) plus one MED (mid-chunk `total` is
trusted for completeness — a forged short total forces premature reassembly
over null slots). Everything else verified sound.

## HIGH

- **H1 — `_def_key_evts` snapshots the polluted InputMap after scene reload** —
  src/game.gd:4424-4454, src/game.gd:4512-4520, src/main.gd:11.
  `Game` is a scene child (`$Game`), not an autoload; `to_title()` calls
  `reload_current_scene()` and the code's own comment says "the MultiplayerAPI
  peer, buses and **InputMap** all survive it". On reload a fresh Game gets
  `_def_key_evts = {}`, then `load_settings()` (game.gd:325→4422) re-runs
  `apply_binds()` — whose lazy snapshot `if not _def_key_evts.has(act)` now
  captures the **already-bound** event set as "defaults".
  Trace: bind move_up→K. InputMap move_up = [UP_arrow, K]. Quit to title.
  Reload: snapshot = [UP_arrow, K]; binds={move_up:K} → erase all → re-add
  `defs[1:]` = [K] → add K → move_up = [K, K]. **The arrow-key alternate is
  gone and K is now baked into "defaults".** Rebind to J → [K, J]: K can never
  be unbound; even `reset_binds()` can't heal — it restores the live map via
  `load_from_project_settings()` but the stale `_def_key_evts` resurrects K on
  the next bind. Only a process restart cures it. Bites exactly the
  dual-default actions (the four move_* = letter+arrow), i.e. the flagship
  "rebinding keeps arrow keys" claim. Single-default actions (dodge etc.)
  are coincidentally immune (`defs[1:]` is empty).
  Unpinned: rebind_walkthrough never reloads the scene (`change_scene_to_file`
  at boot only, before any bind exists), and the smoke binds leg uses
  single-default dodge.
  Fix: make the snapshot's lifetime match InputMap's — `static var
  _def_key_evts` (statics survive node recreation), or rebuild defaults from
  `ProjectSettings` input entries instead of the live map.

## MED

- **M1 — mid-chunk `total` never checked against the head's `parts.size()`;
  the completion test uses the arriving chunk's `total`** — src/net.gd:108-118.
  Head declares total=5 → `parts` sized 5. A mid with `idx=1, total=2` passes
  the range check (idx<2), fills a slot, then `buf["got"] < total` → 2<2 is
  false → the "apply" path runs `append_array` over three still-null slots.
  `append_array(null)` is a GDScript runtime error (Nil→Array), so the apply
  aborts — no partial roster lands — but `parts` is left dirty, the batch is
  zombie-locked, and each repeat spams the error log. The mirror case
  (mid total > head's, e.g. 8 vs 5) wedges the batch permanently until the
  next head. Both violate the claimed invariant "a batch applies only when
  ALL slots filled". Reachability needs inconsistent wire data (hostile host
  or corrupted packet past ENet CRC — sender is `authority` so guests can't
  forge) — low real-world exposure, but this function exists precisely to
  distrust the wire, and the fix is one clause: reject mids with
  `total != buf["parts"].size()` and/or test `buf["got"] < buf["parts"].size()`.

## LOW

- **L1 — `_close_peer` reset incomplete** — src/net.gd:189-191. Clears
  `rows` + `ep` for all four buffers but leaves `parts`/`got` stale (and
  `_send_eps`, `pal_sync_t`, `box_sig` etc. untouched). Unreachable today —
  `ep=-1` rejects all mids and any head re-inits `parts`+`got` — but the
  claim "clears all four buffers with new keys" is half-done. Two clears for
  symmetry.
- **L2 — epoch edge cases verified OK**: `buf["ep"]==-1` fresh/post-overflow
  short-circuits the `>=0` guard so any first head lands; `d>=128` rejects
  stale AND far-ahead heads (inherent mod-256 ambiguity — a ≥128-epoch jump
  needs ~64s of total head loss to bite); same-ep head after a complete apply
  restarts cleanly (d=0); 256-wrap stale-mid contamination needs a 128s-old
  packet still in flight — unreachable on ENet. Negative wire `ep` can only
  park `buf["ep"]` at a negative that the next head overwrites.
- **L3 — `package.sh` preset lane doesn't verify the keystore file exists** —
  tools/package.sh:50-59. `grep -q 'keystore/release="[^"]'` correctly ignores
  `keystore/release_user`/`_password` (requires `="` right after `release`)
  and rejects `keystore/release=""`, but a pinned-but-missing path passes the
  guard and dies inside Godot. Env lane is the real engine triple
  (`GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`, verified against
  Godot export docs) including the `-f` existence check. Guard still fires
  correctly when preset lacks the key AND env unset.
- **L4 — capture-time validation asymmetry** — src/hud.gd:255-296. The live
  capture binds any `pk>0` non-clashing key; `load_settings`
  (game.gd:4409-4415) separately rejects Escape, dead keycodes
  (`OS.get_keycode_string(pk)==""`) and dups. A dead physical keycode
  therefore binds live, persists, and silently vanishes next boot — phantom
  bind this session. Cheap fix: same `get_keycode_string` check at capture.
- **L5 — cfg coercion doesn't scan other actions' live defaults** —
  game.gd:4400-4415. `seen_keys` dedups only within `binds`; a hand-edited cfg
  binding e.g. move_up→S double-fires with unbound move_down's default S —
  the panel's scan (hud.gd:262-272, which covers ALL REBIND_ACTIONS' live
  events, defaults included) would refuse it. The comment "same clash rule
  as the panel" overstates; hostile cfg only, LOW.
- **L6 — rotation rename unchecked** — game.gd:4667-4671. If
  `rename_absolute(main→bak)` fails, `tmp→main` also fails → logged
  "SAVE FAILED" while main+tmp both survive intact. Fail-closed but noisy.
  `f.get_error()` is also checked pre-close, so a flush-at-close error could
  still rotate a torn tmp (rarer than the store-time error it does catch).
- **L7 — `rebind_walkthrough.gd` lacks the `root.size` pin** its 8 siblings
  got — it feeds events via `hudn._unhandled_input` directly so event
  *delivery* is window-free, but `click_rects` still come from
  `get_viewport_rect()`; at a true 64×64 headless window `draw_controls`
  (`rr.size.y = 64-92 <0`, `rows_h<0`) emits zero rows → zero targets.
  audit-70 doc claims "REBIND-LOOP 19/0 headless" — confirm whether the
  harness ran under the project window size or needs the same pin.
- **L8 — latent aliasing** — game.gd:4449-4454. `defs[i]` re-adds the
  snapshot's own event objects; InputMap stores the same refs. Nothing
  mutates events in place today (binds create new `InputEventKey`s); note
  only.
- **L9 — HELP live-map mode drops raw-lane hints** — src/hud.gd:1383-1393.
  When binds are non-default the generated rows omit non-InputMap hints the
  curated set carries (chat Enter, lmb melee/aim/throw). Minor info loss.
- **L10 — efficiency**: `_send_chunked` runs `var_to_bytes(r)` per row per
  0.5s tick for sizing and the rpc serializes again (double cost, ~220 rows);
  `_keys_label` + `InputMap.action_get_events` re-run per row per frame while
  the help/controls panels are open — bounded, memoizable.
- **L11 — cosmetics**: duplicated `file_exists` inside `_read_save` and at
  call sites (game.gd:4715/4719); `has_save` can stay stale-true if files
  vanish mid-session (continue then fails gracefully).

## Verified sound

- Slot-map: `got` counts filled slots exactly (dups rejected by non-null
  slot check; forged idx rejected vs `parts.size()`); `parts`/`got`/`ep`
  can't desync on any reachable path incl. the `rows>SYNC_BUF_CAP` reset
  (parts already cleared, ep=-1 blocks mids).
- `total` forges of idx rejected at the door; head opens only on non-behind
  ep; apply reassembles in wire order; callers gate on `true` before reading
  `buf["rows"]` (pal_sync net.gd:458, drop_sync :816, struct_sync :872,
  decor_delta :879).
- `save_game`: `get_error()` gate before rotation, torn tmp removed, `.bak`
  rotation order correct; `.tmp` probed before `.bak` — tmp only survives
  when it IS the newest attempted commit (main gone or corrupt), and a valid
  main is rightly preferred (uncommitted write isn't the save).
  `Migrate.save_dict` runs inside `_read_save` for all three paths;
  version/field-presence/field-type gates uniform; `_fin(seed)` guard present.
- `has_save` counts all three files (game.gd:327-330).
- `apply_binds` is idempotent within a boot (bind K→J leaves no K), captures
  are `physical_keycode`-keyed and `_key_of` covers the project.godot mix of
  `keycode`-defaults vs `physical_keycode`-defaults.
- Clash scan: covers all `ui_*` actions + RAW_KEY_LANES; every raw
  `event.keycode ==` consumer in src/ is covered (Enter/KP_Enter chat+join,
  N/G guide-close, 1-9 party+build; Escape excluded; Backspace is
  panel-owned typing). F1/F4 are `save`/`load_save` ACTIONS inside
  REBIND_ACTIONS — covered by scan 1, no raw F-lane needed. K has no raw
  consumer (join_net is an action) but is typed text in the join panel —
  lane inclusion defensible, not a miss.
- Joypad-button capture cancel + `rebind_wait` cleared on panel transitions;
  `_eat_input` null-guards the teardown frame.
- KINBOX_OPS single-lane intercept (hud.gd:585-597) — clients hit box_req for
  all eight acts, dead is_client arms gone.
- `_keys_label` shared by help + controls; HELP shows live rows only when
  binds non-default.
- Smoke pins genuinely exercise: stale-head clobber, dup-mid, missing-mid
  (no apply), out-of-order reassembly, half-range (d==128) stale head, and a
  real `net.drop_sync` e2e with `is_host=false`, stale-head interleave, and
  node cleanup. Refusal fixtures delete `.bak`/`.tmp` first (else a valid
  backup would legitimately load — refusal would be vacuous); backup/restore
  covers all three files; footer counts all checks. Leftover
  `_drop_buf["ep"]=7` can't bite (no later drop_sync calls).
- 8 harnesses pin `root.size=1280x720`; `net_verbs_join` correctly documents
  RUN-WINDOWED (live-cursor reads need real warp_mouse).
- package.sh env triple is the real engine override set; guard fires when
  preset lacks `keystore/release=` and env unset; debug/`all` path stays
  unguarded by design.

## Attack paths tried that held

stale/mid-ahead/far-ahead heads, dup heads (restart current batch — lost
tick, not corruption), dup mids, forged idx totals, mid-before-head,
overflow reset, peer-swap residue, negative ep, ep wrap, forged .tmp/.bak
ordering, hostile cfg binds (Escape/dead/dup all rejected), bind-rebind
within a boot (no stacking), reset→rebind (defaults restored), ui_* mirror
binds (refused), joypad cancel mid-capture.

## Remediation (post-review, this tree)

- **H1 FIXED** — `_def_key_evts` is now `static var` (game.gd): the snapshot's
  lifetime matches InputMap's, so `reload_current_scene()` can no longer
  re-snapshot a polluted map. Smoke pin: a fresh `Game` rebinds move_up→J
  after an earlier instance bound K — both `KEY_UP` and `KEY_J` survive on
  the live map.
- **M1 FIXED** — `_sync_chunk` rejects any mid whose `total` differs from
  the head's `parts.size()`, and completion is tested against the head's
  slot array. Smoke pins: forged short total (2<3) refused, forged long
  total (8>3) refused, honest mids complete in wire order.
- **L1 FIXED** — `_close_peer` clears `parts`/`got`/`ep` alongside `rows`.
- **L3 FIXED** — preset lane now extracts `keystore/release="…"` and
  requires `-f` on the resolved path; env lane keeps the real engine triple
  + existence check.
- **L4 FIXED** — capture-time guard: `OS.get_keycode_string(pk)==""` refuses
  dead physical keycodes before they can persist (hud.gd:261).
- **L5 FIXED** — cfg coercion in `load_settings` builds the same occupied
  map as the panel: every other action's live keys + `ui_*` + the
  `RAW_KEY_LANES` const now centralized in game.gd (Enter/KP_Enter/K/N/G/
  1–9). Own-action keys are excluded per action so re-binding to a key the
  action already owns stays legal; dups/Escape/dead keys refused. Smoke pin:
  `move_up→S` + `dodge→8` cfg refuses both (S is move_down's live default,
  8 is a raw hotbar lane).
- **L6 FIXED** — `save_game` checks `get_error()` after `store_var`, removes
  a torn `.tmp`, and fails closed ("SAVE FAILED — rotate"/"— rename") if
  either `rename_absolute` fails — no half-rotated save.
- **L7 FIXED** — `rebind_walkthrough` pins `root.size = 1280x720`; the
  19-check run above is genuinely headless at a real window size.
- **L9 FIXED** — HELP live-map mode appends raw-lane rows the InputMap
  can't describe (lmb melee/aim/throw, build 1–9 + rmb cancel, chat Enter,
  party-hotbar send-out) with matching zh.csv rows.
- L2/L8/L10/L11 — accepted as verified-sound/notes (no behavior change).

## Re-verification

- smoke **1030 checks, 0 failures, 0 skipped** (new pins: forged mid totals,
  fresh-Game snapshot isolation, cfg-clash refusal)
- rebind_walkthrough **19/0**, save_walkthrough **17/0** — headless
- net_verbs two-process (windowed, real cursor) — HOST **16/0** + JOIN
  **16/0**; the slot-map+epoch path carried a real roster sync
- perf_probe 0 budget failures; leak_probe delta=12 rerun (jitter band);
  entity-layer child count flat, no orphan growth
- audit_data ALL CLEAN; sim_economy 43/0

Verdict after remediation: **PASS** — all H/M/L findings closed with
regression pins; no new surface introduced.
