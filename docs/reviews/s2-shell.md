# S2 product shell — external review (commit 47587b0)

Reviewer: fresh-context subagent, read-only code audit.

## HIGH findings and resolutions

| # | Finding | Fix |
|---|---|---|
| H1 | Menu input leaked to gameplay: `player._unhandled_input` had no `game.state` gate — RESUME click also swung the weapon; Q/Tab/R/G/Space all live under menus | `player.gd:50` now returns early unless `state == "play"`; hud title/paused branches call `set_input_as_handled()` so shell-owned events stop propagating |
| H2 | Hostile wild kin could kill the player on the title screen (`hurt_player` ran while the world was ambience) | `hurt_player` returns early unless `state == "play"` |
| H3 | `to_title()` leaked the multiplayer session: `MultiplayerAPI` peer survives `reload_current_scene`, old host misdetected as client, port stayed bound, client `save_game` would clobber the solo save with replica state | `to_title` nulls the peer and `is_host` before reload; `save_game` early-returns for clients; `_on_server_disconnected` nulls the peer too |

## MEDIUM findings and resolutions

| # | Finding | Fix |
|---|---|
| M4 | `net_live()` checked peer presence, not connection status — dropped peers held the sim open | Now checks `get_connection_status() != DISCONNECTED` |
| M5 | Online "pause" was a mislabeled overlay | Pause title reads "MENU — the world keeps running" when `net_live()` |
| M6 | `load_game` left stale shell state (armed `raid_warned`, open panel, dead `chest_ref`, held aim) | All cleared before `Loaded.` |
| M7 | `load_settings` copied untrusted cfg values raw — a String where a float/bool belonged crashed or inverted flags | Per-key type coercion, volumes clamped to 0..1 |
| M8 | `save_game` didn't null-check `FileAccess.open(WRITE)` | Guard + error log added |

## LOW — accepted / deferred

- Quit-confirm and overwrite warnings: deferred to the settings/UX pass.
- Idle CPU burn on title (`queue_redraw` every frame): deferred.
- `save_settings` writes per tap + smoke polluted `user://settings.cfg`: the test now backs up and restores the file (fixed).
- `summon_raid`/`start_gauntlet` bypass the raids toggle: intended (player-initiated), noted.
- Menu keyboard/gamepad nav: title accepts Enter; full menu nav landed with the S6 gamepad pass.

## Process lessons (durable)

1. `return` in `_unhandled_input` does not own the event — every consumer must gate or someone must `set_input_as_handled()`.
2. `reload_current_scene()` is not teardown — engine singletons (MultiplayerAPI peer, AudioServer, InputMap) survive it; the caller owns resetting them.
3. `settings.cfg` is untrusted input like any save — coerce at the boundary (rule 5 extension).
4. Tests that write `user://` must restore what they dirty.
5. One predicate for shell state — `== "paused"` vs `!= "play"` drift caused H2.
