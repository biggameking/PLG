# Audit 60 — S107 kind-based item icons

Scope: `src/hud.gd` icon cache + 3 panel call sites, `tools/shot_items.gd`,
`tools/art/render_item.py` + `post_item.py`, `assets/items/icons/*`,
smoke pins, `docs/reviews/s107-items-*.png`. AGENTS.md contract read first.

## Verified clean

- **Cache boundedness** (AGENTS.md r1/3): `_item_tex` is keyed by *kind*, and
  `kind` is normalized to the `ITEM_KINDS` whitelist or `"relic"` *before*
  insertion (hud.gd:66-74). Max 12 entries by construction; textures are
  create-once `load()` — same contract as `_kin_tex`/`_struct_tex` (hud.gd:43-57).
  No `Image`/`ImageTexture` allocation in draw; `draw_texture_rect` only.
- **Null safety**: `ItemData.ITEMS.get(iid, {})` + `.get()` everywhere (no
  bracket access on foreign dicts); `ResourceLoader.exists` before `load`;
  `draw_item_icon` early-returns on null texture (hud.gd:80-82). Unknown ids,
  empty kind, explicit `"kind": ""`, and non-String kinds (`str()` coerce) all
  land on relic — no crash path.
- **Color parsing**: all 93 `"color"` values in items.gd are `#rrggbb` hex;
  `Color(str(col))` is safe. Malformed input → transparent black (icon
  invisible, not a crash). 16 items lack `"color"` → white tint, intended.
- **Clicks unchanged**: `click_rects` rects are the same shapes as before —
  icons are drawn *inside* the existing row rects (inv 1984/1993, craft
  1937/1939, shop 2203/2209 + 2226/2228). Clicking an icon hits the row verb.
- **Row-skip discipline**: every `break`/`continue` precedes its icon draw —
  inv spill-break at hud.gd:1978 (before 1993), craft bounds-break 1935
  (before 1939), shop scroll-skip 2224 (before 2228). No orphan icons.
- **Assets**: 12 PNGs + 12 `.import` sidecars exist for all 11 `ITEM_KINDS`
  kinds + `relic`. Data kinds in items.gd ⊆ ITEM_KINDS exactly (102 kind'd
  items, 7 kindless specials — matches the pin list, verified gold_coin is
  `"material"`). Screenshots open correctly and show icons rendering in all
  three panels with per-item tints; kin merchant rows are icon-less as designed.
- **shot_items.gd**: bag builder iterates `ItemData.ITEMS` and picks one item
  per kind — covers all 11 kinds automatically, survives kind additions.
  `game.items` keys sort alphabetically in draw_inv → deterministic output.
- **Smoke pin 1** (smoke_test.gd:1818-22): real path — iterates all
  `ItemData.ITEMS` through `item_icon`; a missing PNG → null → fail.
- **Pin 2** (1824-29): asserts data-level kindlessness (not the production
  predicate — satisfies rule 11) plus non-null icon.

## Findings

- **MED-1 — drift hole: unknown kind silently rides relic** (hud.gd:69-70,
  smoke_test.gd:1818). A new `"kind"` added to items.gd maps to relic via the
  whitelist normalize — icon renders, pin 1 stays green, nobody notices. A new
  kind already needs `KIND_WT` (game.gd:716) and now `ITEM_KINDS` (hud.gd:76)
  + a PNG — three places, zero guards. Add a data-level pin:
  `set of kinds in ITEMS ⊆ ITEM_KINDS`.
- **MED-2 — icon offset eats the text budget** (hud.gd:1993-94, 1940-41,
  2210, 2229-30). Text moved +17/+18px but `left()` caps unchanged:
  inv `nm.left(15)` + `" x%d"` ≈ up to ~21 chars ×11px ≈ 231px > 205px free →
  worst case (15-char name + 4-digit stack) bleeds ~26px into column 2's icon.
  Craft `cost.left(50)` + uncapped `out_name` now starts 18px further right —
  visible past-edge overflow in s107-items-craft.png (pre-existing pattern,
  worsened ~1.7 chars). Sell row worst case ≈ +8px past panel edge.
  Recommend tightening `left()` caps by ~2 chars to compensate.
