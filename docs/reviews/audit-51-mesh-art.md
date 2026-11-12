# audit-51 — S98 mesh-migration stage cold review

Context-free subagent review of commits bae8121/522b320/d2a6667
(8 hand + 52 generated + fenjelly = 61/116 species on source meshes).

## Verified clean
- CFG_EXT body→mesh assignments all match `SpeciesData.body_of()`
- generated file unmarked-hand-edit; CFG.setdefault merge correct
- mountable species all map to quadrupedal meshes
- all 116×2 frames + .import sidecars exist; tools/ excluded from PCKs

## Findings fixed in c3a318a
- HIGH batch_mesh.sh: blender without --python-exit-code → false "ok";
  no post_kin step at all. Both fixed + empty-list guard.
- MED silent degradations now WARN: unused/uncolored mat_map slots,
  missing head_bone (eyeless), missing/out-of-range action (f0==f1).
- MED ACCESSORY_SIDS now `rig_auto.ACCESSORY - HAND`; scalcrest/tidscale
  hand-accepted mark loss documented.
- MED animal_pack2 vendored License.txt; PROVENANCE tables current.

## Open (next stages)
- mesh accessory layer (crowns/halos/horns) to migrate the 8 mark species
- ghost/human/blob/hedgehog/monkey (48 spp.) need new CC0 sources
- bird Idle frame could pick a clearer wing pose
- smoke could assert f0!=f1 per species

Evidence: batch sheet 52/52 silhouettes, in-game shot frostfang pack,
smoke 967/0/1skip, audit_data+check_ip CLEAN.
