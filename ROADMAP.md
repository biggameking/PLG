# PLG → Kinbound — staged production plan

Audit baseline (2026-11-10): feature-rich a Palworld-inspired demake, 391-check smoke suite
green, but commercially blocked by IP reuse, placeholder art/audio, no product
shell, no localization/input options, unverified tuning.

## Stage gates — every stage MUST satisfy all of

- `godot --headless --path . -s tools/smoke_test.gd` → `==== N checks, 0 failures ====`
- Leak banner `ObjectDB instances were leaked` ≤ baseline (13).
- `python3 tools/audit_data.py` → `ALL CLEAN`.
- Real behavior change, not doc-only claims; new mechanics get smoke coverage.
- `git commit` + `git push` to origin/main before stage closes.
- After push: a context-free reviewer subagent audits the stage's diff AND the
  workflow; findings → `docs/reviews/` + fixes applied next stage.

## Stages

| # | Name | Deliverable | Acceptance |
|---|------|-------------|------------|
| S1 | IP de-risk | All 116 species renamed (id+name+sprites), pal-lexicon replaced (kin/kinbox/kindex/orbs/lumenite), the Wildmere→Wildmere, Iron Pact→Iron Pact, save-migration for old ids, export metadata updated | `grep -iE "palworld|palapagos|fenjelly|scalbeak|kindex|kin sphere|lumenite"` clean in shipped strings; smoke 0-fail; old save loads via migration |
| S2 | Product shell | Title screen (New/Continue/Quit), Esc pause (Resume/Save/Settings/Quit), settings (master+music+sfx volume, fullscreen), save version field + autosave on quit + quit-confirm | Boot lands on title; Esc pauses sim (single-player); settings persist to user://; F5 save + title continue round-trip |
| S3 | Balance & endgame holes | Legendary species excluded from wild/gacha egg pool (or behind legendary-egg item), raid intensity option (off/normal in settings), boss immunity surfaced in UI pre-throw | New smoke checks: wild egg never yields legendary; peaceful mode spawns no raid |
| S4 | Onboarding | Contextual hints (first-catch aim/throw prompt, first-build ghost hint, hungry warning, raid countdown explainer) + mission tracker stays | New game shows ≤3 concurrent contextual hints; hints retire on action; smoke unaffected |
| S5 | Audio layer | Audio buses (Master/Music/SFX) + volume wired to settings, ambient pad loop (day/night/weather variants), UI click + ~8 more event SFX | Volume sliders audibly change mix (manual check); no crash headless; buses exist in default_bus_layout |
| S6 | Gamepad | InputMap joy bindings for all gameplay actions + UI focus nav on panels | InputMap shows joy events; panels navigable via ui_* actions |

## Out of scope this run (documented, not silently dropped)

Real creature art pass, boss phase design, NPC settlements, localization files,
store page/assets, Steam Deck certification, mobile touch controls, dedicated
net servers.

## Process rules

- One stage at a time; no speculative work outside the stage's checklist.
- Evidence = commands actually run; paste tails, not claims.
- If a check fails twice, stop and re-plan the approach instead of retry loops.
- Lessons from each stage review → appended below AND to AGENTS.md if they are
  durable rules.

## Process lessons ledger

**S1 (external review, `docs/reviews/s1-ip-derisk.md`):** mass-rename needs a
single idempotent script; migrations are written against the serialized save
schema, not runtime dicts; every sweep needs an id-consistency gate + fixture
test + orphan pass. All HIGH/MED findings fixed in the same commit cycle; rules
now live in AGENTS.md → "Rename & sweep rules".

**S2 (external review, `docs/reviews/s2-shell.md`):** `return` in
`_unhandled_input` doesn't own an event — gate every consumer or call
`set_input_as_handled`; `reload_current_scene` isn't teardown (peer/buses/
InputMap survive); `settings.cfg` is untrusted input; tests must restore
`user://` state they dirty. HIGH findings (input leak to gameplay, title-screen
kill, MP session leak into title) fixed and pushed in `2f41030`.

**S3 (external review, `docs/reviews/s3-loop-fixes.md`):** enumerate every
creation site before gating — the legendary leak lived in ~10 spawn paths, not
the egg pool the patch touched; smoke checks must assert invariants against
data, never reuse the production predicate; prefer accessors when data has two
representations. Canonical `acq_pool` gate + breed-combo retargets + raid
warning reset shipped in `2f41030`.

## Stage status

