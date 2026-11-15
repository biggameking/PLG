# Audit-54 — cold review of S101 `player` sprite migration

Scope: `tools/art/render_src_asset.py` (CFG["player"], `zone_mats` branch,
`strip_islands`, `hat` accessory, `eye_abs_z`, `acc_col`), the smoke-test
sprite sweep, `HANDOFF.md`/`PROVENANCE.md` notes, and the produced
`player_f{0,1}.png` sprites. Verified against the actual `.blend` sources
with Blender probes and a live re-render, not just code reading.

## Verified-good (checked, no defect)

- **Order claim is true.** `strip_islands` runs at render_src_asset.py:756–788,
  before `normalize` (:852), before `real_head_bone` (:857) and
  `head_group_span` (:894). Empirically `bmesh.ops.delete(context='FACES')`
  removes the verts too: 878→386 verts, 868→340 faces, **0 orphans**, so
  weighted verts are gone from the vgroups — `head_group_span`/
  `real_head_bone` are not corrupted by the strip.
- **The island filter deletes exactly the eyeballs.** Blender island
  enumeration on Alien_Tall: 8 islands doomed = 528 faces (the 4 baked
  eyeball white+pupil pairs); arms (2×52f, z_min 0.634), mouth islands
  (8f/20f, z_min<0.9), back spikes (20f each, y>0), body (108f) all kept.
- **Sprites are good.** player_f0/f1 512px renders and the 80×64 game
  sprite show: hat seated on the dome, two ink eyes on the face, zone
  bands correct (blue trousers / orange jacket incl. sleeves / skin head),
  a mouth bump below the eyes, f0≠f1. `ISLAND dropped 528 faces`,
  `PASS ext=2.09 kk=0.646 → kk=1.000`, no normalize warning.
- **Batch list resolves.** Ran the batch_mesh.sh heredoc verbatim: all 9
  hand entries resolve, `player → Alien_Tall.blend`; no duplicate `.blend`
  basenames under `tools/art/src/`.
- **Other 116 species unaffected by the new code paths.** `mat_map` and
  wool/skin branches untouched; `head_anchor` signature unchanged;
  `eye_abs_z`/`acc_col` are `cfg.get` gated (defaults reproduce old
  behavior); `mesh_map_gen.py` never emits `zone_mats`/`strip_islands`/
  `eye_abs_z`/`acc_col`, so generated entries can't reach the new code.
- **`zone_mats` + subdiv order is safe.** `materials.clear()` + 3 appends
  (:792–794) precede per-face `material_index` assignment by bind-z
  centroid (:795–801), all before `smooth`/`subdiv`; subdiv children
  inherit parent material. Zones are contiguous [0,1.01) so every face
  lands in a band.
- **`acc_col` reorder is correct** (:905–913): fallback accent → value
  floor → explicit override; dark `acc_col` intentionally skips the floor.
- **Smoke suite re-run green:** 968 checks, 0 failures.

## Findings

### HIGH-1 — Drive-by CFG regression: 3 shipped species pointed at a bone that does not exist

`tools/art/render_src_asset.py:94` (piplump/Cow.blend), `:104`
(digsnout/Pig.blend), `:112` (dozantler/Horse.blend): the S101 diff
changes `head_bone` `"Head"` → `"Head2"`. Blender probe of all three
rigs — Cow/Pig/Horse each end `…'Neck','Head','Hips','Torso',…` — **there
is no `Head2` bone**. `real_head_bone` early-returns the cfg name
(:376–377), `arm.pose.bones.get("Head2")` → `None` → `hb=None` →
"sprite will render EYELESS" WARN, `add_eyes` skipped (eyes AND nose —
all three set `nose_r`). `batch_mesh.sh` counts WARN as ok, so the next
full re-render ships three degraded sprites; piplump's `Black` slot
(0.24,0.22,0.28) passes the ink thresholds, so the smoke check would not
catch it. `mesh_map_gen.py` still emits `"Head"` for these same blends
(ripbell/loampuff/petalantler), confirming the edit is stray — likely a
bulk-replace copied from the player entry. Shipped PNGs are unaffected
(they were rendered under `"Head"`), so this is latent, not visible today.

Fix: revert lines 94/104/112 to `"head_bone": "Head"`.

### MED-2 — `head_bone: "Head2"` is self-rejected on every render; the cfg documents the wrong bone

