
# Audit-45 — Export credibility + perf-under-cap cold pass

Scope: `project.godot`, `export_presets.cfg`, InputMap/touch/pad parity, i18n/font
export survival, OS/net platform paths, and the per-frame cost of `pals.size()
== MAX_PALS` (220). All claims verified against source; prior audits
(audit-34 input, audit-35 perf, audit-44 i18n) cross-referenced — this audit
reports only what survives them.

Verdict: **3 HIGH · 8 MED · 5 LOW** + verified-correct inventory.

---

## HIGH

### H1 — Dev docs, banned-lexicon notes, third-party screenshots, and TS prototype ship inside every PCK
- `export_presets.cfg:9-11,58-60,101-103` — `export_filter="all_resources"` + `exclude_filter="store/*,tools/*"` on all three presets; `docs/` and `prototype/` are **not** excluded.
- `tools/check_ip.sh:4-5` explicitly documents that `docs/` legitimately contains the banned Palworld lexicon ("docs/ and tools/ test fixtures legitimately contain old ids as migration payloads") — but `tools/` is excluded and `docs/` is **not**. The shipped PCK contains the very terms the IP sweep exists to keep out of shipped files.
- `docs/art-study/coo/ref-ingame-*.jpg|png` + `.import` — imported third-party reference screenshots ship as real resources in every build.
- `prototype/` — ~30 TypeScript sources + `package.json`/`vite.config.ts` ship verbatim (`script_export_mode=2` only compiles `.gd`).
- **Impact:** legal/IP exposure — a project whose store page is being de-risked from Palworld comparison ships Palworld-identifying migration notes *and* reference screenshots of another game in every binary; plus web-pack bloat and uncompiled TS source leakage.
- **Fix:** `exclude_filter="store/*,tools/*,docs/*,prototype/*"` on all three presets; byte-probe the built pck to confirm; extend `check_ip.sh`'s "shipped surface" notion to match the preset filter.

