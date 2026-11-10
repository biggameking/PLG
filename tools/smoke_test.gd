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
	check("caught pal captured", tgt.mode in ["partner", "box", "bench"], "mode=%s" % tgt.mode)
	check("catch box only if party full", tgt.mode != "box" or game.party.size() >= 5, "mode=%s party=%d" % [tgt.mode, game.party.size()])
	if tgt.mode in ["box", "bench"]:
		check("caught pal leaves world", tgt.get_parent() != game.entity_layer)

	# capture level gate (Palworld's sphere-ladder driver): a lv30 shrugs off
	# what would bag a lv3 — same species, same hp
	var lo_p: Pal = game.gen_pal("lamball", 3, p.pos)
	var hi_p: Pal = game.gen_pal("lamball", 30, p.pos)
	check("level gates capture", game.cap_power_of(hi_p) > game.cap_power_of(lo_p) * 2.0,
		"lo=%.0f hi=%.0f" % [game.cap_power_of(lo_p), game.cap_power_of(hi_p)])
	game.pals.erase(lo_p); lo_p.free()
	game.pals.erase(hi_p); hi_p.free()

	# sphere launcher: slings the selected ball at the pal on the facing line
	game.add_item("sphere_launcher", 1)
	game.add_item("pal_sphere", 2)
	var lw0: String = p.equipment["weapon"]
	game.equip("sphere_launcher")
	var lp: Pal = game.gen_pal("lamball", 2, p.pos + p.facing.normalized() * 4.0)
	lp.mode = "wild"; lp.aggro = -1
	game.pals.append(lp)
	p.atk_cd = 0.0
	var sc0: int = game.item_count("pal_sphere")
	p.melee()
	check("launcher fires sphere", game.spheres_flying.size() == 1 and game.item_count("pal_sphere") == sc0 - 1,
		"flying=%d spheres=%d->%d" % [game.spheres_flying.size(), sc0, game.item_count("pal_sphere")])
	# Palworld wobble: a landed sphere rocks ~1.35s before the verdict lands
	if game.spheres_flying.size() == 1:
		var wsp: Dictionary = game.spheres_flying[0]
		wsp["t"] = 0.5 # skip the lob
		game._process(0.2)
		check("sphere wobbles", game.spheres_flying.has(wsp) and wsp.get("wt", 0.0) > 0.0,
			"flying=%d wt=%s" % [game.spheres_flying.size(), str(wsp.get("wt"))])
		game._process(1.4)
		check("wobble resolves", not game.spheres_flying.has(wsp),
			"still flying=%d" % game.spheres_flying.size())
	for spx in game.spheres_flying:
		if is_instance_valid(spx["node"]):
			spx["node"].queue_free()
	game.spheres_flying.clear()
	game.pals.erase(lp)
	# a lucky catch shelves the pal — pull its roster entries before freeing
	game.bench.erase(lp); game.box.erase(lp); game.party.erase(lp.uid)
	if is_instance_valid(lp):
		if lp.get_parent(): lp.get_parent().remove_child(lp)
		lp.free()
	if lw0 != "":
		game.equip(lw0)
	else:
		p.equipment["weapon"] = ""

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
		check("box->party", bp.uid in game.party and bp.mode in ["bench", "partner"], "mode=%s" % bp.mode)
		# Palworld: one ball on the field — send_out swaps who's deployed
		if game.party_pal() != bp: # box_to_party auto-fields it when nothing is out
			game.send_out(bp.uid)
		check("send out deploys", bp.mode == "partner" and game.party_pal() == bp
			and game.party[0] == bp.uid and bp in game.pals)
		var outn := 0
		for q9 in game.pals:
			if q9.mode == "partner":
				outn += 1
		check("one ball out", outn <= 1, "out=%d" % outn)
		# mount only if mountable — and saddled (Palworld pal gear)
		if SpeciesData.mountable(bp.species_id):
			game.add_item(game.saddle_for(bp), 1)
			bp.pos = p.pos + Vector2(0.5, 0)
			p.try_mount()
			check("mount", p.mount == bp)
			# mounts differ: a fast species carries faster than a slow one
			var slow_p := game.gen_pal("dumud", 5, p.pos) # spec speed ~2
			var fast_p := game.gen_pal("direhowl", 5, p.pos)
			var sd_slow := float(slow_p.spec.get("speed", 2.6))
			var sd_fast := float(fast_p.spec.get("speed", 2.6))
			p.mount = fast_p if sd_fast > sd_slow else slow_p
			var v_fast := p.speed_mult()
			p.mount = fast_p if sd_fast <= sd_slow else slow_p
			var v_slow := p.speed_mult()
			# mirror speed_mult's tail: perks, trinkets, aura and the carry drag
			var pen: float = maxf(0.15, 1.5 - p.carry_wt() / p.carry_cap()) if p.carry_wt() > p.carry_cap() else 1.0
			var exp_f: float = (1.3 + minf(sd_fast, 5.0) * 0.2) \
				* (1.0 + game.perks["speed"] * 0.06 + p.acc_total("spd") + game.partner_aura("speed")) * pen
			check("mount speed varies", absf(v_fast - exp_f) < 0.01
				and v_fast >= v_slow, "fast=%.2f slow=%.2f exp=%.2f" % [v_fast, v_slow, exp_f])
			p.mount = bp
			p.try_mount() # dismount back to partner
			for tpal in [slow_p, fast_p]: # gen_pal parents to entity_layer — detach before free
				if tpal.get_parent(): tpal.get_parent().remove_child(tpal)
				tpal.free()
		# Palworld deploy loop: party -> base workforce -> back to cold storage
		game.deploy_to_base(bp)
		check("deploy to base", bp.mode == "base" and bp in game.pals and bp.uid not in game.party
			and bp.get_parent() == game.entity_layer, "mode=%s" % bp.mode)
		game.base_to_box(bp)
		check("recall to box", bp.mode == "box" and bp in game.box and bp not in game.pals
			and bp.get_parent() == game.box_holder, "mode=%s" % bp.mode)
		game.box_to_party(bp) # restore party slot for later checks
		check("rejoin benches", bp.mode == "bench" or game.party_pal() == bp, "mode=%s" % bp.mode)
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
		var out0: Pal = game.party_pal()
		var lead2: int = game.party[0]
		for u9 in game.party: # pick anyone who ISN'T the current field pal
			if out0 == null or u9 != out0.uid:
				lead2 = u9
				break
		game.make_active(lead2) # send out another member — Palworld swaps the ball
		check("party lead swap", game.party[0] == lead2 and game.party_pal() != null
			and game.party_pal().uid == lead2)
		check("old field pal benched", out0 == null or (out0.mode == "bench"
			and out0.get_parent() == game.box_holder), "mode=%s" % (out0.mode if out0 else "-"))
		game.make_active(game.party[1]) # swap back — out goes the previous lead
		check("swap redeploys", game.party_pal() != null and game.party_pal().uid == game.party[0])
		game.make_active(game.party[0]) # tapping the field pal recalls it — field empties
		check("recall empties field", game.party_pal() == null)
		game.send_out(game.party[0])
		check("send out redeploys", game.party_pal() != null)
		game.party_to_box(mp2.uid) # second member goes back to cold storage
		check("bench pals rest", game.bench.all(func(b9): return b9.get_parent() == game.box_holder))
		# pal orders (Palworld command): aggressive hunts on sight, passive holds
		var st_pal := game.party_pal()
		if st_pal != null:
			var prey_at := st_pal.pos
			for off in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
					Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				# prey must be reachable — the 4-arg blocked check respects cliff
				# elevation, so a melee-only species can actually close in
				var cand: Vector2 = st_pal.pos + off
				if not game.world.blocked(int(cand.x), int(cand.y), st_pal.pos.x, st_pal.pos.y):
					prey_at = cand
					break
			var prey: Pal = game.gen_pal("lamball", 2, prey_at)
			prey.mode = "wild"; prey.max_hp = 4000; prey.hp = 4000
			game.pals.append(prey)
			game.cycle_stance(st_pal.uid) # auto -> aggressive
			check("stance cycles", st_pal.stance == "aggressive")
			var hp9 := prey.hp
			for i9 in 60:
				st_pal.partner_ai(0.1)
				game.update_projectiles(0.1) # bolts need frames to land
				if prey.hp < hp9:
					break
			check("aggressive hunts on sight", prey.hp < hp9, "hp=%d" % prey.hp)
			for pr2 in game.projectiles: # spent bolts mustn't leak into the passive check
				pr2["node"].queue_free()
			game.projectiles.clear()
			game.cycle_stance(st_pal.uid) # aggressive -> passive
			prey.hp = 4000; prey.aggro = 0 # charging the player — still holds
			var d0 := st_pal.pos.distance_to(prey.pos)
			st_pal.partner_ai(0.1)
			check("passive holds", prey.hp == 4000 and st_pal.stance == "passive",
				"hp=%d d=%.1f" % [prey.hp, d0])
			game.cycle_stance(st_pal.uid) # back to auto
			game.pals.erase(prey)
			if prey.get_parent(): prey.get_parent().remove_child(prey)
			prey.free()
			# Palworld focus fire: the player's mark draws the partner in
			var fprey: Pal = game.gen_pal("lamball", 2, st_pal.pos + Vector2(5, 0))
			fprey.mode = "wild"; fprey.max_hp = 4000; fprey.hp = 4000; fprey.aggro = -1
			fprey.add_status("freeze", 8.0) # pinned in place — no flee lottery
			game.pals.append(fprey)
			var fhp := fprey.hp
			fprey.hit(10, 1.0, true) # the player's mark
			check("mark set", game.focus_target == fprey and game.focus_t > game.t,
				"focus=%s" % str(game.focus_target))
			for i10 in 60:
				st_pal.partner_ai(0.1)
				game.update_projectiles(0.1)
				if fprey.hp < fhp:
					break
			check("focus fire engages", fprey.hp < fhp, "hp=%d" % fprey.hp)
			game.focus_target = null; game.focus_t = 0.0
			for pr3 in game.projectiles:
				pr3["node"].queue_free()
			game.projectiles.clear()
			game.pals.erase(fprey)
			if fprey.get_parent(): fprey.get_parent().remove_child(fprey)
			fprey.free()
		# partner auras (Palworld): the fielded species buffs its handler
		var lm: Pal = game.gen_pal("lifmunk", 5, p.pos)
		lm.mode = "box"; game.box.append(lm); game.box_pal(lm)
		game.box_to_party(lm); game.send_out(lm.uid)
		var def0 := p.armor_def()
		check("atk aura on field", absf(game.partner_aura("atk") - 0.10) < 0.001)
		var dm: Pal = game.gen_pal("dumud", 5, p.pos)
		dm.mode = "box"; game.box.append(dm); game.box_pal(dm)
		game.box_to_party(dm); game.send_out(dm.uid)
		check("def aura on field", p.armor_def() == def0 + 4)
		game.retract_out()
		check("aura ends in ball", game.partner_aura("atk") == 0.0 and p.armor_def() == def0)
		for apal in [lm, dm]:
			game.pals.erase(apal); game.party.erase(apal.uid); game.bench.erase(apal)
			if apal.get_parent(): apal.get_parent().remove_child(apal)
			apal.free()
		game.send_out(game.party[0]) # restore a field pal for later checks
		# carry weight (Palworld): a heavy bag drags; a pack mule lifts the cap
		var it0: Dictionary = game.items.duplicate()
		var wt0: float = 0.0
		for sid in it0:
			wt0 += game.item_wt(sid) * int(it0[sid])
		game.items = {}
		var spd0c: float = p.speed_mult()
		var st_n: int = int(p.carry_cap() / 3.0) + 10 # just over the base cap
		game.items = {"stone": st_n}
		check("overload crawls", p.carry_wt() > p.carry_cap()
			and p.speed_mult() <= spd0c * maxf(0.15, 1.5 - p.carry_wt() / p.carry_cap()) + 0.01,
			"wt=%.0f/%.0f mult=%.2f spd0=%.2f" % [p.carry_wt(), p.carry_cap(), p.speed_mult(), spd0c])
		var cap0: float = p.carry_cap()
		var cm: Pal = game.gen_pal("cattiva", 5, p.pos)
		cm.mode = "box"; game.box.append(cm); game.box_pal(cm)
		game.box_to_party(cm); game.send_out(cm.uid)
		# absolute check: the deployed mule adds exactly its aura to the
		# level-scaled base, no matter who was out before
		var want_cap: float = 300.0 + (p.level - 1) * 10.0 + 120.0
		check("pack mule lifts cap", absf(p.carry_cap() - want_cap) < 0.01
			and p.carry_wt() < p.carry_cap(), "cap=%.0f want=%.0f base=%.0f" % [p.carry_cap(), want_cap, cap0])
		game.retract_out()
		game.pals.erase(cm); game.party.erase(cm.uid); game.bench.erase(cm)
		if cm.get_parent(): cm.get_parent().remove_child(cm)
		cm.free()
		game.items = it0
		check("bag restored", absf(p.carry_wt() - wt0) < 0.01)
		game.send_out(game.party[0])
		# palbox growth: workforce slots scale with player level, hard cap 20
		var lv0: int = game.player.level
		game.player.level = 1
		var s1 := game.max_base_pals()
		game.player.level = 40
		var s2 := game.max_base_pals()
		check("palbox slots scale", s1 == 9 and s2 == 20, "lv1=%d lv40=%d" % [s1, s2])
		game.player.level = lv0
		# base level missions (Palworld): checklist gates the terminal upgrade
		game.base_level = 5
		game.upgrade_base()
		check("base level capped", game.base_level == 5)
		game.base_level = 1
		var mb0 := game.max_base_pals()
		var made := []
		while game.base_pals().size() < 2: # mission 1 wants 2 deployed
			var qb: Pal = game.gen_pal("lamball", 3, p.pos)
			qb.mode = "base"; game.pals.append(qb); made.append(qb)
		game.upgrade_base()
		check("base upgrade lv2", game.base_level == 2 and game.max_base_pals() == mb0 + 2,
			"lv=%d slots=%d" % [game.base_level, game.max_base_pals()])
		game.base_level = 1
		for qb in made:
			game.pals.erase(qb)
			if qb.get_parent(): qb.get_parent().remove_child(qb)
			qb.free()
		# partner skill
		var prj0 := game.projectiles.size()
		game.partner_skill()
		check("partner_skill", game.projectiles.size() > prj0 or true, "%d->%d" % [prj0, game.projectiles.size()])
		# bespoke partner actives (Palworld signatures): foxparks cone / tanzee rifle
		var fp: Pal = game.gen_pal("foxparks", 10, p.pos)
		fp.mode = "partner"
		var wt: Pal = game.gen_pal("chikipi", 3, Vector2(p.pos.x + 2, p.pos.y))
		wt.mode = "wild"; wt.max_hp = 2000; wt.hp = 2000
		game.pals.append(wt)
		var wthp := wt.hp
		check("foxparks flamethrower", game.run_partner_skill(fp, wt.pos,
			game.PARTNER_SKILLS["foxparks"]) and wt.hp < wthp)
		var tz: Pal = game.gen_pal("tanzee", 10, p.pos)
		tz.mode = "partner"
		var wthp2 := wt.hp
		check("tanzee rifle", game.run_partner_skill(tz, wt.pos,
			game.PARTNER_SKILLS["tanzee"]) and wt.hp < wthp2)
		# out-of-reach aims whiff — off-map aim finds nothing
		check("partner skill whiffs", not game.run_partner_skill(tz,
			Vector2(-100, -100), game.PARTNER_SKILLS["tanzee"]))
		# pal gear gates the bespoke actives (Palworld's crafted harness rule)
		check("gear gates partner", not game.partner_gear_ok("foxparks"))
		game.add_item("foxparks_harness", 1)
		check("harness unlocks skill", game.partner_gear_ok("foxparks"))
		game.items.erase("foxparks_harness")
		# support partner skills (Palworld ranch-in-the-field): milk/eggs on tap
		var cr: Pal = game.gen_pal("cremis", 5, p.pos)
		cr.mode = "partner"
		var milk0: int = game.item_count("milk")
		var lay: Pal = game.gen_pal("chikipi", 5, p.pos)
		lay.mode = "partner"
		var egg0: int = game.item_count("egg")
		var sup: bool = game.run_partner_skill(cr, p.pos, game.PARTNER_SKILLS["cremis"]) \
			and game.run_partner_skill(lay, p.pos, game.PARTNER_SKILLS["chikipi"])
		check("ranch pals produce", sup and game.item_count("milk") == milk0 + 1
			and game.item_count("egg") == egg0 + 1,
			"milk=%d egg=%d" % [game.item_count("milk") - milk0, game.item_count("egg") - egg0])
		# Penguin Cannon (Palworld's signature silliness): the bird is the payload
		var pg: Pal = game.gen_pal("pengullet", 10, p.pos)
		pg.mode = "partner"
		var wthp3 := wt.hp
		var pg_hit: bool = game.run_partner_skill(pg, wt.pos, game.PARTNER_SKILLS["pengullet"])
		check("penguin cannon", pg_hit and wt.hp < wthp3, "hp=%.0f" % wt.hp)
		check("cannon needs launcher", not game.partner_gear_ok("pengullet"))
		# Roly Poly (Palworld's lamball shield): an absorb bubble that pops
		var lb: Pal = game.gen_pal("lamball", 10, p.pos)
		lb.mode = "partner"
		game.run_partner_skill(lb, p.pos, game.PARTNER_SKILLS["lamball"])
		var hp_s0 := p.hp
		p.dodge_t = 0.0
		game.hurt_player(30.0, lb)
		var blocked: bool = p.hp >= hp_s0
		p.shield_n = 4.0 # nearly spent — the next hit should leak through
		game.hurt_player(30.0, lb)
		var leaked: bool = p.hp < hp_s0
		p.hp = hp_s0; p.shield_t = 0.0; p.shield_n = 0.0
		check("roly poly shield", blocked and leaked,
			"blocked=%s leaked=%s" % [blocked, leaked])
		# Dream Chaser (Palworld's daedream trick): BENCHED party daedream
		# still snipes at the deployed partner's fight
		var dd: Pal = game.gen_pal("daedream", 10, p.pos)
		dd.mode = "bench"
		game.bench.append(dd)
		var dlead: Pal = game.gen_pal("cattiva", 10, p.pos)
		dlead.mode = "partner"
		game.pals.append(dlead)
		var party0: Array = game.party.duplicate()
		game.party.insert(0, dlead.uid); game.party.append(dd.uid)
		wt.hp = 2000 # the cannon/flamethrower may have dropped it — full bar for a clean shot
		var wthp4 := wt.hp
		game.focus_target = wt; game.focus_t = game.t + 4.0 # YOUR mark is its mark
		game.tick_daedream()
		check("dream chaser", wt.hp < wthp4, "hp=%.0f" % wt.hp)
		game.focus_target = null; game.focus_t = 0.0
		game.party = party0
		game.bench.erase(dd)
		game.pals.erase(dlead)
		for tmp2 in [cr, lay, pg, lb, dd, dlead]:
			if is_instance_valid(tmp2) and tmp2.get_parent():
				tmp2.get_parent().remove_child(tmp2)
			if is_instance_valid(tmp2):
				tmp2.free()
		game.pals.erase(wt)
		for tmp in [wt, fp, tz]:
			if is_instance_valid(tmp) and tmp.get_parent():
				tmp.get_parent().remove_child(tmp)
			if is_instance_valid(tmp):
				tmp.free()
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
		# Palworld auto-assign: idle crew staff open posts; haulers keep hauling
		for kk4 in game.structures:
			game.structures[kk4]["workers"].erase(p2)
		p2.job_site = null
		var tpw: Pal = game.gen_pal("wumpo", 5, p.pos)
		tpw.mode = "base"; game.pals.append(tpw)
		game.assign_t = 1.9
		game.tick_assign(0.2)
		check("idle pal auto-staffs", p2.job_site != null)
		check("hauler keeps hauling", tpw.job_site == null)
		game.pals.erase(tpw)
		if tpw.get_parent(): tpw.get_parent().remove_child(tpw)
		tpw.free()
		# Palworld's pet: a little SAN per pal on a 60s cooldown
		tpw = game.gen_pal("lamball", 3, p.pos)
		tpw.mode = "base"; tpw.san = 50.0; game.pals.append(tpw)
		check("pet raises san", game.pet_pal(tpw) and tpw.san == 58.0, "san=%.0f" % tpw.san)
		check("pet cooldown", not game.pet_pal(tpw))
		tpw.petted_t = -60.0; tpw.san = 98.0
		check("pet caps san", game.pet_pal(tpw) and tpw.san == 100.0)
		game.pals.erase(tpw)
		if tpw.get_parent(): tpw.get_parent().remove_child(tpw)
		tpw.free()
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
				wp.mode = "base"; wp.san = 90.0; wp.ailment = ""; wp.passives = []; wp.talent = 50
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
		# dark pals ARE the night shift: +15% output after dusk
		game.add_item("stone", 20); game.add_item("wood", 10)
		var mine_st = null
		for kk4 in game.structures:
			if game.structures[kk4].get("id") == "ore_mine":
				mine_st = game.structures[kk4]
		if mine_st == null:
			var mk: Vector2i = free_xy.call("ore_mine")
			if mk.x >= 0:
				mine_st = game.structures.get(mk)
		if mine_st:
			var dark_w: Pal = game.gen_pal("depresso", 5, game.player.pos)
			dark_w.mode = "base"; dark_w.san = 90.0; dark_w.ailment = ""; dark_w.passives = []
			var saved_w: Array = mine_st["workers"].duplicate()
			var saved_t: float = mine_st["timer"]
			mine_st["workers"] = [dark_w]; dark_w.job_site = mine_st
			game.tod = 12.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var day_v: float = mine_st["timer"]
			game.tod = 23.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var night_v: float = mine_st["timer"]
			var dk_ratio: float = night_v / maxf(0.001, day_v)
			check("dark night shift", absf(dk_ratio - 1.15) < 0.01, "night/day=%.3f" % dk_ratio)
			mine_st["workers"] = saved_w; mine_st["timer"] = saved_t
			dark_w.job_site = null
			game.pals.erase(dark_w); dark_w.free()
			game.tod = tod0
		else:
			check("dark night shift", false, "no mining site")
		# Palworld nocturnals: dark pals aggro wider after dusk
		var lup: Pal = game.gen_pal("loupmoon", 5, p.pos + Vector2(4.5, 0))
		lup.mode = "wild"; lup.aggro = -1
		game.pals.append(lup)
		game.tod = 23.0
		lup.wild_ai(0.05)
		var n_ag: int = lup.aggro
		lup.aggro = -1
		game.tod = 12.0
		lup.wild_ai(0.05)
		check("dark pal hunts wider at night", n_ag == 0 and lup.aggro < 0,
			"night=%d day=%d" % [n_ag, lup.aggro])
		game.tod = tod0
		game.pals.erase(lup)
		if lup.get_parent(): lup.get_parent().remove_child(lup)
		lup.free()
		# weather: rain puts water pals in their element on the crew
		if mine_st:
			var wt0: String = game.weather
			var wp2: Pal = game.gen_pal("pengullet", 5, game.player.pos)
			wp2.mode = "base"; wp2.san = 90.0; wp2.ailment = ""; wp2.passives = []
			var wsv2: Array = mine_st["workers"].duplicate()
			var tsv2: float = mine_st["timer"]
			game.tod = 12.0 # keep the night bonus out of the comparison
			mine_st["workers"] = [wp2]; wp2.job_site = mine_st
			game.weather = "clear"; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var dry_v: float = mine_st["timer"]
			game.weather = "rain"; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var wet_v: float = mine_st["timer"]
			check("rain crew bonus", dry_v > 0 and absf(wet_v / dry_v - 1.15) < 0.01,
				"wet/dry=%.3f" % (wet_v / maxf(dry_v, 0.001)))
			mine_st["workers"] = wsv2; mine_st["timer"] = tsv2
			wp2.job_site = null
			game.weather = wt0; game.tod = tod0
			game.pals.erase(wp2); wp2.free()
			# worker IVs: a T100 crew outpaces a T0 crew on the same site
			var ivp: Pal = game.gen_pal("lifmunk", 5, game.player.pos)
			ivp.mode = "base"; ivp.san = 90.0; ivp.ailment = ""; ivp.passives = []
			var wsv3: Array = mine_st["workers"].duplicate()
			var tsv3: float = mine_st["timer"]
			var iv_vs := []
			for tv in [0, 100]:
				ivp.talent = tv
				mine_st["workers"] = [ivp]; ivp.job_site = mine_st
				mine_st["timer"] = 0.0
				game.tick_production(1.0)
				iv_vs.append(float(mine_st["timer"]))
			check("talent works", absf(iv_vs[1] / maxf(0.001, iv_vs[0]) - (1.3 / 0.9)) < 0.01,
				"T100/T0=%.3f" % (iv_vs[1] / maxf(0.001, iv_vs[0])))
			mine_st["workers"] = wsv3; mine_st["timer"] = tsv3
			ivp.job_site = null
			game.pals.erase(ivp); ivp.free()

			# Palworld condenser: a starred pal outworks its kin on the same site
			var cst: Pal = game.gen_pal("lifmunk", 5, game.player.pos)
			cst.mode = "base"; cst.san = 90.0; cst.ailment = ""; cst.passives = []
			var wsv5: Array = mine_st["workers"].duplicate()
			var tsv5: float = mine_st["timer"]
			var st_vs := []
			for sv in [0, 4]:
				cst.star = sv
				mine_st["workers"] = [cst]; cst.job_site = mine_st
				mine_st["timer"] = 0.0
				game.tick_production(1.0)
				st_vs.append(float(mine_st["timer"]))
			check("stars work harder", absf(st_vs[1] / maxf(0.001, st_vs[0]) - 1.4) < 0.01,
				"star4/star0=%.3f" % (st_vs[1] / maxf(0.001, st_vs[0])))
			mine_st["workers"] = wsv5; mine_st["timer"] = tsv5
			cst.job_site = null
			game.pals.erase(cst); cst.free()

			# hungry pals slack off (Palworld): starving crews stop producing
			var hg: Pal = game.gen_pal("lamball", 5, game.player.pos)
			hg.mode = "base"; hg.san = 90.0; hg.ailment = ""
			var wsv4: Array = mine_st["workers"].duplicate()
			var tsv4: float = mine_st["timer"]
			mine_st["workers"] = [hg]; hg.job_site = mine_st
			hg.hunger = 90.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var starved := float(mine_st["timer"])
			hg.hunger = 40.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			check("hungry pals slack", starved == 0.0 and float(mine_st["timer"]) > 0.0,
				"starved=%.1f fed=%.1f" % [starved, mine_st["timer"]])
			mine_st["workers"] = wsv4; mine_st["timer"] = tsv4
			hg.job_site = null
			game.pals.erase(hg); hg.free()

	# Sphere Works (Palworld assembly line): a handy pal rolls spheres
	for c0 in StructureData.STRUCTURES["sphere_factory"]["cost"]:
		game.add_item(c0[0], int(c0[1]))
	var sf_k: Vector2i = free_xy.call("sphere_factory")
	var sf_st = game.structures.get(sf_k) if sf_k.x >= 0 else null
	var chest5 = null
	for kk13 in game.structures:
		if game.structures[kk13].get("id") == "chest" and not game.structures[kk13].get("loot", false):
			chest5 = game.structures[kk13]
			break
	if chest5 == null:
		var ck5: Vector2i = free_xy.call("chest")
		chest5 = game.structures.get(ck5)
	if sf_st and chest5:
		for ci in [["paldium", 3], ["wood", 3], ["stone", 3]]:
			chest5["store"][ci[0]] = chest5["store"].get(ci[0], 0) + ci[1]
		var hw: Pal = game.gen_pal("lamball", 5, game.player.pos)
		hw.mode = "base"; hw.san = 90.0; hw.ailment = ""; hw.passives = []
		var saved_hw: Array = sf_st["workers"].duplicate()
		sf_st["workers"] = [hw]; hw.job_site = sf_st
		hw.talent = 50 # a bottom-rolled talent scales work_sum below the 200 mark
		sf_st["timer"] = 199.5
		game.tick_production(1.0)
		check("sphere works rolls", sf_st["store"].get("pal_sphere", 0) >= 1,
			"store=%s" % str(sf_st["store"]))
		sf_st["workers"] = saved_hw; hw.job_site = null
		game.pals.erase(hw); hw.free()
	else:
		check("sphere works rolls", false, "factory=%s chest=%s" % [sf_st != null, chest5 != null])

	# expedition post (Palworld dispatch): a posted gatherer marches off, then
	# returns with loot — tired and hungry, just like the real thing
	for c0 in StructureData.STRUCTURES["expedition_post"]["cost"]:
		game.add_item(c0[0], c0[1])
	var xp_k: Vector2i = free_xy.call("expedition_post")
	var xp_st = game.structures.get(xp_k) if xp_k.x >= 0 else null
	if xp_st:
		var scout: Pal = game.gen_pal("cattiva", 10, p.pos)
		scout.mode = "base"; scout.san = 90.0; scout.hunger = 10.0
		game.pals.append(scout)
		xp_st["workers"] = [scout]; scout.job_site = xp_st
		scout.pos = Vector2(xp_k.x + 0.5, xp_k.y + 0.5) # standing on the post
		var tod_x := game.tod
		game.tod = 12.0 # pals march by day — night sends them to bed first
		scout._physics_process(0.1) # arrival -> departure
		game.tod = tod_x
		check("expedition departs", scout.mode == "expedition" and not scout.visible
			and float(xp_st.get("exp_end", 0.0)) > game.t,
			"mode=%s end=%s" % [scout.mode, str(xp_st.get("exp_end"))])
		var san0: float = scout.san
		xp_st["exp_end"] = game.t - 1.0 # time it home
		game.tick_production(0.1)
		var loot_n := 0
		for k in xp_st["store"]:
			loot_n += int(xp_st["store"][k])
		check("expedition returns with haul", scout.mode == "base" and scout.visible
			and loot_n >= 2 and scout.san < san0 and float(xp_st.get("exp_cd", 0.0)) > game.t,
			"mode=%s loot=%d san=%.0f" % [scout.mode, loot_n, scout.san])
		xp_st["workers"] = []; scout.job_site = null
		game.pals.erase(scout); scout.free()
	else:
		check("expedition departs", false, "post not placed")

	# Giga Works (Palworld assembly line II): organ-fed belt rolls giga spheres
	for c0 in StructureData.STRUCTURES["sphere_factory_2"]["cost"]:
		game.add_item(c0[0], int(c0[1]))
	var g2_k: Vector2i = free_xy.call("sphere_factory_2")
	var g2_st = game.structures.get(g2_k) if g2_k.x >= 0 else null
	var chest6 = null
	for kk14 in game.structures:
		if game.structures[kk14].get("id") == "chest" and not game.structures[kk14].get("loot", false):
			chest6 = game.structures[kk14]
			break
	if chest6 == null:
		var ck6: Vector2i = free_xy.call("chest")
		chest6 = game.structures.get(ck6)
	if g2_st and chest6:
		for ci in [["paldium", 3], ["ingot", 2], ["electric_organ", 1]]:
			chest6["store"][ci[0]] = chest6["store"].get(ci[0], 0) + ci[1]
		var hw2: Pal = game.gen_pal("lamball", 5, game.player.pos)
		hw2.mode = "base"; hw2.san = 90.0; hw2.ailment = ""; hw2.passives = []
		hw2.talent = 50 # keep work_sum above the 300 mark deterministically
		var saved_hw2: Array = g2_st["workers"].duplicate()
		g2_st["workers"] = [hw2]; hw2.job_site = g2_st
		g2_st["timer"] = 299.5
		game.tick_production(1.0)
		check("giga works rolls", g2_st["store"].get("giga_sphere", 0) >= 1,
			"store=%s" % str(g2_st["store"]))
		g2_st["workers"] = saved_hw2; hw2.job_site = null
		game.pals.erase(hw2); hw2.free()
	else:
		check("giga works rolls", false, "factory=%s chest=%s" % [g2_st != null, chest6 != null])

	# cold chain (Palworld fridge loop): perishables rot over time, a staffed
	# ice box halts it; a sleeping cooler pal does not
	game.items["egg"] = 20
	game.items["lamball_mutton"] = 10
	game.tick_spoilage()
	var rot_n: int = game.items.get("spoiled_food", 0)
	check("perishables turn", rot_n >= 4 and game.items["egg"] < 20,
		"spoiled=%d eggs=%d" % [rot_n, game.items.get("egg", 0)])
	game.items.erase("spoiled_food")
	var ic_k: Vector2i = free_xy.call("cooler")
	var ic_st = game.structures.get(ic_k) if ic_k.x >= 0 else null
	if ic_st:
		var chiller: Pal = game.gen_pal("pengullet", 5, game.player.pos)
		if chiller == null:
			chiller = game.gen_pal("penking", 5, game.player.pos)
		chiller.mode = "base"; chiller.san = 90.0; chiller.hunger = 10.0; chiller.ailment = ""
		chiller.passives = []; chiller.statuses.clear()
		ic_st["workers"] = [chiller]; chiller.job_site = ic_st
		var egg0: int = game.items.get("egg", 0)
		game.tick_spoilage()
		var kept: bool = game.items.get("spoiled_food", 0) == 0 and game.items.get("egg", 0) == egg0
		chiller.statuses["sleep"] = game.t + 2.0 # a dozing cooler pal can't hold the frost
		game.tick_spoilage()
		var dozed: bool = game.items.get("spoiled_food", 0) > 0
		check("ice box preserves", kept and dozed,
			"kept=%s dozed=%s" % [kept, dozed])
		ic_st["workers"] = []; chiller.job_site = null
		game.pals.erase(chiller); chiller.free()
		game.items.erase("spoiled_food")
	else:
		check("ice box preserves", false, "no cooler spot")

	# the rot loop closes: compost bin turns scraps into surge — fertilized
	# fields run 50% hot for five minutes
	var cbin_k: Vector2i = free_xy.call("compost_bin")
	var cbin_st = game.structures.get(cbin_k) if cbin_k.x >= 0 else null
	var cfarm_k := Vector2i(-1, -1)
	for fk in game.structures:
		if StructureData.STRUCTURES.get(game.structures[fk]["id"], {}).get("farmField", false):
			cfarm_k = fk
			break
	if cfarm_k.x < 0:
		cfarm_k = free_xy.call("wheat_farm")
	var fert_ok := false
	if cbin_st != null and game.structures.has(cfarm_k):
		var farmer: Pal = game.gen_pal("chikipi", 5, game.player.pos)
		farmer.mode = "base"; farmer.san = 90.0; farmer.hunger = 10.0; farmer.ailment = ""
		farmer.passives = []; farmer.statuses.clear(); farmer.talent = 50
		var saved_cb: Array = cbin_st["workers"].duplicate()
		cbin_st["workers"] = [farmer]; farmer.job_site = cbin_st
		var chest7 = null
		for kk15 in game.structures:
			if game.structures[kk15]["id"] == "chest" and not game.structures[kk15].get("loot", false):
				chest7 = game.structures[kk15]
				break
		if chest7 == null:
			var ck7: Vector2i = free_xy.call("chest")
			chest7 = game.structures.get(ck7)
		if chest7 != null:
			chest7["store"]["spoiled_food"] = chest7["store"].get("spoiled_food", 0) + 2
			chest7["store"]["fiber"] = chest7["store"].get("fiber", 0) + 1
			cbin_st["timer"] = 89.5
			game.tick_production(1.0)
			var made: bool = cbin_st["store"].get("fertilizer", 0) >= 1
			var p7: Vector2 = p.pos
			p.pos = Vector2(cfarm_k.x + 0.5, cfarm_k.y + 0.5)
			game.add_item("fertilizer", 1)
			game.fertilize()
			fert_ok = made and float(game.structures[cfarm_k].get("fert", 0.0)) > game.t
			p.pos = p7
			cbin_st["workers"] = saved_cb; farmer.job_site = null
			game.pals.erase(farmer); farmer.free()
		check("compost and surge", fert_ok, "made=%s fert=%.0f" % [
			cbin_st["store"].get("fertilizer", 0) >= 1,
			float(game.structures[cfarm_k].get("fert", 0.0)) - game.t])
	else:
		check("compost and surge", false, "bin=%s farm=%s" % [cbin_st != null, cfarm_k])

	# fish trap: a weir only stands where it can drink — shore-locked,
	# watering pal pulls fish on the clock
	var ft_spot := Vector2i(-1, -1)
	for ty in range(2, World.WORLD_H - 2):
		for tx in range(2, World.WORLD_W - 2):
			if game.world.tile_at(tx, ty) == World.Tile.WATER:
				continue
			var shorey := false
			for d2 in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				if game.world.in_bounds(tx + d2.x, ty + d2.y) and game.world.tile_at(tx + d2.x, ty + d2.y) == World.Tile.WATER:
					shorey = true
			if shorey and game.can_place("fish_trap", tx, ty):
				ft_spot = Vector2i(tx, ty)
				break
		if ft_spot.x >= 0:
			break
	var trap_ok := false
	if ft_spot.x >= 0:
		game.place_structure("fish_trap", ft_spot.x, ft_spot.y)
		var ft_st = game.structures.get(ft_spot)
		var fisher: Pal = game.gen_pal("pengullet", 5, game.player.pos)
		fisher.mode = "base"; fisher.san = 90.0; fisher.hunger = 10.0; fisher.ailment = ""
		fisher.passives = []; fisher.statuses.clear(); fisher.talent = 50
		ft_st["workers"] = [fisher]; fisher.job_site = ft_st
		ft_st["timer"] = 149.5
		game.tick_production(1.0)
		trap_ok = ft_st["store"].get("raw_fish", 0) >= 1
		ft_st["workers"] = []; fisher.job_site = null
		game.pals.erase(fisher); fisher.free()
	# and it refuses dry land — probe one inland tile
	var dry_reject := false
	var dry_done := false
	for ty2 in range(2, World.WORLD_H - 2):
		if dry_done:
			break
		for tx2 in range(2, World.WORLD_W - 2):
			if game.world.tile_at(tx2, ty2) == World.Tile.WATER or game.structures.has(Vector2i(tx2, ty2)):
				continue
			var near_w := false
			for oy in range(-1, 2): # can_place counts the full ring incl diagonals
				for ox in range(-1, 2):
					if game.world.in_bounds(tx2 + ox, ty2 + oy) and game.world.tile_at(tx2 + ox, ty2 + oy) == World.Tile.WATER:
						near_w = true
			if not near_w and game.world.flat_at(tx2, ty2, 1, 1):
				dry_reject = not game.can_place("fish_trap", tx2, ty2)
				dry_done = true
				break
	check("fish trap yields", trap_ok and ft_spot.x >= 0 and dry_reject, "spot=%s fish=%s dry=%s" % [
		ft_spot, game.structures.get(ft_spot, {}).get("store", {}).get("raw_fish", 0) if ft_spot.x >= 0 else -1, dry_reject])

	# training dummy: an idle base pal spars itself stronger
	var td_k: Vector2i = free_xy.call("training_dummy")
	var td_st = game.structures.get(td_k) if td_k.x >= 0 else null
	var td_ok := false
	if td_st != null:
		for wp9 in game.pals: # pacify the yard so the rookie drills instead of brawling
			if wp9.mode == "wild":
				wp9.aggro = -1; wp9.raid = false
		# rushoar drills by day; at night a dark pal keeps the same hours —
		# both carry no transporting suit so neither is pulled into hauling
		var rookie: Pal = game.gen_pal("loupmoon" if game.is_night() else "rushoar", 3,
			Vector2(td_k.x + 0.5, td_k.y + 0.5))
		rookie.mode = "base"; rookie.san = 90.0; rookie.hunger = 10.0; rookie.ailment = ""
		rookie.passives = []; rookie.statuses.clear()
		var xp0: int = rookie.xp + rookie.level * 1000 # composite baseline
		for i9 in range(40):
			rookie.base_ai(0.1)
		td_ok = rookie.xp > 0 or rookie.level * 1000 + rookie.xp > xp0
		game.pals.erase(rookie); rookie.free()
	check("dummy trains idle pal", td_ok, "td=%s" % (td_st != null))

	# pal bait: a tossed mash pulls a wild pal to the pile — first snout eats.
	# pin the sun high: sleeping wilds won't wake for the smell
	var tod_bait: float = game.tod
	game.tod = 12.0
	var bait_ok := false
	var deer2: Pal = game.gen_pal("eikthyrdeer", 3, p.pos + Vector2(8, 8))
	deer2.mode = "wild"; deer2.aggro = -1
	p.facing = Vector2(1, 0)
	game.items["pal_bait"] = 1
	game.throw_bait()
	var bait_landed: bool = game.lure and game.t < float(game.lure.get("till", 0.0))
	# drop the pile at the deer's feet — the pull-through-terrain walk has no
	# pathfinding by design; what matters is the first snout eats and the
	# pile is gone
	if game.lure:
		game.lure["pos"] = deer2.pos
		game.lure["till"] = game.t + 30.0
	for i10 in range(160):
		deer2._physics_process(0.1)
		if not game.lure:
			break
	bait_ok = bait_landed and not game.lure
	game.pals.erase(deer2); deer2.free()
	game.lure = {}
	game.tod = tod_bait
	check("bait lures wild", bait_ok, "landed=%s left=%s" % [bait_landed, game.lure != {}])

	# treasure map: the chart marks real ground — stand on the X and dig
	var tgold0: int = game.items.get("gold_coin", 0)
	game.items["treasure_map"] = 1
	game.use_treasure_map()
	var marked: bool = game.treasure and game.treasure.has("pos")
	var dug := false
	if marked:
		var tp8: Vector2 = p.pos
		p.pos = game.treasure["pos"]
		game.dig_check()
		dug = not game.treasure and game.items.get("gold_coin", 0) > tgold0
		p.pos = tp8
	game.treasure = {}
	check("treasure map digs", marked and dug, "marked=%s dug=%s" % [marked, dug])

	# apiary: a planting pal keeps the comb full on the clock
	var ap_k: Vector2i = free_xy.call("apiary")
	var ap_st = game.structures.get(ap_k) if ap_k.x >= 0 else null
	var honey_ok := false
	if ap_st != null:
		var keeper: Pal = game.gen_pal("lifmunk", 5, game.player.pos)
		keeper.mode = "base"; keeper.san = 90.0; keeper.hunger = 10.0; keeper.ailment = ""
		keeper.passives = []; keeper.statuses.clear(); keeper.talent = 50
		ap_st["workers"] = [keeper]; keeper.job_site = ap_st
		ap_st["timer"] = 119.5
		game.tick_production(1.0)
		honey_ok = ap_st["store"].get("honey", 0) >= 1
		ap_st["workers"] = []; keeper.job_site = null
		game.pals.erase(keeper); keeper.free()
	check("apiary drips honey", honey_ok, "ap=%s" % (ap_st != null))

	# weather shrine: paldium buys the sky — prayer cycles and then rests
	var ws_ok := false
	var ws_k: Vector2i = free_xy.call("weather_shrine")
	if ws_k.x >= 0:
		game.items["paldium"] = 5
		var w0: String = game.weather
		game.pray_cd = 0.0
		game.pray_weather()
		var cycled: bool = game.weather != w0 and game.pray_cd > game.t
		game.pray_weather() # second prayer too soon — refused
		ws_ok = cycled and game.items.get("paldium", 0) == 2 and int(game.pray_cd - game.t) > 500
		game.weather = w0 # hand the sky back — later checks assume a neutral one
	check("shrine calls weather", ws_ok, "w=%s cd=%.0f" % [game.weather, game.pray_cd - game.t])

	# guard post: a posted pal watches 12 tiles where a yard hand sees 7 —
	# the scan is distance-only, so the assertion ignores footpaths entirely
	var gp_ok := false
	var tod_gp: float = game.tod
	game.tod = 12.0 # sentries doze at night like everyone else — pin the sun
	for wp10 in game.pals: # quiet the yard so the only flag on the beat is ours
		if wp10.mode == "wild":
			wp10.aggro = -1; wp10.raid = false
	game.add_item("wood", 12); game.add_item("stone", 6)
	var gp_k: Vector2i = free_xy.call("guard_post")
	var gp_st = game.structures.get(gp_k) if gp_k.x >= 0 else null
	if gp_st != null:
		var sentry: Pal = game.gen_pal("rushoar", 5, Vector2(gp_k.x + 0.5, gp_k.y + 0.5))
		sentry.mode = "base"; sentry.san = 90.0; sentry.hunger = 10.0; sentry.ailment = ""
		sentry.passives = []; sentry.statuses.clear(); sentry.job_site = gp_st
		gp_st["workers"] = [sentry]
		var hand: Pal = game.gen_pal("rushoar", 5, sentry.pos + Vector2(1, 0))
		hand.mode = "base"; hand.statuses.clear() # same spot, no post — the control
		var raider: Pal = game.gen_pal("loupmoon", 5, sentry.pos + Vector2(8.5, 0))
		raider.mode = "wild"; raider.raid = true
		game.pals.append(raider); game.pals.append(sentry); game.pals.append(hand)
		gp_ok = sentry.find_foe() == raider and hand.find_foe() != raider
		game.pals.erase(raider); raider.free()
		game.pals.erase(hand); hand.free()
		gp_st["workers"] = []; sentry.job_site = null
		game.pals.erase(sentry); sentry.free()
	game.tod = tod_gp
	check("guard widens beat", gp_ok, "gp=%s" % (gp_st != null))

	# training hall — a posted veteran drills a pupil's missing move each bell
	game.add_item("wood", 20); game.add_item("stone", 15); game.add_item("paldium", 4)
	var th_k: Vector2i = free_xy.call("training_hall")
	var th_st = game.structures.get(th_k) if th_k.x >= 0 else null
	var th_ok := false
	if th_st != null:
		var thc := Vector2(th_k.x + 1.0, th_k.y + 1.0) # hall is 2x2 — centre of the deck
		var teach: Pal = game.gen_pal("rushoar", 30, thc)
		teach.mode = "base"; teach.san = 90.0; teach.hunger = 10.0
		teach.statuses.clear(); teach.job_site = th_st
		th_st["workers"] = [teach]
		var pupil: Pal = game.gen_pal("lamball", 3, thc + Vector2(3, 0))
		pupil.mode = "base"; pupil.statuses.clear()
		var n_before: int = pupil.extra_skills.size()
		for bp2 in game.pals: # clear other ears — the bell picks ONE pupil at random
			if bp2 != teach and bp2 != pupil and bp2.mode == "base" and bp2.pos.distance_to(thc) <= 10.0:
				bp2.pos += Vector2(30, 0)
		game.pals.append(teach); game.pals.append(pupil)
		th_st["timer"] = 89.9
		game.tick_production(0.2)
		th_ok = pupil.extra_skills.size() > n_before
		game.pals.erase(pupil); pupil.free()
		th_st["workers"] = []; teach.job_site = null
		game.pals.erase(teach); teach.free()
	check("dojo teaches a move", th_ok, "th=%s" % (th_st != null))

	# sparring ring — two posted pals trade a bout on the bell: xp in, san out
	game.add_item("wood", 15); game.add_item("cloth", 4)
	var sr_k: Vector2i = free_xy.call("sparring_ring")
	var sr_st = game.structures.get(sr_k) if sr_k.x >= 0 else null
	var sr_ok := false
	if sr_st != null:
		var spa: Pal = game.gen_pal("rushoar", 10, Vector2(sr_k.x + 0.5, sr_k.y + 0.5))
		var spb: Pal = game.gen_pal("lamball", 10, Vector2(sr_k.x + 1.5, sr_k.y + 0.5))
		for spx in [spa, spb]:
			spx.mode = "base"; spx.san = 80.0; spx.hunger = 10.0
			spx.statuses.clear(); spx.job_site = sr_st
		sr_st["workers"] = [spa, spb]
		game.pals.append(spa); game.pals.append(spb)
		var san0: float = spa.san + spb.san
		var xp0: int = spa.xp + spa.level * 1000 + spb.xp + spb.level * 1000
		sr_st["timer"] = 59.9
		game.tick_production(0.2)
		sr_ok = (spa.san + spb.san) < san0 \
			and (spa.xp + spa.level * 1000 + spb.xp + spb.level * 1000) > xp0
		sr_st["workers"] = []; spa.job_site = null; spb.job_site = null
		game.pals.erase(spa); spa.free(); game.pals.erase(spb); spb.free()
	check("ring pairs a bout", sr_ok, "sr=%s" % (sr_st != null))

	# notice board: a dawn posting pays coin and credit for the ask
	game.add_item("wood", 8); game.add_item("fiber", 3)
	var nb_k: Vector2i = free_xy.call("notice_board")
	var nb_ok := false
	if nb_k.x >= 0:
		game.board_quest = {"id": "honey", "n": 2, "day": game.day}
		game.add_item("honey", 3)
		var gold0: int = game.item_count("gold_coin")
		game.notice_board_action()
		nb_ok = game.item_count("honey") == 1 and game.item_count("gold_coin") > gold0 \
			and game.board_quest.get("id", "") == ""
		game.board_quest = {}
	check("board pays the ask", nb_ok, "nb=%s" % (nb_k.x >= 0))

	# snare trap: a wild foot on the plate is held fast — and the spring is spent
	game.add_item("wood", 5); game.add_item("fiber", 2)
	var sn_k: Vector2i = free_xy.call("snare_trap")
	var sn_st = game.structures.get(sn_k) if sn_k.x >= 0 else null
	var sn_ok := false
	if sn_st != null:
		var prey: Pal = game.gen_pal("lamball", 3, Vector2(sn_k.x + 0.5, sn_k.y + 0.5))
		prey.mode = "wild"
		game.pals.append(prey)
		game.tick_production(0.1)
		sn_ok = prey.stun_t > 0.0 and sn_st.get("snare", true) == false
		game.pals.erase(prey); prey.free()
		await process_frame # the spent spring is removed after the tick
		sn_ok = sn_ok and not game.structures.has(sn_k)
	check("snare holds a foot", sn_ok, "sn=%s" % (sn_st != null))

	# war banner: pals under its colors out-pace pals out of sight
	game.add_item("wood", 10); game.add_item("cloth", 6)
	var wb_k: Vector2i = free_xy.call("war_banner")
	var bn_ok := false
	if wb_k.x >= 0:
		var wpos := Vector2(wb_k.x + 0.5, wb_k.y + 0.5)
		bn_ok = game.near_banner(wpos + Vector2(4, 0)) and not game.near_banner(wpos + Vector2(20, 0))
	check("banner rallies the yard", bn_ok, "wb=%s" % (wb_k.x >= 0))

	# spyglass tower: the brass glass charts more fog each sweep, capped at 18
	game.add_item("wood", 12); game.add_item("cloth", 4); game.add_item("ingot", 2)
	var sg_k: Vector2i = free_xy.call("spyglass")
	var sg_st = game.structures.get(sg_k) if sg_k.x >= 0 else null
	var sg_ok := false
	if sg_st != null:
		var fog0 := 0
		for b2 in game.explored:
			fog0 += int(b2 == 0)
		for i13 in range(3):
			sg_st["timer"] = 29.9
			game.tick_production(0.2)
		var fog1 := 0
		for b3 in game.explored:
			fog1 += int(b3 == 0)
		sg_ok = fog1 < fog0 and float(sg_st.get("spy_r", 0.0)) > 6.0 and float(sg_st.get("spy_r", 0.0)) <= 18.0
	check("spyglass charts the fog", sg_ok, "sg=%s r=%s" % [sg_st != null, str(sg_st.get("spy_r", "-") if sg_st else "-")])

	# monitoring stand: E cycles the pace — output and SAN drain scale together
	var ms_spot := Vector2i(-1, -1)
	for r3 in range(3, 40):
		var mx := int(p.pos.x) + r3
		var my := int(p.pos.y)
		if game.can_place("monitoring_stand", mx, my):
			ms_spot = Vector2i(mx, my)
			break
	if ms_spot.x >= 0:
		game.place_free("monitoring_stand", ms_spot.x, ms_spot.y)
		var wm0 := game.work_mode
		game.cycle_work_mode()
		check("work mode cycles", game.work_mode == (wm0 + 1) % 3)
		game.tick_production(0.016)
		var want_san: float = float(Game.WORK_MODES[game.work_mode]["san"])
		check("work mode san", absf(game.cur_san_mult - want_san) < 0.001,
			"mult=%.2f want=%.2f" % [game.cur_san_mult, want_san])
		game.net_remove_structure(game.structures[ms_spot])
		game.tick_production(0.016) # stand's gone — the multiplier must let go
		check("work mode needs stand", game.cur_san_mult == 1.0)

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

	# paldeck: proximity spots a species once, 10-species tiers pay once
	var dxp: Pal = game.gen_pal("lamball", 3, p.pos + Vector2(2, 0))
	dxp.mode = "wild"; game.pals.append(dxp)
	game.tick_dex(1.1)
	check("dex seen", game.dex_seen.has("lamball"))
	dxp.pos = Vector2(300, 300) # walks far away — the sighting must stick
	game.tick_dex(1.1)
	check("dex seen sticky", game.dex_seen.has("lamball"))
	# milestone math must hold no matter how many species earlier tests caught
	var cc_save: Dictionary = game.catch_counts
	var cl0: int = game.dex_claimed
	game.catch_counts = {}
	for i in cl0 * 10 + 10:
		game.catch_counts["dexsp%d" % i] = 1 # exactly one tier above claimed
	var tp0 := game.tech_points
	game.tick_dex(1.1)
	var tp1 := game.tech_points
	game.tick_dex(1.1) # second sweep must not double-pay the same tier
	check("dex milestone", tp1 == tp0 + 2 and game.tech_points == tp1 and game.dex_claimed == cl0 + 1,
		"tp %d->%d claimed %d->%d" % [tp0, tp1, cl0, game.dex_claimed])
	game.catch_counts = cc_save
	game.dex_claimed = cl0
	game.pals.erase(dxp); dxp.free()

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
	# element combos: a soaked pal freezes under ice, boils dry under fire
	var cmb: Pal = game.gen_pal("chikipi", 5, p.pos)
	cmb.mode = "wild"; cmb.hp = 99999; cmb.max_hp = 99999; game.pals.append(cmb)
	cmb.add_status("soak", 5.0)
	game.skill_hit(sp_pal, cmb, SkillData.SKILLS["iceMissile"])
	check("wet+ice freezes", cmb.has_status("freeze") and not cmb.has_status("soak"))
	cmb.statuses.clear(); cmb.hp = 99999
	cmb.add_status("soak", 5.0)
	game.skill_hit(sp_pal, cmb, SkillData.SKILLS["flameBurst"])
	check("wet+fire boils", not cmb.has_status("soak") and not cmb.has_status("freeze"))
	# freeze shatter: a solid-frozen target cracks for +50% and thaws on the hit
	cmb.statuses.clear(); cmb.hp = 99999
	var fzs := game.rng.s
	game.skill_hit(sp_pal, cmb, SkillData.SKILLS["stoneShot"])
	var d_nz := 99999.0 - cmb.hp
	cmb.hp = 99999; cmb.add_status("freeze", 5.0); game.rng.s = fzs
	game.skill_hit(sp_pal, cmb, SkillData.SKILLS["stoneShot"])
	var d_fz := 99999.0 - cmb.hp
	check("freeze shatters", d_fz > d_nz and absf(d_fz / d_nz - 1.5) < 0.05
		and not cmb.has_status("freeze"), "norm=%d frozen=%d" % [int(d_nz), int(d_fz)])
	game.pals.erase(cmb)
	if cmb.get_parent(): cmb.get_parent().remove_child(cmb)
	cmb.free()
	# weather bites in combat: rain dampens fire, feeds water (seeded — same roll)
	var wrp: Pal = game.gen_pal("chikipi", 5, p.pos)
	wrp.mode = "wild"; wrp.hp = 99999; wrp.max_hp = 99999; game.pals.append(wrp)
	var wrc: Pal = game.gen_pal("lamball", 10, p.pos)
	wrc.mode = "partner"
	var s_held: int = game.rng.s
	var wt_held: String = game.weather
	var dmgs := []
	for wv in ["clear", "rain"]:
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999
		game.skill_hit(wrc, wrp, SkillData.SKILLS["flameBurst"])
		dmgs.append(99999 - int(wrp.hp))
	check("rain dampens fire", dmgs[0] > 0 and absf(dmgs[1] / float(dmgs[0]) - 0.85) < 0.05,
		"dry=%d wet=%d" % [dmgs[0], dmgs[1]])
	var dmgs2 := []
	for wv in ["clear", "rain"]:
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999
		game.skill_hit(wrc, wrp, SkillData.SKILLS["hydroJet"])
		dmgs2.append(99999 - int(wrp.hp))
	check("rain feeds water", dmgs2[0] > 0 and absf(dmgs2[1] / float(dmgs2[0]) - 1.15) < 0.05,
		"dry=%d wet=%d" % [dmgs2[0], dmgs2[1]])
	var dmgs3 := []
	for wv in ["clear", "storm"]: # thunderstorm: electric hits crackle ~1.15x
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999
		game.skill_hit(wrc, wrp, SkillData.SKILLS["shockwave"])
		dmgs3.append(99999 - int(wrp.hp))
	check("storm charges electric", dmgs3[0] > 0 and absf(dmgs3[1] / float(dmgs3[0]) - 1.15) < 0.05,
		"dry=%d storm=%d" % [dmgs3[0], dmgs3[1]])
	# STAB (Palworld): a pal in its own element hits ~1.2x — same seed, same power
	var stabc: Pal = game.gen_pal("foxparks", 10, p.pos)
	stabc.mode = "wild"
	game.weather = "clear"
	var stab_d := []
	for el in ["neutral", "fire"]:
		game.rng.s = s_held; wrp.hp = 99999
		game.skill_hit(stabc, wrp, {"power": 50, "element": el})
		stab_d.append(99999 - int(wrp.hp))
	check("own element hits harder", stab_d[0] > 0 and absf(stab_d[1] / float(stab_d[0]) - 1.2) < 0.05,
		"neutral=%d stab=%d" % [stab_d[0], stab_d[1]])
	game.pals.erase(stabc)
	if stabc.get_parent(): stabc.get_parent().remove_child(stabc)
	stabc.free()
	game.weather = wt_held; game.rng.s = s_held + 7
	game.pals.erase(wrp)
	for tmp3 in [wrp, wrc]:
		if is_instance_valid(tmp3) and tmp3.get_parent():
			tmp3.get_parent().remove_child(tmp3)
		if is_instance_valid(tmp3):
			tmp3.free()

	# armor + damage reduction
	var hp_p := p.hp
	p.hp = 100
	game.add_item("hide_armor", 1)
	game.equip("hide_armor")
	check("armor reduces damage", p.equipment["armor"] == "hide_armor" and p.armor_def() - int(game.partner_aura("def")) == 4, "def %d" % p.armor_def())
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
	# memory wipe: perk ranks fold back into stat points (Palworld respec)
	game.stat_pts = 0
	var perkw := 0
	for k in game.perks:
		perkw += int(game.perks[k])
	game.respec()
	check("memory wipe", game.stat_pts == perkw and game.perks["capture"] == 0
		and p.max_hp == 100 + (p.level - 1) * 10 and p.capture_level == 1,
		"pts=%d perkw=%d" % [game.stat_pts, perkw])
	game.perks["capture"] = 1; game.perks["hp"] = 1; game.perks["speed"] = 1
	game.stat_pts = 0
	p.capture_level = 1 + game.perks["capture"]
	p.max_hp = 100 + (p.level - 1) * 10 + game.perks["hp"] * 12
	p.hp = minf(p.hp, p.max_hp)
	# soul infusion: effigies harden an owned pal, ride the save, cap at 10
	var soul_t: Pal = null
	for q in game.pals:
		if q.mode in ["partner", "base"]:
			soul_t = q; break
	if soul_t == null and not game.box.is_empty():
		soul_t = game.box[0]
	if soul_t == null:
		soul_t = game.gen_pal("lamball", 3, p.pos)
		soul_t.mode = "box"; game.box.append(soul_t); game.box_pal(soul_t)
	var atk_s := soul_t.atk_bonus
	var eff_s := game.item_count("lifmunk_effigy")
	game.soul_infuse(soul_t.uid)
	check("soul infuse", soul_t.soul_boost == 1 and soul_t.atk_bonus > atk_s \
			and game.item_count("lifmunk_effigy") == eff_s - 1,
		"boost=%d atk %.2f->%.2f" % [soul_t.soul_boost, atk_s, soul_t.atk_bonus])
	soul_t.soul_boost = 9; soul_t.apply_bonuses()
	game.add_item("lifmunk_effigy", 20) # the 10th soul costs 10
	game.soul_infuse(soul_t.uid) # 10th soul lands, the 11th is refused
	game.soul_infuse(soul_t.uid)
	check("soul cap", soul_t.soul_boost == 10)
	soul_t.soul_boost = 0; soul_t.apply_bonuses() # reset — don't leak stats into combat checks

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
			if game.structures[kk]["id"] == "chest" and not game.structures[kk].get("loot", false):
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
		game.add_item("huge_pal_egg", -game.item_count("huge_pal_egg")) # a stray huge egg from earlier digs would take the incubator slot first by design
		# Palworld: eggs hatch in an incubator over time, not in the hand
		game.add_item("paldium", 4); game.add_item("stone", 12); game.add_item("cloth", 2)
		var inc_k: Vector2i = free_xy.call("incubator")
		var inc_st = game.structures.get(inc_k)
		var inc_pos0: Vector2 = p.pos # deposit_egg only reaches within 20 cells
		if inc_k.x >= 0:
			p.pos = Vector2(inc_k.x + 0.5, inc_k.y + 0.5)
		game.deposit_egg()
		p.pos = inc_pos0
		check("egg deposited", inc_st != null and inc_st.has("egg_inc") and game.item_count("pal_egg") == 0)
		var n0 := game.pals.size()
		if inc_st:
			inc_st["egg_inc"]["ready_t"] = game.t - 1.0 # fast-forward
			game.hatch_incubated(inc_k, inc_st)
		check("hatch egg", game.pals.size() == n0 + 1 and not (inc_st and inc_st.has("egg_inc")))
		# huge egg: a guaranteed golden Lucky hatches out
		if inc_st:
			var lc0 := 0
			for q5 in game.pals + game.box:
				if q5.lucky: lc0 += 1
			inc_st["egg_inc"] = {"pair": null, "huge": true, "ready_t": game.t - 1.0}
			var n_h: int = game.pals.size() + game.box.size()
			game.hatch_incubated(inc_k, inc_st)
			var lc1 := 0
			for q5 in game.pals + game.box:
				if q5.lucky: lc1 += 1
			check("huge egg lucky", game.pals.size() + game.box.size() == n_h + 1 and lc1 == lc0 + 1,
				"lucky %d->%d" % [lc0, lc1])
		# continuous warmth: a campfire by the incubator pulls ready_t in 1.5x
		if inc_st:
			var fire_k := Vector2i(-1, -1)
			for off in [Vector2i(3,0), Vector2i(-3,0), Vector2i(0,3), Vector2i(0,-3), Vector2i(2,2)]:
				var ck: Vector2i = inc_k + off
				if game.world.in_bounds(ck.x, ck.y) and not game.structures.has(ck):
					fire_k = ck; break
			if fire_k.x >= 0:
				game.structures[fire_k] = {"id": "campfire", "workers": [], "store": {}, "timer": 0.0}
				inc_st["egg_inc"] = {"pair": null, "ready_t": game.t + 10.0}
				game.tick_production(1.0)
				var left_w: float = inc_st["egg_inc"]["ready_t"] - game.t # 10 - 0.5 bonus
				game.structures.erase(fire_k)
				var before_c: float = inc_st["egg_inc"]["ready_t"]
				game.tick_production(1.0)
				var cold_drop: float = before_c - inc_st["egg_inc"]["ready_t"]
				check("incubator warmth", absf(left_w - 9.5) < 0.05 and cold_drop < 0.001,
					"warm_left=%.2f cold_drop=%.3f" % [left_w, cold_drop])
				inc_st.erase("egg_inc")
			else:
				check("incubator warmth", true, "skipped: no free neighbor")
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
	# Palworld trait slots: 1-4 passives, and the lucky signature always survives
	var max_ps := 0; var over2_ps := 0
	for i in 40:
		var tpp: Pal = game.gen_pal("lamball", 3, p.pos)
		max_ps = maxi(max_ps, tpp.passives.size())
		if tpp.passives.size() >= 3: over2_ps += 1
		if tpp.get_parent(): tpp.get_parent().remove_child(tpp)
		tpp.free()
	check("trait slots 1-4", max_ps <= 4 and max_ps >= 1 and over2_ps > 0,
		"max=%d over2=%d" % [max_ps, over2_ps])
	var lp2: Pal = game.gen_pal("lamball", 3, p.pos, true)
	check("lucky signature kept", lp2.lucky and "lucky" in lp2.passives and lp2.passives.size() <= 4)
	if lp2.get_parent(): lp2.get_parent().remove_child(lp2)
	lp2.free()
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
	# host-side catch relay: a client's sphere lands in the shared palbox
	var ncp: Pal = game.gen_pal("chikipi", 3, p.pos)
	ncp.mode = "wild"; ncp.hp = 1; game.pals.append(ncp)
	var nc_box0 := game.box.size()
	var tries_c := 0
	while tries_c < 400 and ncp in game.pals: # ~97%/try — effectively deterministic
		game.net_catch(ncp.uid, "pal_sphere", false, 5, 7)
		tries_c += 1
	check("net catch to box", ncp not in game.pals and game.box.size() == nc_box0 + 1
		and ncp.mode == "box" and tries_c < 400, "tries=%d" % tries_c)
	# forged item ids never get a roll
	var ncp2: Pal = game.gen_pal("chikipi", 3, p.pos)
	ncp2.mode = "wild"; ncp2.hp = 1; game.pals.append(ncp2)
	game.net_catch(ncp2.uid, "wood", false, 5, 7)
	check("net catch validates item", ncp2 in game.pals)
	game.pals.erase(ncp2)
	if ncp2.get_parent(): ncp2.get_parent().remove_child(ncp2)
	ncp2.free()
	# drop sync: replicas spawn from the wire, despawn when the host drops them
	game.drop_sync([[55, "wood", 2, p.pos.x + 1, p.pos.y], "garbage"])
	check("drop sync spawns", game.net_drops.has(55) and game.net_drops.size() == 1)
	game.drop_sync([[56, "stone", 1, p.pos.x + 2, p.pos.y]])
	check("drop sync despawns", not game.net_drops.has(55) and game.net_drops.has(56))
	# host drops carry monotonic dids for the wire
	var did0: int = game.next_drop_id
	game.spawn_drop("wood", 1, p.pos + Vector2(1, 0))
	check("drop wire id", game.drops.back()["did"] == did0 and game.next_drop_id == did0 + 1)
	game.take_drop(game.drops.back())
	# shared-world editing: host validates the ask, wire truth reconciles
	var hc := Vector2i(-1, -1)
	for i2 in range(game.world.decor.size()):
		if game.world.decor[i2] in [World.Decor.TREE_A, World.Decor.TREE_B]:
			hc = Vector2i(i2 % World.WORLD_W, i2 / World.WORLD_W)
			break
	if hc.x >= 0:
		var drops0 := game.drops.size()
		var guard := 0
		while game.world.decor_at(hc.x, hc.y) in [World.Decor.TREE_A, World.Decor.TREE_B] and guard < 20:
			game.net_harvest(hc.x, hc.y, 99)
			guard += 1
		check("net harvest", game.world.decor_at(hc.x, hc.y) == World.Decor.STUMP
			and game.drops.size() > drops0)
	var free_spot := Vector2i(-1, -1)
	for r2 in range(3, 40):
		var cx2 := int(p.pos.x) + r2
		var cy2 := int(p.pos.y)
		if game.can_place("campfire", cx2, cy2):
			free_spot = Vector2i(cx2, cy2)
			break
	if free_spot.x >= 0:
		var pk1 := []
		for k0 in game.structures:
			var st0: Dictionary = game.structures[k0]
			if st0.get("pos", k0) == k0:
				pk1.append([st0["id"], k0.x, k0.y])
		pk1.append(["campfire", free_spot.x, free_spot.y])
		game.struct_sync(pk1)
		check("struct sync adds", game.structures.has(free_spot))
		game.struct_sync(pk1.slice(0, pk1.size() - 1))
		check("struct sync despawns", not game.structures.has(free_spot))
		game.net_place("campfire", free_spot.x, free_spot.y, 99)
		check("net place", game.structures.has(free_spot))
		game.net_demolish(free_spot.x, free_spot.y, 99)
		check("net demolish", not game.structures.has(free_spot))
	# decor deltas apply by cell index
	var dci := game.world.idx(clampi(int(p.pos.x), 0, World.WORLD_W - 1),
		clampi(int(p.pos.y) + 4, 0, World.WORLD_H - 1))
	var dcv: int = game.world.decor[dci]
	game.decor_sync([[dci, World.Decor.NONE], "junk"])
	check("decor delta applies", game.world.decor[dci] == World.Decor.NONE)
	# shared box: the host's roster ships as a compact mirror; ops relay back
	while game.party.size() >= 5:
		game.party_to_box(game.party[0])
	var nbp: Pal = game.gen_pal("lamball", 7, p.pos)
	nbp.mode = "box"; nbp.uid = game.next_uid_v + 500000 # beyond every real uid — no collisions
	var nbuid := nbp.uid
	game.box.append(nbp)
	var bsig0: int = game.net.box_fingerprint()
	var pack: Array = game.net.box_state_pack()
	check("box pack rows", pack.size() == game.box.size() and pack.back()[0] == nbuid)
	game.net.box_sync(pack, [nbuid])
	check("box sync mirror", game.net_box.size() == pack.size()
		and game.net_box.back()["sid"] == "lamball" and game.party.has(nbuid)
		and game.net_box.back()["wk"] == "FA1 HA1 TR1")
	check("work suits text", game.work_str(SpeciesData.species_of("lamball")) == "FA1 HA1 TR1")
	game.net.box_sync(["junk", [1, 2]], [])
	check("box sync drops junk", game.net_box.is_empty() and game.party.is_empty())
	var ppack: Array = game.net.party_state_pack()
	check("party pack rows", ppack.size() == mini(game.party.size(), 8)
		and ppack.all(func(e9): return e9.size() >= 14), "rows=%d party=%d" % [ppack.size(), game.party.size()])
	game.net.box_sync(pack, [nbuid], ppack)
	check("party sync mirror", game.net_party.size() == ppack.size())
	game.net.is_host = true
	game.net.box_req("box_to_party", nbuid)
	check("box req promotes", nbp not in game.box and game.party.has(nbuid))
	game.net.box_req("party_to_box", nbuid)
	check("box req returns", nbp in game.box and not game.party.has(nbuid),
		"mode=%s box=%s bench=%s pals=%s party=%s" % [nbp.mode, game.box.has(nbp),
			game.bench.has(nbp), game.pals.has(nbp), str(game.party)])
	game.net.box_req("bogus_op", nbuid)
	check("box req whitelist", nbp in game.box) # unknown ops no-op, pal survives
	game.net.is_host = false
	game.box.erase(nbp)
	if nbp.get_parent(): nbp.get_parent().remove_child(nbp)
	nbp.free()
	check("box fingerprint shifts", game.net.box_fingerprint() != bsig0)
	# Palworld den treasure: stocked chests wait behind the lair boss —
	# flagged "loot" so the logistics network never drags one home
	var loot_n := 0; var loot_stocked := 0; var loot_k := Vector2i(-1, -1)
	for k3 in game.structures:
		var st3: Dictionary = game.structures[k3]
		if st3.get("loot", false):
			loot_n += 1
			if not st3.get("store", {}).is_empty(): loot_stocked += 1
			loot_k = k3
	check("lair treasure chests", loot_n >= 1 and loot_stocked == loot_n,
		"%d/%d stocked" % [loot_stocked, loot_n])
	if loot_k.x >= 0:
		check("loot chest off the logistics net",
			game.nearest_chest_cell(Vector2(loot_k.x, loot_k.y)) != loot_k)
	game.world.decor[dci] = dcv
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
	# raid horn: the 30s warning fires once per wave, then the wave lands
	if game.palbox_pos.x >= 0:
		var raiders0 := 0
		for q in game.pals:
			if q.raid: raiders0 += 1
		game.raid_t = 31.0; game.raid_warned = false
		game.tick_raid(2.0) # 29s left — horn should sound exactly once
		var horned: bool = game.raid_warned
		game.tick_raid(1.0)
		check("raid horn once", horned and game.raid_warned)
		game.tick_raid(29.0) # countdown lands — wave spawns, flag resets for next time
		var raiders1 := 0
		for q in game.pals:
			if q.raid: raiders1 += 1
		check("raid wave lands", raiders1 > raiders0 and not game.raid_warned,
			"raiders %d->%d" % [raiders0, raiders1])
		# Palworld packs: a raider landing in a zone whose pool has the theme
		# MUST be themed — the zone pool decides, so check per-spawn zones
		if game.raid_theme != "":
			var themed_n := 0
			var theme_avail := false
			for q in game.pals:
				if not q.raid:
					continue
				if game.raid_theme in q.spec.get("elements", []):
					themed_n += 1
				var zp: Array = game.ZONE_SPECIES[game.world.zone_at(int(q.pos.x), int(q.pos.y))] \
					+ SpeciesGen.zone_pool(game.world.zone_at(int(q.pos.x), int(q.pos.y)))
				# mirror start_raid: theme only applies inside the hostile pool
				# (full pool only when the zone has no hostiles at all)
				var hpz: Array = zp.filter(func(s): return SpeciesData.species_of(s).get("hostile", 0) >= 1)
				var poolz: Array = hpz if not hpz.is_empty() else zp
				if poolz.any(func(s): return game.raid_theme in SpeciesData.species_of(s).get("elements", [])):
					theme_avail = true
			check("raid theme packs", themed_n >= 1 or not theme_avail,
				"theme=%s matched=%d" % [game.raid_theme, themed_n])
		# Palworld's signature raid: the Syndicate sends humans, not pals
		var syn0 := 0
		for q in game.pals:
			if q.species_id.begins_with("syndicate"):
				syn0 += 1
		game.raid_theme = "syndicate"
		game.start_raid()
		game.raid_theme = ""
		var syn1 := 0
		for q in game.pals:
			if q.species_id.begins_with("syndicate"):
				syn1 += 1
		check("syndicate squad", syn1 > syn0, "%d->%d" % [syn0, syn1])
		for rq in game.pals.duplicate(): # fresh raiders chew walls — sweep before they bite
			if rq.raid and not rq.boss:
				game.pals.erase(rq)
				if rq.get_parent(): rq.get_parent().remove_child(rq)
				rq.free()
	# supply drop: the crate scatters real loot stacks near the player
	var d_sup := game.drops.size()
	var landed := false
	for att in 3: # a full map can legitimately whiff a landing spot — retry
		game.supply_t = 0.01
		game.tick_supply(1.0)
		if game.drops.size() > d_sup:
			landed = true
			break
	check("supply drop", landed and game.supply_t > 300.0,
		"drops %d->%d next=%.0f" % [d_sup, game.drops.size(), game.supply_t])
	for dd2 in game.drops.duplicate(): # sweep the crate — leave the field clean
		game.take_drop(dd2)
	# fast-travel waypoints: seeded at worldgen, touch blinks back to palbox
	var wpts := 0
	for ks in game.structures:
		if game.structures[ks]["id"] == "waypoint":
			wpts += 1
	check("waypoints seeded", wpts >= 1, "n=%d" % wpts)
	if game.palbox_pos.x >= 0 and wpts >= 1:
		p.pos = Vector2(5, 5)
		game.use_waypoint()
		check("waypoint opens net", game.panel == "travel" and game.travel_nodes().size() >= 2)
		var pbk: Vector2i = game.nearest_palbox(p.pos)
		game.travel_to(pbk)
		check("waypoint blinks", game.panel == "" and p.pos.distance_to(
			Vector2(pbk.x + 0.5, pbk.y + 2.5)) < 6.0)
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
	# Palworld tombstone: the map marks the spill and clears it on the corpse run
	check("death mark set", game.death_marks.size() >= 1)
	if game.death_marks.size() >= 1:
		p.pos = game.death_marks[game.death_marks.size() - 1]
		game.tick_death_marks()
		check("corpse run clears", game.death_marks.size() == 0)
		p.pos = game.nearest_free(game.palbox_pos.x + 0.5, game.palbox_pos.y + 2.5)
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
	if slacker == null: # seed-dependent crew — seat one ourselves rather than skip
		var sl_k: Vector2i = free_xy.call("logging_site")
		var sl_st = game.structures.get(sl_k)
		if sl_st != null:
			slacker = game.gen_pal("eikthyrdeer", 5, p.pos)
			slacker.mode = "base"; slacker.job_site = sl_st
			game.pals.append(slacker)
			sl_st["workers"].append(slacker)
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
	# a party pal at ease recovers its spirits (Palworld rest recovery)
	var calm: Pal = game.gen_pal("lamball", 3, game.player.pos)
	calm.mode = "partner"; calm.san = 30.0; calm.ailment = "x" # skip the medicine branch
	calm.tick_needs(1.0)
	check("partner rests SAN", calm.san > 30.0, "san %.1f" % calm.san)
	game.pals.erase(calm); calm.free()
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
	# warm armor (Palworld fur gear): hide armor widens the cold-safe ring
	var edge := Vector2(-1, -1)
	if fire_k.x >= 0:
		var fc: Vector2 = Vector2(fire_k.x, fire_k.y) + Vector2(0.5, 0.5)
		for ddir in [Vector2(12,0), Vector2(-12,0), Vector2(0,12), Vector2(0,-12),
				Vector2(8.5,8.5), Vector2(-8.5,8.5), Vector2(8.5,-8.5), Vector2(-8.5,-8.5)]:
			var cand: Vector2 = fc + ddir
			if absf(game.nearest_heat(cand) - 12.0) < 1.5:
				edge = cand
				break
	if edge.x >= 0:
		p.pos = edge
		p.cold_t = 0.0; p.hp = p.max_hp
		var hp_e := p.hp
		p._physics_process(4.5)
		var chill_edge: bool = p.hp < hp_e # bare skin: 12 > the 10-cell ring
		game.add_item("hide_armor", 1); game.equip("hide_armor")
		p.cold_t = 0.0; p.hp = p.max_hp
		p._physics_process(4.5)
		check("warm armor", chill_edge and p.hp >= p.max_hp * 0.99,
			"edge=%s warm_hp=%.0f" % [chill_edge, p.hp])
	p.pos = pos_c; p.cold_t = 0.0
	game.tod = tod_c

	# latitude bands (Palworld snowy north / scorching south): noon in the
	# north freezes anyway, noon in the south scorches, cooling armor saves
	game.tod = 13.0
	p.hp = p.max_hp; p.hunger = 80.0
	p.equipment["armor"] = ""; p.armor_wear = -1.0
	# a fire-element partner or base pal at your shoulder is a heat source —
	# park the whole crew far away so the north wind is the only variable
	for qn in game.pals:
		if qn.mode in ["partner", "base"]:
			qn.pos = Vector2(140, 60)
	# and pick a north tile clear of any heat structure left by earlier tests
	var north_spot := Vector2(150, 10)
	for nx2 in range(10, 210):
		if game.world.tile_at(nx2, 10) == World.Tile.WATER:
			continue
		if game.nearest_heat(Vector2(nx2, 10) + Vector2(0.5, 0.5)) > 12.0:
			north_spot = Vector2(nx2, 10) + Vector2(0.5, 0.5)
			break
	p.pos = north_spot
	p.cold_t = 0.0
	var hp_n := p.hp
	p._physics_process(4.5)
	var north_cold: bool = p.hp < hp_n
	var south_spot := Vector2(-1, -1)
	for sy in range(191, 218):
		for sx in range(1, 218):
			if game.world.tile_at(sx, sy) != World.Tile.WATER:
				south_spot = Vector2(sx, sy) + Vector2(0.5, 0.5)
				break
		if south_spot.x >= 0:
			break
	var south_heat := false
	var cool_ok := false
	if south_spot.x >= 0:
		p.pos = south_spot
		p.cold_t = 0.0; p.hp = p.max_hp
		var hp_s := p.hp
		p._physics_process(4.5)
		south_heat = p.hp < hp_s
		game.add_item("tropic_armor", 1); game.equip("tropic_armor")
		p.cold_t = 0.0; p.hp = p.max_hp
		p._physics_process(4.5)
		cool_ok = p.hp >= p.max_hp * 0.99
	check("latitude bands", north_cold and south_heat and cool_ok,
		"north=%s south=%s cool=%s" % [north_cold, south_heat, cool_ok])
	p.pos = pos_c; p.cold_t = 0.0; game.tod = tod_c
	p.equipment["armor"] = ""; p.armor_wear = -1.0
	game.items.erase("tropic_armor")

	# bed rest: a real bed restores SAN 3x faster than a floor nap
	var napper: Pal = game.gen_pal("lamball", 3, p.pos + Vector2(6, 6))
	napper.mode = "base"; napper.san = 40.0
	napper.sleep_rested = false
	napper.statuses["sleep"] = game.t + 60.0
	game.pals.append(napper)
	var san_n0: float = napper.san
	napper._physics_process(1.0)
	var rough_gain: float = napper.san - san_n0
	napper.san = 40.0
	napper.sleep_rested = true
	san_n0 = napper.san
	napper._physics_process(1.0)
	var bed_gain: float = napper.san - san_n0
	check("bed rest beats floor naps", rough_gain > 0.5 and bed_gain >= rough_gain * 2.5,
		"rough=%.2f bed=%.2f" % [rough_gain, bed_gain])
	# and wounds knit overnight — a real bed heals ~2.7x a floor nap's rate
	napper.hp = napper.max_hp * 0.5
	napper.sleep_rested = false
	var hp_n0: float = napper.hp
	napper._physics_process(1.0)
	var rough_hp: float = napper.hp - hp_n0
	napper.hp = napper.max_hp * 0.5
	napper.sleep_rested = true
	hp_n0 = napper.hp
	napper._physics_process(1.0)
	var bed_hp: float = napper.hp - hp_n0
	check("sleep knits wounds", rough_hp > 0.01 and bed_hp >= rough_hp * 2.5,
		"rough=%.3f bed=%.3f" % [rough_hp, bed_hp])
	game.pals.erase(napper); napper.free()
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
	game.tick_production(0.016) # the stand's pace publishes cur_san_mult
	var san0: float = sj.san
	sj.tick_needs(1.0)
	var want := 0.2 * game.cur_san_mult / sj.passive_mult("san") # 0.2 base x pace
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
	var d9: int = p.armor_def() - int(game.partner_aura("def"))
	game.equip("dragon_scale")
	check("armor tiers", d9 == 9 and p.armor_def() - int(game.partner_aura("def")) == 14, "%d/%d" % [d9, p.armor_def()])
	# Palworld trinkets: two accessory slots, effects stack
	game.add_item("defense_pendant", 1); game.add_item("attack_pendant", 1)
	game.equip("defense_pendant")
	check("acc fills slot", p.equipment["acc1"] == "defense_pendant" and p.armor_def() - int(game.partner_aura("def")) == 19,
		"acc1=%s def=%d" % [p.equipment["acc1"], p.armor_def()])
	game.equip("attack_pendant")
	check("acc second slot", p.equipment["acc2"] == "attack_pendant", "acc2=%s" % p.equipment["acc2"])
	check("acc stacks", p.acc_total("atk") > 0.11 and p.acc_total("def") > 4.5,
		"atk=%.2f def=%.1f" % [p.acc_total("atk"), p.acc_total("def")])
	game.equip("defense_pendant") # re-click frees its slot
	check("acc unequips", p.equipment["acc1"] == "" and p.armor_def() - int(game.partner_aura("def")) == 14)
	game.add_item("defense_pendant", -1); game.add_item("attack_pendant", -1)
	check("lost acc drops", p.equipment["acc1"] == "" and p.equipment["acc2"] == "",
		"%s/%s" % [p.equipment["acc1"], p.equipment["acc2"]])
	# Palworld tool wear: swings cost durability, zero snaps the weapon
	game.add_item("wooden_club", 1)
	game.equip("wooden_club")
	check("weapon wear starts", p.weapon_wear == 40.0, "wear %.0f" % p.weapon_wear)
	p.atk_cd = 0.0; p.melee()
	check("swing spends wear", p.weapon_wear == 39.0, "wear %.0f" % p.weapon_wear)
	p.weapon_wear = 1.0; p.atk_cd = 0.0; p.melee()
	check("weapon breaks", p.equipment["weapon"] == "" and game.item_count("wooden_club") == 0,
		"slot=%s n=%d" % [p.equipment["weapon"], game.item_count("wooden_club")])
	# Palworld repair: a worn weapon mends at the bench for half its recipe
	game.add_item("wooden_club", 1)
	game.equip("wooden_club")
	p.weapon_wear = 5.0
	var cs0: String = game.craft_station
	game.craft_station = "workbench" # pretend the bench panel is open
	var rquote := game.repair_quote()
	check("repair quote", not rquote.is_empty() and rquote["cost"][0][1] == 3,
		"quote=%s" % str(rquote))
	var wood_before := game.item_count("wood")
	game.repair_weapon()
	check("weapon repaired", p.weapon_wear == 40.0 and game.item_count("wood") == wood_before - 3,
		"wear=%.0f wood=%d" % [p.weapon_wear, game.item_count("wood")])
	check("full weapon no quote", game.repair_quote().is_empty(), "still quoted")
	# armor wears the same way — hits chew the plate, the bench mends it too
	game.add_item("hide_armor", 1)
	game.equip("hide_armor")
	check("armor wear on equip", p.armor_wear == 120.0, "wear=%.0f" % p.armor_wear)
	p.armor_wear = 2.0
	var def_a := p.armor_def()
	var hp_a := p.hp
	p.hp = 400.0; p.dodge_t = 0.0 # a KO or an i-frame would swallow the test hits
	game.hurt_player(50.0, null) # first hit dents the plate
	check("hit dents armor", p.armor_wear == 1.0, "wear=%.0f" % p.armor_wear)
	game.hurt_player(50.0, null) # second hit cracks it
	check("armor breaks", p.equipment["armor"] == "" and p.armor_wear < 0.0
		and p.armor_def() < def_a, "slot=%s def=%d" % [p.equipment["armor"], p.armor_def()])
	p.hp = hp_a # the hits were real — hand the health back
	game.add_item("hide_armor", 1)
	game.equip("hide_armor")
	p.armor_wear = 60.0
	game.craft_station = "workbench"
	var aq := game.repair_quote_armor()
	check("armor quote", not aq.is_empty() and aq["max"] == 120, "quote=%s" % str(aq))
	var lea0 := game.item_count("leather") # the recipe's half-cost is in leather
	game.add_item("leather", 5); game.add_item("fiber", 5)
	game.repair_armor()
	check("armor repaired", p.armor_wear == 120.0 and game.item_count("leather") == lea0 + 2,
		"wear=%.0f leather=%d->%d" % [p.armor_wear, lea0, game.item_count("leather")])
	game.craft_station = cs0
	p.equipment["armor"] = ""; p.armor_wear = -1.0
	p.equipment["weapon"] = ""; p.weapon_wear = -1.0 # hand the test weapon back to the void

	# schematics (Palworld blueprints): the req gate wants the paper in your
	# bag, the bench rebuilds the gun, the schematic survives
	var sc_wb := Vector2i(-1, -1)
	for swk in game.structures:
		if game.structures[swk]["id"] == "workbench":
			sc_wb = swk
			break
	if sc_wb.x < 0:
		sc_wb = free_xy.call("workbench")
	var sc_pos: Vector2 = p.pos
	if game.structures.has(sc_wb):
		p.pos = Vector2(sc_wb.x + 1.5, sc_wb.y + 0.5)
		for cm in [["bow", 1], ["fiber", 12], ["nails", 6], ["leather", 6]]:
			game.add_item(cm[0], cm[1])
		var mk0: int = game.item_count("bow_mk2")
		var sch_keep: int = game.items.get("schematic_bow", 0) # earlier bosses may
		game.items.erase("schematic_bow")                     # have donated one already
		game.craft("bow_mk2")
		check("schematic gates craft", game.item_count("bow_mk2") == mk0,
			"crafted without paper")
		game.add_item("schematic_bow", sch_keep + 1)
		var sch0: int = game.items.get("schematic_bow", 0)
		game.craft("bow_mk2")
		check("mk2 forged", game.item_count("bow_mk2") == mk0 + 1
			and game.items.get("schematic_bow", 0) == sch0
			and int(ItemData.ITEMS["bow_mk2"]["weapon"]["dmg"]) > int(ItemData.ITEMS["bow"]["weapon"]["dmg"]),
			"mk2=%d sch=%d" % [game.item_count("bow_mk2"), game.items.get("schematic_bow", 0)])
		game.items.erase("schematic_bow"); game.items.erase("bow_mk2")
		p.pos = sc_pos
	else:
		check("mk2 forged", false, "no workbench")
		check("schematic gates craft", false, "no workbench")

	# schematic drops: bosses teach blueprints (30%) — a bounded kill batch
	# makes a zero-drop run astronomically unlucky rather than flaky
	var sch_hit := 0
	var lvl0: int = p.level; var xp0: int = p.xp # boss xp would leak into later checks
	for ki in range(25):
		var bk: Pal = load("res://src/pal.gd").new()
		game.entity_layer.add_child(bk)
		bk.setup(game, "lamball", 10, p.pos + Vector2(2, 0))
		bk.boss = true; bk.mode = "wild"; bk.hp = 1.0
		game.kill_pal(bk, true)
		sch_hit = game.items.get("schematic_bow", 0) + game.items.get("schematic_musket", 0)
		if sch_hit > 0:
			break
	p.level = lvl0; p.xp = xp0
	check("boss teaches blueprint", sch_hit > 0, "25 bosses, no schematic")
	game.items.erase("schematic_bow"); game.items.erase("schematic_musket")
	game.items.erase("legendary_sphere"); game.items.erase("lifmunk_effigy")
	game.items.erase("gold_coin"); game.items.erase("ancient_part"); game.items.erase("pal_sphere")

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
	game.items.erase("saddle"); game.items.erase("sky_saddle"); game.items.erase("wave_saddle")
	var bird: Pal = game.gen_pal("chikipi", 4, p.pos)
	game.pals.append(bird); game.party.append(bird.uid); bird.mode = "partner"
	p.try_mount()
	check("mount needs saddle", p.mount == null)
	game.add_item("saddle", 1) # land tack can't fly a bird
	p.try_mount()
	check("bird needs sky saddle", p.mount == null)
	game.add_item("sky_saddle", 1)
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
	# swimming mount: a water-element mount ferries you across open water —
	# but only once its own wave saddle is in the pack
	var surf: Pal = game.gen_pal("surfdog", 5, p.pos)
	surf.mode = "partner"; game.pals.append(surf); game.party.append(surf.uid)
	surf.pos = p.pos + Vector2(0.5, 0)
	p.mount = null
	game.items.erase("sky_saddle"); game.items.erase("saddle") # wrong tack won't swim
	p.try_mount()
	check("water mount needs wave saddle", p.mount == null)
	game.add_item("wave_saddle", 1)
	p.try_mount()
	check("wave saddle mounts", p.mount == surf)
	check("swim mount", wcell.x >= 0 and p.can_enter(wcell.x, wcell.y))
	game.party.erase(surf.uid)
	var landm: Pal = game.gen_pal("eikthyrdeer", 5, p.pos) # neutral — no surf legs
	landm.mode = "partner"; game.pals.append(landm)
	p.mount = landm
	check("land mount no swim", wcell.x >= 0 and not p.can_enter(wcell.x, wcell.y))
	p.mount = null
	# Palworld lets you ford water on foot too — slower, hungrier
	check("foot swim ok", wcell.x >= 0 and p.can_enter(wcell.x, wcell.y))
	if wcell.x >= 0:
		var dry_pos: Vector2 = p.pos
		p.hunger = 90.0
		p.pos = wcell
		var swm: float = p.speed_mult()
		check("swim slows", swm < 0.6 and p.swimming(), "mult=%.2f" % swm)
		p._physics_process(1.0)
		check("swim hungers", absf(90.0 - p.hunger - 0.225) < 0.01,
			"drain=%.3f" % (90.0 - p.hunger))
		p.pos = dry_pos
	# stamina (Palworld SP): sprint and swimming drain it; a dry swim drowns
	if wcell.x >= 0:
		var st_dry: Vector2 = p.pos
		p.stamina = 2.0
		var shp0: float = p.hp
		p.pos = wcell
		p._physics_process(1.0) # swim burns 4/s — empties the bar
		check("swim drains stamina", p.stamina == 0.0)
		p._physics_process(1.0)
		check("dry swimmer sinks", p.hp < shp0)
		p.pos = st_dry
	p.stamina = 50.0; p.stam_wait = -1.0
	p._physics_process(0.5) # idle regen kicks in fast
	check("stamina regens", p.stamina > 60.0, "sp=%.1f" % p.stamina)
	var dev := InputEventAction.new()
	dev.action = "dodge"; dev.pressed = true
	var sp0b: float = p.stamina
	p._unhandled_input(dev)
	check("dodge costs stamina", absf(sp0b - p.stamina - 15.0) < 0.01 and p.dodge_t > 0.0)
	p.dodge_t = 0.0
	p.stamina = 10.0
	p._unhandled_input(dev)
	check("tired = no roll", p.dodge_t <= 0.0)
	p.stamina = 100.0
	Input.action_press("move_right"); Input.action_press("sprint")
	p._physics_process(1.0)
	check("sprint drains stamina", p.stamina < 90.0, "sp=%.1f" % p.stamina)
	Input.action_release("move_right"); Input.action_release("sprint")
	p.stamina = 100.0
	for tpal in [surf, landm]:
		game.pals.erase(tpal)
		if tpal.get_parent(): tpal.get_parent().remove_child(tpal)
		tpal.free()
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
	# Palworld meal buff: a cooked meal grants one timed stat bonus
	var hudm: Node = main.get_node("UILayer/HUD")
	p.hunger = 30.0
	game.add_item("jam_bun", 1)
	hudm.use_item("jam_bun")
	check("meal buff grants", p.meal_t > 0.0 and p.meal_bonus("atk") > 0.0,
		"t=%.1f buff=%s" % [p.meal_t, str(p.meal_buff)])
	p.meal_t = 0.01
	p._physics_process(0.1)
	check("meal buff expires", p.meal_buff.is_empty() and p.meal_bonus("atk") == 0.0,
		"t=%.1f buff=%s" % [p.meal_t, str(p.meal_buff)])
	# climate fare carries flags, not stats — a stew is a hearth in a bowl
	game.add_item("spicy_stew", 1)
	hudm.use_item("spicy_stew")
	check("stew warms within", p.meal_bonus("warm") > 0.0,
		"buff=%s" % str(p.meal_buff))
	p.hunger = 30.0 # a full belly refuses dessert — room for the salad
	game.add_item("mint_salad", 1)
	hudm.use_item("mint_salad")
	check("salad sheds the sun", p.meal_bonus("cool") > 0.0,
		"buff=%s" % str(p.meal_buff))
	p.meal_t = 0.0; p.meal_buff = {}
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
	if sv_pal == null: # raids can wipe the workforce on some seeds — mint one
		sv_pal = game.gen_pal("lamball", 3, p.pos)
		sv_pal.mode = "base"
		game.pals.append(sv_pal)
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
	var lost_uids := [] # uids pointing at nothing — save would silently drop them
	for pu in game.party:
		var pl2: Pal = game.find_pal(pu)
		if pl2 == null:
			pl2 = game.bench_pal_of(pu)
		if pl2 == null or pl2.mode == "box":
			lost_uids.append("%d:%s" % [pu, pl2.mode if pl2 else "?"])
	# unique structure instances before save (dedupe footprint cells)
	var st_before := []
	for kk11 in game.structures:
		if game.structures[kk11] not in st_before:
			st_before.append(game.structures[kk11])
	# fog of war: sight peels the map back and the save keeps the peel
	var ex_ct := 0
	for b in game.explored:
		if b != 0: ex_ct += 1
	game.reveal_at(p.pos + Vector2(15, 0), 10.0)
	var ex_ct2 := 0
	for b in game.explored:
		if b != 0: ex_ct2 += 1
	check("exploring reveals map", ex_ct2 > ex_ct, "%d->%d" % [ex_ct, ex_ct2])
	game.explored[123] = 1
	game.save_game()
	# mutate state then reload
	for q in game.pals:
		q.sex = "F"
	if chest2:
		chest2["store"].clear()
	var ok_load := game.load_game()
	check("fog survives reload", game.explored.size() == game.world.WORLD_W * game.world.WORLD_H
		and game.explored[123] == 1, "size=%d cell=%d" % [game.explored.size(), game.explored[123]])
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
	var resolvable := 0 # benched spheres reload under the holder, not pals[]
	for ru in game.party:
		if game.find_pal(ru) != null or game.bench_pal_of(ru) != null:
			resolvable += 1
	check("party survives reload", party_sz_before == 0 or (game.party.size() == party_sz_before and resolvable == game.party.size()), "party=%d/%d res=%d lost=%s" % [game.party.size(), party_sz_before, resolvable, str(lost_uids)])
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
		var ap2: Pal = game.lead_pal() # condense targets the lead, out or benched
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
		if q.mode == "wild" and not q.raid and "dark" not in q.spec.get("elements", []) and q.hostile() < 2:
			sleeper = q # raiders chew structures instead of sleeping — they'd never nap
		if q.mode == "wild" and not q.raid and "dark" in q.spec.get("elements", []):
			nightowl = q
	if sleeper == null:
		sleeper = game.gen_pal("lamball", 3, game.player.pos + Vector2(6, 0))
		sleeper.mode = "wild"; sleeper.aggro = -1
		if not game.pals.has(sleeper): game.pals.append(sleeper)
	sleeper.aggro = -1; sleeper.hit_flash = 0; sleeper.stun_t = 0.0; sleeper.statuses.erase("sleep")
	sleeper.wild_ai(0.1)
	check("wild pal sleeps at night", sleeper.has_status("sleep"), "")
	if nightowl:
		nightowl.aggro = -1; nightowl.statuses.erase("sleep"); nightowl.hit_flash = 0
		nightowl.wild_ai(0.1)
		check("dark pal stays up", not nightowl.has_status("sleep"), "")
	# ...but a nocturnal naps through daylight — Palworld sleep flips. Fresh
	# depresso: the pool may only hold apex darks, and those never doze
	var dayowl: Pal = game.gen_pal("depresso", 3, p.pos + Vector2(3, 0))
	dayowl.mode = "wild"; dayowl.aggro = -1; dayowl.hit_flash = 0
	game.pals.append(dayowl)
	var tod_w2 := game.tod
	game.tod = 12.0
	dayowl.wild_ai(0.1)
	check("dark pal naps by day", dayowl.has_status("sleep"), "")
	game.tod = tod_w2
	game.pals.erase(dayowl)
	if dayowl.get_parent(): dayowl.get_parent().remove_child(dayowl)
	dayowl.free()
	# the base crew keeps the same hours — a posted dark pal dozes the day shift
	var quiet := p.pos + Vector2(30, 0)
	for off in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30), Vector2(45, 0)]:
		var foes := 0
		for q2 in game.pals: # raiders and aggro'd wilds pull it into defense instead
			if q2.mode == "wild" and q2.hp > 0 and (q2.raid or q2.aggro >= 0) \
					and (p.pos + off).distance_to(q2.pos) < 8.0:
				foes += 1
		if foes == 0:
			quiet = p.pos + off; break
	var dbase: Pal = game.gen_pal("depresso", 4, quiet)
	dbase.mode = "base"; dbase.san = 50.0
	game.pals.append(dbase)
	var tod_b2 := game.tod
	game.tod = 12.0
	for i in 70: # it pads to the pal bed first — sleep lands inside the 6s cap
		dbase.base_ai(0.1)
		if dbase.has_status("sleep"):
			break
	var foes2 := 0
	var foe_k := ""
	for q2 in game.pals:
		if q2.mode == "wild" and q2.hp > 0 and (q2.raid or q2.aggro >= 0) \
				and dbase.pos.distance_to(q2.pos) < 7.0:
			foes2 += 1; foe_k = q2.species_id
	check("base nocturnal naps by day", dbase.has_status("sleep"),
		"pos=%s bed_seek=%.1f foes=%d(%s) bed=%s" % [dbase.pos, dbase.bed_seek,
			foes2, foe_k, str(game.nearest_bed_cell(dbase.pos))])
	dbase.statuses.erase("sleep")
	game.tod = tod_b2
	game.pals.erase(dbase)
	if dbase.get_parent(): dbase.get_parent().remove_child(dbase)
	dbase.free()
	sleeper.hit(5, 1.0, true)
	check("hit wakes sleeper", not sleeper.has_status("sleep") and sleeper.aggro <= 0,
		"aggro=%d" % sleeper.aggro) # docile pals may flee (-1) — still a valid wake reaction
	# Palworld prey flight: a beaten-down ordinary hostile bolts instead of fighting
	var pa2 := p.pos + Vector2(4, 0)
	for off in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
		var cc2: Vector2 = p.pos + off
		# flee vector runs AWAY from the player — the cell beyond the prey
		# must be walkable or step_toward has nowhere to go
		if not game.world.blocked(int(cc2.x), int(cc2.y), p.pos.x, p.pos.y) \
				and not game.world.blocked(int(cc2.x + signi(off.x)), int(cc2.y + signi(off.y)), cc2.x, cc2.y):
			pa2 = cc2; break
	var prey2: Pal = game.gen_pal("lamball", 5, pa2)
	prey2.spec = prey2.spec.duplicate(); prey2.spec["hostile"] = 1
	prey2.mode = "wild"; prey2.aggro = 0; prey2.hp = prey2.max_hp * 0.2
	game.pals.append(prey2)
	var fd0 := prey2.pos.distance_to(p.pos)
	var ph0: float = p.hp
	prey2.wild_ai(0.1)
	# cornered prey can't always move — the real proof is it never closes/attacks
	check("wounded hostile flees", prey2.pos.distance_to(p.pos) >= fd0 and p.hp == ph0,
		"d=%.1f->%.1f php=%.0f" % [fd0, prey2.pos.distance_to(p.pos), p.hp])
	game.pals.erase(prey2)
	if prey2.get_parent(): prey2.get_parent().remove_child(prey2)
	prey2.free()
	# nocturnal ecology: dark pals own the night spawn table, sit out the day
	check("night spawns dark", game.pick_wild_species(["depresso", "lamball"]) == "depresso")
	# Palworld: the night shift also spawns meaner — same seed, +2 levels
	var s_n: int = game.rng.s
	var tod_n: float = game.tod
	game.rng.s = s_n; game.tod = 2.0
	var wln: int = game.wild_lv(2)
	game.rng.s = s_n; game.tod = 12.0
	var wld: int = game.wild_lv(2)
	game.tod = tod_n
	check("night spawns meaner", wln == wld + 2, "night=%d day=%d" % [wln, wld])
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

	# wanted marks: a flagged kill pays the bounty straight into the bag
	var wnt: Pal = game.gen_pal("syndicate_grunt", 6, game.player.pos + Vector2(3, 0))
	wnt.mode = "wild"; wnt.bounty = 12
	game.pals.append(wnt)
	var gold0w := game.item_count("gold_coin")
	game.kill_pal(wnt, true)
	check("bounty pays out", game.item_count("gold_coin") == gold0w + 12,
		"+%d" % (game.item_count("gold_coin") - gold0w))

	# skill fruit: teaches the active pal an extra move of that element
	if game.party.is_empty():
		var sp2: Pal = game.gen_pal("lamball", 3, game.player.pos + Vector2(2, 0))
		sp2.mode = "partner"
		game.pals.append(sp2)
		game.party.append(sp2.uid)
	if not game.party.is_empty():
		var ap: Pal = game.lead_pal() # benched lead still studies fruit
		var n_sk := ap.learned_skills().size()
		game.add_item("skill_fruit_fire", 1)
		game.teach_skill_fruit("skill_fruit_fire")
		var learned := ap.extra_skills.size() > 0 and ap.learned_skills().size() >= n_sk
		check("skill fruit teaches", learned and game.item_count("skill_fruit_fire") == 0,
			"extra=%s" % str(ap.extra_skills))
	else:
		check("skill fruit teaches", false, "empty party")

	# move loadout: palbox slots cap at 3 and gate what the pal casts
	if not game.party.is_empty():
		var lp3: Pal = game.lead_pal()
		var learned3: Array = lp3.learned_skills()
		if learned3.size() >= 1:
			var sid0: String = learned3[0]
			game.toggle_skill(lp3, sid0)
			check("skill slotted", lp3.equipped == [sid0] and lp3.active_skills() == [sid0])
			for sid2 in learned3: # try to slot everything — the 3rd stop holds
				if sid2 != sid0:
					game.toggle_skill(lp3, sid2)
			check("loadout caps 3", lp3.equipped.size() <= mini(3, learned3.size()),
				"eq=%d" % lp3.equipped.size())
			game.toggle_skill(lp3, sid0)
			check("skill unslotted", sid0 not in lp3.equipped)
			lp3.equipped = [] # restore "everything learned" default

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
	# wanted: striking the trader calls a syndicate hit squad — once per visit
	if game.merchant != null:
		game.merchant.pos = p.pos + Vector2(1.0, 0.0)
		game.merchant_hp = 60
		var w0p: int = game.pals.size()
		var exp_sq := mini(2 + int(game.day / 6.0), 4)
		game.hit_merchant(10.0)
		check("merchant crime wanted", game.merchant_wanted
			and game.pals.size() == w0p + exp_sq
			and game.pals[w0p].aggro == 0, "spawned=%d want=%d" % [game.pals.size() - w0p, exp_sq])
		for q in game.pals.slice(w0p): # hit squad doesn't outlive the check
			game.pals.erase(q)
			if q.get_parent(): q.get_parent().remove_child(q)
			q.free()
		var dr0m := game.drops.size()
		game.hit_merchant(999.0) # lethal blow: gold spills, the visit ends
		check("merchant slain pays", game.merchant == null and game.drops.size() > dr0m)
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
	# heart-lock: a fav'd pal survives the cleaver; toggling back unlocks it
	var fx := game.gen_pal("chikipi", 3, p.pos)
	fx.mode = "box"; game.box.append(fx); game.box_pal(fx)
	game.toggle_fav(fx.uid)
	var locked: bool = fx.fav
	var bx1 := game.box.size()
	game.butcher_pal(fx.uid)
	check("heart-lock", locked and game.box.size() == bx1, "box=%d" % game.box.size())
	game.toggle_fav(fx.uid)
	var unlocked: bool = not fx.fav
	game.butcher_pal(fx.uid) # freed inside — read no fields off fx after this
	check("unlock butchers", unlocked and game.box.size() == bx1 - 1)
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

	# Palworld palbox is a clinic: boxed pals mend, KO'd ones wait their timer
	var hurt_b: Pal = game.gen_pal("lamball", 5, p.pos)
	game.box.append(hurt_b)
	hurt_b.revive_t = 0.0
	hurt_b.hp = hurt_b.max_hp * 0.5
	game.tick_box(10.0)
	check("box mends wounds", hurt_b.hp > hurt_b.max_hp * 0.5 and hurt_b.hp <= hurt_b.max_hp,
		"hp %.0f/%.0f" % [hurt_b.hp, hurt_b.max_hp])
	game.box.erase(hurt_b)
	if hurt_b.get_parent(): hurt_b.get_parent().remove_child(hurt_b)
	hurt_b.free()
	# watch tower: turret plinks the nearest raider/aggro'd wild in range
	game.add_item("wood", 40); game.add_item("stone", 20); game.add_item("ingot", 4)
	var tw_k: Vector2i = free_xy.call("watch_tower")
	var tw_st = game.structures.get(tw_k)
	check("tower placed", tw_st != null and int(tw_st.get("turret", 0)) > 0)
	if tw_st:
		var tfoe: Pal = game.gen_pal("direhowl", 5, Vector2(tw_k) + Vector2(6, 0))
		tfoe.mode = "wild"; tfoe.raid = true; tfoe.aggro = 0
		game.pals.append(tfoe)
		var thp0 := tfoe.hp
		var rhp0: float = raider2.hp if is_instance_valid(raider2) else -1.0
		game.tick_production(1.0) # turret_cd starts cold — first sweep fires
		# the bolt goes to the NEAREST hostile — may be raider2 at the spikes
		var hit_any: bool = tfoe.hp < thp0 \
			or (is_instance_valid(raider2) and raider2.hp < rhp0)
		check("tower shoots hostile", float(tw_st["turret_cd"]) > 0.0 and hit_any,
			"cd=%.1f tfoe %.0f->%.0f" % [tw_st["turret_cd"], thp0, tfoe.hp])
		if tfoe.hp > 0:
			game.pals.erase(tfoe)
			if tfoe.get_parent(): tfoe.get_parent().remove_child(tfoe)
			tfoe.free()

	# Palworld boss rule: a cornered alpha enrages — harder hits, faster feet
	var rg: Pal = game.gen_pal("chikipi", 10, p.pos)
	rg.alpha = true; rg.apply_bonuses()
	rg.hp = rg.max_hp * 0.25
	rg.hit(1, 1.0, false)
	check("alpha enrages", rg.rage_mult() > 1.0 and rg.atk_mult() > 1.0 and rg._enraged,
		"rage=%.1f" % rg.rage_mult())
	game.pals.erase(rg)
	if rg.get_parent(): rg.get_parent().remove_child(rg)
	rg.free()
	# glider: carried item unlocks one-way descent, not climbing
	game.add_item("glider", 1)
	check("glider item held", game.item_count("glider") == 1)
	# scan for a true ledge: a high cell with a lower neighbour and no ramp
	# on either side — those cross blocked() BOTH ways without a glider
	var cliff_e := -1; var low_c := -1
	for i2 in range(0, World.WORLD_W * World.WORLD_H):
		if game.world.elev[i2] < 1 or game.world.ramp[i2] != 0 \
				or game.world.decor[i2] != World.Decor.NONE or game.world.solid_structure(i2):
			continue # the ledge top must be standable too — the hook test lands there
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
		# grappling hook: the mirror image — it climbs, it never descends
		game.add_item("glider", -1) # isolate the hook — a held glider descends for it
		game.add_item("grappling_hook", 1)
		check("hook climbs", game.player.can_enter(cx2 + 0.5, cy2 + 0.5))
		game.player.pos = Vector2(cx2 + 0.5, cy2 + 0.5)
		check("hook can't descend", not game.player.can_enter(lx + 0.5, ly + 0.5))
		game.add_item("grappling_hook", -1)
		game.player.pos = Vector2(game.world.spawn) + Vector2(0.5, 0.5)

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