- **LOW-3 — pin 3 "misses once" is vacuous** (smoke_test.gd:1830-35).
  `item_icon("__bogus_item__")` resolves to relic → cache *hit*, no miss entry
  is ever inserted; `size() <= 12` is structurally guaranteed (12 possible
  keys). It only guards against an iid-keyed regression — and only because
  pin 1 ran first (109 entries > 12). The true miss path (whitelisted kind,
  absent PNG) can't be exercised via the public API. Rename to
  "icon cache bounded (kind-keyed)" or assert `size() == sz107` after the
  bogus calls — that's what it actually proves.
- **LOW-4 — pin 2 doesn't assert relic identity** (smoke_test.gd:1824-29):
  proves kindless-in-data + non-null, not that the texture *is* relic.png.
  A fallback change to e.g. "material" would stay green.
- **LOW-5 — `Color(str(col))` parse per row per frame** (hud.gd:86): small
  string alloc in a draw loop, against rule 4's spirit (~30-60 rows). If it
  ever matters, cache tint per iid in a dict bounded by ITEMS size — or leave,
  it's a UI loop not a physics hot path.
- **LOW-6 — shot_items.gd:31 bracket access**: `ItemData.ITEMS[b]` crashes if
  any of the 4 hardcoded kindless ids (kin_egg/boss_sigil/ancient_part/
  gauntlet_sigil) is renamed — use `.get(b, {})`. Tool-only.
- **LOW-7 — render_item.py dead gate**: `build()`'s `raise SystemExit("unknown
  kind")` (line 172-73) is unreachable — `CFG[kind]` at line 178 KeyErrors
  first. Move the lookup into a guarded `cfg = CFG.get(kind)` for the friendly
  error. `name` params on `cube/cyl/cone/ico/torus` are unused (Blender
  auto-names) — dead params. `sys.argv[-1]` unguarded.
- **LOW-8 — post_item.py asymmetric clip gate**: checks top + both side edges
  but not the bottom row (lines 36-39) — a bottom-clipped render ships
  silently. `sys.argv[1]` unguarded.
- **LOW-9 — icons never dim**: unaffordable craft rows / sold-out shop rows dim
  text to `INK_SOFT` but icons draw full-tint (hud.gd:1940-41, 2207-11).
  Cosmetic inconsistency only.
- **NOTE — not S107**: the shop screenshot shows a world-space "merchant!"
  label bleeding into the panel behind the card — world label vs panel z-order,
  pre-existing.
- **AGENTS.md rule 7 note**: icon consumers use a null-guard early-return
  rather than a fallback texture — equivalent safety for a decorative icon,
  acceptable.

## Git scope — NOT VERIFIED

Explore mode had no exec tool: could not run `git status`/`git diff --stat`.
On-disk inventory consistent with S107 scope (hud.gd, 12 PNGs+imports,
render_item.py, post_item.py, shot_items.gd, smoke pins, 3 screenshots).
`tools/art/render/` is gitignored. **Parent: run `git status --porcelain` and
`git diff --stat` to confirm nothing else is staged.**

## Verdict

**PASS** — memory-safety contract holds (bounded-by-construction cache, no
per-frame texture allocs, null-safe, coercion at boundary). No blocking
defects. Two MED items worth a follow-up: the kind-drift hole (new kinds
silently render as relic with all pins green) and the text-budget overflow
from the +17/+18px offsets.

## Resolution (all landed)

- MED-1: data-level pin `kinds in ITEMS ⊆ ITEM_KINDS` (smoke_test.gd:1825-35)
- MED-2: `left()` caps tightened — inv 15→13, buy 16→14, sell 15→13,
  craft cost 50→44 + out_name capped at 14
- LOW-3: bound pin asserts `size() == sz107` (bogus ids are relic *hits*)
- LOW-4: relic pin now compares against the loaded relic.png texture
- LOW-5: `_item_tint` iid cache, bounded by ITEMS.size()
- LOW-6/7/8: `.get()` in shot tool, argv+CFG guards, bottom-edge clip gate
  (all 12 shipped icons re-verified against the new gate)
- LOW-9: unaffordable/sold-out icons draw at 0.45 alpha
