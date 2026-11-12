# Asset provenance

Every non-original source used by the art pipeline. CC0/CC-BY only.

| asset | source | license | used in |
|---|---|---|---|
| fenjelly rig | built by hand in `render_kin.py` from Blender primitives | original work | `assets/kin/fenjelly_f{0,1}.png` |
| auto rigs | `tools/art/rig_auto.py` → `rigs_gen.py` — 13 archetypes parameterized from `species_dump.json` (body/color/elements), seeded per id | original work | `assets/kin/<sid>_f{0,1}.png` for 115 non-fenjelly species |
| farm animals pack — `Sheep.blend` (307-face mesh + 24-bone armature + Idle/Walk/Run/Jump/Death actions) | `tools/art/src/farm_animals/` — Quaternius (patreon.com/quaternius), opengameart.org/content/lowpoly-animated-farm-animal-pack | CC0 1.0, `License.txt` in-tree | loaded by `render_src_asset.py` → `assets/kin/fenjelly_f{0,1}.png`; other six animals (cow/horse/pig/llama/pug/zebra) available for future species |
| `render_src.py` | renders a source `.blend` for inspection | original work | tooling only |

## Quaternius "Animal Pack Vol.2" (CC0 1.0)

Downloaded from https://opengameart.org/content/animated-animales-low-poly
(direct zip: Animal Pack Vol.2 by @Quaternius.zip). Stored under
`tools/art/src/animal_pack2/`. Used meshes: Eagle, Wolf, Cat, Piranha, Dog —
armature-animated, CC0 1.0.
