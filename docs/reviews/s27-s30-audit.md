# S27–S29 fifth-pass audit + S30 fix batch

Fresh-context audit over the touch-accessibility batch (`9f801db..cbf62c5`).
2 HIGH / 5 MED / 9 LOW — all actionable items landed, smoke 603–606/0 ×3.

## HIGH

- **Paused text panels couldn't type.** `m_chat`/`m_join` opened their
  panels from the pause shell, but `_unhandled_input` returns inside the
  `title|paused` shell branch before the chat/join key handlers ran.
  Panel drew; every keypress died. chat/join/guide key handling now sits
  above the shell branch (guide gains N/G/Esc close + ←/→ paging under
  pause, matching its on-screen ‹/› turners).
- **Paused panels were keyless traps.** `draw_touch` early-returned on
  `state != "play"` and the event gate shared that check — a panel
  opened from the pause menu had no ✕ rendered and no route to it on a
  slab. The ✕/escape path now keys on `panel != ""` alone; gameplay
  verbs stay `state == "play"`-only (touch_down refuses verb taps under
  the shell).

## MED (all landed)

- `main.gd` wheel-zoom exempted only `panel == "dex"` — scrolling the
  other seven panels also zoomed the camera. Now `panel != ""`.
- Rect clicks ran `run_click` and returned without
  `set_input_as_handled()` — a close-tap fell through to `player`
  melee/throw below.
- `place_ghost` had no touch-zone guard — a ✕-zone tap while build-open
  could plant a structure under the button.
- The merchant sell rail iterated `game.box` unfiltered and `sell_n`
  capped at 12 — guests' boxed kin were sellable and the scroll extent
  lied. `sellable_pals()` filters `owner_id == 0`; both the column and
  the cap consume it.
- Expanded `more_row` drew 19px circles but hit-tested 33 (`BTN_R+8`)
  at 56px spacing — edge bleed. `MORE_BTN_R` feeds draw + `btn_r`.

## LOW (landed)

CHAT row gated on `net_live()` not peer presence; mid-drag touch toggle
releases the stick via `_process`; dex/shop scroll buttons only render
on overflow; guide footer now says "Esc/n close". Deferred-by-design:
title JOIN (world-swap flow is the deferred work, not the row), guest
drop reconciliation (design-limit already on record), the defensive
unreachable `_menu_key` branch left as a seatbelt. Host `m_save` with
guests was audited for semantics: the snapshot serializes guest kin by
keeper tag, and a later session's `hello` reclaim-by-tag re-binds them —
already coherent, documented here rather than changed.

## Coverage added (real routes, not helpers)

Paused chat/join typing + Esc bail, paused guide paging + N-close,
paused-panel touch ✕ through `_unhandled_input`, joy-tap grab refusal
under the shell, `is_input_handled()` after a rect click, all-controls
inside `touch_zone_hit`, `btn_r` vs 56px spacing, `sellable_pals()`
owner filter, `run_click` exercised for `m_host` (live host + close),
`m_dex`/`m_statues`/`m_guide`, and `chest_up`/`chest_dn`.

## Process note

Two HIGHs were self-inflicted by the same batch they shipped in:
feature gates were written for "play" and never re-audited when the
pause shell became a second entry point. Rules 59–61 added to
AGENTS.md.
