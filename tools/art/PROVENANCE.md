# Asset provenance

Every non-original source used by the art pipeline. CC0/CC-BY only.

| asset | source | license | used in |
|---|---|---|---|
| fenjelly rig | built by hand in `render_kin.py` from Blender primitives | original work | `assets/kin/fenjelly_f{0,1}.png` |
| auto rigs | `tools/art/rig_auto.py` → `rigs_gen.py` — 13 archetypes parameterized from `species_dump.json` (body/color/elements), seeded per id | original work | `assets/kin/<sid>_f{0,1}.png` for 115 non-fenjelly species |
| farm animals pack | `tools/art/src/farm_animals/` — Quaternius (patreon.com/quaternius) | CC0 1.0, `License.txt` in-tree | reference geometry only during rig exploration; **not loaded** by the shipped pipeline — `tools/art/render/src_sheep.png` |
| `render_src.py` | renders a source `.blend` for inspection | original work | tooling only |
