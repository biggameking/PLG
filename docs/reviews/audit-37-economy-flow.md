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
