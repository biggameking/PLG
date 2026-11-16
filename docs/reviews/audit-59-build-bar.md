# Audit-59 — S106 build-bar paging / icons / ghost cold review

**Scope**: commit c15a844 "S106" — `build_scroll` 9-slot paging in
`draw_build_bar`, `struct_tex` icons + placement ghost in `src/hud.gd`,
`build_pg`/`build_pick` click acts, key 1-9 paging, `tools/smoke_test.gd`
paging + `struct_dims` completeness checks, `tools/shot_build.gd`.
Read-only cold audit by a context-free subagent.

**Verdict**: NEEDS-FIX — 1 HIGH, 3 MED, 6 LOW. All fixed below; nothing
crashed (every index access guarded, cache bounded).

## Findings → resolutions

| # | sev | finding | resolution |
|---|-----|---------|------------|
| 1 | HIGH | Ghost sprite drawn `tex_h/2` too low — `place_structure`'s center-anchor offset applied to `draw_texture_rect` top-left; preview landed 52–83px under the real plant point | hud.gd ghost rect top-left now `gs + (-W/2, -H + 8)` — identical rect to the planted sprite; `s106-build-ghost.png` captured and committed (was never eyeballed before) |
| 2 | MED | Draw-time clamp + ±9 stepping produced non-page-aligned windows; `(n/m)` lied on the tail page (evidence in s106-build-page2.png itself) | Snap to page edges: `build_scroll = clampi((scroll/9)*9, 0, (pages-1)*9)` |
| 3 | MED | Wheel paging dead code — `"build"` missing from the wheel gate | Added to the gate list; `_panel_scroll` case already stepped ±9 |
| 4 | MED | Smoke page-flip checks could vacuous-pass — gate counted unfiltered `unlocked` | Fixture loops on `buildable_list().size() > 9`, asserts the headcount, else-branch now fails loudly instead of auto-pass |
| 5 | LOW | `build_scroll` survived panel transitions (inconsistent with dex/guide) | Reset to 0 on both open paths (keybind + `bld` verb) |
| 6 | LOW | List reorder silently retargets `build_sel` | `build_sel_sid` pins the picked sid; `place_ghost` refuses + re-pins on mismatch (net_unlocked swap safe); smoke pin added |
| 7 | LOW | ~4% icon squeeze for ar>1.385 (ranch only) | Accepted — 18px cap protects the label gutter; cosmetic only |
| 8 | LOW | Per-frame allocations in the ghost loop | `draw_set_transform` + one static diamond template; `buildable_list()` hoisted once per draw |
| 9 | LOW | Same-frame stale click_rects after page flip | Theoretical (sub-frame); noted, no change |
| 10 | LOW | `shot_build.gd` picked an off-page index | Now picks via `run_click build_pick arg:10` on page 2 through the real path |

## Same-session discovery — the multiplayer evidence bug chain

While producing real host/join screenshots the run surfaced a **critical
latent defect**: `main.gd` instantiated the `net` node with no `name`, so
Godot assigned auto-names (`@Node@221`/`@Node@222`). RPC packets carry the
sender's node path — any divergence in node-creation order between peers
made **every RPC land on a nonexistent path and drop silently**
(`Invalid packet received`). The headless probes passed only because both
processes created nodes in identical order — an accident, not a contract.

- **Fix**: `net.name = "Net"` before `add_child` — deterministic path.
- **Second defect**: `pal_sync`/`drop_sync`/`struct_sync` sent whole
  rosters as single unreliable datagrams — 6.2KB at 45 kin, ~30KB at the
  220 cap — fragmenting past MTU (engine WARN). Now chunked by byte
  budget (`SYNC_BUDGET`=1100B, `var_to_bytes` per row) with idx/total
  reassembly + forge guards; buffers cleared on `_close_peer`.
- **Third defect**: `shot_net_host.gd`/`net_host.gd` wrote the state file
  even when the port bind failed — joiners could handshake a dead host.
  Both now bail when `is_host` stays false.

## Multiplayer visual evidence (first ever captured)

- `docs/reviews/s106b-net-join.png` — guest view: local player walked
  off spawn, host ghost visible at spawn; "Synced world seed 34872" +
  "Synced 41 structures, 45 kin" in log.
- `docs/reviews/s106b-net-host.png` / `s106b-net-host2.png` — host view:
  guest ghost tracked to exactly (+64,+128px) — the (5,3)-tile move —
  `host: guest-ghost screen=(64,3648) player screen=(0,3520)`.
- Zero RPC errors, zero MTU warnings in both logs.
- Position validation worked correctly: an early run that teleported the
  guest onto a blocked tile was correctly rejected by the host's
  anti-spoof gate (ghost stayed at last honest fix).

## Verification

- Smoke: **981 checks, 0 failures, 1 skipped** (grotto room-2 terrain
  skip — pre-existing, seed-dependent).
- `shot_build.gd` re-captured all three shots; `s106-build-ghost.png`
  now committed.
- `tools/net_join.gd` headless probe unchanged behavior: 4/4 PASS
  (seed/day/ghost/teardown).
