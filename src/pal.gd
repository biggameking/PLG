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
var target := Vector2.ZERO
var atk_cd := 0.0
var spec: Dictionary = {}
var job_site = null
var sex := "M"
var alpha := false
var passives := []
var needs_t := 0.0
var skill_cd := {}
var stun_t := 0.0

func setup(g: Game, sp_id: String, lv: int, at: Vector2) -> void:
	game = g
	world = g.world
	species_id = sp_id
	spec = SpeciesData.species_of(sp_id)
	level = lv
	talent = game.rng.int_range(0, 100)
	max_hp = Combat.stat_at(spec["hp"], level, talent)
	hp = max_hp
	san = spec.get("san", 80)
	pos = at
	target = at
	speed = spec.get("speed", 2.6)
	uid = game.next_uid()
	sex = "M" if game.rng.chance(0.5) else "F"
	roll_passives()
	if alpha:
		max_hp *= 4.0
		hp = max_hp
	setup_visuals("res://assets/pals/%s_f0.png" % sp_id, "res://assets/pals/%s_f1.png" % sp_id)
	if alpha:
		sprite.scale = Vector2(1.6, 1.6)
		sprite.position.y = -51.0

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
	var base_speed: float = spec.get("speed", 2.6)
	speed = base_speed * status_speed_mult()
	atk_cd -= dt
	if mode != "wild":
		tick_needs(dt)
	match mode:
		"wild":
			wild_ai(dt)
		"partner":
			partner_ai(dt)
		"base":
			base_ai(dt)
	sync_screen()

func wild_ai(dt: float) -> void:
	var pl := game.player
	var dist := pos.distance_to(pl.pos)
	if aggro == 0:
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
	# wander
	wander_t -= dt
	if wander_t <= 0:
		wander_t = 1.5 + game.rng.next() * 3.0
		var a := game.rng.next() * TAU
		target = pos + Vector2(cos(a), sin(a)) * (1.5 + game.rng.next() * 3.0)
	step_toward(target, dt)
	# aggro check
	if hostile() == 2 and dist < 5.0 and not has_status("sleep"):
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
		if p.mode != "wild" or p.hp <= 0 or p.aggro != 0:
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
	if job_site:
		var site_cell: Vector2i = Vector2i(-1, -1)
		for k in game.structures:
			if game.structures[k] == job_site:
				site_cell = k
				break
		if site_cell.x >= 0:
			step_toward(Vector2(site_cell.x + 0.5, site_cell.y + 0.5), dt)
	else:
		wander_t -= dt
		if wander_t <= 0:
			wander_t = 2.0 + game.rng.next() * 3.0
			var a := game.rng.next() * TAU
			target = pos + Vector2(cos(a), sin(a)) * 2.0
		if pos.distance_to(target) > 0.4:
			step_toward(target, dt)

func tick_needs(dt: float) -> void:
	needs_t += dt
	if needs_t < 1.0:
		return
	needs_t = 0
	hunger = minf(100.0, hunger + 0.5)
	san = maxf(0.0, san - (0.2 if job_site else 0.05))
	if hunger > 70:
		# seek feed box: eat directly for now
		if game.has_structure("feed_box") and game.item_count("berry") > 0:
			game.add_item("berry", -1)
			hunger = maxf(0, hunger - 40)
			san = minf(100, san + 8)

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
	for sid in learned_skills():
		if skill_cd.get(sid, 0) > game.t:
			continue
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		if sk.is_empty() or dist > sk.get("range", 1.4):
			continue
		skill_cd[sid] = game.t + sk.get("cooldown", 2)
		game.cast_skill(self, target_ent, sk)
		return true
	return false

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
	var pv: Dictionary
	for k in passives:
		pv = PassiveData.PASSIVES[k]
		atk_bonus *= pv.get("atk", 1.0)
		def_bonus *= pv.get("def", 1.0)
		speed *= pv.get("speed", 1.0)

var atk_bonus := 1.0
var def_bonus := 1.0
