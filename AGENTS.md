# PLG — Dev Rules

Godot 4.7.2, GDScript, headless-verified. Run the smoke suite before committing:

```
/Volumes/17333023680/Godot/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/smoke_test.gd
# tail of output: "==== N checks, F failures, S skipped ====" must be 0 failures.

# offline probes (run when touching their lane):
#   tools/sim_balance.gd  — capture/raid/xp formulas: "SIM: 0 failures"
#   tools/sim_economy.gd  — every gold→transform→gold lane audited: "SIM-ECO: 0 failures"
#   tools/perf_probe.gd   — frame-budget gates incl. stress scenes: exits non-zero on budget breach
#   tools/leak_probe.gd   — node lifetime: ObjectDB leak census after load cycles
#   tools/package.sh [windows|web|android|all] — real exports into dist/ (build.txt ties to HEAD)
#   net_host.gd + net_join.gd — REAL two-process loopback session: run host
#     first (writes tools/net_host_state.txt), then join; verdict in net_join_out.txt
# One-off stage scripts live in tools/archive/ — not part of the gate.
```

## Memory-safety contract (hard rules — the game must never crash or leak)

1. **Every runtime collection is bounded.** If a list accepts appends during
   play, it must expire entries (TTL/age), evict the oldest, or refuse at a
   `MAX_*` const in `src/game.gd`. Current caps: drops 400, projectiles 200,
   floaters 80, pals 220, box 400, egg parentage 32, merchant stock 64.
   New collections need a new `MAX_*` next to them — no exceptions.
2. **No parentless pals, ever.** Box pals live under `Game.box_holder`
   (process-disabled) via `box_pal(p)` / `unbox_pal(p)` — never `remove_child`
   a pal into the void. Any `Node` removed from the tree must be `free()`d or
   re-parented immediately; `queue_free()` only on nodes still inside the tree.
3. **Textures/images are cached, not rebuilt.** `_drop_tex`, `_light_tex`,
   `map_tex` follow create-once-reuse-forever. Never allocate `Image`/
   `ImageTexture` in `_process`/`_physics_process`.
4. **No per-frame allocations in hot paths.** Reuse scratch dicts/arrays or
   keep entries bounded; `duplicate()` for mutation-during-iteration is the
   established pattern.
5. **Untrusted input is coerced at the boundary.** Save data and net RPCs must
   pass type/shape/range checks before touching typed vars (see `load_game`).
   Bracket-access on foreign dicts is a crash — use `.get()`.
6. **AI cost scales with `pals.size()`** — `MAX_PALS` is also a CPU guard.
7. **New PNGs must be imported before headless runs.** After
   `tools/gen_assets.py` or the Blender kin pipeline creates a file, run
   `godot --headless --path . --import` once — `load()` silently returns null
   on unimported resources, and a null texture mid-`load_game` aborts the
   rebuild. Every `spr.texture` consumer guards with the chest.png fallback.
   Kin sprites are Blender-only: `tools/art/rig_auto.py` → `rigs_gen.py`
   (do not hand-edit), `blender -b -P tools/art/render_kin.py -- <sid>`,
   `python3 tools/art/post_kin.py <sid>`. `gen_assets.py` no longer writes
   `assets/kin/` unless `--kin-legacy` is passed. Far wild pals already
   tick at ~8Hz; keep new per-pal work behind the same accumulation pattern.
8. After changes: smoke test must report 0 failures, and the exit banner must
   not grow new `ObjectDB instances were leaked` counts vs. baseline
   (observed jitter is ~8-17 — treat >13 as a flag, re-run once).

## Rename & sweep rules (learned the hard way in S1)

1. **Mass renames live in ONE idempotent script** covering ids, display names,
   filenames, `.import` internals (source_file + dest_files), `.uid` files,
   `class_name`s, and docs. Never hand-patch a generated rename — fix the name
   table and re-run the whole pipeline including a final `--import`.
2. **Save migrations are written against the serialized schema** — enumerate
   every key `save_game()` writes before touching `Migrate`, not the runtime
   dict shapes they came from.
3. **Display-string replacements must be word-bounded and case-classed**
   (`PAL`/`Pal`/`pal`), and every remaining hit gets human review.
4. **Every rename ships a migration gate:** map values must resolve against
   current data (species/items/structures), plus a smoke fixture that feeds a
   legacy-shaped dict through `Migrate.save_dict`. `tools/check_ip.sh` is the
   committed "old lexicon is gone" check.
5. **Post-sweep orphan pass:** stale `.uid`, `.import` dest paths, export
   metadata, generator sources (`prototype/`, `tools/gen_*.py`) — a rename that
   the generators would revert on next run is not done.
6. New mechanics need checks that would fail on the old behavior, and checks
   must isolate their fixtures (see the `apex.raid = false` hardening — tests
   that depend on random world spawns or leaked raid state flake).

## Design invariants (hard rules — from the S2/S3 external reviews)

9. **Enumerate before you gate.** Before restricting a species/loot/spawn
   category, list every creation site first (`zone_pool`, `pick_wild_species`,
   `SPECIES.keys`, `BREED_COMBOS`, `gen_pal(`, `kin.gd").new`). Each site gets
   the filter or a written reason — put the list in the commit message.
10. **One canonical pool per invariant.** `acquirable()` / `acq_pool()` is the
    only "a species enters mortal pools" gate (no legends, no humans) — never
    per-site ad-hoc filters. The roster gate is `ownable()` (no humans) and
    the two catch chokes answer to `catchable()` (ownable + legends need
    `alpha` — only den heirs are ball-able). Intentional exceptions (dens,
    grotto, sigil raids) pick `LEGENDARY_DEN` deliberately and say so.
