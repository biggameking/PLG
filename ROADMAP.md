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
- S22 touch layer + placed_by persistence — DONE: on-screen stick (rim-push =
  sprint, multi-touch index-tracked) + ATK/AIM/ROLL/E/ORB/☰ verb buttons;
  `settings["touch"]` auto/on/off resolved in `apply_settings` against
  `DisplayServer.is_touchscreen_available()`; touch taps no longer double-fire
  as emulated LMB strikes; `placed_by` structure ownership now serializes
  (`"by"` key) so guest demolition rights survive save/reload. 9 new smoke
  checks, suite 533–537 / 0 failures ×6.
- S18 MP parity + reactive danger layer — DONE: wild projectiles now bite
  guests (`update_projectiles` checks `net.ghosts`, relayed per-guest);
  third procedural pad `music_danger` swallows the
  mix during raids/gauntlets/phase-2 bosses and lifts when danger ends;
  weather/STAB/freeze smoke assertions rewritten as absolute-delta checks —
  double `int()` truncation at low base damage was producing seeded 1.2-vs-
  1.15 ratio flakes, not a formula regression. Suite 8×0-fail, sim 0, IP CLEAN.
- S18b pad panel nav + tranq flake kill — DONE: in-play panels (inv/build/
  tech/dex/shop/chest) now take the same dpad cursor + A-confirm as the
  shell menus; hold-to-repeat covers them. Tranq-dart smoke assert parked
  the wild herd before firing — the dart bites the FIRST kin it reaches,
  so a wandering packmate made it flake (same isolation class as weather).