- S1 IP de-risk — DONE (rename + migration + `check_ip.sh` + external review)
- S2 product shell — DONE (title/pause/settings/versioned saves + review fixes)
- S3 loop corrections — DONE (acquirable gate, peaceful raids, review fixes)
- S4 contextual onboarding — DONE (five retiring hints)
- S5 audio layer — DONE (synth SFX bank + day/night pad score + bus mix)
- S6 gamepad layer — IN PROGRESS (stick/dpad/buttons + menu nav)
- S7 boss/endgame spine — NEXT
- S8 numbers sim + platform/readiness — NEXT

## Stage status (update 2)

- S7 boss/endgame — DONE (phase-2 summons+slam, five Pact spires, crown state, HUD tally, save persistence)
- S8 numbers sim — DONE (`tools/sim_balance.gd` — real-formula probe; found+buffed legendary_orb 95→110)
- S9 localization + store shell — NEXT
- S10 hero art/audio depth — NEXT
- S9 localization slice — DONE (en→zh shell+settings+hints via locale/zh.csv; lang setting persisted+coerced)
- S10 audit-fix batch — DONE (S4–S7 external review: 4H/4M/7L fixed; rules 18–24 in AGENTS.md; `docs/reviews/s4-s7-audit.md`)
- S11 hero art/audio depth — DONE (legendary accessory layer: crowns/halos/horns/wings/flame/fins/mask/hood, body-anchored; pad-aware hints)
- S12 species voices — DONE (deterministic 3-syllable cries per species; catch/deploy/phase-2 call sites)
- S13 export identity — DONE (procedural icon set + .ico, version 0.9.0, company Wildmere Works; Windows 110MB + Web exports verified; Android blocked on local SDK build-tools/apksigner)
- S14 element spire slams — DONE (fire→burn, water→soak, grass→poison, dark→sleep, dragon→none; partner-only)
- S15 S8–S12 audit-fix batch — DONE (`docs/reviews/s8-s12-audit.md` — 6H/6M+/L-series all closed; rules 25–34 in AGENTS.md; client-authority gate shipped; 452 checks/0 failures/0 leaks ×5)
- S16 final platform validation + launch sweep — DONE (`docs/reviews/launch-sweep.md`; E2E shell chain in-suite; Windows 115MB + Web re-verified; second external pass closed at `eaa22cb` — interaction-verb + key-binding layers gated, rules 35–36)

**S4–S7 (external review, `docs/reviews/s4-s7-audit.md`):** gates belong at
choke points, not enumerations — the acquirable pool filtered spawn sites
while `resolve_sphere`/`net_catch` trusted the `boss` flag, so phase-2 adds
walked the legendary ban back in. Pad binds stacked onto unaudited `ui_*`
defaults (B dodged AND paused). `spire_tag`/`phase` never entered the save
contract — reloads forged uncompletable campaigns. Worldgen rolled the
session stream while delta sync assumed determinism — clients grew phantom
walls. Menu rects outlived their menu; a negative cursor wrapped to QUIT.
And a bounty predicate matched a display string ("Iron Pact") instead of
canonical ids, so it never fired once. Fixes shipped in `479ae2a`.

**S8–S12 (external review, `docs/reviews/s8-s12-audit.md`):** the recurring
defect class was "a pattern applied to a strict subset of its sites" — KO
scrub covered `party` not `remote_parties`; `panel == ""` covered 2 of ~8
input paths; `>= 0` bounds in 1 of 3 tag whitelists; `user://` backup covered
settings not the save; ghost-proximity was fail-open at every RPC; clients
ran the entire world sim including deterministic worldgen double-spawning
synced drops; and the balance sim's raid section was a tautological mirror.
Fixes shipped in `c775b20`; the authority contract is AGENTS.md rules 25–34.
Deferred honestly: pad rumble, panel-gate coverage now complete but
hold-to-repeat not implemented, Android preset unverified (local SDK lacks
build-tools/apksigner).
- S18 MP parity + reactive danger layer — DONE: wild projectiles now bite
  guests (`update_projectiles` checks `net.ghosts`, `guest_hit` RPC sends
  atk-equivalent damage); third procedural pad `music_danger` swallows the
  mix during raids/gauntlets/phase-2 bosses and lifts when danger ends;
  weather/STAB/freeze smoke assertions rewritten as absolute-delta checks —
  double `int()` truncation at low base damage was producing seeded 1.2-vs-
  1.15 ratio flakes, not a formula regression. Suite 8×0-fail, sim 0, IP CLEAN.
- S18b pad panel nav + tranq flake kill — DONE: in-play panels (inv/build/
  tech/dex/shop/chest) now take the same dpad cursor + A-confirm as the
  shell menus; hold-to-repeat covers them. Tranq-dart smoke assert parked
  the wild herd before firing — the dart bites the FIRST kin it reaches,
  so a wandering packmate made it flake (same isolation class as weather).
