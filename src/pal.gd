extends Entity
class_name Pal
# A pal in the world: wild (wander/flee/aggro), partner (follows player,
# auto-attacks), or base worker (job site later).

var game: Game
var uid := 0
var species_id := ""
var level := 1
var xp := 0
var hp := 1.0
var max_hp := 1.0
var san := 80.0
var hunger := 0.0
var talent := 0
var mode := "wild"           # wild | partner | base
var statuses := {}           # kind -> until_t
var aggro := -1              # -1 none, 0 player, >0 pal uid
var wander_t := 0.0
var carry = null             # {id,n} while hauling
var home := Vector2.ZERO     # spawn anchor; alphas tether to their lair
var target := Vector2.ZERO
var atk_cd := 0.0
var spec: Dictionary = {}
var job_site = null
var sex := "M"
var alpha := false
var boss := false
var passives := []
var ai_accum := 0.0
var needs_t := 0.0
var skill_cd := {}
var stun_t := 0.0
var revive_t := 0.0         # >0 while knocked out in the box

func setup(g: Game, sp_id: String, lv: int, at: Vector2) -> void:
	game = g
	world = g.world
	species_id = sp_id
	spec = SpeciesData.species_of(sp_id)
	swims = "water" in spec.get("elements", [])
	level = lv
	talent = game.rng.int_range(0, 100)
	max_hp = Combat.stat_at(spec["hp"], level, talent)
	hp = max_hp
	san = spec.get("san", 80)
	pos = at
	target = at
	home = at
	speed = base_move_speed()
	uid = game.next_uid()
	sex = "M" if game.rng.chance(0.5) else "F"
	roll_passives()
	if alpha:
		hp = max_hp # apply_bonuses already folded the 4x into max_hp
	setup_visuals("res://assets/pals/%s_f0.png" % sp_id, "res://assets/pals/%s_f1.png" % sp_id)
	if alpha:
		sprite.scale = Vector2(1.6, 1.6)
		sprite.position.y = -51.0

func base_move_speed() -> float:
	# species.gd stores tiles/sec (2-3.5); species_gen.gd carries stat-scale
	# values (40-88+) — normalize both onto a sane tiles/sec curve
	var s: float = spec.get("speed", 2.6)
	if s > 10.0:
		return 1.8 + s * 0.035
	return s

func hostile() -> int:
	return spec.get("hostile", 1)

func add_status(kind: String, dur: float) -> void:
	statuses[kind] = game.t + dur

func has_status(kind: String) -> bool:
	return statuses.get(kind, 0.0) > game.t

func any_status() -> bool:
	for k in statuses:
		if statuses[k] > game.t:
			return true
	return false

func hit(dmg: int, mult: float, by_player: bool) -> void:
	hp -= dmg
	hit_flash = 0.4
	game.floater(pos, str(dmg) + ("!" if mult >= 2 else ("·" if mult <= 0.6 else "")),
		"#e8d44d" if mult >= 2 else "#e8f0f2")
	if hp <= 0:
		game.kill_pal(self, by_player)
	elif mode == "wild":
		statuses.erase("sleep")
		if hostile() == 0 and game.rng.chance(0.5):
			aggro = -1
		else:
			aggro = 0

func elem() -> Array:
	return spec.get("elements", ["neutral"])

func status_speed_mult() -> float:
	var m := 1.0
	if has_status("freeze"):
		m *= 0.5
	if has_status("soak"):
		m *= 0.7
	return m

func _physics_process(dt: float) -> void:
	if hp <= 0:
		return
	tick_statuses(dt)
	stun_t -= dt
	if has_status("sleep") or stun_t > 0:
		sync_screen()
		return
	speed = base_move_speed() * speed_bonus * status_speed_mult() # passive speed must survive the per-frame recompute
	atk_cd -= dt
	# far wild pals tick their AI at ~8Hz (accumulated dt keeps speeds honest)
	var far := mode == "wild" and pos.distance_squared_to(game.player.pos) > 784.0
	ai_accum += dt
	if far and ai_accum < 0.12:
		sync_screen()
		return
	var adt: float = ai_accum if far else dt
	ai_accum = 0.0
	if mode != "wild":
		tick_needs(dt)
	match mode:
		"wild":
			wild_ai(adt)
		"partner":
			partner_ai(dt)
		"base":
			base_ai(dt)
	sync_screen()