### H2 — zh locale and HUD icon glyphs are tofu on Web and Android: the font fallback is a `SystemFont`
- `src/hud.gd:6` `var font: Font = ThemeDB.fallback_font`; `src/hud.gd:86-89` loads `fonts/PressStart2P-Regular.ttf` (Latin-only pixel font) then `pf.fallbacks = [font]` — the fallback is a `SystemFont`.
- Godot docs: `SystemFont` "is implemented on iOS, Linux, macOS and Windows" — on Web and Android it collapses to the default theme font (Latin/Greek/Cyrillic subset; no CJK, thin symbol coverage). Confirmed by engine docs/issues (godotengine/godot#84590).
- `src/game.gd:4342-4358` runtime-loads `locale/zh.csv` (967 lines, `importer="keep"` at `locale/zh.csv.import:3`) — the *translation data* ships and loads; the *glyphs* can't rasterize.
- The same fallback also carries every HUD glyph PressStart2P lacks (♥ ● ○ ★ ☆ ⚡ ☂ ☀ ✦ ✕ ▲ ▼ ≡ ♡ » etc. used across `hud.gd` draws) — en chrome also degrades on web/Android, not just zh.
- `docs/reviews/audit-44-localization.md:68-72` deferred exactly this to "the export stage" — this is that stage.
- **Impact:** zh (a shipped settings option) is unreadable on 2 of 3 export targets; HUD icon language partially tofu on those targets even in en.
- **Fix:** bundle a CJK-capable font (a subsetted build keeps the MB cost sane) plus a symbol-covered font, and prepend both to `pf.fallbacks` ahead of the SystemFont; verify with a zh screenshot build on web + Android.

### H3 — `tick_repairs` is O(structure-cells × unique-structures) **every frame** on the host whenever idle repair-capable kin exist
- `src/game.gd:2614` calls it unconditionally from `_process`; `src/game.gd:2984-2991` gates on ≥1 idle base kin with `handiwork > 0` (an ordinary mid/late-base state).
- `src/game.gd:2992-2997`: `for k in structures` iterates every footprint **cell** (~up to 400 structures × w·h ≈ 1,600 keys at `MAX_STRUCTURES=400`, `game.gd:2763`) and dedupes with `st in seen` — a linear array scan of up to ~400 `Dictionary` entries per cell → up to ~640k deep dictionary comparisons per frame.
- This is the same defect class audit-35 fixed inside `tick_production` (`cell_of` removal); the save path already uses the correct shape — `src/game.gd:4458-4464` dedupes via `seen_st.has(st)` on a Dictionary.
- **Impact:** sustained multi-ms frame cost during normal base play; worst on the Android GL target — the clearest "visible jank at normal load" found in this pass.
- **Fix:** replace `seen: Array` + `st in seen` with `seen: Dictionary` + `seen.has(st)` (copy the `save_game` shape), or iterate `st.get("pos")`-unique structures once.

---

## MED

### M1 — Android preset is sideload-ready but can't reach Google Play: APK-only, empty SDK floors
- `export_presets.cfg:116-119`: `gradle_build/use_gradle_build=false`, `gradle_build/export_format=0` (APK lane), `min_sdk=""`, `target_sdk=""`. (`version/code=2`, `version/name="0.9.0"`, `package/unique_name="com.kinbound.game"`, `package/signed=true`, `permissions/internet=true` are all coherent.)
- **Impact:** the APK installs on device/itch, but Play Console requires AAB for new apps and an explicit current targetSdk; empty fields defer entirely to template defaults.
- **Fix:** keep this preset as the itch/sideload APK; add a Play lane with `use_gradle_build=true`, `export_format=1` (AAB), explicit `min_sdk`/`target_sdk`.

### M2 — Web preset forces cross-origin isolation for threads nothing uses
- `export_presets.cfg:74` `variant/thread_support=true`; `:83-84` PWA enabled with `ensure_cross_origin_isolation_headers=true` (service-worker COOP/COEP injection — works, but only after SW activation, and not at all in contexts that can't be isolated).
- No `Thread`/`WorkerThreadPool` usage anywhere in `src/` (grep-verified); the sim is single-threaded.
- **Impact:** the page hard-fails (`SharedArrayBuffer is not defined`) on hosts/embeds that can't serve COOP+COEP — itch embeds, iframe contexts, some portals — for zero benefit.
- **Fix:** `variant/thread_support=false` unless a thread consumer lands; keep `:84` set either way.

### M3 — Terrain `_draw` runs every frame with per-tile string work; cost grows ~quadratically as you zoom out
- `src/main.gd:60-66`: `vis != last_vis` is already computed for decor, but `game.drawer.region = vis; drawer.queue_redraw()` runs **unconditionally** every frame.
- `src/world_drawer.gd:23-29` two full passes over `region`; `:41-46` `Rng.hash2` + `base + "_" + str(v)` string concat + `cells` lookups **per tile per frame**; `:49-66` same shape for faces.
- `src/main.gd:71-76` allows zoom down to 0.35: ~12–16k visible cells → ~25–32k `draw_texture_rect_region` + ~15k string allocs/frame; default zoom 0.9 ≈ ~2.8k cells → ~5.6k cmds.
- **Impact:** the largest renderer CPU cost in the game, and it scales the wrong way on small screens where players pinch out most.
- **Fix:** redraw only when `vis != last_vis` or a `terrain_dirty` flag fires (farm/harvest/elev writes mark it); cache the variant name (hash→name LUT or per-cell cache) so steady-state draws are pure `draw_texture_rect_region`.

### M4 — HUD `_draw` rebuilds every string and runs `get_string_size` trim loops every frame, in every state
- `src/hud.gd:92-93` `queue_redraw()` unconditionally; ~187 draw calls in the path.
- Per-frame allocations: `tr("RAID IN %ds")` (`:989`), `tr("%s %s Lv%d%s")` (`:1010`), `tr("» ") + tr(...)` per hint (`:1024`), and `while …get_string_size()… left(len-2)` shaping loops (`:1016-1026`) that can run dozens of shaping calls per hint per frame.
- Per-frame scans: boss-bar O(pals) (`:994-1001`), post-crown den O(pals) (`:1046-1047`), `active_hints()` lambdas incl. `pals.any`/`structures.values().any` evaluated twice per frame (`_draw` + `game.tick_hints`, `game.gd:2536-2547,2549-2551`).
- **Impact:** steady ~ms-scale CPU + allocation churn every frame on every platform — second only to the terrain pass; hits the weak CPU targets (web/Android) hardest.
- **Fix:** cache formatted strings keyed on the value that feeds them (raid_t int, mission idx, hint set); cache measured widths; memoize boss/den scans ~4Hz or behind dirty flags.

### M5 — Net sync has two quadratic shapes at 2Hz and on each client packet
- `src/net.gd:382-433` `pal_sync`: each of up to ~220 rows calls `game.find_net_pal(nid)` which is O(pals) (`src/game.gd:981-985`) → ~48k compares per packet on every client at cap.
- `src/net.gd:767-777` `struct_state_pack`: `st not in seen` array-dedupe — the H3 shape — running every 0.5s on the host (`net.gd:1502-1512`).
- (`box_fingerprint` `net.gd:1294-1312` iterates box+bench+pals+remote_parties each 0.5s — bounded ~1k, fine.)
- **Impact:** per-tick client hitch at full population; host-side 2Hz quadratic on structure-heavy bases.
- **Fix:** maintain a `net_id -> Kin` map on clients (invalidated in the same `seen` sweep); Dictionary-keyed dedupe in `struct_state_pack`.

### M6 — Player heal scan walks every structure cell per physics frame while injured
- `src/player.gd:338-343`: `if hp < max_hp: for k in game.structures:` — O(cells) (~1,600 at cap) every physics frame during the common "damaged" state, no memo. `nearest_heat` (`src/game.gd:3588-3606`) already demonstrates the intended memo shape (0.4s + position + `_struct_gen`).
- **Fix:** memoize identically, or keep a hot-spring position set bumped on `_struct_gen`.

### M7 — Per-kin spatial scans and per-frame array churn stay linear but unbatched at 220
- `src/kin.gd:553-599` `partner_ai`: every partner scans all pals (≤220) + all drops (≤400) per physics tick — partners never qualify for the ~8Hz far-kin accumulator (`kin.gd:306-313`, `far := mode == "wild" and dist > 28`).
- `src/kin.gd:613-626` `find_foe`: O(pals) per base kin per tick (≤ ~40 base kin → ~8.8k distance checks/frame).
- `src/game.gd:2690` `pals.duplicate()` every frame in `tick_raider_sweep` even with zero raiders; `:2630` `floaters.filter` allocates per frame; `:2653` `net_drops.keys()` allocates per frame — rule-4 pressure, all bounded.
- `src/game.gd:2663-2667` wild recount O(pals) per frame; `danger_active` O(pals) via `tick_music` (`:2555-2574`) and again in `hud` draws.
- **Impact:** ~10–12k checks/frame steady-state at cap — tolerable on desktop, worth batching on mobile.
- **Fix:** move partner/base foe scans behind a shared 2–4Hz spatial cache; early-out the raider sweep when no `raid`-flagged kin exist; reuse a scratch array for drops/keys iteration.

### M8 — `perf_probe` measures but cannot fail: no timing budget anywhere in the toolchain
- `tools/perf_probe.gd:22-31,61-69,111-119` prints elapsed ms for kin-tick/game-tick/raid/base stress (`PLG_STRESS`/`PLG_RAID`/`PLG_BASE` envs) but asserts nothing; the smoke gate only checks correctness.
- `tools/sim_balance.gd` / `tools/sim_economy.gd` are formula/data probes — no runtime-cost coverage (audit-35 confirmed their honest scope).
- **Impact:** a 5× regression in kin AI or the HUD draw ships green.
- **Fix:** assert `elapsed < budget` per scenario (scaled generously for CI), or commit a baseline file and fail on >1.5× regression.

---

## LOW

### L1 — `project.godot` carries no `config/version` or `config/description`
- `project.godot:6-12` — name/icon/splash only. Presets each carry 0.9.0 (`export_presets.cfg:39-40` Windows file/product version, `:124-125` Android version), but the shared app version surface is empty — window titles/macOS metadata read `config/version`.
- **Fix:** add `config/version="0.9.0"` and `config/description`.

### L2 — Windows release preset ships a console window
- `export_presets.cfg:24` `debug/export_console_wrapper=1` — useful for beta logs, reads as unfinished on Steam.
- **Fix:** drop to 0 for the Steam build (or keep a separate "beta" preset).

### L3 — Desktop "TOUCH CONTROLS: on" shows buttons the mouse can't press, and they eat clicks
- `project.godot` has no `[input_devices]` section → `emulate_touch_from_mouse=false` (default), `emulate_mouse_from_touch=true` (default, and **load-bearing** — `src/player.gd:70-77` expects touch taps to arrive as emulated LMB and filters them via `hud.touch_zone_hit`).
- `src/hud.gd:154-165` touch verbs fire only on real `InputEventScreenTouch` — so on desktop with `touch=on` forced in settings (`game.gd:4373-4374`), the virtual buttons render, swallow the melee at `player.gd:71`, but can never be pressed.
- **Impact:** self-inflicted dead-controls trap; recoverable (settings rows are mouse-clickable).
- **Fix:** enable `emulate_touch_from_mouse` and test for double-fire (`touch_verb` vs emulated LMB — `atk_cd` gates melee but panel verbs could double-toggle), or route LMB taps through `touch_down`.

### L4 — Android backup disabled: saves die with uninstall
- `export_presets.cfg:130,148` `retain_data_on_uninstall=false`, `user_data_backup/allow=false` — a 400-slot kinbox save has no cloud safety net on the most loss-prone platform.
- **Fix:** consider `user_data_backup/allow=true` (Auto Backup covers `user://` by default on Android) — a design call, not a defect.

### L5 — Same O(n²) `not in seen` dedupe pattern persists in verb/packet paths
- `src/game.gd:2744-2750` `kinbox_count`, `:2786-2790` `place_structure`, `src/net.gd:302-308` `state_sync` cleanup — all bounded and rare (build verbs, join), worth the same Dictionary-keyed fix while touching H3/M5.

---

## Verified correct (checked, no action)

- **Audio:** buses `Music`/`SFX` are created at runtime (`src/game.gd:275-278`), and `apply_settings` bus-lookups guard on `get_bus_index >= 0` (`:4366-4371`) — no missing-bus crash on any platform; all audio is synthesized `AudioStreamWAV` (`src/sfx.gd`) → zero audio assets in the pack.
- **Save/user paths:** `user://settings.cfg|savegame.plg|plg_net.cfg` — portable across desktop/app-sandbox/web-IndexedDB; no absolute paths, no `OS.execute`, no `res://` writes at runtime.
- **Web co-op is cleanly amputated:** `src/main.gd:19-23` never creates `net` on `OS.has_feature("web")`; JOIN/HOST/CHAT rows gate on `game.net != null` (`src/hud.gd:1549-1553,1581-1590`); QUIT rows gate on `not OS.has_feature("web")` (`:1552,1592`) — `get_tree().quit()` unreachable on web; `experimental_virtual_keyboard=false` is consistent (no net ⇒ no join/chat panels to type into, `hud.gd:121-126`).
- **Renderer:** `gl_compatibility` for desktop **and** mobile (`project.godot:25-26`) — the only renderer that ships a web build; correct choice for a 2D canvas game.
- **Stretch/orientation:** `canvas_items` + `expand` (`project.godot:19-20`), `handheld/orientation=4` sensor-landscape (`:21`), PWA `orientation=1` landscape (`export_presets.cfg:87`), `canvas_resize_policy=2` project-size (`:80`), `focus_canvas_on_gameplay=true` — coherent 1280×720 layout on all targets.
- **Texture pipeline:** `import_etc2_astc=true` (`project.godot:28`), web `for_mobile=true` (`export_presets.cfg:76`), s3tc_bptc on Windows (`:26-27`) — GPU-friendly on all three lanes.
- **Every referenced export asset exists:** `assets/ui/icon.ico`, `icon_144/180/192/512.png`, `icon_adaptive_fg/bg/mono.png`, `assets/tiles.png` + `tiles.json` (loaded `world_drawer.gd:13-17`), `locale/zh.csv` + `importer="keep"` (survives export as a readable file for `FileAccess`, `game.gd:4345`), `fonts/PressStart2P-Regular.ttf`, `assets/ui/halftone.png` (`Ink.dots`, `style.gd:49-53`), `assets/shadow.png`, all kin/decor/player PNGs **with** `.import` files.
- **Input parity:** all 30+ actions bound in `[input]` (keyboard + physical keycodes for J/K/P/R/G/U/V/N — layout-independent); `bind_gamepad()` (`game.gd:2449-2477`) covers every verb — axes for move/LT-sprint/RT-strike/RS-zoom, A/B/X/Y face buttons, RB/LB party+stance, Back build, Start ui_cancel, dpad inv/ride/partner_skill/map, L3 demolish, R3 field-swap — and is idempotent (strips joypad events before binding; audit-34/35 verified).
- **Touch layer:** virtual stick + verb row + ✕ buttons + pinch zoom (`InputEventMagnifyGesture`, `main.gd:71-72`) + OS virtual keyboard gated on `touch_ui` (`hud.gd:121-126`); auto/on/off detection via `DisplayServer.is_touchscreen_available()` (`game.gd:4374`).
- **Raw-key paths are typed-input only:** chat/join text entry, party 1-9 digits, build-row digits — keyboard-by-nature paths with pad/touch equivalents (pause-shell INVENTORY, R3 cycle) — consistent with audit-34's parity fix, not new defects.
- **All caps honored:** `MAX_PALS=220` (`game.gd:87`) with every spawn site guarded (`:813,851,869,943,1150,1223,1743,3664,4887,5260,5662,7509,7576`); `MAX_DROPS=400` evict-oldest (`:2221-2231`); `MAX_PROJECTILES=200`; `MAX_FLOATERS=80`; `MAX_BOX=400`; `MAX_BENCH≈198`; `MAX_STRUCTURES=400` (`:2763,2790`).
- **Tick batching:** production ~4Hz (`game.gd:2598-2601`), assignment ~2s (`tick_assign`), fog reveal 0.5s (`:2618-2621`), spoilage 480s (`:2609-2612`), merchant wander 2.5–5s (`:7609-7613`), drop decay 600s (`:2637-2640`), far-wild-kin AI ~8Hz accumulator (`kin.gd:306-313`) with `adt` carried forward so speeds stay honest.
- **Memoization:** `nearest_heat` memo 0.4s + `_struct_gen` invalidation (`game.gd:3584-3606`, bumped `net.gd:308`); haul-kin rescan ~2.5Hz (audit-35); fog/minimap bake keyed on `explored_n` (`hud.gd:81-82`).
- **Image/texture discipline:** `_light_tex` create-once (`game.gd:47-55`), `_drop_tex` per-item-id cache with `_unk` flood-guard (`:2234-2250`), `_kin_tex` portrait cache, `Ink._dots` lazy (`style.gd:50-52`) — **no `Image`/`ImageTexture` allocation in `_process`/`_physics_process`** — rules 3/4 hold.
- **Node budget:** a live kin = `Kin` + shadow + sprite (`entity.gd:20-30`) ≈ 660 nodes at cap; box pals reparent to process-disabled `box_holder` (`box_pal`/`unbox_pal`) — no parentless pals; teardown paths use `free()` for box kin (`:7701,7729`) and `queue_free()` for in-tree nodes; decor sprite pool recycles (`main.gd:93-130`); drop sprites freed on `take_drop` (`:2285-2288`).
- **Host authority:** every world mutation guards `net.is_client()` (spawn_drop `:2217`, hit_structure `:3004`, tick_repairs `:2980`, merchant `:7596`, respawn/raid/supply `:2662-2680`); RPC handlers fail closed on `ghosts.get(pid)` + distance + `_throttle` buckets (take_drop `net.gd:735-753`, harvest `:792-798`, build `:801-818`, demolish `:827-833`); `box_sync` is per-peer owner-filtered + fingerprint-diff gated (`net.gd:1294-1341,1527-1533`).
- **2Hz broadcast shape:** `pal_sync`/`drop_sync`/`struct_sync`/`env_sync`/`decor_delta` on a single 0.5s cadence (`net.gd:1502-1536`); `pal_state_pack` is O(pals) once per broadcast (`net.gd:364-379`) — correct shape, see M5 for the client-side reconcile.
- **Deliberate exceptions documented:** `tick_migration` local-fauna authority (`game.gd:2681` comment, `:5132`); save-time O(pals×structures) job lookup is write-path only (`:4402-4408`).
