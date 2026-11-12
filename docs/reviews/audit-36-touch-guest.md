# Audit 36 — Touch slab & guest co-op parity (S82)

Context-free sweep of the two least-audited faces: the touch input path and the
remote-client experience. Verdict: the verb surface is broad and host-authority
is honest — the gaps were all in the guest's *own* assets being unreachable.

## Landed fixes

### Guest parity (High)
- **Guest catches credited the host's ledger.** `net_catch` wrote the shared
  `catch_counts`, so a guest's kindex/mission chain ("catch 3 kin") stalled
  forever. Now `net.rpc_id(pid, "catch_credit", sid)` rides home after the
  world book logs it — the client's `credit_catch_local` ticks its own copy,
  which is exactly what `total_catches()`/missions/kindex read locally. The
  world ledger intentionally still counts every catch (the island's catalog
  feeds accord/dex completion — a shared-world contract).
- **Deploy was a one-way door.** `pal_state_pack` never carried `owner_id`, so
  a guest couldn't even tell which base rows were theirs. Pack row now appends
  `owner_id` at `[12]`; `pal_sync`→`spawn_net_pal` stamps replicas; the kinbox
  shows `[base_in]`/`[mv]` only for rows the client owns (`owns_pid` still
  enforces host-side — UI follows the wire, not replaces it).
- **Pause INVENTORY row was dead for every input.** `pause_rows` emitted
  `m_inv`, `shell_act` handled it, but `SHELL_ACTS` never listed it — the
  run_click fallthrough dropped it. One word in the const; rule-49 class.
- **No raid warning reached guests.** The 30s horn floater was host-local;
  now `net_floater` relays "RAID INCOMING — %s!" to every ghost pid.
- **`assign_remote` failed silently** when no owned kin/site was in range —
  now `note_remote` explains the miss.
- **`cycle_field_pal` orphaned replicas** on a client (bench is a wire view —
  cycling moved a replica into local bench → duplicate on next pal_sync).
  Early-returns on clients.

### Touch
- **Catch-odds preview was gated off.** Removed the `not game.touch_ui` gate;
  touch targets the nearest wild kin in the facing cone (dot>0.3, 5 tiles)
  instead of mouse hover.
- **`partner_skill` aimed at a phantom cursor** (last emulated-mouse pos, i.e.
  the slab corner) — touch now fires 4 tiles down the facing line.
- **Hints addressed a keyboard that isn't there.** All 7 keyboard-phrased
  hints got `"touch"` alternates (ATK/BLD/INV/≡ phrasing); the HUD picks
  `touch > pad > text` by device.

### Carried over from S81 visual review
- **Guide volume text no longer truncates.** `guide_scroll` + wheel/tap
  scrollers + a `1-41 / 83` range indicator — Vol I reads to the last line.
- Pixel-measured wrap + hard clip already landed earlier; screenshots
  verified: guide fits the paper, kinbox rows clear the button columns.

## Deferred (documented, not fixed this stage)
- Expedition kin invisible to guests (pack ships only wild/base/partner) —
  cosmetic; the post's `exp_t` timer does sync.
- Dead currency displays on clients (tech/stat points accrue but can't be
  spent — deliberate host-authority, panel wording could say so).
- Touch demolish is nearest-only; panel lists use ▲▼ taps not drag-scroll.
- Party quick-swap on touch (kinbox [▼] is the route).

## Evidence
- `==== 893 checks, 0 failures, 1 skipped ====` (worldgen condition item)
- New asserts: own-ledger credit, pack `[12]` owner stamp, replica owner,
  `m_inv` routes, preview ungated, horn relay, assign answer.
- Live-play: `==== S81 live-play: 0 failures ====`; guide + kinbox PNGs
  inspected — wrap, scroll indicator, and button columns all clean.

## Verifier round (second context-free pass on 8ad8f4c)

- **Medium — join-time owner_id loss:** `state_sync` built spawn rows ending
  at `e[11]` (no `e[12]` forward) and `pal_sync`'s update path never
  re-synced the field — replicas spawned at join held `owner_id = 0`
  forever, silently neutering the new `mine` gate. Fixed at `net.gd:348`
  + existing-replica path (`net.gd:408`).
- **Medium — dead guest [mv]:** `skill_tgl` sent `cr["arg"]["p"].uid` raw;
  replicas carry `uid = -net_id`, unresolvable by host `find_pal` — a
  click that did nothing. Now sends `net_id` like `KINBOX_OPS` already
  did (`hud.gd:507-509`).
- **Low — _struct_gen coverage gap:** the scripted insert matched zero
  erase sites while reporting 3 — bumps added after all three erase
  loops + `state_sync`'s clear.
- **Low — preview↔throw divergence:** touch preview selected nearest in
  a `dot>0.3` cone while `throw_sphere` picks best `dot>0.6` in
  `[0.4, 5]`; preview now mirrors the throw exactly.
- Nits: `get_peers()` guard on the `catch_credit` send; smoke ledger
  restore uses `erase` (no phantom zero-count key inflating dex tiers).

Process note for the record: the verifier had no shell — it flagged that
`git show` couldn't confirm the working tree matched the commit. The
fixes above were verified against the live tree and re-tested.

Suite: `==== 893 checks, 0 failures, 1 skipped ====` — 851f888.
