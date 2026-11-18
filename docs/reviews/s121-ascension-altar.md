# S121 — Ascension Altar: the post-Accord repeatable heir channel

The Accord sealed the campaign and then… nothing chased. Every remaining
sink was passive purchasing (effigy stand, merchant kin, statue perks) —
the "shallow late-game purpose" complaint in the original brief was still
true at the top of the curve. S121 adds the loop the endgame was missing.

## The loop

**Ascension Altar** (`structures.gd`, tier-8 tech `cost 5, parts 3`,
build: stone 40 + lumenite 12 + ingot 8, 2×2, lit). Interact:

- **Gate**: `accord` must be sealed — the altar sleeps otherwise.
- **Cost**: 1 Boss Sigil + 2 Legendary Orbs per ring. The orb spend is a
  true sink — no orb refund on KO; the payoff is the catch lane.
- **Summon**: an ASCENDANT heir of a `LEGENDARY_DEN` species — level 60,
  alpha (so the legend stays honestly ball-able), `raid` footing
  (blocks sleep, never re-dens), aggro on the summoner, 1.3× sprite.
- **Star progression**: per-species ledger `den_ascensions[sid]` —
  ring N summons a min(N,4)-star heir. A caught star-4 legend skips
  **84 same-species fodder** of condensation — the only channel to a
  pre-starred legend in the game.
- **Pick cadence**: least-ascended heir first (`ascension_pick`) — same
  pilgrimage rule den refills use, so one species can't soak every ring.
- **KO bounty**: effigies `2+star` + ancient parts `1+star`, floater+log.

## Gates and invariants

- One ascendant at a time (`_ascendant_live`), `pals` cap respected.
- `asc` rides `pals_data` — a saved wild ascendant reloads with its meta
  (wild + legend + alpha + star>0 shape verified, forged `asc` flags on
  rostered kin inert) or the one-kin gate would mint doubles.
- `den_ascensions` saves, loads clamped `0..99`, legend keys only, and
  wipes if the seal is absent — a forged tally can't pre-cheat star 4.
- Guest path `ascension_req`→host validates ghost-at-altar + accord +
  live-check; `net.pay("ascend", {sigil, orbs})` holds then settles on
  `ascension_done`; throttle on `act_bkt`.
- New-island wipe clears the ledger with `accord`.

## Verification

- smoke **1045 checks, 0 failures, 0 skipped** — pins: seed placement,
  pre-seal refusal with item preservation, summon shape (alpha+raid+
  legend+star 1+ledger 1+spend), live-block, KO bounty `eff+5/parts+3`
  with `boss_respawns` untouched, star cap at 4, `catchable()` admits,
  save round-trip coercion + forged-ledger wipe.
- In-game shot `s121-ascension.png`: altar planted, Dreadwyrm Lv60
  ascendant beside the keeper, log `ASCENSION — Dreadwyrm answers the
  altar (star 3)`.
- Fixture taught a lesson: `boss_sigil` stacks cap at 5 — the fixture
  seeds exact counts rather than trusting bag headroom.
- `IP CHECK: CLEAN`.
