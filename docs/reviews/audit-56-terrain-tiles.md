# Audit-56 — terrain tiles atlas cold review

**Scope**: S103 ground-tile migration (`tools/art/render_tile.py`,
`post_tile.py`, `build_tiles.py`, `gen_assets.py` `--tiles-legacy` gate,
`tools/smoke_test.gd` atlas pin, `assets/tiles.png`). Read-only cold audit
by a context-free subagent; findings verified against the working-tree
pixels and a PIL simulation of `world_drawer.gd`'s compositing.

**Verdict**: NEEDS-FIX — manifest/layout/writer-gating/determinism all
clean, but every ground cell ships a 3–5px semi-transparent edge band, so
the composited map shows a dark grid along every diamond edge (visible in
the stage's own evidence `s103-terrain.png`) — the exact defect the stage
set out to avoid.

## Findings

| # | sev | finding | recommended fix |
|---|-----|---------|-----------------|
| 1 | HIGH | **Seam grid across the whole map.** `cam.data.ortho_scale = 1.5` (render_tile.py:216) leaves the 1.414-unit diamond at ~94% of the 256×128 frame (alpha bbox x∈[6,250), y∈[~4,124] for all 16 renders), so after the 4× downscale the opaque region ends ~1.5px inside the diamond mask and EEVEE+LANCZOS falloff widens it to a 3–5px soft band (~830 of ~1056 analytic-diamond px opaque). LANCZOS also pulls rim RGB toward the transparent-black surround, darkening edge color. Neighbors drawn later only cover the far side of each shared edge — the topmost tile's own soft band remains → ~2px of backdrop shows along every edge plus darker dots at vertices where two soft edges stack. Measured: 0 opaque px outside the diamond, but ~225 inside-diamond px ≤230 alpha per cell. PIL simulation of `draw_texture_rect_region` compositing reproduces the grid; `docs/reviews/s103-terrain.png` shows it in-game. Old flat diamonds were 255-alpha to the analytic edge, so this is a regression. | Render slightly oversize so the mask edge cuts fully-opaque pixels: `ortho_scale ≈ 1.36` (or scale the 1×1 slab ~×1.06). Optionally +1px alpha dilation in post_tile before masking. Re-post + rebuild atlas. |
| 2 | LOW | **Smoke pin covers only 11 of 16 ground cells** — the list at smoke_test.gd:4272-4273 omits `tallgrass_1`, `flower_1`, `sand_1`, `water_1`, `stonefield_1`; a blank/missing variant cell would not fail. Thin margin too: measured `sand_0` variance 0.000343 vs the 0.0002 floor (1.7× headroom; fine for the committed PNG, tight for re-renders). | Extend the name list to all 16 (or iterate the manifest's non-wall cells). |
| 3 | LOW | **Dead displace/subsurf.** render_tile.py:72-77 stacks DISPLACE *before* SUBSURF on the 4-vertex slab quad → the CLOUDS texture is sampled at 4 corners only — a slight corner rock, not the "gentle height noise" the comment claims; the slab is effectively flat. `sub.levels = 3` is also the viewport level (render uses `render_levels`, default 2) — moot given the order bug. Harmless, misleading. | Drop both modifiers, or SUBSURF-first if relief is actually wanted. |
| 4 | LOW | **Latent per-tile rescale via `crop_alpha`.** post_tile.py:28 reuses `post_kin.crop_alpha` (pad=10). Today all 16 renders' padded bboxes clamp to the full frame → identical 4× downscale → consistent placement. But any future render whose alpha bbox sits >10px inside the frame on all sides gets a smaller crop that *rescales* its diamond relative to sibling cells — a silent per-tile offset the pin (opaque≥800) would still pass. | Fixed `(0,0,256,128)` crop, or normalize the crop so the diamond always lands identically. |
| 5 | INFO | **Bottom-vertex row dropped.** Old painters covered the analytic diamond rows 0–32 incl. the (32,32) vertex px; the new 64×32 mask ends at row 31, and the top-vertex px (32,0) of every cell is itself ~0 alpha → the coincident vertex px of each 4-tile junction is covered by nothing opaque. Folds into finding 1 (fixed by the same overfill). | Covered by fix 1. |

## Verified clean by the audit

- `assets/tiles.json` **byte-identical to HEAD**; wall/stair/marker cells
  **byte-identical pixels** (0/32768 diff on atlas row 2) — gen_assets'
  painters reproduce exactly under `build_tiles.py` and the manifest
  layout matches `world_drawer.gd:15-17` (`Rect2(c[0]*64, c[1]*64, 64,64)`).
- **Zero bleed**: 0 px with alpha>10 outside the analytic diamond in all
  16 cells; `diamond_mask` polygon is a strict subset of the game diamond.
- No half-cell shift: all 16 raw renders crop to the same full frame →
  uniform 4× downscale, same diamond placement in every cell.
- Determinism: `random.Random(cfg["seed"])` fixed seeds; no set/hash
  iteration; `bpy.ops` primitives + `bpy.context.active_object` only
  immediately after add — deterministic under `-b --factory-startup`.
- Writer gating: only `build_tiles.py` and gated `atlas()`
  (`--tiles-legacy`, gen_assets.py:1316) write `assets/tiles.png`/`.json`;
  only gated `decor()` (`--decor-legacy`, :1322) writes `assets/decor/*`;
  `import gen_assets` is side-effect-free (all writes under `__main__`).
- Artifact hygiene: `tools/art/render/` + `__pycache__` gitignored,
  `render/.gdignore` present; `git status` shows only the intended files.
- Licensing: fully procedural (cones/icospheres/tori/cubes + CLOUDS
  texture) — no external assets; PROVENANCE updated.
- Blank-render guard present (post_tile.py:29-30, <50 opaque px bails).
- Smoke suite headless: **969 checks / 0 failures / 0 skipped**, new pin
  "all ground tiles have textured diamonds" PASS, no new ObjectDB leak
  banner.

## Resolutions (implemented by parent)

| # | resolution |
|---|-----------|
| HIGH | Slab oversized ×1.3 so the fixed crop rect (94.27% centered) cuts fully-opaque interior; mask rebuilt pixel-exact from the game's own diamond inequality (the polygon version was 1px inset on right/bottom edges); output resized to 64×33 so the bottom-vertex row 32 is covered too. Rim opaque ratio now 1.000 on every ground cell; seam grid gone in the re-shot s103-terrain.png |
| LOW | smoke pin now covers all 16 ground names; a 3px rim-band opaqueness pin added (edge>=95%) |
| LOW | displace fixed earlier (SUBSURF before DISPLACE) — re-rendered |
| LOW | crop_alpha's latent rescale hazard removed — post_tile uses the fixed analytic crop rect |
| sand | sand variance pin initially failed post-fix (dunes/ripples too fine) — enriched with dune lumps + bigger rings; now passes |

Re-verify: smoke 972/0/1skip with the rim-band pin active; in-game
screenshot re-taken (seam grid absent).