func wild_ai(dt: float) -> void:
	var pl := game.player
	var dist := pos.distance_to(pl.pos)
	# night: non-nocturnal wild pals sleep — sneak in for catch/backstab;
	# dark-element and apex hostiles stay awake
	if game.is_night() and aggro < 0 and hit_flash <= 0 and "dark" not in spec.get("elements", []) and hostile() < 2:
		statuses["sleep"] = game.t + 2.0
		return
	if aggro == 0:
		# raiders storm the BASE: target the nearest defender, not just the player
		if raid:
			var bt: Pal = null; var bd := dist
			for bp in game.pals:
				if bp.mode != "base" or bp.hp <= 0:
					continue
				var dd := pos.distance_to(bp.pos)
				if dd < bd:
					bd = dd; bt = bp
			if bt != null and bd <= 1.1 and atk_cd <= 0:
				atk_cd = 1.1
				bt.hit(maxi(2, int(spec.get("atk", 40) * 0.4)), 1.0, false)
				return
			elif bt != null:
				if not cast_skills(bt, dt):
					step_toward(bt.pos, dt)
				return
		# fight player if aggressive; timid flees
		if hostile() >= 1:
			if not cast_skills(pl, dt):
				if dist > 1.1:
					step_toward(pl.pos, dt)
				elif atk_cd <= 0:
					atk_cd = 1.1
					game.hurt_player(spec.get("atk", 50), self)
			elif dist > spec.get("reach", 4.0):
				step_toward(pl.pos, dt)
			if dist > 14:
				aggro = -1
		else:
			step_toward(pos + (pos - pl.pos).normalized() * 5.0, dt)
			if dist > 10:
				aggro = -1
		return
	elif aggro > 0:
		var tp: Pal = game.find_pal(aggro)
		if tp == null or tp.hp <= 0:
			aggro = -1
		else:
			var pd := pos.distance_to(tp.pos)
			if not cast_skills(tp, dt):
				if pd > 1.1:
					step_toward(tp.pos, dt)
				elif atk_cd <= 0:
					atk_cd = 1.1
					tp.hit(maxi(2, int(spec.get("atk", 40) * 0.35)), 1.0, false)
			elif pd > spec.get("reach", 4.0):
				step_toward(tp.pos, dt)
			if pd > 16:
				aggro = -1
		return
	# lair alpha: tethered to its lair; engages only on home ground
	if alpha:
		if pos.distance_squared_to(home) > 81.0:
			step_toward(home, dt)
			return
		if dist < 6.0 and not has_status("sleep"):
			aggro = 0
			return
	# a de-aggro'd raider re-targets the base instead of wandering home
	if raid:
		var bt2: Pal = null; var bd2 := 30.0
		for bp in game.pals:
			if bp.mode != "base" or bp.hp <= 0:
				continue
			var dd2 := pos.distance_to(bp.pos)
			if dd2 < bd2:
				bd2 = dd2; bt2 = bp
		if bt2 != null:
			aggro = bt2.uid
			return
	# wander
	wander_t -= dt
	if wander_t <= 0:
		wander_t = 1.5 + game.rng.next() * 3.0
		var a := game.rng.next() * TAU
		target = pos + Vector2(cos(a), sin(a)) * (1.5 + game.rng.next() * 3.0)
	step_toward(target, dt)
	# aggro check — apex pounces from further out, ordinary hostiles at arm's length
	var trigger := 5.0 if hostile() == 2 else 3.5
	if hostile() >= 1 and dist < trigger and not has_status("sleep"):
		aggro = 0

func partner_ai(dt: float) -> void:
	if not visible:
		pos = game.player.pos
		return
	var pl := game.player
	# attack nearest wild pal threatening player
	var best: Pal = null
	var bd := 6.0
	for p in game.pals:
		if p.mode != "wild" or p.hp <= 0:
			continue
		if p.aggro != 0 and p.aggro != uid and not p.raid: # threats to the player or self, plus raiders
			continue
		var d := pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	if best:
		if not cast_skills(best, dt):
			if bd > 1.0:
				step_toward(best.pos, dt)
			elif atk_cd <= 0:
				atk_cd = 1.0
				var mult := Combat.effectiveness("neutral", best.elem())
				var d := Combat.damage(Combat.stat_at(spec["atk"], level, talent) * atk_bonus, 30,
					Combat.stat_at(best.spec["def"], best.level, best.talent) * best.def_bonus, mult, game.rng)
				best.hit(d, mult, true)
		elif bd > 5.0:
			step_toward(best.pos, dt)
		return
	if pos.distance_to(pl.pos) > 1.8:
		step_toward(pl.pos, dt)

