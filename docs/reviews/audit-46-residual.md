# Audit-46 — Residual launch-blocker sweep (S93)

Ninth cold pass — first-ten-minutes onboarding truth, net protocol
completeness, content-data consistency, boss/campaign softlocks, and
whatever prior lenses (33–45) didn't cover. Verdict: **1 HIGH + 2 MED +
1 LOW** — all resolved this stage. Suite: 962 checks / 0 failures / 0
skipped. Full finding list: docs/reviews/audit-46-residual-draft.md.

## HIGH — ten tech nodes charged for nothing

`craft()` + the craft panel gated on `rec["tech"]`, but the orb ladder
(`mega_orb` → `legendary_orb`), guns (`musket`, `tranq_gun`), `orb_launcher`,
`bow`/`arrow`/`musket_ball`/`tranq_dart` declared the gate on the ITEM row —
dead data. Two-sided: players burned ~23 tech points + 6 `ancient_part` on
no-ops, AND the entire orb/gun/launcher ladder (incl. the `legendary_orb`
capstone gating legend-heir catches) was free-craftable at any workbench
from day 1.

**Fix:** `game.recipe_tech(r)` resolves the gate — recipe-level `tech` OR the
output item's `tech` — applied in `craft()` and `draw_craft`. Guard:
`every recipe gate names a real tech node` + `legendary_orb refuses without
tech`/`crafts once unlocked` (at a real workbench — the station check runs
first, so the refusal fixture stands beside one).

## MED

- **Guest craft panel filtered on starter `unlocked`** — guests couldn't
  even see gated recipes though `craft()` would honor `net_unlocked`.
  The panel now uses the same `techs` expression `craft()` consults.
- **Gacha price drift** — structure desc said 20g, guide said 30g, code
  charges 45g (`GACHA_COST`). All three surfaces now say 45 (en + zh).

## LOW

- **Dex habitat blank** for legends + egg-line species — `habitat()` −1 now
  renders ` den ` (LEGENDARY_DEN) / ` egg ` instead of a gap; 2 zh rows added.

## Verified-correct inventory (auditor-confirmed)

All 10 missions have live completion paths; 8/8 hints reachable + verbatim
cost-accurate; starter kit solvency; help overlay verb-complete; guide en/zh
parallel; state_sync ordering; pal_sync replica lifecycle incl. mount/owner/
soul fields; env_sync campaign truth; fail-closed ghost proximity; species/
skills/elements/drops cross-consistency; gauntlet self-heal + void path;
kinbox anchor promotion; migrate id coverage; schematics DO gate mk2s.
