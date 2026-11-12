# Audit-34 — Cross-Platform & Input Credibility (S78c)

Context-free audit of the Windows/Web/Android story: input completeness,
touch layer, layout safety, platform blockers, save portability, mobile
perf, web multiplayer degradation — plus verification of the 3ad7c4c
lineage/pacing batch.

## Findings → fixes

- **[High → fixed] Gamepad could never open the inventory.** No `inv`
  binding, no pause row — a pad-only keeper couldn't eat, heal, equip,
  or use any item. Starvation pins hp at 1; gear was unreachable.
  Fix: dpad binds for every keyboard-only verb (up=inv, right=ride,
  left=partner_skill, down=map), L3=nearest-structure demolish,
  R3=field-swap (`cycle_field_pal` skips KO'd members), plus an
  INVENTORY row in the pause shell (pad/touch reach the bag there too).
- **[Medium → fixed] F8 label was a lie.** `load_save` is F4; the armed
  prompt said F8 and the help overlay documented nothing. Label → F4,
  overlay line now lists `F1 save / F4 reload(armed)`, zh synced.
- **[Medium → fixed] Party 1-9 had no pad/touch route.** R3 cycles the
  field kin through `game.cycle_field_pal()` — same send_out semantics
  as the hotbar, KO'd members skipped, lone ball recalls.
- **[Low → fixed] No orientation lock.** Portrait shrank a 1280-wide
  layout. `handheld/orientation=4` (sensor landscape) + PWA `orientation=1`.
- **[Low → fixed] Mobile-web textures uncompressed.** Web preset
  `for_mobile=false`→`true` (etc2/astc imports already existed).
- **[Low → fixed] Fog rebake churn.** 2×/sec 48,400 `set_pixel` +
  `create_from_image` while the map was open. `explored_n` dirty key
  now bakes only on fresh reveals — stationary map costs a compare.
- **[Low → accepted] Pad can't type an IP.** `m_join` stays (backs out
  cleanly); text entry is keyboard-only by nature.
- **[Nit → fixed]** `_return_egg_parent` nearest-ranch distance used
  cell corners; callers pass centers.

## Verified correct (no action)

Touch coverage is genuinely complete (virtual stick + verbs + panel ✕ +
vkbd); auto/on/off detection works; layout is viewport-relative; web
drops `net` cleanly (every call site null-guarded, rows hidden); no
threads/OS.execute/absolute paths; `user://` saves portable; all
MAX_* caps honored; `3ad7c4c`'s `_return_egg_parent` (mutation order,
double-claim, empty-pool, save round-trip) and prefer-uncaught re-roll
verified SAFE.

## Assertions (smoke suite, "audit-34" block)

- every pad verb carries a `InputEventJoypadButton` binding;
- pause shell offers `m_inv`;
- R3 rotates the deployed kin and swaps back;
- a synthetic L3 joypad press razes the nearest (isolated) structure;
- `explored_n` counts fresh reveals and stays clean on re-reveal.

## Evidence

`==== 878 checks, 0 failures, 0 skipped ====`; store page's
"Gamepad — full navigation" claim is now true rather than aspirational.

## Process note

The inventory gap survived because pad support was added verb-by-verb
without a parity checklist. Rule 119 added to AGENTS.md.
