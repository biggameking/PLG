# Audit-53 — accessory anchor layer cold review

**Scope**: S100 accessory layer (`add_accessory`, `head_anchor`,
`head_group_top`, `real_head_bone`), `batch_mesh.sh`, `mesh_map_gen.py` /
`mesh_cfg_gen.py` determinism, artifact hygiene. Read-only cold audit by a
context-free subagent, then each finding verified and fixed.

**Verdict**: NEEDS-FIX — pipeline honest and deterministic, 10/10 accessory
species present, no PCK leak path; but five geometric defects produced
misplaced marks on shipped species, plus a post-stage blind spot.

## Findings → fixes

| # | sev | finding | fix |
|---|-----|---------|-----|
| 1 | MED | `put()` dims world-axis while `p` in (lat,fwd) frame — rotated rigs got misoriented marks (flarbeak crest lateral at rot_z=90, nibhand mask skewed ~35°) | sphere dims now expressed in the `(lat, fwd, z)` basis via `basis @ Diagonal` |
| 2 | MED | `hw_lat`/`hw_fwd` measured a full-width z-slab — torso/wings inflated "head width" (Horse halo ~1.5× head) | filter now requires the z-band AND `|lv|<0.5s, -0.6s<fv<0.6s` around the face |
| 3 | MED | silhouette-top fallback silently parked a crown on a wingtip | `WARN accessory anchor fell back to silhouette top` — batch surfaces it |
| 4 | MED | `head_anchor` -Y fallback ignored `rot_z` — eyes skewed ~35° on every rotated humanoid (23 generated species) | fallback fwd carried through `arm.matrix_world` yaw |
| 5 | MED | `real_head_bone` vote could be captured by a raised wingtip near the beak xy | distance-weighted tally `w/(1+d)` + 1.5× margin before overriding cfg |
| 6 | MED | `_loc_fcurves` yielded the same FCurve through layered AND flat APIs on Blender 4.4/4.5 → location keys scaled twice per normalize pass | dedupe by `fc.as_pointer()` (not `id()` — wrappers are per-access) |
| 7 | MED | `post_kin` shipped a fully-transparent render as "ok" | bails nonzero when opaque px < 50 |
| 8 | LOW | eye z-clamp was a global height fraction; grazing/low-snout rigs get eyes dragged off the muzzle; xy unclamped | band clamp `t.z ± 0.35s` + horizontal offset cap `0.6s`; nose floor relative to tail |
| 9 | LOW | dead code: `rest_m`, `ACCESSORY_SIDS`, inner `import colorsys` | removed |
| 10 | LOW | `hide_render=False` unhid author-hidden helpers/cutters | only unhide when `not o.hide_get()` |
| 11 | LOW | `tools/art/render/` had no `.gdignore` (import churn) | added |
| 12 | LOW | `setup_visuals` bare `load()` → null texture possible | chest.png fallback per the load contract |
| 13 | LOW | fixed `/tmp/mesh_*` paths; batch only covered CFG_EXT (107) — hand CFGs had no batch signal; PROVENANCE stale "8 accessory species still primitive" | `mktemp -d`; batch list now emits hand entries (blend resolved from `# Xxx.blend` comment + src walk, fenjelly→Sheep) = 116; PROVENANCE corrected |

## Verified clean by the audit

- `bone_attach` math correct; f0-pose-before-attach ordering correct
- `normalize()` two-sided bake, bounded 10 passes, unconverged WARN
- `batch_mesh.sh` truthfulness: `ok` requires blender-exit-0 AND post-exit-0;
  WARN re-surfaced on both paths; empty list exits 1
- `mesh_map_gen.py` byte-deterministic (regen → zero-diff)
- 10/10 accessory species present (8 generated + 2 hand), matches
  `rig_auto.ACCESSORY` exactly
- no PCK leak path: `tools/art/render/` gitignored + export-excluded +
  `.gdignore`; `src/` `.gdignore` covers blends; `assets/kin/` conforming

## Regen evidence

- Full 116 batch re-render after anchor/basis changes: `batch_mesh.sh`
  116 entries (107 generated + 9 hand)
- smoke suite, sprite pixel pins (scalbeak crown >6, vermtrot fan >4),
  audit_data, check_ip — see commit trailer
