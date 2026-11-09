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
   not grow new `ObjectDB instances were leaked` counts vs. baseline.
