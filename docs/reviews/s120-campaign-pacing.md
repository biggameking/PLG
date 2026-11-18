# S120 — campaign pacing probe

`tools/sim_pacing.gd` measures the ACTION-COST of every progression gate
from shipped formulas (no mirrored design guesses — the one mirror,
`level*25` kin xp, is pinned by an exact-boundary smoke check so a formula
drift fails the suite instead of silently invalidating this probe).

## The campaign curve (fresh lv19 z3 catch → gate)

| gate | xp | wild-farm kills | day-10 raid | day-20 raid | day-30 raid |
|---|---|---|---|---|---|
| lv25 (spire-1) | 3,225 | 112 | 75 | 45 | 39 |
| lv35 (spire-3) | 10,600 | 366 | 247 | 146 | 128 |
| lv42 (spire-4) | 17,250 | 595 | 402 | 237 | 208 |
| lv50 (spire-5) | 26,350 | 909 | 613 | 361 | 318 |
| lv60 (cap) | 39,975 | 1,379 | 930 | 548 | 482 |

Reading: spire-1 is wild-farmable (~112 kills fields the whole strip —
partner share hits EVERY field kin). The raid engine then out-earns wild
farming 2.5x (day-20 raiders are lv32-46) — the mid campaign runs on
defense nights, not grinding lv19s. The cap is ~480 max-day raid kills —
a real endgame, not an afternoon.

## Economy audit

- **tp**: 130 total, earnable 134 by lv50+dex — full tree reachable inside
  one campaign; orb ladder (14) affordable by lv12; essential set (39) by lv20.
- **ancient parts**: need 23 — guaranteed EXACTLY 23 (spire chests
  Σ(1+placed)=15, gauntlet-EX +6, dex_full +2), with alpha/boss/crate/fossil
  income on top. The seal rewards ARE the tech tree.
- **orb ladder maps to zones**: zone-0 kin_orb 65% → zone-1 mega → zone-2
  giga → zone-3 ultra (all ≥50% at 30%hp no-status on that zone's own
  median capturePower). Softest legend heir lv50: legendary 0.83 / ultra
  0.56 / mega 0.23 — the top rung out-earns the mid rung 2.6×.
- **sigil loop**: self-funding (spire kill +1, gauntlet pays 1-2 back).
- **condense**: star-4 = 116 same-species fodder, ×1.75 stats — a
  completionist sink, never a requirement.

## Verdict

The "shallow late-game" risk is quantitative now, not a feeling: the wall
between wild-caps (lv21) and spire-5 (lv50) is bridged by raid escalation,
and every seal the campaign asks for pays the exact currency the tech tree
charges. 22 checks, 0 failures.

## Smoke pin added

`level*25 xp` boundary check — the one mirrored formula in this probe is
now pinned at its exact edge (74xp at lv3 holds, +1xp levels exactly once).