11. **Smoke checks assert invariants against DATA, not the implementation.**
    Never reuse the production predicate in its own test — tautological checks
    certify nothing (`spec.get("body")` vs `body_of()` was the S3 proof).
12. **Filter fields must exist.** Before `.get("field")` in a filter, confirm
    the key in the data; when two representations exist (inline `body` vs the
    `BODY` table) the filter must cover both — use the accessor.
13. **Shell input contract.** Every `_unhandled_input` consumer gates on
    `game.state` at entry, or the owner calls `set_input_as_handled()` —
    `return` alone does not own the event. New consumers get a smoke check
    that shell input can't reach gameplay.
14. **`reload_current_scene()` is not teardown.** MultiplayerAPI peers,
    AudioServer buses and InputMap survive it — `to_title` closes the peer
    first, and a client never `save_game()`s replica state into the solo file.
15. **`settings.cfg` is untrusted input** — coerce per key in `load_settings`
    (rule 5's boundary applies to every file we read, not just the savegame).
16. **Toggles own their transitions.** A switch that freezes a countdown
    defines what happens to armed state on re-enable (`raid_warned`/`theme`
    reset); pins share a const with the threshold they dodge (`RAID_WARN_T`).
17. **Tests leave no dirty state.** Anything written to `user://` in a smoke
    run gets backed up and restored (see the settings round-trip fixture).
18. **Ownable kin pass through one gate.** Every path that can put a kin in
    party/box/bench — catch, summon, load, shop, cage, boss-phase adds —
    answers to `ownable()`/`catchable()`. `resolve_sphere`/`net_catch` reject
    non-ownable targets regardless of `boss`, and legends additionally need
    `alpha` (den heirs only — phase adds/sigil spares stay immune); spawn
    pools filter at the source AND the catch layer refuses what slipped
    through. **The load gate is roster-scoped, not species-scoped** —
    `load_game` applies `ownable()` only to non-`wild` modes. Wild Iron Pact
    mobs legitimately live in `pals` and ride the save like any other world
    fauna; dropping them mid-list shifts every `party_idx`/`rparties` index
    after it (the S68 roster round-trip break).
19. **Pad binds may not collide with `ui_*` defaults.** `bind_gamepad` strips
    joypad events from every action it touches before adding its own — B can
    never dodge AND pause, and a scene reload can't stack duplicates.
20. **New kin fields are a save contract.** A gameplay-meaningful `Kin`
    member lands in `pals_data` write + load coercion + `pal_state_pack` (if
    net-visible), or carries a "transient by design" comment. Campaign tags
    (`spire_tag`, `phase`) get a save→load→kill smoke round-trip.
21. **Worldgen is seed-deterministic.** `regenerate()` reseeds the placement
    stream from `world.seed`; a joining client lands the same POIs/decor as
    the host. Delta-only sync assumes deterministic state — don't mix a
    session rng into placement.
22. **Fix the pattern, not the instance.** A gate added for one call site
    (`acquirable`, `net_id > 0`, `state` checks) gets grepped across every
    other site of the same verb before the fix is closed; replicas never run
    `hit()`/`kill_pal()` locally — authority lives at the choke point.
23. **Menu state resets on transitions.** `menu_sel`/`click_rects` belong to
    exactly one `state|panel`; a transition voids them before the next event
    dispatches. Cursors never wrap to a negative index.
24. **No dead predicates.** Match canonical ids (`ironpact_*`), never display
    or theme strings ("Iron Pact"). Every predicate added gets at least one
    smoke check that fires it positively.

## Multiplayer authority contract (from the S8–S12 audit)

25. **Every load/teardown clears every runtime collection, or names the
    exception in a checklist at the function head** (`pals`, `box`, `bench`,
    `party`, `remote_parties`, `drops`, `net_drops`, `drops_wanted`,
    `spheres_flying`, `projectiles`, `structures`, `boss_respawns`,
    `spires_done`, `crowned`, `lure`, `treasure`, `focus_target`, merchant,
    `gauntlet`, `hint_seen`, `explored`). A new collection adds its reset at
    `load_game` AND `regenerate` in the same PR — `bench` proved the
    checklist matters.
26. **Proximity-gated RPCs fail closed.** `ghosts.get(pid)` returning null
    refuses the op (`gp == null or dist > R`), never skips the check — one
    helper shape, applied at every request handler (`take_drop`,
    `net_harvest`, `net_place`, `net_demolish`, `assign_req`, `pal_hit`).
27. **Client-claimed values are untrusted input.** Handlers re-derive or
    bound anything the client asserts (behind flags, item ownership, tech
    unlocks, hit damage, positions). `cap_lv`'s clamp is the shape — extend
    the shape.
28. **A probe/sim gate must call production code or it gates nothing.**
    Un-callable formulas get extracted to a shared static
    (`Combat.raid_day_bonus(day)`) used by both sides. A gate over a local
    copy is a tautology; "keep in lockstep" comments don't count.
29. **Kill/box/destroy paths scrub every roster the uid can appear in** —
    `party`, every `remote_parties` row, `bench`, `pals`,
    `job_site.workers`. Before closing, grep `\.erase\(.*uid` across every
    verb of the same class.
30. **Tests leave no dirty state — all of `user://`, not just settings.cfg.**
    `savegame.plg` gets backup/restore too; no real sockets left bound
    (loopback-free stub or close post-check); a finally-position cleanup runs
    even on mid-run abort.
31. **Serialized/whitelisted string ids carry the full three-part check** —
    `begins_with(prefix)` + `is_valid_int` + `0 <= int(rest) < size` —
    copied whole to every site (save loader, wire validator, predicate
    reader). `int()` accepts garbage→0 and negatives. One validator
    (`spire_tag_ok`) for all readers.
32. **tr() slices ship a coverage inventory.** A locale PR lists every
    user-visible emit site (`log_msg`, `floater`, `draw_string` literal,
    `menu_row` label, data strings) and wraps it or records the exclusion in
    the CSV header/docs. A CSV key with no producing `tr()` call is dead —
    grep `tr("` vs keys as the lint. CSV fields containing commas must be
    quoted — `\,` escapes are literal, not escapes.
33. **Deterministic worldgen produces each synced entity through exactly one
    channel on clients.** If a replica system carries it (drops→`net_drops`,
    structures→`struct_sync`, kin→`pal_sync`), the client's `regenerate` must
    not also spawn a local copy — or name the deliberate exception like
    `tick_migration` did, in the commit.
34. **Every wiring check ships its negative.** Slam outside phase 2, catch
    on boss/legend, box op on a non-owned uid, harvest with no ghost, strike
    during a panel, load with non-empty bench — the positive assertion
    without its gate-check certifies half the contract.
35. **A gate class has layers — grep them all.** Gating frame-loop ticks but
    not interaction verbs, or gating verbs but not key bindings, ships the
    same hole twice. Closing a class means enumerating its LAYERS: per-frame
    ticks, E-verb/item-cost interactions, save/load verbs, net-control keys,
    and RPC handlers. `client_locked()` is the interaction-layer gate; key
    handlers refuse mid-session (`host_net`/`join_net`/`load_save`); save
    verbs refuse on client AND on host-with-guests.
36. **A "named exception" needs its consequences reconciled, not just a
    comment.** `tick_migration` was documented as the local-fauna exception
    while its downstream effects (real AI, real loot, roster capacity,
    catchability, uid-space collision) were never owned. If an exception
    survives review, enumerate every consumer of the thing it produces.
37. **Event flags must be released at capture.** `raid`/`raid_t0`/`gauntlet`
    mark a *temporary invader*. Every catch/convert path must demobilize
    (see `release_event_flags`): a caught raider that keeps its flag re-arms
    `danger_active`, blocks sleep forever, and strands the gauntlet counter.
38. **Validate untrusted input at the source, not at each consumer.**
    `sync_pos` wrote the one coordinate every proximity gate trusted — the
    gates were "fail closed" against a fully spoofable value. Sanitize the
    write once (finite/bounds/step-cap) and downstream checks become honest.
39. **Sentinel migrations are a grep-able defect class.** `aggro = 0` meant
    "the host keeper" at ~12 sites; migrating only the proximity scan left
    every provoke-path (hit, catch-fail, herd-pull, raid fallback) aiming
    guest aggression at the host. When a sentinel gains a second meaning,
    sweep every literal site of the old one in the same change.
40. **Symmetric damage paths share one state rule.** Melee was paused-
    immune while projectiles weren't. If two hit paths disagree about a
    gate (`state`, dodge, god-mode), they share one predicate or the
    difference is a documented asymmetry.
41. **Shape the allowance, don't drop the cap.** A 12-tile step cap on
    `sync_pos` killed legit teleports too (waypoint hops, death respawn).
    The fix is a destination-shape rule — big jumps may only land on
    sanctioned travel nodes, and outbound-only nodes require a node
    departure — never "trust the client when it says teleport". Claim
    clamps get the same treatment: bound `pal_hit` claims at ~3x the
    honest formula ceiling (500), not "whatever fits in a float".
42. **Test fixtures must not depend on world state a later load can
    erase.** The save-coercion tests reload with `structures: {}`, so a
    blink test that hunted "an existing waypoint" found nothing. Plant
    the structures the test needs (or compute provably-empty spots) —
    a check that reads ambient world content flakes on suite order.
43. **Bound untrusted claims against the model, not a magic number.** A
    flat 500 clamp on `pal_hit` still let a client deal ~10x real damage.
    The honest bound is the formula's own ceiling: run Combat.damage at
    max plausible atk vs the actual target's def, add small slack, cap
    there. Claims you can't re-derive get model bounds, not wishes.
44. **Ring-buffered signals need content asserts, not size deltas.**
    `messages` (6) and `floaters` (80) evict at cap — `size() - before`
    is 0 even when a call fires. Assert on the tail's content instead.
    Bucket-gated RPCs in tests: `_throttle` lives on the ghost's meta —
    set_meta a fresh token between sequential probes or the second call
    starves at the rate gate, not the logic gate.
45. **Ghost-gated handlers fail closed when the ghost is missing.**
    Every sender-proximity/sender-bucket check resolves through
    `ghosts.get(pid)` — a null ghost means refuse, and headless tests
    must `spawn_ghost(sender_pid)` before calling the RPC, not just
    set `is_host`.
46. **Transfer paths normalize every per-kin flag, not just `mode`.**
    `orphan_guest_kin` boxed expedition pals still `visible=false` with
    cargo attached — every sibling box path clears `carry`/`job_site`.
    When a kin changes containers, scrub the full flag list
    (`visible`, `carry`, `job_site`, `owner_*`) or it resurfaces as an
    invisible worker / stasis cargo / rebindable wild.
47. **Clamp bounds derive from the model's real max — verify the number.**
    `cap_lv` was "fixed" to 20 while the reachable range is 1..6
    (`capture_level = 1 + statue≤5`). When a bound is meant to match
    honest play, compute it from the data (perk caps, item tables,
    level max) — a plausible-looking constant IS the exploit.
48. **Session-surviving identity is the tag, not the pid.** Structures
    stamped `placed_by = pid` kept raze rights only until the peer
    rejoined with a new id — the persistence was hollow. Anything that
    must outlive the connection (roster, build ownership) keys on
    `peer_tags[pid]`; pids are for live-session checks only.
49. **Test the routing layer, not the callee.** `m_join` lived in
    `shell_act` but was never registered in `SHELL_ACTS` — the click
    path was dead while `hudn.shell_act("m_join")` stayed green. Verb
    tests must drive `run_click` / `_unhandled_input`, and any new
    shell act needs its registry entry in the same edit.
50. **A new input verb is three contracts: flag, resource, effect.**
    Touch sprint set `touch_sprint` and billed 12 SP/s while the speed
    term never read it — pure stamina tax at 1.0×. When a verb drains
    a resource, assert the payoff it buys, not just the flag and the
    cost.
51. **Transition handlers must live in every transition site.**
    `_unhandled_input` released the joystick on menu swaps, but
    `_process` performs the same `_menu_key` sync one frame earlier —
    the release never ran and mid-drift pauses latched a phantom run.
    Any state/panel transition cleanup belongs in a shared helper
    (`_release_stick`) called from BOTH sites.
52. **Sibling mutation paths must share the recall tail.** Three structure
    removers existed — `demolish_at`, `raze_structure`, `net_remove_structure`
    — and only the local one forgot `exp_pal` recall, stranding expedition
    pals invisible forever. When a new removal/mutation path is added, grep
    the sibling list and mirror the FULL tail (workers, exp_pal, store,
    chest_ref, anchors) — or extract it.
53. **Zone gates and their consumers share ONE radius table.** `touch_zone_hit`
    used JOY_R+8/BTN+8 while `touch_down` claimed at JOY_R*1.7/raw-BTN — taps
    in the gap either double-fired or went dead both directions. Any paired
    hit-test (gate + handler, bounds check + consumer) derives from one
    helper (`joy_grab_r`/`btn_r`), never two literals.
54. **Strings that cross a boundary get tr() at the call site.** `log_msg`
    stores raw text — two zh.csv rows sat dead because callers passed
    literals. Every log/note/message string that reaches a user goes through
    tr() where it's emitted, with a zh row in the same commit.
55. **Every modal needs a same-class exit.** Touch gates hid the whole verb
    cluster when `game.panel != ""` — including the only way to close it.
    Panels became one-way doors on a slab (Inv opened, Esc-less devices
    could never leave). Any input-mode gate that swaps the control set must
    keep a visible escape affordance in the NEW set (☰→✕ here), and smoke
    must exercise "open then close" through the real event path.
56. **Menu rows are a bounded collection too.** Pause rows grew past the
    648px floor: 11 rows × 40px can't stack under a title. Row collections
    that vary by state need a fit rule — the pause shell falls back to two
    columns over 7 rows. New rows must be counted against the worst-case
    viewport, not the dev screen.
57. **A list that can outgrow its panel must scroll.** Six panels clipped
    at the floor (chest/craft/shop/inv/kinbox/statues) and the tech tree
    silently amputated 34 of 70 unlocks — dead content on EVERY input
    class. Any list drawn from an unbounded collection gets a per-panel
    `*_scroll` offset, `_panel_scroll` wheel arm, and `_scroll_btns` tap
    arrows when it overflows — drawn via display index (`di = i - scroll`),
    never by mutating the source index.
58. **draw_* receives viewport SIZE, not a panel rect.** `draw_statues`
    painted every row off-screen for its entire existence (perks/infusion
    were a dead system) because it treated `r` as a Rect2. First statement
    of every panel draw is `var rr := Rect2(...)` built from the size —
    and a smoke check or eyeball must prove rows land inside it.
59. **A feature's input gate must cover every state that can reach it.**
    Pause-shell rows opened chat/join/guide, but their key handlers sat
    below the shell's eat-everything return — typing worked only in
    "play". When a panel gains a new entry point, audit its handlers
    against every state that can reach it and hoist the handler above
    the earliest consumer it must outrank.
60. **Handled clicks are a contract, not a courtesy.** Any event a panel
    consumes must call `set_input_as_handled()` — otherwise the same
    press falls through to melee/throw/ghost-placement below. Assert the
    flag in smoke, not just the side effect.
61. **Presence is not liveness.** `multiplayer_peer != null` stays true
    on a dropped socket — gate UI on a `net_live()`-style check that
    reads `get_connection_status()`, never on pointer presence.
62. **A sync field absent on the wire is not an empty value.** `struct_sync`
    refreshed `cur["store"] = e[3] if present else {}` — every pack built
    without the field wiped every mirrored chest (11 lair chests emptied
    mid-suite). When a wire payload can carry a field optionally, gate the
    write on presence (`e.size() > 3`), never on a defaulted read.
63. **Guard the irreplaceable, not the category.** First draft refused ALL
    kinbox razes — but the outpost network is designed to promote a backup.
    The audit's harm case was losing the LAST anchor, so the guard is
    `pos == kinbox_pos and extra_boxes.is_empty()`. Before gating a whole
    type, find the code path that makes a member legitimately removable —
    demolish_at's own promotion tail was the spec.
64. **Sibling verbs pay one price, not just share one predicate.**
    `can_dodge()` was already shared, but the cost triple (0.35s / -15 SP /
    0.8s wait) lived in both the key path and the touch verb — three magic
    numbers to drift. Extract the verb (`dodge()`) too; a shared predicate
    with duplicated effects is half a contract.
65. **`get_peers()` needs a live peer, not just a pointer.** Calling it
    while `multiplayer_peer == null` emits an engine ERROR — every
    `give_remote`/`note_remote` on an offline rig or test harness was
    dirtying output. Guard the peer handle before asking for the list.
66. **Deterministic assertions need a drained world, not just parked
    actors.** The tranq test parked the herd but left stray projectiles in
    flight — every `fire_player_shot` departs from `player.pos` and one
    stray hit erases `sleep` per kin.gd's any-hit-wakes rule. Drain
    transient collections (projectiles/drops/floaters) before
    timing-sensitive checks; `projectiles.clear()` before the shot is the
    contract, same as the clears at steps elsewhere.
67. **A remote verb ports its gate before its effect.** `condense_remote`
    shipped owner-filtered logic but no `kin_condenser` reach — the remote
    twin was a strict superset of the local exploit surface. When wiring a
    guest verb, port the local's precondition (structure, range, stock,
    merchant) first, then its effect; a request that skips the gate IS the
    exploit.
