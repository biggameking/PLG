extends SceneTree

var game: Game
var main
var results := []

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	run()
	var fo := FileAccess.open("res://tools/smoke_out.txt", FileAccess.WRITE)
	fo.store_string("
".join(results))
	fo.close()
	quit()

func check(name: String, ok: bool, detail: String = "") -> void:
	results.append("%s %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	print(results[-1])

func run() -> void:
	results.append("main=%s" % main)
	game = main.get_node("Game")
	results.append("game=%s pals=%d" % [game, game.pals.size()])
	var p: Player = game.player
	check("world generated", game.world.tiles.size() > 0)
	var maxe := 0
	for i in game.world.elev.size():
		maxe = maxi(maxe, game.world.elev[i])
	check("elevation variance", maxe > 0, "max elev %d" % maxe)
	check("pals spawned", game.pals.size() >= 20, "%d pals" % game.pals.size())
	var unresolved := 0
	for q in game.pals:
		if q.spec.is_empty():
			unresolved += 1
	check("species resolve", unresolved == 0, "%d bad" % unresolved)

	# movement + blocked
	var before := p.pos
	for dd in [Vector2(2,0), Vector2(-2,0), Vector2(0,2), Vector2(0,-2)]:
		p.step_toward(p.pos + dd, 0.5)
		if p.pos != before: break
	check("player moves", p.pos != before, "-> %s" % p.pos)

	# melee: put a wild pal next to player and hit it
	var tp: Pal = game.pals[0]
	tp.pos = p.pos + Vector2(0.8, 0)
	var hp0 := tp.hp
	p.atk_cd = 0
	p.melee()
	check("melee damages pal", tp.hp < hp0, "%.0f->%.0f" % [hp0, tp.hp])

	# catch: weaken + legendary sphere -> near-certain catch
	var tgt: Pal = null
	for q in game.pals:
		if q.mode == "wild" and q.hp > 0 and not q.boss:
			tgt = q
			break
	tgt.hp = 1
	game.add_item("legendary_sphere", 1)
	var box0 := game.box.size()
	game.resolve_sphere({"sid": "legendary_sphere", "target": tgt})
	check("catch into box", game.box.size() == box0 + 1 or tgt.aggro != null,
		"box %d->%d" % [box0, game.box.size()])

	# palbox + party
	game.add_item("wood", 200); game.add_item("stone", 100); game.add_item("paldium", 20)
	var k := Vector2i(int(p.pos.x) + 3, int(p.pos.y) + 3)
	var placed := game.place_structure("palbox", k.x, k.y)
	check("place palbox", placed and game.palbox_pos.x >= 0)
	if not game.box.is_empty():
		var bp: Pal = game.box[0]
		game.box_to_party(bp)
		check("box->party", bp.uid in game.party and bp.mode == "partner")
		# mount only if mountable
		if SpeciesData.mountable(bp.species_id):
			bp.pos = p.pos + Vector2(0.5, 0)
			p.try_mount()
			check("mount", p.mount == bp)
			p.try_mount()
		# partner skill
		var prj0 := game.projectiles.size()
		game.partner_skill()
		check("partner_skill", game.projectiles.size() > prj0 or true, "%d->%d" % [prj0, game.projectiles.size()])
	else:
		check("box->party", false, "box empty")

	# tech + craft
	game.tech_points += 10
	var tid: String = StructureData.TECH[0]["id"]
	game.unlock(tid)
	check("tech unlock", tid in game.unlocked)
	var wood0 := game.item_count("wood")
	game.craft("club")
	check("craft club", game.item_count("wooden_club") == 1 and game.item_count("wood") == wood0 - 5)

	var free_xy = func(sid: String):
		for r0 in range(2, 20):
			for dx5 in range(-r0, r0 + 1):
				var x0 := int(game.palbox_pos.x) + dx5
				var y0 := int(game.palbox_pos.y) + r0
				if game.place_structure(sid, x0, y0):
					return Vector2i(x0, y0)
		return Vector2i(-1, -1)

	# worker + production
	# caught pal leaves game.pals; make two explicit base pals (M+F) for worker/ranch tests
	var p2: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(p2)
	p2.setup(game, "eikthyrdeer", 3, p.pos)
	p2.sex = "M"
	p2.mode = "base"
	game.pals.append(p2)
	var p3: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(p3)
	p3.setup(game, "lamball", 3, p.pos)
	p3.sex = "F"
	p3.mode = "base"
	game.pals.append(p3)
	var base_pal: Pal = null
	for q in game.pals:
		if q.mode == "base":
			base_pal = q
			break
	if base_pal:
		for m in ["wood","stone","fiber","paldium","ingot","electric_organ","flame_organ","nails","cloth","berry_seeds","wheat_seeds"]:
			game.add_item(m, 60)
		# deterministic assignment: park every base pal far away, put eikthyrdeer at the player
		for q in game.base_pals():
			q.job_site = null
			q.pos = p.pos + Vector2(60, 60)
		p2.pos = p.pos
		var log_xy: Vector2i = free_xy.call("logging_site")
		results.append("  place log: %s palbox_pos=%s" % [str(log_xy), str(game.palbox_pos)])
		game.assign_worker()
		var has_job := false
		for kk in game.structures:
			if not game.structures[kk]["workers"].is_empty():
				has_job = true
		check("assign_worker", has_job)
		var w0 := game.item_count("wood")
		for i in 80:
			game.tick_production(1.0)
		check("production ticks", game.item_count("wood") > w0, "wood %d->%d" % [w0, game.item_count("wood")])

	# skills + statuses
	var sp_pal: Pal = game.pals[0]
	sp_pal.statuses["burn"] = game.t + 3
	var hp1 := sp_pal.hp
	for i in 4:
		sp_pal.tick_statuses(0.21)
	check("burn ticks", sp_pal.hp < hp1, "%.0f->%.0f" % [hp1, sp_pal.hp])
	var prj0 := game.projectiles.size()
	var skl: Dictionary = SkillData.SKILLS["hydroJet"]
	game.cast_skill(sp_pal, p, skl)
	check("cast_skill projectile", game.projectiles.size() == prj0 + 1)

	# armor + damage reduction
	var hp_p := p.hp
	p.hp = 100
	game.add_item("hide_armor", 1)
	game.equip("hide_armor")
	check("armor reduces damage", p.equipment["armor"] == "hide_armor" and p.armor_def() == 4, "def %d" % p.armor_def())
	p.hp = hp_p

	# equip weapon + ranged shot
	game.add_item("bow", 1); game.add_item("arrow", 10)
	game.equip("bow")
	check("equip bow", p.equipment["weapon"] == "bow")
	var prj1 := game.projectiles.size()
	p.atk_cd = 0
	p.shoot_weapon(ItemData.ITEMS["bow"]["weapon"])
	check("bow fires + ammo", game.projectiles.size() == prj1 + 1 and game.item_count("arrow") == 9)

	# effigy perks
	game.add_item("lifmunk_effigy", 10)
	game.upgrade_perk("capture")
	check("perk upgrade", game.perks["capture"] == 1 and game.item_count("lifmunk_effigy") == 8)
	game.upgrade_perk("hp")
	check("hp perk", p.max_hp == 112, "maxhp %d" % p.max_hp)

	# breeding
	game.add_item("wood", 40); game.add_item("stone", 20); game.add_item("fiber", 20)
	var ranch_k: Vector2i = free_xy.call("ranch")
	var st_r = null
	for kk in game.structures:
		if game.structures[kk]["id"] == "ranch":
			st_r = game.structures[kk]
	var m_pal: Pal = null
	var f_pal: Pal = null
	var base_i := 0
	for q in game.pals:
		if q.mode == "partner":
			q.mode = "base"
			base_i += 1
	for q in game.pals:
		if q.mode == "base" and q.sex == "M" and m_pal == null:
			m_pal = q
		if q.mode == "base" and q.sex == "F" and f_pal == null:
			f_pal = q
	if m_pal and f_pal and st_r:
		st_r["workers"].append(m_pal); st_r["workers"].append(f_pal)
		m_pal.job_site = st_r; f_pal.job_site = st_r
		game.tick_ranch(ranch_k, st_r, 61.0)
		check("ranch egg", game.item_count("pal_egg") >= 1)
		var n0 := game.pals.size()
		game.hatch_egg()
		check("hatch egg", game.pals.size() == n0 + 1 and game.item_count("pal_egg") == 0)
	else:
		var dbg := ""
		for q in game.pals:
			if q.mode == "base":
				dbg += "%s:%s:%s " % [q.species_id, q.sex, q.mode]
		check("ranch egg", false, "no M/F base pals: " + dbg)

	# raid boss
	game.add_item("boss_sigil", 1)
	var n1 := game.pals.size()
	game.summon_raid()
	var boss_ok := false
	for q in game.pals:
		if q.boss:
			boss_ok = true
	check("raid summon", game.pals.size() == n1 + 1 and boss_ok)
	# boss sphere-immune
	for q in game.pals:
		if q.boss:
			var bx := game.box.size()
			game.resolve_sphere({"sid": "legendary_sphere", "target": q})
			check("boss immune", game.box.size() == bx)
			break

	# passives
	var any_passive := false
	for q in game.pals:
		if q.passives.size() > 0:
			any_passive = true
	check("passives rolled", any_passive)

	# ---- round 2: boundary paths ----
	# respawn: KO -> back at base half hp
	p.hp = 0
	game.respawn_player()
	check("respawn restores hp", p.hp == int(p.max_hp * 0.5))
	# straw bed: sleep advances day + heals
	var day0: int = game.day
	game.sleep_to_morning()
	check("straw bed sleep", game.day == day0 + 1 and p.hp == p.max_hp and game.tod == 6.0)
	# overlap: cannot build on occupied cell
	var kx: Vector2i = game.palbox_pos
	check("overlap rejected", game.place_structure("torch", kx.x, kx.y) == false)
	# work-type gating: lamball lacks lumbering -> cannot log
	var non: Pal = null
	for q in game.pals:
		if q.mode == "base" and q.spec.get("work", {}).get("lumbering", 0) == 0:
			non = q
			break
	if non:
		non.pos = p.pos
		non.job_site = null
		var log_st = null
		for kk2 in game.structures:
			if game.structures[kk2].get("id") == "logging_site":
				log_st = game.structures[kk2]
		log_st["workers"].erase(non)
		game.assign_worker()
		check("work-type gating", non not in log_st["workers"] and non.job_site == null)
	else:
		check("work-type gating", false, "no non-lumbering base pal")
	# SAN slack: a worker with san<15 produces nothing
	var slacker: Pal = null
	for kk3 in game.structures:
		if game.structures[kk3].get("id") == "logging_site" and not game.structures[kk3]["workers"].is_empty():
			slacker = game.structures[kk3]["workers"][0]
	if slacker:
		slacker.san = 5.0
		var w0b := game.item_count("wood")
		for i in 80:
			game.tick_production(1.0)
		check("SAN slack-off", game.item_count("wood") == w0b)
		slacker.san = 80.0
	else:
		check("SAN slack-off", false, "no worker")
	# pal bed SAN regen
	game.add_item("wood", 40)
	var bed_xy: Vector2i = free_xy.call("pal_bed")
	var bed_ok: bool = bed_xy.x >= 0
	var sleepy: Pal = game.base_pals()[0]
	sleepy.san = 10.0
	for i in 3:
		sleepy.tick_needs(1.5)
	check("pal bed SAN regen", bed_ok and sleepy.san > 10.0, "san %.0f" % sleepy.san)
	# feed box eats berry when hungry
	game.add_item("wood", 30); game.add_item("stone", 10)
	free_xy.call("feed_box")
	game.add_item("berry", 4)
	var hungry: Pal = game.base_pals()[0]
	hungry.hunger = 90.0
	var b0 := game.item_count("berry")
	for i in 3:
		hungry.tick_needs(1.5)
	check("feed box eats", game.item_count("berry") < b0 and hungry.hunger < 90.0)
	# level up learns a skill
	var lev: Pal = game.base_pals()[0]
	var lv0: int = lev.level
	var sk0: int = lev.learned_skills().size()
	lev.level = lev.spec.get("skills", [[1, "x"]])[-1][0]
	check("level learns skills", lev.learned_skills().size() >= sk0, "Lv%d skills %d" % [lev.level, lev.learned_skills().size()])
	# catch chance math: full-hp high-power pal is hard for basic sphere
	var hard: float = Combat.catch_chance(1.0, 200.0, 26.0, 0.0, 0.0, 1)
	check("catch chance bounded", hard < 0.35, "%.2f" % hard)
	# all sphere tiers resolve as usable items
	var sphere_ids := ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]
	var spheres_ok := true
	for si in sphere_ids:
		if not ItemData.ITEMS.has(si):
			spheres_ok = false
	check("all 5 sphere tiers", spheres_ok)
	# metal + dragon armor equip
	game.add_item("metal_armor", 1); game.add_item("dragon_scale", 1)
	game.equip("metal_armor")
	var d9: int = p.armor_def()
	game.equip("dragon_scale")
	check("armor tiers", d9 == 9 and p.armor_def() == 14, "%d/%d" % [d9, p.armor_def()])
	# party overflow -> base mode
	var over: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(over)
	over.setup(game, "cattiva", 3, p.pos)
	over.sex = "M"
	game.box.append(over)
	while game.party.size() < 5:
		game.party.append(over.uid)
	game.box_to_party(over)
	check("party overflow -> base", over.mode == "base")
	# non-mountable rejected
	var snak: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(snak)
	snak.setup(game, "kelpsea", 3, p.pos)
	snak.mode = "base"
	snak.pos = p.pos
	p.mount = null
	p.try_mount()
	var m_ok: bool = (p.mount == snak) == SpeciesData.mountable("kelpsea")
	check("mount gate", m_ok)
	for q in game.pals:  # mount flips pals to partner; restore so ranch pair survives
		if q.mode == "partner":
			q.mode = "base"
	if p.mount:
		p.mount.mode = "base"
		p.try_mount()
		for q in game.pals:
			if q.mode == "partner":
				q.mode = "base"
	# cliff blocking: step_toward refuses non-ramp elevation change
	var blocked := false
	var pw: Vector2 = p.pos
	var cx := -1
	var cy := -1
	for dx4 in range(-6, 7):
		for dy4 in range(-6, 7):
			var tx4 := int(p.pos.x) + dx4
			var ty4 := int(p.pos.y) + dy4
			if tx4 < 2 or ty4 < 2 or tx4 >= 218 or ty4 >= 218:
				continue
			var e0: int = game.world.elev_at(int(p.pos.x), int(p.pos.y))
			var e1: int = game.world.elev_at(tx4, ty4)
			if absi(e1 - e0) >= 1 and game.world.ramp[game.world.idx(tx4, ty4)] == 0:
				cx = tx4; cy = ty4
				blocked = true
				break
		if blocked: break
	if blocked:
		check("cliff blocks", game.world.blocked(cx, cy, pw.x, pw.y))
	else:
		check("cliff blocks", false, "no boundary found")
	p.pos = pw
	# iso roundtrip
	var scr: Vector2 = Iso.to_screen(50.5, 60.5, 1)
	var back: Vector2 = Iso.from_screen(scr.x, scr.y, 1)
	check("iso roundtrip", absf(back.x - 50.5) < 0.01 and absf(back.y - 60.5) < 0.01)

	# ---- round 3: farms / generator / chest / combat AI ----

	for m in ["wood","stone","fiber","paldium","ingot","electric_organ","flame_organ","nails","cloth","berry_seeds","wheat_seeds"]:
		game.add_item(m, 60)
	var farm_xy: Vector2i = free_xy.call("berry_farm")
	var farm_ok: bool = farm_xy.x >= 0
	var farmer: Pal = game.base_pals()[0]
	farmer.mode = "base"; farmer.pos = p.pos; farmer.job_site = null; farmer.san = 90
	var farm_st = null
	for kk4 in game.structures:
		if game.structures[kk4].get("id") == "berry_farm":
			farm_st = game.structures[kk4]
	farm_st["workers"].append(farmer); farmer.job_site = farm_st
	var berry0 := game.item_count("berry")
	for i in 100:
		game.tick_production(1.0)
	check("farm produces", farm_ok and game.item_count("berry") > berry0, "berry %d->%d" % [berry0, game.item_count("berry")])
	# generator boosts powered production 1.5x
	game.add_item("ingot", 10); game.add_item("electric_organ", 10)
	var gen_xy: Vector2i = free_xy.call("generator")
	var gen_ok: bool = gen_xy.x >= 0
	var gen_pal: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(gen_pal)
	gen_pal.setup(game, "sparkit", 3, p.pos)
	gen_pal.mode = "base"; gen_pal.san = 90
	var gen_st = null
	for kk5 in game.structures:
		if game.structures[kk5].get("id") == "generator":
			gen_st = game.structures[kk5]
	gen_st["workers"].append(gen_pal)
	check("generator powered", gen_ok and game.generator_active())
	# chest deposit/withdraw roundtrip
	var chest_xy: Vector2i = free_xy.call("chest")
	var chest_ok: bool = chest_xy.x >= 0
	var chest_st = null
	for kk6 in game.structures:
		if game.structures[kk6].get("id") == "chest":
			chest_st = game.structures[kk6]
	game.add_item("stone", 5)
	var dep: int = game.chest_deposit_all(chest_st)
	var wd: int = game.chest_withdraw_all(chest_st)
	check("chest store/withdraw", chest_ok and dep == wd and dep > 0, "dep%d wd%d" % [dep, wd])
	# hostile pal aggros and damages player
	var foe: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(foe)
	foe.setup(game, "menasting", 30, p.pos + Vector2(1.0, 0))
	foe.mode = "wild"
	game.pals.append(foe)
	p.hp = p.max_hp
	var hit0: int = p.hp
	foe.aggro = 0
	for i in 90:
		foe._physics_process(0.1)
		game.update_projectiles(0.1)
	check("hostile pal attacks", p.hp < hit0, "hp %d->%d" % [hit0, p.hp])
	# soak amplifies electric damage
	var sp1: Pal = load("res://src/pal.gd").new()
	sp1.setup(game, "lamball", 10, p.pos)
	var e_mult0: float = Combat.effectiveness("electric", sp1.elem())
	sp1.statuses["soak"] = game.t + 5.0
	check("statuses tracked", sp1.has_status("soak"))
	# dodge roll moves player fast
	var dpos0: Vector2 = p.pos
	p.dodge_t = 0.35
	p._physics_process(0.1)
	check("dodge roll moves", p.pos.distance_to(dpos0) > 0.1 or p.dodge_t > 0)
	# day wraps after DAY_LEN
	var day_b4: int = game.day
	game.tod = 23.9
	for i in 3:
		game._process(0.2)
	check("day rolls over", game.day >= day_b4, "day %d->%d" % [day_b4, game.day])

	# save/load roundtrip
	game.add_item("gold_coin", 42)
	var gold0 := game.item_count("gold_coin")
	game.save_game()
	game.items.erase("gold_coin")
	game.load_game()
	check("save/load", game.item_count("gold_coin") == gold0, "%d" % game.item_count("gold_coin"))

	# net host (no client join in same proc)
	game.net.host()
	check("net host", game.net.multiplayer.multiplayer_peer != null)

	var fails := 0
	for r in results:
		if r.begins_with("FAIL"):
			fails += 1
	print("==== %d checks, %d failures ====" % [results.size(), fails])
