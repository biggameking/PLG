# Kinbound launch sweep — verified vs deferred (S16)

> **Stale — superseded by S60/audit-22** (HEAD ~`4469668`, 763-check
> suite). Findings below are the S16-era snapshot; the authority surface
> claims still hold but check counts, artifact names and the deferred
> list have moved. See ROADMAP S55-S60 for the current release gate.

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

- **Android preset unverified**: local SDK lacks `build-tools`/`apksigner` — treat mobile as not-a-target for this release. Touch input itself now ships: on-screen stick (rim = sprint) + ATK/AIM/ROLL/E/ORB/☰ buttons, `settings["touch"]` auto/on/off (auto = `DisplayServer.is_touchscreen_available()`), verified headless via `hud.touch_down/move/up` (9 checks).
- **Pad**: nav, actions, hold-to-repeat (0.42s/0.09s cadence), rumble on
  catch/hit, and panel row navigation (dpad steps, A confirms) all ship.
- **UI art**: default font, but the shell got a real pass — pixel brand type
  (OFL Press Start 2P), animated procedural dawn (sky/sea/island silhouette/
  motes), wordmark with gold rule + orb sigils, header accents, row
  separators, cursor ticks. In-game juice: screen shake on hits/phase-2,
  screen-space rain/storm/drought FX, pulsing danger vignette. Hero-species
  polish remains the procedural accessory layer.
- **MP — guest combat parity is approximate**: host wildlife engages the
  nearest warm body (player OR ghost), melee bites reach guests via
  `guest_hit`, and wild projectiles relay through `guest_skill_hit` — the
  guest applies the same `power*0.6` keeper pipeline locally (own armor/
  absorb, statuses only when damage lands, chance rolled host-side). Guest
  shots relay through `pal_hit` — S21 hardened it: a per-sender token
  bucket (3/s+6 burst) and the claim is now bounded by the formula's own
  ceiling against THIS target's def (≤250 landed), not a blanket cap;
  forged `sleep_s` routes through the same chain-sleep immunity as the
  host's own tranq. `danger` reaches clients via env_sync. Guest
  teleports are shaped, not banned: `sync_pos` accepts >12-tile jumps
  only onto travel nodes (kinbox/spawn from anywhere = respawn; waypoint
  needs a node departure), home-lane blinks carry a 3s cooldown, and
  elevation is finite+clamped. S21 authority: every client→host request
  is per-sender throttled (catch ~1.4s, build/demolish ~1s, harvest/
  loot/roster 8/s+10); `demolish` refuses anchors and anything not
  stamped `placed_tag = peer_tags[sender]` (the keeper tag — pids die
  with the session, tags survive rejoin; save `by` round-trips the tag);
  disconnect orphans the guest's roster
  under its tag (rejoin reclaims via hello), purges field kin into the
  box, and drops all host replicas; a guest's pal provokes the guest
  (`owner_id` rides hit/skill_hit); foreign partners can't graze the
  host pantry/medicine. Remaining trust class: client claims of damage
  dealt and items paid are bounded/gated, not re-derived — private bags
  are client-side, so a forged `build_req` can still plant an unlocked
  structure free in the shared world (throttled + tech-gated; deny refunds
  only fire for honest-reachable placement failures, so forgery gains the
  plant itself but never free materials). Co-op friend scope.
- **BGM**: three procedural pads — day, night, and a minor danger drone that
  swallows the mix during raids/gauntlets/phase-2 bosses — each with a
  plucked arp layer so the drones carry a line. The loop seam is fixed:
  arp slots quantize onto the loop boundary and the wrap edge meets at
  zero crossing (smoke-verified). Reactive, still not produced.
- **MP — orb claims aren't inventory-verified**: `sphere_catch`'s `sid` is client-claimed; the host validates it's a real sphere type but can't check the guest actually owns one (private rosters are client-side). Design limit.
- **MP — no lobby/NAT traversal** (co-op is direct-connect IP).
- **Cosmetic phantom damage**: `tick_shadelump`/`update_projectiles` can flash damage on replicas; `pal_sync` reverts within a sync beat. Visual only.
- **Store assets**: procedural capsules ship in `store/` (Steam 460x215 + 616x353, itch 630x500, hero 1920x622 — `tools/gen_store.py` regenerates from the same dawn-scene contract as the title). Procedural, not commissioned key art. `tools/package.sh` builds versioned zips for itch (verified artifacts); `store/page.md` is the page copy; presets exclude `store/*` from shipped builds.

## Release-shape recommendation

itch.io / free EA candidate on Windows+Web today. Steam paid still wants a
real art pass on ~12 hero species + one produced music track; store
capsules now exist procedurally (good enough for itch, thin for Steam
key art).