68. **Pay the actor, not the local.** `kill_pal`'s loot/xp/hunt-credit
    defaulted to the host's bag because pid threading stopped one hop
    short (`hit` carried `provoked_pid`, `kill_pal` never saw it). Any
    shared verb that mints rewards routes them by actor pid at the
    mutation point — `give_remote`/`xp_gain` — never to whichever bag is
    local on the authority.
69. **A wire pack the harness never calls is already broken.**
    `state_snapshot`/`pal_state_pack` shipped `p.lv` for a property named
    `p.level` — every real join and every 2Hz broadcast would have died,
    invisible until the suite invoked them directly. Any new pack/snapshot
    function gets a harness call in the same commit; seed ≥1 live entry so
    `all()`/`any()` can't pass vacuously on an empty roster.
70. **A mirror writes to its own slot only.** Client replicas must never
    overwrite a live authority entity — `net_merchant_apply` is called
    solely from host-guarded handlers, and the smoke drill steps the real
    merchant aside before applying. If a helper can clobber host truth
    when invoked off-lane, gate it or quarantine it in the test.
71. **No honest path to a free mutation.** Goods minted host-side before
    payment lands are a mint exploit the moment ANY resale route exists
    (`bought` subtracted from an empty stack and the goods stayed —
    buy→sell printed gold). The honest client's UI must gate on
    affordability BEFORE the request flies (`board_done`/`buy`/`infuse`
    pattern); the echo then pays best-effort. Forged clients remain the
    documented bound — the gate is for honest hands.
