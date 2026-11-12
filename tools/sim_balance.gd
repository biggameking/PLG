extends SceneTree
# Offline balance probe — runs the REAL catch/raid/xp formulas over a grid and
# fails loudly when the numbers drift outside sane bounds. No world, no sim —
# just the math a playtest would take hours to surface.
#
#   godot --headless --path . -s tools/sim_balance.gd
#
# Exit banner "SIM: N checks, 0 failures" is the gate.

var Combat := preload("res://src/combat.gd")
var ItemData := preload("res://src/data/items.gd")
var SpeciesData := preload("res://src/data/species.gd")
var SpeciesGen := preload("res://src/data/species_gen.gd")

var fails := 0
func gate(name: String, cond: bool, info := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not cond:
		fails += 1

func cap_pow(base: float, lv: int, lucky := false) -> float:
	return Combat.cap_power(base, lv, lucky) # the shipped formula, not a mirror

func pct(hp_frac: float, cp: float, sp: float, st := false, bh := false, cl := 1) -> float:
	return Combat.catch_chance(hp_frac, cp, sp, st, bh, cl) * 100.0

func _init() -> void:
	var orbs := []
	for oid in ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]:
		if ItemData.ITEMS.has(oid): # powers come from data — a hardcoded probe lies
			orbs.append([oid, float(ItemData.ITEMS[oid].get("spherePower", 26))])
	print("== capture grid: chance%% = f(orb, level, hp) at cap_lv=1, front, no status ==")
	var lvs := [5, 15, 30, 50]
	print("%-15s %s" % ["orb\\lv", "  ".join(lvs.map(func(l): return "%3d" % l))])
	for o in orbs:
		var row := []
		for lv in lvs:
			# a mid-range target: capturePower 50 scaled by level
			row.append("%2.0f%%" % pct(0.25, cap_pow(50, lv), o[1]))
		print("%-15s %s" % [o[0], "  ".join(row)])

	print("\n== sanity gates ==")
	# early game must feel generous: starter orb, lv5, weakened
	gate("starter orb bags lv5 @25%", pct(0.25, cap_pow(35, 5), 26.0) >= 40.0,
		"%2.0f%%" % pct(0.25, cap_pow(35, 5), 26.0))
	# the ladder must matter: starter orb vs deep-zone lv50 at full HP is a prayer
	gate("starter orb fails lv50 @100%", pct(1.0, cap_pow(60, 50), 26.0) <= 8.0,
		"%2.0f%%" % pct(1.0, cap_pow(60, 50), 26.0))
	# top orb must answer the deepest catch: legendary orb, lv50, softened
	var leg_p := float(ItemData.ITEMS["legendary_orb"].get("spherePower", 110))
	gate("legendary orb lands lv50 @25%", pct(0.25, cap_pow(60, 50), leg_p) >= 45.0,
		"%2.0f%%" % pct(0.25, cap_pow(60, 50), leg_p))
	# status + backstab must each feel worth the setup (~+20%/+15%)
	var flat := pct(0.5, cap_pow(50, 15), 42.0)
	gate("status pays", pct(0.5, cap_pow(50, 15), 42.0, true) > flat,
		"%2.0f%% -> %2.0f%%" % [flat, pct(0.5, cap_pow(50, 15), 42.0, true)])
	gate("backstab pays", pct(0.5, cap_pow(50, 15), 42.0, false, true) > flat,
		"%2.0f%% -> %2.0f%%" % [flat, pct(0.5, cap_pow(50, 15), 42.0, false, true)])
	# lucky tax must not make kin uncatchable
	gate("lucky lv15 stays catchable", pct(0.25, cap_pow(50, 15, true), 58.0) >= 25.0,
		"%2.0f%%" % pct(0.25, cap_pow(50, 15, true), 58.0))

	print("\n== species capturePower spread ==")
	var cps := []
	for s in SpeciesData.SPECIES.values() + SpeciesGen.SPECIES.values():
		cps.append(float(s.get("capturePower", 50)))
	cps.sort()
	print("min %d  p25 %d  med %d  p75 %d  max %d" % [
		cps[0], cps[cps.size() / 4], cps[cps.size() / 2],
		cps[cps.size() * 3 / 4], cps[-1]])

	print("\n== raid escalation (real Combat formulas — no mirror copies) ==")
	for d in [1, 3, 5, 8, 10, 15, 20, 30]:
		var bonus := Combat.raid_day_bonus(d)
		var n := 3 + Combat.raid_wave_bonus(d)
		print("day %2d: +%2d lv, wave size ~%d-%d (zone lv on top)" % [d, bonus, n, n + 2])
	gate("day-1 raid survivable", Combat.raid_day_bonus(1) <= 0) # +0 lv bonus
	gate("raid curve saturates", Combat.raid_day_bonus(30) == 25) # cap holds the ceiling
	gate("wave size saturates", Combat.raid_wave_bonus(30) == 4)

	print("\n== catch-cost pacing: expected orbs to bag at @25% hp ==")
	var orb_p := {}
	for o2 in orbs:
		orb_p[o2[0]] = o2[1]
	var paces := [ # label, target lv, orb id, species capturePower, max orbs allowed
		["early", 8, "kin_orb", 40, 4],
		["mid", 30, "giga_orb", 50, 6],
		["deep", 50, "ultra_orb", 55, 7],
		["legend", 50, "legendary_orb", 65, 4],
	]
	for pc in paces:
		var ch: float = Combat.catch_chance(0.25, cap_pow(pc[3], pc[1]),
			orb_p[pc[2]], false, false, 1)
		var want := 1.0 / maxf(ch, 0.001)
		print("%-8s lv%-3d %s: %2.0f%% -> ~%.1f orbs" % [pc[0], pc[1], pc[2], ch * 100.0, want])
		gate("%s catch costs sane orbs" % pc[0], want <= float(pc[4]),
			"~%.1f orbs" % want)

	print("\n== roster power curve: turns-to-kill through real Combat.damage ==")
	var rng2 := Rng.new(0x5EED)
	var bases := []
	for s2 in SpeciesData.SPECIES.values() + SpeciesGen.SPECIES.values():
		bases.append(float(s2.get("atk", 60)))
	bases.sort()
	var med_atk: float = bases[bases.size() / 2]
	var med_def: float = bases[bases.size() / 2]
	var powers := []
	for sk in SkillData.SKILLS.values():
		powers.append(float(sk.get("power", 10)))
	powers.sort()
	var mid_power: float = powers[powers.size() / 2] # the roster's median hit, not a wish
	var ttk := func(atk_lv: int, def_lv: int) -> float:
		var hits := 0
		var hp := Combat.stat_at(70.0, def_lv) # median hp base
		while hp > 0.0 and hits < 90:
			hp -= Combat.damage(Combat.stat_at(med_atk, atk_lv), mid_power,
				Combat.stat_at(med_def, def_lv), 1.0, rng2)
			hits += 1
		return float(hits)
	var par: float = ttk.call(20, 20)
	var und: float = ttk.call(20, 35)
	var over: float = ttk.call(35, 20)
	print("median skill power %.0f | parity lv20v20 ~%.0f hits | under -15 ~%.0f | over +15 ~%.0f" % [mid_power, par, und, over])
	# invariants, not taste: parity must resolve in a sane window, an underdog
	# must still be able to fight, and levels must matter at all. The soft
	# damage ratio (atk/(atk+2def) saturates) means +15 is a grind, not a
	# stomp — a deliberate curve property worth watching, not a bug
	gate("parity duel resolves", par >= 4.0 and par <= 16.0, "%.0f hits" % par)
	gate("underdog -15 isn't hopeless", und >= par and und <= 40.0, "%.0f hits" % und)
	gate("levels still matter", over < par, "%.0f vs %.0f" % [over, par])
	gate("stat curve inflation bounded",
		Combat.stat_at(60.0, 60) / Combat.stat_at(60.0, 1) <= 6.5,
		"%.1fx" % (Combat.stat_at(60.0, 60) / Combat.stat_at(60.0, 1)))

	print("\n== skill kit pacing: no dead hatchlings, signatures at 20 ==")
	var kit_dead := 0
	var kit_nosig := 0
	var kit_dangle := 0
	var all_species := SpeciesData.SPECIES.values() + SpeciesGen.SPECIES.values()
	for s3 in all_species:
		var learns: Array = s3.get("skills", [])
		if learns.is_empty() or int(learns[0][0]) > 5:
			kit_dead += 1
		var has_sig := false
		for le in learns:
			if int(le[0]) == 20:
				has_sig = true
			if not SkillData.SKILLS.has(str(le[1])):
				kit_dangle += 1
		if not has_sig:
			kit_nosig += 1
	gate("every species fights by lv5", kit_dead == 0, "%d dead kits" % kit_dead)
	gate("every species has a lv20 signature", kit_nosig == 0, "%d missing" % kit_nosig)
	gate("no dangling skill ids", kit_dangle == 0, "%d bad refs" % kit_dangle)

	print("\n== element chart: rock-paper coverage ==")
	var elems: Array = ElementData.CHART.keys()
	var uncovered := []
	for de in elems:
		var counters := 0
		for ae in elems:
			if Combat.effectiveness(ae, [de]) >= 1.9:
				counters += 1
		if counters == 0:
			uncovered.append(de)
		var neut := Combat.effectiveness("neutral", [de])
		print("def %-8s counters=%d  neutral-vs=%.1f" % [de, counters, neut])
	gate("every element has a counter", uncovered.is_empty(), "uncovered: %s" % [uncovered])
	gate("neutral is honest 1x", Combat.effectiveness("neutral", ["dragon"]) == 1.0)

	print("\n==== SIM: %d failures ====" % fails)
	quit(1 if fails > 0 else 0)
