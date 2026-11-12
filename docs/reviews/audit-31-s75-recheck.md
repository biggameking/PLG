# audit-31 — context-free recheck of S75 first-session hardening

Independent review of `da62865` (S75). The auditor had no prior context; every
S75 claim was verified against source. Verdict: **all nine S75 claims real, no
Critical/High findings** — but a batch of Medium/Low truthfulness gaps.

## Verified claims (source-confirmed)

- Starter cargo: 3 kin_orb + 4 lumenite; first kinbox costs 4 lumenite.
- Renewable lumenite: 12% shard drop on rock/coal/gold ore destruction.
- Day 1 runs at half rate; later days normal.
- Opening ring: 3 docile zone-0 kin within 4.5–7.5 tiles of spawn.
- First kinbox (paid path) grants `raid_t ≥ DAY_LEN + 60`.
- Death packs are `mine`-flagged, decay-immune, and survive save/load.
- Straw-bed sleep is night-gated for host and guest.
- New Game overwrite requires a second confirmation.
- Hint system is condition-driven, capped at 3, self-retiring.

## Findings → fixes (this commit)

| # | Sev | Finding | Fix |
|---|-----|---------|-----|
| M1 | M | Pad guide hint named Back; actual path is Start → GUIDE row | Hint text corrected (`Start → GUIDE — every verb lives there`) |
| M2 | M | Orb hint implied throw-first; catch odds want weakening first | Both en/pad strings now teach "weaken first (low HP catches easier)" |
| M3 | M | F8 quick-load overwrote a live session with zero confirmation | `load_arm` two-tap confirm, same pattern as NEW GAME |
| L1 | L | `place_free` kinbox skipped first-base raid grace (guest/sync path) | Same `raid_t` grant at the choke point |
| L3 | L | "Assign kin with F" pointed at the wrong verb | Now "E on the kinbox posts a kin to the yard" |
| L4 | L | Opening-ring kin could wander off-screen before first catch | `ring_kin` meta + wander tether to `home` (≤2 tiles back) |
| L5 | L | Cold hints fired at 4-tile threshold; real warmth radius is ~10 | Hint conds aligned to `nearest_heat > 10.0` (same source table) |
| L7 | L | `MAX_DROPS` eviction removed the oldest bag — could eat a corpse pack | Eviction picks the oldest non-`mine` drop |
| L8 | L | Guest bed distance (6) exceeded the host's own reach (~3) | `sleep_req_remote` aligned to 3.0 |
| L10 | L | Title footer always promised "enter = continue" | Footer switches on `has_save` |
| F4 | F | Build-bar rows overlapped (~160px text in 122px slots); header recipe spilled off the card; row costs showed raw item ids to zh players | Rows now show index+name only (cost detail is the selected header's job); header auto-shrinks 11→10→crop; costs resolve through translated item names |
| L9 | — | `hint_seen` cleared on load flagged as a gap | Kept: deliberate re-onboarding (commented at both clears); contract covered by rule-25 checklist |

## Regression coverage added (tools/smoke_test.gd)

- `place_free` kinbox buys the same grace — placed=true raid_t=300
- corpse pack outranks the drop flood — 400-cap flood evicts a plain bag, `mine=1` survives
- ring kin wanders stay near home — planted flagged kin retargets to ≤2.1 of home
- quickload first tap arms / second tap loads — arm contract via real `_unhandled_input`
- footer tracks the real save flag — `has_save == file_exists(savegame.plg)`

Result: **845 checks, 0 failures** (was 835 + new assertions; one worldgen-
conditional skip on some seeds).

Bonus flake kill: the suite's own `node-to-node hop` check intermittently
failed — root cause was the real wall-clock `pos_pps` packet bucket draining
across sequential probes (rule 44's "refresh the token between bucket-gated
probes" applied to a bucket the fixture never refreshed).

## Visual evidence

`/tmp/plg-s75-buildbar.png` before: rows overprinted each other; header recipe
ran off the card edge. After: rows clean (`1 Kinbox 2 Kin Bed …`), header
`BUILD placing: Kinbox — 4 Lumenite Shard 6 Wood 6 Stone` fully inside the card.
`confirm` shot: `OVERWRITE the save?` now fits its button.

## Known-transient

`ring_kin` is a meta flag, not a save field — wild kin respawn unmarked on
load. Transient by design (rule 20 comment at the set site): the tether guards
the first minutes only; a returning keeper needs no tethered prey.