72. **Ownership rides the claim, not the live pid.** `egg_parents` and
    `egg_inc` entries carry their owners' ids/tag because a stored pid
    rots the moment its session ends — resolve a dead pid to
    orphan-plus-tag (hello rebinds), never to a ghost owner that locks
    the kin out of every roster. Same for `placed_tag` on structures:
    tags outlive pids.
73. **Shared caps are per-owner slices.** A cap that protects balance
    (`max_base_pals`) must count the actor's own slice
    (`base_pals_of(pid)`), not the shared pool — otherwise a guest's pile
    silently starves the keeper's workforce with no eviction path.

74. **Explicit null clears; absence means "no change".** Every mirrored
    state field is tristate — a freed captive (`cap: null`) or an emptied
    crew (`wk: []`) can never ride "key missing", or the replica keeps a
    ghost value forever. `struct_wire_state` always ships `wk`/`timer` even
    at zero; apply-side `has()` + `erase()` pairs carry the distinction.
75. **A relay checks the wire, not the flag.** `rpc()` inside a request
    handler runs against the real peer — `is_host` true with a CONNECTING
    peer (or a torn-down one) spams "RPC via a peer which is not connected".
    Guards that precede an `rpc()` call check
    `get_connection_status() == CONNECTION_CONNECTED`, not just non-null.
