# audit-74 — S122 kin render pass cold review → remediation

**Scope:** S122/S122b source-mesh kin render reconstruction (`8047709`, `d9dea26`)
reviewed cold. Verdict: **NEEDS-FIX (minor)** — the showcase six were corrected,
but the diagnosed root causes survived on 9 sibling species, evidence PNGs
lacked `.import` sidecars, and no ROADMAP entry existed.

## Findings → status

| # | Sev | Finding | Status |
|---|-----|---------|--------|
| MED-1 | MED | `s122-kin-before.png`, `s122-kin-after.png`, `s122-ingame-*.png` shipped without `.import` sidecars | **fixed** at d9dea26 (`--import` pass); this round adds sidecars for the two new sheets + two new in-game shots |
| MED-2 | MED | same root cause on 9 siblings: 5 serpents on Piranha.blend (`Idle`, `target_h 0.8`, frames `(5,25)`), 4 deer on Horse.blend (`rot 0` rear-to-camera) | **fixed this round** — see below |
| LOW-1 | LOW | no S122 ROADMAP entry; smoke count drift (1045 vs 1048 is the documented RNG band) | **fixed** — entry appended |
| LOW-2 | LOW | probe script uncommitted | accepted — convention keeps probes in `/tmp`; the method is documented here |
| LOW-3 | LOW | gloamwing stray dark pixels | noted, cosmetic, deferred |

## MED-2 remediation — the real diagnosis

Propagating the hand-tuned `tidscale` values to the template was **necessary
but not sufficient**. A 5-rotation probe (`/tmp/probe_rot.py` — import the
module, override `CFG[sid]["rot_z"]`, re-run `main()`) showed the convention
itself was wrong:

- `rot -90` faced the Piranha **head-on to the camera** — the blob was not
  a weak pose, it was the wrong axis. tidscale itself shared the defect.
- `rot 0` is the clean side profile (head-left, matching quadruped
  convention).

Template changes (`tools/art/mesh_map_gen.py`):

- serpent: `rot_z -90→0`, `action Idle→Swimming`, `frames (5,25)→(10,30)`,
  `target_h 0.80→1.35`, body-level `"fins"` accessory (per-sid legendary
  marks still win — `snovstride` keeps `halo`), `eye_fwd 0.10→0.05`,
  `eye_up 0.10→0.06`
- deer: `rot_z 0→90` side profile, `frames (5,25)→(20,80)` graze window
- `render_src_asset.py`: tidscale hand entry `rot_z -90→0`, `eye_fwd 0.10→0.05`

Re-rendered all 10 affected species (5 serpents + tidscale + 4 deer),
`post_kin` re-posted. Fill ratios: serpents `0.11→0.33` (post-profile),
deer `0.26–0.31`. Contact sheet `s122-kin-after2.png` (all 10) and
`s122-kin-serp.png` (6 fish, eye+fin detail).

In-game evidence: `s122-ingame-noctfang.png`, `s122-ingame-petalantler.png`
(windowed `tools/shot_kin.gd` — headless `root.get_texture()` is null).

## Verification

- `godot --headless --import` — clean; **zero** missing `.import` sidecars
  across `docs/reviews/*.png` and `assets/kin/*`
- smoke: **1049 checks, 0 failures, 0 skipped**

## Process lesson

"Propagate the showcase fix to siblings" was the audit's ask, but the probe
proved the showcase values themselves carried a wrong-axis bug. **Verify the
reference, not just the spread** — a template fix copies whatever the
hand-tuned exemplar got wrong. Rotation conventions belong in a rendered
probe matrix (5 cardinal/diagonal rots → contact sheet) before they ship in
a template.
