# PLG — Dev Rules

Godot 4.7.2, GDScript, headless-verified. Run the smoke suite before committing:

```
/Volumes/17333023680/Godot/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/smoke_test.gd
# tail of output: "==== N checks, 0 failures ====" must be 0 failures.
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
   `tools/gen_assets.py` creates a file, run
   `godot --headless --path . --import` once — `load()` silently returns null
   on unimported resources, and a null texture mid-`load_game` aborts the
   rebuild. Every `spr.texture` consumer guards with the chest.png fallback.
   Far wild pals already tick at ~8Hz; keep new per-pal work behind the same
   accumulation pattern.
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
    only "a species the player may own" gate — never per-site ad-hoc filters.
    Intentional exceptions (dens, grotto, sigil raids) pick `LEGENDARY_DEN`
    deliberately and say so in a comment.
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
    answers to `acquirable()`. `resolve_sphere`/`net_catch` reject
    non-acquirable targets regardless of `boss`; spawn pools filter at the
    source AND the catch layer refuses what slipped through.
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
