# Audit-48 — cold process review of the audit campaign (S95)

A context-free subagent reviewed the *development process* itself (S1–S94):
commit archaeology via reflog, ROADMAP ledger, AGENTS rules, audit docs,
and the verification tools. Verdict: real results, recurring meta-pattern —
defects found as instances and closed as instances, so the same gate
classes were re-litigated for dozens of stages.

## What S95 fixed

- **sim_economy tautology** (rule 28 violation) — it mirrored 3 production
  constants: kin sticker `90+lv*12+z*80`, stock markup `maxi(price,25)`
  (semantically looser — lifted sub-25 stickers), and `price*0.5` sell.
  All three now live in `src/game.gd` as `merchant_stock_price` /
  `merchant_kin_price` / `sell_value` statics; production AND the sim call
  the same code. SIM-ECO 43/0 still green — proof the shipped formulas,
  not the mirror, hold the invariant.
- **ROADMAP ledger** — S37 block duplicated verbatim (removed), S22 entry
  sat before S18 (moved), S17 (`f988b5b`) had no entry (restored, citing
  the S24 `placed_tag` follow-up).
- **check() cost** — ~1000 FileAccess open/seek/close cycles per run;
  now a persistent handle + per-line flush. Crash-marker contract kept
  (the on-disk tail still names the last check that ran).
- **Dead tools** — 12 one-off stage scripts (shot_*, play_s81, dbg, repro*)
  moved to `tools/archive/`; AGENTS.md's gate block now registers
  perf_probe/leak_probe/package.sh and fixes the stale banner text.
- **Config-parse guard** — project.godot must parse via ConfigFile in the
  suite + ETC2 flag must read through ProjectSettings (S94 class).

## Verified (this stage)

smoke 968/0/1 · SIM 0 · SIM-ECO 43/0 · web+windows+android artifacts built.

## Findings kept on record (not all mechanized yet)

- Same-gate re-litigation chains (sync_pos ×5, pal_hit bound ×3, demolish
  ×6, hello ×5, phantom walls ×4, ~12 stages of guest-dead-verbs) — the
  "class-closure fix contract" recommendation: every fix commit names its
  sibling sites. Adopted as convention; not yet a lint.
- Verified-clean verdicts later falsified (audit-38→40, audit-45→47) —
  the "verify-before-claim" rule: no DONE lands without the diff
  exercised. Adopted; audit docs already carry file:line evidence.
- 10 of 47 audits lack docs/reviews artifacts; drafts committed with
  subagent preamble — convention going forward is curated docs only.
- 126 rules vs enforcement: recurring rule families should become
  executable lints over prose. Partially done (recipe-gate lint,
  config-parse lint); a fuller lint_rules pass is future work.
- Seed-conditional skips: retry-first fixtures landed S94b; remaining
  ~5 skip-path checks are honest legal-roll skips, tolerated.

The review's three systemic recommendations — class-closure contracts,
deterministic skip-free gates, verify-before-claim — are now the campaign
convention; each is already half-institutionalized by S90–S94 practice.