76. **The host's own packets are truth, not suspect.** Position policing
    (`sync_pos` first-fix/step cap) is a host-side verb on guest claims —
    a client never runs it for another guest (the `peer_pos` relay is its
    only truth), and the host's own avatar (pid 1) can't spoof itself.
    Applying the gate to authority packets strands the host invisible
    past spawn+12.
77. **Same-shape fixes must enumerate every site.** Determinism lanes, reach
    gates, mirrors, pay-first — when a pattern lands on one site, list its
    siblings first. The phantom-wall class resurfaced a third time because
    the earlier sweep patched `regenerate` and left `_ready` on the same bug.
    Sweep sibling sites at write time; don't defer discovery to the audit.
78. **Cost verbs pay first; every refusal refunds.** Effects are host truth,
    the bag is client truth — effect-before-echo turns a dropped wire into a
    mint. New spend verbs default to `pay → req → done/rej`; an echo settles
    the ledger, it never debits.
79. **Snapshots sharing a field's truth must replace wholesale.** `state_sync`
    only placed rows — a same-cell local structure blocked `place_free` and
    left a phantom. Join-time application is raze-and-replace, not merge.
80. **Object references die before the node does.** Any long-lived pointer to
    a node the wire can free (mounts, focus targets, chest refs) must be
    cleared at every free site AND guarded at every consumer —
    `is_instance_valid` at the deref, not just the producer. `queue_free()`
    leaves the ref truthy until frame end; a missing-guard bug reads as
    per-frame freed-instance spam plus a wedged verb.
81. **Bound-state fields have a teardown contract.** When a status link
    (`mounted_by`, `job_site`, `carry`, `visible`) couples two entities,
    every path that retires, relocates, converts or frees either side calls
    the same unbind helper. New exit paths inherit the contract — grep the
    helper's call sites before adding a sibling, never inline a partial
    clear.
82. **Ledgers book actual debit, never declared cost.** `add_item` floors
    at zero, so `pay()` records `had - after`, not the price tag — an
    underfunded bag must never mint a refundable hold. Refunds draw from
    the recorded debit (FIFO tag match), and cap-full refuses BEFORE the
    request flies: a booked hold can never be evicted into a same-tag
    mis-settle.
