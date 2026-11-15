# Asset provenance

Every non-original source used by the art pipeline. CC0/CC-BY only.

| asset | source | license | used in |
|---|---|---|---|
| fenjelly rig | built by hand in `render_kin.py` from Blender primitives | original work | `assets/kin/fenjelly_f{0,1}.png` |
| auto rigs | `tools/art/rig_auto.py` → `rigs_gen.py` — 13 archetypes parameterized from `species_dump.json` (body/color/elements), seeded per id | original work | primitive route retired — all species ship mesh sprites; `rig_auto.ACCESSORY` remains the identity-mark reference for the mesh accessory layer |
| farm animals pack — `Sheep/Cow/Pig/Horse.blend` (lowpoly meshes + armatures + Idle/Walk/Run/Jump/Death actions) | `tools/art/src/farm_animals/` — Quaternius (patreon.com/quaternius), opengameart.org/content/lowpoly-animated-farm-animal-pack | CC0 1.0, `License.txt` in-tree | Sheep→fenjelly; Cow→piplump/ripbell/statchew/snovmool/cindchew(crest via accessory layer); Pig→digsnout/loampuff; Horse→dozantler/petalantler/statstride/snovfawn/snovstride(halo via accessory layer); Llama/Pug/Zebra unused |
| `render_src.py` | renders a source `.blend` for inspection | original work | tooling only |

## Quaternius "Animal Pack Vol.2" (CC0 1.0)

Downloaded from https://opengameart.org/content/animated-animales-low-poly
(direct zip: Animal Pack Vol.2 by @Quaternius.zip). Stored under
`tools/art/src/animal_pack2/`, `License.txt` in-tree. Used meshes: Eagle→all
`bird` species; Wolf→`quadruped`+`mouse`; Cat→`kitty`; Piranha→`serpent`;
Dog→cindpaw — armature-animated, CC0 1.0.

## Quaternius "Cute Animated Monsters" (CC0 1.0)

https://opengameart.org/content/textured-cute-monster-pack — stored under
`tools/art/src/cute_monsters/`, `License.txt` in-tree. Used: Ghost→all `ghost`,
Cactus→`hedgehog`, Yeti→`monkey`, Alien_Tall→`human` species (rot_z≈35° —
front view is head-only; the angle exposes the raised arms). Cyclops/Demon
were probed and rejected — same head-dominant silhouette.

## Quaternius "Animated Monster Pack" (CC0 1.0)

https://opengameart.org/content/lowpoly-animated-monsters — stored under
`tools/art/src/monsters_basic/`, pack's own `License.txt` in-tree. Used:
Slime→all `blob` species (`no_eyes` — the mesh's own eye material is used).
Bat/Dragon/Skeleton blends kept for future bodies — Skeleton was probed for
`human` and rejected (detached bone segments read as floating fragments).
