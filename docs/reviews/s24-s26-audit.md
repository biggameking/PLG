# S24–S25 fourth-pass audit + S26 fix batch

Fresh-context audit over `217690e..e19f319` (audit-fix batch, i18n,
packaging). 1 HIGH / 3 MED / 9 LOW — all landed, smoke 555/0.

## HIGH

- `demolish_at` diverged from its sibling removers: it cleared workers
  and refunded cost but never recalled `exp_pal` — a pal mid-expedition
  lost its post and stayed `mode="expedition"` + `visible=false` with no
  `exp_end`/`job_site` to ever come home (only save/reload recovered).
  Both `raze_structure` and `net_remove_structure` recall correctly;
  `demolish_at` now mirrors the same tail.

## MED

- `touch_zone_hit` (JOY_R+8 / BTN+8) vs `touch_down` (JOY_R*1.7 / raw
  BTN): taps between the rings either engaged the stick AND swung, or
  ate the LMB without firing the verb. One radius table both directions.
- `log_msg` stores raw text; two call sites skipped `tr()` so the zh
  rows for the welcome/day-1 strings were dead.
- `package.sh` shipped `export/web/.` — dotfiles included — and assumed
  `embed_pck` stays on (zipped only the .exe). Now cleans export dirs,
  zips `index.*` / `*`, VER fallback reachable under pipefail.

## LOW (all landed)

joy_idx cleared on load_game; demolish refusals send the guest a
localized `net_note` via peer-guarded `note_remote`; dodge roll steers
with `touch_vec`; foreign-build test now covers tagless/mismatch/owner
branches separately; dead LMB panel-guard removed; orphan-cargo comment
honest about the host-bag fallback; hello-refusal note already existed
(verified, unchanged).

## Deferred honestly (unchanged)

Unauthenticated tag identity (LAN scope, documented); private-roster
spend unverifiable; guest claims bounded not re-derived; produced
BGM/hero art external; Android SDK absent.
