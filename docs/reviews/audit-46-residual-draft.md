# Audit 46 — Residual Sweep (draft)

Read-only cold-context audit of the Godot 4.7.2 creature-capture game. Scope: first-ten-minutes onboarding truth, net protocol completeness, content-data consistency, boss/campaign softlocks, and any other real defect — minus areas already proven by `tools/smoke_test.gd` (~960 checks) and prior audits 33–45.

Method: direct source inspection with end-to-end trace per claim; every finding carries `file:line` evidence.

---

## Findings

### HIGH

**1. Ten tech-tree nodes are purchasable no-ops — the whole orb ladder, guns, and orb launcher are free-craftable from day 1**

- `file:line`: gate lives only in the recipe row — `src/game.gd:3116` (`if r.get("tech", "") != "" and r["tech"] not in techs:`) and the craft-panel mirror `src/hud.gd:1820` (`if rec.get("tech", "") != "" and rec["tech"] not in game.unlocked:`). Nothing reads `ItemData.ITEMS[x]["tech"]` (verified by grep — the only two `"tech"` consumers are those two lines).
- Evidence: these `ItemData.RECIPES` rows have **no `"tech"` field**: `bow` (`src/data/items.gd:1143`), `arrow` (1162), `musket` (1181), `tranq_gun` (1204), `tranq_dart` (1227), `musket_ball` (1246), `orb_launcher` (1265), `mega_orb` (1381), `giga_orb` (1404), `ultra_orb` (1427), `legendary_orb` (1454). The matching `StructureData.TECH` rows still charge the player: `bow` (`src/data/structures.gd:1216`, tier 2, 2pt), `arrow` (1228, 1pt), `mega_orb` (1356, 2pt), `giga_orb` (1386, 3pt), `musket` (1398, 3pt+3 parts), `tranq_gun` (1405, 2pt+1 part), `musket_ball` (1425, 1pt), `ultra_orb` (1438, 4pt), `legendary_orb` (1444, 5pt), `orb_launcher` (1482, 2pt+2 parts). `unlock()` (`src/game.gd:3070-3091`) happily debits tech points and `ancient_part` and appends the id to `unlocked` — which nothing then consults for these ids. Item rows carry a **dead** `"tech"` key at `src/data/items.gd:509,521,532,543,584,601,618,686,733,743,753,850,872,883,894,905,916,927,938,949,960`; the keys that *do* work (`spear` 1124, `axe` 1289, `pick` 1309, equipment 1778–1873) are on the recipe rows, proving the intended shape.
- Impact: two-sided defect. (a) Players burn 23 tech points + 6 boss-drop `ancient_part` on nodes that unlock literally nothing. (b) `legendary_orb` — the intended tier-8 capstone gating legend-heir catches via `Combat.catch_chance`/`cap_power` (`src/combat.gd:18-42`) — plus `musket`, `tranq_gun`, `orb_launcher`, and all mid-tier orbs are craftable at any workbench with raw materials, collapsing the intended capture/gear progression and the ancient-parts economy. Player-visible in the first workbench session.
- Suggested fix: add `"tech": "<tech-id>"` to each of the 11 recipes above (mirroring the `spear`/`saddle` pattern), or have `craft()` and the HUD filter fall back to `ItemData.ITEMS[rec["out"][0]].get("tech")`. Then delete or repurpose the dead item-level `"tech"` keys.

### MED

**2. Guests can never see (and therefore never craft) tech-gated recipes — the craft panel filters on the wrong tech list**

- `file:line`: `src/hud.gd:1820` (`rec["tech"] not in game.unlocked`) vs. `src/game.gd:3114-3115` (`var techs: Array = net_unlocked if (net != null and net.is_client() and not net_unlocked.is_empty()) else unlocked`).
- Evidence: a client's `unlocked` stays the static starter list `src/game.gd:69` (`["kinbox","kin_bed","feed_box","campfire","workbench","straw_bed"]`) — `unlock()` is `client_locked()` (`src/game.gd:3071`) and host tech arrives only in `net_unlocked` (`src/net.gd:321`, `state_sync`). So `draw_craft` hides every recipe whose `"tech"` isn't a starter structure: spear, axe, pick, all three saddles, glider, grappling_hook, meat_cleaver, all four partner gears. `craft()` *would* accept them (it honors `net_unlocked`), but the button is never drawn.
- Impact: LAN guests are silently denied the gated half of the crafting table on developed islands. Combined with finding 1, the inversion is glaring: a guest can craft a `legendary_orb` but not a `spear`.
- Suggested fix: in `draw_craft`, filter with the same `techs` expression `craft()` uses (`net_unlocked` when client, else `unlocked`).

