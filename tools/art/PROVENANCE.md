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
front view is head-only; the angle exposes the raised arms) AND the `player`
rancher (S101: zone_mats outfit bands, `hat` accessory, baked eyeball/mouth
mesh islands stripped via `strip_islands`). Cyclops/Demon were probed and
rejected — same head-dominant silhouette.

## Quaternius "Animated Monster Pack" (CC0 1.0)

https://opengameart.org/content/lowpoly-animated-monsters — stored under
`tools/art/src/monsters_basic/`, pack's own `License.txt` in-tree. Used:
Slime→all `blob` species (`no_eyes` — the mesh's own eye material is used).
Bat/Dragon/Skeleton blends kept for future bodies — Skeleton was probed for
`human` and rejected (detached bone segments read as floating fragments).

## Quaternius "Ultimate Nature Pack" (CC0)

Downloaded from
https://opengameart.org/sites/default/files/ultimate_nature_pack_by_quaternius_1.zip
(pack page: https://quaternius.com/packs/ultimatenature.html). Stored under
`tools/art/src/nature/`, pack's own `License.txt` in-tree. S102 decor
migration — used meshes, via `tools/art/render_decor.py` + `post_decor.py`:

- PineTree_2 → `tree_a` (conifer)
- BirchTree_1 → `tree_b` (round canopy, source White/Black birch bark)
- BushBerries_1 → `berry_bush`
- Rock_2 → `rock`, `ore_coal` (dark), `ore_gold` (warm) — recolor variants
- TreeStump_Moss → `stump`

Output dims match the replaced sprites exactly (bottom-anchor semantics of
the decor pool in `src/main.gd` preserved — no code change needed).
Note: legacy blends carry double-output node trees whose render output is a
DIFFUSE node — `render_decor.py` rebuilds a clean Principled material when
recoloring (setting Principled inputs on the source material reaches nothing).

Kept-but-unused blends for future decor/POI work: CommonTree_1, Flowers,
Grass, Rock_Moss_3, WoodLog_Moss.

## S103 ground tiles — fully procedural Blender geometry (no external mesh)

`tools/art/render_tile.py` builds each ground cell procedurally (slab +
cones/icospheres/tori/cubes detail) under a dimetric camera (az 45°, el 30°
→ the game's 2:1 diamond) and the kin light rig; `post_tile.py` masks to
the exact diamond (no ink outline — cell edges are shared with neighbors);
`build_tiles.py` assembles tiles.png/tiles.json (wall/stair/marker cells
still come from gen_assets' procedural painters — the flat cliff look is
deliberate contrast). `gen_assets.py` atlas() is gated behind
`--tiles-legacy` (audit-55 lesson: gate every writer of a migrated file).

## S104 cliff walls — procedural Blender cube (no external mesh)

`render_wall.py` renders one 1x1xH cube under the same dimetric camera;
`post_wall.py` extracts the two visible side faces into wall_sx/sy/corner
cells by the game's own face geometry (edge + 16px drop), re-applying the
INK top line + lilac rim and post strata lines. Stair/marker cells stay
procedural — stepped treads read better flat.

## S105 structures — fully procedural Blender geometry (no external mesh)

All 50 `assets/structures/*.png` are produced by
`tools/art/render_structure.py` (per-id primitive builders: cube/cyl/
cone/ico/roof_prism under the shared kin light rig + upright 3/4 ortho
camera) and `tools/art/post_structure.py` (post_kin post chain, output
dims pinned byte-identical to the legacy sprites so the `p.y - h*0.5 + 8`
anchor is unchanged). `tools/art/batch_struct.sh` renders all 50 with
`--python-exit-code` on both stages. No external source assets; the flat
`make_structure` path in `tools/gen_assets.py` remains only behind
`--struct-legacy`.