func base_ai(dt: float) -> void:
	# defend the base: raiders beating on workers get fought back
	var foe: Pal = null; var fbd := 4.0
	for p in game.pals:
		if p.mode != "wild" or p.hp <= 0:
			continue
		if not p.raid and p.aggro < 0:
			continue
		var dd := pos.distance_to(p.pos)
		if dd < fbd:
			fbd = dd; foe = p
	if foe != null:
		if not cast_skills(foe, dt):
			if fbd > 1.1:
				step_toward(foe.pos, dt)
			elif atk_cd <= 0:
				atk_cd = 1.0
				var mult := Combat.effectiveness("neutral", foe.elem())
				var d := Combat.damage(Combat.stat_at(spec["atk"], level, talent) * atk_bonus, 25,
					Combat.stat_at(foe.spec["def"], foe.level, foe.talent) * foe.def_bonus, mult, game.rng)
				foe.hit(d, mult, true)
		return
	if job_site:
		var site_cell: Vector2i = Vector2i(-1, -1)
		for k in game.structures:
			if game.structures[k] == job_site:
				site_cell = k
				break
		if site_cell.x >= 0:
			step_toward(Vector2(site_cell.x + 0.5, site_cell.y + 0.5), dt)
	elif spec.get("work", {}).get("transporting", 0) > 0:
		haul_ai(dt)
	else:
		wander_t -= dt
		if wander_t <= 0:
			wander_t = 2.0 + game.rng.next() * 3.0
			var a := game.rng.next() * TAU
			target = pos + Vector2(cos(a), sin(a)) * 2.0
		if pos.distance_to(target) > 0.4:
			step_toward(target, dt)

func haul_ai(dt: float) -> void:
	if carry != null:
		var cc := game.nearest_chest_cell(pos, carry["id"])
		if cc.x < 0:
			return  # no chest that can take it: hold the goods
		var cp := Vector2(cc.x + 0.5, cc.y + 0.5)
		if pos.distance_to(cp) > 1.8:
			step_toward(cp, dt)
		else:
			var st: Dictionary = game.structures[cc]
			st["store"][carry["id"]] = st["store"].get(carry["id"], 0) + carry["n"]
			carry = null
		return
	# first: production sites holding goods -> move one stack to a chest
	var bd := 24.0 * 24.0; var bd2 := bd
	var site_pick = null; var site_id := ""
	for k in game.structures:
		var st2: Dictionary = game.structures[k]
		if st2["id"] in ["chest", "feed_box"] or st2.get("store", {}).is_empty():
			continue # feed_box stock is the pals' own food — hauling it out starves the base
		var dd2 := pos.distance_squared_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd2 < bd2:
			bd2 = dd2; site_pick = k
	if site_pick != null:
		var sst: Dictionary = game.structures[site_pick]
		var cp2 := Vector2(site_pick.x + 0.5, site_pick.y + 0.5)
		if pos.distance_to(cp2) > 1.6:
			step_toward(cp2, dt)
		else:
			site_id = sst["store"].keys()[0]
			carry = {"id": site_id, "n": sst["store"][site_id]}
			sst["store"].erase(site_id)
		return
	bd2 = bd
	var pick = null
	for d in game.drops:
		var dd := pos.distance_squared_to(d["pos"])
		if dd < bd2:
			bd2 = dd; pick = d
	if pick == null:
		wander_t -= dt
		if wander_t <= 0:
			wander_t = 2.0 + game.rng.next() * 3.0
			var a := game.rng.next() * TAU
			target = pos + Vector2(cos(a), sin(a)) * 2.0
		if pos.distance_to(target) > 0.4:
			step_toward(target, dt)
		return
	if pos.distance_to(pick["pos"]) > 0.6:
		step_toward(pick["pos"], dt)
	else:
		carry = {"id": pick["id"], "n": pick["n"]}
		game.take_drop(pick)