83. **Throttles never gate hold-lifecycle verbs.** Claim/settle/release
    verbs self-guard on the live hold (`board_paid_remote` matches pid+id,
    first success erases) — a starved settle eats goods the keeper already
    shipped; a starved release squats the ask for its freshness window.
    Buckets belong on spammable requests, not on the verbs that free state.
84. **Every refused request echoes; every handshake flag needs a way out.**
    A throttle drop without a response wedges the waiting flag for the
    session (`mount_pending`, `board_paid_out`). The deny echo is part of
    the request (`mount_done(uid,0)`, `pay_rej`, `board_rej`), and a flag
    only a success can clear gets a self-heal lane (`unbind_retry_t`) or
    a reject path — never a silent hole.
85. **API names are probed, not assumed.** `server_relay` lives on
    `SceneMultiplayer`, not `ENetMultiplayerPeer` — a 10-line
    `get_property_list()` probe beat the runtime error. Godot API claims
    in a fix get the same treatment as data claims: verify the surface
    exists before wiring it.
86. **Untrusted-value aborts are a class with layers.** Coercing `int()`/
    `float()` was only layer one: typed function parameters
    (`world.generate(seed)`), `for ... in` on raw stored fields, `.split()`
    on dict keys, `has()`-gated iteration, and `bool()`/`== true` on
    foreign values all abort the same way. Closing the class means
    enumerating EVERY conversion surface, not just arithmetic reads —
    and migrate runs before load's guards, so it needs its own.
87. **Fixtures feed every abort shape, not the ones you fixed.** The
    hostile-save fixture missed seed/sp/key-type/iteration shapes because
    it was built from the fix list, not the failure taxonomy. When
    hardening a boundary, fixture the whole class: bad scalars, bad
    iterables, bad keys, bad tails, bad parents — or the next audit
    finds the layer you skipped.
