# Audit-55 — S102 decor mesh migration cold review

**Scope**: S102 nature-pack decor migration — `tools/art/render_decor.py`,
`tools/art/post_decor.py`, the 7 `assets/decor/*.png` replacements, the new
smoke decor pin, docs (PROVENANCE/HANDOFF/ROADMAP), provenance/licensing,
and the zero-code-change claim on `src/main.gd`. Read-only cold audit by a
context-free subagent; sprites verified by direct image reads (dims +
visuals), `gen_assets.py` used as the original-dims authority.

**Verdict**: NEEDS-FIX — shipped artifacts are verified correct (7/7 dims
exact, meshes real, semantics untouched, CC0 provenance complete), but the
pipeline carries a silent-revert path, an overstated rig claim, and a
clipping pin that is structurally dead.

## Findings

| # | sev | finding | fix |
|---|-----|---------|-----|
| 1 | MED | `gen_assets.py` `decor()` still runs unguarded in `__main__` (`gen_assets.py:1309-1316`) — kin was gated behind `--kin-legacy`, decor was not. A routine regen silently overwrites all 7 mesh sprites with flat placeholders, and the smoke pin passes the placeholders (they have ink + partial fill) — the whole stage reverts with zero failures | gate `decor()` behind `--decor-legacy` |
| 2 | MED | "same camera/light rig as the creature renderer" is overstated (`render_decor.py:130-149` vs `render_src_asset.py:697-727`): no world ambient (Background 0.55@0.35 dropped — each blend's own world leaks into exposure), key is white DISK 5.0 vs warm square 4.0 (1.0,0.93,0.82), fill is 350 + default ~0.25 size (near-point) vs 260/5.0 soft fill | import `light_rig()`/`camera()` from `render_src_asset.py`, or copy the rig exactly; fix docs |
| 3 | MED | smoke `dopaque > dtotal*0.95` clipping detector is unreachable (`smoke_test.gd:4241`): the `(dw-4,dh-4)` thumbnail pad caps fill at ~94.9% even for a fully solid render + ink ring (tree_a: 5824/6144 < 5836.8); a camera-clipped frame crops ~square → ~59% fill → passes. No legit sprite can ever fail it, and the pathology it describes can't trip it either | pin alpha-fill of the pre-thumbnail crop in `post_decor`, or assert transparent top-edge rows in smoke |
| 4 | MED | smoke never pins decor dims — the invariant that justifies "no code change" is untested (`smoke_test.gd:4227-4244`); a `post_decor.DIMS` drift silently shifts every anchor. Third hardcoded decor list (`smoke_test.gd:4228` vs `main.gd:14`, `DECOR_KIND`) | assert `get_width()/get_height()` per key; iterate `main.DECOR_KIND.values()` |
| 5 | LOW | normalize assumes origin+unit-scale source (`render_decor.py:114-126`): `src.scale = k` replaces absolutely — correct iff scale==1/location==0 (true for these blends, verified); wrong by `1/s0` + `T(1-k)` on baked transforms. `meshes[0]` is alphabetical-first, not main — WARN honest but siblings render unnormalized (kin contract, audit-52) | two-pass measure (scale→re-measure→correct) or assert; pick largest-volume mesh |
| 6 | LOW | `if not o.hide_get(): o.hide_render = False` (`render_decor.py:90-92`) leaves viewport-hidden + render-enabled objects live — same latent quirk copied from kin audit-53 | also set `hide_render=True` on hidden objects, or document the intent |
| 7 | LOW | paste margin `dh - img.height - 1` (`post_decor.py:34`) = 1px floor gap vs old placeholders' 2–6px → decor sits ~1–5px lower on its tile (screenshot reads fine) | optional `-2` for parity with the old look |
| 8 | LOW | doc/hygiene nits: PROVENANCE omits the 5 unused kept blends (other pack sections list theirs); no `batch_decor.sh` — re-render is 14 manual invocations, WARNs not surfaced like batch_mesh does; `mat()` comment premise is slightly off (both pipelines create fresh materials — the in-place recolor it warns about was never the plan; the explicit rebuild is equivalent but more robust); ROADMAP 974 = +3 over S101's 971 for +1 check | doc touch-ups; optional batch script |

## Verified clean by the audit

- **Dims**: all 7 PNGs read back identical to the `gen_assets.py` originals —
  tree_a/tree_b 64×96, rock/ore_gold/ore_coal 64×40, berry_bush 64×56,
  stump 48×30. `main.gd:136` anchors on `tex.get_height()` only (Sprite2D
  centers horizontally) → zero-code-change claim holds.
- **Semantics**: `World.Decor` enum untouched (world.gd:22); `DECOR_KIND`
  covers all 7 non-NONE values; harvest loot table covers all kinds,
  TREE→STUMP + regrowth + `decor_sync`/`decor_snapshot_apply` byte clamps
  intact (game.gd:2180-2214, 2677-2682, 7272-7295).
- **render_decor**: `pal` dict creates exactly one material per `mat_map`
  entry — no accidental duplication; slot-replace + dead/bare WARN is the
  kin contract; normalize math exact under the origin/unit-scale assumption
  that holds for these 5 blends; bad-id/empty-blend crash loudly.
- **post_decor**: blank-render bail at <50 px of alpha>40 (same as kin);
  thumbnail+paste math verified (feet land 1px above floor); identical
  cel→warm→fit→violet→halftone→ink chain order as `post_kin.process`.
- **smoke pin**: `ink>=2` cannot false-fail — `ink_outline` guarantees a
  ≥8-px ring for any blob and INK (28,26,46) satisfies the dark-pixel test;
  `load_from_file` reads source bytes, so the check is immune to import
  staleness.
- **Licensing/hygiene**: `src/nature/License.txt` is CC0 1.0 in-tree;
  PROVENANCE lists all used blends incl. the Rock_2 triple-use;
  `tools/art/src/.gdignore` covers nature/; `tools/art/render/` gitignored +
  `.gdignore`; `tools/*` export-excluded → no PCK leak.
- **Evidence**: `docs/reviews/s102-world.png` shows the new meshes in-game
  (also proves the .ctex reimport ran); 7/7 x4 previews inspected — correct
  silhouettes, ink contour, readable berries/ore tints.

## Caveats

- No shell access this run — `git status`/`git diff HEAD`/`git show` blob
  compares were not executed; all files verified by direct reads and
  `gen_assets.py` as dims authority. Confirm the diff contains no unlisted
  files before closing.

## Resolutions (implemented by parent)

| # | resolution |
|---|-----------|
| 1 | `decor()` gated behind `--decor-legacy` in `gen_assets.py` — same pattern as `--kin-legacy` |
| 2 | `render_decor.py` now uses the exact `light_rig()` values: warm square key 900/4.0/(1.0,0.93,0.82), soft cool fill 260/5.0/(0.62,0.68,1.0), world ambient Background 0.55/0.35 — all 7 re-rendered under the real kin rig |
| 3 | dead total-fill threshold replaced by a TOP-band transparency pin (top 10% rows ≤60% opaque — a clipped/full-bleed frame fills the top edge, a framed sprite thins out there) |
| 4 | per-key `get_width()/get_height()` assertions added for all 7 decor ids |
| 5 | normalize now multiplicative (`scale *= k`) with folded location `(T - bound) * k` — correct for baked transforms; main mesh picked by largest bound-box volume, not alphabetical |
| 6 | `o.hide_render = o.hide_get()` — source-author intent honored both ways |
| 7 | paste floor margin 1px→2px |
| 8 | PROVENANCE lists the 5 kept-but-unused blends; batch script deferred (7 decor re-rendered via the documented loop) |

Re-verify: `python3 tools/gen_assets.py` no longer rewrites decor;
smoke 971/0/1skip with the dims + top-band pins active.
