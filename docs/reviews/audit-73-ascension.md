# audit-73 — S121 Ascension Altar cold review + remediation

Cold review of `7c0ad90` (context-free subagent). Verdict **NEEDS-FIX** —
the diff was well-hardened on the axes it aimed at, but one real logic
defect stalled the advertised "repeatable" loop and the wire layer never
carried the ascendant's distinguishing state.

## Findings → fixes

| # | Finding | Fix |
|---|---------|-----|
| MED-1 | `_ascendant_live()` counted ANY `pals` member with the meta — a caught heir fielded as `partner` kept it and **sealed the altar forever** | `_ascendant_live()` requires `mode == "wild"`; `release_event_flags` strips `ascendant` on capture — ownership ends the claim. Regression pins: "caught heir releases the altar's claim" + "the ring re-opens after the catch" |
| MED-2 | Forged `ascension_req` (no pay hold) spawns a free ascendant | **Accepted + documented**: inventory is client-authoritative (shrine/gacha precedent); a modified client owns its bag anyway. Host gates what IT owns — seal, ghost reach, live ring, capacity. Comment at `ascension_req_remote` names the boundary |
| LOW-3 | Rewild lane could re-mint a blocking/bounty-paying ascendant | Killed by the capture-strip — a released heir has no meta, can't re-block or re-pay |
| LOW-4 | `ascension_done` silently drained the guest's bag | Guest-side `log_msg` added (shrine_done parity) + zh row |
| LOW-5 | Summon-steal: anyone can catch a guest's paid ascendant | **Documented design** — identical to den-heir ownership (the wild heir belongs to whoever lands the orb); the cost buys the ring, not the claim |
| LOW-6 | Host reach 5.0 vs ghost 4.0 | Both paths now 5.0 |
| LOW-7 | `_nearest_struct` queried twice per remote ring | Hoisted into a single `cell` |
| LOW-8 | Doc claimed "0 skipped" — real runs show 1 (seeded grotto fixture) | `s121-ascension-altar.md` corrected + count-drift note |

## Self-found during remediation

- **Wire field 14 missing**: `pal_state_pack`/`spawn_net_pal` never carried
  `asc` — guests saw a normal-sized alpha, not the 1.3× heir, and the meta
  never reached replicas. Field appended, `spawn_net_pal` mints meta+scale;
  smoke pins the forged-row path, net_verbs proves it E2E.
- **Discoverability**: the Accord epilogue now names the altar once —
  the loop's only door was otherwise invisible until a tech-list stroll.

## Verification

- smoke **1051/0/0 skip** (RNG-banded: 1045–1051 across runs)
- net_verbs two-process windowed run: **HOST 19/0 + JOIN 19/0**
  - `guest ring calls an ascendant on host truth` (wild alpha raid, ledger=1)
  - `a second guest ring is refused — one walks, ledger still` (cnt=1 tot=1)
  - `guest ring settles + replica carries the asc flag` (rep=true)
  - `a second ring is refused — the hold refunds` (orbs 0→2, sigils 0→1)
- `IP CHECK: CLEAN`

## Lesson

World-gate metadata needs a **mode-scoped live check AND a capture-strip**:
a flag that outlives its mode seals its own gate. And a spawn-time visual
transform must ride the wire — replicas diverge silently otherwise.