88. **Row-tail reads abort at the highest unguarded index.** A
    `size() < 5` gate licenses `e[0..4]` only — the unconditional
    `e[5]` two lines later still crashes on the exact row the gate
    admitted (box_sync's sex field proved it). When a loop guards
    `size()`, every raw `e[N]` either takes `e.size() > N` or the
    gate rises to the deepest index the row actually touches.
89. **Wire handlers get the same boundary as saves.** Hardening
    load_game left `net.gd` running the identical `int()`/`float()`
    class the audit had just condemned — the trust boundary is the
    transport, not the file. Any boundary sweep greps BOTH
    directions of every sync verb before it closes, and fixtures
    drive hostile rows through the RPC handler itself, not just
    the coercion helper.
90. **Refusal precedes side-effects on bounded transfers.** A
    `to_box` that unbinds/drops the job then discovers a full box
    has already spent the kin's state. Capacity checks that can
    refuse go first in the function; the strip-row erase rides the
    same transaction so a failed lane can't orphan a uid.
91. **Release artifacts are rebuilt, never updated.** `zip` refreshes
    members in place — files deleted between exports survive inside
    the shipped bundle. Delete the target archive first, and let the
    shell expand the file list so the member set is real.
92. **The PCK ships every .gd under the project — tools included.**
    `export_filter="all_resources"` compiles test fixtures and dev
    scripts into the release binary (legacy-ID strings and all).
    Presets must exclude `tools/*`; IP scanning then skips tools/ by
    design — so any fixture that DOES ship must live outside tools/.
93. **IP sweep scope covers every shipped surface, incl. CJK.**
    Locale files and store copy are user-facing bytes; a romanized
    community name (e.g. 帕鲁) is the same leak as an English id.
    check_ip.sh scans src/+locale/+store/ with CJK terms in the pattern.
94. **Platform-dead features are hidden, not shipped broken.** A
    button that cannot work on the target (quit on web, ENet co-op in
    a browser) gets gated at the surface — `OS.has_feature("web")` —
    and marketing copy carries the same platform qualifier.
95. **Batch-wrap edits verify parse per pattern, not per file.** The
    tr(str()) sweep failed twice on whole-file regex — winning
    approach was one explicit pattern per shape, parse-check after
    each. A silent no-match reads as success; grep for residue after
    every pass, and never let a wrapper regex span string literals.
96. **Translation keys are authored from call-site truth, not scrape.**
    ~91 zh.csv rows were dead because the keys were scraped from
    literals that never reached tr(). A key that no call site can
    produce is worse than a missing one — it lies about coverage.
    Verify keys against actual tr() args (incl. trailing spaces).
97. **Generated artifacts must be reproducible from committed source.**
    `rigs_gen.py` regenerates from `rig_auto.py` + `species_dump.json`;
    verify `python3 tools/art/rig_auto.py` produces no diff before
    calling a render batch done. A generator committed older than its
    output silently regresses the next regeneration.
98. **Data dumps must read the authoritative accessor, not the row.**
    `dump_species.gd` used `d.get("body")` while the truth lives in
    `SpeciesData.body_of()` — 15 species rendered the wrong archetype
    and mounts rendered unmountable. Any field with an accessor
    (`body_of`, `species_of`, `mountable`) is dumped via the accessor.
99. **Replacing an asset means retiring its old writer.** The
    procedural kin writer in `gen_assets.py` stayed live after the
    Blender pipeline shipped — one documented run would silently
    revert all sprites. Old generators get a flag gate (`--kin-legacy`)
    or are removed; never leave two writers targeting the same files.
100. **Verification is weakened never.** The crown-pixel check was
    loosened to pass the new sprites instead of restoring the
    accessory. When a pinned assertion fails after an asset swap,
    restore the feature the test described or move the pin to a real
    equivalent — do not widen it until anything passes.
101. **A declared provenance is a write contract.** A header that says
    "auto-generated from X — do not edit" makes X the merge target:
    the S71 skills landed in `skills.gd` + `gen_species.py` but not in
    `prototype/src/data/skills.ts`, so one regen would have reverted the
    feature while the header kept lying. Patch the .ts (and its type
    union) in the same commit, or retitle the header to hand-maintained.
    Cousin defect: a second copy of a table with zero consumers
    (`SPECIES_LIST`) drifts silently against the live one — dead tables
    get deleted, never updated.
102. **A widened bound needs its whole class swept — twice.** `party_cap()`
    replaced a literal 5 at eleven sites and the audit still found four
    guest lanes (`rebind_owner` slice, `r_send_out` stray-uid gate, guest
    catch auto-join, guest box-full guard) plus `MAX_BENCH`'s formula and
    the hotkey range. When a constant becomes a function, grep the literal
    in EVERY file that touches the concept — host paths first, then the
    remote/mirror twins, then the derived-const formulas, then the input
    and copy surfaces.
103. **A synced flag needs its disconnect+join story, not just its tick.**
    A value carried by env_sync also needs: state_snapshot (join-time,
    before any dependent strip), _on_server_disconnected (residue reset),
    and the mirror's HUD read site named. A flag synced only on the tick
    desyncs for up to a resend window at every join.
104. **Wire text carries the english key + raw args; the receiver tr()s.**
    Never tr() before an rpc — a zh host would broadcast Chinese to en
    clients. `note_remote(pid, key, args)` and `net_floater` translate at
    the receiving end; string args ride as data keys and get tr()d one by
    one (`tr_args`). New RPC text channels follow the same shape.
105. **locale/zh.csv is loaded at runtime** (`load_csv_translations`) —
    the headless csv_translation importer scans the file and silently
    produces nothing; a stale `.translation` binary hid an entire i18n
    batch behind a green suite. Do not commit `.translation` binaries or
    trust `--import` for locale work: edit the csv, run the suite.
106. **The csv is a format-template contract, linted in the suite.** Every
    row: 3 columns, unique msgid, en/zh placeholder-signature parity, and no
    lone `%` in zh when the key is `%`-formatted downstream (`50%` must be
    `50%%`). Reordering `%d` args across clauses silently swaps values —
    keep en arg order. `tools/` append scripts caused a fused row once:
    never `open('a')`-append without a trailing-newline guard — read, edit,
    rewrite the whole file.
107. **A rule written is a rule re-audited.** Rule 104 was in the file while
    `note_remote(pid, fmt % args)` and `note_remote(pid, k, [tr(name)])`
    shipped the exact violation it bans. When a protocol rule lands, grep
    every sender of that channel in the same pass.
108. **Runtime-read data files need `importer="keep"`.** `FileAccess` on a
    `res://` path with a real importer resolves through the remap — an
    exported build reads the imported binary or nothing. `zh.csv.import`
    is keep; verify with `--export-pack` + byte-probe the pck when adding
    another raw file read.
109. **Identity secrets never ride broadcast state.** `struct_sync` shipped
    `placed_tag`/`own_tag` to every guest while `hello()` treated tag
    possession as proof — a public handle became an auth credential and
    any peer could inherit a disconnected keeper's roster. Wire schemas
    carry only what receivers consume; anything `hello`/ownership checks
    trust must never leave the host. Adding a field to `*_wire_state`
    means asking "does a stranger need this?" not "might it be useful".
110. **Session identity binds first-write-wins.** `hello(pid, tag)` locks
    the pid→tag mapping for the session's life; a second differing tag is
    refused, an identical one is idempotent. Any claim-style verb that
    rewrites identity is a session-escalation hole.
111. **Echoes settle against the recorded hold, not the wire's number.**
    The optimistic-debit ledger (`pending_pays`) is the client's truth —
    a receipt may only bill up to `pay_hold(tag)`, and mirrored postings
    (`board_quest`) cap quantities and whitelist ids. A forged echo can
    then waste a packet, never mint goods.
112. **World-clock verbs need semantic gates, not rate limits.** A bucket
    slows abuse; a rule kills it — guest sleep requires `is_night()`, and
    one sleep rolls dawn so the gate self-limits. Prefer the domain
    predicate ("is it time for this?") before reaching for another bucket.
113. **Fixtures plant full rows or erase by dict, never both.** A fake
    `structures` row without `workers`/`node` crashed `net_remove_structure`
    mid-call — the aborted cleanup left residue that poisoned every later
    save/load pass (a 10-failure cascade from one bad fixture). Fake rows
    leave via `structures.erase`; real teardown wants real shapes. And
    snapshot EVERY ambient key a scan touches (`egg_parents` lives on any
    structure — clear all of them before asserting claims).
114. **Fixtures observe outcomes; they never simulate the code path.** My
    lumenite-shard test mirrored `int_range` + `next()` to predict a seed —
    a hidden consumer elsewhere in the call chain would silently shift the
    stream. The robust fixture re-arms the world (same cell, hp=10) and
    forces `rng.s`, then reads what actually spawned. Same family: a shared
    tick couples the variable under test to unrelated systems — my corpse-
    bag check died because `_process` runs walk-over pickup alongside
    decay; isolate by moving the player out of pickup radius, not by
    assuming the tick only decays.
115. **Text layout is measured in pixels, not character budgets.** The build
    bar's `.left(9)` truncations looked defensive until a screenshot showed
    ~160px of row text overprinting a 122px slot — char counts lie across
    fonts, locales (CJK glyphs are double-width), and composed strings.
    Fixed-pitch UI gets a `font.get_string_size` check at draw time (step
    the font down, crop as last resort) or pixel evidence on every layout
    change. Same audit: untranslated fragments hide inside format parts —
    `cost += id.left(4)` shipped raw item ids to zh players; wrap the
    composed unit, not just the headline string.
116. **Progression keys need a first-source audit, not just a use-site
    check.** `gauntlet_sigil` was only ever awarded inside its own reward
    loop — a perfect circular dependency that shipped a dead campaign arc.
    For every item/flag that gates progress, grep its WRITE sites and ask
    "can a player reach this without already having it?" — then add the
    check to the suite as a source-existence assertion. Corollary: worldgen
    collections that `load_game` can't repopulate via `place_pois` (POIs
    ride the save, not worldgen) must serialize AND self-heal — `spire_pos`
    merges validated `spos` rows then derives the rest from live guardian
    tags, so a pre-field save loses nothing.
