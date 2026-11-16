# Audit-58 — S105 structure sprite migration cold review

**Scope**: S105 migration of all 50 `assets/structures/*.png` from flat
procedural PIL art to `tools/art/render_structure.py` (procedural Blender
geometry) + `tools/art/post_structure.py`, the `gen_assets.py` `--struct-legacy`
gate + `migrated` whitelist, the `smoke_test.gd` structure pins, and
`tools/shot_struct.gd`. Read-only cold audit by a context-free subagent; all 50
shipped PNGs inspected directly (dims + pixels), plus the four batch evidence
shots `docs/reviews/s105{,b,c,d}-structures*.png`. Commit messages not trusted —
everything below is verified against files and pixels.

**Verdict**: NEEDS-FIX — all 50 shipped sprites are verified good (correct dims,
nonblank, cel-shaded Blender renders, ink-contoured, bottom-anchored,
identity-plausible, whitelist/dims tables pairwise-exact), but the smoke
top-band clip pin is mathematically dead for 33/50 sprites and effectively dead
for ~47/50 — the stage's only camera-clip guard cannot fire for exactly the
tall thin structures most at risk. Same defect class as audit-55 finding 3,
re-emerged with new constants.

## Findings

| # | sev | finding | recommended fix |
|---|-----|---------|-----------------|
| 1 | HIGH | **The top-band transparency pin cannot fire for 33/50 sprites and is effectively dead for ~47/50.** `post_structure.py:52-54` fits content inside `(dw-8, dh-8)` and pastes at `dh - img.height - 2`, so opaque content can never start above row 6 (ink ring ≥ row 5). The smoke pin (`smoke_test.gd:4294-4307`) requires >60% of the top-10% band opaque. For h=104 (25 ids incl. watch_tower, war_banner, lightning_rod, guard_post, kin_cage): band=10 rows, fillable rows 5-9 → max `5×80=400 < 0.6×10×80=480` → **unreachable**. For h=120 (8 ids): `7×112=784 < 806.4` → unreachable. For h=136 (14): a square-clipped frame thumbs to 128-wide → `8×128=1024 < 1123.2` → dead unless the clipped crop is wider than ~1.1:1. For h=134/h=166 (3): fires only if the clip leaves a >~1.33:1 crop — realistically only reachable on berry_farm/wheat_farm/ranch. A mid-torso camera clip on any 1-tile structure passes dims+opaque+ink+top-band silently. No left/right/bottom edge check exists at all (a bottom clip is the worse defect — `game.gd:2831/2886` anchors `p.y - h*0.5 + 8`, assuming PNG bottom = ground line). | Move the clip check into `post_structure.py` on the **pre-thumbnail** alpha crop: assert the crop's edge rows/cols are mostly transparent (a clipped frame has a flat solid edge, a framed sprite tapers to spires/roofs). Or in smoke, measure the opaque fraction of the sprite's *first opaque row* (spire tip = narrow, clipped top = ~full-width flat). Cover all four edges. |
| 2 | MED | **CFG `"h"` and documented `rot_z` are dead fields** (`render_structure.py:17-71`): only `build`/`ortho`/`tz` are consumed (lines 553, 578, 583); `h` is set on all 50 entries but never read, `rot_z` is in the header comment but in no entry and unimplemented (unlike `render_decor.py:98`). Worse, `h` under-reports real build tops — watch_tower h=2.4 vs actual top 2.50, guard_post 1.6 vs 1.90, war_banner 1.7 vs 1.83 — so it can't serve as a clip-lint input as-is. | Either wire `h` into a frame-fit lint (`actual_top < tz + ortho·cos(pitch)/2`, replacing `h` with measured tops) or drop the fields and fix the comment. |
| 3 | LOW | **Furnace `fire` cube fully occluded** (`render_structure.py:239-240`): fire spans y∈[-0.53,-0.47], mouth spans y∈[-0.57,-0.47] — the emissive cube sits inside the opaque dark mouth → contributes zero pixels (the dark mouth still reads as a firebox; night glow is game-side `add_glow`). | Move fire in front of the mouth face (y≈-0.58), or build the mouth as a frame with the fire visible inside. |
| 4 | LOW | **`build()` has no `else`** (`render_structure.py:143-543`): an unmatched `cfg["build"]` silently constructs an empty scene; `main()` still prints "rendered struct X" and only post's `<50 opaque px` check catches it downstream (loud, but late and mislabeled as success). | `else: raise RuntimeError("unknown build kind %s" % kind)`. |
| 5 | LOW | **No batch driver; invocation omits `--python-exit-code`** (header line 5; cf. audit-51/batch_mesh.sh:34): a script exception inside a shell loop exits Blender 0 → false "ok". 50 renders + 50 posts are manual invocations today; audit-55 deferred the same gap for decor. | Add `batch_struct.sh` mirroring `batch_mesh.sh` (exit-code AND post-exit-code checks, per-id logs, WARN surfacing). |
| 6 | LOW | **Doc/hygiene nits**: `PROVENANCE.md` has S103/S104 "fully procedural, no external mesh" sections but no S105 entry — the provenance chain breaks at exactly the largest procedural batch. `import mathutils` unused (line 11). `sparring` allocates a duplicate `"rope"` material per torus (rope/rope.001, harmless). `sphere_factory_2` dome `emit=1.6` renders near-white — HANDOFF's own S105a note warns emit approaches the Standard-transform white clip; the intended violet reads pale cream (cosmetic; drop to ~1.1-1.2 if violet is wanted). | Add S105 provenance section; drop the import; hoist the rope material; optionally retune dome2 emit. |
| 7 | LOW | **Pin-suite residual blind spots** (accepted convention, recorded for completeness): same-size texture swaps (chest↔torch, both 80×104) are undetectable; a wrong-identity-but-inked sprite passes opaque+ink; `struct_dims` is a third hardcoded dims table alongside `post_structure.DIMS` and the `struct_img` formula — self-consistent today, triply maintained tomorrow. | Optional: assert `struct_dims.keys() == STRUCT_DEFS.keys()` in smoke, or derive one table from the other. |

