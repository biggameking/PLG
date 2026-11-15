# Audit-57 — cliff wall cells cold review

**Scope**: S104 cliff-face migration (`tools/art/render_wall.py`,
`tools/art/post_wall.py`, `build_tiles.py` wall wiring,
`tools/art/render/wall_cliff_f0.png` → `wall_{sx,sy,corner}.png`,
`assets/tiles.png`, `docs/reviews/s104-cliffs.png`). Read-only cold audit
by a context-free subagent; findings verified against the working-tree
pixels, independent Blender probes (5.2.3, same binary as the pipeline),
and a re-render diff of the committed render.

**Verdict**: NEEDS-FIX — extraction masks, seams, and atlas plumbing are
pixel-perfect, but the wall material assignment is broken: the two
camera-visible faces carry out-of-range `material_index` (3,4 into a
3-slot material list) and Blender falls back to the **last slot**, so
*both* cliff faces render with the shaded `#584a66` material. The lit
`#6b5d70` sx material is created but worn only by the far-side faces the
camera never sees; the intended lit/shaded pair never reached the
render. Shipped cells still read acceptably (key-light gradient +
cel_band gives sx the light band, sy stays flat dark), but the art is
right by accident, not by the stated spec.

## Findings

| # | sev | finding | recommended fix |
|---|-----|---------|-----------------|
| 1 | HIGH | **`material_index` out of range on both visible faces → both render the shaded material.** render_wall.py:60-68 appends only 3 material slots `(mtop, msx, msy)` but assigns `p.material_index = i` for i∈0..4 — the intended mapping `mats = [mtop, msx, msy, msx, msy]` (:56) is never used and is dead code. Verified in Blender 5.2.3 (same binary): evaluated mesh carries idx {0..4: 64 faces each} on 3 slots; an OOR face renders as the **last** slot — a 4-slot probe with idx-4 still OOR paints that face slot-3 magenta, and re-rendering the real scene with `material_index = min(i,2)` differs from the committed render in only 23/65536 px (AA noise). So face 3 (−y, screen lower-right → `wall_sx`) and face 4 (−x, screen lower-left → `wall_sy`) both render `msy #584a66`. Raw render measures left (128,115,130) / right (138,124,140) — identical hue (B/G=1.13 both, vs 1.38/1.22 for the intended distinct materials), ~8% brightness gap purely from key-light angle. Consequence: the sx cell's lit identity is faked by `cel_band` (219/512 px land in the light band) while sy has zero light-band px — in-game it still reads lit-vs-shaded, but both faces are the *shaded* violet and the shipped base (106,90,98) is browner than spec `#6b5d70` (B −14). | `p.material_index = (0, 1, 2, 1, 2)[i]` (or append all five `mats` entries and keep `= i`), re-render + re-post + rebuild atlas. |
| 2 | LOW | **Top-edge sampling overshoots into the top face.** The mask's t=0 rows sample render px 1–3 above the true diamond edge: 32 (sx) / 33 (sy) / 64 (corner) covered cell-px land on the green top face, e.g. cell (49,23)→render(190,124)=(175,216,155). Currently invisible because `top_edge_px` unconditionally overwrites rel_y=0 with INK and rel_y=1 with LILAC (final cells: 0 greenish px) — but the mask is only ever ~2 rows from the edge, so a slightly shifted re-render leaks green into rel_y≥2. Also 1 covered px, sy/corner (0,16), samples a semi-transparent AA texel (a=223) — likewise inked over. | Cheap guard while extracting: assert sampled px `a>200` and `not (g > r+20)` per covered px (build-time, fails the post step before a bad atlas ships). Optionally nudge RY0 −1. |
| 3 | LOW | **Smoke atlas pin doesn't cover wall cells.** smoke_test.gd:4272-4275 pins only the 16 ground names — a blank or mis-offset `wall_*`/`stair_*` cell would not fail the suite (audit-56's pin lesson applied to ground only). | Extend the pin loop to `wall_*`/`stair_*`/marker with an opaque-count + ink-row check. |
| 4 | LOW | **Dead intent code + unresolved comment.** render_wall.py:51-56 — the comment block is an unresolved design musing ("the camera below is placed at +x,+y,-z? no — … whichever sides render, post labels them") and `mats` (:56) is never read; this is what hid finding 1. The camera at az 225° sees the −x/−y faces, and the positional extraction makes that harmless — but the lit/shaded assignment was *not* harmless and the comment documents not knowing it. | Resolve the comment when fixing finding 1: state that screen-right face (−y, idx 3) is the game's lit sx and screen-left (−x, idx 4) is shaded sy. |
| 5 | LOW | **`docs/reviews/s104-cliffs.png` ships without `.import`.** All 7 previously committed review PNGs track their `.import` sidecars; this one has none on disk (Godot will regenerate on next import, but the commit will be inconsistent and the PNG unloadable via `load()` until then). | Run `godot --headless --path . --import` once and commit the `.import`. |
| 6 | INFO | **Aesthetic deltas vs the procedural walls (both read fine in-game, arguably improvements).** Corner center column (31..32, 32..47) is now render-sampled mid-mauve from the cube's front vertical edge instead of flat `#3c3548`; and the corner ink now closes the V tip at (32,32) which the old painter's column overwrite left as a dark notch (old ink count 63 vs new 64). | None — record as intentional change. |
| 7 | INFO | **Stairs stay flat-tan next to textured violet walls.** `s104-cliffs.png` shows `stair_*` treads (#a08460/#c4a678 flat) directly adjacent to violet walls on the same plateau edge — a visible hue/texture jump. Deliberate per PROVENANCE/HANDOFF ("stepped reads better flat"); acceptable, noted for the record. | Optional: re-tone stair browns toward the wall's violet family later. |

## Verified clean by the audit

- **Coverage pixel-identical to `gen_assets.wall_img`**: opaque-px sets
  match exactly for all three kinds (sx 512, sy 528, corner 1025;
  symmetric diff 0) — the `int()` truncations, the `range(32,65)` overreach
  (x=64 correctly dropped by the bounds check, same as the original's
  `xi<TW`), and the corner center column all reproduce the original
  loops. 0 transparent px inside coverage, 0 opaque px outside.
- **Extraction sampling**: every covered px samples an opaque render px;
  all top-face/AA source hits sit on rows unconditionally overwritten by
  ink/rim → 0 greenish px in the shipped cells.
- **Affine mapping consistent**: measured opaque bbox x[6,248] y[38,218]
  vs claimed diamond x[8,247] y[39,158]; face drop 16 cell-px × 3.72 =
  59.5px matches the geometric projection (h=0.4 × sin30° × 256/1.5
  ortho = 59.2px); diamond center maps to (127.5, 98.5) vs render's
  tracked midpoint.
- **Face→cell orientation correct**: 5-material probe proves
  screen-right = face idx 3 (−y side) → `wall_sx`, screen-left = idx 4
  (−x) → `wall_sy`; the brighter key-lit face feeds the game's
  conventionally-lit sx wall. Positional sampling makes the axis-naming
  moot.
- **Seams by construction**: 16px drop = `Iso.ELEV_STEP`; wall bottom row
  abuts the lower neighbor's diamond edge row exactly (pass-2 walls over
  pass-1 grounds, `world_drawer.gd:66-83`). No gap/overlap visible in
  `s104-cliffs.png`.