- S19 third external pass — DONE: context-free audit of S17–S18 found
  3 HIGH / 5 MED / 4 LOW. Fixed: caught raiders demobilize via
  `release_event_flags` (was stuck danger drone + stranded gauntlet wave +
  sleep lock); `aggro=0` sentinel fully migrated to `aggro_pid` across hit/
  catch-fail/herd-pull/summons/raid-fallback; `sync_pos` now validates
  finite/bounds/step-cap at the source; pause damage rule unified (solo
  pause armours, net session doesn't); guest shots relay via `pal_hit`
  (+tranq payload); `env_sync` carries the danger bit so guests hear the
  drone too; `guest_hit` transfers burn/soak/freeze; weather/STAB/freeze
  smoke tolerances tightened to the real truncation bounds; nav-hold resets
  on mid-hold transitions; ambient pads recover without dead air; one
  pal snapshot per projectile tick; chat brake precedes the host log.
- S19b guest skill parity — DONE: `apply_player_damage` is now the single
  keeper-hit pipeline (absorb → armor → flash → shake → floater → wear →
  death) shared by `hurt_player`, `skill_hit`'s player branch and the new
  `hurt_player_skill`; wild skill shots on guests moved off `guest_hit`
  onto `guest_skill_hit` — host rolls status chance, guest applies the
  same power*0.6 formula against its own armor/absorb locally (real
  parity gain: the guest's plate actually protects it now, and statuses
  only land when damage does). Smoke asserts the guest-side pipeline.
- S19c teleport protocol + claim bound — DONE: the 12-tile `sync_pos`
  cap was silently killing legit guest teleports (waypoint hops and
  death respawn). `_legit_blink` now shapes the allowance: jumps land
  only on travel nodes — kinbox/spawn accept any origin (respawn is
  legal from anywhere), waypoint destinations also require a node
  departure. `pal_hit` claim clamp tightened 2000→500 (~3x the honest
  formula ceiling — the damage formula self-caps near 2*power*mult).
  All remaining `aggro = 0` literal sites paired with `aggro_pid`
  (gauntlet/raid-boss spawns and raid fallback use nearest_body_pid;
  host-only provocations set 0 explicitly). "Guest melee statuses don't
  transfer" deferred item RETIRED — melee weapons carry no status data
  on the host side either; parity already held. Smoke: blink accept/
  reject matrix with planted fixtures, pal_hit clamp bound. Suite
  500 checks / 0 failures.
  Deferred honestly: guest claims damage numbers (host clamps), forged
  build_req plants free unlocked structures (private-bag limit),
  guest armor invisible to host.
- S19d–S19f movement cap + guest skill fire — DONE: sync_pos moved
  from a per-packet cap (240 u/s effective at 20Hz) to a per-ghost
  token bucket — 40 u/s accrual (mounted sprint peaks ~29), 6-tile
  burst covers ~5 dropped packets, blinks drain it; host disconnect
  now resets the mirrored net_danger; wild kin aggroed on a guest
  cast real skills at ghost coordinates (cast_skills accepts Vector2
  targets + a kinds filter — projectile/self only, lunge/burst need a
  body); update_projectiles' freed-caster read reordered behind an
  untyped is_instance_valid guard (killed the "previously freed
  instance" error spam when a shooter died mid-flight).
- S20 shell visual pass — DONE: procedural animated dawn behind the title
  (gradient sky, sun+glow, drifting clouds, sea, island ridge silhouette,
  rising motes — all driven by game.t); wordmark gets gold rule + twin orb
  sigils; menu rows gain cursor ticks + separators; pause header gets the
  gold rule. BGM pads gained a plucked arp voice (per-track step/vol:
  day .75s, night 1.0s, danger .3s) — melodies stay inside the loop seam.
- S20b brand type — DONE: bundled Press Start 2P (OFL, license in
  fonts/OFL.txt) as the HUD face; CJK/icons fall through to the system font
  via FontFile.fallbacks. Title verified by live render, not just headless.
- S20c gameplay juice — DONE: camera shake on hits and boss phase-2
  (decaying pixel offset via Camera2D.offset); screen-space weather FX
  (rain/storm streaks, drought motes) and a pulsing red danger vignette
  while `danger_active` holds. Smoke covers shake kick + decay; FX are
  deterministic game.t lanes, zero allocation.
- S21 authority hardening — DONE: shared `_throttle` token-bucket helper
  keyed on the sender's ghost drives every per-peer rate limit
  (pal_hit 3/s+6 burst, sphere_catch ~1.4s, build/demolish ~1s+,
  harvest/loot/roster shared 8/s+10). pal_hit claims now bounded by the
  formula's own ceiling vs THIS target (atk=500 model, ≤250 landed) and
  sleep claims route through `apply_sleep_claim`'s chain-sleep immunity
  (host tranq uses the same gate). sphere_catch cap_lv clamps to 1..6 —
  the real range (1 + statue≤5), not a plausible-looking 20. demolish refuses anchors outright and any
  structure not stamped `placed_tag = peer_tags[sender]` (net_place stamps
  it — the tag, not the pid, since pids die with the session).
  Disconnect: `_on_peer_disconnected` retracts the field pal then
  `orphan_guest_kin` boxes every owned kin under its tag for rejoin
  (`rebind_owner` reclaims on hello); `_on_server_disconnected` purges
  host replicas (no statue kin left catchable). Foreign partner kin no
  longer graze the host bag/medicine; `assign_worker` lets the host
  evict (unassign) foreign workers but never post them. `sync_pos` now
  validates elevation (finite, clamp −1..8) and home-lane blinks carry a
  3s cooldown. `skill_hit`/`hit` pass `caster.owner_id` so a guest's pal
  provokes the guest. Razing a structure recalls its `exp_pal`. chat is
  per-sender braked + self-echo deduped; hello rejects a tag held by a
  live peer. Smoke +26 checks covering every new gate's accept/reject.
  Deferred honestly: client damage/sleep claims are bounded, not
  re-derived; guest bag/orb spend unverifiable (private rosters);
  build_deny only fires for honest-reachable denials (site contested) —
  forged locked/throttled requests get silence, not a refund.
- S21b re-audit fixes — DONE: second context-free pass over S21 found
  4M+8L, all landed. `orphan_guest_kin` now restores `visible` for
  expedition kin and routes `carry` home via `give_remote` (L1), caps
  its `box.append` at MAX_BOX+32 releasing tagged kin past the lane.
  `sphere_catch` cap_lv clamp is 1..6 (statue-derived, not a plausible
  20). `sync_pos` first fixes must land at spawn or a travel pad — the
  one free blink per ghost is gone. `net_catch` enforces the global
  `box.size()` bound alongside the per-owner lane. `pal_hit` drops 0/0
  claims before they wake tranq'd kin; `peer_pos` relays the clamped z
  and rejects non-finite elev; `kill_pal`'s wild-release clears
  `owner_tag`; `_legit_blink` scans a cached travel-cell set (rebuild on
  count change or 3s TTL); `chat_last` prunes on disconnect. Smoke +4
  (spawn first-fix accept/reject, expedition orphan, zero-claim no-op).
- S22b guest damage ceiling — DONE: `pal_hit`'s claim bound derives from
  the real ceiling (top weapon ×2 transmog + 60-level attack + perks 0.4
  + trinkets 0.24 + partner aura 0.1 + meal) ≈ 775 instead of a flat
  500 that would have clipped legit end-game builds. Smoke asserts the
  derived cap.
- S22c loop seam + hello coverage — DONE: pad `arp_step` quantizes onto
  the 24s loop and the per-loop attack ramp is gone; smoke asserts
  head/tail continuity. `hello` gained a positive-path check
  (fresh tag registers).
- S22d touch verbs complete — DONE: the button cluster gained INV (bag)
  and BLD (build, resets selection) — a touch-only player could not
  reach either panel before. Smoke +2.
- S23 store capsules — DONE: `tools/gen_store.py` ports the title dawn
  scene to PIL, stamps the hero-kin lineup + Press Start 2P wordmark,
  and emits Steam 460x215 / 616x353, itch 630x500, and a 1920x622 hero
  into `store/`. Found + fixed a real bug: ImageDraw writes 4-tuples
  raw onto RGBA (no blend), so the vignette rect blacked the frame —
  now a whole-frame blend. Pixel-verified, not blind-generated.
- S24 audit-fix batch — DONE: third context-free pass (S22–S23 scope)
  found 2H/7M/8L, all landed. `m_join` was in `shell_act` but missing
  from `SHELL_ACTS` — the JOIN row was dead and touch had no join door
  (now also reachable via run_click, smoke exercises the real path).
  Touch sprint billed 12 SP/s while the speed term ignored it — now
  real ×1.7, asserted by displacement. `_process` ran the menu-swap
  sync without the stick release (mid-drift pause latched a phantom
  run) — shared `_release_stick` at both transition sites; load_game
  clears touch state too. Real mice regained LMB: taps are eaten only
  inside virtual-control zones (`touch_zone_hit`), not globally.
  `placed_by` (session pid) became `placed_tag` (keeper tag) — save
  round-trips the tag, demolish requires a hello'd tag match. Minor:
  pause rows extracted to `pause_rows()` (no headless draw in tests),
  `can_dodge()` shared across key/pad/touch, `touch_layout` cached,
  menu button moved out from under the minimap, gen_store shadows
  composite via overlay + kin clamped on-canvas, seam check samples
  the wrap neighborhood, atk-cap band tightened 740..800, `or true`
  tautology removed. Smoke +12 (routing gates, stick park, sprint
  speed, mouse-vs-tap, join row + run_click path).
- S25 release engineering — DONE: `tools/package.sh` exports Windows+Web
  presets and zips versioned artifacts to `dist/` (verified: 115MB exe,
  21-file web bundle). `store/page.md` holds the itch page copy (every
  claim maps to shipped+tested behavior; Android unsigned is disclosed).
  export/ + dist/ gitignored as build output.
- S26 fourth-pass audit fixes — DONE: fresh-context pass found 1H/3M/9L.
  HIGH: `demolish_at` (host X-key) never recalled `exp_pal` — three removal
  paths had diverged and only the local one stranded expedition pals
  invisible forever; recall tail now mirrored. MED: `touch_zone_hit` and
  `touch_down` used different radius tables — taps in the ring gap either
  double-fired or went dead; shared `joy_grab_r`/`btn_r` helpers now.
  Two `log_msg` literals bypassed tr() so zh rows were dead. package.sh
  zipped `export/.` including dotfiles — now cleans first and zips
  `index.*`/`*` exactly. LOW: joy_idx cleared on load_game, dodge roll
  steers with touch_vec, demolish refuses now net_note the guest (via the
  peer-guarded `note_remote`, zh-localized), foreign-build test covers
  all three gate branches (tagless/mismatch/owner), dead LMB panel-guard
  removed, orphan-cargo comment made honest, VER fallback reachable.
- S27 text-panel touch parity — DONE: chat opened only via ENTER, join/chat
  closed only via Enter/Esc — keyless slabs could neither reach nor leave
  either panel. Pause menu gains a peer-gated CHAT row (mirrors JOIN);
  both text panels draw on-screen OK/X buttons routed through the real
  `run_click` path; submit logic extracted to `_chat_submit`/`_join_submit`
  shared by keys and taps. zh.csv += CHAT. Smoke +7 (row gating by live
  peer, send/cancel routes, vkbd drop). Suite 563/0.
  Android blocker narrowed: Homebrew openjdk@21 is present and runnable —
  only the SDK itself is absent (install declined: 6.1GB free disk).
- S28 touch verb coverage + panel trap — DONE: every panel was a one-way
  door on a slab — touch gates hid the verb cluster when a panel was open,
  including the exit (open Inv → never close without Esc). ☰ now becomes
  ✕ while a panel is up (touch_down routes it, draw_touch keeps it
  visible); a ··· row adds the missing world verbs ASG/STN/KSK/RDE/DML/MAP
  (demolish targets the nearest structure within 4.5 tiles — no cursor on
  glass); pause shell gains HOST SESSION (no-peer) and TECH TREE/KINDEX/
  STATUES/GUIDE rows so panels are reachable on pad+touch too, with a
  two-column fallback over 7 rows. zh.csv += 5 rows. Smoke +12 (trap
  close, stray-tap rejection, row zones, verb toggles, demolish fixture,
  pause rows, m_tech route). Suite 575–578 checks, 0 failures ×3.
- S29 list-panel scroll reach — DONE: clipped list tails were unreachable
  on EVERY input class, not just touch — chest/craft/shop broke at the
  panel floor and only dex had a wheel hook. Per-panel scroll offsets +
  shared _scroll_btns tap arrows (shop rides the column gutter), wheel
  dispatch extended to all four panels, guide gains ‹/› tap turners.
  Smoke +7. Suite 579/0.
  S29b: the same clip class covered inv (54-stack cap) and kinbox brows
  (column-spill) — display-index offsets inv_scroll/kin_scroll, same
  _scroll_btns + wheel path. Suite 581–582/0.
  S29c: worst clip of the class — StructureData.TECH holds 70 entries but
  the tech panel drew 36 (2 cols × 18) with the third column painting
  OFF-PANEL as floating text — 34 techs could never be unlocked on any
  device, silently amputating the progression tree. Display-index offset
  + cap-aware clamp + _scroll_btns, same contract as the rest. +3 checks.
  S29d: build bar rows had NO click rects — 1-9 keys were the only picker,
  so touch could open BLD but never select a structure (build fully
  broken on slabs). Rows now run_click "build_pick" toggles (re-tap =
  the RMB-cancel glass never had).