## Verified clean by the audit

- **All 50 PNGs inspected directly**: nonblank, cel-banded, ink-contoured,
  bottom-anchored, identity-plausible silhouettes. `sphere_factory` vs
  `sphere_factory_2` clearly distinguishable. No top/bottom clipping; every
  base sits at the frame bottom.
- **Dims contract**: all 50 `DIMS`, `struct_dims`, and the legacy
  `struct_img` formula agree byte-for-byte → anchor math unchanged.
- **Whitelist completeness**: `migrated` == `STRUCT_DEFS` == `CFG` ==
  `DIMS` == PNGs on disk == 50, pairwise exact.
- **No material_index anywhere** (audit-57 defect class absent);
  `roof_prism` topology correct; every `bpy.context.active_object` access
  follows an immediate `primitive_*_add`; `transform_apply(scale-only)`
  avoids the documented origin-zeroing trap.
- **Determinism**: no `random`/dict-order/version-sensitive paths.
- **Blank-render safety**: post `<50 opaque px` bail + smoke `opaque<40`
  pin double-catch blanks.
- **Anchoring**: lowest content px at dh-3 — same floor contract as
  post_decor; in-game shots show correct ground contact incl. night glow.
- **Consistency**: rig/camera/post chain verbatim from the decor pipeline.

## Resolutions (implemented by parent)

- HIGH-1: clip detection moved into `post_structure.py` on the
  pre-thumbnail crop — all four edges must be <60% opaque (a clipped frame
  has a flat solid edge; a framed sprite tapers to tips/ground contact).
  In smoke, the top-band pin is replaced by a first-opaque-row width pin
  (spire tip = narrow, clipped top = ~full-width flat).
- MED-2: `h`/`rot_z` dead fields dropped from CFG + header comment.
- LOW-3: furnace fire moved in front of the mouth face.
- LOW-4: `build()` now raises on unknown kind.
- LOW-5: `tools/art/batch_struct.sh` added — `--python-exit-code` on both
  stages, per-id logs, WARN surfacing, mirror of batch_mesh.sh.
- LOW-6: PROVENANCE S105 section added; unused import dropped; sparring
  rope material hoisted; sphere_factory_2 dome emit 1.6→1.15.
- LOW-7: smoke asserts `struct_dims` covers every `STRUCTURES` id.
