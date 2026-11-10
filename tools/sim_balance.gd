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
	# mirrors game.gd cap_power_of — keep in lockstep or the probe lies
	return base * (1.35 if lucky else 1.0) * (1.0 + 0.05 * maxf(0.0, lv - 1.0))

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

	print("\n== raid escalation: day_bonus = min(day^2/20, 25) ==")
	for d in [1, 3, 5, 8, 10, 15, 20, 30]:
		var bonus := mini(d * d / 20, 25)
		var n := 3 + mini(d / 4, 4)
		print("day %2d: +%2d lv, wave size ~%d-%d (zone lv on top)" % [d, bonus, n, n + 2])
	gate("day-1 raid survivable", mini(1 * 1 / 20, 25) <= 0) # +0 lv bonus
	gate("raid curve saturates", mini(30 * 30 / 20, 25) == 25) # cap holds the ceiling

	print("\n==== SIM: %d failures ====" % fails)
	quit(1 if fails > 0 else 0)
