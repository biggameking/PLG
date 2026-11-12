# Audit 37 — Economy/resource-flow numbers (S83)

Context-free arithmetic audit of every gold/item source and sink. Verdict:
two positive-EV money printers, three honest-but-thin spots, one deferred
co-op trust hole. All fixed or documented below. Baseline: DAY_LEN 240s.

## Landed

- **High — the gacha was a mint.** Pull 30g → 90% kin_egg / 10% huge_kin_egg.
  Best-of(raw-sell, hatch-sell) per outcome was 48g/100g → +24g EV/pull
  (+80%). Now: `pal_sell_price` base 40→20 (lv1 sells 28g) AND pull 30→45
  (`GACHA_COST` const). Post-fix EV = 0.9×28 + 0.1×100 = 35.2g < 45g —
  the "sink not a mint" comment is finally true. Asserted by formula, not
  by a fixed constant.
- **High — merchant kin_egg + cake fed the same loop.** kin_egg 30g →
  hatch→28g is now dead. Cake was unpriced (15g fallback): 1 cake → ranch
  → bred egg raw-sells 25g = +10g/60s mint. Cake now `price: 40` — the
  catalyst outprices every bred-egg exit. Asserted.
- **Medium — mega_orb rode the 15g unpriced fallback** (spherePower 42,
  same as the 26-power kin_orb). Now `price: 45`.
- **Medium — nightly sleep zeroed kin hunger**, cutting the food economy
  ~28-50%. Workers now wake at hunger 60 — hp/san still restore.
  Asserted.
- **Low — merchant murder was net-positive** (~+60-110g/visit, wanted
  reset per visit). `merchant_deaths` now persists in the save
  (`mdeaths`) and each corpse pays `drop/deaths` — repeat kills decay to
  the 4g floor. New-game resets it; asserted the save field round-trips.
- **Info — post-Accord effigy sink was rate-capped, not balance-capped**
  (3×160g/visit ≈ 480g/merchant-day). Stock now `n: 99` — a sealed keeper
  can convert up to 8,800g/kin into soul_boost; gold actually means
  something again in the endgame.

## Deferred / accepted

- **Client bag-trust chest mint** (`chest_req_remote` "dep" writes
  store[iid] += c unverified): provable for a cheating client on co-op.
  LAN co-op threat model — guests are friends; the wire hardens against
  crashes/malformed, not a determined cheater. Documented, not fixed.
- `sell_to_merchant` 1g floor for unpriced materials: intended (materials
  sellable; 999 wood → 999g one click at a time is grind, not a mint).
- Board supply pays 2× sticker: deliberate generosity, 1/day bound.
- Dead currency displays on clients (tech/stat points unusable —
  deliberate host-authority).

## Evidence

- `==== 902 checks, 0 failures, 1 skipped ====` (worldgen condition item)
- New asserts: lv1/lucky resell below sticker, gacha EV < slot, cake >
  bred-egg exits, sleep wakes hungry, mdeaths save round-trip, effigy 99.
- `==== SIM: 0 failures ====`

## Recheck (verifier pass) — closed

The post-fix cold verifier confirmed all eight claims (sell baseline, gacha EV,
cake/mega_orb pricing, sleep hunger, `merchant_deaths` save order, effigy 99,
wanted-reset semantics, `_struct_gen` coverage) and flagged two real holes
plus one fragility, now fixed:

- **Guest sell sticker drifted (hud.gd).** The mirrored buyback literal still
  read `40 + lv*8` while `pal_sell_price` moved to base 20 — guests saw ~20g
  over the real payout. Sticker now mirrors base 20, and a lockstep smoke
  check recomputes both sides so the formulas can't silently fork again.
- **`kin_gacha` had no client gate (hud.gd → net.gd → game.gd).** A guest pull
  ran `gacha_pull()` fully client-side — unvalidated host bypass inconsistent
  with every neighboring paid verb. Now `net.pay("gacha", {gold_coin: GACHA_COST})`
  holds the gold client-side and `gacha_req` flies; host validates ghost reach
  (`_nearest_struct("kin_gacha", at, 6.0)`), rolls with host rng, ships the egg
  via `give_remote`, and refuses echo `pay_rej` (hold refunds). `gacha_done`
  settles the hold and logs the roll.
- **Division-order fragility (game.gd).** `merchant_deaths` divides the bounty;
  the increment lands first today, but `maxi(1, merchant_deaths)` makes a
  future reorder non-fatal.

Suite after recheck: `903 checks, 0 failures, 0 skipped`. Balance sim still
`0 failures`. New regression pins: sticker/formula lockstep, ghostless
`gacha_req` refusal, host roll + bag delivery through the remote path.

Coordinates note surfaced during fixture work: `structures` keys and
`_ghost_at`/`player.pos` all live in *tile* space (world is 220² cells); the
first fixture divided by 32 and missed reach. Cell-space is the contract.

## Deferred findings — resolved (S84)

- **Unpriced-item sell fallback (was: 1g pity floor).** `sell_to_merchant` now
  refuses any item with `price <= 0` — 63 sink items (orbs, sigils, effigy,
  quest goods, gatherables) can never leave for loose change. Smoke pins the
  refusal; the old `wood` sell fixture now sells priced `cake` instead.
- **Merchant pool composition re-evaluated — by enumeration, not taste.**
  `tools/sim_economy.gd` walks every gold-in→transform→gold-out lane the data
  tables describe: all 23 MERCH_POOL lines + 4 fixed lines resell under their
  stickers, 3 egg hatch lanes lose, cake beats bred-egg exit, gacha EV (35.2)
  stays under the 45 slot, **0 fully-priced recipes exist** (every recipe has
  a gatherable ingredient — a market-only craft mint is structurally
  impossible), merchant-kin buyback table loses at every z/lv, and every
  BOARD_POOL good is gather-only. `43 checks, 0 failures`.
- **Co-op storage lane — audited, already defended.** Ghost-reach 6.0, 1 op/s
  bucket, item-id whitelist, per-call count caps, `chest_can_take` stack
  limits, and the pay-ledger gap refund mean a forged deposit claim can only
  launder what actually left the bag. No change needed; the audit's worry is
  documented here as verified-safe.
- **Economy-day income-rate sim — descoped deliberately.** The lane
  enumerator answers the security question (no closed gold loop exists);
  per-day income pacing is a balance question owned by sim_balance + the S83
  decay/price work. Building a full world-day sim for pacing would duplicate
  the smoke suite's world harness for marginal signal.

Suite after this batch: `903 checks, 0 failures, 0 skipped`;
SIM `0 failures`; SIM-ECO `43 checks, 0 failures`.
