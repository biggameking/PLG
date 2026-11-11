# Kin Art Pipeline — Blender → post → `assets/kin/`

Replaces `tools/gen_assets.py` shape-stacking for species sprites, one species
at a time. Preferred source: **licensed rigged meshes** (CC0, GitHub/HF) —
render_src_asset.py upgrades them to our look. Primitive rigs
(render_kin.py RIGS/RIGS_GEN) remain the fallback when no source exists.

## Flow — source-asset path (preferred)

```
tools/art/src/<pack>/… .blend            (downloaded, licensed, see PROVENANCE)
   │  blender -b <model.blend> -P tools/art/render_src_asset.py -- <sid>
   │    · splits wool/skin materials · Subsurf×N (×60-140 base faces)
   │    · procedural displace on wool · puff-shell fleece (bone-parented)
   │    · auto-placed ink eyes/nose on the Head bone · palette recolor
   │    · drives the model's OWN armature action → real skeletal frames
   ▼
tools/art/render/<sid>_f{0,1}.png        (512px raw EEVEE render)
   │  python3 tools/art/post_kin.py <sid>
   │    · alpha crop → 5-level cel banding (hue kept) → warm pastel lift
   │    · violet shade → halftone dots in shade → navy ink contour → 80×64
   ▼
assets/kin/<sid>_f{0,1}.png + render/<sid>_f{0,1}_x4.png (review preview)
   │  godot --headless --path . --import   (AGENTS.md rule 7)
   ▼
godot --path . -s tools/shot_kin.gd      → /tmp/plg-kin-<sid>.png
```

## Authoring a new species (source path)

1. Species data first: `src/data/species.gd` color/description/body plan must
   read in the final sprite.
2. Find a licensed mesh (CC0 > CC-BY). Quaternius packs on OpenGameArt /
   poly.pizza cover most quadrupeds/creatures. Record in `PROVENANCE.md`
   BEFORE shipping the sprite.
3. `render_src.py` quick-view the raw model to check pose/materials.
4. Add `CFG["<sid>"]` in render_src_asset.py: wool material index, palette,
   subd levels, displace, rot_z (face the camera), action + frame pair,
   eye params (head bone auto-solve), puff shell for woolly species.
5. Render → post → shot_kin → review x4 + in-game shot. Iterate CFG, not post.

## Primitive path (fallback)

`render_kin.py` RIGS/RIGS_GEN: dict-driven parts (sph/cyl/fluff), isometric
camera, same post. Use only when no rigged source fits the species.

## Look rules (post_kin.py — shared, tune globally not per-species)

- `Standard` view transform, never AgX (filmic desaturation kills the poster).
- `LEVELS/EDGES`: five absolute luminance bands → cel flats, hue preserved.
- Shade drifts toward `VIOLET` (#5b4a8a) below luma 100; halftone dots in the
  same band — COO's "shadow is dot density, not darkness".
- `INK` (#1c1a2e) contour: outside edge + alpha rim + interior-edge solidify.

## Provenance

`PROVENANCE.md` — every external mesh/texture source + license. CC0/CC-BY
only; CC-BY entries also land in the credits file.