**3. Kin gacha price is described three different ways — two of them lie**

- `file:line`: `src/game.gd:7438` (`const GACHA_COST := 45`, enforced 7443-7446 and remote `gacha_req_remote` 7454+); structure desc `src/data/structures.gd:572` ("feed it 20 gold"); guide `src/data/guide.gd:157` ("takes thirty gold a pull"; ZH page mirrors it).
- Evidence: `gacha_pull()` refuses under 45 coins; the structure card and the field guide both quote lower prices.
- Impact: player-facing teaching surfaces misstate a paid economy verb by >2×; players stand at the machine with 30 gold and get a refusal.
- Suggested fix: interpolate `GACHA_COST` into the structure desc at build time and correct the guide text to 45 in `PAGES` and `PAGES_ZH`.

### LOW

**4. Kindex habitat is blank for every species outside `SpeciesGen.ZONE`**

- `file:line`: `src/data/species_gen.gd:4656-4671` (`ZONE` pools + `habitat()` returns `-1` for unlisted ids).
- Evidence: legends `scalcrest`/`vermtrot` are in `LEGENDARY_DEN` (`src/game.gd:6399-6400`) but in no zone pool; all core `src/data/species.gd` species (cindlump, fenlump, corlmite, ironpact, sand_stalker…) likewise. The dex panel (`src/hud.gd:2307+`) prints the glyph but no habitat band for them.
- Impact: cosmetic — some dex rows lack habitat data while others have it.
- Suggested fix: treat `-1` as "dens/special" label, or extend `ZONE`/habitat with a special-provenance bucket.

### INFO — verified correct (excerpts; full inventory below)

- All 10 missions have live completion paths (`src/game.gd:1304-1369`): `kinbox`/`logger`/`ranch`/`bed` via `has_structure`, `catch3` via `total_catches`, `deploy` via `base_pals`, `orb` via `note_crafted` called from both instant and queued craft paths (`src/game.gd:3151,3231`), `elite` on alpha-or-boss kill (`src/game.gd:1042-1043`), `egg` on bred-egg hatch (`src/game.gd:5704`), `gauntlet` on clear (`src/game.gd:1284`). Starter kit (3 `kin_orb` + 4 `lumenite`) exactly funds the kinbox cost (`src/data/structures.gd:12-25`).
- All 8 hints reachable and accurate (`src/game.gd:2489-2531`): verb text matches `project.godot` input map and `bind_gamepad` (`src/game.gd:2455-2477`); kinbox/campfire cost text exact-matches structure defs; `active_hints()` caps at 3 and retires on `once` (`src/game.gd:2536-2551`).
- Help overlay (`src/hud.gd:1194-1211`) correctly documents every verb incl. ride/partner-skill/statues/kindex/chat and the gamepad row; guide six-slot text matches `party_cap()` post-Accord (`src/data/guide.gd:95,261` vs `src/game.gd:1415-1418`).
- Net protocol: `state_sync` razes-and-rebuilds structures before kin, lands decor first (`src/net.gd:294-358`); `pal_sync` carries pos/hp/level/mode/lucky/boss/alpha/spire_tag/mounted_by/owner_id/soul_boost with seen-set despawn, mount unbind, and self-heal (`src/net.gd:364-438`); `env_sync` ships weather/danger/board-quest/spire/den tallies (`src/net.gd:441+`); join-mid-raid covered — raiders are ordinary `pals` rows plus `net_danger`; disconnect clears the mirror (`src/net.gd:521`).
- Gauntlet: per-tick reconciliation of `left` against live `gauntlet`-meta raiders, voids cleanly on mass-despawn, never scores an empty wave, EX apex for crowned, refunds the sigil (`src/game.gd:1194-1286`).
- Kinbox anchor: last anchor undemolishable, outpost promotion via `_kinbox_anchor_gone`, both `place` and `place_free` maintain `kinbox_pos`/`extra_boxes` (`src/game.gd:2850-2967`).
- Data: all 95 generated species use only the 28 real skill ids, valid elements, valid item drops; dual speed scale normalized in `base_move_speed` (`src/kin.gd:104-110`); `acq_pool`/`ownable`/`LEGENDARY_DEN`/`SPIRE_DEFS` consistent; `Migrate` remaps every legacy id shape incl. egg pairs and ranch stores (`src/data/migrate.gd`); all 16 procedural SFX keys exist (`src/game.gd:254-272`); `MERCH_POOL` ids all valid.
- Schematics are *not* dead: `schematic_bow`/`schematic_musket` gate `bow_mk2`/`musket_mk2` via `"req"` (`src/data/items.gd:1819,1827`, enforced `src/game.gd:3124-3127`).

