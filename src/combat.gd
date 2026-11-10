class_name Combat
# Battle formulas ported from the TS prototype (combat.ts), calibrated
# against the island-Win64-Shipping.exe FNames (CalcCaptureRate chain verified).

static func stat_at(base: float, level: int, talent: int = 0) -> float:
	return base * (1.0 + (level - 1) * 0.08) * (1.0 + talent * 0.002)

static func effectiveness(atk_elem: String, def_elems: Array) -> float:
	var m := 1.0
	for d in def_elems:
		m *= ElementData.CHART.get(atk_elem, {}).get(d, 1.0)
	return m

static func damage(atk: float, power: float, def: float, mult: float, rng: Rng) -> int:
	var raw := power * (2.0 * atk) / maxf(1.0, atk + 2.0 * def)
	return maxi(1, int(round(raw * mult * (0.9 + rng.next() * 0.2))))

static func catch_chance(hp_frac: float, capture_power: float, sphere_power: float,
		has_status: bool, behind: bool, capture_level: int) -> float:
	var hp_factor := 1.8 - 1.3 * hp_frac
	var status_bonus := 1.2 if has_status else 1.0
	var back_bonus := 1.15 if behind else 1.0
	var cap_lv := 1.0 + 0.04 * (capture_level - 1)
	var raw := (sphere_power * hp_factor * status_bonus * back_bonus * cap_lv) / (capture_power * 1.6)
	return clampf(raw, 0.03, 0.97)

# raid escalation lives here so the sim gates REAL math, not a local copy:
# game.start_raid and tools/sim_balance.gd both call these — a gate over a
# mirror formula proves nothing about the shipped curve
static func raid_day_bonus(day: int) -> int:
	# the curve squares with day so a day-one wave is survivable on a wooden
	# club and a lamb, while deep-campaign raids still out-level slack bases
	return mini(day * day / 20, 25)

static func raid_wave_bonus(day: int) -> int:
	# wave size floor: 3 + rng(0..2) + this — saturates at +4 by day 16
	return mini(day / 4, 4)

static func cap_power(base: float, lv: int, lucky := false) -> float:
	# luckies resist; the real gate is level — a lv50 shrugs off a ball that
	# would bag a lv5, which is what pushes the orb ladder
	return base * (1.35 if lucky else 1.0) * (1.0 + 0.05 * maxf(0.0, lv - 1.0))
