# audit-52 — expanded mesh migration cold review

Context-free subagent audit of the S98c→S99 stage: mesh coverage 61→108/116
(+ cute_monsters / monsters_basic CC0 packs for ghost/human/monkey/hedgehog/
blob bodies), iterative evaluated-geometry normalization, per-pass action
location-fcurve scaling, bird/serpent orientation fixes.

## Verdict: NEEDS-FIX (minor) → all findings fixed this stage

Shipped artifacts verified correct: 116×2 sprites all present + fresh,
coverage arithmetic exact (9 hand + 99 generated + 8 accessory = 116, no
silent primitives), accessory pixel-pins intact, license files in-tree,
generated config reproduces deterministically.

## Findings & fixes

| # | sev | finding | fix |
|---|---|---|---|
| 1 | MED | `batch_mesh.sh` discarded `post_kin.py` exit code — a post crash printed `ok` while shipping the stale sprite | post output now captured + `FAIL(post)` counted |
| 2 | MED | batch exited 0 even with `99 failed` — no programmatic failure signal | `exit 2` when fail>0, `exit 1` on empty list |
| 3 | MED | `normalize()` silent non-convergence after 10 passes | `WARN normalize unconverged` |
| 4 | MED | render WARNs (eyeless/static/mat_map misses) hid inside "ok" tally | batch prints per-species WARN lines during the run |
| 5 | MED | only the first MESH object processed — multi-mesh sources would render unscaled siblings | `WARN N mesh objects` guard |
| 6 | LOW | PROVENANCE drift: `cindchew` listed as Cow-mesh (it's accessory→primitive); "115 non-fenjelly" stale | corrected |
| 7 | LOW | `BLENDER_EEVEE` invalid on Blender ≥4.2 | `EEVEE_NEXT` with legacy fallback |
| 8 | LOW | eye clamp is z-only (X/Y unbounded) | documented limitation in HANDOFF — current entries verified in-bounds |
| 9 | LOW | `assets/kin/probe_*` leftovers would ship in PCK | deleted (8 files + imports) |
| 10 | LOW | contact sheet/gitignored evidence unverifiable from repo | `docs/reviews/s99-sheet108.png` + `s99-ingame.png` committed |

## Process notes carried forward

- "ok" tallies must mean *the full pipeline* succeeded: render + post +
  no-WARN surfaced. Counted-ok ≠ verified-ok is a recurring class
  (audit-51 batch exit-code, audit-46 recipe gate).
- Blender-script probes belong outside `assets/` — anything in a PCK-included
  dir ships. Probe prefix convention now expected in `tools/art/render/`.