Live render output: `WARN head_bone 'Head2' is not weighted at the head —
real driver 'Head3'`. `real_head_bone`'s weight vote remaps the bone, so
eyes + hat are actually bone-parented to **Head3** (the dome driver, vgroup
norm z 0.98–1.35), not the `Head2` the cfg and comments claim (face/mid
driver, 0.55–1.14). Output is correct today because `eye_abs_z` fixes z
and Idle tracks the bones together, but: (a) the cfg key is factually
wrong; (b) a permanent WARN in every batch log trains reviewers to ignore
WARN lines — the only tripwire for e.g. HIGH-1-style regressions; (c) the
remap is pose/vote-dependent — a different action or frame could vote a
different driver and move marks onto a bone that doesn't track the face.

Fix: set `"head_bone": "Head3"` (verifier already proves it owns the
skull); or add a `head_bone_hint` that skips the vote when intentional.

### MED-3 — `hat` anchors to the global silhouette top; works here by coincidence

render_src_asset.py:614 `hat_top = Vector((face.x, face.y, hi_z))` where
`hi_z = zcap[1]` (:494) is the **whole-mesh** evaluated top at f0 —
including raised arms, wings, or (here) the back stalks at y>0. On
Alien_Tall it happens to equal the Head3 cluster top (1.35) and the wide
brim rests on the dome shoulder, so the render is correct — but the
function already computes `htop`/`htop_z` (head-vgroup top + skull-column
fallback, :519–539) precisely to avoid appendage-top anchors, then the
`hat` branch ignores it. On any rig where an appendage exceeds the head at
f0 — or where the stalks were taller — the hat floats at appendage-tip
height centered on the face xy. Reuse hazard baked into a generic branch.

Fix: anchor `hat_top.z` to the head-band measurement (the `skull` column
max, or `htop_z` when it lands inside the dome band), and WARN when
`hi_z − anchor > 0.1·s` instead of silently trusting silhouette top.

### MED-4 — The smoke ink check cannot see the player's eyes; "face" coverage is overclaimed

`tools/smoke_test.gd:4190–4204`: `ink` counts any opaque pixel with
r<0.25,g<0.25,b<0.3. Measured on the shipped `player_f0.png`: **267 ink
px, ~100 in the top third (the hat)**. Worse, `post_kin.py`'s
`ink_outline` stamps INK (28,26,46) around every sprite's silhouette —
those pass all three thresholds — so *any* non-empty sprite already has
dozens of "ink" pixels regardless of facial features. The check verifies
"non-empty sprite with a contour", never "has a face": eyes missing,
buried in the dome, or hidden under the brim all pass. HANDOFF.md's
"sprite 像素断言已含 player" implies face coverage the assertion doesn't
deliver — and the same weakness makes HIGH-1 invisible for piplump
(Black spots = ink).

Fix: add a region-scoped pin for player (e.g., ≥2 ink clusters inside the
eye-band rows, like the scalbeak crown/vermtrot fin pins), or darken the
assertion: count ink px *inside the silhouette interior*, excluding the
1-px outline ring.

### LOW-5 — `strip_islands` heuristics are raw bind-space absolutes; partly luck-bound, unconditionally destructive