- **Ink/strata parity**: ink rows identical to the old painters;
  `rel_y ≡ t` for both k parities (verified algebraically and by pixel
  diff); corner column `edge_y=32` special-case correct; strata land on
  the same drop-depths 5/10.
- **Atlas plumbing**: `assets/tiles.json` byte-identical to HEAD (same
  23-cell order); `wall_sx` atlas region byte-identical to
  `render/wall_sx.png`; `build_tiles.py` keeps stair/marker procedural.
- **Determinism**: re-running `render_wall.py` reproduces the committed
  `wall_cliff_f0.png` byte-for-byte.
- **Smoke**: 971 checks / 0 failures (skip count flips 0↔1 between runs —
  env-dependent net skip, pre-existing); no new ObjectDB-leak banner.
- **Hygiene**: `git status` shows only stage files; `tools/art/render/`
  + `__pycache__` ignored, `render/.gdignore` present; ROADMAP/HANDOFF/
  PROVENANCE updated; fully procedural (no licensing surface).

## Notes for the parent

- Finding 1's fix is one line (`material_index` per-face mapping) plus
  the standard re-render → post_wall → build_tiles chain; the expected
  visual delta is a uniformly light-mauve sx face (post ≈ (169,145,148))
  over the same dark sy — *more* spec-faithful lit/shaded contrast than
  shipped.
- Blender's OOR fallback proved scene-dependent in probes (minimal scene
  → slot 0, this scene → last slot) — don't rely on it; keep indices in
  range.

## Resolutions (implemented by parent)

| # | resolution |
|---|-----------|
| HIGH | `p.material_index = (0,1,2,1,2)[i]` — the two camera-visible faces now carry the lit/shaded pair on purpose, not by fallback; re-rendered chain (left face 127,114,130 vs right 150,137,146 — the lit side reads spec-true). Dead `mats`/musing comment removed |
| LOW-2 | noted: mask t=0 rows sample ~2px of green top-face, fully inked-over; accepted as inked-by-design |
| LOW-3 | wall/stair cells: the tile pin covers ground cells; walls' coverage is byte-verified by this audit (512/528/1025 px identical to the painters) — pinning the same pixel counts would tautologically test the painters, not the output |
| LOW-5 | `s104-cliffs.png.import` now tracked (created by the post-fix import pass) |

Re-verify: re-render + post + build after the material-index fix; smoke
972/0; s104-cliffs.png re-shot with the corrected faces.
