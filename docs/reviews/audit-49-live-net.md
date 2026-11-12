# Audit-49 — real-socket multiplayer + leak soak (S96)

Not a code lens — an evidence stage. Every prior network assertion ran
inside one process with spawned ghosts. This ran two real Godot processes
over ENet loopback and a 3-round lifecycle soak.

## Live session (tools/net_host.gd + tools/net_join.gd)

- Host writes `tools/net_host_state.txt` (seed, day/tod, peer sampling);
  join reads it and asserts over the real wire: **4/0** —
  host ghost visible (pid 1), world seed synced (79977), 26 kin spawned
  locally, day synced.
- Host log proves the full lifecycle ran live: `ghosts=1 peers=[…]` for
  two samples, then clean teardown — `_on_peer_disconnected` ran
  `r_retract` (field pal balls up), `orphan_guest_kin` (roster survives
  under the tag), `peer_tags`/`chat_last` pruning, `peer_left` broadcast.
- Repro: run `net_host.gd` headless first, then `net_join.gd`; verdict in
  `tools/net_join_out.txt`.

## Leak soak (tools/leak_probe.gd)

3 rounds of spawn/kill churn, drop/collect, build/raze, save/load:
objects 3794 → 3796 → 3801 → 3804, **delta +10** — inside the documented
~8–17 jitter band; entity-layer node count flat at 1863. No secular
growth.

## Known-benign noted

- One `put_packet` stderr line: the host's 2Hz `pal_sync` broadcast fired
  once in the window where the ENet peer was dropped but the ghost was
  not yet pruned. Harmless race; recorded here so it isn't mistaken for
  a new defect later.
- `host peers` shows the raw ENet id (754713170), not the small pid —
  expected; ghosts key on the small id.
