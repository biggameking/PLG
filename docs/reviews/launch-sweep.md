# Kinbound launch sweep — verified vs deferred (S16)

Date basis: HEAD `fb9e7c1` + audit-fix batch `c775b20`.

## Verified by tool output (not claimed)

| Gate | Evidence |
|---|---|
| Smoke suite | 456–459 checks, **0 failures**, ×5 consecutive runs; zero ObjectDB leak banner under headless Dummy driver (audio `play()` gated by `audio_live`) |
| Balance sim | `tools/sim_balance.gd` → `==== SIM: 0 failures ====` (day-1 raid survivable, curve saturates, wave size saturates; shares `Combat.raid_*`/`cap_power` with shipped code) |
| IP scan | `tools/check_ip.sh` → `IP CHECK: CLEAN` |
| Windows export | `kinbound.exe` 115 MB, embedded PCK, preset `Windows Desktop (Steam)`, s3tc_bptc on |
| Web export | full artifact set (index.pck 5.9 MB + index.wasm 38 MB + icons/manifest) |
| Shell E2E | title→new_game→pause→settings→resume→save→continue→load asserted in-suite |
| Save schema | round-trip incl. `stag`/`ph` campaign tags; `Migrate.save_dict` covers legacy keys |
| MP authority | fail-closed ghost guards, client-claim validation, replica uid=-net_id, clients no longer tick the world |
| Localization | zh slice verified in-engine (quoted CSV; backslash-comma was literal) |
| devrules | review records closed: S1/S2/S3, S4–S7 (retro), S8–S12 |

## Second external pass (post-sweep)

A fresh-context reviewer re-audited HEAD after the first fix batch and found the
same defect class one layer down: the frame-loop world systems were gated but
the interaction-verb layer was not. Closed in this pass:

- `tick_migration` gated — phantom herds with real AI/loot on clients (was the
  named exception; its downstream impact was never reconciled)
- `load_game` refuses on clients AND on a host with connected guests; J/K key
  handlers refuse mid-session; `net.host()`/`join()` close the old peer before
  rebinding (was a live-peer swap that flipped `is_client()` off on a guest)
- `respawn_player` no longer deletes a guest's bag (spawn_drop is host-only)
- 15 world-mutating interaction verbs route through `client_locked()`:
  deposit_egg, dig_fossil, free_captive, open_mimic, pray_weather,
  sleep_to_morning, fertilize, teach_skill_fruit, soul_infuse, cast_line,
  start_gauntlet, unlock, chest_deposit/withdraw, cycle_work_mode
- `tick_assign`/`tick_repairs` gated (were writing replica job_site/hp)
- `record_spire` re-validates the tag at the choke point
- `chat` uses `get_remote_sender_id()`, 160-char cap, one relay per 0.25s
- regenerate/load_game checklist gaps: hint_seen, focus_target, death_marks,
  raid_warned/theme/t(re-armed to 180), catch_counts/streak, player.statuses
- smoke suite: save restored right after the last save-mutating test;
  smoke_out.txt truncates per run (was still appending)
- new negatives in-suite: 11 client-context refusals exercised against a real
  connecting ENet peer (465 checks / 0 failures)

## Deferred — honest list

- **Android preset unverified**: local SDK lacks `build-tools`/`apksigner`; also zero touch input implemented — treat mobile as not-a-target for this release.
- **Pad**: nav, actions, hold-to-repeat (0.42s/0.09s cadence) and rumble on
  catch/hit all ship; UI rows aren't pad-scrollable inside panels yet.
- **UI art**: still default-font panels + procedural icons; hero-species polish is procedural accessory layer only.
- **MP — guest combat parity is approximate**: host wildlife engages the
  nearest warm body (player OR ghost), melee bites AND wild projectiles reach
  guests via `guest_hit` (projectile damage sent as atk-equivalent —
  `power * 1.2`, statuses don't transfer). Guest→host damage still runs
  through `pal_hit` as before.
- **BGM**: three procedural pads — day, night, and a minor danger drone that
  swallows the mix during raids/gauntlets/phase-2 bosses. Reactive, not
  produced.
- **MP — orb claims aren't inventory-verified**: `sphere_catch`'s `sid` is client-claimed; the host validates it's a real sphere type but can't check the guest actually owns one (private rosters are client-side). Design limit.
- **MP — no lobby/NAT traversal; client drop-reconciliation unimplemented** (drops only exist as host-synced replicas).
- **Cosmetic phantom damage**: `tick_shadelump`/`update_projectiles` can flash damage on replicas; `pal_sync` reverts within a sync beat. Visual only.
- **Day/night pad loop**: ~0.5s crossfade seam is audible on loop wrap.

## Release-shape recommendation

itch.io / free EA candidate on Windows+Web today. Steam paid still wants real
art pass on ~12 hero species + one produced music track + store assets.
