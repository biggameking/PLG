# audit-61 — S108 den wardens cold review

**Scope**: 4 new den-exclusive legendaries (gloamwing/cragmaw/hexfiend/
dreadwyrm), LEGENDARY_DEN 10→14, `norm_obj` renderer path, species data,
smoke pins, evidence harness `tools/shot_den.gd`.

**Verdict**: NEEDS-FIX → **all findings resolved** (0 HIGH, 2 MED, 11 LOW).

## Resolved

| # | Sev | Finding | Resolution |
|---|-----|---------|------------|
| M1 | MED | Pre-S108 sealed Accord saves silently unseal — heirs=10 < new 14 roster → `accord=false` → 6th party member quietly drops | `game.gd:4784` grandfathered: heirs bar = `mini(LEGENDARY_DEN.size(), 10)` (roster size at the time sealing was possible). Anti-forgery surface unchanged — still requires `d["accord"]` + crown + EX + ≥10 heirs. New smoke pin crafts the exact save shape and asserts survival |
| M2 | MED | `docs/reviews/s108-*.png` missing `.import` sidecars — broke the tracked-sidecar convention every sibling evidence PNG follows | `--import` pass regenerated all sidecars; committed |
| L1 | LOW | "den-exclusive" pin half-tautological — `acquirable()` conjuncts are entailed by DEN membership | Pin renamed to the honest assertion (roster membership); pool exclusion stays covered by the global "zone pools carry no legends" pin |
| L2 | LOW | 5 stale "ten-name"/"tenth name" comments after roster growth | All rewritten roster-neutral |
| L3 | LOW | `shot_den.gd` missing `.gd.uid` | Generated via import pass, committed |
| L4 | LOW | `rigs_gen.py` out of sync with regeneration contract (dump +4 species) | `rig_auto.py` re-run — +67 lines, only the 4 new entries, zero unrelated diff |
| L6 | LOW | First-armature ambiguity: `next(o for o in objects if type==ARMATURE)` picks bpy.data order — with 2 armatures (Dragon+Eye), rot_z/action/eye anchors could land on the wrong rig silently | `arm = src.find_armature() or next(...)` — the processed mesh's own deformer, with explicit no-armature error |
| L10a | LOW | `shot_den.gd` decor access depends on `or` short-circuit after bounds-checked `blocked()` | Load-bearing ordering commented |
| L10b | LOW | Heir-pass spawned `boss=true` — real heirs are non-boss alpha | Heir pass now `boss=false` (α name bar in re-shot evidence confirms) |
| L11 | LOW | `s108-warden-sprites.png` canvas sized 1280w — last 4 frames clipped, sheet showed only 2 species | Regenerated at 2560w — all 8 frames verified |

## Accepted as-is (pre-existing / consistent)

- **L5** raw `zone_pool(3)` legend channels (summon_raid boss, grotto deep
  room) — predates S108, widens rather than introduces; den pool remains
  the only *catchable* source.
- **L7** `net_den` `dn=-1` clamp path — unreachable at the sole call site.
- **L8** balance nits (work totals 7 vs typical 4-5; cragmaw `stone` drops)
  — tier-3 stats/skills/elements/hostile all properly shaped; cosmetic.
- **L9** `habitat()` reports zone 3 for den-exclusives — same as the old 10.

## Verified clean by auditor

Every 10→14 consumer is dynamic (`den_caught`, `tick_accord`, save-heirs,
HUD DEN %d/%d, net_den clamps, spawn filter, heir re-roll fresh filter,
grotto pick, spire fallback, catchable, hatch_pool, merchant stock,
ownable_species_count, dex_full, accord smoke pin). `norm_obj` skips the
bake loop only when an armature owner resolves, floor-drop runs for both
paths, residual measured + 3% WARN. All 4 CFGs consume only existing keys.

## Residual (new, not from this stage)

Smoke run during fixing showed 3 transient `sync_pos` failures once, then
clean across reruns — the step-candidate fixture can pick a destination
past the step cap on some world layouts (rule-42 class flake, pre-existing).

## Evidence

`docs/reviews/s108-warden-sprites.png` (4 sp × f0/f1 ship pixels),
`s108-den-wardens.png` (2.5× warden lineup + BOSS bar),
`s108-den-heirs.png` (1.0× α-heir lineup). Smoke **987/0/0skip**.
