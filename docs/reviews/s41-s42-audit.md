# Eighth context-free audit — S41 merchant mirror + honest-path sweep (S42)

Scope: guest merchant parity (mirror + stock + merch_hit) and the full
host-authoritative verb surface. Reviewer had no prior context; audited the
working tree while S39–S41 edits were still landing, plus the final S41 commit
`862d74c`.

## Verdict

Guest-parity surface is structurally sound — the reviewer verified the whole
gate matrix clean (sync_pos, pal_hit, net_catch, take_drop, chest_req,
net_demolish, net_place, every `*_req_remote` structure gate, box_op owner
slicing, orphan/rebind contract). What remained was a class the previous rounds
hadn't reached: **honest-client economy paths** — things a stock client could
do that mint, crash, or strand state. All resolved in S42.

## Findings and resolutions

| Sev | Finding | Resolution |
|---|---|---|
| H1 | Free purchase → infinite gold mint. No affordability gate on buy rows; `bought` subtracted from an empty stack and goods stayed; resale converted free goods to coin. Same class on `infuse_req`. | Buy rows gate `item_count("gold_coin") >= price` (soft+unclickable otherwise); infuse gates ≥1 effigy. Bound documented: forged bags remain client-authoritative. |
| M1 | `add_item` overflow: `spawn_drop` early-returns on clients → `drops.back()` nil-crash + silent item loss via honest echoes. | Guest over-cap stays in their own bag; `drops.is_empty()` belt guard on host path. |
| M2 | `craft` read `unlocked` not `net_unlocked` — guests could never craft host-tech recipes despite building the stations. | Effective tech list mirrors buildable_list semantics. |
| M3 | Shared `max_base_pals()` cap counted every owner's workers; host had no eviction for guest kin. | `base_pals_of(pid)` — caps are per-owner slices. |
| M4 | Dead-pid egg hatch locked a kin forever: `opid>0` skipped the tag resolve → `owner_id` = a session that no longer exists. | Dead pid → 0 → tag resolves to a LIVE peer else orphan+tag (hello rebinds). |
| M5 | `hello` was the only unthrottled `any_peer` verb (O(roster)+RPC fan-out per call). | `hello_bkt` 1/s burst 4, ghost-scoped (headless calls don't fail closed). |
| L1 | `_free_incubator` compared `distance_squared_to` with a linear bound — the remote arm was √6≈2.45 tiles, not 6. | `bd := bound * bound`. |
| L2 | `egg_parents` pop consumed the first non-empty queue anywhere — a guest's egg inherited the host's ranch genetics. | Entries carry parents' owner ids at index 8; `_claim_egg_parent(pid)` pops only matching claims; legacy rows answer the keeper. |
| L3 | Guests couldn't raze a backup kinbox they placed (anchor refusal preceded the ownership check). | Anchor refusal now scopes to `st.pos == kinbox_pos` after placed_tag. |
| L4 | `chest_took` RTT race could over-credit the shared chest. | Skipped — bound-adjacent (forged clients need no race). |
| L5 | `memory_wipe` respec worked for guests but produced unspendable stat_pts (perk verbs are host-gated). | Guest-gated like upgrade_perk. |
| L6 | Bag-row `kin_egg` was a dead button (`client_locked`) while the interact path correctly routed `egg_req`. | Bag row routes `egg_req` with the clicked egg's id. |
| L7 | `work_req` flipped shared `work_mode` cost-free with no rebroadcast — other guests' mirrors drifted. | `wmode` rides `env_sync`; converges within a tick. |
| L8 | `pal_hit` `clampf(sleep_s, 0.5, 15.0)` inflates a 0.001s claim to 0.5s. | Skipped — `slp_immune` still blocks chains. |

## Verified clean (spot list)

sync_pos (spawn/first-fix, speed bucket, blink lanes, elev clamp),
pal_hit (wild-only, ghost ≤8, claim veto, honest-damage bound),
net_catch (behind re-derived, cap_lv clamp, owner slice),
take_drop (fail-closed ghost + reach + monotonic dids),
chest_req (whitelist, gold veto, food rule), net_demolish (tag + reach),
net_place (host unlocked + reach + cap), box_op_remote owner gating,
orphan→tag→hello rebind, hit_merchant client→merch_hit→aggro_pid.

## Process notes adopted

- Reviewer had no exec: diff-attribution and suite tail unverifiable —
  parent verified `==== 69x checks, 0 failures ====` ×4.
- New rule 69 proved its worth immediately: the S41 harness caught
  `state_snapshot`/`pal_state_pack`'s latent `p.lv` crash that every real
  join would have hit.
- Echo-underpay coverage pattern added (UI affordability gate = the
  `board_done` precedent generalized to `buy`/`infuse`).

## Residual bound (documented, accepted)

Forged-client freebies the trust model accepts: build_deny refunds,
board_paid goods-settled trust, chest dep valid-id conjure,
sphere_catch sid claims, tag-theft needing the local token.
