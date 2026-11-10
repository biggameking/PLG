# S21 re-audit — second context-free pass

Scope: `net.gd`/`game.gd` authority hardening landed in `3efadd8` plus the
S22 touch layer. Read-only audit, no execution. Findings landed in `f390574`.

## MEDIUM (all fixed)

- **M1 orphan_guest_kin lost `visible`** — expedition kin boxed while
  `visible=false` and no exit path restored it (unbox/send/deploy never
  touch the flag) → invisible workers/partners on rejoin. Fix: `p.visible =
  true` in the orphan loop.
- **M2 sphere_catch cap_lv clamped to 20, real max is 6** — capture_level =
  1 + statue(≤5); a claim of 20 gave a 1.76 cap factor vs honest 1.20,
  saturating the 0.97 roll ceiling. Clamp now `1..6`. (Rule 47 — the bound
  had rule-43's shape but not its math.)
- **M3 sync_pos first fix was a free blink** — `net_pos.x >= 0` exempted
  all gates once per ghost lifetime (rejoin re-armed it); every proximity
  verb trusts net_pos. Fix: first fix must land within 12 of world.spawn
  or on a travel pad, else net_pos stays -1 (fail-closed).
- **M4 net_catch box gate was per-owner only** — a guest could push
  `box.size()` past MAX_BOX, locking the host's own catches. Fix: global
  `box.size() >= MAX_BOX` gate alongside the per-owner lane.

## LOW (all fixed)

- L1 orphan cargo: `p.carry` routed home via `give_remote` (falls back to
  host bag for a gone peer).
- L2 orphan `box.append` capped at MAX_BOX+32; past the lane the kin is
  released with `owner_tag` cleared.
- L3 `peer_pos` relayed raw `elev`; now relays the clamped `g.net_pos.z`
  and rejects non-finite values.
- L4 `kill_pal` overflow path kept `owner_tag` on wild-released kin —
  a `hello` rebind could own-id a wild kin, then orphan-box it with no
  roll. Tag cleared on release.
- L5 `pal_hit` 0/0 claims woke tranq'd kin and pulled aggro — dropped
  before `hit()` runs.
- L6 `build_deny` refunded every denial incl. forged locked requests —
  free materials. Now only placement-failure denials (honest race) refund.
- L7 `chat_last` pruned on disconnect (peer-id reuse safety).
- L8 `_legit_blink`/`_near_travel_node` scanned `game.structures` twice
  per oversize packet → cached travel-cell set, rebuilt on count change
  or 3s TTL.

## Process findings absorbed

- Boxing/transfer paths must scrub the full per-kin flag set
  (`visible`, `carry`, `job_site`, `owner_*`), not just `mode` → rule 46.
- Clamp bounds must derive from the model's actual max, verified against
  data — a plausible-looking constant IS the exploit → rule 47.
- Smoke gaps closed: spawn-gated first-fix accept/reject, expedition-mode
  orphan coverage, zero-claim no-op assertion.
