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
