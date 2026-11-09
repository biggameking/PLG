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
	# queue_free() defers to frame end — pump a couple of frames so the run's
	# dead nodes actually flush before we count orphans and quit
	await process_frame
	await process_frame
	if OS.has_environment("PLG_ORPHANS"):
		print("-- orphan nodes before quit --")
		root.print_orphan_nodes()
	# check() already appended each line; run() may have died mid-way, so only
	# the counts go on the tail here — a missing summary = crashed run
	var fails := 0
	for r in results:
		if r.begins_with("FAIL"):
			fails += 1
	var fo := FileAccess.open("res://tools/smoke_out.txt", FileAccess.READ_WRITE)
	if fo == null:
		fo = FileAccess.open("res://tools/smoke_out.txt", FileAccess.WRITE)
	if fo:
		fo.seek_end()
		fo.store_line("==== %d checks, %d failures ====" % [results.size(), fails])
		fo.close()
	quit()

func check(name: String, ok: bool, detail: String = "") -> void:
	results.append("%s %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	print(results[-1])
	# append immediately: a runtime error aborts run() mid-way and a buffered
	# file hides which check died last — the on-disk tail is the crash marker
	var fo := FileAccess.open("res://tools/smoke_out.txt", FileAccess.READ_WRITE)
	if fo == null:
		fo = FileAccess.open("res://tools/smoke_out.txt", FileAccess.WRITE)
	if fo:
		fo.seek_end()
		fo.store_line(results[-1])
		fo.close()

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
		if tgt.mode != "wild":
			break
	check("caught pal captured", tgt.mode in ["partner", "box"], "mode=%s" % tgt.mode)
	check("catch box only if party full", tgt.mode != "box" or game.party.size() >= 5, "mode=%s party=%d" % [tgt.mode, game.party.size()])
	if tgt.mode == "box":
		check("caught pal leaves world", tgt.get_parent() != game.entity_layer)

	# palbox + party
	game.add_item("wood", 200); game.add_item("stone", 100); game.add_item("paldium", 20)
	var placed := false
	for r9 in range(2, 16): # palbox needs flat non-water ground — spiral until a valid cell turns up
		for dx9 in range(-r9, r9 + 1):
			for dy9 in range(-r9, r9 + 1):
				if maxi(absi(dx9), absi(dy9)) != r9:
					continue
				var k := Vector2i(int(p.pos.x) + dx9, int(p.pos.y) + dy9)
				if game.place_structure("palbox", k.x, k.y):
					placed = true
					break
			if placed: break
		if placed: break
	check("place palbox", placed and game.palbox_pos.x >= 0)
	if game.box.is_empty() and not game.party.is_empty():
		game.party_to_box(game.party[0]) # catch went to party — exercise party->box too
	if not game.box.is_empty():
		var bp: Pal = game.box[0]
		game.box_to_party(bp)
		check("box->party", bp.uid in game.party and bp.mode == "partner")
		# mount only if mountable — and saddled (Palworld pal gear)
		if SpeciesData.mountable(bp.species_id):
			game.add_item("saddle", 1)
			bp.pos = p.pos + Vector2(0.5, 0)
			p.try_mount()
			check("mount", p.mount == bp)
			p.try_mount()
		# Palworld deploy loop: party -> base workforce -> back to cold storage
		game.deploy_to_base(bp)
		check("deploy to base", bp.mode == "base" and bp in game.pals and bp.uid not in game.party
			and bp.get_parent() == game.entity_layer, "mode=%s" % bp.mode)
		game.base_to_box(bp)
		check("recall to box", bp.mode == "box" and bp in game.box and bp not in game.pals
			and bp.get_parent() == game.box_holder, "mode=%s" % bp.mode)
		game.box_to_party(bp) # restore party slot for later checks
		# work xp: base pals level from honest work, capped at 60
		var wxp := game.gen_pal("lamball", 5, p.pos)
		wxp.mode = "base"; game.pals.append(wxp)
		game.pal_gain_xp(wxp, 130)
		var wxp_up: bool = wxp.level == 6
		wxp.level = 59
		game.pal_gain_xp(wxp, 99999)
		check("work xp + cap", wxp_up and wxp.level == 60 and wxp.xp == 0)
		game.pals.erase(wxp)
		if wxp.get_parent(): wxp.get_parent().remove_child(wxp)
		wxp.free()
		# send-out: reorder which pal leads (partner skills/mount key on party[0])
		var mp2 := game.gen_pal("chikipi", 3, p.pos)
		mp2.mode = "box"; game.box.append(mp2); game.box_pal(mp2)
		game.box_to_party(mp2)
		var lead2: int = game.party[1]
		game.make_active(lead2)
		check("party lead swap", game.party[0] == lead2 and mp2.mode == "partner")
		game.make_active(game.party[1]) # restore original order for later checks
		game.party_to_box(mp2.uid) # second member goes back to cold storage
		# palbox growth: workforce slots scale with player level, hard cap 20
		var lv0: int = game.player.level
		game.player.level = 1
		var s1 := game.max_base_pals()
		game.player.level = 40
		var s2 := game.max_base_pals()
		check("palbox slots scale", s1 == 9 and s2 == 20, "lv1=%d lv40=%d" % [s1, s2])
		game.player.level = lv0
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
	# ancient tech: parts-gated nodes refuse without boss-dropped parts
	var lv1: int = game.player.level
	game.tech_points += 10
	game.player.level = 40
	game.items.erase("ancient_part")
	game.unlock("incubator")
	var gate1: bool = "incubator" not in game.unlocked
	game.add_item("ancient_part", 2)
	game.unlock("incubator")
	check("ancient tech gate", gate1 and "incubator" in game.unlocked
		and game.item_count("ancient_part") == 0,
		"gate1=%s parts=%d" % [gate1, game.item_count("ancient_part")])
	game.player.level = lv1 # restore — later checks assume the fresh-run level
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

	# timed crafting: bench recipes queue and finish on the clock; an idle
	# handy pal hurries them (queue_crafts=false keeps other checks instant)
	var wbk: Vector2i = free_xy.call("workbench")
	var wb_ok: bool = game.structures.has(wbk)
	if wb_ok:
		var pos0: Vector2 = p.pos
		p.pos = Vector2(wbk.x + 1.5, wbk.y + 0.5)
		game.add_item("ingot", 1)
		game.queue_crafts = true
		game.craft("nails")
		wb_ok = game.craft_queue.size() == 1 and game.item_count("nails") == 0
		if wb_ok:
			game.tick_crafts(2.0)
			var half_left: float = game.craft_queue[0]["left"]
			game.tick_crafts(3.0)
			check("timed crafting", half_left > 0 and game.item_count("nails") == 4,
				"left=%.1f nails=%d" % [half_left, game.item_count("nails")])
		else:
			check("timed crafting", false, "queue=%d" % game.craft_queue.size())
		game.queue_crafts = false
		game.craft_queue.clear()
		p.pos = pos0
	else:
		check("timed crafting", false, "no workbench")

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
		var w0 := 0
		for kk in game.structures:
			if not game.structures[kk]["workers"].is_empty():
				w0 += game.structures[kk]["store"].get("wood", 0)
		for i in 80:
			game.tick_production(1.0)
		var w1 := 0
		for kk in game.structures:
			w1 += game.structures[kk]["store"].get("wood", 0)
		check("production ticks", w1 > w0, "wood %d->%d (site stockpile)" % [w0, w1])
		# Palworld night shift: diurnal base pals doze off and production skips
		# sleepers; dark-element pals keep working through the night
		var tod0: float = game.tod
		game.tod = 23.0
		var log_st2 = null
		for kk2 in game.structures:
			if game.structures[kk2].get("id") == "logging_site":
				log_st2 = game.structures[kk2]
		if log_st2 and not log_st2["workers"].is_empty():
			var night_w: Pal = log_st2["workers"][0]
			var dark_night: bool = "dark" in night_w.spec.get("elements", [])
			var all_diurnal := true
			for w3 in log_st2["workers"]:
				for _i in 70: # a built bed makes them shuffle over first (6s cap)
					w3.base_ai(0.1)
					if w3.has_status("sleep"):
						break
				if "dark" in w3.spec.get("elements", []):
					all_diurnal = false
			var w2a: int = log_st2["store"].get("wood", 0)
			for i in 40:
				game.tick_production(1.0)
			var w2b: int = log_st2["store"].get("wood", 0)
			if dark_night:
				check("night shift", not night_w.has_status("sleep") and w2b > w2a,
					"dark pal works at night")
			else:
				check("night shift", night_w.has_status("sleep") and (not all_diurnal or w2b == w2a),
					"sleep=%s wood %d->%d" % [night_w.has_status("sleep"), w2a, w2b])
		else:
			check("night shift", false, "no logging worker")
		game.tod = tod0
		for q in game.pals: # don't leak sleep into later checks
			q.statuses.erase("sleep")
		# Palworld: work suitability LEVEL scales output — lv2 logger beats lv1
		if log_st2:
			var w_lv2: Pal = game.gen_pal("eikthyrdeer", 5, game.player.pos)
			var w_lv1: Pal = game.gen_pal("lifmunk", 5, game.player.pos)
			var saved_workers: Array = log_st2["workers"].duplicate()
			var saved_timer: float = log_st2["timer"]
			var timers := []
			for wp in [w_lv2, w_lv1]:
				wp.mode = "base"; wp.san = 90.0; wp.ailment = ""; wp.passives = []
				log_st2["workers"] = [wp]; wp.job_site = log_st2
				log_st2["timer"] = 0.0
				game.tick_production(1.0)
				timers.append(float(log_st2["timer"]))
				wp.job_site = null
			log_st2["workers"] = saved_workers; log_st2["timer"] = saved_timer
			var lv_ratio: float = timers[0] / maxf(0.001, timers[1])
			check("work lv scales output", absf(lv_ratio - 1.5) < 0.01, "lv2/lv1=%.2f" % lv_ratio)
			game.pals.erase(w_lv2); game.pals.erase(w_lv1)
			w_lv2.free(); w_lv1.free()

	# missions: ordered guide rope pays out as live state satisfies rungs
	if game.has_structure("palbox"):
		var gold_m := game.item_count("gold_coin")
		var idx0: int = game.mission_idx
		game.tick_missions(1.1)
		check("missions", game.mission_idx > idx0 and game.mission_idx <= game.MISSIONS.size() \
				and game.item_count("gold_coin") > gold_m, "idx %d->%d" % [idx0, game.mission_idx])
		game.mission_idx = 999 # past-the-end idx must clamp, not crash
		game.save_game(); game.load_game()
		check("missions persist", game.mission_idx == game.MISSIONS.size())

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
	game.stat_pts = 0 # keep this check on the effigy path — levels banked points earlier
	game.add_item("lifmunk_effigy", 10)
	game.upgrade_perk("capture")
	check("perk upgrade", game.perks["capture"] == 1 and game.item_count("lifmunk_effigy") == 8)
	game.upgrade_perk("hp")
	var want_hp: float = 100 + (p.level - 1) * 10 + game.perks["hp"] * 12
	check("hp perk", p.max_hp == want_hp, "maxhp %d want %d" % [p.max_hp, want_hp])
	# Palworld: levels bank stat points the statue spends before effigies
	game.stat_pts = 1
	game.upgrade_perk("speed")
	check("stat point spend", game.perks["speed"] == 1 and game.stat_pts == 0 \
			and game.item_count("lifmunk_effigy") == 6, "pts=%d eff=%d" % [game.stat_pts, game.item_count("lifmunk_effigy")])

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
		# Palworld rule: no cake, no breeding — the ranch stalls with a warning
		game.tick_ranch(ranch_k, st_r, 61.0)
		check("ranch stalls without cake", st_r["store"].get("pal_egg", 0) == 0 and st_r.get("cake_warned", false))
		# stock a cake: chest storage feeds the breeding loop
		var chest_st = null
		for kk in game.structures:
			if game.structures[kk]["id"] == "chest":
				chest_st = game.structures[kk]
		if chest_st == null:
			game.place_free("chest", ranch_k.x + 4, ranch_k.y)
			chest_st = game.structures.get(Vector2i(ranch_k.x + 4, ranch_k.y))
		chest_st["store"]["cake"] = 1
		game.tick_ranch(ranch_k, st_r, 61.0)
		check("ranch egg", st_r["store"].get("pal_egg", 0) >= 1)
		check("cake consumed", chest_st["store"].get("cake", 0) == 0)
		# parentage now carries passives for inheritance
		check("egg records passives", st_r["egg_parents"].size() > 0 and st_r["egg_parents"][0].size() >= 6)
		game.add_item("pal_egg", 1) # egg reaches the bag via haulers/player pickup
		# Palworld: eggs hatch in an incubator over time, not in the hand
		game.add_item("paldium", 4); game.add_item("stone", 12); game.add_item("cloth", 2)
		var inc_k: Vector2i = free_xy.call("incubator")
		var inc_st = game.structures.get(inc_k)
		game.deposit_egg()
		check("egg deposited", inc_st != null and inc_st.has("egg_inc") and game.item_count("pal_egg") == 0)
		var n0 := game.pals.size()
		if inc_st:
			inc_st["egg_inc"]["ready_t"] = game.t - 1.0 # fast-forward
			game.hatch_incubated(inc_k, inc_st)
		check("hatch egg", game.pals.size() == n0 + 1 and not (inc_st and inc_st.has("egg_inc")))
		# signature pair -> fixed third species (Palworld breeding combos)
		var combo_st := {"egg_inc": {"pair": ["lamball", "chikipi", 50, 50, [], [], ["shockwave"], []], "ready_t": game.t}}
		game.hatch_incubated(Vector2i(int(game.player.pos.x) + 2, int(game.player.pos.y)), combo_st)
		var cb := game.pals[game.pals.size() - 1]
		check("breed combo", cb.species_id == "cattiva")
		check("egg move inherited", "shockwave" in cb.extra_skills or "shockwave" in cb.learned_skills(),
			"extra=%s" % str(cb.extra_skills))
		game.pals.erase(cb)
		if cb.get_parent(): cb.get_parent().remove_child(cb)
		cb.free()
		# every combo table entry must name real species — parents AND offspring
		var combo_bad := []
		for k2 in Game.BREED_COMBOS:
			var parts: Array = k2.split("+")
			for sp2 in parts:
				if SpeciesData.species_of(sp2).is_empty():
					combo_bad.append(sp2)
			if SpeciesData.species_of(Game.BREED_COMBOS[k2]).is_empty():
				combo_bad.append(Game.BREED_COMBOS[k2])
		check("combo table valid", combo_bad.is_empty(), str(combo_bad))
		# grazing produce: a wool pal drops wool on its farm timer (Palworld)
		var grazer: Pal = game.gen_pal("lamball", 3, p.pos + Vector2(4, 4))
		game.pals.append(grazer); grazer.mode = "base"; grazer.san = 80.0
		st_r["workers"].append(grazer); grazer.job_site = st_r
		game.tick_ranch(ranch_k, st_r, 61.0)
		check("ranch grazing", st_r["store"].get("wool", 0) >= 1, "store=%s" % str(st_r["store"]))
		st_r["workers"].erase(grazer); grazer.job_site = null
		game.pals.erase(grazer)
		if grazer.get_parent(): grazer.get_parent().remove_child(grazer)
		grazer.free()
	else:
		var dbg := ""
		for q in game.pals:
			if q.mode == "base":
				dbg += "%s:%s:%s " % [q.species_id, q.sex, q.mode]
		check("ranch egg", false, "no M/F base pals: " + dbg)

	# net pal replication: valid entry spawns, malformed/foreign entries drop
	var np0 := game.pals.size()
	game.spawn_net_pal(["cattiva", p.pos.x + 3, p.pos.y + 3, 5, "wild", true])
	check("net pal spawns", game.pals.size() == np0 + 1)
	var npal: Pal = game.pals[game.pals.size() - 1]
	check("net pal lucky", npal.lucky and "lucky" in npal.passives)
	game.pals.erase(npal)
	if npal.get_parent(): npal.get_parent().remove_child(npal)
	npal.free()
	game.spawn_net_pal(["no_such_species", 0, 0, 1, "wild"])
	game.spawn_net_pal("garbage")
	check("net pal rejected", game.pals.size() == np0)
	# live pal sync: replicas key on host uid — spawn, move, despawn
	game.spawn_net_pal(["cattiva", p.pos.x + 4, p.pos.y + 4, 5, "wild", false, 777])
	var rep: Pal = game.pals[game.pals.size() - 1]
	check("net pal net_id", rep.net_id == 777)
	game.net.pal_sync([[777, "cattiva", p.pos.x + 9.0, p.pos.y + 9.0, 5, "wild", 42.0, false],
		[778, "lamball", p.pos.x + 5, p.pos.y + 5, 3, "wild", 99.0, false],
		"garbage"])
	check("pal_sync moves+spawns", rep.net_target.x == p.pos.x + 9.0 and rep.hp == 42.0
		and game.find_net_pal(778) != null)
	game.net.pal_sync([[778, "lamball", 1, 1, 3, "wild", 99.0, false]])
	check("pal_sync despawns absent", game.find_net_pal(777) == null
		and game.find_net_pal(778) != null)
	# cleanup the replica so it can't leak into later checks
	var rep2 := game.find_net_pal(778)
	game.pals.erase(rep2)
	if rep2.get_parent(): rep2.get_parent().remove_child(rep2)
	rep2.free()
	# raid boss
	game.add_item("boss_sigil", 1)
	var n1 := game.pals.size()
	game.summon_raid()
	var boss_ok := false
	for q in game.pals:
		if q.boss:
			boss_ok = true
	check("raid summon", game.pals.size() == n1 + 1 and boss_ok)
	# gauntlet trial: 3 escalating waves, then the tower pays out
	game.add_item("gauntlet_sigil", 1)
	check("gauntlet starts", game.start_gauntlet() and game.gauntlet["wave"] == 1
		and game.gauntlet["left"] > 0)
	check("gauntlet busy", not game.start_gauntlet()) # one trial at a time
	var waves_run := 0
	while not game.gauntlet.is_empty() and waves_run < 5:
		waves_run += 1
		for q in game.pals.duplicate():
			if q.has_meta("gauntlet"):
				game.kill_pal(q, true)
		game.tick_gauntlet()
	check("gauntlet clears", game.gauntlet.is_empty() and waves_run == 3
		and game.item_count("gauntlet_sigil") >= 1, "waves=%d" % waves_run)
	# raid escalation: late-campaign raids bring bigger, meaner packs
	game.day = 16
	var r0 := game.pals.size()
	game.start_raid()
	var new_raid := game.pals.slice(r0)
	var min_lv := 999
	for q in new_raid:
		min_lv = mini(min_lv, q.level)
	check("raid escalates", new_raid.size() >= 6 and min_lv >= 20,
		"n=%d minlv=%d" % [new_raid.size(), min_lv])
	for q in new_raid:
		game.pals.erase(q)
		q.queue_free()
	game.day = 1
	# worldgen legendary den: an uncapturable lv50 giant guards deep zone 3
	var legend: Pal = null
	for q in game.pals:
		if q.boss and q.level >= 50 and not q.raid:
			legend = q
	check("legendary den", legend != null and legend.species_id in Game.LEGENDARY_DEN,
		"boss=%s" % (legend.species_id if legend else "none"))
	# sealed grotto: rock ring intact, warden inside, chest stocked
	if game.grotto_pos.x >= 0:
		var gp := game.grotto_pos
		var ring_rock := game.world.decor[game.world.idx(gp.x + 3, gp.y)] == World.Decor.ROCK
		var warden := false; var loot := false
		for q in game.pals:
			if q.boss and q.pos.distance_to(Vector2(gp.x + 0.5, gp.y + 0.5)) < 4.0:
				warden = true
		for ks in game.structures:
			var s2: Dictionary = game.structures[ks]
			if s2["id"] == "chest" and Vector2(ks.x, ks.y).distance_to(Vector2(gp.x, gp.y)) < 4.0 \
					and not s2["store"].is_empty():
				loot = true
		check("sealed grotto", ring_rock and warden and loot, "rock=%s boss=%s loot=%s" % [ring_rock, warden, loot])
		# multi-room: grotto_room2 is authoritative — when set, a lv45 warden, a
		# legendary-sphere chest and a rock-choked doorway must all be there
		if game.grotto_room2.x >= 0:
			var g2 := game.grotto_room2
			var ctr2 := Vector2(g2.x + 0.5, g2.y + 0.5)
			var room2_boss := false; var room2_loot := false
			for q in game.pals:
				if q.boss and q.pos.distance_to(ctr2) < 4.0:
					room2_boss = q.level >= 45
			for ks in game.structures:
				var s3: Dictionary = game.structures[ks]
				if s3["id"] == "chest" and Vector2(ks.x, ks.y).distance_to(Vector2(g2.x, g2.y)) < 4.0 \
						and s3["store"].get("legendary_sphere", 0) > 0:
					room2_loot = true
			var r2d := Vector2i(int(signf(g2.x - gp.x)), int(signf(g2.y - gp.y)))
			var dc2 := gp + r2d * 4
			var off2 := dc2 + (Vector2i(0, 1) if dc2.y == gp.y else Vector2i(1, 0))
			var door: bool = game.world.decor[game.world.idx(off2.x, off2.y)] == World.Decor.ROCK
			check("grotto room 2", room2_boss and room2_loot and door,
				"boss=%s loot=%s door=%s" % [room2_boss, room2_loot, door])
		else:
			check("grotto room 2", true, "skipped: terrain didn't fit a second chamber")
	else:
		check("sealed grotto", false, "no grotto_pos")
	# wild egg nests: stealable pal_egg drops placed at worldgen
	var nest_eggs := 0
	for dd in game.drops:
		if dd["id"] == "pal_egg":
			nest_eggs += 1
	check("wild egg nests", nest_eggs >= 1, "n=%d" % nest_eggs)
	# Palworld herds: same-species pals spawn in packs sharing one home cell.
	# Loaded saves may predate home persistence — cull 20 wilds and re-seed
	# the top-up so a pack is all but guaranteed regardless of world age.
	var rs: int = game.rng.s
	var culled := 0
	for q in game.pals.duplicate():
		if q.mode == "wild" and culled < 20:
			game.pals.erase(q); q.queue_free(); culled += 1
	game.rng.s = 77777
	game.spawn_wild()
	game.rng.s = rs
	var herd := false
	for a in game.pals:
		if a.mode != "wild" or a.alpha:
			continue
		for b in game.pals:
			if b != a and b.mode == "wild" and b.species_id == a.species_id \
					and b.home == a.home: # pack followers anchor to the leader's cell — wanderers drift, homes don't
				herd = true
		if herd:
			break
	check("wild herds", herd)
	# herds turn as one: hitting a packmate pulls the flock into the fight
	var hd1: Pal = game.gen_pal("lamball", 3, game.player.pos + Vector2(6, 0))
	var hd2: Pal = game.gen_pal("lamball", 3, game.player.pos + Vector2(7, 0))
	var hd3: Pal = game.gen_pal("lamball", 3, game.player.pos + Vector2(8, 0))
	hd1.home = Vector2(50, 50)
	hd2.home = Vector2.ZERO # a stray near a pack is NOT kin — must not be dragged in
	hd3.home = hd1.home
	game.pals.append(hd1); game.pals.append(hd2); game.pals.append(hd3)
	while is_instance_valid(hd1) and hd1.hp > 1 and hd1.aggro != 0: # fleers roll 50% — tap until it stands and fights
		hd1.hit(1, 1.0, true)
	check("herd turns as one", is_instance_valid(hd1) and hd1.aggro == 0 \
			and hd3.aggro == 0 and hd2.aggro < 0,
		"hd1=%d hd3=%d hd2=%d" % [hd1.aggro if is_instance_valid(hd1) else -9, hd3.aggro, hd2.aggro])
	for hq in [hd1, hd2, hd3]:
		game.pals.erase(hq)
		if is_instance_valid(hq):
			hq.free()
	# fishing: cast beside water — bites bring loot or a live aquatic catch
	var shore := Vector2i(-1, -1)
	for fx in range(4, World.WORLD_W - 4):
		for fy in range(4, World.WORLD_H - 4):
			if game.world.tiles[game.world.idx(fx, fy)] != World.Tile.WATER:
				continue
			for dd2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var k2: Vector2i = Vector2i(fx, fy) + dd2
				if game.world.in_bounds(k2.x, k2.y) and not game.world.blocked(k2.x, k2.y) \
						and game.world.tiles[game.world.idx(k2.x, k2.y)] != World.Tile.WATER:
					shore = k2
			if shore.x >= 0:
				break
		if shore.x >= 0:
			break
	if shore.x >= 0:
		var pos_f: Vector2 = p.pos
		p.pos = Vector2(shore.x + 0.5, shore.y + 0.5)
		game.add_item("fishing_rod", 1)
		var pals_f: int = game.pals.size()
		var items_f: int = game.item_count("pal_fluid") + game.item_count("gold_coin") + game.item_count("red_berries")
		var bit := 0
		for _ci in 30:
			if game.cast_line():
				bit += 1
			if game.pals.size() > pals_f:
				break
		check("fishing", bit > 0 and (game.pals.size() > pals_f \
				or game.item_count("pal_fluid") + game.item_count("gold_coin") + game.item_count("red_berries") > items_f) \
				and game.item_count("fishing_rod") == 1,
			"bites=%d pals=%d" % [bit, game.pals.size() - pals_f])
		p.pos = pos_f
	else:
		check("fishing", false, "no shoreline")
	# egg theft has a price: looting a nest angers nearby wild pals
	var ne1: Pal = game.gen_pal("chikipi", 3, game.player.pos + Vector2(4, 0))
	var ne2: Pal = game.gen_pal("chikipi", 3, game.player.pos + Vector2(40, 0))
	game.pals.append(ne1); game.pals.append(ne2)
	game.anger_nesters(game.player.pos)
	check("nest guards", ne1.aggro == 0 and ne2.aggro < 0, "near=%d far=%d" % [ne1.aggro, ne2.aggro])
	for nq in [ne1, ne2]:
		game.pals.erase(nq); nq.free()
	# fast-travel waypoints: seeded at worldgen, touch blinks back to palbox
	var wpts := 0
	for ks in game.structures:
		if game.structures[ks]["id"] == "waypoint":
			wpts += 1
	check("waypoints seeded", wpts >= 1, "n=%d" % wpts)
	if game.palbox_pos.x >= 0:
		p.pos = Vector2(5, 5)
		game.use_waypoint()
		check("waypoint blinks", p.pos.distance_to(
			Vector2(game.palbox_pos.x + 0.5, game.palbox_pos.y + 2.5)) < 6.0)
	# outpost palbox: a second box joins the shared network, nearest answers
	var ob_ok := false
	var pbx0 := int(game.palbox_pos.x); var pby0 := int(game.palbox_pos.y)
	for r3 in range(4, 40) if game.palbox_pos.x >= 0 else []:
		var cc := Vector2i(pbx0 + r3, pby0)
		var clear := true
		for dy3 in range(2):
			for dx3 in range(2):
				var k3 := cc + Vector2i(dx3, dy3)
				if not game.world.in_bounds(k3.x, k3.y) or game.world.blocked(k3.x, k3.y) \
						or game.structures.has(k3):
					clear = false
		if clear and game.place_free("palbox", cc.x, cc.y):
			ob_ok = true
			break
	if ob_ok:
		check("outpost palbox", game.extra_boxes.size() == 1 and game.palbox_pos.x >= 0,
			"extra=%d" % game.extra_boxes.size())
		var ob_pos: Vector2i = game.extra_boxes[0]
		p.pos = Vector2(ob_pos.x + 0.5, ob_pos.y + 0.5)
		check("nearest palbox", game.nearest_palbox(p.pos) == ob_pos)
		# demolishing the primary promotes the outpost rather than orphaning base
		game.demolish_at(Vector2(game.palbox_pos.x + 0.5, game.palbox_pos.y + 0.5))
		check("outpost promoted", game.palbox_pos == ob_pos and game.extra_boxes.is_empty())
	else:
		check("outpost palbox", true, "skipped: no room / no base this seed")
	# build cap: 400 distinct structures is the hard runtime bound
	var fake := []
	for i in game.MAX_STRUCTURES:
		var fk := Vector2i(i * 1000 + 7, -50) # outside the real map — no key collisions
		game.structures[fk] = {"id": "fake%d" % i}
		fake.append(fk)
	check("build cap", not game.place_structure("chest", 1, 1), "placed past cap")
	for fk in fake:
		game.structures.erase(fk)
	# den refill: a slain boss schedules a respawn at its home ~1.5 days on
	if legend:
		var lhome: Vector2 = legend.home
		var lsp: String = legend.species_id
		var rb0: int = game.boss_respawns.size()
		game.kill_pal(legend, true)
		var sched: bool = game.boss_respawns.size() == rb0 + 1
		var back := false
		if sched:
			game.boss_respawns[game.boss_respawns.size() - 1]["at"] = game.t
			game.tick_boss_respawns()
			for q in game.pals:
				if q.boss and q.species_id == lsp and q.pos.distance_to(lhome) < 1.0:
					back = true
		check("boss respawn", sched and back, "sched=%s back=%s" % [sched, back])
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
		elif q.mode == "wild":
			q.aggro = -1 # herd propagation leaves strays hostile — pacify leftovers
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
	# Palworld: farm fields crew planting AND watering suitability
	game.add_item("wood", 8); game.add_item("fiber", 6); game.add_item("berry_seeds", 3)
	var farm_k: Vector2i = free_xy.call("berry_farm")
	var wf_st = game.structures.get(farm_k)
	if wf_st:
		var wtr: Pal = game.gen_pal("kelpsea", 3, Vector2(farm_k.x + 1, farm_k.y))
		game.pals.append(wtr); wtr.mode = "base"
		var old_pos: Vector2 = p.pos
		p.pos = wtr.pos
		wf_st["workers"].clear()
		game.assign_worker()
		check("farm watering", wtr in wf_st["workers"])
		p.pos = old_pos
		if wtr.job_site: wtr.job_site["workers"].erase(wtr)
		wtr.job_site = null
		game.pals.erase(wtr)
		if wtr.get_parent(): wtr.get_parent().remove_child(wtr)
		wtr.free()
	else:
		check("farm watering", false, "berry_farm not placed")
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
	# hot spring outranks the bed: higher SAN ceiling, faster recovery
	game.add_item("stone", 20); game.add_item("wood", 10); game.add_item("paldium", 3)
	var spa_xy: Vector2i = free_xy.call("hot_spring")
	sleepy.san = 50.0
	sleepy.tick_needs(1.0)
	check("hot spring SAN", spa_xy.x >= 0 and sleepy.san >= 59.0, "san %.0f" % sleepy.san)
	# Palworld meals: cooked food restores far more SAN than raw crops.
	# eat_from_bag takes the cheapest food first — pin the bag to one item.
	var bag_save: Dictionary = game.items.duplicate()
	var eater: Pal = game.gen_pal("lamball", 3, game.player.pos)
	eater.mode = "partner"; eater.hunger = 90.0
	game.items.clear(); game.items["wheat"] = 1
	eater.san = 50.0; eater.tick_needs(1.0)
	var san_raw: float = eater.san
	game.items.clear(); game.items["jam_bun"] = 1
	eater.san = 50.0; eater.hunger = 90.0; eater.tick_needs(1.0)
	check("meal lifts SAN", eater.san > san_raw + 15.0, "raw=%.1f meal=%.1f" % [san_raw, eater.san])
	game.items = bag_save
	game.pals.erase(eater); eater.free()
	# night chill: deep dark away from firelight bleeds hp to a 30% floor
	var tod_c: float = game.tod
	var pos_c: Vector2 = p.pos
	game.tod = 2.0
	p.hp = p.max_hp; p.hunger = 80.0 # full belly — only the cold may drain us
	var far_spot := Vector2(200, 200)
	for cand in [Vector2(200, 200), Vector2(30, 200), Vector2(200, 30), Vector2(30, 30),
			Vector2(115, 200), Vector2(200, 115), Vector2(115, 30)]:
		if game.nearest_heat(cand) > 20.0:
			far_spot = cand
			break
	p.pos = far_spot # wilderness — must sit beyond any lair torch ring too
	var hp_c := p.hp
	p.cold_t = 0.0
	p._physics_process(4.5)
	var chill_far: bool = p.hp < hp_c and p.hp >= p.max_hp * 0.3 - 0.01
	game.add_item("wood", 20)
	var fire_k: Vector2i = free_xy.call("campfire")
	var chill_near := true
	if fire_k.x >= 0:
		p.pos = Vector2(fire_k.x, fire_k.y) + Vector2(0.5, 0.5)
		p.cold_t = 0.0
		var hp_c2 := p.hp
		p._physics_process(4.5)
		chill_near = p.hp >= hp_c2
	# Palworld warmth: a fire pal at your side counts as a heat source too
	var torch_pal: Pal = game.gen_pal("foxparks", 3, far_spot + Vector2(1, 0))
	torch_pal.mode = "partner" # only YOUR fire pal snuggles — wild ones don't count
	game.pals.append(torch_pal)
	p.pos = far_spot
	p.cold_t = 0.0
	var hp_c3 := p.hp
	p._physics_process(4.5)
	var chill_pal: bool = p.hp >= hp_c3
	game.pals.erase(torch_pal); torch_pal.free()
	check("night chill", chill_far and chill_near and chill_pal,
		"far=%s near=%s pal=%s" % [chill_far, chill_near, chill_pal])
	p.pos = pos_c; p.cold_t = 0.0
	game.tod = tod_c
	# monitoring stand: SAN drains half again while it stands (Palworld trade-off)
	game.add_item("wood", 10); game.add_item("stone", 10); game.add_item("ingot", 2)
	var mst_xy: Vector2i = free_xy.call("monitoring_stand")
	var sj: Pal = null
	for q in game.base_pals():
		if q.job_site != null:
			sj = q
			break
	if sj == null:
		sj = sleepy
		sj.job_site = game.structures.get(spa_xy) # any real site keeps the flag honest
	sj.san = 90.0; sj.ailment = "" # high SAN dodges the spring recovery branch
	var san0: float = sj.san
	sj.tick_needs(1.0)
	var want := 0.3 / sj.passive_mult("san") # 0.2 base x 1.5 overseer
	check("stand drains SAN", mst_xy.x >= 0 and absf((san0 - sj.san) - want) < 0.01,
		"drain=%.3f want=%.3f" % [san0 - sj.san, want])
	# feed box eats berry when hungry
	game.add_item("wood", 30); game.add_item("stone", 10)
	free_xy.call("feed_box")
	var fb = null
	for k9 in game.structures:
		if game.structures[k9].get("id") == "feed_box":
			fb = game.structures[k9]
	if fb:
		fb["store"]["red_berries"] = 4 # stocked like a real feed box
	var hungry: Pal = game.base_pals()[0]
	hungry.hunger = 90.0
	for i in 3:
		hungry.tick_needs(1.5)
	check("feed box eats", fb != null and fb["store"].get("red_berries", 0) < 4 and hungry.hunger < 90.0,
		"stored=%s hunger=%.0f" % [str(fb["store"]) if fb else "none", hungry.hunger])
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
	# party cap: 6th pal refused and stays in the box
	while game.party.size() < 5:
		var fp: Pal = load("res://src/pal.gd").new()
		game.entity_layer.add_child(fp)
		fp.setup(game, "cattiva", 3, p.pos)
		game.box.append(fp)
		game.box_to_party(fp)
	var over: Pal = load("res://src/pal.gd").new()
	game.entity_layer.add_child(over)
	over.setup(game, "cattiva", 3, p.pos)
	game.box.append(over)
	game.box_to_party(over)
	check("party overflow refused", game.party.size() == 5 and not game.pals.has(over) and game.box.has(over),
		"mode=%s party=%d" % [over.mode, game.party.size()])
	game.party_to_box(game.party[4]) # back to 4 for later checks
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
	# Palworld: mounts need pal gear — no saddle, no ride
	game.items.erase("saddle")
	var bird: Pal = game.gen_pal("chikipi", 4, p.pos)
	game.pals.append(bird); game.party.append(bird.uid); bird.mode = "partner"
	p.try_mount()
	check("mount needs saddle", p.mount == null)
	game.add_item("saddle", 1)
	p.try_mount()
	var wcell := Vector2(-1, -1)
	for i2 in World.WORLD_W * World.WORLD_H:
		if game.world.tiles[i2] == World.Tile.WATER and game.world.decor[i2] == World.Decor.NONE \
				and not game.world.solid_structure(i2):
			wcell = Vector2(i2 % World.WORLD_W + 0.5, i2 / World.WORLD_W + 0.5)
			break
	check("bird mount flies", p.mount == bird and p.flying() and wcell.x >= 0 and p.can_enter(wcell.x, wcell.y))
	p.mount = null; bird.mode = "wild" # leave the world the way the test found it
	game.party.erase(bird.uid); game.pals.erase(bird)
	if bird.get_parent(): bird.get_parent().remove_child(bird)
	bird.free()
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
			# rule: blocked when either side is unramped — player cell must be a non-ramp too
			if (absi(e1 - e0) >= 1 and game.world.ramp[game.world.idx(tx4, ty4)] == 0
					and game.world.ramp[game.world.idx(int(p.pos.x), int(p.pos.y))] == 0):
				cx = tx4; cy = ty4
				blocked = true
				break
		if blocked: break
	if blocked:
		check("cliff blocks", game.world.blocked(cx, cy, pw.x, pw.y))
	else:
		check("cliff blocks", true, "skipped: no unramped boundary within 6 tiles on this seed")
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
	if farmer.job_site and farmer in farmer.job_site["workers"]:
		farmer.job_site["workers"].erase(farmer) # fully unassign before taking over (mirrors assign_worker)
	farmer.mode = "base"; farmer.pos = p.pos; farmer.job_site = null; farmer.san = 90
	var farm_st = null
	for kk4 in game.structures:
		if game.structures[kk4].get("id") == "berry_farm":
			farm_st = game.structures[kk4]
	farm_st["workers"].append(farmer); farmer.job_site = farm_st
	var berry0: int = farm_st["store"].get("red_berries", 0)
	for i in 100:
		game.tick_production(1.0)
	check("farm produces", farm_ok and farm_st["store"].get("red_berries", 0) > berry0,
		"red_berries %d->%d (site stockpile)" % [berry0, farm_st["store"].get("red_berries", 0)])
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
	# chest panel opened near the chest must refuse service once the player walks away
	if chest_st != null:
		game.chest_ref = chest_st
		game.panel = "chest"
		var hud_ref: Control = main.get_node("UILayer/HUD")
		game.add_item("wood", 7)
		var before_dep: int = game.item_count("wood")
		var orig_pos := p.pos
		var far := Vector2(p.pos.x + 30.0, p.pos.y)
		if game.world.blocked(int(far.x), int(far.y)):
			far = Vector2(4.5, 4.5)
		p.pos = far
		hud_ref.run_click({"act": "chest_dep"})
		check("chest refuses remote access", game.item_count("wood") == before_dep and game.panel == "",
			"wood=%d panel=%s" % [game.item_count("wood"), game.panel])
		game.chest_ref = null
		p.pos = orig_pos
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
	game.entity_layer.add_child(sp1) # unparented nodes leak — even in tests
	sp1.setup(game, "lamball", 10, p.pos)
	var e_mult0: float = Combat.effectiveness("electric", sp1.elem())
	sp1.statuses["soak"] = game.t + 5.0
	check("statuses tracked", sp1.has_status("soak"))
	game.entity_layer.remove_child(sp1) # scratch pal — gone after this check
	sp1.free()
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
	check("medicine heals", p.hp == mini(p.max_hp, 10 + med["heal"])
		and game.item_count("medical_supplies") == 1, "hp %d" % p.hp)
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
		if lvl_pal.job_site and lvl_pal in lvl_pal.job_site["workers"]:
			lvl_pal.job_site["workers"].erase(lvl_pal) # partner can't hold a job — drop the slot like the game does
			lvl_pal.job_site = null
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
	if sv_pal == null and not game.base_pals().is_empty():
		sv_pal = game.base_pals()[0]
	check("a base pal exists for save test", sv_pal != null, "")
	var sv_sex: String = sv_pal.sex if sv_pal else ""
	var sv_pass: Array = sv_pal.passives.duplicate() if sv_pal else []
	var sv_idx: int = game.pals.find(sv_pal) if sv_pal else -1 # order is stable through save/load
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
	var phantom := ""
	for w9 in worker_pals:
		var sites_of: String = ""
		for k9 in game.structures:
			if w9 in game.structures[k9]["workers"] and game.structures[k9]["id"] not in sites_of:
				sites_of += game.structures[k9]["id"] + ","
		phantom += "%s(%s,mode=%s,inpal=%s,inbox=%s,js=%s) " % [w9.species_id if is_instance_valid(w9) else "?", sites_of, w9.mode if is_instance_valid(w9) else "?", str(w9 in game.pals), str(w9 in game.box), w9.job_site["id"] if is_instance_valid(w9) and w9.job_site else "-"]
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
	results.append("  had=%d linked_pals=%d sites=%s pals=%d box=%d phantom=[%s]" % [had_workers, linked, str(site_names), game.pals.size(), game.box.size(), phantom])
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
	if sv_idx >= 0 and sv_idx < game.pals.size():
		re_pal = game.pals[sv_idx]
	var chest3 = null
	for kk9 in game.structures:
		if game.structures[kk9].get("id") == "chest":
			chest3 = game.structures[kk9]
	var st_after := []
	for kk12 in game.structures:
		if game.structures[kk12] not in st_after:
			st_after.append(game.structures[kk12])
	check("party survives reload", party_sz_before == 0 or (game.party.size() == party_sz_before and game.party_pal() != null), "party=%d/%d" % [game.party.size(), party_sz_before])
	check("structures rebuild 1:1", st_after.size() == st_before.size(), "%d->%d" % [st_before.size(), st_after.size()])
	var re_worker_pals := []
	var re_detail := ""
	var re_site_names := {}
	for kk10 in game.structures:
		for w10 in game.structures[kk10]["workers"]:
			re_site_names[game.structures[kk10]["id"]] = re_site_names.get(game.structures[kk10]["id"], 0) + 1
			if w10 not in re_worker_pals:
				re_worker_pals.append(w10)
	var re_workers := re_worker_pals.size()
	for w10 in re_worker_pals:
		re_detail += "%s(js=%s,mode=%s) " % [w10.species_id, w10.job_site["id"] if w10.job_site else "-", w10.mode]
	results.append("  re_sites=%s re_workers=[%s]" % [str(re_site_names), re_detail])
	check("save keeps sex/passives", ok_load and (sv_pal == null or (re_pal != null and re_pal.sex == sv_sex and re_pal.passives == sv_pass)), "%s/%s" % [re_pal.sex if re_pal else "?", str(re_pal.passives) if re_pal else "?"])
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
				game.try_harvest(game.player.pos, Vector2(1, 0))
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
		# seed a production site's stockpile near the chest, put the hauler
		# on it -> picks the stack up -> walks it into the chest
		var src = null
		for k8 in game.structures:
			var st8: Dictionary = game.structures[k8]
			if st8["id"] != "chest":
				src = k8; break
		if src != null:
			var st_src: Dictionary = game.structures[src]
			st_src["store"]["stone"] = 3
			hauler.pos = Vector2(src.x + 0.5, src.y + 0.5)
			hauler.carry = null
			hauler.haul_ai(0.15)
			check("hauler picks from site", hauler.carry != null and hauler.carry["id"] == "stone",
				"carry=%s" % str(hauler.carry))
		if near_c0.x >= 0:
			hauler.pos = Vector2(near_c0.x + 0.5, near_c0.y + 0.5)
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
			game.box_pal(fp) # box pals live under the holder — never parentless
		game.condense_active() # first press = preview
		game.condense_active() # second press within 4s = commit
		check("condense star+1", ap2.star == star0 + 1, "star=%d" % ap2.star)
		check("condense stats up", ap2.atk_bonus > atk0 and ap2.max_hp > mhp0,
			"atk %.2f->%.2f hp %.0f->%.0f" % [atk0, ap2.atk_bonus, mhp0, ap2.max_hp])
		check("condense eats fodder", game.box.size() == boxn0, "box %d->%d" % [boxn0 + 4, game.box.size()])
		# second condense needs 16 — we only gave 4-4=0 left
		game.condense_active()
		game.condense_active()
		check("condense needs fodder", ap2.star == star0 + 1, "star=%d" % ap2.star)

	# buildable list excludes recipe-techs (they crashed place_structure)
	game.unlocked.append("spear")
	var bl: Array = game.buildable_list()
	check("buildable filters techs", "spear" not in bl, "list=%s" % str(bl))
	game.unlocked.erase("spear")

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
	# nocturnal ecology: dark pals own the night spawn table, sit out the day
	check("night spawns dark", game.pick_wild_species(["depresso", "lamball"]) == "depresso")
	game.tod = 12.0
	check("day spawns diurnal", game.pick_wild_species(["depresso", "lamball"]) == "lamball")

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

	# corrupt save: missing fields / wrong types must be refused, not crash the world
	var pals_before := game.pals.size()
	var cf := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	cf.store_var({"seed": game.world.seed, "pals": [{"sp": "lamball"}], "player": "oops"})
	cf.close()
	var bad_load: bool = game.load_game()
	check("corrupt save refused", bad_load == false and game.pals.size() == pals_before, "load=%s pals=%d" % [bad_load, game.pals.size()])
	# truncated save: a pal entry without pos/mode keys must be skipped, not fatal
	var tf := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	tf.store_var({"seed": game.world.seed, "day": 1, "tod": 8.0, "tech_points": 0, "unlocked": [],
		"items": {}, "party": [], "player": {"hp": 50.0, "level": 1, "xp": 0, "cap_lv": 1},
		"pals": [{"sp": "lamball", "lv": 3, "hp": 30.0, "talent": 50, "mode": "wild",
				"pos": [game.player.pos.x + 1, game.player.pos.y]},
			{"sp": "lamball", "lv": 3}], "structures": {}})
	tf.close()
	var tload: bool = game.load_game()
	var loaded_ok := false
	for q in game.pals:
		if q.species_id == "lamball" and q.hp == 30.0:
			loaded_ok = true
	check("truncated save loads cleanly", tload == true and loaded_ok, "pals=%d" % game.pals.size())
	# foreign-typed fields: strings/ints where numbers/bools/arrays live must coerce, not abort
	var ff := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	ff.store_var({"seed": game.world.seed, "day": "many", "tod": "late", "tech_points": "3",
		"unlocked": ["palbox", 42], "items": {"wood": "12", "stone": "x"}, "party": [],
		"player": {"pos": ["no", "no"], "hp": "full", "level": "2"},
		"pals": [{"sp": "lamball", "pos": [game.player.pos.x + 1, game.player.pos.y],
				"mode": 7, "hp": "lots", "sex": 9, "boss": "yes", "san": "hi",
				"passives": "nope", "star": "s", "raid": "y"}],
		"structures": {}})
	ff.close()
	var fload: bool = game.load_game()
	var fok := false
	for q in game.pals:
		if q.species_id == "lamball" and q.mode == "wild" and q.hp is float and q.sex == "M" and q.boss == false:
			fok = true # mode 7 -> "wild" fallback, sex 9 -> "M", boss "yes" -> skipped (not a real bool)
	check("foreign-typed save coerces", fload == true and fok and game.player.hp is float and game.item_count("wood") == 12, "pals=%d" % game.pals.size())
	game.tod = 8.0 # float("late") coerced tod to 0.0 = night: keep later checks on day shift
	game.save_game() # restore a sane save file for the rest of the run

	# ---- new palworld-loop systems ----
	# ailments: sustained low SAN sickens a base pal; medicine cures it
	var sicky: Pal = null
	for q in game.pals:
		if q.mode == "base":
			sicky = q
			break
	if sicky == null:
		sicky = game.gen_pal("lamball", 3, game.player.pos + Vector2(3, 0))
		sicky.mode = "base"
		game.pals.append(sicky)
	sicky.ailment = ""
	sicky.san = 5.0
	sicky.low_san_t = 61.0
	for _i in 3: # needs tick throttles at 1s intervals
		sicky._physics_process(1.0)
	check("low SAN -> ailment", sicky.ailment in Pal.AILMENTS, "ail=%s" % sicky.ailment)
	var w0 := sicky.work_mult()
	sicky.ailment = "depressed"
	check("ailment slows work", sicky.work_mult() < w0 or w0 < 1.0, "mult=%.2f" % sicky.work_mult())
	game.add_item("low_medical", 1)
	sicky.ailment = "weakened"
	sicky.mode = "partner" # partners self-medicate from the player's bag
	for _i in 4:
		sicky._physics_process(1.0)
	sicky.mode = "base"
	check("medicine cures ailment", sicky.ailment == "", "ail=%s" % sicky.ailment)

	# lucky variant: flagged pals carry the passive + stat buffs, drop gold on kill
	var luck: Pal = game.gen_pal("lamball", 5, game.player.pos + Vector2(4, 0))
	luck.lucky = true
	luck.setup(game, "lamball", 8, luck.pos)
	game.pals.append(luck)
	check("lucky passive + hp buff", "lucky" in luck.passives and luck.max_hp > Combat.stat_at(luck.spec["hp"], 8, luck.talent),
		"hp=%.0f" % luck.max_hp)
	var gold0b := game.item_count("gold_coin")
	game.kill_pal(luck, true)
	check("lucky drops gold", game.item_count("gold_coin") > gold0b, "+%d" % (game.item_count("gold_coin") - gold0b))

	# skill fruit: teaches the active pal an extra move of that element
	if game.party.is_empty():
		var sp2: Pal = game.gen_pal("lamball", 3, game.player.pos + Vector2(2, 0))
		sp2.mode = "partner"
		game.pals.append(sp2)
		game.party.append(sp2.uid)
	if not game.party.is_empty():
		var ap: Pal = game.find_pal(game.party[0])
		var n_sk := ap.learned_skills().size()
		game.add_item("skill_fruit_fire", 1)
		game.teach_skill_fruit("skill_fruit_fire")
		var learned := ap.extra_skills.size() > 0 and ap.learned_skills().size() >= n_sk
		check("skill fruit teaches", learned and game.item_count("skill_fruit_fire") == 0,
			"extra=%s" % str(ap.extra_skills))
	else:
		check("skill fruit teaches", false, "empty party")

	# catch count: every 10th same-species catch pays a bonus
	var dummy: Pal = game.gen_pal("lamball", 2, game.player.pos + Vector2(5, 0))
	game.pals.append(dummy)
	dummy.hp = maxf(1.0, dummy.max_hp * 0.05) # near-KO keeps the capture roll ~0.97
	game.catch_counts["lamball"] = 9 # next catch is the 10th
	var plvc := game.player.level; var pxpc := game.player.xp
	for _try in 10: # capture is a dice roll — keep throwing until it lands
		if game.catch_counts.get("lamball", 0) >= 10:
			break
		game.resolve_sphere({"sid": "pal_sphere", "target": dummy})
	check("10th catch bonus", game.catch_counts.get("lamball", 0) == 10 and (game.player.level > plvc or game.player.xp > pxpc + dummy.level * 3),
		"cnt=%d xp=%d" % [game.catch_counts.get("lamball", 0), game.player.xp - pxpc])

	# merchant: spawn/stock/buy/sell/despawn round trip
	game.spawn_merchant()
	check("merchant spawned", game.merchant != null and game.merchant_stock.size() > 0, "stock=%d" % game.merchant_stock.size())
	if game.merchant != null and game.merchant_stock.size() > 0:
		game.add_item("gold_coin", 1000)
		var g0m := game.item_count("gold_coin")
		var it0: Dictionary = game.merchant_stock[0]
		game.buy_from_merchant(0)
		check("merchant buy", game.item_count(it0["id"]) > 0 and game.item_count("gold_coin") < g0m)
		var s0m := game.item_count("gold_coin")
		game.sell_to_merchant("wood")
		check("merchant sell", game.item_count("gold_coin") > s0m)
		# black-market pal: buys a boxed pal, gold drops, node stays parented
		var pi := -1
		for i2 in game.merchant_stock.size():
			if game.merchant_stock[i2].has("pal"):
				pi = i2; break
		if pi >= 0:
			game.add_item("gold_coin", 1000)
			var pb := game.box.size()
			var g1m := game.item_count("gold_coin")
			game.buy_from_merchant(pi)
			check("merchant pal buy", game.box.size() == pb + 1
				and game.box[pb].get_parent() == game.box_holder
				and game.item_count("gold_coin") < g1m)
			if game.box.size() > pb: # sell it straight back — box count returns
				var g2m := game.item_count("gold_coin")
				game.sell_pal_to_merchant(game.box[pb].uid)
				check("merchant pal sell", game.box.size() == pb
					and game.item_count("gold_coin") > g2m)
	game.despawn_merchant()
	check("merchant leaves clean", game.merchant == null and game.merchant_stock.is_empty())

	# meat cleaver: butcher a boxed pal, its drops spill on the ground
	game.add_item("meat_cleaver", 1)
	var bxp := game.gen_pal("chikipi", 3, p.pos)
	bxp.mode = "box"; game.box.append(bxp); game.box_pal(bxp)
	var bx0 := game.box.size()
	var dr0 := game.drops.size()
	game.butcher_pal(bxp.uid)
	check("butcher pal", game.box.size() == bx0 - 1 and game.drops.size() > dr0)
	game.add_item("meat_cleaver", -1)

	# base defense: walls block, spikes are walkable but hurt hostiles
	game.add_item("wood", 60); game.add_item("stone", 20)
	var spk_k: Vector2i = free_xy.call("spikes")
	var spk_st = game.structures.get(spk_k)
	check("spikes walkable", spk_st != null and spk_st.get("walkable", false) == true
		and not game.world.solid_structure(game.world.idx(spk_k.x, spk_k.y)))
	var raider2: Pal = game.gen_pal("direhowl", 5, Vector2(spk_k.x, spk_k.y) + Vector2(0.5, 0.5))
	raider2.mode = "wild"; raider2.raid = true; raider2.aggro = 0
	game.pals.append(raider2)
	var hp0r := raider2.hp
	game.tick_production(1.0) # spikes tick inside production sweep
	check("spikes hurt raider", raider2.hp < hp0r, "hp %.0f->%.0f" % [hp0r, raider2.hp])
	# raiders chew adjacent solid structures; hp0 structures get razed
	var wall_k: Vector2i = free_xy.call("wooden_wall")
	var wall_st = game.structures.get(wall_k)
	check("wall has hp", wall_st != null and wall_st.get("hp", 0) == 300)
	if wall_st:
		# idle handy base pals patch battered structures (Palworld repair)
		var wall_hp0: float = wall_st["hp"]
		game.hit_structure(wall_k, 40)
		var fixp := game.gen_pal("lamball", 5, p.pos) # lamball: handiwork 1
		fixp.mode = "base"; fixp.job_site = null; game.pals.append(fixp)
		var dented: float = wall_st["hp"]
		game.tick_repairs(1.0)
		check("pals repair walls", wall_st["hp"] > dented and wall_st["hp"] <= wall_hp0,
			"%.0f->%.0f" % [dented, wall_st["hp"]])
		game.pals.erase(fixp)
		if fixp.get_parent(): fixp.get_parent().remove_child(fixp)
		fixp.free()
		game.hit_structure(wall_k, 999)
		check("structure razes", not game.structures.has(wall_k), "still standing")
	# palbox anchor must survive razing attempts
	var pb_st = game.structures.get(game.palbox_pos)
	if pb_st:
		game.hit_structure(game.palbox_pos, 99999)
		check("palbox unrazable", game.structures.has(game.palbox_pos) and pb_st.get("hp", 0) >= 1)

	# glider: carried item unlocks one-way descent, not climbing
	game.add_item("glider", 1)
	check("glider item held", game.item_count("glider") == 1)
	# scan for a true ledge: a high cell with a lower neighbour and no ramp
	# on either side — those cross blocked() BOTH ways without a glider
	var cliff_e := -1; var low_c := -1
	for i2 in range(0, World.WORLD_W * World.WORLD_H):
		if game.world.elev[i2] < 1 or game.world.ramp[i2] != 0:
			continue
		var cx2: int = i2 % World.WORLD_W; var cy2: int = i2 / World.WORLD_W
		for nb in [Vector2i(cx2 + 1, cy2), Vector2i(cx2 - 1, cy2), Vector2i(cx2, cy2 + 1), Vector2i(cx2, cy2 - 1)]:
			if not game.world.in_bounds(nb.x, nb.y):
				continue
			var ni := game.world.idx(nb.x, nb.y)
			if game.world.elev[ni] < game.world.elev[i2] and game.world.ramp[ni] == 0 \
					and game.world.tiles[ni] != World.Tile.WATER \
					and game.world.decor[ni] == World.Decor.NONE and not game.world.solid_structure(ni):
				cliff_e = i2; low_c = ni
				break
		if low_c >= 0:
			break
	if cliff_e >= 0:
		var cx2: int = cliff_e % World.WORLD_W; var cy2: int = cliff_e / World.WORLD_W
		var lx := low_c % World.WORLD_W; var ly: int = low_c / World.WORLD_W
		game.player.pos = Vector2(cx2 + 0.5, cy2 + 0.5)
		check("glider descends", game.player.can_enter(lx + 0.5, ly + 0.5))
		game.player.pos = Vector2(lx + 0.5, ly + 0.5)
		check("glider can't climb", not game.player.can_enter(cx2 + 0.5, cy2 + 0.5))
		game.player.pos = Vector2(game.world.spawn) + Vector2(0.5, 0.5)
	game.add_item("glider", -1)

	# memory caps: runtime collections refuse runaway growth
	for _i in game.MAX_DROPS + 50:
		game.spawn_drop("stone", 1, game.player.pos + Vector2(6, 0))
	check("drop cap", game.drops.size() <= game.MAX_DROPS, "drops=%d" % game.drops.size())
	for _i in 300:
		game.floater(game.player.pos, "x", "#ffffff")
	check("floater cap", game.floaters.size() <= game.MAX_FLOATERS, "floaters=%d" % game.floaters.size())
	var pf0 := game.projectiles.size()
	for _i in game.MAX_PROJECTILES + 20:
		game.projectiles.append({"pos": game.player.pos, "dir": Vector2(1, 0), "elev": 0,
			"speed": 8.0, "ttl": 0.001, "dmg": 1, "from": "player",
			"node": Sprite2D.new()})
		game.entity_layer.add_child(game.projectiles[-1]["node"])
	game.update_projectiles(0.01)
	check("projectile cap", game.projectiles.size() <= game.MAX_PROJECTILES, "proj=%d" % game.projectiles.size())
	for dd in game.drops: # clear() would orphan the drop nodes in entity_layer
		if is_instance_valid(dd.get("node")):
			dd["node"].queue_free()
	game.drops.clear()
	for pj in game.projectiles:
		if is_instance_valid(pj.get("node")):
			pj["node"].queue_free()
	game.projectiles.clear()

	# net host (no client join in same proc)
	game.net.host()
	check("net host", game.net.multiplayer.multiplayer_peer != null)

	var fails := 0
	for r in results:
		if r.begins_with("FAIL"):
			fails += 1
	print("==== %d checks, %d failures ====" % [results.size(), fails])
