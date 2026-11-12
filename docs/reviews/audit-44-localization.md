# Audit-44 — Localization Completeness (S91)

Cold-lens audit of i18n: `locale/zh.csv` integrity, `tr()` call-site coverage,
dynamic assembly, locale plumbing, CJK font path. Verdict: **7 HIGH + 12 MED +
6 LOW**, all code findings resolved this stage. Suite: 958 checks, 0 failures.

## Verdict on plumbing — correct by design (verified, not assumed)

- `zh.csv` is the single locale source (~960 rows, `keys,en,zh`); English is
  the msgid. Boot parses it into a `Translation` and registers `zh`.
- `settings.lang` coerced `en|zh`, persisted in `settings.cfg`, toggled from
  the settings row; panels re-render immediately (draw-time `tr()`).
- Wire protocol is right: English key + raw args travel; receivers localize
  (`net_note`/`net_floater` → `tr(msg) % tr_args(args)`).
- Guide is parallel-text (`PAGES`/`PAGES_ZH`, 9/9) not CSV.
- Font fallback chain (`PressStart2P` → system face) is desktop-correct.

## The defect class — argument localization

The format strings translated; the **nouns interpolated into them didn't**.
`tr("Built %s") % s["name"]` renders `建成了 Campfire` — one half of every
log line leaked English into zh.

**HIGH — all fixed**
- `Built %s` / `Demolished %s (50%% refund)` — structure names now `tr(str(...))`.
- `Base mission: ` + raw `BASE_MISSION_TEXT` — the data string now goes
  through `tr(str())` (rows existed, unwired).
- `A boss stirs again at its den` — the ternary else-branch was unwrapped
  and keyless; wrapped + row added.
- `sk["name"] + tr("!")` ×2 (burst/multi floaters) — skill name now `tr(str())`.
- `Equipped `/`Unequipped ` + raw item name → `+ tr(str(it["name"]))`.
- `Statue upgraded: %s Lv%d` interpolated the raw perk id — `PERK_LABEL`
  moved to `Game` (one source), log + panel share it.

**MED — all fixed**
- `Need to be at a %s` / `Player %d razed %s` — raw structure ids → display names.
- `Unlock %s in the tech tree first` — raw tech id → `StructureData.TECH` name lookup.
- `Out of ` + raw ammo id → `+ tr(str(item name))`.
- kin.gd ×3 (`burned out`, `took medicine`, `going BERSERK`) — `spec["name"]` → `tr(str())`.
- `Monitoring stand: %s pace` — raw mode name → `tr(str())` + Normal/Hard/Overdrive rows.
- Raid howl — `Iron Pact squad` / `%s pack` / `wild mob` all tr()'d; the theme
  arg is `tr(str(raid_theme))` so `Fire pack` → `火群`.
- `" and a lumenite shard"` / `"LUCKY "` raw fragments → `tr()` + rows.
- `+%s` floater interpolated a raw item id → display name.
- audit-43's own additions (`clink!`, `can't see a line to that mark`) shipped
  keys this time — the new lint is why they'll stay shipped.

**LOW** — `OK` button, `, ` joiner, `%d-%d / %d` pager, `Lv%d %s` kin rows —
wrapped and keyed. `tr_args` invariant pinned in a comment (raw keys/ids in,
never pre-translated text — double-translate hazard).

## The lints that now guard the whole class

Four new assertions in the i18n block — the audit's actual deliverable, since
this defect class is mechanical and recurring:

1. **Coverage lint** — every literal `tr("key")` under `src/` must exist as a
   `zh.csv` row. First run caught the drifted party-row format immediately.
2. **Dead-key lint** — a `zh.csv` key that appears nowhere in `src/` is drift.
   Pruned 8 stale rows (`OFF`, `SPD`, `GLOW`, old formats/hints).
3. **zh≠en prose lint** — identical columns with a ≥4-letter English run flag
   untranslated rows (brand/formats whitelisted).
4. **Guide parity** — `PAGES.size() == PAGES_ZH.size()`.

Plus the slam-guest fixture learned the audit-43 lesson it needed (a ghost
inside the ring must sit on a sight-clear lane).

## Deferred

- **Bundled CJK font for export** — desktop falls back to the OS face
  correctly; stripped export targets (esp. web) may tofu. Bundling a CJK
  subset font is an asset-size decision for the export stage.
