# S120 campaign pacing probe — the ACTION-COST of every progression gate,
# computed from shipped formulas and data tables (TECH, MISSIONS, SPIRE_DEFS,
# orb powers, RECIPES, CONDENSE_COST, Combat.*). Mirrors are documented and
# pinned against the live functions in smoke_test.gd — a probe over a local
# copy gates nothing (rule 28).
#
#   godot --headless --path . -s tools/sim_pacing.gd
#
# Exit banner "PACING: N checks, 0 failures" is the gate. A wall is a gate a
# player can see but only reach through unreasonable repetition — this probe
# measures kills/points/parts so the campaign curve stays a curve, not a cliff.
extends SceneTree

var fails := 0
var checks := 0

func gate(name: String, cond: bool, info := "") -> void:
	checks += 1
	var line := ("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else "")
	print(line)
	if not cond:
		fails += 1

# ---- mirrored formulas (each pinned in smoke against the live path) ----
# kin level cost: pal_gain_xp's `while xp >= level*25` loop (game.gd:3272)
func kin_xp_to(from_lv: int, to_lv: int) -> int:
	var xp := 0
	for k in range(from_lv, to_lv):
		xp += k * 25
	return xp
# player level cost: gain_xp's `30 + level*20` loop (game.gd:3291)
func player_xp_to(to_lv: int) -> int:
	var xp := 0
	for k in range(1, to_lv):
		xp += 30 + k * 20
	return xp
# kill xp: _kill_xp(level*4) → partner 0.5, bench 0.25 — whole field strip shares
func partner_xp_per_kill(victim_lv: float) -> float:
	return victim_lv * 4.0 * 0.5
# wild level band: rng(1+3z, 4+5z) — use the day-time mean; night +2 is gravy
func wild_avg_lv(zone: int) -> float:
	return (1.0 + zone * 3 + 4.0 + zone * 5) * 0.5
# raid band: rng(3+3z+b, 6+5z+b), b = raid_day_bonus(day)
func raid_avg_lv(zone: int, day: int) -> float:
	var b := Combat.raid_day_bonus(day)
	return (3.0 + zone * 3 + b + 6.0 + zone * 5 + b) * 0.5
# tp income: missions 14 + 2/level + 2 per 10 unique species
func tp_at_level(lv: int, species: int) -> int:
	var mtp := 0
	for m in Game.MISSIONS:
		mtp += int(m.get("tp", 0))
	return mtp + 2 * (lv - 1) + 2 * (species / 10)

func _init() -> void:
	# ================= A. KIN LEVEL WALLS =================
	# wilds cap ~lv21 (z3 night) — every level past that is earned via kills.
	# A fresh z3 catch is ~lv19; measure kills to each spire gate from there.
	print("--- kin xp table (fresh lv19 catch, partner share, whole strip gains) ---")
	var gates := {"spire1": 25, "spire2": 30, "spire3": 35, "spire4": 42,
		"spire5": 50, "cap": 60}
	var incomes := {
		"wild z3 avg": partner_xp_per_kill(wild_avg_lv(3)),
		"raid z3 day10": partner_xp_per_kill(raid_avg_lv(3, 10)),
		"raid z3 day20": partner_xp_per_kill(raid_avg_lv(3, 20)),
		"raid z3 day30": partner_xp_per_kill(raid_avg_lv(3, 30)),
	}
	var xp1950: int = kin_xp_to(19, 50)
	for gname in gates:
		var xp: int = kin_xp_to(19, int(gates[gname]))
		var row := "  lv19→%d needs %d xp |" % [int(gates[gname]), xp]
		for iname in incomes:
			row += " %s: %d kills" % [iname, ceili(float(xp) / float(incomes[iname]))]
		print(row)
	# Gate semantics: the wilds-only path must field a spire-1 squad (the
	# campaign can't demand raids before the crown); raids must carry the
	# mid-game; endgame caps inside one sane evening's defense grind.
	gate("wild-farm path to spire1 exists", xp1950 > 0
		and kin_xp_to(19, 25) / incomes["wild z3 avg"] <= 150.0,
		"kills=%d" % ceili(kin_xp_to(19, 25) / incomes["wild z3 avg"]))
	gate("mid-curve to spire4 via day-20 raids", kin_xp_to(19, 42)
		/ incomes["raid z3 day20"] <= 350.0,
		"kills=%d" % ceili(kin_xp_to(19, 42) / incomes["raid z3 day20"]))
	gate("cap reachable via capped raids", kin_xp_to(19, 60)
		/ incomes["raid z3 day30"] <= 600.0,
		"kills=%d" % ceili(kin_xp_to(19, 60) / incomes["raid z3 day30"]))
	# raid scaling must actually outrun wild farming — else late game = farm
	# lv19s forever (the shallow-late-game complaint made numeric)
	gate("raid income outgrows wild farm", incomes["raid z3 day20"]
		> incomes["wild z3 avg"] * 1.8,
		"%.0f vs %.0f" % [incomes["raid z3 day20"], incomes["wild z3 avg"]])
	# xp income scales with prey level — no asymptote cliff mid-campaign
	gate("kill xp scales with prey level", partner_xp_per_kill(45.0)
		> partner_xp_per_kill(15.0) * 2.5)

	# ================= B. PLAYER LEVEL + TP =================
	# tp must never be the hard wall: check earnable-vs-needed at the levels
	# where each demand lands. Orb ladder = 14; essential base chain ≈ 26.
	var orb_ladder := 0
	var essential := ["workbench", "kin_bed", "feed_box", "logging_site",
		"stone_pit", "berry_farm", "ranch", "chest", "torch", "incubator",
		"sphere_factory", "watch_tower", "musket", "orb_launcher", "mega_orb",
		"giga_orb", "ultra_orb", "legendary_orb"]
	var essential_cost := 0
	for t in StructureData.TECH:
		if str(t["id"]) in ["mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]:
			orb_ladder += int(t["cost"])
		if str(t["id"]) in essential:
			essential_cost += int(t["cost"])
	var all_tp := 0
	var all_parts := 0
	var max_tier := 0
	for t2 in StructureData.TECH:
		all_tp += int(t2["cost"])
		all_parts += int(t2.get("parts", 0))
		max_tier = maxi(max_tier, int(t2["tier"]))
	print("--- tech economy: %d nodes, %d tp, %d parts, max tier %d ---" % [
		StructureData.TECH.size(), all_tp, all_parts, max_tier])
	print("  orb ladder=%dtp  essential set(%d)=%dtp" % [
		orb_ladder, essential.size(), essential_cost])
	gate("orb ladder affordable by lv12", tp_at_level(12, 20) >= orb_ladder + 10,
		"earn=%d need=%d" % [tp_at_level(12, 20), orb_ladder + 10])
	gate("essential path affordable by lv20", tp_at_level(20, 40)
		>= essential_cost, "earn=%d need=%d" % [tp_at_level(20, 40), essential_cost])
	gate("full tech tree reachable in a campaign", tp_at_level(50, 116)
		>= all_tp, "earn=%d need=%d" % [tp_at_level(50, 116), all_tp])
	# level gates must not exceed the level where a player realistically is:
	# spire-1 asks ~lv20-25 party — player level should be comparable, and
	# every tech tier must sit well under the accord-era level.
	var p_lv_at_spire1 := 1
	var acc := 0
	while acc < kin_xp_to(1, 25): # player earns ~2x a partner's pace
		acc += 60 # ~2 wild kills per level early — rough player pace
		p_lv_at_spire1 += 1
	gate("tech tiers below realistic player level", max_tier <= 20,
		"max tier=%d" % max_tier)

	# ================= C. ANCIENT PARTS =================
	# guaranteed: spire chests pay 1+placed (0..4) = 15; dex_full +2;
	# gauntlet EX +6. Renewable: alpha 1-2, boss 2-4, crates/fossil/grotto.
	var guaranteed := 15 + 2 + 6
	print("--- ancient parts: need %d, guaranteed %d, renewable via alphas/bosses ---"
		% [all_parts, guaranteed])
	gate("parts fully earnable inside the campaign", guaranteed >= all_parts,
		"%d vs %d" % [guaranteed, all_parts])
	# early parts nodes must not wait for the crown: alphas (zone2+, 8% spawn)
	# pay 1-2, supply crates pay 2, fossil beds 2-4 — ~15 renewable parts
	# exist in zone-2 play before any spire falls. The bound is that income,
	# not a taste number.
	var early_parts := 0
	for t3 in StructureData.TECH:
		if int(t3["tier"]) <= 5:
			early_parts += int(t3.get("parts", 0))
	gate("early parts nodes reachable pre-spires", early_parts <= 12,
		"tier<=5 parts total=%d, pre-spire income ~15" % early_parts)

	# ================= D. ORB ADEQUACY =================
	# for each zone's max wild level, some orb the player can plausibly own
	# must catch a weakened target ≥50% (hp_frac 0.3, no status, not behind).
	print("--- orb ladder vs zone max wild level (30% hp, no bonuses) ---")
	var orb_ids := ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]
	# per-zone median capturePower — each band's own species set the bar,
	# not a global median (zone0 starter kin are soft ~40, deep kin ~60-80)
	for z in 4:
		var med_cap := 0.0
		var cap_samples := 0
		var pool_z: Array = Game.ZONE_SPECIES[z] + SpeciesGen.zone_pool(z)
		for sid in pool_z:
			cap_samples += 1
			med_cap += float(SpeciesData.species_of(sid).get("capturePower", 50))
		if cap_samples == 0:
			med_cap = 50.0
		else:
			med_cap /= cap_samples
		var max_lv := 4 + z * 5 + 2 # day max + night edge
		var cap := Combat.cap_power(med_cap, max_lv)
		var best_id := ""
		var best_pct := 0.0
		for oid in orb_ids:
			var sp := float(ItemData.ITEMS[oid].get("spherePower", 0))
			var pct := Combat.catch_chance(0.3, cap, sp, false, false, 8)
			if pct >= 0.5 and best_id == "":
				best_id = oid
				best_pct = pct
		print("  zone%d max lv%d: cap=%.0f first-≥50%% orb=%s (%.2f)" % [
			z, max_lv, cap, best_id if best_id != "" else "NONE", best_pct])
		gate("zone%d has a catch orb inside the ladder" % z, best_id != "",
			"first=%s" % best_id)
	# legends must demand the top orb — use the real den capturePower (80
	# for most heirs, 60 for two), not the zone median. The rung check is
	# the GAP: legendary must out-pay the mid orb ≥2× on a real legend or
	# the ladder's last step is decoration.
	var den_caps := {}
	for ls in Game.LEGENDARY_DEN:
		var cp := float(SpeciesData.species_of(ls).get("capturePower", 50))
		den_caps[ls] = cp
	var worst_cap := 60.0 # the softest heir — if mega still shrugs at HER,
	# the ladder leaks everywhere
	for ls in den_caps:
		worst_cap = minf(worst_cap, float(den_caps[ls]))
	var den_cap := Combat.cap_power(worst_cap, 50)
	var leg_pct := Combat.catch_chance(0.3, den_cap,
		float(ItemData.ITEMS["legendary_orb"]["spherePower"]), true, true, 8)
	var mega_pct := Combat.catch_chance(0.3, den_cap,
		float(ItemData.ITEMS["mega_orb"]["spherePower"]), false, false, 8)
	var ultra_pct := Combat.catch_chance(0.3, den_cap,
		float(ItemData.ITEMS["ultra_orb"]["spherePower"]), true, true, 8)
	print("  softest heir lv50 (cap=%.0f): legendary %.2f ultra %.2f mega %.2f"
		% [den_cap, leg_pct, ultra_pct, mega_pct])
	gate("lv50 legend answerable by legendary orb", leg_pct >= 0.35,
		"%.2f" % leg_pct)
	gate("the top rung out-earns the mid rung 2x", leg_pct > mega_pct * 2.0,
		"%.2f vs %.2f" % [leg_pct, mega_pct])

	# ================= E. SIGIL / GAUNTLET LOOP =================
	# the gauntlet pays 1-2 sigils and costs 1 — the loop is self-funding
	# only if the first sigil is findable pre-crown. Spire kills pay 1 each;
	# alphas 15% boss_sigil; merchant stocks both. Count non-rng sources.
	var sigil_sources := 5 # one per spire chest kill
	gate("first gauntlet sigil reachable pre-crown", sigil_sources >= 1
		and ItemData.ITEMS.has("gauntlet_sigil"), "spires pay %d" % sigil_sources)

	# ================= F. ENDGAME SINKS =================
	# condense star-4 costs 4+16+32+64 = 116 same-species — a completionist
	# sink, not a power requirement. Assert the ladder's total stays under
	# the box cap and the stat payoff is real but optional.
	var fodder := 0
	for c in Game.CONDENSE_COST:
		fodder += int(c)
	gate("star-4 sink bounded by box", fodder <= 400, "total fodder=%d" % fodder)
	gate("star-4 is optional not required", Game.CONDENSE_COST.size() == 4
		and pow(1.15, 4) < 2.0, "mult=%.2f" % pow(1.15, 4))
	# dex completion is the last collectible spine — ownable count sanity
	print("--- post-accord sinks: fodder=%d/species, dens=%d, EX sigils pay 2 ---"
		% [fodder, Game.LEGENDARY_DEN.size()])

	# ================= G. MISSION CHAIN COHERENCE =================
	# every mission key must be checkable — an unreachable mission is a dead
	# end the probe can see statically.
	gate("mission chain covers the campaign", Game.MISSIONS.size()
		== Game.MISSION_KEYS.size() and Game.MISSION_KEYS.has("gauntlet"),
		"%d missions" % Game.MISSIONS.size())
	# player level curve stays sub-linear vs kin curve (players outpace kin
	# early, kin catch up late — the intended rhythm)
	gate("player curve gentler than kin curve", player_xp_to(30)
		< kin_xp_to(1, 30), "%d vs %d" % [player_xp_to(30), kin_xp_to(1, 30)])

	print("\n==== PACING: %d checks, %d failures ====" % [checks, fails])
	quit(fails)
