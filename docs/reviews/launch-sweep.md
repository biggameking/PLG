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

## Deferred — honest list

- **Android preset unverified**: local SDK lacks `build-tools`/`apksigner`; also zero touch input implemented — treat mobile as not-a-target for this release.
- **Pad**: navigation/action layer works; rumble and hold-to-repeat not implemented.
- **UI art**: still default-font panels + procedural icons; hero-species polish is procedural accessory layer only.
- **BGM**: two procedural pads (day/night) — functional, not a produced score.
- **MP**: LAN-only host-authoritative; no lobby/NAT traversal; client drop-reconciliation not implemented (drops only exist as host-synced replicas).
- **Day/night pad loop**: ~0.5s crossfade seam is audible on loop wrap.

## Release-shape recommendation

itch.io / free EA candidate on Windows+Web today. Steam paid still wants real
art pass on ~12 hero species + one produced music track + store assets.
