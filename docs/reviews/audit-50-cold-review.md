# Audit-50 — cold process review of S96–S97 (dafb650..eb846ba)

Context-free subagent review of HOW the stage was done — evidence
quality, not game design. 18 findings; all MED/LOW landed in this pass.

## Verdict

Work was real and verified; the sins were evidence-chain gaps — claims
that outran instrumentation, one real data-loss bug in leak_probe, and
three commits with no ledger entry. All fixed below.

## What the review caught (severity order)

- **[MED] Claim exceeded instrumentation.** audit-49 asserted the full
  disconnect teardown "ran live" but net_host only sampled
  `ghosts=%d peers=%s`. Fixed: net_host now detects ghost 1→0 and writes
  `disconnect: ghosts=0 rparty=%d tags=%d`. Fresh run transcript:
  `ghosts=1 peers=[1084324222]` then `disconnect: ghosts=0 rparty=1
  tags=0` — ghost freed, tag pruned, roster persisted for rejoin
  (rule-48 observed on the wire).
- **[MED] leak_probe clobbered the real savegame.** `save_game()` ran 3×
  per soak with no backup — a rule-30 violation promoted to the gate
  block. First fix used `get_as_text`/`store_string` on a binary
  `store_var` file and corrupted it (5-byte UTF-8 mangling observed on
  disk — the probe's own residue, player saves live elsewhere). Now
  byte-level backup/restore, matching smoke's own contract.
- **[MED] Tolerance band borrowed across metrics.** The ~8-17 jitter
  band is documented for the exit-banner leak census; the probe measures
  live OBJECT_COUNT. Conclusion still right (entity-layer nodes flat),
  now documented as its own band: ≤~20 over 3 rounds with flat el-count.
- **[MED] Zero durable visual-QA record for 116 re-renders.** Added
  `docs/reviews/s97-contact.png` — committed contact sheet of the weak
  archetypes (serpent/blob/human/ghost/bird/player), f0 vs f1 rows.
- **[LOW] net_join silent-skip.** `host_day < 0 or` made a fixture-read
  failure pass; now `>= 0 and`. Stale marker + `plg_net.cfg` residue
  cleaned at probe start.
- **[LOW] Fixture hygiene.** Campfire evict went through
  `raze_structure` not dict-shallow erase; ring eviction scrubs
  `job_site.workers`; outpost comment no longer overstates; hostile-kin
  fallback relocates the player instead of blind +1,0.
- **[LOW] Player rig kept old f1 amplitude** — the flagged weak spot
  persisted on the most-seen sprite. Bumped to parity, re-rendered.
- **[LOW] Ledger gap.** S96b/c295271/S97 had no ROADMAP entry — added.
- **[LOW] One-off tools.** `rename_ip.py`, `i18n_wrap.py`,
  `i18n_zh_merge.py` archived per the S95 convention.
- **[INFO] Verified honest:** join's 4 checks are real wire assertions
  (client spawn_wild early-returns — kin can only arrive via pal_sync);
  no tautology in the de-flakes (fixture selection vs assertion stayed
  separated); 115-species re-render was required (shared generator
  params), not waste; `player` through render_kin.py is the correct path.

## Transcripts (re-run 2026-05, seed 42755)

join: `PASS join sees host ghost ghosts=[1]` / `world seed synced
have=42755` / `kin respawned locally 24` / `day synced day=1` → **4/0**

host tail: `ghosts=1 peers=[1084324222]` → `disconnect: ghosts=0
rparty=1 tags=0`

leak soak (save-safe build): 3695→3701→3708→3711, **delta +16**, el flat
1772 — inside the probe band.

smoke: 966/0/1skip (grotto room-2 terrain — legal skip).

## Next-stage process change (carried forward)

**Paste transcripts into the audit doc** — paraphrased numbers are a
re-run requirement, not evidence. Done here and going forward.
