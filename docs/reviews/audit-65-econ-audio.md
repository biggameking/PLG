# audit-65 — S115 econ harness + S116 audio coverage

**Verdict**: NEEDS-FIX → 0 HIGH / 4 MED / 6 LOW, all fixed and re-verified.
Cold agent, no prior context; memory-safety contract clean; determinism
analysis correct except two seed lotteries below.

## MED — all fixed

1. **sfx pins were gameable** (`smoke_test.gd`): comment lines counted as
   wired, only 5 of 21 src files scanned, and `SFX.has(key)` accepted a
   null stream. → Whole-tree DirAccess walk over `res://src` + `src/data`,
   comment lines skipped, and the orphan check now asserts each entry
   `is AudioStreamWAV and data.size() > 0`.
2. **Craft gate exercised nothing station-gated**: `"club"` is a
   `"hand"` recipe — the bench proximity check, `craft_queue` and the
   helper-hurried drain were all dead coverage. → Added a `flour` leg
   (wheat 3→1, the cheapest tech-free workbench recipe): row click →
   queue grows → hurried drain → `flour +1 / wheat -3`. First attempt
   used `"arrow"`, which *looked* free but its output item carries tech —
   `recipe_tech()` checks recipe AND output item; noted in the harness.
3. **Direction-only money checks**: `< gold0` / `> gold1` pass on any
   delta. → Exact assertions: `gold == gold0 - price`,
   `gold == gold1 + Game.sell_value(...)`, `tech_points == pts0 - cost`.
4. **Buy pick was a seed lottery**: `price <= 40` could leave `stock_i=-1`
   on expensive rolls. → Cheapest in-stock row regardless of price, purse
   topped up to afford it, exact-debit assertion.

## LOW — fixed

- `cr["arg"]` → `cr.get("arg")` (future arg-less rects no longer crash).
- `_stand_spot` fallback could plant the player inside terrain → ring
  widened to 7, bare `near` returned so the downstream gate fails loudly.
- Merchant could despawn mid-leg at dusk → `game.tod = 10.0` pinned.
- `var SfxLib := preload(...)` shadowed the `SFX_LIB` const → all 25
  synthesis calls now use `SFX_LIB`; shadow removed.

## Accepted notes

- Kin-lane buys and multi-unit sells remain uncovered (noted, not defects).
- Guest-triggered cues play on host speakers only — current design.

## Re-verification

- `tools/econ_walkthrough.gd`: **19 gates, 0 failures, ×2 seeds**
  (was 16 — +3 for the station/queue leg).
- `tools/smoke_test.gd`: **1006 checks, 0 failures, 0 skipped**.
- `tools/play_walkthrough.gd` (windowed): 0 failures — headless `-s`
  cannot screenshot (Dummy renderer, null viewport texture), expected.
