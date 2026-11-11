# Sixth context-free audit — S31/S32 batch + touch layer maturity

Scope: demolish-reach contract, title-screen JOIN + join-autosave, and the
full touch/net surface as it stood at `8bd9398`. Reviewer had no thread
context. Verdict: **3 HIGH / 8 MED / 5 LOW — all actionable.** One HIGH and
one MED turned out to be subtle regressions introduced by earlier audit
fixes — the suite caught both before commit.

## HIGH

| # | Finding | Fix |
|---|---------|-----|
| H1 | `demolish_at()` had no anchor guard — X key / touch DML could raze the base kinbox; `net_demolish` already refused guests | Guard added, **narrowed to the last anchor** (`pos == kinbox_pos and extra_boxes.is_empty()`): a backup outpost still razes clean and primary+backup still promotes — both are designed paths, verified by the outpost-promotion test that broke on the first draft. Guests remain fully blocked — intended authority asymmetry |
| H2 | Disconnect left a "residue" world — host structures + dead-uid party refs + mirrors stayed; `save_game()` became callable the moment `is_client()` turned false → the hybrid world could overwrite the real solo save | `net_residue` flag set by `world_sync`, refused by `save_game`, lifted by `load_game`, dies with the scene on `to_title`. Disconnect now also purges `party`/`net_party`/`net_box`/`net_unlocked` and nulls the peer |
| H3 | Client `buildable_list()` used only local `unlocked` — a developed save joining a fresh host offered structures the host hadn't researched, then `build_req` ate the materials on a silent deny | `net_unlocked` mirrors host tech through `state_snapshot`/`state_sync`; build bar intersects it; `build_req` now sends `build_deny` + refund on an honest deny (forgeries still gain nothing — bags are client-authoritative) |

## MED

| # | Finding | Fix |
|---|---------|-----|
| M1 | Chest/store contents never rode the wire — clients saw empty chests | `state_snapshot`, `struct_state_pack`, `state_sync`, `struct_sync` all carry `st["store"]` as element 4; `place_free` accepts a store dict. **Regression caught by the suite:** first implementation refreshed `cur["store"]` with a `{}` default for packs lacking the field — every legacy pack zeroed every mirrored chest. Now refreshes only when the element is actually present |
| M2 | S30's zone guard over-blocked build placement — any tap inside ANY touch zone (joystick corner, most of the play area) refused placement | `_build_tap_ok()` — only the menu/X control zone still guards; the rest of the slab places normally |
| M3 | Roll button overlapped ATK's fat-finger hit disc | Moved to `r.y - 178`; smoke asserts `distance >= btn_r("atk") + btn_r("roll")` |
| M4 | Button label dicts duplicated between draw and verbs | `BTN_LABELS` shared const |
| M5 | Open panel still ate pinch-zoom gestures the wheel gate doesn't see | `InputEventMagnifyGesture` handled in `main._unhandled_input`, same clamp band; slab now has a real zoom verb |
| M6 | OS virtual keyboard covers chat/join input bars on the slab | `_vkbd_lift()` reads `DisplayServer.virtual_keyboard_get_height()` while `_vkbd_open`; both panels ride above it |
| M7 | Dex id-sort ran every painted frame (~200 species) | `_dex_ids()` cache keyed on catch-book size/seen/count-sum |
| M8 | Guests got a dead TECH TREE pause row (research is host truth) | `pause_rows()` gates `m_tech` on `not is_client()` |

## LOW

- Shell-state reset duplicated between `load_game` tail and `regenerate` —
  `_reset_shell_state()` is now the single transition scrub (raid horn,
  panel, chest ref, aim, dodge, stick + finger owner).
- Dodge cost triple (0.35s / −15 SP / 0.8s wait) duplicated across key and
  touch paths — `player.dodge()` is the one verb; `can_dodge()` stays the
  one predicate.
- Aim preview read the mouse position under `touch_ui` — the hint now says
  "tap a kin to throw" on touch; the hover-odds block is desktop-only.
- `game.build_sel` dead field removed (the live one is hud-local).
- Touch-control visible set: draw and hit-test already walk the same
  `touch_layout()` dicts through `btn_r()`; visual radii deliberately sit
  8px inside hit radii (fat-finger bleed). Satisfied, documented here.

## Verification

- Smoke **631–633 checks ×3, 0 failures**; SIM 0; no ObjectDB growth.
- New real-route assertions: last-anchor refuse (planted fixture —
  `kinbox_pos` can be a phantom `(10,10)` from earlier fixtures),
  outpost backup raze, residue save-refuse, disconnect mirror purge,
  client build-list intersect, `build_deny` refund, guest tech-row gate,
  facing-based touch shot, `_build_tap_ok` zones, pinch zoom, `x_close`
  act, dex cache, wire-carried store (`{"wood":3}` pack).
- Suite self-caught two regressions in this batch's first draft
  (store-wipe + promotion kill) — the audit loop's evidence is real.

## Still deferred (honest list)

- Android export verification — JDK present (`openjdk@21`), Android SDK +
  build-tools still absent.
- True-hardware touch feel, pad rumble.
- Guest-side structure store edits (deposit/withdraw RPC) — mirrors are
  now correct on arrival; mutation sync remains host-authoritative by
  design for ops that exist (box_req pattern is the template).
- LAN/tag trust model, private-roster consumption proofs — recorded design
  bounds.
- `m_save` on the host serializes guest kin under keeper tags — reclaim on
  re-hello is the designed contract.
