# S4–S7 external process audit — findings & dispositions

Fresh-context subagent review of the S4 (onboarding), S5 (audio), S6 (gamepad
layer) and S7 (boss/endgame spine) work. Severity-ranked; all correctness
findings fixed in the same commit batch unless noted.

## Fixed

| # | Severity | Finding | Disposition |
|---|----------|---------|-------------|
| H1 | HIGH | `spire_tag`/`phase` not in `pals_data` — save+load turned a live spire guardian into an untagged boss: campaign uncompletable, infinite boss farm | `"stag"`/`"ph"` saved, whitelisted on load (`spire_0..4`, `1..2`); round-trip smoke check |
| H2 | HIGH | Pad B bound to `dodge` while `ui_cancel` kept its default B → every dodge paused; with a panel open it closed+dodged in one press | `bind_gamepad` strips joypad events from every action it touches (B gone from `ui_cancel`, pad cancel = Start); idempotent across scene reloads; smoke checks both |
| H3 | HIGH | Phase-2 adds (`enter_phase_two`) are same-species wild kin — a legendary/den boss summons *catchable* legendaries; `resolve_sphere`/`net_catch` gated on `boss` only. Dark spires could roll ironpact humans | `acquirable()` gate at both catch choke points; `spire_pick` filters `body_of != "human"` |
| H4 | HIGH | Client replicas ran real `hit()`/`kill_pal()` — phase summons and `boss_respawns` executed client-side, growing ghost kin the host never spawned | `net_id > 0` early-return at both choke points; replica pals render host snapshots only |
| M1 | MED | `phase` lost on save → re-summons up to +2 adds per save/load | persisted with H1 |
| M2 | MED | POI placement used the time-seeded session rng — joining clients placed spires/grotto/camps at different cells; delta-only decor sync leaves phantom walls | `regenerate()` reseeds `rng.s` from `world.seed` around the worldgen chain, restores after |
| M3 | MED | `spawn_pact_spires` could exhaust tries with <5 spires → unwinnable map, silent | relaxed second pass (zone-only) + `push_warning`; placement extracted to `_place_spire` |
| M4 | MED | Stale `click_rects`/`menu_sel` across transitions — one frame of last menu's hit areas stayed live; `menu_sel = -1` wrapped to the last row (QUIT on Enter) | `_menu_key` (`state|panel`) voids rects+cursor on transition; `wrapi` nav, accept guards bounds |
| L2 | LOW | `bind_gamepad` not idempotent — reload stacked InputMap events | folded into H2 fix (`_pad_erase`) |
| L4 | LOW | Dead predicate `sid.begins_with("Iron Pact")` — ids are `ironpact_*`; raider bounty never fired | `begins_with("ironpact")` |
| L5 | LOW | `spawn_net_pal` dropped `alpha`/`spire_tag` — replicas lost flags | both wires (state_snapshot + pal_state_pack) carry `boss,alpha,spire_tag` |
| L6 | LOW | `pact_slam` also hit parked `base` workers near an arena | restricted to `partner` |
| L7 | LOW | `hint_seen` survived `regenerate`; `draw_title` stat'ed `savegame.plg` every frame | `hint_seen.clear()` on regenerate; `game.has_save` cached at boot/save |
| —  | —   | Rework residue: stale "locally authoritative" comment, doubled raid/star comment, `# was never called` | cleaned |

## Deferred (documented, not fixed)

- **L1** — the 24s pad loop swells in for ~0.5s at each wrap (attack envelope
  isn't amplitude-continuous). Cosmetic; reworking the envelope risks the
  verified seamless-phase math for a subtlety no one has heard yet.
- **L2 (rest)** — `aim`/`interact`/`party_toggle` have no panel gate
  (pre-existing): keys fire while browsing panels. `pad_strike` and melee are
  gated. Tracked as a UX-hardening item, not a correctness bug.
- **M2 (rest)** — client-local drops from `spawn_nests` still diverge (drop
  sync sweeps net_drops only). Worldgen decor is now deterministic; drop
  reconciliation is a follow-up net task.

## Process findings → rules 18–24 in AGENTS.md

- Gates belonged at choke points, not enumerations: `acquirable()` filtered
  spawn pools but the *catch* path trusted `boss`; `enter_phase_two` walked
  the invariant back in. → rules 18, 22.
- Pad bindings stacked onto unaudited `ui_*` defaults. → rule 19.
- `spire_tag`/`phase` were gameplay-meaningful but never entered the save
  contract. → rule 20.
- Worldgen rolled the session stream; delta sync assumed determinism. → 21.
- Menu cursor/rects outlived their menu. → 23.
- A predicate matching a display string never fired once. → 24.
- Smoke tests verified wiring (`has_action`) not invariants, and tested the
  wrong layer (injecting into `player._unhandled_input` bypassed the HUD
  where the bug lived); `record_spire` was tested by calling `record_spire`.
  New checks exercise the real path: InputMap contents, save→load→kill, and
  catch-through-`resolve_sphere`.

## Verification

Smoke suite: 437→435 checks, 0 failures, 13 ObjectDB leaks (baseline).
IP scan: clean.
