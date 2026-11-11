# S43 — eighth external audit landing (wire shapes + mirror lifecycle)

Scope: `src/net.gd`, `src/game.gd`, `src/hud.gd`, `tools/smoke_test.gd`.
Audit input: context-free review of the S41/S42 tree reported 3H/5M/8L + 5
process items. All HIGH/MEDIUM findings landed; LOW findings landed or were
verified bound-consistent with notes.

## Fixed

| Sev | Finding | Landing |
|---|---|---|
| H1 | `stock_sync` filtered `id`-only rows → kin rows invisible, guest kin purchase dead | dual-shape row parser, SpeciesData whitelist, lv/n/price clamps, rebuilt dicts, MAX cap (`net.gd` `stock_sync`) |
| H2 | guest sell rail read `game.box` → dead UI | `sellable_pals()` reads `net_box` dicts on clients (`hud.gd`); host recomputes price at `r_sell_pal` |
| H3 | `chest_req("dep")` laundered forged claims into durable shared truth | 9999-unit per-call cap under existing throttle + bound comment (`game.gd`) |
| M1 | merchant mirror survived disconnect → interactable zombie | `_on_server_disconnected` teardown (`net.gd`) |
| M2 | `buildable_list` under-offered host tech | guests read `net_unlocked` directly; `unlocked` rides `env_sync` |
| M3 | `struct_sync` lacked all state fields | `[id,ox,oy,store,state]` wire shape: cap/inc/exp/fert/loot/timer/hp/by/wk, re-anchored times, explicit-null clears, uid→replica crew (`game.gd` `struct_wire_state`/`_struct_wire_apply`) |
| M4 | honest-path payment gates | verified: shrine lumenite gate already existed (`hud.gd:703`) |
| M8 | `MAX_MERCH_STOCK` dead const | enforced in `gen_merchant_stock` + `stock_sync` |
| L1 | host avatar invisible past spawn+12 on clients | clients accept `sync_pos` only from pid 1; others ride `peer_pos` |
| L2 | hit squad bypassed `MAX_PALS` | loop breaks at cap |
| L3 | `merch_hit` reach 3.0 | tightened to 2.5 tiles |
| L4 | `deploy_to_base` silent for guests | `_deploy_note` routes to owner pid |
| L5 | `board_quest.pending` leaked holder pid | `env_sync` packs a filtered bq dict |
| P2 | vacuous-skip checks invisible | banner now prints `N skipped` (grotto-room fixture skip surfaced) |
| P4 | duplicated struct pack loops | `state_snapshot` calls `struct_state_pack` — also fixes a latent footprint-cell→origin mis-key |

## Bound-consistent / documented

- chest-dep laundering beyond the 9999 cap requires a provenance ledger, which
  would break honest crafted-goods deposits (crafting is client-authoritative
  by design). Documented bound, not a hole.
- wire-level `sender_id` cannot be faked in the harness; RPC gates are
  exercised via direct calls (`merch_hit`, `pal_hit` coverage).
- multi-sleeper day-skip heals only the sleeper — noted as design, not a bug.
- hello tag-switch party desync is self-inflicted; guest-hit sfx locality is cosmetic.

## New durable rules (AGENTS.md 74-76)

74 explicit-null clears / 75 relays check CONNECTION_CONNECTED / 76 the
host's own packets are truth, not suspect.

## Verification

Smoke `700-704 checks, 0 failures` ×9 runs; 0 ERROR; skipped counter surfaces
the legacy fixture-skip ("grotto room 2"). One transient single-check failure
observed once in 12 runs (seed-class flake, not reproduced).
