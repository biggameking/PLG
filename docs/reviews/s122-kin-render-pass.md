# S122 — kin render pass: the 12 licensed meshes stopped reading as blobs

## What the audit found

All 120 species render from licensed .blend sources (107 CFG_EXT + 13
hand-tuned in `render_src_asset.py`) — the "ellipsoid kits" only survive
in the legacy `rigs_gen` fallback path, which feeds nothing. The real
defect was **per-species render tuning**: six CFG'd species — including
all four S108 den wardens — produced unreadable sprites:

| species | was | fix |
|---|---|---|
| `dreadwyrm` | wings folded over the body at `Dragon_Flying` f10 — a red lump | frames (20,30) spread wings + show belly |
| `tidscale` | `target_h` 0.80 normalized a long fish to a sliver; `Idle` action doesn't exist in the blend | `Swimming` (10,30), `target_h` 1.35 |
| `dozantler` | rear-to-camera grazing pose read as a hump; name's antlers never delivered | `rot_z` 45 side profile, `horns` accessory, frames (20,80) |
| `gloamwing` | upright bat at `target_h` 1.2 rendered a speck | 1.5, frames (0,15) |
| `cragmaw` | single `eye_fwd` 0.72/r0.13 bead buried behind the chibi brow; rot 35 hid the face | rot 0 front-on, bead 0.95/0.17 clears the brow |
| `hexfiend` | same class — rot 35 + buried beads left a pink ball | rot 0, beads 0.90/0.10 |

## Method (evidence, not vibes)

- `tools/art` probe script (throwaway `/tmp/probe_variants.py`): opens each
  .blend, poses the armature through `(action, frame, rot_z)` grids, renders
  16–20 variants per species in one Eevee session — picks by rendered
  evidence, not guesswork.
- Probe confirmed Cyclops/Demon ship `Texture`-mats whose image files are
  absent — face detail must come from geometry + the bead system, so the
  fix was bead projection + facing, not a texture rescue.
- Before/after sheets: `s122-kin-before.png` vs `s122-kin-after.png`;
  in-game captures `s122-ingame-dreadwyrm.png`, `s122-ingame-cragmaw.png`.

## Verification

- `post_kin` cel pipeline unchanged — same poster levels for all 120.
- smoke **1048/0/0skip** after re-import; no code touched besides CFG.
- Assets: 12 PNGs regenerated (f0+f1 × 6 species).