---

## Findings table

| # | Sev | File:line | Defect |
|---|-----|-----------|--------|
| 1 | HIGH | `items.gd:1143-1483` + `structures.gd:1216-1487` + `game.gd:3116` + `hud.gd:1820` | 10 tech nodes are no-ops; orb ladder/guns/launcher free-craftable |
| 2 | MED | `hud.gd:1820` vs `game.gd:3114` / `net.gd:321` / `game.gd:69` | Guest craft panel filters on starter `unlocked`; gated recipes unreachable though `craft()` would accept |
| 3 | MED | `structures.gd:572` / `guide.gd:157` / `game.gd:7438` | Gacha desc says 20g, guide says 30g, code is 45g |
| 4 | LOW | `species_gen.gd:4656-4671` | Dex habitat blank for legends `scalcrest`/`vermtrot` and all core species |

## Verified-correct inventory

Onboarding: mission chain (10/10 live flags), hints (8/8 reachable, verbatim-cost-accurate), starter kit solvency, help overlay verb completeness, guide EN/ZH parallel, day-1 half-rate clock, gamepad binding coverage (dpad verbs incl. demolish/swap).
Protocol: `state_sync` ordering, `pal_sync` replica lifecycle + mount/owner/soul fields, `env_sync` campaign+weather+quest truth, `stock_sync` id validation, `net_danger` join/teardown, fail-closed ghost proximity (`net_place`, `harvest_req`), client bag trust boundary documented.
Content: species/skills/elements/drops cross-consistency, zone pools, `acq_pool`/`ownable` legend+human gates, recipe cost/output ids, structure `w/h/cost/anchor` fields, merchant pool ids, migrate id coverage.
Campaign: gauntlet self-heal + void path, kinbox anchor promotion + last-anchor lock, spire tally clamps, Accord three-seal gate, den/raid flags in sync payloads, sigil host-only refusal with refund semantics.
Systems: schematic `req` gating, partner-gear gating, dual species stat scales, procedural audio bank completeness, bounded collections, sleep/danger truth-gate non-memoized.

---

### Notes for the parent agent

1. **Write this content to** `/Volumes/17333023680/Game/PLG/docs/reviews/audit-46-residual-draft.md` — I had no write tools.
2. Finding 1 (HIGH) is the headline: the fix is a ~11-line data change adding `"tech"` keys to recipes in `src/data/items.gd`; consider whether the item-level `"tech"` keys should drive the check instead — either direction resolves it, but the dead TECH purchases must stop.
3. Finding 2 is a one-word-class fix in `hud.gd:1820` (use the `net_unlocked`-aware list).
4. I did not run the smoke suite (no exec permission granted); coverage was assessed by reading `tools/smoke_test.gd` check names — none of the four findings are asserted there (the suite asserts `craft club`/`timed crafting`/`tech unlock` mechanics but never asserts a recipe requires tech, so finding 1 is not contradicted).
5. Surfaces I could not fully exhaust within budget and that merit a follow-up look if a 47th audit happens: `kin.gd` work/AI tick internals (~1068 lines read partially), `world.gd` POI placement edge cases beyond the audit-42 fixes, `hud.gd` touch `draw_touch` rect-table completeness, and ZH guide parity line-by-line (spot-checked only).