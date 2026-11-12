# Audit-45 — Export credibility + perf-under-cap (S92)

Cold-lens audit of `project.godot`, `export_presets.cfg`, input/locale export
survival, net platform paths, and per-frame cost at `pals.size()==MAX_PALS`.
Verdict: **3 HIGH + 8 MED + 5 LOW** — all code/config findings resolved this
stage. Suite: 958-961 checks (seed-dependent branches), 0 failures. Full
finding list: docs/reviews/audit-45-export-perf-draft.md.

## HIGH — shipped content & platform-blocking costs

- **H1 dev payloads inside every PCK** — `docs/` and `prototype/` were not in
  the export exclude filter: the shipped binary carried the banned-lexicon
  migration notes, third-party art-study reference screenshots, and ~30
  uncompiled TypeScript sources. Fixed: `exclude_filter` now
  `store/*,tools/*,docs/*,prototype/*` on all three presets, guarded by a
  suite assertion (`every preset excludes dev payloads`).
- **H2 zh + HUD glyphs tofu on Web/Android** — the font fallback was a
  `SystemFont`, which cannot rasterize on those targets. Fixed: bundled two
  subsetted fonts — `fonts/FusionPixel12px.ttf` (192KB, OFL Fusion Pixel
  zh_hans covering every zh.csv + guide glyph) and `fonts/DejaVuSymbols.ttf`
  (21KB, covering all 102 non-ASCII symbols used in src+csv). Loaded via
  `FontFile.load_dynamic_font` — no `.import` sidecar needed in the export.
  Fallback ladder: PressStart2P → FusionPixel → DejaVu → SystemFont. License
  files ship in `fonts/` (inside the PCK, as OFL requires). Two assertions
  walk the live chain's cmaps.
- **H3 `tick_repairs` O(cells×structures)/frame** — `st in seen` linear
  dedupe over ~1600 footprint cells × ~400 dicts ran ~600k compares/frame.
  Fixed: Dictionary-keyed dedupe (same shape `save_game` already used).

## MED — export lanes & hot-loop costs

- **M1 Android lane** — explicit `min_sdk=24`, `target_sdk=35`. The
  Play/AAB lane (`use_gradle_build`) stays deferred to the release stage.
- **M2 Web thread_support=false** — nothing in src uses threads; forcing it
  required cross-origin isolation headers that hard-fail on itch embeds.
- **M3 terrain `_draw`** — now repaints only when the visible window or
  `world.terrain_gen` changes (tiles/elev/ramp are write-once after
  `generate()`). Variant-name strings prebaked in a static LUT — was ~15k
  string allocs/frame at max zoom-out.
- **M4 HUD strings/scans** — 4Hz memo block: boss-bar + post-crown den
  O(pals) scans, `RAID IN`/`★ mission`/hint `tr()` formats, and the
  get_string_size trim loops all cache; draw reads the cache every frame.
- **M5 net quadratic** — `pal_sync` builds one `net_id→Kin` map per packet
  (was O(rows×pals) ≈ 48k compares/broadcast at 220 kin);
  `struct_state_pack` uses dict dedupe.
- **M6 spring heal scan** — `nearest_spring(at)` memoized like `nearest_heat`
  (0.4s + `_struct_gen` invalidation); was O(cells) per physics frame while
  injured.
- **M7 partner AI batching** — foe/drop sweeps moved to a staggered 4Hz
  rescan clock (`_foe_cache`/`_grab_cache`, uid-phased) — 6 partners stopped
  scanning pals+drops every physics frame (~10k checks/frame at cap).
  Stance re-gates the cached lock per frame (aggressive→passive drops the
  target immediately — found by the suite). `tick_raider_sweep` throttled to
  0.5Hz at the call site (240s expiry needs no 60Hz pass); `floaters`
  backward-erase; `net_drops` direct iteration; wild recount memoized 2Hz.
  `danger_active` deliberately left unmemoized — callers are truth-gates.
- **M8 perf budgets** — `tools/perf_probe.gd` now fails (exit 1) when a
  scenario exceeds ~4x baseline: kin-tick per-kin budget, game-tick 200ms,
  raid/base-tick 1500ms. Current: 86ms/9ms/341ms/190ms all PASS.

## LOW

- **L1** `config/version="0.9.0"` + `config/description` in project.godot.
- **L2** console wrapper off on the Windows preset.
- **L3** desktop `touch=on` — LMB routes through `touch_down/up/move` under a
  synthetic finger index (99), so the virtual row actually presses; the
  existing `touch_zone_hit` guard still eats the melee.
- **L4** `user_data_backup/allow=true` — the kinbox save rides Android Auto
  Backup.
- **L5** remaining `not in seen` dedupes in `kinbox_count`/`place_structure`/
  net build verb all dict-keyed.

## Verified correct (auditor-confirmed, no change needed)

Buses + synth SFX (zero audio assets), `user://` portability, web co-op
amputation (`net==null` gates), gl_compatibility renderer choice, stretch/
orientation coherence, ETC2/ASTC texture pipeline, all export-referenced
assets exist, 30+ action input parity + idempotent `bind_gamepad`, touch
layer completeness, all runtime caps honored, batching cadences (production
4Hz, assignment 2s, fog 0.5s, merchant 2.5-5s, drop decay 600s, far-kin ~8Hz),
image/texture discipline (no Image alloc in hot paths), node budget (~660 at
cap, no parentless pals), host authority + fail-closed RPCs, 2Hz broadcast
shape, documented tick_migration exception.

## Deferred

- Play/AAB gradle lane (release stage). Real-device fps validation needs an
  Android/Windows box — the perf_probe budgets are the code-level guard.
- Itch upload / release keystore — owner-deferred.
