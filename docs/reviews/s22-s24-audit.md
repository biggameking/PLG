# S22–S23 third-pass audit + S24 fix batch

Fresh-context audit over `4dcf2ca..84686f5` (touch layer, placed_by save
persistence, guest cap, BGM seam, gen_store). 2 HIGH / 7 MED / 8 LOW —
all landed in `55ccaf7`, smoke 553-556/0 failures ×3.

## HIGH — both real, both masked by tests asserting helpers not contracts

- `m_join` added to `shell_act` but never registered in `SHELL_ACTS` —
  the pause JOIN row was a dead click and touch rigs had no join path
  at all (K was the only door). Smoke asserted `shell_act("m_join")`,
  bypassing the routing table it was meant to prove. Fixed: registry
  entry + the test now drives `run_click`.
- `touch_sprint` billed 12 SP/s while the speed term only read keyboard
  sprint — stamina tax at 1.0×. The smoke test asserted the flag, never
  the payoff. Fixed: speed term honors it; test asserts displacement.

## MED

- `_process` ran the `_menu_key` transition WITHOUT the stick release
  `_unhandled_input` had — the release never ran since _process is a
  frame ahead; mid-drift pause latched a phantom run + stamina drain.
  Shared `_release_stick()` at both sites; `load_game` clears touch
  state too.
- `not game.touch_ui` disabled ALL LMB attacks — real mice on
  touchscreen laptops lost melee/throw/harvest. Taps now eaten only
  inside virtual-control zones (`touch_zone_hit`).
- `placed_by` stored a session pid — persistence that was hollow the
  moment a guest rejoined. Now `placed_tag` stores `peer_tags[pid]`
  (same identity model as `remote_parties`); save `by` round-trips the
  tag; demolish requires `t != "" and tag match`.
- gen_store: shadow ellipses wrote raw 4-tuples (hard black discs) —
  now overlay-composited; kin clamped on-canvas so `alpha_composite`
  can't throw on narrow banners.

## LOW

`pause_rows()` extracted (data-testable, no headless draw spam);
`can_dodge()` shared (was a copied ruleset); `touch_layout` cached
(AGENTS §4); menu button off the minimap rect; seam check covers the
wrap neighborhood; atk-cap band 740..800; `or true` tautology removed;
touch tests route real events through `_unhandled_input`.

## Deferred honestly (unchanged)

hello tag-swap is identity-by-tag (no auth — documented LAN scope);
guest damage claims bounded not re-derived; private-roster spend
unverifiable; produced BGM/hero art external; Android SDK absent.

## Process note

The recurring failure shape: tests asserted helper calls and flags while
the contract lived one layer up (routing table, speed term). Rules 48–51
in AGENTS.md now name the pattern.
