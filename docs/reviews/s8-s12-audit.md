# S8–S12 External Audit — fresh-context review + resolution ledger

Fresh-context subagent review of S8 (balance sim), S9 (zh slice), S10 (audit fixes),
S11 (hero silhouettes + pad), S12 (species voices). Static read-only audit.

## Verdicts

The strong patterns held: `acquirable()` gate at both catch entries, `net_id > 0`
replica guards at the real choke points, idempotent `bind_gamepad`, `spire_tag`/`phase`
in the save+wire contracts. The recurring defect CLASS was "a pattern applied to a
strict subset of its sites": KO scrub covered `party` not `remote_parties`; `panel == ""`
covered 2 of ~8 action paths; `>= 0` bound in 1 of 3 spire whitelists; `user://` backup
covered settings.cfg not savegame.plg; ghost-proximity was fail-OPEN at all 4 RPC sites;
client-gating covered `tod` and nothing else; texture caching covered drops not orbs.

## Findings → fixes (all landed)

| Sev | Finding | Fix |
|---|---|---|
| H1 | `load_game` never cleared `bench` — quickload grew a phantom stable | free+clear bench (+lure/focus_target/raid_warned/raid_theme) in `load_game` |
| H2 | KO'd guest pal left a dead `remote_parties` slot → "Party full" softlock | `kill_pal` scrubs every remote roster row; `r_butcher`/`r_sell_pal` too |
| H3 | Clients ran the full sim — raid/supply/merchant/weather/wild/production/stump/structure-damage all ticked on clients | every world-mutating verb gated `is_client()` at the function head — one line each, choke-point style; `tick_migration` kept as the documented local-fauna exception |
| H4 | Deterministic worldgen double-spawned synced drops on clients (double-loot) | `spawn_drop` client-gated — net_drops replicas are the only synced bags |
| H5 | Fail-open ghost guards at `take_drop`/`net_harvest`/`net_place`/`net_demolish` | all flipped to `gp == null or dist > R` — fail closed; smoke fixtures now plant real ghosts |
| H6 | Client-claimed `behind`/orb/dmg trusted host-side | `net_catch` re-derives `behind` from the witnessed ghost + proximity-gates the throw; `pal_hit` requires wild-mode + ghost range; `net_place` checks `unlocked` |
| M2 | In-order spire placement could ship 0–4 spires | per-spire independent strict→relaxed passes; relaxed still requires standable center |
| M4 | Two of three `stag` whitelists missed the `>=0`/`is_valid_int` half | one `spire_tag_ok()` for save/wire/kill paths |
| M5 | `np.hp`/`player.hp` unclamped on load | `clampf` both ends |
| M6 | `panel == ""` covered only LMB + pad_strike | gated `aim`/`ride`/`partner_skill`/`cycle_sphere`/`dodge`/`party_toggle`/`pal_stance`/`demolish`/`interact` |
| M7 | KO path bypassed `MAX_BOX` | bounded overflow lane `MAX_BOX + 32`, then honest release to wild |
| M8 | `sim_balance` raid section + `cap_pow` were mirror copies — tautological gates | `Combat.raid_day_bonus`/`raid_wave_bonus`/`cap_power` extracted; sim calls the shipped math |
| M9 | Dead CSV rows; `\,` escapes broke the one real key (verified in-engine: `tr()` fell back to English) | quoted CSV fields; `Saved.`/`Loaded.`/`SAVE FAILED`/host-save lines wrapped at emit; "Kinbound" title rides tr() |
| M10 | Suite clobbered the real `savegame.plg` | backup at run start, restore before tally |
| M11 | `net.host()` bound :7777 mid-suite, never closed | peer closed + cleared post-check |
| L-series | `_exit_tree` stale comment; write-only `grotto_pos`/`grotto_room2`; dead `net_id = 0`; `int()` slam-tag parse; `net_drops` uncapped; `smoke_out.txt` append-only; ASCII-only chat; silent spire-chest failure; `find_pal` uid/net_id aliasing | comment corrected; grotto markers now serialized; dead line removed; `spire_tag_ok` in `pact_slam`; `MAX_DROPS` gate; file truncates per run; chat takes any unicode ≥32; `push_warning` on chest failure; replicas get `uid = -net_id` so the two id spaces can't collide |

## New negatives in the suite

ghostless place/catch refused; out-of-range catch refused; forged spire tags
("spire_-1", "spire_abc", "spire_9") refused; stale bench cleared on load;
KO frees the guest's party slot; mule test now mirrors `carry_cap`'s formula
(the +120-delta assumption broke when the outgoing pal had its own aura).

## Process lessons → AGENTS.md rules 25–34

Recorded in `AGENTS.md`. Headlines: every load/teardown clears every collection or
names the exception at the function head; proximity RPCs fail closed; client-claimed
values are untrusted; sim gates call production code or gate nothing; kill paths scrub
every roster the uid can appear in; whitelisted string ids carry the full
prefix+valid-int+bounds check; tr() slices ship a coverage inventory; deterministic
worldgen produces each synced entity through exactly one channel; every wiring check
ships its negative.
