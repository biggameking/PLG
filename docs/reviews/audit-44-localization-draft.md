Subagent agent_id=db49c717 completed successfully:

Evidence collection complete. Here is the full audit report — I could not write the file myself (read-only Explore mode); the parent agent must write it to the requested path and print it.

---

```markdown
# Audit 44 — Localization Completeness (zh)

Scope: `tr()` coverage, `locale/zh.csv` integrity, dynamic args, locale plumbing, CJK font, smoke assertions. Gameplay/netcode/art deliberately out of scope. Godot 4.7.2, GDScript.

## Architecture (verified)

- **Single runtime locale source**: `locale/zh.csv` (~960 rows, header `keys,en,zh`). No `assets/i18n/en.csv` exists — English text is the msgid (`keys == en` on every row). `zh.csv.import` is `importer="keep"` → shipped as-is via `export_filter="all_resources"` (only `store/*,tools/*` excluded).
- **Loader**: `game.gd:4333-4349` parses the CSV at boot, builds a `Translation` with `t.locale="zh"`, registers via `TranslationServer`. `game.gd:4357-4363` applies `set_locale("zh"|"en")` from `settings.lang`.
- **Persistence**: `user://settings.cfg`, `game.gd:4323` coerces `lang` to `en|zh` (bad values → `en`). Default `game.gd:71` `"lang":"en"`.
- **Toggle**: `hud.gd:644-645` flips `settings["lang"]` → `apply_settings()` → save. Label at `hud.gd:1628` (`中文`/`EN`, deliberate self-describing). Open panels re-render immediately — `hud._process` calls `queue_redraw()` every frame, all text is drawn via `tr()` at draw time. ✓
- **Net boundary**: `game.gd:405-411` `note_remote` sends the English key + raw args; receivers translate in `net.gd:200-218` (`net_note`/`net_floater` → `tr(msg) % tr_args(args)`). All 48 `note_remote` call sites pass raw data names (e.g. `p.spec["name"]`) — args travel as translation keys by design, and smoke tests cover the round-trip. ✓
- **Guide**: `GuideData.pages()` (`src/data/guide.gd:487`) returns `PAGES_ZH` (9 pages) vs `PAGES` (9 pages) by locale — parallel-text design, not CSV. ✓
- **Font**: `hud.gd:86-89` loads `PressStart2P-Regular.ttf`, sets `pf.fallbacks = [ThemeDB.fallback_font]` — CJK/icon glyphs fall through to the OS system face; every `draw_string` uses this `font`. Desktop-correct by design.
- **Render-time translation**: `menu_row` (`hud.gd:1427`) wraps labels; all item/structure/species/skill/element/stance/ailment display names resolve through `tr(str(...))` at draw sites. ✓

## CSV integrity (verified)

- Header `keys,en,zh`; every inspected row has exactly 3 columns, `keys == en`.
- No duplicate msgids observed (also runtime-linted, see smoke section).
- No empty `zh` cells; no English prose left in `zh` (exceptions are intentional: `Kinbound` brand L35, `Lv%d %s` L81 identical, symbol/format-only rows).
- `keys`/`en`/`zh` placeholder sets consistent (runtime-linted after `%%` strip).

## Findings

### HIGH

1. `src/game.gd:2849` — `log_msg(tr("Built %s") % s["name"])` — structure display name not tr()'d → zh log reads `建成了 Campfire`. **Fix**: `tr(str(s["name"]))`. **Smoke**: yes (build → assert log tail contains no `[A-Za-z]`).
2. `src/game.gd:2953` — `log_msg(tr("Demolished %s (50%% refund)") % StructureData.STRUCTURES[sid]["name"])` — same class → `拆除了 Campfire（返还 50%）`. **Fix**: `tr(str(...["name"]))`. **Smoke**: yes.
3. `src/game.gd:3853` — `log_msg(tr("Base mission: ") + BASE_MISSION_TEXT[base_level])` — the data string is never tr()'d → `基础任务：deploy 2 kin` (CSV keys exist at L892-895). **Fix**: `tr(str(BASE_MISSION_TEXT[base_level]))`. **Smoke**: yes.
4. `src/game.gd:1182-1183` — `else "A boss stirs again at its den"` — ternary else-branch unwrapped AND not a CSV key → full English log at the boss-respawn beat. **Fix**: `tr("A boss stirs again at its den")` + CSV row. **Smoke**: yes.
5. `src/game.gd:4098` & `4105` — `floater(caster.pos, sk["name"] + tr("!"), ...)` — skill name raw (only `!` translates) → `Whirlwind！` on every AoE/multi cast. **Fix**: `tr("%s!") % tr(str(sk["name"]))`. **Smoke**: yes.
6. `src/game.gd:7293` & `7300` — `tr("Unequipped ") + it["name"]` / `tr("Equipped ") + it["name"]` — raw item name + English word order → `已卸下 Meat Cleaver`. **Fix**: new keys `Unequipped %s`/`Equipped %s`, `tr("...") % tr(str(it["name"]))`. **Smoke**: yes.
7. `src/game.gd:6689` — `tr("Statue upgraded: %s Lv%d") % [k, perks[k]]` — raw perk id (`atk`,`capture`,`speed`,`hp`,`work`,`xp`; defined `game.gd:11`) interpolated → `雕像升级：atk Lv2`; no CSV keys for them. **Fix**: 6 CSV keys (or a `PERK_LABEL` map) + `tr(k)`. **Smoke**: yes.

### MED

8. `src/game.gd:3099` — `tr("Need to be at a %s") % stn` — raw structure id → `需要站在 workbench 旁` (fires on every gated craft). **Fix**: `tr(str(StructureData.STRUCTURES.get(stn, {}).get("name", stn)))`. **Smoke**: yes.
9. `src/game.gd:3104` — `tr("Unlock %s in the tech tree first") % r["tech"]` — raw tech id → `先在科技树解锁 logging`. **Fix**: translate via a tech-name table/CSV keys. **Smoke**: yes.
10. `src/game.gd:7076` — `tr("Player %d razed %s") % [pid, st["id"]]` — raw structure id → `玩家 2 拆掉了 campfire` (net path). **Fix**: resolve display name then `tr()`. **Smoke**: yes.
11. `src/player.gd:459` — `log_msg(tr("Out of ") + ammo_id)` — raw item id + wrong order → `用光了kin_orb`. **Fix**: `tr("Out of %s") % tr(str(ItemData.ITEMS.get(ammo_id, {}).get("name", ammo_id)))`. **Smoke**: yes.
12. `src/kin.gd:646` — `tr("%s burned out — now weakened") % spec["name"]` — raw species name (`Pyrejelly 精疲力尽——…`). Same unwrapped-arg defect at `kin.gd:881` (`took medicine - recovered`) and `kin.gd:887` (`is going BERSERK — keep medicine stocked!`). Sibling calls at `kin.gd:763-764,773` already tr() the same field — fix is local. **Fix**: `tr(str(spec["name"]))`. **Smoke**: yes.
13. `src/net.gd:1001` — `tr("Monitoring stand: %s pace") % d["name"]` — arg not tr()'d AND `Normal`/`Hard`/`Overdrive` (`game.gd:5078-5081`) aren't CSV keys → English on guests AND on host (`game.gd:5091-5093` tr()'s a non-existent key). **Fix**: 3 CSV keys + `tr(str(d["name"]))`. **Smoke**: yes.
14. `src/game.gd:6873` — `tr("%s can't see a line to that mark")` — missing CSV key → full English log line. **Fix**: add row. **Smoke**: coverage lint would catch (not yet present).
15. `src/game.gd:5204-5207` — `howl` = `"Iron Pact squad"`/`"%s pack" % raid_theme.capitalize()`/`"wild mob"` — raw English inserted into `tr("Raid party spotted — a %s is coming for the kinbox!")` (5208) and shipped via `note_remote` `RAID INCOMING — %s!` (5213) → `突袭队现身——一只 Fire pack 冲着兽箱来了！`. **Fix**: tr() the howl variants (`Iron Pact squad`, `%s pack` with `tr(str(theme))`, `wild mob`). **Smoke**: yes.
16. `src/game.gd:1787` — `floater(cur, tr("clink!"), ...)` — missing CSV key → English floater on every blocked throw. **Fix**: add row. **Smoke**: coverage lint.
17. `src/game.gd:5757` — `" and a lumenite shard"` raw fragment → `挖出化石：3 个古代零件 and a lumenite shard`. **Fix**: tr() the fragment. **Smoke**: yes.
18. `src/game.gd:5665` — `"LUCKY " if huge else ""` raw fragment → `蛋孵化了：LUCKY 沼冻灵`. **Fix**: reuse `tr("☆ LUCKY ☆")` (CSV L388) or add a `LUCKY ` key. **Smoke**: yes.
19. `src/game.gd:5295` — `tr("+%s") % fm["item"]` — raw item id floater → `+dart`. **Fix**: `tr(str(item display name))`. **Smoke**: yes.

### LOW

20. `src/hud.gd:2215` — `draw_string(..., "OK", ...)` — confirm button label unwrapped, no CSV row → `OK` stays Latin in zh (cancel `"X"` at :2218 is a glyph, acceptable). **Fix**: `tr("OK")` + row, or document as an icon exclusion. **Smoke**: coverage lint.
21. `src/hud.gd:2041` — `"Lv%d %s" % [...]` unwrapped format — output identical anyway (`Lv%d %s` translates to itself, CSV L81). Cosmetic inconsistency. **Fix**: `tr("Lv%d %s")`. **Smoke**: yes.
22. `src/hud.gd:2281` — `tr(", ")` missing key — falls back to `, ` (identical). **Fix**: add row or use a CJK joiner key. **Smoke**: coverage lint.
23. `src/hud.gd:2470` — `tr("%d-%d / %d")` missing key — identical fallback. **Fix**: add row. **Smoke**: coverage lint.
24. Dead CSV rows (no producing `tr()` call — AGENTS.md rule-96 lint would flag): `"  (placing: %s)"` (L875 — call site now uses `BUILD  placing: %s — %s`), `"%s%s%s %s%s Lv%d T%d %sHP%d/%d"` (L831 — party row produces `%s%d/%d`), `"Lv%d %s"` (L81 — only produced unwrapped at hud:2041). **Fix**: prune or rewire. **Smoke**: dead-key lint (grep tr-keys vs CSV).
25. `hud.gd:86-89` font chain is correct on desktop, but zh renders on the *system* face rather than a bundled CJK font — stripped export targets (esp. web) may degrade to tofu. **Fix**: bundle a CJK fallback `.ttf` for exports. **Smoke**: no (visual).

### Design notes (not defects)

- `game.gd:398-411` `tr_args` translates **every** string arg — correct today because all callers pass raw names/keys, but an already-localized arg would double-translate. Worth a comment pinning the invariant.
- `hud.gd:2269` elements, `game.gd:3742` `WORK_ABBR` glyphs, `game.gd:3753` stances, `kin.gd:871` ailments — all dynamic keys exist in CSV (L353-365, L901-903). ✓
- `src/data/items.gd` `desc` fields, `species_gen.gd` `desc` fields, `work.gd:20` `WORK_LABEL` — dead data, never rendered. Not leaks.
- `hud.gd` raw draws `"»"` (:1210), `"X"` (:1393), touch glyphs (`···`, `≡`), `E`/`ATK`-style button letters — acceptable control/icon glyphs, not prose.
- `kin.gd:138` `str(dmg) + "!"` — numeric floater, not prose.
- `hud.gd:1628` `中文`/`EN` — deliberate self-describing labels.
- `net.gd:1496` `tr("[friend] ") + line` — `line` is user chat text (correctly untranslated).
- `hud.gd:2284` `work_str(sp).left(10)`, `:2289` `str(tr(...)).left(18)` — post-tr() truncation; CJK counts 1 char each, caps are generous. Acceptable.

## Smoke coverage (`tools/smoke_test.gd:6749-6815`)

Already asserted: zh locale registered; `tr()` output (`SETTINGS`→`设置`, batch rows); `net_note`/`net_floater`/`note_remote` localize key + args; hostile arg coercion; CSV structural lint — 3 columns, dup msgids, sorted placeholder-signature parity after `%%` strip, lone-`%` reject; missing-key fallback; `bad lang` fallback; en restore.

**Not covered** (what the findings above need):
- Call-site coverage lint: every `tr("literal")` in `src/*.gd` must exist as a CSV row (would have caught `clink!`, `can't see a line`, `, `, `%d-%d / %d`, `OK`).
- Dead-key lint: CSV keys with no producing call site.
- Arg-translation lint: `tr(...) % <identifier>` where the identifier is a raw `["name"]`/id field rather than `tr(str(...))` — the dominant defect class here (7 HIGH rows).
- `zh≠en` check for prose rows (guards regressions where someone leaves English in the zh column).
- Guide parity assertion (`PAGES_ZH.size() == PAGES.size()`).

## Summary

| Severity | Count | Class |
|---|---|---|
| HIGH | 7 | untranslated `%s` args (structure/skill/item/perk names), unwrapped data strings, unwrapped ternary branch |
| MED | 12 | raw ids/names interpolated, missing keys, raw fragments, unlocalized mode names, wire-arg inconsistency |
| LOW | 6 | `OK` button, identical-fallback missing keys, dead CSV rows, CJK font supply risk |

**Verdict**: Plumbing is solid — selection, persistence, live re-render, wire protocol, guide, font chain, and CSV structure are all correct-by-design. The launch risk is concentrated in **argument localization**: the format strings translate correctly, but the nouns inserted into them (structure/skill/item/perk names, ids) frequently bypass `tr()`, leaking English into zh. Fixes are mechanical and individually small; the missing piece is a call-site coverage lint that would have flagged most of them at build time.

## Recommended fix order

1. Add the two smoke lints (tr-key ⊆ CSV-key; dead-key) — they convert this report's MED/LOW class into a failing build before it ships.
2. Wrap display-name args at the 7 HIGH sites (structures, skills, items, perks, base-mission text, boss-stirrs string, +CSV rows where missing).
3. Fix the MED arg leaks (ids → `tr(str(display_name))`; mode/perk-name keys; raid-howl; `Out of %s`/`Equipped %s` word-order keys).
4. Tidy LOW (`OK`, `, `, `%d-%d / %d`, `Lv%d %s`, prune dead rows, decide on bundled CJK font for export).
```

---

## Handoff notes for the parent agent

- **File write required**: I could not create `/Volumes/17333023680/Game/PLG/docs/reviews/audit-44-localization-draft.md` (Explore mode is read-only). Write the Markdown block above verbatim to that path and print it to stdout.
- **Smoke suite not run** — evidence is from static inspection only; no execution.
- All file:line references verified by direct reads during this session.
- One caveat to relay: the CSV "no English prose left in zh" claim is based on a full read of the file; the smoke lint verifies structure at runtime but cannot detect semantic untranslatedness — recommend the `zh≠en` assertion noted in the report.