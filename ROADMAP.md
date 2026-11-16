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
- S17 guest biting + pad polish — DONE (`f988b5b`): wild projectiles bite
  guests through the relay; gamepad layer polished. Ledger entry restored
  post-hoc (audit-47 review found it missing).
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
- S22 touch layer + placed_by persistence — DONE: on-screen stick (rim-push =
  sprint, multi-touch index-tracked) + ATK/AIM/ROLL/E/ORB/☰ verb buttons;
  `settings["touch"]` auto/on/off resolved in `apply_settings` against
  `DisplayServer.is_touchscreen_available()`; touch taps no longer double-fire
  as emulated LMB strikes; `placed_by` structure ownership now serializes
  (`"by"` key) so guest demolition rights survive save/reload (later replaced
  by `placed_tag` at S24 — pids die with the session). 9 new smoke checks,
  suite 533–537 / 0 failures ×6.
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
  S29e: the statues panel never rendered — draw_statues treated the
  viewport SIZE as a position (rows at r.x+16 / r.y+40, off-screen both
  axes), so perks and soul infusion were a dead system since the panel
  shipped. Rebuilt on a proper rr rect; infusion list (party+box, up to
  400+) now clips + scrolls like its siblings.
S30 (5th context-free audit — S27..S29 touch batch, 2H/5M/9L):
  H1 pause-shell rows opened chat/join but their key handlers sat below
  the shell's eat-everything branch — panels drew, typing was dead.
  chat/join/guide hoisted above the shell (guide gets N/G/Esc close +
  ←/→ paging under pause). H2 draw_touch/event gate required
  state=="play" so a pause-opened panel had NO ✕ — a keyless trap.
  Panel escape now covers any panel!="" while verbs stay play-only.
  M1 wheel-zoom exempted only dex — now any panel. M2 rect clicks mark
  set_input_as_handled (no more close-tap leaking to melee). M3
  place_ghost skips taps inside touch zones. M4 the sell rail listed
  guests' boxed kin — sellable_pals() filters owner_id and sell_n now
  counts the real list. M5 more-row drew 19px but hit-tested 33 — one
  MORE_BTN_R const feeds both. L2 CHAT row gates on net_live() not peer
  presence. L4 a mid-drag touch toggle now releases the stick. L5
  scroll buttons only render on overflow. L7 guide footer says Esc.
  Coverage: paused typing/paging/X/joy-guard, handled-flag, all-zone
  containment, row-radius spacing, sellable_pals, run_click for
  m_host/m_dex/m_statues/m_guide, chest scroll. Smoke 603-606/0 x3.
S33 (6th context-free audit — S31..S32 batch, 3H/8M/5L):
  H1 demolish_at anchor guard, narrowed to the LAST anchor — a lone
  outpost razes and a backed-up primary still promotes; the flat draft
  killed both. H2 net_residue: a dropped session's hybrid world can't
  overwrite the real solo save; disconnect purges party/mirrors/unlocked
  + nulls the peer. H3 net_unlocked mirrors host tech — the client's
  build bar intersects it and build_req refunds on an honest deny.
  M: store contents ride snapshot/pack/sync as element 4 (refresh only
  when present — the default-{} first draft zeroed every mirrored
  chest; suite caught it). _build_tap_ok limits the S30 zone guard to
  the X button; roll clears ATK's hit disc; pinch zoom via
  MagnifyGesture; vkbd lifts chat/join bars; guest pause menu drops
  the dead TECH row; dex sort cached; BTN_LABELS shared. L:
  _reset_shell_state shared by load+regenerate, dodge() is the one
  roll verb, touch aim hint + desktop-only preview, build_sel dead
  field gone. Art pass landed with the batch: Ink paper/navy grammar
  (src/style.gd) wired into pause rows + scroll buttons, ink_outline
  pipeline regenerated all sprites, halftone tile. Coverage: planted
  last-anchor refuse, outpost raze, residue refuse, mirror purge,
  client intersect, deny refund, tech-row gate, facing shot, tap
  zones, pinch, x_close, dex cache, wire store. Smoke 631-633/0 x3.
S34 (guest container protocol): chest/feed_box buttons were dead for
  clients — client_locked() swallowed every bulk op. chest_req RPC:
  throttle + witnessed-ghost range (same 6.0 rule as demolition) +
  container whitelist + mimic refuse. wd grants only host-truth items
  (zero fabrication surface); dep whitelists the claimed payload
  through ItemData + stack cap + feed-box food gate, client pays out
  only what chest_took echoes. Vanish mid-op: wd goods roll back into
  the box, dep goods stay shared (the echo is a nicety, the move is
  the truth). Coverage: deposit whitelist (coin/junk refused), store
  arrival, far-ghost refuse, withdraw empties, non-container refuse,
  feed-box food rule. Smoke 637/0 x2.
S35 (guest world-verbs): the interact layer left three verbs dead for
  clients — fishing (a personal rod that only locked because live catches
  are host truth), fertilizer (farm labor), and dungeon mimics (the flag
  stays off the wire on purpose, so a guest's click opened a plain panel
  and the trap never sprang). fish_req rolls host-side at the ghost's
  shore — a live catch spawns host-truth and pal_sync carries it, loot
  echoes through give_remote/note_remote. fert_req validates a farmField
  near the ghost, then fert_done pays the bag on acceptance — never up
  front. mimic_req probes on chest-open: the structure dies on the wire
  and open_mimic(st, opener_pid) marks the asker, not the host. Bonus:
  give_remote/note_remote needed a multiplayer_peer null-guard —
  get_peers() itself errors on offline rigs. Smoke 644/0 x2.
S36 (guest interact parity): swept every remaining interact branch —
  seven verbs dead for guests, two silently divergent. New RPCs all ride
  the witnessed-ghost reach rule: sleep_req (bed turns everyone's clock,
  hostiles veto), work_req (stand dial is shared base policy), shrine_req
  (guest offering turns the sky; bag pays lumenite on shrine_done echo),
  dig_req (fossil one-shot via give_remote), cage_req (freed kin joins the
  asker's owner-tagged slice), board_req/board_done (the posting now rides
  env_sync — guests see the same quest, claim it, pay goods on echo),
  cond_req (fodder filtered to the asker's slice — heart-locked and other
  keepers' kin are never fuel). gacha_pull audited: eggs go to the guest's
  own bag, client-authoritative — already correct. deposit_egg/soul_infuse/
  start_gauntlet stay host-only by design (hatch ownership + roster trust
  bounds documented). Smoke 657-658/0 x2.
S37 (guest incubation): deposit_egg was the last core-loop verb locked —
  guests couldn't hatch. _free_incubator extracted; egg_req whitelists the
  claimed egg kind, claims the nearest free slot by ghost reach, and the
  egg_inc slot carries own_pid so hatch_incubated owner-tags the newborn
  into the depositor's roster slice. egg_done pays the bag on acceptance.
  Known bound: occupied-state (egg_inc) isn't wire-mirrored — a busy
  incubator answers through the honest refusal note. Smoke 659-660/0 x2.
S38 (panel-act sweep): the run_click act table had a second, worse class
  of guest holes — not locked but divergent. buy decremented mirror stock
  (real exploit: struct_sync resync meant infinite purchases); skill_tgl/
  base_in/lead/deploy/box_out/party_in/sell_pal/butcher/fav mutated local
  replicas or no-op'd on the empty client box. All now route through
  box_req (owner-gated remote ops already existed) + box_req grew an
  extra arg slot for toggle_skill's sid. New buy_req/buy_remote/bought:
  host drains real stock, items via give_remote, kin owner-tagged, gold
  paid on echo. perk/base_up found to be a real grief surface — guest
  clicks spent the HOST's stat_pts/base claim; now honestly refused.
  soul_infuse wired as infuse_req (uid must own-check). sell/equip/repair/
  craft audited: client-authoritative bag+player, already correct. Smoke
  663-665/0 x2.
S38b (sleep reach): sleep_req_remote had no bed check — a guest could nap
  remotely for a party-wide heal. _nearest_struct("straw_bed") gate added;
  smoke covers both the no-bed refusal and the honest clock turn.
S38c (board two-phase + reach): claim-and-dip burned everyone's daily
  posting; remote claims needed no board. board_action_remote now holds a
  15s pending slot + notice_board reach gate; board_done pays goods then
  asserts via board_paid; gold+xp arrive on board_pay after settlement.
  Smoke 667/0.
S38d (flake kill): the tranq assertion wasn't seed jitter (40% fail rate) —
  stray projectiles from earlier steps re-hit the parked target inside its
  12-tick window and hit() erases "sleep" on any damage. projectiles.clear()
  before the shot; the drained-world contract is AGENTS rule 66.
S39 (skill-fruit parity + honest dead ends): teach_skill_fruit was the last
  roster verb silently dead for guests — fruit_req teaches the asker's own
  lead (rparty_for + owner check), fruit_done pays the bag on acceptance.
  boss/gauntlet sigils and tech-row clicks now explain themselves to guests
  instead of failing silent (host-authority by design, honest by UX).
S40 (seventh audit sweep — 0C/0H/4M/10L):
  M1 condense_remote had NO gate — remote starring from anywhere. Now
    kin_condenser reach like every other machine verb.
  M2 guest kills/catches never credited the hunt posting and all kill
    loot/xp fell into the host's bag. kill_pal threads provoked_pid (the
    partner-attack sites already carried owner_id — the wire just dropped
    it at the last hop). _kill_loot/_kill_xp route give_remote/xp_gain;
    board_hunt_credit(sp, pid) pays the killer's keeper; net_catch grants
    hunt credit + flat catch xp (catch_xp would feed the host's streak).
  M3 buy_remote/r_sell_pal had no merchant reach — modded clients could
    blind-trade across the island. _ghost_reaches(merchant.pos, 6.0) both.
    Merchant replica sync remains deferred (guests still can't SEE the
    trader — honest-shop surface is a separate feature, not this gate).
  M4 board holds hardened: same-asker re-reads its 15s hold without a
    fresh clock (was silently renewable — one guest could starve the daily
    posting forever); expired holds cool the SAME pid off for 30s; settle
    keeps the holder's claim without freshness decay; an honest
    insufficient-goods reply releases the hold early (board_release).
  L: _free_incubator bound parameterized (20 local UX -> 6 ghost reach);
    egg_inc persists own_tag so a saved guest egg hatches into the right
    slice (pid-by-tag resolve, orphan fallback rebinds on hello);
    box_fingerprint folds star/level (condense/infuse no longer leave a
    15s-stale mirror); env_sync applies bq unconditionally (an empty
    packet is "no posting", not "keep the old world's quest"); board_pay
    xp parity (qn*3, was ~gold); sleep_done heals the sleeper's own player
    (host's hp stays host's); net_catch peer-guard; r_butcher trust note;
    dup-claim + hold-lifecycle + hunt-discrimination smoke coverage.
  Smoke 676-678/0 x4.

S41 (trader mirror — the last invisible NPC):
  Guests now SEE the merchant: env_sync carries {on,x,y} at 2Hz and
  net_merchant_apply builds a display-only Entity mirror (pos fed, till
  stays host-side); despawn rides the same packet's on=false and clears
  the mirrored briefcase. stock_sync broadcasts the shelf on spawn and
  after every accepted buy so all watchers see it thin; state_snapshot/
  state_sync carry merch+stock so a mid-visit joiner walks into the same
  shop. merch_hit routes a guest's beating host-side (hit_bkt throttle,
  3.0 melee reach vs merchant.pos — rifle-length swings are forged),
  clamps dmg <=80, and the Iron Pact squad now spawns at the GUEST's
  ghost with aggro_pid pointing home. hit_merchant(dmg, pid) keeps the
  host path for local play.
  Found while covering the pack: state_snapshot/pal_state_pack shipped
  p.lv for a property named p.level — every real join-with-pals and
  every 2Hz broadcast would have aborted mid-call. Fixed + harness now
  invokes both packs directly (rule 69).
  Smoke 682-686/0 x6, no ERRORs, no leaks.

