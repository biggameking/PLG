# S1 IP de-risk — external review findings + fixes

Reviewer: context-free subagent (read-only audit of commit `3832d99` + tree).

## Correctness findings → status

| Sev | Finding | Fix |
|-----|---------|-----|
| H1 | `Migrate.save_dict` mapped runtime keys, not serialized keys: `cap`/`egg`/`inc.pair` never migrated (caged kin lost, ranch lineages re-rolled, incubators hatched random) | Rewrote against the real `save_game()` schema |
| H2 | `respawns[].sid` never migrated — pending boss den refills silently dropped | Mapped |
| H3 | `mimic` species id never migrated — legacy mimic chests went inert | Mapped |
| H4 | `kin[].carry.id` never migrated — phantom items | Mapped |
| H5 | Dead `stock` branch proved save_dict was written blind | Removed |
| M1 | Substring-mangled names: `IronpactGlaclumpper`, `IronpactGrunt`, `Glaclumpt comb/bun` | Fixed in .gd + prototype .ts sources |
| M2 | 35+577 migrate entries pointed at nonexistent ids | Pruned against real id set; now 135 valid mappings |
| M3 | `PAL-SKILL` in help bar (all-caps escaped the lexicon) | → `KIN-SKILL` |
| M4 | `Palworld`→`the island` produced nonsense English in 9 strings | Rewrote per-string in .gd + .ts |
| M5 | Orb items described as "spheres" | Display strings unified to orb |
| L1 | `class_name Pal` left in renamed file; `Pal` type refs everywhere | `Pal`→`Kin` across all .gd |
| L2 | `pal_bait`/`pal_fluid` ids survived | →`kin_bait`/`kin_fluid` + migrate entries |
| L3 | orphan `src/pal.gd.uid` | Removed |
| L4 | stale `.import` dest paths for 7 second-pass names | Repaired + re-imported |
| L5 | `export_path=PLG.exe`, `com.plg.game` package id | →kinbound |
| L6 | ROADMAP acceptance grep listed NEW names (backwards, could never pass) | Replaced by committed `tools/check_ip.sh` |
| L8 | `audit_data.py` dead `'sphere'` check; `gen_assets.py` stale docstring | Fixed |
| L9 | `docs/reviews/` missing | Created (this file) |

Also added: smoke fixture `legacy` dict exercising every migrated field
(7 checks) and `tools/check_ip.sh` as the committed acceptance gate.

## Process lessons (→ AGENTS.md "Rename & sweep rules")

1. One idempotent script for the whole surface — never hand-patch a generated
   rename; fix the name table and re-run end to end.
2. Save migrations are written against the *serialized* schema (`save_game()`
   output), never runtime dicts — enumerate written keys first.
3. Display-string replacements must be word-bounded and case-classed
   (PAL/Pal/pal), and every hit gets human review.
4. Every rename needs a migration-consistency gate (map values resolve against
   current data) plus a fixture test — file presence is not evidence.
5. Post-rename orphan sweep: stale `.uid`, `.import` dests, identifier/class
   names, docs, export metadata.