117. **A serialization contract is verified writer→reader, not reader-only.**
    `spire_pos` serialized raw `Vector2i`s while the loader coerced
    `is Array` — every real save's markers were silently dropped, and the
    crafted-save fixture (which hand-wrote Array rows the writer never
    emits) still passed. When a collection crosses a boundary (save, wire,
    settings), the fixture must round-trip the REAL producer's output —
    a hostile-input coercion check plus a sentinel the derivation path
    can't fabricate. Same pattern bit twice this cycle: the E-stockpile
    gate enumerated "automated sites" by hand and missed six producers —
    match-arm lists that mirror a data property (`job.produces` /
    `st["store"]` writers) should be derived from the data or audited
    against the full writer set, not curated by memory.
118. **A curated roster must satisfy every gate it answers to.**
     `LEGENDARY_DEN` picked `nibhand`/`shadekin` for flavor (paladin,
     doom knight sprites) — both `body: "human"`, which `ownable()`
     rejected, silently capping `den_caught()` at 8/10 and making the
     Accord unearnable forever. When a hand-picked list feeds a
     progression gate (den heirs, quest targets, unlock rosters), the
     invariant is "every member can satisfy its purpose" — write the
     smoke check against the LIST (all members pass the eligibility
     predicate), not the predicate alone. Gates compose multiplicatively
     and no single-site review saw the whole chain.
119. **Input verbs ship on every device layer at once.** `inv` had a key
     and a touch verb but no pad path for a year of pad support — a
     pad-only keeper couldn't eat, heal, or equip. Every new gameplay
     action gets: keyboard binding + pad binding (`bind_gamepad` dpad/
     stick budget is documented) + touch verb or pause row, or a written
     exception — in the same change. The smoke check enumerates each
     verb's bindings per layer (`InputMap.action_get_events`), so an
     action added without a pad/touch route fails the suite, not a
     store review.

120. **A "dedupe scan" inside a per-element loop is a hidden O(n²).**
     `cell_of` looked like a 6-line helper; inside `tick_production`'s
     per-cell loop it was 1.3M compares/frame at cap. When the element
     already stores its key (`structures.*["pos"]` is the anchor), the
     scan is a lie — read the field, and grep EVERY call site of the
     helper before shipping (hud.gd had 4 more in draw paths).
121. **Skipped-needs containers must reset the skipped accumulator on
     exit.** Box kin don't run `tick_needs`, so `hunger=100` froze
     forever — every revive replayed the same KO 50s later. Any mode
     that suspends a decaying stat needs the transition-out to clamp it
     (or the suspension is a softlock dressed as mercy). And log the
     real cause — "KO'd" hid "starved" from the player entirely.
122. **Batch linear-in-dt ticks; cache stationary targets.** If a tick
     only does `x += dt * f(...)` work, an accumulator running it at
     4Hz is mathematically identical and drops every nested O(cells)
     helper to a quarter of the cost. AI that re-scans for a target
     which can't move (chests) should rescan on a clock, not per frame.

123. **Run the game and look at it.** Static reviews missed two defects
     that one screenshot caught in a second: text drawn past the screen
     edge, and the hint column a player reads every minute. A real
     playthrough harness (real verbs, real frames, PNG per beat) is a
     first-class audit — write one per visual domain, keep the shots.
124. **A memo needs an invalidation key, not just a TTL.** The heat
     cache was correct until a campfire appeared inside its 0.4s window.
     Cache keys must include the thing that can change the answer —
     and `size()` lies: a same-size raze+build swap nets zero. Use a
     monotone generation counter bumped at every mutation site
     (`_struct_gen`), and grep ALL write paths when wiring one —
     erase sites, footprint inserts, clears, and load rebuilds. TTL
     alone is a staleness bomb with a fuse.
125. **Owner-slice every ledger write; trace the reshape, not the
     pack.** Multiplayer credit that reads as "the world's record" must
     name whose book it lands in — the island's catalog (accord/dex)
     counts every catch, but a guest's kindex/missions need their OWN
     ledger riding home (`catch_credit` → `credit_catch_local`). And
     append-only wire fields only stay compatible if the reshape chain
     forwards them: `pal_state_pack[12]` becomes `spawn_net_pal[11]` —
     assert the field at the consumer's index, not the producer's.
126. **Mixed-outcome pays are audited best-of-branch, then summed.** A
     gacha/chest with a rare tier stays a mint if ANY branch's best exit
     (raw resale, processed resale, crafted value) beats its share of
     cost — killing the common branch leaves the rare one printing.
     Assert `Σ P(b) × max(exit_b) < cost` computed from live tables, so
     price edits re-validate instead of rotting. And a rate cap is a
     time gate, not a depth gate: if a sink is meant to absorb surplus,
     uncap the stock and let the conversion rate do the limiting.
