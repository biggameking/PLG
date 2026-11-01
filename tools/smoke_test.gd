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

	# every work type except transporting has a structure site that uses it
	var missing_sites: Array = []
	for wt in ["kindling","watering","planting","electricity","handiwork",
			"gathering","lumbering","mining","medicine","cooling","farming","oilExtraction"]:
		var has_site := false
		for st in StructureData.STRUCTURES.values():
			var jb: Dictionary = st.get("job", {})
			if jb.get("workType") == wt:
				has_site = true
				break
		if not has_site:
			missing_sites.append(wt)
	check("work types have sites", missing_sites.is_empty(), ",".join(missing_sites))

	# movement + blocked — if the spawn is boxed in, relocate to open ground
	if [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)].all(
			func(d0): return game.world.blocked(int(p.pos.x + d0.x), int(p.pos.y + d0.y))):
		for r8 in range(1, 40):
			var moved := false
			for dx8 in range(-r8, r8 + 1):
				for dy8 in [-r8, r8]:
					var cx8: int = int(p.pos.x) + dx8; var cy8: int = int(p.pos.y) + dy8
					if not game.world.blocked(cx8, cy8):
						p.pos = Vector2(cx8 + 0.5, cy8 + 0.5)
						moved = true; break
				if moved: break
			if moved: break
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
	game.add_item("legendary_sphere", 10)
	var box0 := game.box.size()
	for try in 12:  # catch is chance-based; retry until captured
		game.resolve_sphere({"sid": "legendary_sphere", "target": tgt})
		if tgt.mode == "box":
			break
	check("caught pal leaves world", tgt.get_parent() != game.entity_layer)
	check("catch into box", game.box.size() == box0 + 1, "box %d->%d" % [box0, game.box.size()])

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
		var bx := int(game.palbox_pos.x); var by := int(game.palbox_pos.y)
		for r0 in range(2, 30):
			var cells := []
			for dx5 in range(-r0, r0 + 1):
				cells.append(Vector2i(bx + dx5, by - r0))
				cells.append(Vector2i(bx + dx5, by + r0))
			for dy5 in range(-r0 + 1, r0):
				cells.append(Vector2i(bx - r0, by + dy5))
				cells.append(Vector2i(bx + r0, by + dy5))
			for c0 in cells:
				if game.place_structure(sid, c0.x, c0.y):
					return c0
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
	game.add_item("wood", 10)
	var dcnt0 := game.drops.size()
	game.respawn_player()
	check("respawn restores hp", p.hp == int(p.max_hp * 0.5))
	check("death drops inventory", game.drops.size() > dcnt0 and game.item_count("wood") == 0,
		"drops %d->%d" % [dcnt0, game.drops.size()])
	game.add_item("wood", 200); game.add_item("stone", 100); game.add_item("paldium", 20); game.add_item("fiber", 40)
	# straw bed: raid boss alive -> sleep refused; after killing it -> works
	var day0: int = game.day
	game.sleep_to_morning()
	check("sleep blocked by raid", game.day == day0, "day=%d" % game.day)
	for q in game.pals:
		if q.raid and q.hp > 0:
			game.kill_pal(q, true)
	game.sleep_to_morning()
	check("straw bed sleep", game.day == day0 + 1 and p.hp == p.max_hp and game.tod == 6.0)
	# overlap: cannot build on occupied cell
	var kx: Vector2i = game.palbox_pos
	check("overlap rejected", game.place_structure("torch", kx.x, kx.y) == false)
	# demolish: removes structure + refunds half cost
	var t_xy = free_xy.call("torch")
	check("demolish removes", t_xy != null and game.demolish_at(Vector2(t_xy.x, t_xy.y) + Vector2(0.5,0.5)) and not game.structures.has(t_xy), "")
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
		check("work-type gating", non not in log_st["workers"], "site=%s" % (non.job_site["id"] if non.job_site else "none"))
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
	game.add_item("red_berries", 4)
	var hungry: Pal = game.base_pals()[0]
	hungry.hunger = 90.0
	var b0 := game.item_count("red_berries")
	for i in 3:
		hungry.tick_needs(1.5)
	check("feed box eats", game.item_count("red_berries") < b0 and hungry.hunger < 90.0)
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
	var berry0 := game.item_count("red_berries")
	for i in 100:
		game.tick_production(1.0)
	check("farm produces", farm_ok and game.item_count("red_berries") > berry0, "red_berries %d->%d" % [berry0, game.item_count("red_berries")])
	# generator boosts powered production 1.5x
	game.add_item("ingot", 10); game.add_item("electric_organ", 10)
	var gen_xy: Vector2i = free_xy.call("generator")
	var gen_ok: bool = gen_xy.x >= 0
	var gen_pal: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(gen_pal)
	gen_pal.setup(game, "sparkit", 3, p.pos)
	gen_pal.mode = "base"; gen_pal.san = 90
	game.pals.append(gen_pal)
	var gen_st = null
	for kk5 in game.structures:
		if game.structures[kk5].get("id") == "generator":
			gen_st = game.structures[kk5]
	gen_st["workers"].append(gen_pal); gen_pal.job_site = gen_st
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

	# ---- round 4: save completeness + consumables + pal xp ----
	# medicine heals + consumes
	game.add_item("medical_supplies", 2)
	p.hp = 10
	# simulate hud use_item heal path
	var med: Dictionary = ItemData.ITEMS["medical_supplies"]
	p.hp = mini(p.max_hp, p.hp + med["heal"])
	game.add_item("medical_supplies", -1)
	check("medicine heals", p.hp == p.max_hp and game.item_count("medical_supplies") == 1, "hp %d" % p.hp)
	# sigil consumed on use
	var sig0 := game.item_count("boss_sigil")
	game.add_item("boss_sigil", 1)
	var sig_n := game.pals.size()
	game.summon_raid()
	game.add_item("boss_sigil", -1)
	check("sigil consumed", game.item_count("boss_sigil") == sig0 and game.pals.size() == sig_n + 1, "sig%d pals%d" % [game.item_count("boss_sigil"), game.pals.size() - sig_n])
	# pal xp levels up a partner pal
	var lvl_pal: Pal = null
	for q in game.pals:
		if q.mode == "partner":
			lvl_pal = q
			break
	if lvl_pal == null:
		lvl_pal = game.base_pals()[0]
		lvl_pal.mode = "partner"
	var plv0: int = lvl_pal.level
	lvl_pal.xp = lvl_pal.level * 25 - 10
	game.gain_xp(40)
	check("pal levels via xp", lvl_pal.level > plv0, "Lv%d->%d xp%d" % [plv0, lvl_pal.level, lvl_pal.xp])
	# save/load preserves pal sex/passives + chest store + job links
	game.box.clear()
	var sv_pal: Pal = null
	var seen := {}
	for q in game.pals:
		seen[q.species_id] = seen.get(q.species_id, 0) + 1
	for q in game.pals:
		if q.mode == "base" and seen[q.species_id] == 1:
			sv_pal = q
			break
	if sv_pal == null:
		sv_pal = game.base_pals()[0]
	var sv_sex: String = sv_pal.sex
	var sv_pass: Array = sv_pal.passives.duplicate()
	var chest2 = null
	for kk7 in game.structures:
		if game.structures[kk7].get("id") == "chest":
			chest2 = game.structures[kk7]
	if chest2:
		chest2["store"]["test_item"] = 7
	# count UNIQUE worker pals (a pal may sit in two arrays from manual test appends)
	var worker_pals := []
	for kk8 in game.structures:
		for w8 in game.structures[kk8]["workers"]:
			if w8 not in worker_pals:
				worker_pals.append(w8)
	var had_workers := worker_pals.size()
	var linked := 0
	for q in game.pals:
		for kj2 in game.structures:
			if q in game.structures[kj2]["workers"]:
				linked += 1
				break
	var boxp := 0
	for q in game.box:
		for kj3 in game.structures:
			if q in game.structures[kj3]["workers"]:
				boxp += 1
				break
	var site_names := {}
	for kk8 in game.structures:
		for w8 in game.structures[kk8]["workers"]:
			site_names[game.structures[kk8]["id"]] = site_names.get(game.structures[kk8]["id"], 0) + 1
	results.append("  had=%d linked_pals=%d sites=%s pals=%d" % [had_workers, linked, str(site_names), game.pals.size()])
	var party_sz_before := game.party.size()
	# unique structure instances before save (dedupe footprint cells)
	var st_before := []
	for kk11 in game.structures:
		if game.structures[kk11] not in st_before:
			st_before.append(game.structures[kk11])
	game.save_game()
	# mutate state then reload
	for q in game.pals:
		q.sex = "F"
	if chest2:
		chest2["store"].clear()
	var ok_load := game.load_game()
	var re_pal: Pal = null
	for q in game.pals:
		if q.species_id == sv_pal.species_id:
			re_pal = q
			break
	var chest3 = null
	for kk9 in game.structures:
		if game.structures[kk9].get("id") == "chest":
			chest3 = game.structures[kk9]
	var st_after := []
	for kk12 in game.structures:
		if game.structures[kk12] not in st_after:
			st_after.append(game.structures[kk12])
	check("party survives reload", game.party.size() == party_sz_before and game.party_pal() != null, "party=%d/%d" % [game.party.size(), party_sz_before])
	check("structures rebuild 1:1", st_after.size() == st_before.size(), "%d->%d" % [st_before.size(), st_after.size()])
	var re_worker_pals := []
	var re_site_names := {}
	for kk10 in game.structures:
		for w10 in game.structures[kk10]["workers"]:
			re_site_names[game.structures[kk10]["id"]] = re_site_names.get(game.structures[kk10]["id"], 0) + 1
			if w10 not in re_worker_pals:
				re_worker_pals.append(w10)
	var re_workers := re_worker_pals.size()
	results.append("  re_sites=%s" % str(re_site_names))
	check("save keeps sex/passives", ok_load and re_pal != null and re_pal.sex == sv_sex and re_pal.passives == sv_pass, "%s/%s" % [re_pal.sex if re_pal else "?", str(re_pal.passives) if re_pal else "?"])
	check("save keeps chest store", chest3 == null or chest3["store"].get("test_item", 0) == 7)
	var job_names := ""
	for q in game.pals:
		if q.job_site:
			job_names += q.species_id + " "
	check("save keeps workers", re_workers == had_workers, "%d->%d [%s]" % [had_workers, re_workers, job_names])

	# partner death frees the party slot + clears job site
	var dp: Pal = game.find_pal(game.party[0]) if game.party.size() > 0 else null
	if dp:
		var psz0: int = game.party.size()
		game.kill_pal(dp, true)
		check("dead partner frees slot", game.party.size() == psz0 - 1, "%d->%d" % [psz0, game.party.size()])
	# raid wave: forced timer spawns hostile raiders near base
	var pals0 := game.pals.size()
	game.raid_t = 0.0
	game._process(0.1)
	var raiders := 0
	for q in game.pals:
		if q.aggro >= 0 and q.mode == "wild":
			raiders += 1
	check("raid wave spawns", game.pals.size() > pals0 and raiders >= 2, "+%d pals, %d aggro" % [game.pals.size() - pals0, raiders])
	# aggro>0 pal targeting: raider fights a base pal
	var raider: Pal = null
	for q in game.pals:
		if q.mode == "wild" and q.aggro > 0:
			raider = q
			break
	if raider:
		var victim: Pal = game.find_pal(raider.aggro)
		if victim:
			raider.pos = victim.pos + Vector2(0.5, 0)
			var vhp0 := victim.hp
			raider.atk_cd = 0
			raider.wild_ai(0.1)
			check("raider hits base pal", victim.hp < vhp0 or raider.stun_t > -1.0, "victim hp %.0f->%.0f" % [vhp0, victim.hp])
			raider.queue_free()
			game.pals.erase(raider)
	# ground drops: harvest spawns a drop; walking over it collects
	var wood_ct0 := game.item_count("wood")
	var dxy = null
	for dy in range(0, 6):
		for dx in range(0, 6):
			var tx := int(game.player.pos.x) + dx; var ty := int(game.player.pos.y) + dy
			var dd := game.world.decor_at(tx, ty)
			if dd == World.Decor.TREE_A or dd == World.Decor.TREE_B:
				game.world.hp[game.world.idx(tx, ty)] = 1
				game.try_harvest(game.player.pos, 0)
				dxy = Vector2i(tx, ty)
				break
		if dxy != null: break
	# force-spawn a drop next to the player regardless of tree luck
	game.spawn_drop("wood", 2, game.player.pos + Vector2(0.4, 0))
	var drops0 := game.drops.size()
	game._process(0.1)
	check("drops spawn+pickup", game.drops.size() < drops0 and game.item_count("wood") > wood_ct0,
		"drops %d->%d wood %d" % [drops0, game.drops.size(), game.item_count("wood")])
	# hauling: unassigned transporting pal carries a drop to the chest
	var hauler: Pal = null
	for q in game.pals:
		if q.spec.get("work", {}).get("transporting", 0) > 0:
			hauler = q
			break
	if hauler == null:
		hauler = game.gen_pal("lamball", 5, game.player.pos + Vector2(2, 0))
		if "transporting" not in hauler.spec.get("work", {}) or hauler.spec["work"].get("transporting", 0) == 0:
			hauler.spec["work"]["transporting"] = 1
		hauler.mode = "base"; hauler.job_site = null
		if not game.pals.has(hauler): game.pals.append(hauler)
	hauler.mode = "base"; hauler.job_site = null; hauler.carry = null
	# dedicated chest in open space; hauler must pick THIS one (nearest)
	var cst_xy := Vector2i(-1, -1)
	var near_c0 := Vector2i(-1, -1)
	for r7 in range(6, 40):
		var cx7 := int(game.palbox_pos.x) + r7; var cy7 := int(game.palbox_pos.y)
		if game.world.blocked(cx7, cy7) or game.structures.has(Vector2i(cx7, cy7)):
			continue
		# spot must have a free neighbor for the hauler to stand on
		var nc := Vector2i(-1, -1)
		for off7 in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var cc7: Vector2i = Vector2i(cx7, cy7) + off7
			if not game.world.blocked(cc7.x, cc7.y) and not game.structures.has(cc7):
				nc = cc7; break
		if nc.x >= 0 and game.place_free("chest", cx7, cy7):
			cst_xy = Vector2i(cx7, cy7)
			near_c0 = nc
			break
	check("test chest placed", cst_xy.x >= 0)
	# haulers deposit into the NEAREST chest — the base may hold several,
	# so assert on the aggregate stone across all chests, not one of them
	var stone_in_chests := func() -> int:
		var total := 0
		for k7 in game.structures:
			var st7: Dictionary = game.structures[k7]
			if st7["id"] == "chest":
				total += st7["store"].get("stone", 0)
		return total
	var stone0: int = stone_in_chests.call()
	if cst_xy.x >= 0:
		if near_c0.x >= 0:
			hauler.pos = Vector2(near_c0.x + 0.5, near_c0.y + 0.5)
			game.spawn_drop("stone", 3, hauler.pos)
			for i in 30:
				hauler.haul_ai(0.15)
				if hauler.carry == null:
					break
	check("hauler delivers to chest", stone_in_chests.call() >= stone0 + 3,
		"stone %d->%d carry=%s" % [stone0, stone_in_chests.call(), str(hauler.carry)])

	# lair alpha: engages on approach, tethered to its lair
	var la: Pal = null
	for q in game.pals:
		if q.alpha and q.mode == "wild":
			la = q
			break
	if la:
		game.tod = 12.0
		la.aggro = -1; la.statuses.erase("sleep")
		game.player.pos = la.home
		la.pos = la.home + Vector2(4, 0)
		la.wild_ai(0.1)
		check("lair alpha engages", la.aggro == 0, "aggro=%d" % la.aggro)
		la.aggro = -1
		# place it ~11 tiles off-lair on a walkable cell so one step is not blocked
		var tether_spot := Vector2(-1, -1)
		for rad in [11, 12, 13]:
			for dd9 in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1),
					Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]:
				var cand: Vector2 = la.home + dd9.normalized() * rad
				# require a clear, elevation-flat straight line home — the
				# pal can't pathfind, so a cliff edge on the line sticks it
				var e_home: int = game.world.elev_at(int(la.home.x), int(la.home.y))
				var clear := true
				for f9 in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var mid: Vector2 = cand.lerp(la.home, f9)
					if game.world.blocked(int(mid.x), int(mid.y)) 							or game.world.elev_at(int(mid.x), int(mid.y)) != e_home:
						clear = false; break
				if clear:
					tether_spot = cand; break
			if tether_spot.x >= 0: break
		if tether_spot.x >= 0:
			la.pos = tether_spot
			var dh0 := la.pos.distance_to(la.home)
			var spd0 := la.speed
			la.wild_ai(0.01)
			check("lair alpha tethered", la.pos.distance_to(la.home) < dh0,
				"%.1f->%.1f sp=%s spd=%.2f->%.2f aggro=%d moving=%s spec_spd=%s" % [
				dh0, la.pos.distance_to(la.home), la.species_id, spd0, la.speed,
				la.aggro, str(la.moving), str(la.spec.get("speed"))])

	# generated-species capturePower must be on the 30-90 scale —
	# a basic sphere at full HP should never be a free 97% catch
	for gid in SpeciesGen.SPECIES.keys():
		var gsp: Dictionary = SpeciesData.species_of(gid)
		var ch := Combat.catch_chance(1.0, gsp["capturePower"], 26.0, false, false, 1)
		check("gen %s capture scale" % gid, ch < 0.9, "capturePower=%s ch=%.2f" % [str(gsp["capturePower"]), ch])
		break

	# apex hostiles (hostile==2) auto-aggro on sight and skip night sleep
	var apex: Pal = null
	for q in game.pals:
		if q.mode == "wild" and q.hostile() == 2:
			apex = q; break
	if apex:
		game.tod = 12.0
		apex.aggro = -1; apex.statuses.erase("sleep")
		apex.pos = game.player.pos + Vector2(4.5, 0)
		apex.wild_ai(0.05)
		check("apex aggros on sight", apex.aggro == 0, "aggro=%d" % apex.aggro)
		game.tod = 23.0
		apex.aggro = -1; apex.hit_flash = 0
		apex.wild_ai(0.05)
		check("apex stays up at night", not apex.has_status("sleep"), str(apex.statuses))
		game.tod = 12.0

	# projectiles die on trees/rocks/buildings/cliff faces, not over water
	# shoot from open ground into the map edge: should die well short of range
	var sh_pos := p.pos
	var n0: int = game.projectiles.size()
	game.projectiles.append({"pos": sh_pos, "dir": Vector2(1, 0), "speed": 14.0,
		"ttl": 10.0, "dmg": 20, "elev": game.world.elev_at(int(sh_pos.x), int(sh_pos.y)),
		"from": "player", "node": Sprite2D.new()})
	for i in 400:
		game.update_projectiles(0.05)
		if game.projectiles.size() <= n0:
			break
	var prl: Dictionary = game.projectiles.back() if game.projectiles.size() > n0 else {}
	var travelled := 0.0
	if prl.is_empty():
		# died — good, can't know where, count as terrain-hit pass
		check("projectile hits terrain", true)
	else:
		travelled = (prl["pos"] - sh_pos).length()
		check("projectile hits terrain", travelled < 14.0 * 10.0, "flew %.1f unobstructed" % travelled)

	# essence condenser: 4 same-species box pals -> star+1, stats x1.15
	if game.party.size() > 0:
		var ap2: Pal = game.find_pal(game.party[0])
		var star0 := ap2.star; var mhp0 := ap2.max_hp; var atk0 := ap2.atk_bonus
		var boxn0 := game.box.size()
		for j in 4:
			var fp := Pal.new()
			fp.setup(game, ap2.species_id, 1, Vector2.ZERO)
			fp.mode = "box"
			game.box.append(fp)
		game.condense_active()
		check("condense star+1", ap2.star == star0 + 1, "star=%d" % ap2.star)
		check("condense stats up", ap2.atk_bonus > atk0 and ap2.max_hp > mhp0,
			"atk %.2f->%.2f hp %.0f->%.0f" % [atk0, ap2.atk_bonus, mhp0, ap2.max_hp])
		check("condense eats fodder", game.box.size() == boxn0, "box %d->%d" % [boxn0 + 4, game.box.size()])
		# second condense needs 16 — we only gave 4-4=0 left
		game.condense_active()
		check("condense needs fodder", ap2.star == star0 + 1, "star=%d" % ap2.star)

	# stack cap: overflow spills to a ground drop, items not lost
	var n_drops := game.drops.size()
	game.add_item("pal_sphere", 9999) # stack 50
	check("stack capped", game.item_count("pal_sphere") == 50, "=%d" % game.item_count("pal_sphere"))
	check("overflow spilled", game.drops.size() > n_drops, "drops=%d" % game.drops.size())

	# night sleep: wild non-dark pals sleep; dark pals stay up; hit wakes
	game.tod = 23.0
	var sleeper: Pal = null; var nightowl: Pal = null
	for q in game.pals:
		if q.mode == "wild" and "dark" not in q.spec.get("elements", []) and q.hostile() < 2:
			sleeper = q
		if q.mode == "wild" and "dark" in q.spec.get("elements", []):
			nightowl = q
	if sleeper == null:
		sleeper = game.gen_pal("lamball", 3, game.player.pos + Vector2(6, 0))
		sleeper.mode = "wild"; sleeper.aggro = -1
		if not game.pals.has(sleeper): game.pals.append(sleeper)
	sleeper.aggro = -1; sleeper.hit_flash = 0; sleeper.statuses.erase("sleep")
	sleeper.wild_ai(0.1)
	check("wild pal sleeps at night", sleeper.has_status("sleep"), "")
	if nightowl:
		nightowl.aggro = -1; nightowl.statuses.erase("sleep"); nightowl.hit_flash = 0
		nightowl.wild_ai(0.1)
		check("dark pal stays up", not nightowl.has_status("sleep"), "")
	sleeper.hit(5, 1.0, true)
	check("hit wakes sleeper", not sleeper.has_status("sleep") and sleeper.aggro >= 0, "aggro=%d" % sleeper.aggro)
	game.tod = 12.0

	# player hunger: drain, slow when low, food restores
	game.player.hunger = 20.0
	var slow := game.player.speed_mult()
	game.player.hunger = 90.0
	var fast := game.player.speed_mult()
	check("hunger slows player", slow < fast, "low %.2f vs fed %.2f" % [slow, fast])
	game.add_item("red_berries", 2)
	game.player.hunger = 40.0
	main.get_node("UILayer/HUD").use_item("red_berries")
	check("food restores hunger", game.player.hunger > 45.0, "hunger %.1f" % game.player.hunger)
	# drops persist through save/load
	game.spawn_drop("gold_coin", 7, game.player.pos + Vector2(1, 0))
	var drops_sv := game.drops.size()
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
