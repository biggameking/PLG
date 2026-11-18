# audit-72 — audit-71 fixes cold review

Context-free re-review of `39e6fc3` (audit-71 remediation). Scope: static bind
snapshot lifetime, `_sync_chunk` mid-total validation, settings/config clash
semantics, package keystore existence checks, harness realism.

## Findings

| id | severity | finding | status |
|---|---|---|---|
| — | — | static `_def_key_evts` survives `reload_current_scene`, mid-chunk `total` forgery rejected, `_close_peer` clears all slots, preset keystore `-f` check, RAW_KEY_LANES single source | **HELD** — all attack paths re-verified clean |
| L-a | LOW | `load_settings` occupied-map was strictly start-state: `{move_down→99, dodge→S}` refused dodge even though move_down vacates S inside the same cfg — stricter than the panel's sequential semantics AND semantically meaningless anyway, since `ConfigFile` serializes dict keys sorted (cfg entry order is not the author's order) | **FIXED** — end-state resolution below |
| L-b | LOW | dead-key upper bound `< 4194592` clipped real keycodes above that ceiling (Godot key space runs past `KEY_SPECIAL` block end) | **FIXED** — bound widened to `< 4194816` |
| L-c | LOW | `package.sh` preset-keystore sed could match an empty `release=""` and the usage line omitted `android-release` | **FIXED** — `\{1,\}` nonempty match + usage updated |

## L-a — the real fix: end-state bind resolution

The sequential "free the lane as you go" patch was wrong twice over:

1. **Order is meaningless.** `ConfigFile` writes dict keys sorted — a cfg
   claiming `{move_down, dodge}` reads back `{dodge, move_down}`. Any
   order-dependent validator interprets noise.
2. **Partial acceptance mints clashes.** Sequential release lets
   `dodge→S` steal a lane while `move_down→99` is what frees it — fine —
   but a *half-refused swap* `{dodge→Q, aim→ui_accept's SPACE}` lets
   dodge keep aim's Q while aim never leaves it. Double-fire.

Replaced with fixed-point resolution over the whole claim set:

- **movers** = cfg entries targeting `REBIND_ACTIONS`. A mover owns
  nothing until its claim lands.
- **owner_of** = live keys of non-movers + `ui_*` + `RAW_KEY_LANES`.
  Permanently occupied — no cfg can claim them.
- Loop: malformed claim (`Escape`, dead keycode, out-of-range,
  non-number) or claim on `owner_of`/`claimed` → fail now, the mover's
  own keys re-own (it never vacated). Claim on a lane owned by a still-
  pending mover → wait a round. Otherwise → resolve, claim the key.
- Deadlock pass: survivors all wait on each other = a legal rotation
  (A→keyB, B→keyA) — resolve simultaneously iff no two share a target.
  Anything that isn't a clean rotation stays refused wholesale, so a
  half-impossible swap leaves no dangling winner.

## Verification

- `==== 1036 checks, 0 failures, 1 skipped ====` (grotto fixture)
- New pins: sequential free-lane, full rotation resolves, half-refused
  swap stays refused, plus the earlier clash/dead-key/Escape pins
- `==== REBIND-LOOP: 0 failures ====` · `==== SAVE-LOOP: 0 failures ====`
- `IP CHECK: CLEAN`
