# Audit-35 — economy/balance + performance cold pass (S79)

Scope: gold/food/lumenite/XP/crafting economy end-to-end, per-frame perf hot
paths at MAX_STRUCTURES/MAX_PALS, sim_balance coverage honesty, and a
spot-check of the audit-34 pad work. Context-free external agent, findings
verified against code before fixing.

## Fixed this pass

- **[High] O(structures²) per frame in `tick_production`**: `cell_of(st)` ran a
  linear dict scan once per footprint cell (~1.3M compares/frame at cap).
  Every structure dict already stores `pos` = the anchor cell on all four
  creation/load paths; `key != st.get("pos")` is provably equivalent.
  `cell_of` deleted; all 11 call sites in game.gd + hud.gd now read `pos`.
- **[Medium] `tick_production` batching**: production math is linear in `dt`
  (timers, turret_cd, spyglass) — the whole sweep now runs at ~4Hz via a
  `prod_t` accumulator instead of 60Hz. Drops `consume_ready`/`near_banner`/
  `near_well`/`has_structure` per-frame O(cells) calls to a quarter.
- **[Medium] `nearest_heat` memo**: player chill check + 2 hint lambdas ×
  `_draw`+`tick_hints` ≈ 3–5 full structure+pals scans/frame. Memoized for
  0.4s within ~0.75 tile — chill thresholds don't move that fast.
- **[Medium] kin AI scans**: `base_ai` job-site lookup re-scanned the
  structures dict per working kin per frame — now reads `job_site["pos"]`.
  `haul_ai` ran `nearest_chest_cell` + site/drop sweeps every frame — now
  rescans at ~2.5Hz and keeps walking the cached leg between scans
  (`haul_scan_t`/`haul_cell`/`haul_dest`); fresh pickups reset the cache.
- **[Medium] starvation KO-loop**: KO'd kin kept `hunger=100` (box skips
  `tick_needs`), revived at 30% hp still starving, re-KO'd ~50s later —
  a zero-food base could never recover and nothing told the player why.
  Revive now clamps hunger to ≤50 ("the box nurses it back"), and a
  starvation KO logs `starved out … build a feed box!` instead of the
  generic KO line (zh row added).
- Smoke: +5 checks (pos-is-anchor invariant across every unique structure,
  starved-kin box path + log + revive clamp, heat memo self-consistency).

## Verified clean, no change

- `explored_n` write-path audit: every write of `explored` pairs with
  `explored_n`; load recomputes `count(1)`; regen zeroes. Clean.
- `bind_gamepad`/`cycle_field_pal`/joypad-demolish/`_pad_btn` idempotency —
  all verified against code (rule-19 strip-then-bind holds).
- Economy dead-ends: none found. No unbuyable-uncraftable essential; lumenite
  is the intended pacing currency (crusher + 12% rock rolls + expeditions);
  food pressure is tight-by-design (~1.1 kin fed per lv1 farmer).
- `sim_balance.gd` is honest about its coverage: formulas + data tables only,
  no economy/AI/frame visibility — and its header says so.
- `update_projectiles` O(proj×pals) stays bounded by MAX_* (44k worst frame).

## Accepted / deferred

- **[Medium] gold inflation**: renewable sources (pal sales, gold-cat ranch,
  bounties, gacha EV) outpace sinks (merchant stock, sigils, 3 recipes).
  Gold is already session-transient and nothing essential is gold-gated —
  real risk is late-game meaninglessness, not a break. Deferred to the
  endgame-content pass (a repeatable sink belongs with post-Accord goals,
  not a standalone knob).
- **[Low] gacha→hatch→sell +EV**: 30g pull hatches a ~48-80g kin; bounded by
  the 90s incubator + box cap (≈600g/hr ceiling vs 30-60g/bounty minutes).
  Real fix needs hatch-provenance on Kin (a save-contract field) — not worth
  the schema for a slow mint.
- **[Low] per-frame allocations**: `floaters.filter`, `active_hints`, the
  sanctioned `duplicate()` pattern — all bounded ≤80 entries; rule-4 pressure
  only, no leak.

Suite: `==== 883 checks, 0 failures, 0 skipped ====`; sim `0 failures`.
