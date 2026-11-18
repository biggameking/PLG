# audit-69 — holistic launch-readiness cold review + fix pass

Cold reviewer verdict: **NEEDS-FIX** — core game sound (egg gating, capture
chain, endgame reachability, save coercion, multiplayer authority, bounded
collections, localization, art direction, input hygiene all verified);
failings were platform-fit gaps plus one save-durability defect.

## Fixed

| # | Finding | Fix | Evidence |
|---|---------|-----|----------|
| H1 | Single save slot, in-place write — a crash mid-write kills the campaign | `save_game()` writes `.tmp` → rotates last-good to `.bak` → renames in; `load_game()` falls back to `.bak` on missing/unreadable main; `has_save` counts the backup | save_walkthrough: `torn main recovers via .bak state=play` + `both-dead saves fail closed` (17/0) |
| M1 | No resolution option — only fullscreen toggle | `settings["wsize"]` + `WSIZES` list, WINDOW SIZE row cycles it, applies via window.size + re-center, coerced on load, doesn't stomp OS drags (`_applied_wsize`) | `s119-settings.png` |
| M2 | No input remapping | `REBIND_ACTIONS` (28), `settings["binds"]`, `apply_binds()` replaces keyboard events only (pad binds untouched), controls panel with capture + clash check + RESET KEYS | `s119-controls.png`, smoke pins |
| M3 | Android release signing resolved from ambient editor settings | `tools/package.sh` documents the keystore contract + `android-release` refuses ambient signing | package.sh header |
| M4 | Smoke unattested at audit HEAD | ran at a111df3 → 1015/0 | this file |
| L1 | Metadata still 0.9.0 | → 1.0.0 / code 3 | export_presets.cfg |
| L2 | Dead `sell_pal`/`butcher`/`fav` client arms under KINBOX_OPS | removed — arms are local-only now | hud.gd match |
| L3 | Single save slot | `.bak` rotation is the second slot | — |
| L4 | Gamepad-only sessions can't type | `virtual_keyboard_show` also fires under `using_pad` (desktop no-op, Steam Deck/consoles surface OS kbd) | hud.gd |

## Harness work

- `save_walkthrough.gd` corrupt leg rewritten for the new contract:
  torn main → `.bak` recovery into play; BOTH files dead → fails closed.
  Harness also backs up/restores `savegame.plg.bak` (operator state).
- `tools/shot_controls.gd` — settings/controls/capture-state evidence.
- Smoke pins: wsize list coercion, binds persist+coerce+apply+reset
  (inside the existing settings.cfg backup window), stale-epoch chunk
  tail (earlier commit), `"%s  [>]"` tr row.

## Self-caught while fixing

- Default binds use `keycode`, captured ones `physical_keycode` — the
  clash check and row labels both normalize via `_key_of()` or half the
  keyboard map is invisible to each other.
- `rebind_wait` dies on panel transition (rule 23) or a stale capture
  eats the next gameplay key.
- Settings card was 300px — 7 rows clipped; now 456px.
- `\,` in CSV is literal, not an escape (rule 32) — comma-bearing keys
  get quoted fields.