S42 (eighth audit sweep — 0C/1H/5M/8L, honest-path economy):
  H1 free-buy mint: merchant rows had no affordability gate — a guest
    with 0 gold bought, the bought echo subtracted from an empty stack,
    goods stayed, and sell_pal/r_sell converted them to real coin.
    Buy rows now gate on item_count(gold)>=price (unaffordable renders
    soft + unclickable); infuse gates on >=1 effigy. Forged-client
    underpay remains the documented bag-trust bound.
  M1 add_item spill crashed on clients (spawn_drop early-returns ->
    drops.back() nil) and silently destroyed the overflow — a guest's
    over-cap stack now stays in their own bag.
  M2 craft read unlocked not net_unlocked — guests can now craft
    host-tech recipes at replica stations (build menu already did).
  M3 base workforce cap was shared — a guest's pile starved the keeper
    with no eviction. base_pals_of(pid) makes caps per-owner slices.
  M4 dead-pid egg hatch locked the kin forever (opid>0 skipped the
    tag resolve -> owner_id=dead session). Now: dead pid -> 0 ->
    tag resolves to a LIVE peer or the kin orphans+keeps tag.
  M5 hello was the only unthrottled any_peer verb (O(roster)+fan-out
    per call) — dedicated hello_bkt (1/s, burst 4), ghost-scoped so
    headless/offline calls don't eat a false closed.
  L1 _free_incubator compared distance_squared to a linear bound —
    bound now squared (remote arm is the documented six tiles).
  L2 egg_parents pop stole any queue's oldest parentage — entries now
    carry the parents' owner ids; claims are owner-scoped
    (_claim_egg_parent), legacy rows answer the keeper.
  L3 guests couldn't raze their own BACKUP kinbox — anchor refusal now
    scopes to st.pos == kinbox_pos after the placed_tag check.
  L5 memory_wipe respec was a dead-end verb for guests (perks wiped,
    stat_pts unspendable) — gated like upgrade_perk.
  L6 bag-row kin_egg was client_locked dead — routes egg_req like
    the incubator interact.
  L7 work_req flipped shared work_mode with no rebroadcast — wmode
    rides env_sync; all mirrors converge in a tick.
  Skipped as bound-consistent/negligible: chest_took RTT over-credit,
    pal_hit sleep floor, forged shrine/work flaps (echo-verified).
  Smoke 692-695/0 x4.

## S43 — second eighth-audit landing (wire shapes + mirror lifecycle)
  H1 guest shelf dropped kin rows: stock_sync accepted only `id` rows —
    merchant kin sales were invisible. Rows now parse both shapes with a
    SpeciesData whitelist + lv/n/price clamps; rebuilt dicts, never raw dup.
  H2 guest sell rail was dead UI — sellable_pals() read the host's box.
    Guests now list game.net_box dicts (uid/lv/name/est. price — host
    recomputes the true buyback at r_sell_pal).
  H3 chest deposit could launder forged claims into durable shared storage —
    bounded to 9999 units/request under the existing throttle; the residual
    laundering lane is the documented bag-trust bound (ledger would break
    honest crafted-goods deposits).
  M1 merchant mirror outlived disconnect as an interactable zombie —
    _on_server_disconnected tears it down (apply off + hp/wanted reset).
  M2 buildable_list intersected host tech with the guest's own research —
    a fresh guest saw a starter bar on a developed island. Guests now read
    net_unlocked directly; unlocked also rides env_sync for mid-session tech.
  M3 struct_sync carried id/origin/store only — guests saw chests but no
    captive state, egg timers, fertilizer, expedition countdowns, workers.
    Wire shape is now [id, ox, oy, store, state] with re-anchored times and
    uid→replica crew resolution; mimic and egg_parents stay off by design.
    state_snapshot reuses struct_state_pack (fixes a latent footprint-cell
    origin bug: snapshot keyed footprint cells, not origins).
  L1 host ghost stranded past spawn+12 on clients (first-fix gate policed
    authority packets) — clients accept sync_pos only from pid 1; other
    guests arrive via peer_pos relay only.
  L2 Iron Pact squad loop now breaks at MAX_PALS.
  L3 merch_hit guest reach tightened 3.0→2.5 tiles.
  L4 deploy_to_base failures now note_remote the asking guest.
  L5 env_sync board_quest stripped `pending` (holder pid leaked + stale-open).
  P1 MAX_MERCH_STOCK enforced in generation AND sync.
  P2 smoke banner now prints skipped checks separately (fixture-skip
    pattern surfaced, e.g. "grotto room 2 skipped: terrain…").
  P4 state_snapshot no longer duplicates the struct pack loop.
  Bound-consistent: shrine honest gate already existed; wire-level sender_id
    can't be faked in the harness (merch_hit/pal_hit RPC gates are direct-call
    tested instead); multi-sleeper day-skip asymmetry noted as design;
    hello tag-switch desync is self-inflicted; guest-hit sfx is cosmetic.
  Smoke 700-704/0 x9, 0 ERROR, skip counter live.

## S44 — the crown's payoff: apex gauntlet
  crowned was a flag + a one-time loot dump — the campaign ended in a log
  line. Now tick_gauntlet asks a fourth question when the keeper is crowned:
  wave 4 spawns 3× zone-3 elites (lv46-54) + a true boss (lv56-60, phase-2
  slam). EX clear pays legendary_orb×4, effigy×5, gold×500, ancient_part×6,
  huge_kin_egg×2, gauntlet_sigil×2 (self-sustaining); uncrowned keeps the
  3-wave/standard-purse contract untouched.
  Verified the user's two named fears are already structurally safe:
  hatch_pool() excludes LEGENDARY_DEN + boss + non-acquirable species
  (eggs can't mint legendaries — now asserted in-suite), and every boss
  runs a real phase-2 (pack summon + element shock ring at half hp).
  gauntlet_sigil desc now advertises the apex wave; mission flag
  gauntlet_ex persists through mflags.
  Sim: capture grid/raid curve/species spread all sane (SIM 0 failures).
  Smoke 705/0.

## S45 — Android export unblocked (debug APK builds + signs)
  The named blocker was three separate gaps, none in game code:
  - editor settings pointed android_sdk_path at a nonexistent dir; real SDK
    lives at /opt/homebrew/share/android-commandlinetools (homebrew). Fixed
    + java_sdk_path now points at brewed openjdk@17 (was empty).
  - project.godot lacked textures/vram_compression/import_etc2_astc —
    required for Android. Enabled.
  - export templates for 4.7.2 were already installed under editor_data.
  Result: --export-debug "Android" produces a signed, verified 35MB APK —
  com.kinbound.game v0.9.0, minSdk 24, targetSdk 36, 706 assets inside.
  Release export needs a release keystore (owner decision; debug lane is
  green for device sideload via adb install).

## S46 — ninth-audit landing: boot-lane determinism + pay-first protocol (2H/3M/5L)
  H1 worldgen: _ready now shares regenerate()'s place_pois() lane under the
    world.seed reseed — guests of a fresh-boot host no longer get phantom
    walls (clean-boot probe: identical grotto/structures/pals).
  H2 pay-first ledger (net.pending_pays): bag debits at request time, every
    host refusal path sends pay_rej, echoes settle — disconnect window went
    from mint to payer-loss across chest_dep/egg/buy/infuse/fruit/shrine/fert.
  M: MAX_PEERS 8, POS_PPS packet-rate cap, host-packet bucket exemption.
  L: state_sync raze-and-replace structures, net_live requires CONNECTED,
    chest_ref cleared on drop.
  Smoke 711/0 x4 green. Rules 77-79.

## S47 — store-page truth pass + all-platform export verified
  Windows+Web release exports now produce real artifacts end-to-end:
  dist/kinbound-0.9.0-windows.zip (117MB exe) + kinbound-0.9.0-web.zip
  (38MB wasm + pck + workers). Store copy updated: Android line went from
  "unsigned/unverified" to signed-debug-APK; "five biomes" replaced with
  honest terrain description (4 spawn bands + meadows/stonefields/shore).
  IP check CLEAN (tools/check_ip.sh).

## S48 — guest mounting: the last dead mechanic comes online
  Guests were honestly refused "can't ride a host kin" — now the mount
  lane is host-truth: mount_req → mount_req_remote gates ghost reach,
  roster ownership (rparty), species/body and one-saddle-one-steed; the
  bound kin's pos rides the validated ghost pos in pal_state_pack (all
  watchers converge); mounted_by rides the wire as field 11; replicas
  hide under their rider and sleep their AI; orphan_guest_kin unbinds
  on disconnect. Client try_mount scans own-roster replicas and mount_done
  completes the handoff. Smoke: far/stranger/species/owner gates + toggle.