func tick_needs(dt: float) -> void:
	needs_t += dt
	if needs_t < 1.0:
		return
	needs_t = 0
	hunger = minf(100.0, hunger + 0.5 * passive_mult("food"))  # Glutton eats more
	san = maxf(0.0, san - (0.2 if job_site else 0.05) / passive_mult("san"))  # Zen/Pacifist hold SAN longer
	if hunger > 70:
		var ate := 0
		if mode == "base" and game.has_structure("feed_box"):
			ate = game.eat_food_item() # stocked base food
		elif mode == "partner":
			ate = game.eat_from_bag() # party pals share the player's pack
		if ate > 0:
			hunger = maxf(0, hunger - float(ate) * 2.5)
			san = minf(100, san + 8)
		elif mode in ["base", "partner"]:
			san = maxf(0.0, san - 0.6)  # starving with no food to find: SAN bleeds
	if hunger >= 100.0:
		hp -= maxi(1, int(max_hp * 0.02)) # prolonged starvation costs real hp
		if hp <= 0 and mode in ["base", "partner"]:
			game.kill_pal(self, false)
	if mode == "base" and san < 30 and game.has_structure("pal_bed"):
		san = minf(100.0, san + 6.0)  # resting requires being AT the base

func learned_skills() -> Array:
	var out := []
	for e in spec.get("skills", []):
		if level >= e[0]:
			out.append(e[1])
	return out

func tick_statuses(dt: float) -> void:
	for k in statuses.keys():
		if statuses[k] <= game.t:
			statuses.erase(k)
			continue
		match k:
			"burn":
				if int(game.t * 5) != int((game.t - dt) * 5):
					take_dps(maxi(1, int(max_hp * 0.02)))
			"poison":
				if int(game.t * 3) != int((game.t - dt) * 3):
					take_dps(maxi(1, int(max_hp * 0.012)))
			"shock":
				if game.rng.chance(dt * 0.25):
					stun_t = 0.45

func take_dps(n: int) -> void:
	hp -= n
	hit_flash = 0.2
	if hp <= 0:
		game.kill_pal(self, false)

func cast_skills(target_ent, dt: float) -> bool:
	var dist := pos.distance_to(target_ent.pos)
	var best: Dictionary = {}
	for sid in learned_skills():
		if skill_cd.get(sid, 0) > game.t:
			continue
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		if sk.is_empty() or dist > sk.get("range", 1.4):
			continue
		if best.is_empty() or sk.get("power", 0) > best.get("power", 0):
			best = sk # strongest usable skill, not the lowest-level one
	if best.is_empty():
		return false
	skill_cd[best["id"]] = game.t + best.get("cooldown", 2)
	game.cast_skill(self, target_ent, best)
	return true

func apply_skill_status(sk: Dictionary, is_behind: bool = false) -> void:
	var st = sk.get("status")
	if st and game.rng.chance(st.get("chance", 1.0)):
		add_status(st["kind"], st.get("dur", 3))

func roll_passives() -> void:
	passives.clear()
	var keys := PassiveData.PASSIVES.keys()
	var n := 1 + (1 if game.rng.chance(0.35) else 0)
	for i in n:
		var k: String = keys[game.rng.int_range(0, keys.size() - 1)]
		if k not in passives:
			passives.append(k)
	apply_bonuses()

func passive_mult(field: String) -> float:
	var m := 1.0
	for k in passives:
		m *= PassiveData.PASSIVES.get(k, {}).get(field, 1.0) # stale save keys skip safely
	return m

func apply_bonuses() -> void:
	atk_bonus = 1.0
	def_bonus = 1.0
	speed_bonus = 1.0
	var pv: Dictionary
	for k in passives:
		pv = PassiveData.PASSIVES.get(k, {})
		atk_bonus *= pv.get("atk", 1.0)
		def_bonus *= pv.get("def", 1.0)
		speed_bonus *= pv.get("speed", 1.0)
	# star rank stacks on top of passives (Palworld essence condenser)
	var star_mult := pow(1.15, star)
	atk_bonus *= star_mult
	def_bonus *= star_mult
	max_hp = Combat.stat_at(spec["hp"], level, talent) * star_mult
	if alpha:
		max_hp *= 4.0
	if boss:
		max_hp *= 2.0
	hp = minf(hp, max_hp)

# condense: +1 star rank; stats scale, current hp grows proportionally
func condense() -> void:
	star += 1
	var frac := hp / maxf(1.0, max_hp)
	apply_bonuses()
	hp = max_hp * frac

var atk_bonus := 1.0
var def_bonus := 1.0
var speed_bonus := 1.0
var star := 0
var raid := false            # spawned by a raid wave — blocks sleeping # essence-condense rank 0-4; each star multiplies combat stats