render_src_asset.py:783 `len(isl) < 200 and min(zs) > 0.9 and
max(ys) < -0.15` — in **un-normalized model units**, correct only for
this specific mesh. Verified on Alien: the arms survive *both* on z
(0.634 < 0.9) and on a y-margin of only **0.004** (arm y_max = −0.154 vs
the −0.15 cut) — the comment's rationale "arms (lateral, y≈0)" is
factually wrong; their real protector is z_min. Any future mesh where a
wanted island (teeth, inner ear, raised hand) satisfies all three
predicates is silently deleted — the only log is a face count. The flag
is also silently ignored outside the `zone_mats` branch (a `mat_map`
entry can't strip).

Fix: express thresholds as bind-height fractions; log each doomed/kept
island's stats (not just a count); accept an optional
`strip_expect` island/face count that fails loudly on mismatch; correct
the arms comment.

### LOW-6 — `zone_mats`: faces matching no band keep a stale `material_index`

:795–801 — after `materials.clear()`, a face whose centroid falls in a
gap between zones (or ≥ the last z1) keeps whatever index it had —
possibly ≥ the new slot count, which renders wrong/black with no warning.
Player's bands are contiguous so it can't fire today, but the code is one
non-contiguous cfg away from a silent defect.

Fix: default unmatched faces to the nearest zone, or `break` else-WARN
with the face count.

### LOW-7 — `eye_abs_z` bypasses both z-clamps with no sanity bound; nose ignores it

:430–433 — `center.z = cfg["eye_abs_z"]` preempts the `head_span` and
`zcap` clamps entirely (the xy clamp :445–451 still applies). For this
tuning it's harmless — verified 0.98 would land inside the would've-been
head_span clamp [0.82, 1.08] anyway — but a mistuned value or an
unconverged normalize floats the eyes off the head with no guard. Also,
the nose path (:468–480) still clamps to `head_span`/`zcap`, so a cfg
combining `eye_abs_z` + `nose_r` would anchor eyes and nose in different
spaces (player has `nose_r: None` — latent only).

Fix: WARN when `eye_abs_z` falls outside `[zlo, zhi]` or outside
`head_span` by >0.1·span; apply the override to `p.z` for the nose too
when set.

### LOW-8 — `zone_mats` branch leaves `wm = sm = None`; a `zone_mats`+`puffs` cfg crashes

:807 sets `wm = sm = None`; `fluff_shell` (:918) is only skipped because
player has no `puffs`. A future cfg combining `zone_mats` with `puffs`
passes `None` as the puff material → `e.data.materials.append(None)`
TypeError mid-render.

Fix: derive a puff material from `zone_mats` palette (e.g. first zone
color) when `wm is None`, or hard-fail early with a clear message.

### LOW-9 — Cosmetic/doc nits

- :780–781 `zs` prepends `isl[0].verts` even though the second
  comprehension already covers it — harmless duplication.
- Vgroup-band numbers drift between comments: `head_anchor` says "Head
  ≤0.87, Head3 ≥1.14" (:432); the hat comment says `'Head'` vgroup
  top=0.94 (:611–613). Measured (norm): Head 0.22–0.94, Head2 0.55–1.14,
  Head3 0.98–1.35 — the 0.94 figure is right; 0.87 and "Head3≥1.14" are
  stale/wrong (1.14 is Head2's top). HANDOFF repeats the 0.87/1.14 pair.
  Fix the comments — they're the tuning reference for the next species.

## Docs assessment

HANDOFF/PROVENANCE claims verified against ground truth: island strip
selectivity (exact), `materials.clear()` necessity, batch-list regex
inclusion, `eye_abs_z` escape hatch. The "socket reads as mouth" claim is
marginal but supported — a visible bump below the eyes at 80px. The one
overclaim is the implied face coverage of the pixel assertion (MED-4).

## Verdict

**NEEDS-FIX** — the player sprite itself ships clean, but the diff also
mutates three shipped species' `head_bone` to a bone that does not exist
on their rigs (HIGH-1): the next batch re-render produces eyeless
sprites that the current smoke check cannot catch. Revert lines 94/104/
112 to `"Head"`, fix the self-rejected `"Head2"` cfg (MED-2), and either
harden the hat anchor (MED-3) or scope it player-only before reuse.

## Resolution (post-audit)

- **HIGH-1 FIXED** — piplump/digsnout/dozantler reverted to
  `"head_bone": "Head"`; live re-render shows EYES on all three
  (piplump z1.24, digsnout 0.81, dozantler 1.36). Root cause: a `sed`
  bulk-replace intended for the player entry matched three animal CFs —
  lesson: never bulk-replace inside the CFG table.
- **MED-2 FIXED** — cfg now names `"Head3"` directly (the weight-vote's
  own conclusion); the self-reject WARN is gone.
- **MED-3 FIXED** — hat anchors to `htop_z` (vgroup/skull band), WARNs
  when the silhouette top out-rises it by >0.1·s.
- **MED-4 FIXED** — smoke now asserts ≥8 interior ink px in the player
  face band (rows 30-55%, cols 30-72%): 971 checks, 0 failures
  (measured ink=43).
- **LOW-5 FIXED** — strip_islands thresholds are bind-z-span fractions,
  per-island stats printed (DROP/keep lines), `strip_expect_faces:528`
  fails loudly on mismatch, arm-protection comment corrected.
- **LOW-6 FIXED** — band-less faces snap to the nearest zone edge + WARN.
- **LOW-7 FIXED** — eye_abs_z WARNs when outside head_span±0.1·span or
  the mesh z-cap; the nose anchor uses it too.
- **LOW-8 FIXED** — puffs on a zone_mats/mat_map cfg derive their
  material from the lowest zone instead of passing None.
- **LOW-9 FIXED** — comment band numbers corrected (Head≤0.94,
  Head3≥0.98); duplicate verts comprehension removed.
