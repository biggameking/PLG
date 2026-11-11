# Seventh context-free audit — guest-parity protocol (S34–S38d)

Scope: the whole guest-authority batch (chest_req through board_paid).
A context-free agent re-derived the contract from source, verified every
claim against live text, and reported **0 critical / 0 high / 4 medium /
10 low**. Several would-be HIGHs (double-claims, board burn-before-pay,
bed reach) were already closed mid-audit by S38b/S38c — the report
verified them fixed rather than counting them.

## Medium findings — all fixed in S40

1. **`condense_remote` had no gate at all.** Every other guest verb
   checks ghost proximity to its structure; this one let a guest star a
   kin from anywhere with no `kin_condenser` built. Now
   `_nearest_struct("kin_condenser", at, 6.0)` like every machine verb.
   *(AGENTS rule 67: a remote verb ports its gate before its effect.)*

2. **Guest kills and catches paid the host.** `pal_hit` carried
   `provoked_pid` through `hit()` but `kill_pal` never saw it — loot,
   xp, and hunt credit all landed in the host's bag. `kill_pal` now takes
   the pid (partner-attack sites already passed `owner_id` — the wire
   dropped it at the last hop), `_kill_loot`/`_kill_xp` route via
   `give_remote`/`xp_gain`, `board_hunt_credit(sp, pid)` pays the killer,
   and `net_catch` grants hunt credit + flat catch xp (using `catch_xp`
   would have fed the host's streak). *(AGENTS rule 68.)*

3. **Merchant ops had no proximity.** `buy_remote`/`r_sell_pal` only
   checked `merchant != null` — a modded client could blind-trade across
   the island. Both now `_ghost_reaches(pid, merchant.pos, 6.0)`.
   Merchant *replica* sync remains a deferred feature (honest guests
   still can't see the trader — that surface is a separate stage).

4. **Board holds were renewable forever.** Re-claiming by the same pid
   silently refreshed `pending.t` — one guest could starve the daily
   posting indefinitely. Now: same-asker re-reads its hold without a
   fresh clock; an expired hold cools that pid off for 30s; settle keeps
   the holder's claim (freshness gates claims, not settlements); an
   honest insufficient-goods reply releases the hold via `board_release`.

## Low findings — fixed

- `_free_incubator` bound parameterized (20 local UX → 6 ghost reach).
- `egg_inc` persists `own_tag` — a guest egg saved mid-incubation hatches
  into the right slice (tag→pid resolve, orphan+rebind fallback).
- `box_fingerprint` folds `star`/`level` — condense/infuse no longer
  leave a 15s-stale mirror.
- `env_sync` applies `bq` unconditionally — an empty packet means "no
  posting", not "keep the old world's quest" (rule 62 again).
- `board_pay` xp parity (`qn*3`, was `gain_xp(gold)` ≈ 2–4× local).
- `sleep_done` heals the sleeper's own player — the shared loops mend
  rosters; each keeper's body is their own.
- `net_catch` peer-guard; `r_butcher` trust-boundary note.
- Smoke: dup-claim, hold lifecycle, hunt-post discrimination (the old
  check was vacuous — no board seeded), merchant reach, condenser gate,
  skill-fruit teach.

## Deferred (recorded, not defects)

- Merchant replica + stock sync — guests can't see the trader at all;
  the shop surface is a feature batch, not a gate.
- `struct_sync` whitelisting of `captive`/`fert`/`egg_inc`/`workers` for
  client rendering — graceful degrade today.
- `chest_deposit` credits store before echo (single-RTT phantom-stock
  window) — bounded by bag trust.
- `work_done` echoes to asker only — cosmetic, nothing client-side reads
  work_mode.
- Echo-RPC paths (`*_done`) can't run in the host-side test harness —
  contract verified by code review, not assertions.
- Unpaid `board_paid` settle is inside bag-trust (the gold only reaches
  the cheater's own bag, equivalent to minting the goods).

## Process lessons (folded into AGENTS.md)

- Rule 66: drained world, not parked actors (tranq flake — S38d).
- Rule 67: remote verbs port the gate before the effect.
- Rule 68: minted rewards route by actor pid at the mutation point.

## Convergence

0C/4H/6M/4L → 3H/5M/4L → 2H/7M/8L → 1H/3M/9L → 2H/5M/9L → 3H/8M/5L →
**0C/0H/4M/10L → all landed**. Severity keeps falling; findings cluster
now in protocol-edge polish rather than authority violations.
