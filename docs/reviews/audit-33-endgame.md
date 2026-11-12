# Audit-33 — Endgame Earnability (S77)

Context-free audit of the post-crown chain: spires → gauntlet → crown →
EX wave → legendary dens → Wildmere Accord → sixth party slot → what
remains afterward.

## Findings

- **[Critical] Accord permanently unreachable — 2/10 den heirs uncatched.**
  `LEGENDARY_DEN` includes `nibhand` ("Sacred paladin legend") and
  `shadekin` ("Abyssal doom knight"); both are `body: "human"`.
  `ownable()` rejected every human-bodied species, so `catchable()`
  refused the alpha heirs, `catch_counts` capped at 8/10, and
  `tick_accord()` could never seal — no sixth slot, no endgame.
  **Fix:** `ownable()` now returns true for `sid in LEGENDARY_DEN`.
  `acquirable()` is unchanged, so heirs stay out of wild/breed/raid
  pools; `spire_pick`'s body filter is unchanged; ironpact grunts stay
  uncatchable. The den warden stays immune via the `boss` check that
  runs before `catchable()` in `resolve_sphere`.
- **[Low] Demolish refund loses bred-egg parentage.** `egg_inc` stores
  `pair` but not the consumed queue row; a refunded `bred_kin_egg`
  redeposited later claims whichever pair is next in `egg_parents`.
  Comments on the three refund sites now say the pedigree dies with the
  box's records — honest, and bounded. A full lineage-preserving refund
  (storing the consumed row) is deferred: the exploit requires
  demolishing your own incubator mid-incubation to shuffle a breeding
  queue, low value.
- **[Low] No post-Accord guidance.** Guide Vol IX ended at the
  signature. Added a closing paragraph (en+zh): dens re-call heirs in
  ~1.5 days for keeps, apex trials pay while sigils last, catalog/stars/
  statues remain.
- **[Info] Legendary respawn pool.** `tick_boss_respawns` filters the
  den list only by data existence — after the fix every member is
  catchable, so the pool can no longer schedule a permanently-immune
  heir. No change needed.

## Regression assertions (tools/smoke_test.gd, "audit-33" block)

- knight heir (`nibhand`, alpha, non-boss) is catchable;
- same species non-alpha stays immune;
- `ownable()` accepts both knight legends and still refuses
  `ironpact_grunt`;
- crown + `gauntlet_ex` + all ten heirs caught → `tick_accord()` seals
  `accord` and `party_cap() == 6` (with full snapshot/restore).

## Evidence

- Before: `den_caught()` capped at 8/10 — verified against
  `species_gen.gd` bodies + `ownable()` predicate.
- After: `==== 868 checks, 0 failures, 0 skipped ====`.
- One unrelated ambient flake observed ("night shift", worldgen
  bed-proximity dependent, passes on re-run; predates this batch).

## Process note

The miss class: a hand-curated roster (`LEGENDARY_DEN`) gained members
chosen for flavor ("paladin", "doom knight") without checking every
member against the eligibility gates the list must satisfy. Rule 118
added to AGENTS.md.
