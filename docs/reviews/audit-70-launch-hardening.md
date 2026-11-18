# audit-70 — a111df3 + 26eac15 cold review: NEEDS-FIX → all closed

Cold review of the batch-epoch commit and the S119 launch-readiness pass.
Verdict: no HIGH, but 5 MED + 12 LOW — the epoch left a stale-*head* hole
in the class it claimed to close, the Android env lane bypassed its own
guard with a wrong var name, and the rebind clash check was blind to
ui_*/raw keycode lanes.

## Fixes shipped

| ID | Defect | Fix | Pin |
|----|--------|-----|-----|
| M1 | `idx==0` unconditionally cleared a newer in-flight batch — a delayed stale head could rewind `ep` and merge a dead roster | mod-256 forward check: head accepted only if `buf["ep"]<0` or `(ep-buf["ep"])&0xFF<128` (255→0 wraps forward, ==ep restarts) | smoke `stale head can't clobber` + `stale head behind by half-range` |
| M5 | epoch pins only covered `decor_delta` (reliable — can't reorder); dup-mid + missing-mid + out-of-order unexercised | `_sync_chunk` restructured: `parts[]` slot map per batch — apply only when all slots filled (never partial), dup mid dropped (slot non-null), out-of-order reassembles in wire order | 6 new choke pins + drop_sync end-to-end interleave |
| M2 | `GODOT_ANDROID_RELEASE_KEYSTORE` isn't an engine var — env lane silenced the guard without configuring signing | real engine triple `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`, all three required + path must exist | package.sh contract |
| M3 | clash check scanned only REBIND_ACTIONS — Enter (ui_accept+chat), K, N/G, 1-9 raw lanes double-fired | scan all `ui_*` InputMap actions + RAW_KEY_LANES const | rebind_loop `ui_accept clash refused` |
| M4 | `store_var`/`close` errors unchecked — torn tmp rotated in, logged "Saved." | `get_error()` gate before rotation; torn tmp removed | — |
| L1 | .bak fallback only for deserialize failures | `_read_save` runs the FULL chain (parse/migrate/version/fields/types) per file | refactor |
| L2 | crash between rotate & rename stranded newest save in .tmp | `.tmp` probed after main (newest-first), `has_save` counts it | save_walkthrough |
| L5 | hostile cfg could bind Escape/dead keys/28-to-1 | Escape + dead keycode + duplicate-key rejection in coercion | — |
| L4 | rebind destroyed dual-key defaults; help lied post-rebind | apply_binds keeps default alternates (arrow half survives); help shows live InputMap-derived rows when binds customized | `_keys_label` shared by controls panel |
| L6 | pad couldn't cancel capture | any joypad press cancels armed capture | — |
| L7 | dead is_client() arms in box verbs | removed — KINBOX_OPS owns all eight | — |
| L12 | "unsigned debug APK" wording | debug keystore wording corrected | — |

Deferred by design: L3 fsync (FileAccess has no fsync; .bak covers the
page-cache window), L8 modifier-drop (single-key scheme, undocumented),
L10/L11 cosmetic/intended.

## Harness discoveries this round

- **Headless window is 64×64** — piped mouse events positioned outside it
  never reach `_unhandled_input` (KEY events unaffected). Every positioned-
  click harness now pins `root.size = Vector2i(1280,720)` at boot:
  save_walkthrough verified 17/0 HEADLESS after the pin.
- **But live-cursor paths still need a real window**: `throw_sphere` reads
  `get_global_mouse_position`, which headless `warp_mouse` never reaches —
  net_verbs_join is documented RUN-WINDOWED. Windowed session at HEAD:
  HOST 16/0 + JOIN 16/0.
- `split()`/hardcoded-key traps continue: J was occupied, then Z landed on
  `ui_undo` — the walkthrough now picks a provably-free key from live
  occupancy (`_free_key()` scans all actions + RAW_KEY_LANES).

## Verification

- smoke **1024 checks, 0 failures, 0 skipped** (new epoch/dup/out-of-order
  pins + all harness parse pins incl. rebind_walkthrough)
- SAVE-LOOP **17/0 headless** (window pin), REBIND-LOOP **19/0 headless**
- net_verbs WINDOWED session: **HOST 16/0 + JOIN 16/0** — catch lands in
  `remote_parties[tag]`, torch plants under the guest tag, far-catch/
  locked-build/far-hit refused (d=93.0 measured), 1e9 claim clamped to
  max_drop=161, disconnect orphans to bench under the tag
- smoke refusal fixtures hardened: `.bak`/`.tmp` now backed up & restored
  with the main save; refusal legs kill all fallbacks first (a valid .bak
  IS a legitimate load, not a refusal failure)
