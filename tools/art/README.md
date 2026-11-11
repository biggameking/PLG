# Kin Art Pipeline — Blender → post → `assets/kin/`

Replaces `tools/gen_assets.py` shape-stacking for species sprites, one species
at a time. Each species is a rigged primitive build in Blender, rendered at
512px, then posterized/inked/halftoned down to the game's 80×64 sprite.

## Flow

```
RIGS entry (tools/art/render_kin.py)
   │  blender -b -P tools/art/render_kin.py -- <species_id>
   ▼
tools/art/render/<sid>_f{0,1}.png          (512px raw EEVEE render)
   │  python3 tools/art/post_kin.py <species_id>
   ▼
assets/kin/<sid>_f{0,1}.png                (80×64 game sprite)
   + tools/art/render/<sid>_f{0,1}_x4.png  (4× review preview)
   │  godot --headless --path . --import   (AGENTS.md rule 7)
   ▼
godot --path . -s tools/shot_kin.gd        → /tmp/plg-kin-<sid>.png
```

## Authoring a new species

1. Read the species entry in `src/data/species.gd` (color, glyph, description,
   body plan) — the rig must read as that description at 80px.
2. Add a `RIGS["<sid>"]` entry: `mats` (fleece/skin/ink palette as linear RGB)
   + `parts` list. Kinds: `sph` (ellipsoid via r tuple), `cyl`, `fluff`
   (deterministic squashed-sphere cluster — seed makes it reproducible).
   `f1` dict = idle-frame deltas (bob, ear lift).
3. Coordinate convention: ground plane z=0, creature ~1.5–2.0 units tall,
   faces -Y. Camera is a fixed ortho ¾ view — do not move it per-species.
4. Render + post + shot_kin. Review the `_x4.png` preview AND the in-game
   screenshot. Iterate on the rig, not the post knobs — post is shared.
5. External CC0 meshes (GitHub/HF): import in `build()`, scale to the same
   unit convention, apply the same `mat()` slots. Record source + license in
   `tools/art/PROVENANCE.md`.

## Look rules (post_kin.py — shared, tune globally not per-species)

- `Standard` view transform, never AgX (filmic desaturation kills the poster).
- `LEVELS/EDGES`: five absolute luminance bands → cel flats, hue preserved.
- Shade drifts toward `VIOLET` (#5b4a8a) below luma 100; halftone dots in the
  same band — COO's "shadow is dot density, not darkness".
- `INK` (#1c1a2e) contour: outside edge + alpha rim + interior-edge solidify.

## Provenance

`PROVENANCE.md` — every external mesh/texture source + license. CC0/CC-BY
only; CC-BY entries also land in the credits file.