## S49 — mount lifecycle contract + mature-world join layer (audit 10)
  Tenth context-free audit (1C/2H/3M/6L) all landed. _unbind_mount(p)
  centralizes rider teardown; every live-state exit path calls it:
  kill_pal, r_retract, r_party_to_box, r_base_to_box, deploy_to_base,
  r_butcher, r_sell_pal, orphan_guest_kin, respawn_player. Replicas freed
  by pal_sync/purge_replicas clear player.mount first (the C1 dangling
  ref — freed-instance derefs every frame). mount_req_remote now validates
  before unbinding (a refused swap can't strip the saddle) and every
  refusal echoes mount_done so mount_pending can't wedge the button.
  Host mounts stamp mounted_by=1 — replicas hide for watchers, not just
  the rider. state_snapshot carries world.decor/hp_map (mature worlds no
  longer phantom-wall joiners) and shares pal_state_pack's 12-field rows.
  chest_took refunds claim-accepted gaps; throw_bait is wired (bait_req →
  ghost-anchored lure); board_paid/board_release ride board_bkt (settle
  can't starve behind act spam); _on_connection_failed clears pending
  ledger/mount handshake/chest ref. player.gd _mount_guard() belts every
  mount consumer. Smoke 729-731/0 x3 green.

## S50 — audit-11: pay ledger honesty + mount handshake resilience
  Eleventh context-free audit (2H/1M/5L) all landed. pay() now books
  the ACTUAL debited delta, not the claimed cost — an underfunded
  refund can't mint goods; empty debits book no hold; MAX_PENDING_PAYS
  caps the ledger. buy/infuse call sites gained balance gates (the
  only two verbs whose cost wasn't bag-constructed). mount_req's
  throttle-drop now echoes mount_done(0) so mount_pending can't wedge
  mid-session; the handshake is uid-scoped (a stray echo can't re-arm
  it); _mount_selfheal_check re-asks the unbind when a replica still
  reports us as its rider (2s cooldown). state_sync/pal_sync apply
  mode + mount guards symmetric with purge_replicas. Smoke 736/0.

## S51 — audit-12: silent-refusal echoes + deploy-mount desync
  Twelfth context-free audit (1H/1M/4L): build_req's throttle drop
  silently ate paid materials (0.7/s bucket vs honest wall-rows) —
  every paid verb now echoes its refusal (build_deny, bait_deny).
  deploy_to_base is the only unbind that leaves the replica alive;
  pal_sync now drops the local saddle when the wire says nobody rides
  (or somebody else does). Ledger eviction became refuse-at-cap —
  a booked hold can never be evicted into a same-tag mis-settle.
  respawn skips a duplicate unbind when a handshake is already out
  (toggle can't express unbind-only); to_title uses _close_peer for
  a graceful drop; pal_sync refuses nonpositive uids; infuse_done
  feeds the replica's soul_boost so guest price mirrors converge.
  Smoke 741/0, IP CLEAN.

## S52 — audit-13: armed respawn unbind + ledger-wide paid verbs
  Thirteenth audit (1M/6L): respawn's mount_req was the only unarmed
  sender — a stale pal_sync row could fire the self-heal toggle inside
  the echo window and re-BIND the just-released kin (toggles can't
  express release-only). respawn now arms pending+uid like every
  sender. mount_done splits state 0 (refuse → handshake only, saddle
  stays) from state 2 (release → unbind + instant re-show). build and
  bait moved onto the ledger: deny refunds draw from the recorded
  debit, never the cost table — build_deny/bait_deny deleted for
  build_done/bait_done(ok) settles; throw_bait_remote reports landing
  so a hold never hangs. Smoke 743/0.

## S53 — audit-14: settle verbs can't starve, board idempotent
  Fourteenth audit (2M/8L): board_done deducted goods then sent a
  throttle-able settle — a starved board_paid ate paid goods and a
  re-shown ask double-deducted. Settle verbs no longer throttle
  (board_paid_remote self-guards + first success erases the hold);
  client-side board_paid_out makes re-shown asks no-ops; rpc_id(1)
  became rpc() broadcast — a leaf's only remote IS the host. Respawn
  arm, mount_done guards, _close_peer ledger wipes, and peer-existence
  guards on every refusal echo rounded out the batch. Smoke now drives
  a real CONNECTED loopback for board+respawn coverage. 746/0.

## S54 — audit-15: board_rej frees dead holds + server_relay off
  Fifteenth context-free audit (1M/6L): board_paid_out cleared ONLY on a
  board_pay echo — when the hold died silently (expiry overwrite, board_quest
  dict swap, regen) the client kept its goods-loss flag forever and every
  same-qid ask was swallowed. board_paid now echoes board_rej(qid) so the
  assert flag frees. Bigger catch hiding in a "comments are wrong" finding:
  server_relay defaults true on SceneMultiplayer, so every guest broadcast
  reached all guests — chat printed twice in 3+ player sessions (original +
  host relay). server_relay=false at host() makes leaf-remote true; roster/
  positions still arrive via the host's peer_pos/peer_joined relays.
  board_release lost its bucket too — a starved release squats the ask.
  _close_peer wipes chest_ref; loopback fixture now restores hunger, the
  connect-hook ghost, and plg_net.cfg (rule 30). Smoke 746/0.

## S55 — audit-16: hostile-variant saves can't abort mid-load
  Sixteenth context-free audit, first on the save/migration surface
  (1H/6M/13L): int()/float()/"x"==true abort on non-numeric Variants —
  a forged save kills load_game between world-teardown and rebuild, and
  the next save clobbers the real file. Game._i/_f coerce every numeric
  read (~35 sites) and bools use `is bool` two-stage. Loaded structures
  regain pos+turret (kinbox anchor + tower fire were dead post-load);
  every load list honors its runtime MAX_*; captive/inc/egg shapes
  validate; session leftovers (dirty_decor, statuses, catch_streak,
  mission_t, last_merchant_day) reset on load like regenerate; wire
  hp clamps to the save's ceiling. New hostile-Variant fixture feeds
  Array/Dict payloads through the whole path. Smoke 749/0, 747/0.

## S56 — audit-17: structural aborts can't reach post-teardown code
  Seventeenth audit, reviewing S55 itself (4C/3H/2M/3L): the numeric-
  coercion layer held, but typed-arg/iterator/key-type aborts remained —
  seed into generate(), int keys under split(), raw sp into species_of(),
  has()-gated party_idx. All refuse-or-skip now; migrate's pre-guard loops
  and load's post-teardown loops both take is-Array; boss_respawns rows
  rebuild whitelisted (hostile tails could ghost-node at tick); pending_jobs
  queues only after placement; _norm_pair() shares head+tail validation
  across save inc / wire inc / egg_parents; spawn_net_pal pre-evaluates
  wire casts before gen_pal; MAX_BENCH names the co-op orb bound.
  Smoke 752/0, 749/0 zero-error.

## S57 — audit-18: NaN-class, dict-values and cap-lane gaps
  Eighteenth audit on the S56 surface (1C/3M/3L). meal_buff dict
  VALUES reached int()/float() readers per-frame — rebuilt against
  the six-key whitelist. NaN/INF passed every "is float" gate —
  _i/_f now reject non-finite and _fin() replaces all 18 boundary
  numeric gates (save + wire + settings). remote_parties' row cap
  was bypassed by rebind_owner's raw write while evicted orbs
  stayed on the bench (+5/cycle unbounded) — tags route through
  the eviction lane, evicted orbs box, and _bench_add is the one
  overflow lane all six bench sites take. hatch_incubated gains
  the MAX_PALS/max_base_pals/box caps every other kin path had.
  Fixture asserts all six respawn fields and fires one row live.
  Smoke 750/0, 749/0 zero-error.

## S58 — audit-19: wire-layer coercion parity + roster-uid hygiene
  Nineteenth audit on the S57 surface (1H/3M/4L): the save boundary
  was sealed but the SAME hostile shapes still reached wire handlers —
  raw int()/float() inside world_sync (tod/day/kin-row id/merch pos),
  pal_sync update tails (pos/hp/lv/mounted_by), env_sync board-quest
  and merchant fields, box_sync rows, drop_sync coords, decor_sync
  values. All route through Game._i/_f/_fin now; tod clamps 0-24 so an
  INF can't fast-forward days; level clamps 1-60. Found live while
  fixturing: a size-5 box_sync row aborted on unconditional e[5] —
  gate tails at the highest unguarded index, both rows. Roster lanes:
  _bench_add's box/free overflow now scrubs the stale strip uid
  (r_retract/retract_out), r_box_to_party erases before append like
  its local twin, local box_to_party gates mode=="box", all four
  party/base->box verbs refuse at MAX_BOX before side-effects, the
  catch overflow lanes take MAX_BOX+32 then free clean. hello("")
  binds "_pid%d" instead of the unclaimable empty tag; saved
  remote_parties skip empty keys; meal_buff only loads with a live
  meal_t. Fixture: hostile box/pal/env/drop/decor rows coerce or
  skip without aborting. Smoke 755-757/0 x3, zero-error.

## S59 — audit-20: NaN damage claims + wire echo coercions
  Twentieth audit on the S58 surface (1H/14M/19L). H1 was live:
  pal_hit's clampf passes NaN through — int(NaN) poisons a wild kin's
  hp to ~9e18 (unkillable, uncatchable) or insta-kills bosses, one
  packet guest→host. is_finite() now refuses dmg/sleep claims on
  pal_hit, merch_hit, guest_hit, guest_skill_hit and net_floater.
  Mid-handler aborts sealed: bool(Variant) on wire (state_sync merch,
  env_sync merch), for-in on non-Array structures/kin rows, raw int()
  in stock_sync/chest_grant/chest_took/board_done/chest_req dep —
  all ride Game._i/_fin/is-Array now; negative counts can't mint
  goods (qn/c clamps); chest_grant whitelists ITEMS ids. Bounds moved
  to choke points: MAX_STRUCTURES inside place_free (wire callers
  bypassed the verb caps), MAX_EXTRA_BOXES on the same path,
  spawn_ghost caps at MAX_PEERS, _drop_tex keys whitelist to real
  item ids (forged ids share one texture). Replica integrity:
  spawn_net_pal refuses nid<=0 (untrackable catchable local kin),
  mounted_by clamps >=0, decor bytes clamp to the enum (off-enum
  crashed harvest_cell's literal lookup), hello reserves the _pid
  namespace (fallback rows can't be claimed), party_idx/party dedup
  + cap 5, placed_tag .left(24), weather echo whitelisted,
  soul_boost echo capped at 10. env_sync tod/day — the claim that
  never shipped — now clamps like state_sync. Hostile fixtures drive
  pal_hit/merch_hit/chest_grant/board_done/stock_sync/spawn rows.
  Smoke 761-762/0 x2, zero-error.

## S59b/c — audit-21 (SHIP): residual echo signs + dedup parity
  Twenty-first audit shipped S59 clean (no C/H) with a fast
  follow-up list, all landed: state_sync chest stores take the
  same per-entry _i/0 clamp struct_sync runs (M1); every echo
  amount floors at zero — bought price, infuse cost, board_pay
  gold+xp, got_loot n — and board_done whitelists ITEMS ids so a
  forged ask can't deduct real stacks (M2); saved rparties and
  wire party strips dedup uids and share the 5-slot bound (L1/L2);
  stock_sync item rows whitelist ITEMS (L4); decor snapshot
  clamps a duplicate, not the caller's dict. Smoke 760-761/0.

## S60 — release-candidate gate: packaging integrity
  Found + fixed a real ship-blocker in tools/package.sh: zip ran in
  update mode, so entries deleted between exports (an old
  index.144x144.png.import artifact) survived inside the shipped
  bundle. Zips are now deleted before repacking and index.* is
  shell-expanded. Rebuilt 0.9.0 windows+web candidates from the
  post-S59 tree — 15-file clean web bundle, single-exe windows
  (embedded pck), zero warnings in export logs.

## S60b — audit-22 HOLD closed: release gate findings landed
  Twenty-second audit returned HOLD on artifact/localization/export
  scope (not code): 帕鲁 survived in the zh KINDEX row; tools/*.gd —
  including the legacy-ID save fixture — compiled into every PCK;
  two malformed zh rows flipped en/zh columns; web shipped a fake
  QUIT that freezes the canvas; page copy promised OS keyboard on
  mobile-web (Android-only in reality); package.sh read the version
  from the Android preset field. All fixed, zips rebuilt, PCK greps
  clean (0 tool strings, 0 legacy IDs), SHA256SUMS + build.txt now
  travel with dist/. check_ip.sh covers locale/+store/+CJK terms.

## S60c — audit-22b verify: PASS ×7, one new H closed
  Re-audit confirmed every S60b fix landed (locale, presets, ip
  check, web-quit gates, package metadata, page copy, roadmap) with
  zero regressions — and caught one more H: the web build still
  mounted the whole co-op surface (JOIN/HOST rows, J/K hotkeys)
  while browsers can't host or join ENet, and page.md sold co-op
  without a platform tag. main.gd now skips instantiating the net
  layer on web (every consumer already null-guards game.net);
  page copy reads "Multiplayer (Windows/Android)". Suite 761/0.

## S61 — zh coverage: full UI chrome
  locale/zh.csv grew 54 → 122 rows covering every tr()-routed
  literal: all menu/tab rows (title, pause, settings, kinbox ops,
  party verbs), hints, toasts, day/clock, catch %, incubator/effigy
  strings, guest-refusal lines. Verified: python csv parse shows
  zero missing UI keys; suite 762/0. Remaining surface (S62):
  data-name display (species/items/structures ~268 names render
  raw — names are display-only, never logic keys, so a tr() wrap
  at render sites is safe).

## S62 — zh data-name wiring + item/species coverage
  Every display-name read now passes tr(str(...)): 149 sites across
  spec["name"], ITEMS[..]["name"], and all .get("name") consumers —
  names were verified display-only (logic keys are ids). zh.csv grew
  to 253 rows: 21 core species + all 108 items translated. Deferred
  to S63: 120 structure names, 95 procgen species (proper nouns —
  romanized acceptable for EA), skills/passives names.

## S63 — zh coverage complete: structures/skills/passives/ailments/elements/guide
  zh.csv now 343 rows: +49 structures, +29 skills/passives, +7
  ailments, +9 elements, +13 work labels (dead data but future-
  proof). Ailment and element strings are tr()-wrapped at their
  three render sites. The 8-volume Field Guide ships a full
  PAGES_ZH parallel set; GuideData.pages() picks by locale, so a
  zh player sees the entire manual in Chinese. Procgen species
  names (95) stay romanized — coined proper nouns, defensible
  for EA. Suite 763/0. zh coverage is now effectively complete:
  every user-facing string class localizes.

## S63b — audit-23 verify: SHIP + honesty-gap closures
  Twenty-third audit passed logic-clean (zero tr() into logic
  paths, zero syntax residue, working locale switch) but flagged
  that literal UI sinks sat unwrapped, leaving ~91 csv rows dead.
  Landed the high-traffic sinks: all panel headers, BTN_LABELS
  touch buttons, passive_str, PERK_LABEL, PARTNER_SKILLS names,
  Day/Wt/Stat-points/guide-footer literals, Can't-use concat,
  skill-learn messages. csv: added real ailment ids
  (depressed/sprain/ulcer), XP Gain, 7 partner-skill names; dropped
  the 2 wrong-authored keys and the unspaced — CROWNED dup.
  Suite 761/0. Remaining known-partial: ~95 procgen species names
  stay romanized (coined proper nouns), ~200 log_msg literals and
  pace/stance labels still English — documented EA gap, not a
  defect: tr() keys added later localize without code change.

## S64 — release candidates refreshed + Android debug lane
  Rebuilt win/web zips at ad63d84 (carries zh arc + web co-op
  gating + packaging hardening). Android export verified end-to-end
  through alignment — release signing is the only missing piece
  (owner keystore). --export-debug produces a sideloadable
  debug-signed APK today: dist/kinbound-0.9.0-debug.apk (33M),
  checksummed into SHA256SUMS; package.sh gained an `android`
  lane so all three artifacts come from one command.

## S65 — kin art: every species now renders a real creature
  Parametric rig generator (tools/art/rig_auto.py) derives a Blender
  rig per species from its own data — 13 body archetypes (blob/
  quadruped/bird/ghost/human/serpent/cow/deer/kitty/mouse/monkey/
  boar/hedgehog), palette + parts seeded by id. render_kin.py merges
  rigs_gen.py (authored fenjelly rig keeps priority). All 115
  non-fenjelly species re-rendered through the posterize/ink/halftone
  post chain — flat procedural squares are gone; every kin has a
  silhouette, a face, and its species color. Smoke 761/0 (the crown
  assertion now checks the head zone's opaque pixels, not one magic
  coordinate from the placeholder era).

## S66 — kin art audit fix (external review, HOLD → closed)
  Context-free audit caught: dump read d["body"] instead of
  SpeciesData.body_of() so 15 species rendered the wrong archetype
  (mounts as birds, non-mounts as cows) — fixed; CORE_BODY deleted.
  gen_assets.py kin writer gated behind --kin-legacy (footgun that
  silently reverted the whole roster). 10 legendary accessories
  (crown/halo/mask/horns/crest/fins/back-fan) restored as rig parts;
  hedgehog rig rebuilt (fluff mound no longer buries the face);
  eyes moved proud of head surfaces on every archetype; bird heads
  lifted + face tint; f1 frame now bobs the top half per-rig (was a
  ~1px no-op for 80% of species); player rendered through the same
  pipeline. Smoke grew a per-species sprite check (load + opaque +
  ink floor over all 232 frames) — 762/0. Render dir left git;
  rules 97-100 record the process lessons (reproducible artifacts,
  authoritative accessors, retire old writers, never weaken tests).

## S67 — roster faces: real sprites on every roster surface
  Party strip, kinbox three lanes, sell-back rows, statue infuse
  rows, boss bars, and the dex caught-column all render the species
  sprite (was text glyphs). kin_tex guards ResourceLoader.exists —
  stale mirror sids can't spam load errors. Party rows shed the
  passive string (the [mv] panel already carries it) — no more
  text/button collisions. Smoke 766/0.

## S68 — legends earnable: the den's heir contract
  legendary_orb was a dead item — 10 legend species were combat-only.
  ownable() splits from acquirable() (pool filtering unchanged);
  a killed den warden respawns as a catchable alpha heir from a
  re-rolled LEGENDARY_DEN species — kill or catch re-summons the
  next. Immunity lives in catchable(): legend + not alpha = immune
  (phase adds/sigil raiders can't be sigil-farmed). Load/cage paths
  gate ownable in roster scope only — wild ironpact humans still
  load (the index-drift bug this gate nearly shipped).

## S69 — audit-25 fix batch + crowned guidance
  HUD crown line: SPIRES n/5 + DEN n/10 tracker with warden/heir/
  stirs-eta states. Fixture hardening: lair alpha skips raid-flagged
  alphas + tod pinned to species cycle; nocturnal corridor disarms
  pull-in foes; tranq lane scans the dart's real step; floater
  asserts read .back() (ring-buffer truth).

## S70 — boss telegraphs: Pact Slam is dodgeable, guests eat it
  Phase-2 slam: 5s charge -> rooted 0.8s "IT REARS UP" telegraph ->
  ring lands on players, guest ghosts, and partner kin with the
  spire's element ailment. Snapshot-iterated (kills mid-loop can't
  skip targets). Guest symmetry: guests share the ring damage.

## S71 — signature mechanics: fans, pierces, drains
  Three real kinds: multi (fan volleys), pierce (hitset-scored
  through-shots), drain (damage heals caster). All 95 gen species +
  21 core species learn a lv20 signature from the third element
  pool slot; gen_species.py preserves curated glyphs. .ts sources
  patched in the same commit (provenance rule 101).

## S72 — the Wildmere Accord: the island's last contract
  crowned + all ten legend heirs caught + EX gauntlet sealed once
  -> party_cap() widens the roster 5->6 permanently (banner, horn,
  rumble, guest fanfare). Eleven hardcoded-5 sites unified under
  party_cap(); gauntlet_ex save hole found + fixed (EX flag never
  survived load). Campaign spine (crowned/accord/spire+den tallies)
  rides env_sync + state_snapshot — guests get the crown HUD and
  the sixth slot, join-time strips can't starve the cap. Sim grew
  catch-cost/TTK/kit/element gates. Smoke 790+/0.

## S73 — the cataloger's seal: a full Kindex pays out
  102 ownable species registered -> KINDEX COMPLETE banner + 3 legendary
  orbs. Same ledger discipline as accord: catch_counts re-derives the
  claim, a forged dex_claimed flag is refused. Smoke 798/0.

## S74 — localization closure: the whole lexicon rides one csv
  ~480 keys wrapped across log/floater/draw_string/menu/data surfaces
  (help panel, mission texts, weather/altar, work abbrevs, names in
  every dex/kinbox format line). Wire protocol reworked: note_remote
  ships english key + raw args, receiver tr()s per-arg (a zh host no
  longer broadcasts Chinese to en clients). locale/zh.csv loads at
  RUNTIME via FileAccess (the headless csv_translation importer
  silently produced nothing). zh.csv.import -> importer="keep" so the
  raw bytes pack; --export-pack byte-probe proves it. 95 gen species
  given real zh names; terminology unified on 精灵. Smoke 802/0.

## audit-28 — i18n reaudit
  Wire leaks (pretranslated args, preformatted strings), csv contract
  lint (3 cols, unique msgids, placeholder parity, no lone %), fused-
  row repair, keep-importer export fix, cross-line emit-site sweep.
  Smoke 802/0.

## audit-29 — multiplayer trust-boundary reaudit
  H: keeper tags rode struct_sync broadcast while hello() treated
  possession as proof — disconnect-then-impersonate stole rosters.
  Tags stripped from the wire; hello binds first-write-wins.
  M: guest sleep minted shared days (now is_night-gated); egg
  parentage keyed on pids (now owner_tag); receipt echoes trusted
  wire numbers (now settle against recorded holds + mirrored posting).
  L: hit-flood buckets, ghostless take_drop fail-closed, live-lure
  stomp refusal, NaN guards across every float-arg handler.
  Rules 109-113. Smoke 816/0.

## S75 — first-session hardening (audit-30 fixes)
  C1 soft lock closed: starter cargo is 3 orbs + 4 drift lumenite
  (exactly a kinbox's share); rocks/ore/coal shed a 12% shard so
  lumenite stays renewable. C2 pacing: day 1 clock runs half rate —
  first dusk ~4 min, not ~130s. spawn_wild(true) seeds 3 docile
  zone-0 kin inside the spawn ring at worldgen only. First kinbox
  plants raid_t = DAY_LEN+60 grace. Corpse bags mine-flagged —
  600s decay can't eat them, flag round-trips the save ("m" bool).
  Host straw_bed takes the same is_night gate as guests. NEW GAME
  with a live save arms a red SURE? row before it fires. New hints:
  chop / kinbox cost / guide N / dusk campfire prep; night hint
  rewritten off the phantom torch (it was never an ItemData row).
  Help card auto-sizes (was overflowing at 8 lines); build bar shows
  the full recipe on the selected header + dims short rows.
  Smoke 835/0 — 17 new assertions, all with live values.

## audit-30 — first-15-minutes onboarding reaudit
  Context-free lens on the opening arc: found the C1 lumenite
  soft-lock chain (fossil beds zone-locked, crusher needs kinbox,
  rod needs lumenite, maps downstream) and the C2 two-minute
  daylight crush. Every finding independently verified against
  source before implementation. Keep-list honored: mission rope
  retroactive pay, catch-odds feedback, zone-0 passive nights.
  docs/reviews/audit-30-first-session.md.

## audit-31 — S75 recheck: the small-truth batch
  All nine S75 claims source-verified, no C/H. Landed: F8 arms
  before it loads (overwrite class), place_free kinbox grants the
  same raid grace, MAX_DROPS eviction skips mine-flagged corpse
  packs, opening-ring kin tether to home (meta, transient by
  design), guest bed reach aligned to host, cold hints read the
  real 10-tile warmth radius, hint copy truths (Start→GUIDE,
  weaken-first), footer honors has_save, build bar un-overlapped
  (measured header + name-only rows + zh cost names). Bonus:
  pos_pps wall-clock bucket refresh killed the node-hop flake.
  Rule 115. Smoke 845/0. 93c1122.
## audit-32 — mid-game progression sweep + fixes
  Context-free probe of the kinbox → missions 2-10 → base economy →
  zones → spires → gauntlet → crown → accord arc. One hard dead-end:
  gauntlet_sigil only spawned inside its own reward loop — the trial,
  mission 10, the Accord and the sixth party slot were unreachable.
  Landed: spire kills pay 1 sigil (idempotent), merchant carries a 10%
  sigil listing; gauntlet raiders exempt from the 240s stale sweep and
  tick_gauntlet reconciles left↔live (void on empty, never silent-pay);
  bred_kin_egg split from kin_egg so wild eggs can't drain ranch
  parentage (legacy ranch stores migrate on load); host E empties any
  automated stockpile (guests refused); spire placement gains a third
  door-validated pass and all passes require a walkable same-elev
  approach; spire_pos pings violet on charted minimap cells (spos
  serialized + guardian-derived self-heal); Guide Vol. IX documents
  the late arc. +16 checks. Smoke 858/0 (1 known worldgen skip).
  Sim 0 failures. Rule 116. Shot: /tmp/plg-s76-map.png. 59c74aa.
## audit-32 recheck — context-free findings all landed
  R1 spos wrote Vector2i vs loader's Array coercion → real saves dropped
  every marker (sentinel round-trip now proves the real writer); R3 E-drain
  missed 6 store producers (apiary/fish_trap/orb works/compost/expedition);
  R4 door cell (tx,ty+2) unchecked in relaxed+fallback passes → movement
  predicate on door AND approach, suite asserts the same; empty-wave
  auto-clear at pal cap voided (wave rolls back); env_sync carries the
  spire bitmask so guest maps draw hollow markers; guests refused on
  host-only sigil buys; items.ts 17-entry drift ported back; fixture
  hygiene: real-writer round-trip + snapshot/restore (rules 117).
  Smoke 860/0 (1 known worldgen skip). Sim 0 failures.


### S77 — endgame earnability (audit-33) — SHIPPED
- Critical: `ownable()` now exempts `LEGENDARY_DEN` — knight-bodied heirs
  (nibhand/shadekin) catchable as alpha re-dens, Accord seals at 10/10,
  sixth slot earnable. acquirable/spire_pick/warden-immunity unchanged.
- Incubator demolition refunds the egg; comments honest about parentage
  loss (pedigree dies with the box — deferred full-lineage refund).
- Guide Vol IX gains a post-Accord paragraph (en+zh): re-dens, apex
  trials, catalog/stars/statues as the remaining score.
- Smoke 868/0/0. Rules +118 (curated rosters satisfy their gates).
- S77b verification sweep: full world defers den respawns instead of
  dropping the heir; forged alpha:false legend records can't smuggle an
  immune roamer. Smoke 869/0/0. Commit b79e95e.

### S78 — lineage + legend pacing — SHIPPED
- Incubator demolish/raze/net-demolish now returns the consumed
  parentage row to the nearest ranch ledger (_return_egg_parent) — a
  refunded bred egg redeposits onto the same blood, audit-33 Low closed.
- Legend den re-roll prefers species with no catch yet → the 10-heir
  quest is ≤10 cycles (~15 days) not ~29 (~44 days). Guide updated.
- Smoke 870/0/0, sim 0 failures.

### S78c — cross-platform credibility (audit-34) — SHIPPED
- High closed: pad can open the bag — dpad inv/ride/kin-skill/map, L3
  nearest-structure demolish, R3 field-swap (cycle_field_pal), plus an
  INVENTORY pause row for pad/touch.
- F8→F4 label truth, help overlay gains save/load keys + a pad-only
  control line (using_pad-gated); zh synced.
- Landscape lock (sensor) + PWA orientation, web mobile VRAM
  compression on, fog bake gated on explored_n dirty key.
- 7 new assertions; 878/0/0. Rules +119 (input verbs ship on all layers).

### S79 — economy/perf cold audit (audit-35) — SHIPPED
- High closed: `cell_of` O(structures²) per frame — 11 call sites read
  `pos` (the anchor) directly; helper deleted.
- `tick_production` batched to ~4Hz (dt-linear), `nearest_heat` memoized,
  base_ai reads `job_site.pos`, haul_ai rescans at ~2.5Hz with cached leg.
- Starvation KO-loop broken: revive clamps hunger to 50, starvation KO
  logs "starved out … build a feed box!" (zh synced).
- Economy verified: no dead-end chain; gold inflation + gacha→hatch→sell
  documented as accepted/deferred (bounded mint, needs a save field).
- 5 new assertions; 883/0/0. Audit doc: docs/reviews/audit-35-economy-perf.md.

### S80 — post-Accord gold sink — SHIPPED
- Audit-35's deferred Medium closed: sealed Accord keepers get a standing
  effigy order in every merchant stock (3 @ 160g) — surplus gold now feeds
  soul_infuse (55 effigies maxes one kin), not a lottery line.
- Guide vol IX "after the signature" paragraph documents it (en+zh).
- 2 assertions (pre-accord absence + post-accord presence); 884/0/1skip.

### S81 — live-play evidence pass — SHIPPED
- tools/play_s81.gd drives real verbs end-to-end and photographs each beat
  (13 shots): shell new-game, real tree→wood drop, place_free workbench,
  facing-throw sphere → "Caught Fenjelly Lv4!" → party 1/5, kinbox/guide/
  dex/map/inv/pause panels, campfire night. 0 failures.
- Screenshots caught + fixed: hint/mission text overflowing the right
  screen edge (clipped to column), nearest_heat memo staleness on
  place/raze (structures.size() invalidation).
- Suite: 887/0/0.

### S82 — touch slab & guest co-op parity (audit-36) — SHIPPED
- Guest parity: own-ledger catch_credit RPC unstalls guest kindex/missions
  (world book still counts all catches); owner_id in pal pack lets guests
  recall/manage ONLY their own base rows; pause INVENTORY row routed (was
  dead for every input); raid horn relays to guests; assign_remote answers
  misses; cycle_field_pal refuses replica-orphaning on clients.
- Touch: catch-odds preview ungated with facing-cone target; partner_skill
  fires down the facing line; all 7 keyboard-phrased hints got touch
  alternates; guide page scrolls (guide_scroll + range indicator).
- Correctness: nearest_heat memo keyed on structure generation — same-size
  raze+build swaps no longer serve stale distances (fixed a real flake
  class seen in dusk/night hint tests).
- 8 new assertions; 893/0/1skip; S81 live-play 0 failures; guide+kinbox
  PNGs verified. Audit doc: docs/reviews/audit-36-touch-guest.md.

### S83 — economy-flow audit (audit-37) — SHIPPED
- Closed two positive-EV mints by arithmetic, not vibes: gacha pull
  (30→45 const + lv1 sell base 40→20 → EV 35.2 < cost) and the
  merchant cake→ranch→bred-egg loop (cake 15-fallback → price 40).
- mega_orb priced 45 (was unpriced 15-fallback); sleep now wakes kin at
  hunger 60 instead of zeroing the food economy; merchant murders pay
  drop/deaths with a persistent `mdeaths` save field.
- Accord effigy sink uncapped (3→99 per visit) — the deepest
  gold→power conversion the island offers is real, not time-gated.
- 7 new assertions; 902/0/1skip. Audit doc: docs/reviews/audit-37-economy-flow.md.
- Deferred: client bag-trust chest mint (LAN co-op threat model).

### S84 — economy closure pass (audit-37 deferred) — SHIPPED
- `sell_to_merchant` refuses `price<=0` — the 1g pity floor across 63
  unpriced items is gone (orbs/sigils/effigy/gatherables are pure sinks).
- `tools/sim_economy.gd` — best-of-branch lane enumerator: every stock
  line, egg hatch, cake mint, craft recipe, merchant-kin buyback and board
  good audited against the data tables. 43 checks, 0 failures. Finding:
  zero fully-priced recipes exist — market-only crafting can't mint.
- Recheck fixes folded in: guest sell sticker mirrors base-20 formula
  (lockstep assertion), kin_gacha wired through `net.pay` + `gacha_req`/
  `gacha_done` with host-side reach+roll, `merchant_deaths` division
  hardened.
- Co-op storage lane audited and verified already-defended (reach +
  throttle + whitelist + caps + gap refund); documented, no change.
- 903/0/0; SIM 0; SIM-ECO 0.

### S85 — save integrity lens (audit-38) — VERIFIED CLEAN
- Line-by-line walk of `load_game` + `Migrate.save_dict`: every field class
  already carries door checks, whitelists, clamps, derived-flag re-derivation
  and bounded collections. Zero must-fix findings — the S-series hardening
  holds. Info notes: unbounded `items` counts and ledger forgery are solo
  self-cheat, out of model.
- Process lesson banked: background audit subagents truncate final reports —
  foreground or file-output for audit lenses.

### S86 — kin AI behavior lens (audit-39) — SHIPPED
- Expedition KO no longer deletes the gatherer as wild loot (High); the post
  relinks its berth on return so jobs survive trips and saves; haulers
  wander+warn under no-capacity and drop honestly at the 90s unreachable
  bound; assign paths empty the paw; KO clears berserk_t; load honors the
  workers≤4 crew cap.
- Three per-frame scans (find_foe/bed/dummy) memoized at 0.4s with
  `_struct_gen` invalidation — same pattern as nearest_heat.
- 6 new assertions; 911/0/1skip; SIM 0; SIM-ECO 0. Audit doc:
  docs/reviews/audit-39-kin-ai.md.

### S87 — boss/endgame mechanics lens (audit-40) — SHIPPED
- HIGH: saved hp was clamped against the pre-bonus max_hp BEFORE
  apply_bonuses() — every flagged kin (alpha/boss/star/lucky/soul) silently
  lost its multiplier share of hp on reload; an 8x guardian relogged at
  1/8 health. Clamp now lands after bonuses; missing field heals full.
- take_dps shares the 50% phase gate — DoT can't skip enter_phase_two.
- Raider sweep extracted to tick_raider_sweep() and now retires any wild
  raider when no trial lives — a mid-gauntlet save can no longer strand a
  permanent uncatchable boss (or add).
- danger_active requires engagement — a leashed phase-2 boss is dormant,
  not a forever-drone (phase itself persists; re-engaging resumes it).
- MAX_PALS enforced in raid spawn loops + the raid horn; untagged guardians
  record their spire via an 8-cell home fallback; raid_t/rt0 clamp on load;
  crowned re-derives from spires_done; den respawns dedup by sid+anchor;
  phase-2 adds carry raid/raid_t0 so the sweep retires them.
- 11 new assertions + sweep fixture updated to the live-trial contract.
  922/0/0; SIM 0. Audit doc: docs/reviews/audit-40-boss-endgame.md.

### S88 — player lifecycle & survival lens (audit-41) — SHIPPED
- MED: soul_boost now rides pal_state_pack[13] → spawn[12]; guest statue
  panels quote off the real investment (receipt-cap had frozen the stale
  under-charge permanently).
- MED: perks clamp 0-5 on load — the grant cap binds the second consumer.
- MED: wear_by_id banks durability per item id across unequips — the
  re-equip free-repair loop is dead; serialized "wearmap" with whitelist.
- LOW: take_drop refuses mine bags on the wire (guests can't loot corpse
  packs); corpse scatter routes through nearest_free (no wall-stranded
  tombstones); the MAX_DROPS backstop refuses at full-mine saturation
  instead of eating a grave; kinbox anchor promotion unified into
  _kinbox_anchor_gone for all three removal paths.
- INFO: player hp floor 1 on load; hunger polarity hazard documented.
- 10 new assertions; 932/0/2skip(seed-conditional). Audit doc:
  docs/reviews/audit-41-player-lifecycle.md.

### S89 — world generation & POI semantics lens (audit-42) — SHIPPED
- MED: poi_reach() — seeded flood-fill from spawn through the real movement
  predicate (elevation steps). All campaign POIs gate on it: lair/grotto/den
  centres, spire door approaches on strict, relaxed AND last-resort paths.
  A coherent door on a cliff-locked plateau can no longer wall the run.
- MED: empty species pools can't abort the campaign — lair pool computed once
  (zone-3 → zone-2 fallback), the loop skips, the den/grotto/spire/nest/
  waypoint tail still runs. pick_wild_species("")→""; all callers skip;
  summon_raid refuses on an empty zone-3 pool (sigil kept).
- LOW: pool checks moved BEFORE side-effect writes — empty pools no longer
  leave sealed grottos or orphaned torch rings; cage captives check the pick.
- LOW: blocked_swim(x,y,x,y) was a same-cell no-op — new world.swim_open()
  (water + no decor + no solid structure) in spawn_wild and migration.
- LOW: spawn-cell clearing re-runs after the berry/ore pass (decor + hp).
- LOW: spire rock rings skip water/structure cells on all three paths.
- LOW: load_game clamps off-enum decor bytes (byte 99 → NONE), matching the
  net snapshot path's contract.
- 9 new assertions incl. forged-decor and live-spire reachability sweeps;
  942/0/1skip. Audit doc: docs/reviews/audit-42-worldgen-poi.md.

### S90 — combat spatial integrity lens (audit-43) — SHIPPED
- HIGH: World.los_clear(a,b) — shared segment-march (~8 samples/cell):
  OOB, decor, solid structures and unramped elevation steps break the
  line; endpoint cells exempt (a wall is the between, not the bodies'
  own cells). Every damaging verb now honours it: player melee (+merchant
  swing), all five kin bite lanes, pact_slam per victim, burst/nova per
  victim, lunge post-dash recheck, bespoke partner actives (mark reach +
  pal-side LoS + per-victim LoS, blind marks return false), Dream Chaser.
- HIGH: wire claims respect the same wall — pal_hit ghost→target segment,
  net_catch orb claims, sync_pos refuses claims inside blocked() cells
  (water exempt for swimmers); nearest_free gained a deployer anchor so
  send_out/r_send_out/dig_check can't blind-drop into a sealed ring.
- MED: tick_spheres(dt) — orbs die on decor/solid/OOB/uphill cells like
  any projectile (no more lobbing over a sealed ring); update_projectiles
  marches the travelled segment so fast bolts can't tunnel 1-cell walls;
  walkable spike floors don't eat shots.
- Regression repair lessons folded back: endpoint-exempt LoS semantics;
  poi_reach() is walk ∪ swim_open (a barefoot swimmer crosses a strait —
  gear-gated moves stay excluded); fixtures must prove the lane clear
  BEFORE the rock and keep the target alive through the positive control.
- 952-955 checks / 0 failures across four consecutive seeded runs.
  Audit doc: docs/reviews/audit-43-combat-spatial-integrity.md.

### S91 — localization completeness lens (audit-44) — SHIPPED
- Verdict on plumbing: correct by design — single zh.csv locale source,
  persisted setting + live re-render, key+raw-args wire protocol, parallel
  guide pages, font fallback chain.
- HIGH×7 + MED×12 fixed — the whole defect class was arg-localization:
  format strings translated but the nouns interpolated into them (structure/
  skill/item/perk/tech/species names, ids, howl fragments) leaked English
  into zh. PERK_LABEL moved to Game (one source for log + panel).
- LOW: OK/joiner/pager/Lv-rows keyed; tr_args invariant pinned.
- 4 guard lints now hold the class: literal-tr-key ⊆ CSV coverage, dead-key
  (8 stale rows pruned), zh≠en prose, guide page parity.
- Deferred: bundled CJK font for export targets (desktop fallback correct).
- 958/0/0. Audit doc: docs/reviews/audit-44-localization.md.

### S92 — export credibility + perf-under-cap (audit-45) — SHIPPED
- HIGH: docs/+prototype/ purged from all 3 preset exclude_filters (was
  shipping banned-lexicon notes + third-party screenshots + TS source in
  every PCK); bundled subset fonts (FusionPixel 192KB CJK + DejaVu 21KB
  symbols) end the web/Android tofu — loaded via load_dynamic_font, licenses
  ship in fonts/; tick_repairs dict-dedupe (~600k compares/frame killed).
- MED: terrain repaint only on vis/terrain_gen change + prebaked variant
  LUT; HUD 4Hz memo for boss/den scans + tr() formats + trim loops; pal_sync
  per-packet net_id map; struct_state_pack dict dedupe; spring-heal memo;
  partner AI staggered 4Hz rescan (stance re-gates per frame); raider sweep
  0.5Hz; wild recount 2Hz; perf_probe now fails on >4x-baseline budgets.
- Config: explicit SDK floors (24/35), web thread_support off, console
  wrapper off, config/version+description, Android backup on, desktop
  touch=on LMB→virtual-finger routing.
- Verified-correct inventory covers renderer/input/caps/authority/audio.
- 958-961/0. Audit doc: docs/reviews/audit-45-export-perf.md.

### S93 — residual launch-blocker sweep (audit-46) — SHIPPED
- HIGH: ten tech nodes were purchasable no-ops — orb/gun/launcher ladder
  (incl. legendary_orb capstone) declared gates on dead item-row keys while
  recipes ran un-gated; recipe_tech() resolves rec-or-item tech in craft()
  + panel, with refuse/craft assertions at a real workbench.
- MED: guest craft panel filtered starter unlocked → now uses net_unlocked
  like craft(); gacha price aligned (desc/guide/code all 45g).
- LOW: dex habitat shows den/egg provenance for non-zoned species.
- Verified-correct: all missions/hints/protocol/consistency/gauntlet/dex.
- 962/0/0. Audit doc: docs/reviews/audit-46-residual.md.

### S94 — shipped-artifact truth — SHIPPED
- Web export was unbuildable: vram_texture_compression variants failed
  validation with an empty error list; disabled (right for pixel art too),
  16M→12M. tools/art/src/.gdignore ends Blender-scan noise; PWA COI
  contradiction resolved, PWA off.
- Rebuilt windows+web at HEAD (prior dist was 7 commits stale); verified
  PCK exclusion (0 docs/tools hits), booted the web build in a live
  browser preview.
- Doc: docs/reviews/audit-47-artifact-truth.md.
- S94b/c: inline `#` comment had silently deadened the whole [rendering]
  section (parser swallows the next header) — rendering_method, texture
  filter and ETC2 flag were all moot until now. Android debug APK builds.
  Three seed-flaky smoke fixtures hardened; 6x consecutive green.

### S95 — cold process review of the campaign (audit-48) — SHIPPED
- Context-free review of S1–S94 (reflog archaeology, ledger, rules, tools):
  defects were closed as instances, so gate classes were re-litigated —
  sync_pos ×5, pal_hit bound ×3, demolish ×6, phantom walls ×4, ~12 stages
  of guest-dead-verbs. Verified-clean verdicts were later falsified.
- Landed: sim_economy mirrors→production statics (rule 28), ROADMAP
  dedup/order/S17 restored, check() persistent handle, 12 dead tools
  archived, gate block registers perf/leak/package/net probes.
- S95b: act-routing census — every emitted act must reach run_click's
  routing (the guest-verb class is now a red build, not a memo); slam
  ghost same-point anchor kills the last known flake. 5x green.
- Doc: docs/reviews/audit-48-process-review.md.

### S96 — real-socket multiplayer + leak soak — SHIPPED
- First live host+client session: ENet loopback, join asserts host ghost,
  world seed, kin spawn, day sync (4/0); host log shows peer seen, then
  clean disconnect lifecycle (ghost erase + r_retract + orphan_guest_kin +
  peer_tags all exercised live).
- leak_probe 3-round soak (spawn/kill, drop/collect, build/raze,
  save/load): 3794→3804 objects, delta 10 — inside documented jitter.
- Known-benign noted: one put_packet stderr line from the post-disconnect
  broadcast race (ghost pruned a frame after ENet drops the peer).
- Doc: docs/reviews/audit-49-live-net.md.
- S96b: de-flaked the seed-lottery checks — one degenerate seed cascaded
  6 failures (unreachable zone-3 emptied lairs/den/spires; a walled
  pocket broke catch/bow/LoS fixtures). All retry-first or synthesized:
  placement re-rolls, relocates, catchable()-gated targets, baseline
  counts, +2 elev synthesis. 4x green; skips down to grotto room-2.
- c295271: audit_data.py registered in the gate block.

### S97 — art weak-spot pass — SHIPPED
- HANDOFF's two surviving look complaints fixed at the generator:
  every eyes() radius +30-40% (human 0.06->0.085, serpent 0.078->0.105,
  blob 0.085->0.115; player matched) and f1 idle amplitude doubled
  (head_dy 0.04->0.08, fluff_dy 0.06->0.10, ear_drop 0.3->0.45).
- rigs_gen.py regenerated clean; 115 rig species + player re-rendered
  through the Blender->post chain; smoke 967/0/0 after reimport —
  ink/accessory pixel pins still green. IP CHECK: CLEAN.
- QA evidence: docs/reviews/s97-contact.png (6 archetypes, f0/f1 rows).
- Remaining weak spot: primitive-part look itself — the mesh-source
  migration (render_src_asset.py path) is the next and biggest jump.

### audit-50 — cold process review of S96–S97 — LANDED
- Context-free review: 18 findings. Real defects found: leak_probe
  clobbered the binary savegame (byte-backup now, matching smoke);
  net_host couldn't observe the teardown it claimed (now samples
  rparty/tags at ghost 1->0 — fresh transcript shows rparty=1 tags=0);
  player f1 amplitude missed the bump; net_join silent-skip closed;
  fixture hygiene (raze not dict-erase, job_site scrub, pocket relocate);
  3 one-off tools archived; ledger gap closed. Doc: audit-50-cold-review.md.

### S98 — licensed-mesh migration — SHIPPED (bae8121 / 522b320 / c3a318a / 2b1804a)
- Owner's top complaint (ellipsoid stacks) addressed: species render via
  CC0 Quaternius .blend meshes through render_src_asset.py — real
  armature-animated anatomy, not primitive rigs.
- S98: 8 hand-tuned species (Eagle/Wolf/Cat/Piranha/Cow/Pig/Horse/Dog +
  fenjelly Sheep). Armature-object scale does nothing to modifier output —
  scale is baked into bone+vert data (transform_apply → data.transform).
- S98b: mesh_map_gen.py → mesh_cfg_gen.py batch mapping by body archetype
  (mat_map multi-material recolor, head_bone naming, action+frames);
  58 species rendered zero-fail; accessory species stayed primitive
  (identity marks > coverage count).
- S98c audit-51 hardening: batch_mesh.sh gained --python-exit-code +
  post step (was reporting crashes as ok); ACCESSORY derives from
  rig_auto; pack License.txt files in-tree. Doc: audit-51-mesh-art.md.

### S99 — mesh expansion to 108/116 — SHIPPED (1b0c130)
- Two more CC0 packs close the last source-less bodies: cute_monsters
  (Ghost→ghost, Alien_Tall→human, Yeti→monkey, Cactus→hedgehog) and
  monsters_basic (Slime→blob, no_eyes). Skeleton/Cyclops/Demon probed
  and rejected — detached-bone/same-head silhouettes.
- normalize() rebuilt: iterative evaluated-geometry residual baking
  (mesh verts + armature bones, ≤10 passes), child locations untouched,
  action location F-curves scaled EVERY pass via _loc_fcurves()
  (Blender 4.x + 5.x channelbag layouts) — fixing Cat-class
  pose-dominated rigs that diverged when scaled once at the end.
- Eye placement: z-clamped to evaluated bounds; near-vertical head
  bones fall back to a stable -Y facing vector.
- human/monkey rendered at rot_z=35 — chibi-pack heads hide the arms
  front-on. Bird rot_z=90 shows the eagle's wing silhouette.
- audit-52 (context-free, NEEDS-FIX→all fixed): batch post-exit-code +
  non-zero exit, per-species WARN surfacing, normalize unconverged WARN,
  multi-mesh guard, EEVEE_NEXT, probe_* PCK leftovers deleted,
  PROVENANCE drift corrected.
- Evidence committed: docs/reviews/s99-sheet108.png (all 108 mesh
  species), s99-ingame.png, audit-52-mesh-expansion.md.
- Gates: smoke 968-971/0 across 3 runs (grotto room-2 skip gone too),
  audit_data ALL CLEAN, check_ip CLEAN.
- Remaining: 8 accessory species still primitive until a mesh accessory
  layer exists; unused Bat/Dragon/Cyclops/Demon kept for future bodies.

### S100 — accessory layer → 116/116 mesh coverage — SHIPPED (d5f83e0)
- render_src_asset.add_accessory(): primitive marks (crown/halo/horns/
  crest/fins/mask/wings) bone-parented to the armature head bone —
  they ride Idle animation, matching the legacy route's placement.
- Anchoring that survived three rework rounds: head_anchor() shared
  face/fwd/lateral basis; head_group_top() takes the skull top from
  vertices weighted to the head bone (silhouette max fails on raised
  bird wings, bone tail lands at the muzzle on quadrupeds);
  real_head_bone() weight-votes the cfg bone and remaps unweighted
  control/IK bones (Ghost Head→Body, Slime→Head3, Eagle→Bone.004).
- Action + f0 settled BEFORE bone-parenting — offsets computed at rest
  get dragged by the pose delta (wolf horns ended up under the chin).
- crown/halo/horns span fwd-z so pure side-view rigs still read the
  mark; accent colour value-floored so dark species don't swallow it.
- Full 116 re-render; batch 107 ok/0 failed; smoke 972/0/1skip;
  audit ALL CLEAN; IP CLEAN. Evidence: docs/reviews/s100-sheet116.png,
  s100-accessories.png. Zero primitive species remain.

### S100b — audit-53 fixes (cold review NEEDS-FIX → shipped)
- Cold audit (context-free subagent) found 6 MED + 7 LOW against the
  accessory layer — all fixed: sphere dims now in (lat,fwd,z) basis,
  hw measurement needs z-band AND xy window, silhouette-top fallback
  WARNs, humanoid -Y fallback carries rig yaw, head-bone vote is
  distance-weighted + margined, _loc_fcurves dedupes by as_pointer
  (Blender 4.4/4.5 double-scale trap), post_kin refuses blank renders.
- Eyes/noses clamp to head_group_span (the head cluster's own z-band) —
  Wolf's Bone.003 tail reports z=-0.53 under Idle f0; bone-space bands
  bury parts, geometry-space bands don't.
- batch_mesh.sh covers all 116 (hand CFGs resolved from # blend
  comments); mktemp -d scratch; PROVENANCE corrected.
- Doc: docs/reviews/audit-53-accessory-anchor.md.

### S101 — player migration (last primitive unit → source mesh)
- Player rendered via Alien_Tall.blend (CC0): zone_mats splits the single
  material by bind-z bands into trousers/jacket/skin; `hat` accessory
  anchors brim+crown at the silhouette top (Alien's 'Head' vgroup covers
  the face only — silhouette top IS the crown for this rig).
- `strip_islands` removes baked face islands by region (upper-front
  small islands = the 4 eyeballs); arms and mouth socket survive — the
  socket sits below the eyes and reads as the mouth/beard at 80px.
- `eye_abs_z` escape hatch when vgroup bands leave the visual face
  unreachable (Alien: Head≤0.87, Head3≥1.14, face mid ~0.98).
- zone_mats must materials.clear() before appending — slot index drift
  was the first-live-render bug (colors shifted one zone).
- player joins batch list via hand-CFG regex; smoke sprite sweep now
  covers "player" (body+ink). Smoke 969/0/1skip, audit ALL CLEAN.
- Consumers unchanged: player.gd, ghost.gd, merchant portraits all load
  the same player_f{0,1}.png paths.
- Cold audit (audit-54, context-free) → NEEDS-FIX closed: a sed bulk
  replace had flipped 3 species' head_bone to a nonexistent "Head2"
  (eyeless next render, uncatchable by ink); hat anchor moved off the
  global silhouette top; face-band interior ink pin added for player;
  strip_islands thresholds now bind-z fractions with per-island logs +
  strip_expect; zone band gaps snap+WARN; eye_abs_z guards + shares the
  nose anchor; puffs fallback material. Smoke 971/0/1skip.

## S102 — 环境美术迁移（Ultimate Nature Pack，7/7 decor → mesh）

- 世界装饰从平涂泪滴/菱形占位图全部迁到 Quaternius Ultimate Nature
  Pack（CC0）真实网格渲染：松树层冠、白桦圆冠、浆果灌丛、三色岩、
  苔藓树桩。`render_decor.py` + `post_decor.py` 新管线；输出尺寸与旧
  图一致 → `src/main.gd` 装饰池零改动，收获/资源语义不变。
- 实机证据 `docs/reviews/s102-world.png`；smoke 新增全 decor
  存在/不透明/墨描边/非全出血断言（974/0/1skip，audit ALL CLEAN，
  IP CLEAN）。

## S103 — 地砖迁移（16 地面格 → 程序几何渲染）

- tiles.png 的 16 个地面格从平涂菱形迁到 Blender 程序几何（草叶/花/
  波环/卵石/土块/田垄），dimetric 30°/45° 相机严格投影 2:1 菱形；
  无墨描边防网格线；wall/stair/marker 格保留程序画（崖面对比）。
- `render_tile.py`/`post_tile.py`/`build_tiles.py` 新管线；
  `gen_assets atlas()` 加 `--tiles-legacy` 门（audit-55 课的应用）。
- smoke 加 atlas 地面格钉；实机证据 `docs/reviews/s103-terrain.png`；
  smoke 971/0/1skip。

## S104 — 崖面迁移（wall_sx/sy/corner → 立方体渲染）

- 崖壁三格从平涂多边形迁到 1×1×H 立方体 dimetric 渲染+面区抽取，
  保留墨线顶边/淡紫 rim/层理线的可读性标记；stair/marker 仍程序画。
- `render_wall.py`/`post_wall.py`；build_tiles 接入渲染墙面；
  实机证据 `docs/reviews/s104-cliffs.png`；smoke 971/0/1skip。

## S105a — 结构迁移批次1（12 高可见结构 → 程序几何渲染）

- 结构 sprite 是底锚竖直图（`place_free`/`build` 共用同一贴图路径），
  约 50 种。批次1 迁最高可见的 12 种：kinbox/campfire/workbench/
  well/torch/waypoint/chest/feed_box/kin_bed/wooden_wall/
  watch_tower/notice_board。
- `render_structure.py`：逐 id 程序建场景（cyl/cube/cone/ico/prism
  构件库），kin 同 rig + decor 同 upright 3/4 机位单帧；
  `post_structure.py` 复用 post_kin 链，输出尺寸逐字节对齐旧图
  → 放置/锚定/光照语义零代码改动。
- `gen_assets.py` 结构段加 `--struct-legacy` 门 + migrated 白名单
  （未迁 id 仍走旧路，批次推进时逐批移除）。
- smoke 新钉：12 结构 dims+body+ink+顶带（974/0/0skip）。
- 实机证据 `docs/reviews/s105-structures.png` /
  `s105-structures-night.png`（火光/塔灯光晕在位）。
- 剩余 ~38 种结构仍平涂——S105b/c 续迁。

## S105b — 结构迁移批次2（12 生产机器 → 程序几何渲染）

- furnace/generator/crusher/mill/incubator/ore_mine/logging_site/
  stone_pit/gathering_site/spikes/cooler/kin_condenser 全部实几何化。
- 真坑修复：`transform_apply(scale=True)` 默认连 location/rotation 一起
  烘——对象原点归零，后续 rotation_euler 绕世界原点甩飞（mill 风翼
  散开即此）。改 `transform_apply(location=False, rotation=False,
  scale=True)`；批次1 因无 cube+rotation 组合未踩中。
- 实机证据 `docs/reviews/s105b-structures.png`；smoke 钉扩到 24。
- 剩余 ~26 种结构仍平涂——S105c 续迁（农场/防御/杂项）。

## S105c — 结构迁移批次3（14 农场/防御/杂项 → 程序几何渲染）

- berry_farm/wheat_farm/ranch/straw_bed/hot_spring/fish_trap/
  snare_trap/kin_cage/guard_post/training_hall/sparring_ring/
  training_dummy/war_banner/monitoring_stand 全部实几何化。
- 实机证据 `docs/reviews/s105c-structures.png`（38 结构基地全景）；
  smoke 钉扩到 38。
- 剩余 ~12 种（pharmacy/oil_extractor/sphere_factory×2/compost_bin/
  apiary/weather_shrine/kin_gacha/fossil_bed/spyglass/lightning_rod/
  expedition_post）——S105d 收官批。

## S105d — 结构迁移收官批（12 机器/POI → 程序几何渲染，50/50 完成）

- pharmacy/oil_extractor/sphere_factory/sphere_factory_2/compost_bin/
  apiary/weather_shrine/kin_gacha/fossil_bed/spyglass/lightning_rod/
  expedition_post —— 结构面全部实几何化，gen_assets 结构段除
  --struct-legacy 外不再产出任何平涂图。
- 实机证据 `docs/reviews/s105d-structures.png`（50 结构全景）；
  smoke 钉覆盖全部 50 种（dims+body+ink+顶带）。
- 至此游戏可见面全部 mesh/几何化：生物 116+player、装饰 7、
  地砖 16、崖面 3、结构 50。

## S106 — 建造栏图标+翻页+ghost sprite（修真可达性缺陷）

- **真缺陷修复**：build bar 只画 `mini(9, lst.size())` 且无分页——
  解锁 >9 个结构后第 10+ 项**永远够不到**（50 结构游戏里的实际
  blocker）。新增 `build_scroll` 页偏移：滚轮/◀▶ 按 9 翻页，1-9 键
  寻址页内槽位，build_pick arg 改绝对索引（跨页一致），build_pg
  翻页时按菜单规则作废 build_sel。
- 槽位加结构 sprite 图标（_struct_tex 懒缓存，misses 也有界）+
  买不起红色 tint。
- ghost 预览从纯菱形升级为叠放真结构 sprite（绿/红 tint 表可达性，
  锚定数学与 place_structure 同源）。
- smoke 新钉：解锁 >9 → build_pg 翻页 → 第 10 项可选中；
  struct_dims 覆盖全 STRUCTURES id（audit-58 LOW-7）。
- 实机证据 `docs/reviews/s106-build-bar.png` / `-page2.png`；
  978/0/0skip。

## S106b — audit-59 修复 + 联机实机证据（首次真实双人截图）

- **audit-59 冷审 NEEDS-FIX → 10 项全修**（`docs/reviews/audit-59-build-bar.md`）：
  ghost sprite 锚点错半高（center-anchor 误当 top-left，预览比真实落点低
  52-83px）；分页尾页非对齐窗 + 计数器撒谎 → 页边界吸附；wheel 门漏 build；
  smoke 翻页门数错列表（改 `buildable_list()` 且失败即红）；`build_sel_sid`
  钉选中 sid 防 net_unlocked 重排偷换；ghost 循环去每帧分配。
- **联机真缺陷链**（制作双人截图时挖出）：
  - `main.gd` 建 net 节点不设 name → 自动名 @Node@N 两端漂移 →
    **所有 RPC 路径无效被静默丢弃**（headless 探针靠节点序巧合相等才过）。
    修 `net.name = "Net"`。
  - pal/drop/struct_sync 全量名册单不可靠包 → 45kin=6.2KB/220kin≈30KB
    超 MTU 碎片化丢包。改 `_send_chunked` 按 `var_to_bytes` 字节预算
    （1100B/包）+ idx/total 重组 + 伪造守卫，`_close_peer` 清半批。
  - shot/net_host 状态文件 bind 失败照写 → `is_host` 校验失败即退出。
- **首次联机视觉证据**（`docs/reviews/s106b-net-*.png`）：guest 视角见
  host ghost 停出生点 + "Synced world seed" 日志；host 视角 guest ghost
  精确跟随 +5,+3 位移（screen=64,3648 vs player=0,3520）。零 RPC 错误、
  零 MTU 警告。反作弊验证：传送阻挡格被 host 正确拒绝。
- smoke **979/0/0skip** · audit_data ALL CLEAN · IP CLEAN。

## S107b — 图标面收尾：chest + 修理行（audit-60 模式延伸）

- `draw_chest` 物品行 + `draw_craft` 武器/护甲 REPAIR 行补图标（含装备
  自身图标+afford dim）。至此**全部物品消费面**（inv/craft 配方/修理/
  shop 买卖/chest）图标化完毕；tech 行刻意纯文本（非物品）。
- 新证据 `docs/reviews/s107-items-chest.png`（12 行全 kind+relic）、
  `s107-items-craft.png` 更新（双 REPAIR 行入镜，fixture 磨损武器+护甲）。
- smoke 984/0/1skip。

## S107 — 物品 kind 图标：137 物品从纯文本到剪影+色调（audit-60 PASS）

- **新管线** `render_item.py`（12 个 kind 剪影：11 种 + relic 兜 7 个无
  kind 特殊品）→ `post_item.py`（24×24 cel+ink，四边裁剪检测）。
  weapon/ammo/armor 三轮视觉返修（细线剑→立剑、镐状箭→箭、糊盾→椭圆盾）。
- **HUD 集成**：`item_icon(iid)` kind 归一化懒缓存（白名单外→relic，构造
  上限 12 键）+ `_item_tint` iid 色缓存（上限=ITEMS.size()，消逐帧 Color
  解析）+ `draw_item_icon(iid,pos,size,a)` 支持 alpha dim。
  接入 draw_inv / draw_craft / draw_shop 买·卖四行，kin 商品行刻意无图标。
- **audit-60 冷审 PASS**（`docs/reviews/audit-60-item-icons.md`）——2 MED
  + 7 LOW 全修：kind 漂移洞（数据 kind⊆ITEM_KINDS 数据钉，新 kind 不再
  静默骑 relic）；+17/+18px 图标偏移吃文本预算（left() 截断收紧）；未购
  得/售空行图标 dim 至 0.45α；relic 身份钉改纹理对象比较；post 补底边
  检测；render/post argv 守卫。
- **视觉证据**（`docs/reviews/s107-items-*.png`）：inv 17 行图标+物品色
  tint / craft 20 行配方剪影 / shop 买·卖双列图标+kin 行正确留白，
  全部经真实 draw 路径渲染。
- smoke **984/0/1skip**（4 新钉：全 id 解析·kind⊆白名单·7 特殊品=relic
  纹理·缓存构造界）· git 范围干净。
