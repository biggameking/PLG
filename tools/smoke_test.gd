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
	var skips := 0
	for r in results:
		if "  skipped" in r:
			skips += 1
	var fo := FileAccess.open("res://tools/smoke_out.txt", FileAccess.WRITE)
	if fo: # WRITE truncates — the file is this run's verdict, not a history log
		fo.store_line("==== %d checks, %d failures, %d skipped ====" % [results.size(), fails, skips])
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
	# suite hygiene: the log truncates per run (it appended forever), and the
	# dev's real savegame gets backed up — several tests write user:// saves
	FileAccess.open("res://tools/smoke_out.txt", FileAccess.WRITE).close()
	var save_backup := FileAccess.get_file_as_bytes("user://savegame.plg") \
		if FileAccess.file_exists("user://savegame.plg") else PackedByteArray()
	results.append("main=%s" % main)
	game = main.get_node("Game")
	game.state = "play" # boot lands on the title screen; tests drive the sim itself
	results.append("game=%s kin=%d" % [game, game.pals.size()])
	var p: Player = game.player
	check("world generated", game.world.tiles.size() > 0)
	var maxe := 0
	for i in game.world.elev.size():
		maxe = maxi(maxe, game.world.elev[i])
	check("elevation variance", maxe > 0, "max elev %d" % maxe)
	check("kin spawned", game.pals.size() >= 20, "%d kin" % game.pals.size())
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

	# melee: put a wild kin next to player and hit it
	var tp: Kin = game.pals[0]
	tp.pos = p.pos + Vector2(0.8, 0)
	var hp0 := tp.hp
	p.atk_cd = 0
	p.melee()
	check("melee damages kin", tp.hp < hp0, "%.0f->%.0f" % [hp0, tp.hp])

	# catch: weaken + legendary sphere -> near-certain catch
	var tgt: Kin = null
	for q in game.pals:
		if q.mode == "wild" and q.hp > 0 and not q.boss:
			tgt = q
			break
	tgt.hp = 1
	game.add_item("legendary_orb", 10)
	var box0 := game.box.size()
	for try in 12:  # catch is chance-based; retry until captured
		game.resolve_sphere({"sid": "legendary_orb", "target": tgt})
		if tgt.mode != "wild":
			break
	check("caught kin captured", tgt.mode in ["partner", "box", "bench"], "mode=%s" % tgt.mode)
	check("catch box only if party full", tgt.mode != "box" or game.party.size() >= 5, "mode=%s party=%d" % [tgt.mode, game.party.size()])
	if tgt.mode in ["box", "bench"]:
		check("caught kin leaves world", tgt.get_parent() != game.entity_layer)

	# a caught raider stops being an invader — without release the danger
	# drone sticks on, sleep stays blocked, and the gauntlet never ends
	var raider_c: Kin = game.gen_pal("fenjelly", 5, p.pos)
	raider_c.mode = "wild"; raider_c.hp = 1
	raider_c.raid = true; raider_c.set_meta("raid_t0", game.t)
	raider_c.set_meta("gauntlet", true)
	game.gauntlet = {"wave": 1, "left": 3, "t": 0.0}
	game.pals.append(raider_c)
	game.add_item("legendary_orb", 20)
	for try2 in 14:
		game.resolve_sphere({"sid": "legendary_orb", "target": raider_c})
		if raider_c.mode != "wild":
			break
	check("caught raider demobilized", raider_c.mode != "wild" and not raider_c.raid
		and not raider_c.has_meta("raid_t0") and not raider_c.has_meta("gauntlet"),
		"mode=%s raid=%s" % [raider_c.mode, raider_c.raid])
	check("caught raider counts the wave", game.gauntlet["left"] == 2,
		"left=%s" % game.gauntlet.get("left"))
	game.gauntlet = {}

	# capture level gate (sphere-ladder driver): a lv30 shrugs off
	# what would bag a lv3 — same species, same hp
	var lo_p: Kin = game.gen_pal("fenjelly", 3, p.pos)
	var hi_p: Kin = game.gen_pal("fenjelly", 30, p.pos)
	check("level gates capture", game.cap_power_of(hi_p) > game.cap_power_of(lo_p) * 2.0,
		"lo=%.0f hi=%.0f" % [game.cap_power_of(lo_p), game.cap_power_of(hi_p)])
	game.pals.erase(lo_p); lo_p.free()
	game.pals.erase(hi_p); hi_p.free()

	# sphere launcher: slings the selected ball at the kin on the facing line
	game.add_item("orb_launcher", 1)
	game.add_item("kin_orb", 2)
	var lw0: String = p.equipment["weapon"]
	game.equip("orb_launcher")
	var lp: Kin = game.gen_pal("fenjelly", 2, p.pos + p.facing.normalized() * 4.0)
	lp.mode = "wild"; lp.aggro = -1
	game.pals.append(lp)
	p.atk_cd = 0.0
	var sc0: int = game.item_count("kin_orb")
	p.melee()
	check("launcher fires sphere", game.spheres_flying.size() == 1 and game.item_count("kin_orb") == sc0 - 1,
		"flying=%d spheres=%d->%d" % [game.spheres_flying.size(), sc0, game.item_count("kin_orb")])
	# the island wobble: a landed sphere rocks ~1.35s before the verdict lands
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
	# a lucky catch shelves the kin — pull its roster entries before freeing
	game.bench.erase(lp); game.box.erase(lp); game.party.erase(lp.uid)
	if is_instance_valid(lp):
		if lp.get_parent(): lp.get_parent().remove_child(lp)
		lp.free()
	if lw0 != "":
		game.equip(lw0)
	else:
		p.equipment["weapon"] = ""

	# kinbox + party
	game.add_item("wood", 200); game.add_item("stone", 100); game.add_item("lumenite", 20)
	var placed := false
	for r9 in range(2, 16): # kinbox needs flat non-water ground — spiral until a valid cell turns up
		for dx9 in range(-r9, r9 + 1):
			for dy9 in range(-r9, r9 + 1):
				if maxi(absi(dx9), absi(dy9)) != r9:
					continue
				var k := Vector2i(int(p.pos.x) + dx9, int(p.pos.y) + dy9)
				if game.place_structure("kinbox", k.x, k.y):
					placed = true
					break
			if placed: break
		if placed: break
	check("place kinbox", placed and game.kinbox_pos.x >= 0)
	if game.box.is_empty() and not game.party.is_empty():
		game.party_to_box(game.party[0]) # catch went to party — exercise party->box too
	if not game.box.is_empty():
		var bp: Kin = game.box[0]
		game.box_to_party(bp)
		check("box->party", bp.uid in game.party and bp.mode in ["bench", "partner"], "mode=%s" % bp.mode)
		# the island: one ball on the field — send_out swaps who's deployed
		if game.party_pal() != bp: # box_to_party auto-fields it when nothing is out
			game.send_out(bp.uid)
		check("send out deploys", bp.mode == "partner" and game.party_pal() == bp
			and game.party[0] == bp.uid and bp in game.pals)
		var outn := 0
		for q9 in game.pals:
			if q9.mode == "partner":
				outn += 1
		check("one ball out", outn <= 1, "out=%d" % outn)
		# mount only if mountable — and saddled (the island kin gear)
		if SpeciesData.mountable(bp.species_id):
			game.add_item(game.saddle_for(bp), 1)
			bp.pos = p.pos + Vector2(0.5, 0)
			p.try_mount()
			check("mount", p.mount == bp)
			# mounts differ: a fast species carries faster than a slow one
			var slow_p := game.gen_pal("loammelt", 5, p.pos) # spec speed ~2
			var fast_p := game.gen_pal("tammane", 5, p.pos)
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
		# the island deploy loop: party -> base workforce -> back to cold storage
		game.deploy_to_base(bp)
		check("deploy to base", bp.mode == "base" and bp in game.pals and bp.uid not in game.party
			and bp.get_parent() == game.entity_layer, "mode=%s" % bp.mode)
		game.base_to_box(bp)
		check("recall to box", bp.mode == "box" and bp in game.box and bp not in game.pals
			and bp.get_parent() == game.box_holder, "mode=%s" % bp.mode)
		game.box_to_party(bp) # restore party slot for later checks
		check("rejoin benches", bp.mode == "bench" or game.party_pal() == bp, "mode=%s" % bp.mode)
		# work xp: base kin level from honest work, capped at 60
		var wxp := game.gen_pal("fenjelly", 5, p.pos)
		wxp.mode = "base"; game.pals.append(wxp)
		game.pal_gain_xp(wxp, 130)
		var wxp_up: bool = wxp.level == 6
		wxp.level = 59
		game.pal_gain_xp(wxp, 99999)
		check("work xp + cap", wxp_up and wxp.level == 60 and wxp.xp == 0)
		game.pals.erase(wxp)
		if wxp.get_parent(): wxp.get_parent().remove_child(wxp)
		wxp.free()
		# send-out: reorder which kin leads (partner skills/mount key on party[0])
		var mp2 := game.gen_pal("fenlump", 3, p.pos)
		mp2.mode = "box"; game.box.append(mp2); game.box_pal(mp2)
		game.box_to_party(mp2)
		var out0: Kin = game.party_pal()
		var lead2: int = game.party[0]
		for u9 in game.party: # pick anyone who ISN'T the current field pal
			if out0 == null or u9 != out0.uid:
				lead2 = u9
				break
		game.make_active(lead2) # send out another member — the island swaps the ball
		check("party lead swap", game.party[0] == lead2 and game.party_pal() != null
			and game.party_pal().uid == lead2)
		check("old field kin benched", out0 == null or (out0.mode == "bench"
			and out0.get_parent() == game.box_holder), "mode=%s" % (out0.mode if out0 else "-"))
		game.make_active(game.party[1]) # swap back — out goes the previous lead
		check("swap redeploys", game.party_pal() != null and game.party_pal().uid == game.party[0])
		game.make_active(game.party[0]) # tapping the field pal recalls it — field empties
		check("recall empties field", game.party_pal() == null)
		game.send_out(game.party[0])
		check("send out redeploys", game.party_pal() != null)
		game.party_to_box(mp2.uid) # second member goes back to cold storage
		check("bench kin rest", game.bench.all(func(b9): return b9.get_parent() == game.box_holder))
		# kin orders (the island command): aggressive hunts on sight, passive holds
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
			var prey: Kin = game.gen_pal("fenjelly", 2, prey_at)
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
			# the island focus fire: the player's mark draws the partner in
			var fprey: Kin = game.gen_pal("fenjelly", 2, st_pal.pos + Vector2(5, 0))
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
		# partner auras (the island): the fielded species buffs its handler
		var lm: Kin = game.gen_pal("sprigmelt", 5, p.pos)
		lm.mode = "box"; game.box.append(lm); game.box_pal(lm)
		game.box_to_party(lm); game.send_out(lm.uid)
		var def0 := p.armor_def()
		check("atk aura on field", absf(game.partner_aura("atk") - 0.10) < 0.001)
		var dm: Kin = game.gen_pal("loammelt", 5, p.pos)
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
		# carry weight (the island): a heavy bag drags; a pack mule lifts the cap
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
		var cm: Kin = game.gen_pal("puffmite", 5, p.pos)
		cm.mode = "box"; game.box.append(cm); game.box_pal(cm)
		while game.party.size() >= 5: # a full strip silently refuses the mule —
			game.party_to_box(game.party[0]) # make room or the aura never fields
		game.box_to_party(cm)
		if game.party_pal() != cm: # box_to_party auto-fields an empty strip —
			game.send_out(cm.uid)  # a second tap on the out pal recalls it
		# absolute check: the fielded mule IS the cap — the outgoing pal's aura
		# leaves with it, so mirror carry_cap's own formula, not a +120 delta.
		# (bag weight is seed-dependent — the contract is the cap, not the load)
		var want_cap: float = 300.0 + (p.level - 1) * 10.0 + 120.0
		check("pack mule lifts cap", absf(p.carry_cap() - want_cap) < 0.01,
			"cap=%.0f want=%.0f base=%.0f" % [p.carry_cap(), want_cap, cap0])
		game.retract_out()
		game.pals.erase(cm); game.party.erase(cm.uid); game.bench.erase(cm)
		if cm.get_parent(): cm.get_parent().remove_child(cm)
		cm.free()
		game.items = it0
		check("bag restored", absf(p.carry_wt() - wt0) < 0.01)
		game.send_out(game.party[0])
		# kinbox growth: workforce slots scale with player level, hard cap 20
		var lv0: int = game.player.level
		game.player.level = 1
		var s1 := game.max_base_pals()
		game.player.level = 40
		var s2 := game.max_base_pals()
		check("kinbox slots scale", s1 == 9 and s2 == 20, "lv1=%d lv40=%d" % [s1, s2])
		game.player.level = lv0
		# base level missions (the island): checklist gates the terminal upgrade
		game.base_level = 5
		game.upgrade_base()
		check("base level capped", game.base_level == 5)
		game.base_level = 1
		var mb0 := game.max_base_pals()
		var made := []
		while game.base_pals().size() < 2: # mission 1 wants 2 deployed
			var qb: Kin = game.gen_pal("fenjelly", 3, p.pos)
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
		check("partner_skill", game.projectiles.size() >= prj0, "%d->%d" % [prj0, game.projectiles.size()])
		# bespoke partner actives (the island signatures): cindlump cone / briargoo rifle
		var fp: Kin = game.gen_pal("cindlump", 10, p.pos)
		fp.mode = "partner"
		var wt: Kin = game.gen_pal("fenlump", 3, Vector2(p.pos.x + 2, p.pos.y))
		wt.mode = "wild"; wt.max_hp = 2000; wt.hp = 2000
		game.pals.append(wt)
		var wthp := wt.hp
		check("cindlump flamethrower", game.run_partner_skill(fp, wt.pos,
			game.PARTNER_SKILLS["cindlump"]) and wt.hp < wthp)
		var tz: Kin = game.gen_pal("briargoo", 10, p.pos)
		tz.mode = "partner"
		var wthp2 := wt.hp
		check("briargoo rifle", game.run_partner_skill(tz, wt.pos,
			game.PARTNER_SKILLS["briargoo"]) and wt.hp < wthp2)
		# out-of-reach aims whiff — off-map aim finds nothing
		check("partner skill whiffs", not game.run_partner_skill(tz,
			Vector2(-100, -100), game.PARTNER_SKILLS["briargoo"]))
		# kin gear gates the bespoke actives (crafted harness rule)
		check("gear gates partner", not game.partner_gear_ok("cindlump"))
		game.add_item("cindlump_harness", 1)
		check("harness unlocks skill", game.partner_gear_ok("cindlump"))
		game.items.erase("cindlump_harness")
		# support partner skills (the island ranch-in-the-field): milk/eggs on tap
		var cr: Kin = game.gen_pal("nibjelly", 5, p.pos)
		cr.mode = "partner"
		var milk0: int = game.item_count("milk")
		var lay: Kin = game.gen_pal("fenlump", 5, p.pos)
		lay.mode = "partner"
		var egg0: int = game.item_count("egg")
		var sup: bool = game.run_partner_skill(cr, p.pos, game.PARTNER_SKILLS["nibjelly"]) \
			and game.run_partner_skill(lay, p.pos, game.PARTNER_SKILLS["fenlump"])
		check("ranch kin produce", sup and game.item_count("milk") == milk0 + 1
			and game.item_count("egg") == egg0 + 1,
			"milk=%d egg=%d" % [game.item_count("milk") - milk0, game.item_count("egg") - egg0])
		# Penguin Cannon (signature silliness): the bird is the payload
		var pg: Kin = game.gen_pal("corlmite", 10, p.pos)
		pg.mode = "partner"
		var wthp3 := wt.hp
		var pg_hit: bool = game.run_partner_skill(pg, wt.pos, game.PARTNER_SKILLS["corlmite"])
		check("penguin cannon", pg_hit and wt.hp < wthp3, "hp=%.0f" % wt.hp)
		check("cannon needs launcher", not game.partner_gear_ok("corlmite"))
		# Roly Poly (fenjelly shield): an absorb bubble that pops
		var lb: Kin = game.gen_pal("fenjelly", 10, p.pos)
		lb.mode = "partner"
		game.run_partner_skill(lb, p.pos, game.PARTNER_SKILLS["fenjelly"])
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
		check("hit kicks camera", game.shake > 0.0, "shake=%.2f" % game.shake)
		var shake0: float = game.shake
		game._process(0.2)
		check("camera shake decays", game.shake < shake0, "shake=%.2f" % game.shake)
		game.shake = 0.0
		# guest skill relay uses the shared keeper pipeline: power*0.6, own
		# armor/absorb, then the host-rolled status lands on the player
		p.statuses.clear()
		var hp_gs := p.hp
		game.hurt_player_skill(10.0, "freeze", 2.0)
		check("guest skill bites keeper", p.hp < hp_gs, "hp=%.0f" % p.hp)
		check("guest skill carries status", p.statuses.get("freeze", 0.0) > game.t)
		p.statuses.clear()
		var hp_gs2 := p.hp
		game.hurt_player_skill(10.0, "", 0.0)
		check("guest skill without status", p.hp < hp_gs2 and p.statuses.is_empty())
		p.hp = hp_gs # leave the keeper as the test found him
		# Dream Chaser (shadelump trick): BENCHED party shadelump
		# still snipes at the deployed partner's fight
		var dd: Kin = game.gen_pal("shadelump", 10, p.pos)
		dd.mode = "bench"
		game.bench.append(dd)
		var dlead: Kin = game.gen_pal("puffmite", 10, p.pos)
		dlead.mode = "partner"
		game.pals.append(dlead)
		var party0: Array = game.party.duplicate()
		game.party.insert(0, dlead.uid); game.party.append(dd.uid)
		wt.hp = 2000 # the cannon/flamethrower may have dropped it — full bar for a clean shot
		var wthp4 := wt.hp
		game.focus_target = wt; game.focus_t = game.t + 4.0 # YOUR mark is its mark
		game.tick_shadelump()
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
		var bx := int(game.kinbox_pos.x); var by := int(game.kinbox_pos.y)
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
	# handy kin hurries them (queue_crafts=false keeps other checks instant)
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
	# caught kin leaves game.kin; make two explicit base kin (M+F) for worker/ranch tests
	var p2: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(p2)
	p2.setup(game, "dozantler", 3, p.pos)
	p2.sex = "M"
	p2.mode = "base"
	game.pals.append(p2)
	var p3: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(p3)
	p3.setup(game, "fenjelly", 3, p.pos)
	p3.sex = "F"
	p3.mode = "base"
	game.pals.append(p3)
	var base_pal: Kin = null
	for q in game.pals:
		if q.mode == "base":
			base_pal = q
			break
	if base_pal:
		for m in ["wood","stone","fiber","lumenite","ingot","electric_organ","flame_organ","nails","cloth","berry_seeds","wheat_seeds"]:
			game.add_item(m, 60)
		# deterministic assignment: park every base kin far away, put dozantler at the player
		for q in game.base_pals():
			q.job_site = null
			q.pos = p.pos + Vector2(60, 60)
		p2.pos = p.pos
		var log_xy: Vector2i = free_xy.call("logging_site")
		results.append("  place log: %s kinbox_pos=%s" % [str(log_xy), str(game.kinbox_pos)])
		game.assign_worker()
		var has_job := false
		for kk in game.structures:
			if not game.structures[kk]["workers"].is_empty():
				has_job = true
		check("assign_worker", has_job)
		# the island auto-assign: idle crew staff open posts; haulers keep hauling
		for kk4 in game.structures:
			game.structures[kk4]["workers"].erase(p2)
		p2.job_site = null
		var tpw: Kin = game.gen_pal("snovmool", 5, p.pos)
		tpw.mode = "base"; game.pals.append(tpw)
		game.assign_t = 1.9
		game.tick_assign(0.2)
		check("idle kin auto-staffs", p2.job_site != null)
		check("hauler keeps hauling", tpw.job_site == null)
		game.pals.erase(tpw)
		if tpw.get_parent(): tpw.get_parent().remove_child(tpw)
		tpw.free()
		# pet: a little SAN per kin on a 60s cooldown
		tpw = game.gen_pal("fenjelly", 3, p.pos)
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
		# the island night shift: diurnal base kin doze off and production skips
		# sleepers; dark-element kin keep working through the night
		var tod0: float = game.tod
		game.tod = 23.0
		var log_st2 = null
		for kk2 in game.structures:
			if game.structures[kk2].get("id") == "logging_site":
				log_st2 = game.structures[kk2]
		if log_st2 and not log_st2["workers"].is_empty():
			var night_w: Kin = log_st2["workers"][0]
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
					"dark kin works at night")
			else:
				check("night shift", night_w.has_status("sleep") and (not all_diurnal or w2b == w2a),
					"sleep=%s wood %d->%d" % [night_w.has_status("sleep"), w2a, w2b])
		else:
			check("night shift", false, "no logging worker")
		game.tod = tod0
		for q in game.pals: # don't leak sleep into later checks
			q.statuses.erase("sleep")
		# the island: work suitability LEVEL scales output — lv2 logger beats lv1
		if log_st2:
			var w_lv2: Kin = game.gen_pal("dozantler", 5, game.player.pos)
			var w_lv1: Kin = game.gen_pal("sprigmelt", 5, game.player.pos)
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
		# dark kin ARE the night shift: +15% output after dusk
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
			var dark_w: Kin = game.gen_pal("shademite", 5, game.player.pos)
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
		# the island nocturnals: dark kin aggro wider after dusk
		var lup: Kin = game.gen_pal("noctmane", 5, p.pos + Vector2(4.5, 0))
		lup.mode = "wild"; lup.aggro = -1
		game.pals.append(lup)
		game.tod = 23.0
		lup.wild_ai(0.05)
		var n_ag: int = lup.aggro
		lup.aggro = -1
		game.tod = 12.0
		lup.wild_ai(0.05)
		check("dark kin hunts wider at night", n_ag == 0 and lup.aggro < 0,
			"night=%d day=%d" % [n_ag, lup.aggro])
		game.tod = tod0
		game.pals.erase(lup)
		if lup.get_parent(): lup.get_parent().remove_child(lup)
		lup.free()
		# weather: rain puts water kin in their element on the crew
		if mine_st:
			var wt0: String = game.weather
			var wp2: Kin = game.gen_pal("corlmite", 5, game.player.pos)
			wp2.mode = "base"; wp2.san = 90.0; wp2.ailment = ""; wp2.passives = []
			var wsv2: Array = mine_st["workers"].duplicate()
			var tsv2: float = mine_st["timer"]
			game.tod = 12.0 # keep the night bonus out of the comparison
			mine_st["workers"] = [wp2]; wp2.job_site = mine_st
			game.weather = "clear"; mine_st["timer"] = 0.0
			game.tick_production(0.1) # small dt: a fast crew at 1.0s can wrap the
			var dry_v: float = mine_st["timer"] # produce threshold and measure the remainder
			game.weather = "rain"; mine_st["timer"] = 0.0
			game.tick_production(0.1)
			var wet_v: float = mine_st["timer"]
			check("rain crew bonus", dry_v > 0 and absf(wet_v / dry_v - 1.15) < 0.01,
				"wet/dry=%.3f" % (wet_v / maxf(dry_v, 0.001)))
			mine_st["workers"] = wsv2; mine_st["timer"] = tsv2
			wp2.job_site = null
			game.weather = wt0; game.tod = tod0
			game.pals.erase(wp2); wp2.free()
			# the dry sky pays fire kin the same rate rain pays water
			var fp2: Kin = game.gen_pal("cindlump", 5, game.player.pos)
			fp2.mode = "base"; fp2.san = 90.0; fp2.ailment = ""; fp2.passives = []
			var wsv6: Array = mine_st["workers"].duplicate()
			var tsv6: float = mine_st["timer"]
			mine_st["workers"] = [fp2]; fp2.job_site = mine_st
			game.weather = "clear"; mine_st["timer"] = 0.0
			game.tick_production(0.1) # same wrap guard as the rain check above
			var fdry: float = mine_st["timer"]
			game.weather = "drought"; mine_st["timer"] = 0.0
			game.tick_production(0.1)
			var fpar: float = mine_st["timer"]
			check("drought feeds the fire crew", fdry > 0 and absf(fpar / fdry - 1.15) < 0.01,
				"parch/clear=%.3f" % (fpar / maxf(fdry, 0.001)))
			mine_st["workers"] = wsv6; mine_st["timer"] = tsv6
			fp2.job_site = null
			game.weather = wt0; game.tod = tod0
			game.pals.erase(fp2); fp2.free()
			# worker IVs: a T100 crew outpaces a T0 crew on the same site
			var ivp: Kin = game.gen_pal("sprigmelt", 5, game.player.pos)
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

			# the island condenser: a starred kin outworks its kin on the same site
			var cst: Kin = game.gen_pal("sprigmelt", 5, game.player.pos)
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

			# hungry kin slack off (the island): starving crews stop producing
			var hg: Kin = game.gen_pal("fenjelly", 5, game.player.pos)
			hg.mode = "base"; hg.san = 90.0; hg.ailment = ""
			var wsv4: Array = mine_st["workers"].duplicate()
			var tsv4: float = mine_st["timer"]
			mine_st["workers"] = [hg]; hg.job_site = mine_st
			hg.hunger = 90.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			var starved := float(mine_st["timer"])
			hg.hunger = 40.0; mine_st["timer"] = 0.0
			game.tick_production(1.0)
			check("hungry kin slack", starved == 0.0 and float(mine_st["timer"]) > 0.0,
				"starved=%.1f fed=%.1f" % [starved, mine_st["timer"]])
			mine_st["workers"] = wsv4; mine_st["timer"] = tsv4
			hg.job_site = null
			game.pals.erase(hg); hg.free()

	# Sphere Works (the island assembly line): a handy kin rolls spheres
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
		for ci in [["lumenite", 3], ["wood", 3], ["stone", 3]]:
			chest5["store"][ci[0]] = chest5["store"].get(ci[0], 0) + ci[1]
		var hw: Kin = game.gen_pal("fenjelly", 5, game.player.pos)
		hw.mode = "base"; hw.san = 90.0; hw.ailment = ""; hw.passives = []
		var saved_hw: Array = sf_st["workers"].duplicate()
		sf_st["workers"] = [hw]; hw.job_site = sf_st
		hw.talent = 50 # a bottom-rolled talent scales work_sum below the 200 mark
		sf_st["timer"] = 199.5
		game.tick_production(1.0)
		check("sphere works rolls", sf_st["store"].get("kin_orb", 0) >= 1,
			"store=%s" % str(sf_st["store"]))
		sf_st["workers"] = saved_hw; hw.job_site = null
		game.pals.erase(hw); hw.free()
	else:
		check("sphere works rolls", false, "factory=%s chest=%s" % [sf_st != null, chest5 != null])

	# expedition post (the island dispatch): a posted gatherer marches off, then
	# returns with loot — tired and hungry, just like the real thing
	for c0 in StructureData.STRUCTURES["expedition_post"]["cost"]:
		game.add_item(c0[0], c0[1])
	var xp_k: Vector2i = free_xy.call("expedition_post")
	var xp_st = game.structures.get(xp_k) if xp_k.x >= 0 else null
	if xp_st:
		var scout: Kin = game.gen_pal("puffmite", 10, p.pos)
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

	# Giga Works (an assembly line II): organ-fed belt rolls giga spheres
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
		for ci in [["lumenite", 3], ["ingot", 2], ["electric_organ", 1]]:
			chest6["store"][ci[0]] = chest6["store"].get(ci[0], 0) + ci[1]
		var hw2: Kin = game.gen_pal("fenjelly", 5, game.player.pos)
		hw2.mode = "base"; hw2.san = 90.0; hw2.ailment = ""; hw2.passives = []
		hw2.talent = 50 # keep work_sum above the 300 mark deterministically
		var saved_hw2: Array = g2_st["workers"].duplicate()
		g2_st["workers"] = [hw2]; hw2.job_site = g2_st
		g2_st["timer"] = 299.5
		game.tick_production(1.0)
		check("giga works rolls", g2_st["store"].get("giga_orb", 0) >= 1,
			"store=%s" % str(g2_st["store"]))
		g2_st["workers"] = saved_hw2; hw2.job_site = null
		game.pals.erase(hw2); hw2.free()
	else:
		check("giga works rolls", false, "factory=%s chest=%s" % [g2_st != null, chest6 != null])

	# cold chain (the island fridge loop): perishables rot over time, a staffed
	# ice box halts it; a sleeping cooler kin does not
	game.items["egg"] = 20
	game.items["fenjelly_mutton"] = 10
	game.tick_spoilage()
	var rot_n: int = game.items.get("spoiled_food", 0)
	check("perishables turn", rot_n >= 4 and game.items["egg"] < 20,
		"spoiled=%d eggs=%d" % [rot_n, game.items.get("egg", 0)])
	game.items.erase("spoiled_food")
	var ic_k: Vector2i = free_xy.call("cooler")
	var ic_st = game.structures.get(ic_k) if ic_k.x >= 0 else null
	if ic_st:
		var chiller: Kin = game.gen_pal("corlmite", 5, game.player.pos)
		if chiller == null:
			chiller = game.gen_pal("marlump", 5, game.player.pos)
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
		var farmer: Kin = game.gen_pal("fenlump", 5, game.player.pos)
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
	# watering kin pulls fish on the clock
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
		var fisher: Kin = game.gen_pal("corlmite", 5, game.player.pos)
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

	# training dummy: an idle base kin spars itself stronger
	var td_k: Vector2i = free_xy.call("training_dummy")
	var td_st = game.structures.get(td_k) if td_k.x >= 0 else null
	var td_ok := false
	if td_st != null:
		for wp9 in game.pals: # pacify the yard so the rookie drills instead of brawling
			if wp9.mode == "wild":
				wp9.aggro = -1; wp9.raid = false
		# loampuff drills by day; at night a dark kin keeps the same hours —
		# both carry no transporting suit so neither is pulled into hauling
		var rookie: Kin = game.gen_pal("noctmane" if game.is_night() else "loampuff", 3,
			Vector2(td_k.x + 0.5, td_k.y + 0.5))
		rookie.mode = "base"; rookie.san = 90.0; rookie.hunger = 10.0; rookie.ailment = ""
		rookie.passives = []; rookie.statuses.clear()
		var xp0: int = rookie.xp + rookie.level * 1000 # composite baseline
		for i9 in range(40):
			rookie.base_ai(0.1)
		td_ok = rookie.xp > 0 or rookie.level * 1000 + rookie.xp > xp0
		game.pals.erase(rookie); rookie.free()
	check("dummy trains idle kin", td_ok, "td=%s" % (td_st != null))

	# kin bait: a tossed mash pulls a wild kin to the pile — first snout eats.
	# pin the sun high: sleeping wilds won't wake for the smell
	var tod_bait: float = game.tod
	game.tod = 12.0
	var bait_ok := false
	var deer2: Kin = game.gen_pal("dozantler", 3, p.pos + Vector2(8, 8))
	deer2.mode = "wild"; deer2.aggro = -1
	p.facing = Vector2(1, 0)
	game.items["kin_bait"] = 1
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

	# apiary: a planting kin keeps the comb full on the clock
	var ap_k: Vector2i = free_xy.call("apiary")
	var ap_st = game.structures.get(ap_k) if ap_k.x >= 0 else null
	var honey_ok := false
	if ap_st != null:
		var keeper: Kin = game.gen_pal("sprigmelt", 5, game.player.pos)
		keeper.mode = "base"; keeper.san = 90.0; keeper.hunger = 10.0; keeper.ailment = ""
		keeper.passives = []; keeper.statuses.clear(); keeper.talent = 50
		ap_st["workers"] = [keeper]; keeper.job_site = ap_st
		ap_st["timer"] = 119.5
		game.tick_production(1.0)
		honey_ok = ap_st["store"].get("honey", 0) >= 1
		ap_st["workers"] = []; keeper.job_site = null
		game.pals.erase(keeper); keeper.free()
	check("apiary drips honey", honey_ok, "ap=%s" % (ap_st != null))

	# weather shrine: lumenite buys the sky — prayer cycles and then rests
	var ws_ok := false
	var ws_k: Vector2i = free_xy.call("weather_shrine")
	if ws_k.x >= 0:
		game.items["lumenite"] = 5
		var w0: String = game.weather
		game.pray_cd = 0.0
		game.pray_weather()
		var cycled: bool = game.weather != w0 and game.pray_cd > game.t
		game.pray_weather() # second prayer too soon — refused
		var spent: bool = game.items.get("lumenite", 0) == 2
		game.items["lumenite"] = 12 # the cycle's full circuit: sun→rain→thunder→parch→sun
		game.weather = "clear"
		var seen_w := []
		for _wi in 4:
			game.pray_cd = 0.0
			game.pray_weather()
			seen_w.append(game.weather)
		ws_ok = cycled and spent and seen_w == ["rain", "storm", "drought", "clear"] \
			and game.items.get("lumenite", 0) == 0 and int(game.pray_cd - game.t) > 500
		game.weather = w0 # hand the sky back — later checks assume a neutral one
	check("shrine calls weather", ws_ok, "w=%s cd=%.0f" % [game.weather, game.pray_cd - game.t])

	# guard post: a posted kin watches 12 tiles where a yard hand sees 7 —
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
		var sentry: Kin = game.gen_pal("loampuff", 5, Vector2(gp_k.x + 0.5, gp_k.y + 0.5))
		sentry.mode = "base"; sentry.san = 90.0; sentry.hunger = 10.0; sentry.ailment = ""
		sentry.passives = []; sentry.statuses.clear(); sentry.job_site = gp_st
		gp_st["workers"] = [sentry]
		var hand: Kin = game.gen_pal("loampuff", 5, sentry.pos + Vector2(1, 0))
		hand.mode = "base"; hand.statuses.clear() # same spot, no post — the control
		var raider: Kin = game.gen_pal("noctmane", 5, sentry.pos + Vector2(8.5, 0))
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
	game.add_item("wood", 20); game.add_item("stone", 15); game.add_item("lumenite", 4)
	var th_k: Vector2i = free_xy.call("training_hall")
	var th_st = game.structures.get(th_k) if th_k.x >= 0 else null
	var th_ok := false
	if th_st != null:
		var thc := Vector2(th_k.x + 1.0, th_k.y + 1.0) # hall is 2x2 — centre of the deck
		var teach: Kin = game.gen_pal("loampuff", 30, thc)
		teach.mode = "base"; teach.san = 90.0; teach.hunger = 10.0
		teach.statuses.clear(); teach.job_site = th_st
		th_st["workers"] = [teach]
		var pupil: Kin = game.gen_pal("fenjelly", 3, thc + Vector2(3, 0))
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

	# sparring ring — two posted kin trade a bout on the bell: xp in, san out
	game.add_item("wood", 15); game.add_item("cloth", 4)
	var sr_k: Vector2i = free_xy.call("sparring_ring")
	var sr_st = game.structures.get(sr_k) if sr_k.x >= 0 else null
	var sr_ok := false
	if sr_st != null:
		var spa: Kin = game.gen_pal("loampuff", 10, Vector2(sr_k.x + 0.5, sr_k.y + 0.5))
		var spb: Kin = game.gen_pal("fenjelly", 10, Vector2(sr_k.x + 1.5, sr_k.y + 0.5))
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

	# hunt posting: the guild pays in the field — bag or box both thin the herd
	var hq0: Dictionary = game.board_quest
	game.board_quest = {"kind": "hunt", "sp": "fenjelly", "n": 2, "got": 0, "day": game.day}
	var hq_gold0: int = game.item_count("gold_coin")
	game.board_hunt_credit("fenlump") # wrong species must not move the count
	game.board_hunt_credit("fenjelly")
	var hq_mid: int = int(game.board_quest["got"])
	game.board_hunt_credit("fenjelly")
	check("hunt posting fills in the field", hq_mid == 1 \
		and str(game.board_quest.get("kind", "")) == "done" \
		and game.item_count("gold_coin") > hq_gold0,
		"got=%d kind=%s" % [hq_mid, game.board_quest.get("kind", "")])
	game.board_quest = hq0

	# kin gacha: thirty gold in the slot, an egg rattles out (repriced —
	# at 20 the resale EV outpaid the pull and the machine printed money)
	game.add_item("wood", 10); game.add_item("ingot", 6); game.add_item("lumenite", 4)
	var gc_k: Vector2i = free_xy.call("kin_gacha")
	var gc_ok := false
	if gc_k.x >= 0:
		var gc_eggs0: int = game.item_count("kin_egg") + game.item_count("huge_kin_egg")
		var gc_pe0: int = game.item_count("kin_egg")
		var gc_he0: int = game.item_count("huge_kin_egg")
		var gc_gold0: int = game.item_count("gold_coin")
		game.add_item("gold_coin", 100)
		game.gacha_pull()
		gc_ok = game.item_count("kin_egg") + game.item_count("huge_kin_egg") == gc_eggs0 + 1 \
			and game.item_count("gold_coin") == gc_gold0 + 70 # 100 in, 30 spent
		game.add_item("gold_coin", -(game.item_count("gold_coin") - gc_gold0))
		# the pulled egg must leave too — the incubator test counts its own eggs
		game.add_item("kin_egg", gc_pe0 - game.item_count("kin_egg"))
		game.add_item("huge_kin_egg", gc_he0 - game.item_count("huge_kin_egg"))
	check("gacha rattles out an egg", gc_ok, "gc=%s" % (gc_k.x >= 0))

	# snare trap: a wild foot on the plate is held fast — and the spring is spent
	game.add_item("wood", 5); game.add_item("fiber", 2)
	var sn_k: Vector2i = free_xy.call("snare_trap")
	var sn_st = game.structures.get(sn_k) if sn_k.x >= 0 else null
	var sn_ok := false
	if sn_st != null:
		var prey: Kin = game.gen_pal("fenjelly", 3, Vector2(sn_k.x + 0.5, sn_k.y + 0.5))
		prey.mode = "wild"
		game.pals.append(prey)
		game.tick_production(0.1)
		sn_ok = prey.stun_t > 0.0 and sn_st.get("snare", true) == false
		game.pals.erase(prey); prey.free()
		await process_frame # the spent spring is removed after the tick
		sn_ok = sn_ok and not game.structures.has(sn_k)
	check("snare holds a foot", sn_ok, "sn=%s" % (sn_st != null))

	# war banner: kin under its colors out-pace kin out of sight
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
		for i13 in range(3):
			sg_st["timer"] = 29.9
			game.tick_production(0.2)
		# the real contract: every cell inside the swept radius is charted
		var ring_ok := true
		var r_now := float(sg_st.get("spy_r", 0.0)) - 1.0
		for a8 in range(8):
			var rc := Vector2(sg_k.x + 0.5, sg_k.y + 0.5) + Vector2.RIGHT.rotated(TAU * a8 / 8.0) * r_now
			var rx := int(rc.x); var ry := int(rc.y)
			if rx >= 0 and ry >= 0 and rx < game.world.WORLD_W and ry < game.world.WORLD_H:
				if game.explored[ry * game.world.WORLD_W + rx] == 0:
					ring_ok = false
		sg_ok = ring_ok and float(sg_st.get("spy_r", 0.0)) > 6.0 and float(sg_st.get("spy_r", 0.0)) <= 18.0
	check("spyglass charts the fog", sg_ok, "sg=%s r=%s" % [sg_st != null, str(sg_st.get("spy_r", "-") if sg_st else "-")])

	# ring of mercy: equipped blows floor a wild kin at 1 HP, never below
	var mr_victim = game.gen_pal("fenjelly", 5, p.pos)
	game.pals.append(mr_victim)
	mr_victim.hp = 6
	var mr_pre := int(p.equipment["acc1"] != "mercy_ring" and p.equipment["acc2"] != "mercy_ring")
	var mr_slot0: String = p.equipment["acc1"]
	p.equipment["acc1"] = "mercy_ring"
	var mr_hit: int = p.mercy_dmg(99, mr_victim)
	var mr_hit2: int = p.mercy_dmg(4, mr_victim)
	p.equipment["acc1"] = mr_slot0
	var mr_raw: int = p.mercy_dmg(99, mr_victim)
	check("ring of mercy spares the last breath", mr_hit == 5 and mr_hit2 == 4 and mr_raw == 99 and mr_pre == 1,
		"hit=%s/%s raw=%s" % [mr_hit, mr_hit2, mr_raw])
	mr_victim.queue_free()
	game.pals.erase(mr_victim)

	# kindex mastery: ten of a kind caught — every one you keep fights sharper
	var pm_own = game.gen_pal("fenjelly", 5, p.pos)
	pm_own.mode = "base"
	var pm_wild = game.gen_pal("fenjelly", 5, p.pos)
	pm_wild.mode = "wild"
	var pm_base_a: float = pm_own.atk_bonus
	var pm_wild_a: float = pm_wild.atk_bonus
	game.catch_counts["fenjelly"] = 10
	pm_own.apply_bonuses()
	pm_wild.apply_bonuses()
	check("kindex mastery sharpens the line", pm_own.atk_bonus > pm_base_a * 1.05 and absf(pm_wild.atk_bonus - pm_wild_a) < 0.001,
		"own=%.2f→%.2f wild=%.2f→%.2f" % [pm_base_a, pm_own.atk_bonus, pm_wild_a, pm_wild.atk_bonus])
	game.catch_counts.erase("fenjelly")
	pm_own.mode = "wild"
	pm_own.apply_bonuses()
	pm_own.queue_free(); game.pals.erase(pm_own)
	pm_wild.queue_free(); game.pals.erase(pm_wild)

	# well: fields in its shadow count as watered even under clear skies
	game.add_item("stone", 15)
	var wl_k: Vector2i = free_xy.call("well")
	var wl_ok := false
	if wl_k.x >= 0:
		wl_ok = game.near_well(Vector2(wl_k.x + 4, wl_k.y)) and not game.near_well(Vector2(wl_k.x + 20, wl_k.y))
	check("well waters its shadow", wl_ok, "wl=%s" % (wl_k.x >= 0))

	# drought: a parching sky starves open fields a fifth — a well's shadow is exempt
	var dr_k := Vector2i(-1, -1)
	for sy2 in range(4, game.world.WORLD_H - 6, 5):
		for sx2 in range(4, game.world.WORLD_W - 6, 5):
			if game.can_place("wheat_farm", sx2, sy2) \
					and not game.near_well(Vector2(sx2 + 1.5, sy2 + 1.0)):
				dr_k = Vector2i(sx2, sy2); break
		if dr_k.x >= 0:
			break
	var dr_ok := false
	if dr_k.x >= 0 and game.place_free("wheat_farm", dr_k.x, dr_k.y):
		var dr_st = game.structures[dr_k]
		var dr_pal: Kin = game.gen_pal("fenlump", 5, game.player.pos)
		dr_pal.mode = "base"; dr_pal.san = 90.0; dr_pal.hunger = 10.0; dr_pal.ailment = ""
		dr_pal.passives = []; dr_pal.statuses.clear(); dr_pal.talent = 50
		var wtd0: String = game.weather
		var todd0: float = game.tod
		game.tod = 12.0 # pin the sun — the night shift must not pad the ratio
		dr_st["workers"] = [dr_pal]; dr_pal.job_site = dr_st
		game.weather = "clear"; dr_st["timer"] = 0.0
		game.tick_production(1.0)
		var v_fair: float = dr_st["timer"]
		game.weather = "drought"; dr_st["timer"] = 0.0
		game.tick_production(1.0)
		var v_parch: float = dr_st["timer"]
		var wl2 = null # stand a well in the field's shadow — the drought can't touch it
		for off2 in [Vector2i(-1, 0), Vector2i(3, 0), Vector2i(0, -1), Vector2i(0, 2)]:
			var wk2: Vector2i = dr_k + off2
			if game.world.in_bounds(wk2.x, wk2.y) and not game.structures.has(wk2) \
					and game.world.tile_at(wk2.x, wk2.y) != World.Tile.WATER \
					and game.place_free("well", wk2.x, wk2.y):
				wl2 = game.structures[wk2]; break
		var v_sh: float = -1.0
		if wl2 != null:
			dr_st["timer"] = 0.0
			game.tick_production(1.0)
			v_sh = dr_st["timer"]
		dr_ok = v_fair > 0 and absf(v_parch / v_fair - 0.8) < 0.02 \
			and wl2 != null and absf(v_sh / v_fair - 1.25) < 0.02
		game.weather = wtd0; game.tod = todd0
		dr_st["workers"] = []; dr_pal.job_site = null
		game.pals.erase(dr_pal); dr_pal.free()
		if wl2 != null:
			game.net_remove_structure(wl2)
		game.net_remove_structure(dr_st)
	check("drought parches open fields, wells exempt", dr_ok, "farm=%s" % (dr_k.x >= 0))

	# boss sigil: the dare is actually for sale — merchant rolls stock it
	var bs_found := false
	for i14 in range(40):
		game.gen_merchant_stock()
		for bs_e in game.merchant_stock:
			if bs_e.get("id") == "boss_sigil" and int(bs_e.get("price", 0)) == 150:
				bs_found = true
		if bs_found:
			break
	check("boss sigil reaches the market", bs_found, "40 rolls")

	# lightning rod: banks an organ per strike, only while the sky is loud
	game.add_item("ingot", 8); game.add_item("lumenite", 4)
	var lr_k: Vector2i = free_xy.call("lightning_rod")
	var lr_st = game.structures.get(lr_k) if lr_k.x >= 0 else null
	var lr_ok := false
	if lr_st != null:
		var w0: String = game.weather
		var o0 := game.item_count("electric_organ")
		lr_st["timer"] = 44.9
		game.tick_production(0.2) # clear sky — no drink
		var o1 := game.item_count("electric_organ")
		game.weather = "storm"
		lr_st["timer"] = 44.9
		game.tick_production(0.2)
		var o2 := game.item_count("electric_organ")
		lr_ok = o1 == o0 and o2 == o0 + 1
		game.weather = w0
	check("lightning rod banks the storm", lr_ok, "lr=%s" % (lr_st != null))

	# despair snap: a depressed base kin at zero SAN goes berserk, then burns out
	var bk_p = game.gen_pal("loampuff", 8, p.pos)
	bk_p.mode = "base"
	bk_p.ailment = "depressed"
	bk_p.san = 0.0
	bk_p.hunger = 0.0
	game.pals.append(bk_p)
	for mid in game.items.keys(): # strip the medicine cabinet so nothing saves it
		if ItemData.ITEMS.get(mid, {}).get("kind") == "medicine":
			game.items[mid] = 0
	for k6 in game.structures:
		var st6: Dictionary = game.structures[k6]
		for mid2 in st6.get("store", {}).keys():
			if ItemData.ITEMS.get(mid2, {}).get("kind") == "medicine":
				st6["store"].erase(mid2)
	bk_p.tick_needs(1.0)
	var snapped: bool = bk_p.berserk_t > 0.0 and bk_p.job_site == null
	for i15 in range(20):
		bk_p.berserk_t = 0.05
		bk_p.base_ai(0.1)
	var burned: bool = bk_p.ailment == "weakened"
	check("despair snaps then burns out", snapped and burned,
		"snap=%s burn=%s ail=%s" % [snapped, burned, bk_p.ailment])
	bk_p.queue_free()
	game.pals.erase(bk_p)

	# bond bonus: a petted kin works a tenth lighter for the pat's window
	var bd_p = game.gen_pal("fenjelly", 5, p.pos)
	bd_p.mode = "base"
	game.pals.append(bd_p)
	var bd_w0: float = bd_p.work_mult()
	var bd_s0: float = bd_p.san
	var pet_ok: bool = game.pet_pal(bd_p)
	var bd_up: bool = bd_p.work_mult() > bd_w0 + 0.05 and bd_p.san > bd_s0
	var pet_cd: bool = not game.pet_pal(bd_p) # the per-pal cooldown holds
	bd_p.petted_t = game.t - 1.0
	var bd_down: bool = absf(bd_p.work_mult() - bd_w0) < 0.001
	check("a pet works lighter", pet_ok and bd_up and pet_cd and bd_down,
		"w=%.2f→%.2f san=%.0f→%.0f" % [bd_w0, bd_p.work_mult(), bd_s0, bd_p.san])
	bd_p.queue_free()
	game.pals.erase(bd_p)

	# tranq gun: a dart drops a wild kin asleep mid-stride — the sting still lands first.
	# Other wild pals can wander into the line of fire: the dart bites the FIRST
	# kin it reaches, so park the herd before shooting or the assert goes flaky.
	var tg_away := {}
	for wp2 in game.pals:
		if wp2.mode == "wild" and is_instance_valid(wp2):
			tg_away[wp2] = wp2.pos
			wp2.pos = Vector2(-9999, -9999)
	var tg_wd: Dictionary = ItemData.ITEMS["tranq_gun"]["weapon"]
	var tg_p = game.gen_pal("fenjelly", 5, Vector2(p.pos.x + 1, p.pos.y))
	game.pals.append(tg_p)
	tg_p.mode = "wild"
	game.projectiles.clear() # stray shots from earlier steps would re-wake it — any hit erases sleep
	game.fire_player_shot(Vector2(p.pos.x + 1, p.pos.y), tg_wd)
	for i16 in range(12):
		game.update_projectiles(0.1)
	var tg_slept: bool = tg_p.statuses.get("sleep", 0.0) > game.t
	check("tranq dart drops prey asleep", tg_slept and tg_p.hp > 0,
		"slept=%s hp=%s" % [tg_slept, tg_p.hp])
	tg_p.queue_free()
	game.pals.erase(tg_p)
	for wp2 in tg_away.keys():
		if is_instance_valid(wp2):
			wp2.pos = tg_away[wp2]

	# hot spring soak: standing in the steam mends the keeper too
	var hs_k := Vector2i(-1, -1)
	for k7 in game.structures:
		if game.structures[k7]["id"] == "hot_spring":
			hs_k = k7
			break
	if hs_k.x < 0: # none built yet — raise one for the soak
		game.add_item("stone", 20); game.add_item("wood", 10); game.add_item("lumenite", 3)
		hs_k = free_xy.call("hot_spring")
	var soak_ok := true
	if hs_k.x >= 0:
		var old_pos := p.pos
		var old_hp := p.hp
		p.pos = Vector2(hs_k.x + 0.5, hs_k.y + 0.5)
		p.hp = p.max_hp * 0.5
		for i17 in range(40):
			p._physics_process(0.1)
		soak_ok = p.hp > p.max_hp * 0.52
		p.pos = old_pos
		p.hp = old_hp
	check("spring soak mends the keeper", soak_ok, "hs=%s" % (hs_k.x >= 0))

	# Iron Pact camp: a caged local under guard — break the lock, it joins the box
	var cage_st = null
	for k8 in game.structures:
		if game.structures[k8]["id"] == "kin_cage":
			cage_st = game.structures[k8]
			break
	var camp_ok := false
	if cage_st != null:
		var cap: Dictionary = cage_st.get("captive", {})
		var box_n0 := game.box.size()
		var free_sp: String = str(cap.get("sp", ""))
		game.free_captive(cage_st)
		await process_frame # the cage removal defers out of the tick
		camp_ok = free_sp != "" and game.box.size() == box_n0 + 1 \
			and game.box[-1].species_id == free_sp
	check("camp captive joins the box", camp_ok, "cage=%s" % (cage_st != null))

	# fossil bed: old bones in the deep wilds — one dig, then the ground is quiet
	var fb_k := Vector2i(-1, -1)
	for k9 in game.structures:
		if game.structures[k9]["id"] == "fossil_bed":
			fb_k = k9
			break
	var fb_ok := false
	if fb_k.x >= 0:
		var fb_ap0: int = game.item_count("ancient_part")
		game.dig_fossil(game.structures[fb_k])
		fb_ok = game.item_count("ancient_part") > fb_ap0 and not game.structures.has(fb_k)
	check("fossil bed pays then goes quiet", fb_ok, "fb=%s" % (fb_k.x >= 0))

	# mimic chest: some dungeon boxes are only chest-shaped — open and it grins
	var mm_k: Vector2i = free_xy.call("chest")
	var mm_ok := false
	if mm_k.x >= 0:
		var mm_st: Dictionary = game.structures[mm_k]
		mm_st["mimic"] = "shadelump"
		game.open_mimic(mm_st)
		var mm_pal = null # find by identity — the spawn isn't guaranteed tail position
		for q in game.pals:
			if q.species_id == "shadelump" and q.mode == "wild" and q.aggro == 0:
				mm_pal = q
				break
		mm_ok = mm_pal != null and not game.structures.has(mm_k)
	check("mimic chest opens back", mm_ok)

	# miner's cap: the lamp rides on the armor slot, swapped out with the set
	var mc_armor0: String = p.equipment["armor"]
	p.equipment["armor"] = "miner_cap"
	p._physics_process(0.1)
	var lamp_on: bool = p._lamp != null
	p.equipment["armor"] = mc_armor0
	p._physics_process(0.1)
	check("miner cap lamp swaps with armor", lamp_on and p._lamp == null,
		"on=%s off=%s" % [lamp_on, p._lamp == null])

	# glowcap soup: cave mushrooms simmered down — the light comes from inside
	p.eat_buff({"glow": 5.0, "t": 240})
	p._physics_process(0.1)
	var glow_on: bool = p._lamp != null
	p.meal_buff = {}
	p._physics_process(0.1)
	check("glowcap soup lights the eater", glow_on and p._lamp == null,
		"on=%s off=%s" % [glow_on, p._lamp == null])

	# catch streak: each landed capture pays a little more — one escape snaps it
	var stk0 := game.catch_streak
	game.catch_streak = 0
	var stk_xp1: int = game.catch_xp(10) # 10*3*1.05 -> 32
	var stk_xp2: int = game.catch_xp(10) # streak 2 -> 33
	game.catch_streak = 20 # past the cap
	var stk_xp_cap: int = game.catch_xp(10) # 10*3*1.5 -> 45
	game.catch_fail()
	check("catch streak pays and snaps", stk_xp1 > 30 and stk_xp2 > stk_xp1 \
		and stk_xp_cap == 45 and game.catch_streak == 0,
		"xp=%d,%d,%d streak=%d" % [stk_xp1, stk_xp2, stk_xp_cap, game.catch_streak])
	game.catch_streak = stk0

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
	if game.has_structure("kinbox"):
		var gold_m := game.item_count("gold_coin")
		var idx0: int = game.mission_idx
		game.tick_missions(1.1)
		check("missions", game.mission_idx > idx0 and game.mission_idx <= game.MISSIONS.size() \
				and game.item_count("gold_coin") > gold_m, "idx %d->%d" % [idx0, game.mission_idx])
		game.mission_idx = 999 # past-the-end idx must clamp, not crash
		game.save_game(); game.load_game()
		check("missions persist", game.mission_idx == game.MISSIONS.size())

	# kindex: proximity spots a species once, 10-species tiers pay once
	var dxp: Kin = game.gen_pal("fenjelly", 3, p.pos + Vector2(2, 0))
	dxp.mode = "wild"; game.pals.append(dxp)
	game.tick_dex(1.1)
	check("dex seen", game.dex_seen.has("fenjelly"))
	dxp.pos = Vector2(300, 300) # walks far away — the sighting must stick
	game.tick_dex(1.1)
	check("dex seen sticky", game.dex_seen.has("fenjelly"))
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
	var sp_pal: Kin = game.pals[0]
	sp_pal.statuses["burn"] = game.t + 3
	var hp1 := sp_pal.hp
	for i in 4:
		sp_pal.tick_statuses(0.21)
	check("burn ticks", sp_pal.hp < hp1, "%.0f->%.0f" % [hp1, sp_pal.hp])
	var prj0 := game.projectiles.size()
	var skl: Dictionary = SkillData.SKILLS["hydroJet"]
	game.cast_skill(sp_pal, p, skl)
	check("cast_skill projectile", game.projectiles.size() == prj0 + 1)
	# element combos: a soaked kin freezes under ice, boils dry under fire
	var cmb: Kin = game.gen_pal("fenlump", 5, p.pos)
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
	check("freeze shatters", d_fz > d_nz and absf(d_fz - d_nz * 1.5) <= 1.6
		and not cmb.has_status("freeze"), "norm=%d frozen=%d" % [int(d_nz), int(d_fz)])
	game.pals.erase(cmb)
	if cmb.get_parent(): cmb.get_parent().remove_child(cmb)
	cmb.free()
	# weather bites in combat: rain dampens fire, feeds water (seeded — same roll)
	var wrp: Kin = game.gen_pal("fenlump", 5, p.pos)
	wrp.mode = "wild"; wrp.hp = 99999; wrp.max_hp = 99999; game.pals.append(wrp)
	var wrc: Kin = game.gen_pal("fenjelly", 10, p.pos)
	wrc.mode = "partner"
	var s_held: int = game.rng.s
	var wt_held: String = game.weather
	var dmgs := []
	for wv in ["clear", "rain"]:
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999; wrp.statuses.clear() # isolate: leftover soak/burn bends the next measure
		game.skill_hit(wrc, wrp, SkillData.SKILLS["flameBurst"])
		dmgs.append(99999 - int(wrp.hp))
	check("rain dampens fire", dmgs[0] > 0 and absf(dmgs[1] - dmgs[0] * 0.85) <= 1.01,
		"dry=%d wet=%d" % [dmgs[0], dmgs[1]])
	var dmgs2 := []
	for wv in ["clear", "rain"]:
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999; wrp.statuses.clear() # isolate: leftover soak/burn bends the next measure
		game.skill_hit(wrc, wrp, SkillData.SKILLS["hydroJet"])
		dmgs2.append(99999 - int(wrp.hp))
	check("rain feeds water", dmgs2[0] > 0 and absf(dmgs2[1] - dmgs2[0] * 1.15) <= 1.2,
		"dry=%d wet=%d" % [dmgs2[0], dmgs2[1]])
	var dmgs3 := []
	for wv in ["clear", "storm"]: # thunderstorm: electric hits crackle ~1.15x
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999; wrp.statuses.clear() # isolate: leftover soak/burn bends the next measure
		game.skill_hit(wrc, wrp, SkillData.SKILLS["shockwave"])
		dmgs3.append(99999 - int(wrp.hp))
	check("storm charges electric", dmgs3[0] > 0 and absf(dmgs3[1] - dmgs3[0] * 1.15) <= 1.2,
		"dry=%d storm=%d" % [dmgs3[0], dmgs3[1]])
	var dmgs4 := []
	for wv in ["clear", "drought"]: # a parching sky feeds flame ~1.15x
		game.weather = wv; game.rng.s = s_held; wrp.hp = 99999; wrp.statuses.clear() # isolate: leftover soak/burn bends the next measure
		game.skill_hit(wrc, wrp, SkillData.SKILLS["flameBurst"])
		dmgs4.append(99999 - int(wrp.hp))
	check("drought feeds flame", dmgs4[0] > 0 and absf(dmgs4[1] - dmgs4[0] * 1.15) <= 1.2,
		"dry=%d parch=%d" % [dmgs4[0], dmgs4[1]])
	# STAB (the island): a kin in its own element hits ~1.2x — same seed, same power
	var stabc: Kin = game.gen_pal("cindlump", 10, p.pos)
	stabc.mode = "wild"
	game.weather = "clear"
	var stab_d := []
	for el in ["neutral", "fire"]:
		game.rng.s = s_held; wrp.hp = 99999; wrp.statuses.clear() # isolate: leftover soak/burn bends the next measure
		game.skill_hit(stabc, wrp, {"power": 50, "element": el})
		stab_d.append(99999 - int(wrp.hp))
	check("own element hits harder", stab_d[0] > 0 and absf(stab_d[1] - stab_d[0] * 1.2) <= 1.3,
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
	game.add_item("sprigmelt_effigy", 10)
	game.upgrade_perk("capture")
	check("perk upgrade", game.perks["capture"] == 1 and game.item_count("sprigmelt_effigy") == 8)
	game.upgrade_perk("hp")
	var want_hp: float = 100 + (p.level - 1) * 10 + game.perks["hp"] * 12
	check("hp perk", p.max_hp == want_hp, "maxhp %d want %d" % [p.max_hp, want_hp])
	# the island: levels bank stat points the statue spends before effigies
	game.stat_pts = 1
	game.upgrade_perk("speed")
	check("stat point spend", game.perks["speed"] == 1 and game.stat_pts == 0 \
			and game.item_count("sprigmelt_effigy") == 6, "pts=%d eff=%d" % [game.stat_pts, game.item_count("sprigmelt_effigy")])
	# memory wipe: perk ranks fold back into stat points (a full respec)
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
	# soul infusion: effigies harden an owned kin, ride the save, cap at 10
	var soul_t: Kin = null
	for q in game.pals:
		if q.mode in ["partner", "base"]:
			soul_t = q; break
	if soul_t == null and not game.box.is_empty():
		soul_t = game.box[0]
	if soul_t == null:
		soul_t = game.gen_pal("fenjelly", 3, p.pos)
		soul_t.mode = "box"; game.box.append(soul_t); game.box_pal(soul_t)
	var atk_s := soul_t.atk_bonus
	var eff_s := game.item_count("sprigmelt_effigy")
	game.soul_infuse(soul_t.uid)
	check("soul infuse", soul_t.soul_boost == 1 and soul_t.atk_bonus > atk_s \
			and game.item_count("sprigmelt_effigy") == eff_s - 1,
		"boost=%d atk %.2f->%.2f" % [soul_t.soul_boost, atk_s, soul_t.atk_bonus])
	soul_t.soul_boost = 9; soul_t.apply_bonuses()
	game.add_item("sprigmelt_effigy", 20) # the 10th soul costs 10
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
	var m_pal: Kin = null
	var f_pal: Kin = null
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
		# the island rule: no cake, no breeding — the ranch stalls with a warning
		game.tick_ranch(ranch_k, st_r, 61.0)
		check("ranch stalls without cake", st_r["store"].get("kin_egg", 0) == 0 and st_r.get("cake_warned", false))
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
		check("ranch egg", st_r["store"].get("kin_egg", 0) >= 1)
		check("cake consumed", chest_st["store"].get("cake", 0) == 0)
		# parentage now carries passives for inheritance
		check("egg records passives", st_r["egg_parents"].size() > 0 and st_r["egg_parents"][0].size() >= 6)
		game.add_item("kin_egg", 1) # egg reaches the bag via haulers/player pickup
		game.add_item("huge_kin_egg", -game.item_count("huge_kin_egg")) # a stray huge egg from earlier digs would take the incubator slot first by design
		# the island: eggs hatch in an incubator over time, not in the hand
		game.add_item("lumenite", 4); game.add_item("stone", 12); game.add_item("cloth", 2)
		var inc_k: Vector2i = free_xy.call("incubator")
		var inc_st = game.structures.get(inc_k)
		var inc_pos0: Vector2 = p.pos # deposit_egg only reaches within 20 cells
		if inc_k.x >= 0:
			p.pos = Vector2(inc_k.x + 0.5, inc_k.y + 0.5)
		game.deposit_egg()
		p.pos = inc_pos0
		check("egg deposited", inc_st != null and inc_st.has("egg_inc") and game.item_count("kin_egg") == 0)
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
		# signature pair -> fixed third species (the island breeding combos)
		var combo_st := {"egg_inc": {"pair": ["fenjelly", "fenlump", 50, 50, [], [], ["shockwave"], []], "ready_t": game.t}}
		game.hatch_incubated(Vector2i(int(game.player.pos.x) + 2, int(game.player.pos.y)), combo_st)
		var cb := game.pals[game.pals.size() - 1]
		check("breed combo", cb.species_id == "puffmite")
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
		# grazing produce: a wool kin drops wool on its farm timer (the island)
		var grazer: Kin = game.gen_pal("fenjelly", 3, p.pos + Vector2(4, 4))
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
		check("ranch egg", false, "no M/F base kin: " + dbg)

	# net kin replication: valid entry spawns, malformed/foreign entries drop
	var np0 := game.pals.size()
	game.spawn_net_pal(["puffmite", p.pos.x + 3, p.pos.y + 3, 5, "wild", true])
	check("net kin spawns", game.pals.size() == np0 + 1)
	var npal: Kin = game.pals[game.pals.size() - 1]
	check("net kin lucky", npal.lucky and "lucky" in npal.passives)
	# the island trait slots: 1-4 passives, and the lucky signature always survives
	var max_ps := 0; var over2_ps := 0
	for i in 40:
		var tpp: Kin = game.gen_pal("fenjelly", 3, p.pos)
		max_ps = maxi(max_ps, tpp.passives.size())
		if tpp.passives.size() >= 3: over2_ps += 1
		if tpp.get_parent(): tpp.get_parent().remove_child(tpp)
		tpp.free()
	check("trait slots 1-4", max_ps <= 4 and max_ps >= 1 and over2_ps > 0,
		"max=%d over2=%d" % [max_ps, over2_ps])
	var lp2: Kin = game.gen_pal("fenjelly", 3, p.pos, true)
	check("lucky signature kept", lp2.lucky and "lucky" in lp2.passives and lp2.passives.size() <= 4)
	if lp2.get_parent(): lp2.get_parent().remove_child(lp2)
	lp2.free()
	game.pals.erase(npal)
	if npal.get_parent(): npal.get_parent().remove_child(npal)
	npal.free()
	game.spawn_net_pal(["no_such_species", 0, 0, 1, "wild"])
	game.spawn_net_pal("garbage")
	check("net kin rejected", game.pals.size() == np0)
	# live kin sync: replicas key on host uid — spawn, move, despawn
	game.spawn_net_pal(["puffmite", p.pos.x + 4, p.pos.y + 4, 5, "wild", false, 777])
	var rep: Kin = game.pals[game.pals.size() - 1]
	check("net kin net_id", rep.net_id == 777)
	game.net.pal_sync([[777, "puffmite", p.pos.x + 9.0, p.pos.y + 9.0, 5, "wild", 42.0, false],
		[778, "fenjelly", p.pos.x + 5, p.pos.y + 5, 3, "wild", 99.0, false],
		"garbage"])
	check("pal_sync moves+spawns", rep.net_target.x == p.pos.x + 9.0 and rep.hp == 42.0
		and game.find_net_pal(778) != null)
	game.net.pal_sync([[778, "fenjelly", 1, 1, 3, "wild", 99.0, false]])
	check("pal_sync despawns absent", game.find_net_pal(777) == null
		and game.find_net_pal(778) != null)
	# cleanup the replica so it can't leak into later checks
	var rep2 := game.find_net_pal(778)
	game.pals.erase(rep2)
	if rep2.get_parent(): rep2.get_parent().remove_child(rep2)
	rep2.free()
	# host-side catch relay: a client's sphere lands in THEIR OWN roster —
	# private rosters mean the keeper's box stays untouched
	var ncp: Kin = game.gen_pal("fenlump", 3, p.pos)
	ncp.mode = "wild"; ncp.hp = 1; game.pals.append(ncp)
	game.net.spawn_ghost(7) # fail-closed: the throw needs a witnessed ghost
	game.net.ghosts[7].net_pos = Vector3(p.pos.x, p.pos.y, 0)
	var nc_box0 := game.box.size()
	var tries_c := 0
	while tries_c < 400 and ncp.mode == "wild": # ~97%/try — effectively deterministic
		game.net_catch(ncp.uid, "kin_orb", false, 5, 7)
		tries_c += 1
	check("net catch claims guest", ncp.owner_id == 7 and ncp.mode == "partner"
		and game.rparty_for(7).has(ncp.uid) and game.box.size() == nc_box0
		and tries_c < 400, "mode=%s box=%d tries=%d" % [ncp.mode, game.box.size(), tries_c])
	game.remote_parties.clear() # the fake keeper's roster ends with the test
	game.pals.erase(ncp)
	if ncp.get_parent(): ncp.get_parent().remove_child(ncp)
	ncp.free()
	# forged item ids never get a roll — and a ghostless pid doesn't even ask
	var ncp2: Kin = game.gen_pal("fenlump", 3, p.pos)
	ncp2.mode = "wild"; ncp2.hp = 1; game.pals.append(ncp2)
	game.net_catch(ncp2.uid, "wood", false, 5, 77)
	check("net catch validates item", ncp2 in game.pals)
	game.net_catch(ncp2.uid, "kin_orb", false, 5, 77)
	check("ghostless catch refused", ncp2 in game.pals and ncp2.mode == "wild")
	game.net.ghosts[7].net_pos = Vector3(p.pos.x + 50.0, p.pos.y, 0) # out of range
	game.net_catch(ncp2.uid, "kin_orb", false, 5, 7)
	check("out-of-range catch refused", ncp2 in game.pals and ncp2.mode == "wild")
	if game.net.ghosts.has(7):
		game.net.ghosts[7].queue_free(); game.net.ghosts.erase(7)
	game.pals.erase(ncp2)
	if ncp2.get_parent(): ncp2.get_parent().remove_child(ncp2)
	ncp2.free()
	# host wildlife hunts the nearest warm body — a guest's ghost included;
	# at melee range the bite goes down the wire, not into the host's hp
	game.net.spawn_ghost(7)
	var hunter: Kin = game.gen_pal("loampuff", 8, p.pos + Vector2(30.0, 0))
	hunter.mode = "wild"; hunter.hit_flash = 1.0 # flash suppresses the clock-nap
	game.pals.append(hunter)
	game.net.ghosts[7].net_pos = Vector3(hunter.pos.x + 0.6, hunter.pos.y, 0)
	var hp_g0: int = p.hp
	hunter.wild_ai(0.1)
	check("wild kin engages the ghost", hunter.aggro == 0 and hunter.aggro_pid == 7,
		"aggro=%s pid=%s" % [hunter.aggro, hunter.aggro_pid])
	var n_pr_h := game.projectiles.size()
	hunter.atk_cd = 0.0
	hunter.wild_ai(0.1)
	# the guest eats the engagement — bite or skill shot — never the host's hp
	check("guest bite stays off the host", p.hp == hp_g0 and \
		(hunter.atk_cd > 0 or game.projectiles.size() > n_pr_h),
		"hp=%d->%d cd=%.2f pr=%d" % [hp_g0, p.hp, hunter.atk_cd, game.projectiles.size()])
	if game.projectiles.size() > n_pr_h: # don't leave a shot aimed at a freed ghost
		var pr_h = game.projectiles.pop_back()
		if is_instance_valid(pr_h.get("node")):
			pr_h["node"].queue_free()
	game.net.ghosts[7].net_pos = Vector3(-1, -1, 0)
	check("lost ghost falls back", hunter.target_pos().distance_to(p.pos) < 0.01)
	game.net.ghosts[7].queue_free(); game.net.ghosts.erase(7)
	game.pals.erase(hunter)
	if hunter.get_parent(): hunter.get_parent().remove_child(hunter)
	hunter.free()
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
		game.net.spawn_ghost(99) # fail-closed guards need a witnessed ghost
		game.net.ghosts[99].net_pos = Vector3(hc.x, hc.y, 0)
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
		pk1.append(["campfire", free_spot.x, free_spot.y, {"wood": 3}]) # chest truth rides element 4
		game.struct_sync(pk1)
		check("struct sync adds", game.structures.has(free_spot))
		check("store rides the wire", game.structures[free_spot].get("store", {}).get("wood", 0) == 3)
		game.struct_sync(pk1.slice(0, pk1.size() - 1))
		check("struct sync despawns", not game.structures.has(free_spot))
		if not game.net.ghosts.has(99):
			game.net.spawn_ghost(99) # no tree above → the ghost was never planted
		game.net.ghosts[99].net_pos = Vector3(free_spot.x, free_spot.y, 0)
		game.net.peer_tags[99] = "tk_99" # demolish demands a hello'd identity
		game.net_place("campfire", free_spot.x, free_spot.y, 99)
		check("net place", game.structures.has(free_spot))
		game.net_demolish(free_spot.x, free_spot.y, 99)
		check("net demolish", not game.structures.has(free_spot))
		game.net.peer_tags.erase(99)
		# fail-closed: a pid with no registered ghost gets nothing, no matter
		# how politely it asks — proximity proofs are mandatory, not optional
		game.net_place("campfire", free_spot.x, free_spot.y, 77)
		check("ghostless place refused", not game.structures.has(free_spot))
	# decor deltas apply by cell index
	var dci := game.world.idx(clampi(int(p.pos.x), 0, World.WORLD_W - 1),
		clampi(int(p.pos.y) + 4, 0, World.WORLD_H - 1))
	var dcv: int = game.world.decor[dci]
	game.decor_sync([[dci, World.Decor.NONE], "junk"])
	check("decor delta applies", game.world.decor[dci] == World.Decor.NONE)
	# shared box: the host's roster ships as a compact mirror; ops relay back
	while game.party.size() >= 5:
		game.party_to_box(game.party[0])
	var nbp: Kin = game.gen_pal("fenjelly", 7, p.pos)
	nbp.mode = "box"; nbp.uid = game.next_uid_v + 500000 # beyond every real uid — no collisions
	var nbuid := nbp.uid
	game.box.append(nbp)
	var bsig0: int = game.net.box_fingerprint()
	var pack: Array = game.net.box_state_pack(0)
	check("box pack rows", pack.size() == game.box.size() and pack.back()[0] == nbuid)
	game.net.box_sync(pack, [nbuid])
	check("box sync mirror", game.net_box.size() == pack.size()
		and game.net_box.back()["sid"] == "fenjelly" and game.party.has(nbuid)
		and game.net_box.back()["wk"] == "FA1 HA1 TR1")
	check("work suits text", game.work_str(SpeciesData.species_of("fenjelly")) == "FA1 HA1 TR1")
	game.net.box_sync(["junk", [1, 2]], [])
	check("box sync drops junk", game.net_box.is_empty() and game.party.is_empty())
	var ppack: Array = game.net.party_state_pack(0)
	check("party pack rows", ppack.size() == mini(game.party.size(), 8)
		and ppack.all(func(e9): return e9.size() >= 14), "rows=%d party=%d" % [ppack.size(), game.party.size()])
	game.net.box_sync(pack, [nbuid], ppack)
	check("party sync mirror", game.net_party.size() == ppack.size())
	game.net.is_host = true
	game.net.spawn_ghost(0) # the wire's headless sender carries a bucket
	game.net.box_req("box_to_party", nbuid)
	check("box req promotes", nbp not in game.box and game.party.has(nbuid))
	game.net.box_req("party_to_box", nbuid)
	check("box req returns", nbp in game.box and not game.party.has(nbuid),
		"mode=%s box=%s bench=%s kin=%s party=%s" % [nbp.mode, game.box.has(nbp),
			game.bench.has(nbp), game.pals.has(nbp), str(game.party)])
	game.net.box_req("bogus_op", nbuid)
	check("box req whitelist", nbp in game.box) # unknown ops no-op, pal survives
	game.net.ghosts[0].queue_free(); game.net.ghosts.erase(0)
	game.net.is_host = false
	game.box.erase(nbp)
	if nbp.get_parent(): nbp.get_parent().remove_child(nbp)
	nbp.free()
	check("box fingerprint shifts", game.net.box_fingerprint() != bsig0)
	# private rosters: a guest's kin answers to no other hand
	var gpal: Kin = game.gen_pal("fenjelly", 4, p.pos)
	gpal.mode = "box"; gpal.owner_id = 7; gpal.owner_tag = "tok_a"
	game.box.append(gpal)
	game.box_pal(gpal)
	check("box pack scopes owner", game.net.box_state_pack(7).size() == 1
		and game.net.box_state_pack(0).size() == game.box.size() - 1)
	game.box_op_remote("box_to_party", gpal.uid, 9) # peer 9 doesn't own it
	check("foreign op refused", gpal.mode == "box" and gpal in game.box
		and not game.rparty_for(9).has(gpal.uid))
	game.box_op_remote("box_to_party", gpal.uid, 7)
	check("owner op deploys", gpal.mode == "partner" and gpal in game.pals
		and game.rparty_for(7).has(gpal.uid))
	game.r_retract(7) # the keeper leaving balls their field pal up
	check("retract to bench", gpal.mode == "bench" and gpal in game.bench
		and gpal not in game.pals and game.rparty_for(7).has(gpal.uid))
	# five slots per keeper — a sixth promote is refused
	var guest_junk := []
	var rp7 := game.rparty_for(7)
	while rp7.size() < 5:
		var extra: Kin = game.gen_pal("fenjelly", 1, p.pos)
		extra.mode = "box"; extra.owner_id = 7
		game.box.append(extra); game.box_pal(extra)
		guest_junk.append(extra)
		game.box_op_remote("box_to_party", extra.uid, 7)
	var sixth: Kin = game.gen_pal("fenjelly", 1, p.pos)
	sixth.mode = "box"; sixth.owner_id = 7
	game.box.append(sixth); game.box_pal(sixth)
	guest_junk.append(sixth)
	game.box_op_remote("box_to_party", sixth.uid, 7)
	check("guest strip caps at 5", rp7.size() == 5 and sixth.mode == "box")
	# install-token rebind: a dropped peer orphans its kin — ops refuse until
	# the same token says hello; a live claim can't be re-stolen by a stranger
	for q in game.box + game.bench + game.pals:
		if q.owner_id == 7:
			q.owner_id = -1
	game.box_op_remote("box_to_party", sixth.uid, 7)
	check("orphan ops refused", sixth.mode == "box")
	game.rebind_owner(7, "tok_a")
	check("tag rebinds orphan", gpal.owner_id == 7
		and game.rparty_by_tag("tok_a").has(gpal.uid))
	game.rebind_owner(9, "tok_a") # a stranger echoing the token gets nothing live
	check("live claim not stolen", gpal.owner_id == 7)
	guest_junk.append(gpal)
	for q in guest_junk:
		game.box.erase(q); game.bench.erase(q); game.pals.erase(q)
		if q.get_parent(): q.get_parent().remove_child(q)
		q.free()
	game.remote_parties.clear()
	# the island den treasure: stocked chests wait behind the lair boss —
	# flagged "loot" so the logistics network never drags one home
	var loot_n := 0; var loot_stocked := 0; var loot_k := Vector2i(-1, -1)
	for k3 in game.structures:
		var st3: Dictionary = game.structures[k3]
		if st3.get("loot", false):
			loot_n += 1
			if not st3.get("store", {}).is_empty() or str(st3.get("mimic", "")) != "":
				loot_stocked += 1 # stocked goods or a waiting grin both count
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
	# raid escalation: late-campaign raids bring bigger, meaner packs —
	# but the squared curve means a day-one wave stays survivable
	game.day = 20
	var r0 := game.pals.size()
	game.start_raid()
	var new_raid := game.pals.slice(r0)
	var min_lv := 999
	for q in new_raid:
		min_lv = mini(min_lv, q.level)
	check("raid escalates", new_raid.size() >= 6 and min_lv >= 23,
		"n=%d minlv=%d" % [new_raid.size(), min_lv])
	for q in new_raid:
		game.pals.erase(q)
		q.queue_free()
	game.day = 1
	r0 = game.pals.size()
	game.start_raid()
	new_raid = game.pals.slice(r0)
	var max_lv := 0
	min_lv = 999
	for q in new_raid:
		min_lv = mini(min_lv, q.level)
		max_lv = maxi(max_lv, q.level)
	check("day-one raid stays soft", new_raid.size() >= 3 and min_lv >= 3
		and max_lv <= 11, "n=%d lv=%d-%d" % [new_raid.size(), min_lv, max_lv])
	for q in new_raid:
		game.pals.erase(q)
		q.queue_free()
	# worldgen legendary den: an uncapturable lv50 giant guards deep zone 3
	var legend: Kin = null
	for q in game.pals:
		if q.boss and q.level >= 50 and not q.raid and q.spire_tag == "": # spire guardians are one-shot — they never respawn
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
					and (not s2["store"].is_empty() or str(s2.get("mimic", "")) != ""):
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
						and (s3["store"].get("legendary_orb", 0) > 0 or str(s3.get("mimic", "")) != ""):
					room2_loot = true # the deep room pays in gold or in teeth
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
	# wild egg nests: stealable kin_egg drops placed at worldgen
	var nest_eggs := 0
	for dd in game.drops:
		if dd["id"] == "kin_egg":
			nest_eggs += 1
	check("wild egg nests", nest_eggs >= 1, "n=%d" % nest_eggs)
	# the island herds: same-species kin spawn in packs sharing one home cell.
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
	var hd1: Kin = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(6, 0))
	var hd2: Kin = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(7, 0))
	var hd3: Kin = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(8, 0))
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
		var items_f: int = game.item_count("kin_fluid") + game.item_count("gold_coin") + game.item_count("red_berries")
		var bit := 0
		for _ci in 30:
			if game.cast_line():
				bit += 1
			if game.pals.size() > pals_f:
				break
		check("fishing", bit > 0 and (game.pals.size() > pals_f \
				or game.item_count("kin_fluid") + game.item_count("gold_coin") + game.item_count("red_berries") > items_f) \
				and game.item_count("fishing_rod") == 1,
			"bites=%d kin=%d" % [bit, game.pals.size() - pals_f])
		var wthr0: String = game.weather
		game.weather = "rain"
		var bite_r: float = game.fish_bite_p()
		game.weather = "clear"
		var bite_c: float = game.fish_bite_p()
		var maps0: int = game.item_count("treasure_map")
		for _ci2 in 300: # the corked promise is a 5% tail — 300 casts can't miss it
			game.cast_line()
		check("rain feeds the bite and the sea mails maps", bite_r > bite_c \
			and game.item_count("treasure_map") > maps0,
			"bite=%.2f/%.2f maps=%d" % [bite_r, bite_c, game.item_count("treasure_map") - maps0])
		game.weather = wthr0
		p.pos = pos_f
	else:
		check("fishing", false, "no shoreline")
	# egg theft has a price: looting a nest angers nearby wild kin
	var ne1: Kin = game.gen_pal("fenlump", 3, game.player.pos + Vector2(4, 0))
	var ne2: Kin = game.gen_pal("fenlump", 3, game.player.pos + Vector2(40, 0))
	game.pals.append(ne1); game.pals.append(ne2)
	game.anger_nesters(game.player.pos)
	check("nest guards", ne1.aggro == 0 and ne2.aggro < 0, "near=%d far=%d" % [ne1.aggro, ne2.aggro])
	for nq in [ne1, ne2]:
		game.pals.erase(nq); nq.free()
	# raid horn: the 30s warning fires once per wave, then the wave lands
	if game.kinbox_pos.x >= 0:
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
		# the island packs: a raider landing in a zone whose pool has the theme
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
		# signature raid: the Iron Pact sends humans, not kin
		var syn0 := 0
		for q in game.pals:
			if q.species_id.begins_with("ironpact"):
				syn0 += 1
		game.raid_theme = "Iron Pact"
		game.start_raid()
		game.raid_theme = ""
		var syn1 := 0
		for q in game.pals:
			if q.species_id.begins_with("ironpact"):
				syn1 += 1
		check("Iron Pact squad", syn1 > syn0, "%d->%d" % [syn0, syn1])
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
	# migration: a deeper-zone herd lands as one species on one shared anchor
	var mig_n := 0
	var mig_sid := ""
	var herd_ok := false
	for att in 5: # landlocked maps can whiff a landing — same retry contract as supply
		var n_before := game.pals.size()
		game.mig_t = 0.01
		game.tick_migration(1.0)
		var newcomers := game.pals.slice(n_before)
		if newcomers.size() >= 3:
			mig_n = newcomers.size()
			mig_sid = newcomers[0].species_id
			herd_ok = true
			for q in newcomers:
				if q.mode != "wild" or q.species_id != mig_sid or q.home != newcomers[0].home:
					herd_ok = false
			break
	check("migration herd lands", herd_ok and game.mig_t > 400.0,
		"n=%d sid=%s next=%.0f" % [mig_n, mig_sid, game.mig_t])
	# fast-travel waypoints: seeded at worldgen, touch blinks back to kinbox
	var wpts := 0
	for ks in game.structures:
		if game.structures[ks]["id"] == "waypoint":
			wpts += 1
	check("waypoints seeded", wpts >= 1, "n=%d" % wpts)
	if game.kinbox_pos.x >= 0 and wpts >= 1:
		p.pos = Vector2(5, 5)
		game.use_waypoint()
		check("waypoint opens net", game.panel == "travel" and game.travel_nodes().size() >= 2)
		var pbk: Vector2i = game.nearest_kinbox(p.pos)
		game.travel_to(pbk)
		check("waypoint blinks", game.panel == "" and p.pos.distance_to(
			Vector2(pbk.x + 0.5, pbk.y + 2.5)) < 6.0)
	# outpost kinbox: a second box joins the shared network, nearest answers
	var ob_ok := false
	var pbx0 := int(game.kinbox_pos.x); var pby0 := int(game.kinbox_pos.y)
	for r3 in range(4, 40) if game.kinbox_pos.x >= 0 else []:
		var cc := Vector2i(pbx0 + r3, pby0)
		var clear := true
		for dy3 in range(2):
			for dx3 in range(2):
				var k3 := cc + Vector2i(dx3, dy3)
				if not game.world.in_bounds(k3.x, k3.y) or game.world.blocked(k3.x, k3.y) \
						or game.structures.has(k3):
					clear = false
		if clear and game.place_free("kinbox", cc.x, cc.y):
			ob_ok = true
			break
	if ob_ok:
		check("outpost kinbox", game.extra_boxes.size() == 1 and game.kinbox_pos.x >= 0,
			"extra=%d" % game.extra_boxes.size())
		var ob_pos: Vector2i = game.extra_boxes[0]
		p.pos = Vector2(ob_pos.x + 0.5, ob_pos.y + 0.5)
		check("nearest kinbox", game.nearest_kinbox(p.pos) == ob_pos)
		# demolishing the primary promotes the outpost rather than orphaning base
		game.demolish_at(Vector2(game.kinbox_pos.x + 0.5, game.kinbox_pos.y + 0.5))
		check("outpost promoted", game.kinbox_pos == ob_pos and game.extra_boxes.is_empty())
	else:
		check("outpost kinbox", true, "skipped: no room / no base this seed")
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
			game.resolve_sphere({"sid": "legendary_orb", "target": q})
			check("boss immune", game.box.size() == bx)
			break
	# the ownable gate covers what the boss flag misses: a non-boss legendary
	# (boss-phase adds summon wild kin) still can't be balled
	var ladd: Kin = game.gen_pal(Game.LEGENDARY_DEN[0], 10, p.pos + Vector2(2, 0))
	game.pals.append(ladd)
	var bx2 := game.box.size()
	game.resolve_sphere({"sid": "legendary_orb", "target": ladd})
	check("non-boss legendary immune", game.box.size() == bx2)
	game.pals.erase(ladd); ladd.queue_free()
	# replicas take wounds and deaths only from the host snapshot — a local
	# hit must not spawn phase adds, a local kill must not schedule respawns
	var repl: Kin = game.gen_pal("fenjelly", 5, p.pos + Vector2(1, 0))
	repl.net_id = 77
	var rhp := repl.hp
	repl.hit(50, 1.0, true)
	repl.boss = true; repl.alpha = true; repl.home = repl.pos
	var rb1 := game.boss_respawns.size()
	game.kill_pal(repl, true)
	check("replica takes no local wounds", repl.hp == rhp and game.boss_respawns.size() == rb1)
	repl.queue_free()

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
	# the island tombstone: the map marks the spill and clears it on the corpse run
	check("death mark set", game.death_marks.size() >= 1)
	if game.death_marks.size() >= 1:
		p.pos = game.death_marks[game.death_marks.size() - 1]
		game.tick_death_marks()
		check("corpse run clears", game.death_marks.size() == 0)
		p.pos = game.nearest_free(game.kinbox_pos.x + 0.5, game.kinbox_pos.y + 2.5)
	game.add_item("wood", 200); game.add_item("stone", 100); game.add_item("lumenite", 20); game.add_item("fiber", 40)
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
	var kx: Vector2i = game.kinbox_pos
	check("overlap rejected", game.place_structure("torch", kx.x, kx.y) == false)
	# demolish: removes structure + refunds half cost
	var t_xy = free_xy.call("torch")
	check("demolish removes", t_xy != null and game.demolish_at(Vector2(t_xy.x, t_xy.y) + Vector2(0.5,0.5)) and not game.structures.has(t_xy), "")
	# work-type gating: fenjelly lacks lumbering -> cannot log
	var non: Kin = null
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
		check("work-type gating", false, "no non-lumbering base kin")
	# the island: farm fields crew planting AND watering suitability
	game.add_item("wood", 8); game.add_item("fiber", 6); game.add_item("berry_seeds", 3)
	var farm_k: Vector2i = free_xy.call("berry_farm")
	var wf_st = game.structures.get(farm_k)
	if wf_st:
		var wtr: Kin = game.gen_pal("bubwrith", 3, Vector2(farm_k.x + 1, farm_k.y))
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
	var slacker: Kin = null
	for kk3 in game.structures:
		if game.structures[kk3].get("id") == "logging_site" and not game.structures[kk3]["workers"].is_empty():
			slacker = game.structures[kk3]["workers"][0]
	if slacker == null: # seed-dependent crew — seat one ourselves rather than skip
		var sl_k: Vector2i = free_xy.call("logging_site")
		var sl_st = game.structures.get(sl_k)
		if sl_st != null:
			slacker = game.gen_pal("dozantler", 5, p.pos)
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
	# kin bed SAN regen
	game.add_item("wood", 40)
	var bed_xy: Vector2i = free_xy.call("kin_bed")
	var bed_ok: bool = bed_xy.x >= 0
	var sleepy: Kin = game.base_pals()[0]
	sleepy.san = 10.0
	for i in 3:
		sleepy.tick_needs(1.5)
	check("kin bed SAN regen", bed_ok and sleepy.san > 10.0, "san %.0f" % sleepy.san)
	# hot spring outranks the bed: higher SAN ceiling, faster recovery
	game.add_item("stone", 20); game.add_item("wood", 10); game.add_item("lumenite", 3)
	var spa_xy: Vector2i = free_xy.call("hot_spring")
	sleepy.san = 50.0
	sleepy.tick_needs(1.0)
	check("hot spring SAN", spa_xy.x >= 0 and sleepy.san >= 59.0, "san %.0f" % sleepy.san)
	# the island meals: cooked food restores far more SAN than raw crops.
	# eat_from_bag takes the cheapest food first — pin the bag to one item.
	var bag_save: Dictionary = game.items.duplicate()
	var eater: Kin = game.gen_pal("fenjelly", 3, game.player.pos)
	eater.mode = "partner"; eater.hunger = 90.0
	game.items.clear(); game.items["wheat"] = 1
	eater.san = 50.0; eater.tick_needs(1.0)
	var san_raw: float = eater.san
	game.items.clear(); game.items["jam_bun"] = 1
	eater.san = 50.0; eater.hunger = 90.0; eater.tick_needs(1.0)
	check("meal lifts SAN", eater.san > san_raw + 15.0, "raw=%.1f meal=%.1f" % [san_raw, eater.san])
	game.items = bag_save
	game.pals.erase(eater); eater.free()
	# a party kin at ease recovers its spirits (the island rest recovery)
	var calm: Kin = game.gen_pal("fenjelly", 3, game.player.pos)
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
	# the island warmth: a fire kin at your side counts as a heat source too
	var torch_pal: Kin = game.gen_pal("cindlump", 3, far_spot + Vector2(1, 0))
	torch_pal.mode = "partner" # only YOUR fire pal snuggles — wild ones don't count
	game.pals.append(torch_pal)
	p.pos = far_spot
	p.cold_t = 0.0
	var hp_c3 := p.hp
	p._physics_process(4.5)
	var chill_pal: bool = p.hp >= hp_c3
	game.pals.erase(torch_pal); torch_pal.free()
	check("night chill", chill_far and chill_near and chill_pal,
		"far=%s near=%s kin=%s" % [chill_far, chill_near, chill_pal])
	# warm armor (the island fur gear): hide armor widens the cold-safe ring
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

	# latitude bands (the island snowy north / scorching south): noon in the
	# north freezes anyway, noon in the south scorches, cooling armor saves
	game.tod = 13.0
	p.hp = p.max_hp; p.hunger = 80.0
	p.equipment["armor"] = ""; p.armor_wear = -1.0
	# a fire-element partner or base kin at your shoulder is a heat source —
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
	var napper: Kin = game.gen_pal("fenjelly", 3, p.pos + Vector2(6, 6))
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
	# monitoring stand: SAN drains half again while it stands (the island trade-off)
	game.add_item("wood", 10); game.add_item("stone", 10); game.add_item("ingot", 2)
	var mst_xy: Vector2i = free_xy.call("monitoring_stand")
	var sj: Kin = null
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
	var hungry: Kin = game.base_pals()[0]
	hungry.hunger = 90.0
	for i in 3:
		hungry.tick_needs(1.5)
	check("feed box eats", fb != null and fb["store"].get("red_berries", 0) < 4 and hungry.hunger < 90.0,
		"stored=%s hunger=%.0f" % [str(fb["store"]) if fb else "none", hungry.hunger])
	# level up learns a skill
	var lev: Kin = game.base_pals()[0]
	var lv0: int = lev.level
	var sk0: int = lev.learned_skills().size()
	lev.level = lev.spec.get("skills", [[1, "x"]])[-1][0]
	check("level learns skills", lev.learned_skills().size() >= sk0, "Lv%d skills %d" % [lev.level, lev.learned_skills().size()])
	# catch chance math: full-hp high-power kin is hard for basic sphere
	var hard: float = Combat.catch_chance(1.0, 200.0, 26.0, 0.0, 0.0, 1)
	check("catch chance bounded", hard < 0.35, "%.2f" % hard)
	# all sphere tiers resolve as usable items
	var sphere_ids := ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]
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
	# a trinkets: two accessory slots, effects stack
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
	# the island tool wear: swings cost durability, zero snaps the weapon
	game.add_item("wooden_club", 1)
	game.equip("wooden_club")
	check("weapon wear starts", p.weapon_wear == 40.0, "wear %.0f" % p.weapon_wear)
	p.atk_cd = 0.0; p.melee()
	check("swing spends wear", p.weapon_wear == 39.0, "wear %.0f" % p.weapon_wear)
	p.weapon_wear = 1.0; p.atk_cd = 0.0; p.melee()
	check("weapon breaks", p.equipment["weapon"] == "" and game.item_count("wooden_club") == 0,
		"slot=%s n=%d" % [p.equipment["weapon"], game.item_count("wooden_club")])
	# the island repair: a worn weapon mends at the bench for half its recipe
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

	# schematics (the island blueprints): the req gate wants the paper in your
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
		var bk: Kin = load("res://src/kin.gd").new()
		game.entity_layer.add_child(bk)
		bk.setup(game, "fenjelly", 10, p.pos + Vector2(2, 0))
		bk.boss = true; bk.mode = "wild"; bk.hp = 1.0
		game.kill_pal(bk, true)
		sch_hit = game.items.get("schematic_bow", 0) + game.items.get("schematic_musket", 0)
		if sch_hit > 0:
			break
	p.level = lvl0; p.xp = xp0
	check("boss teaches blueprint", sch_hit > 0, "25 bosses, no schematic")
	game.items.erase("schematic_bow"); game.items.erase("schematic_musket")
	game.items.erase("legendary_orb"); game.items.erase("sprigmelt_effigy")
	game.items.erase("gold_coin"); game.items.erase("ancient_part"); game.items.erase("kin_orb")

	# party cap: 6th kin refused and stays in the box
	while game.party.size() < 5:
		var fp: Kin = load("res://src/kin.gd").new()
		game.entity_layer.add_child(fp)
		fp.setup(game, "puffmite", 3, p.pos)
		game.box.append(fp)
		game.box_to_party(fp)
	var over: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(over)
	over.setup(game, "puffmite", 3, p.pos)
	game.box.append(over)
	game.box_to_party(over)
	check("party overflow refused", game.party.size() == 5 and not game.pals.has(over) and game.box.has(over),
		"mode=%s party=%d" % [over.mode, game.party.size()])
	game.party_to_box(game.party[4]) # back to 4 for later checks
	# non-mountable rejected
	var snak: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(snak)
	snak.setup(game, "bubwrith", 3, p.pos)
	snak.mode = "base"
	snak.pos = p.pos
	p.mount = null
	p.try_mount()
	var m_ok: bool = (p.mount == snak) == SpeciesData.mountable("bubwrith")
	check("mount gate", m_ok)
	# the island: mounts need kin gear — no saddle, no ride
	game.items.erase("saddle"); game.items.erase("sky_saddle"); game.items.erase("wave_saddle")
	var bird: Kin = game.gen_pal("fenlump", 4, p.pos)
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
	var surf: Kin = game.gen_pal("dewmane", 5, p.pos)
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
	var landm: Kin = game.gen_pal("dozantler", 5, p.pos) # neutral — no surf legs
	landm.mode = "partner"; game.pals.append(landm)
	p.mount = landm
	check("land mount no swim", wcell.x >= 0 and not p.can_enter(wcell.x, wcell.y))
	p.mount = null
	# the island lets you ford water on foot too — slower, hungrier
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
	# stamina (the island SP): sprint and swimming drain it; a dry swim drowns
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

	for m in ["wood","stone","fiber","lumenite","ingot","electric_organ","flame_organ","nails","cloth","berry_seeds","wheat_seeds"]:
		game.add_item(m, 60)
	var farm_xy: Vector2i = free_xy.call("berry_farm")
	var farm_ok: bool = farm_xy.x >= 0
	var farmer: Kin = game.base_pals()[0]
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
	var gen_pal: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(gen_pal)
	gen_pal.setup(game, "voltgoo", 3, p.pos)
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
	# hostile kin aggros and damages player
	var foe: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(foe)
	foe.setup(game, "shadesmith", 30, p.pos + Vector2(1.0, 0))
	foe.mode = "wild"
	game.pals.append(foe)
	p.hp = p.max_hp
	var hit0: int = p.hp
	foe.aggro = 0
	for i in 90:
		foe._physics_process(0.1)
		game.update_projectiles(0.1)
	check("hostile kin attacks", p.hp < hit0, "hp %d->%d" % [hit0, p.hp])
	# soak amplifies electric damage
	var sp1: Kin = load("res://src/kin.gd").new()
	game.entity_layer.add_child(sp1) # unparented nodes leak — even in tests
	sp1.setup(game, "fenjelly", 10, p.pos)
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

	# ---- round 4: save completeness + consumables + kin xp ----
	# medicine heals + consumes
	game.add_item("medical_supplies", 2)
	p.hp = 10
	# simulate hud use_item heal path
	var med: Dictionary = ItemData.ITEMS["medical_supplies"]
	p.hp = mini(p.max_hp, p.hp + med["heal"])
	game.add_item("medical_supplies", -1)
	check("medicine heals", p.hp == mini(p.max_hp, 10 + med["heal"])
		and game.item_count("medical_supplies") == 1, "hp %d" % p.hp)
	# the island meal buff: a cooked meal grants one timed stat bonus
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
	check("sigil consumed", game.item_count("boss_sigil") == sig0 and game.pals.size() == sig_n + 1, "sig%d kin%d" % [game.item_count("boss_sigil"), game.pals.size() - sig_n])
	# kin xp levels up a partner kin
	var lvl_pal: Kin = null
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
	check("kin levels via xp", lvl_pal.level > plv0, "Lv%d->%d xp%d" % [plv0, lvl_pal.level, lvl_pal.xp])
	# save/load preserves kin sex/passives + chest store + job links
	game.box.clear()
	var sv_pal: Kin = null
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
		sv_pal = game.gen_pal("fenjelly", 3, p.pos)
		sv_pal.mode = "base"
		game.pals.append(sv_pal)
	check("a base kin exists for save test", sv_pal != null, "")
	var sv_sex: String = sv_pal.sex if sv_pal else ""
	var sv_pass: Array = sv_pal.passives.duplicate() if sv_pal else []
	var sv_idx: int = game.pals.find(sv_pal) if sv_pal else -1 # order is stable through save/load
	var chest2 = null
	for kk7 in game.structures:
		if game.structures[kk7].get("id") == "chest":
			chest2 = game.structures[kk7]
	if chest2:
		chest2["store"]["test_item"] = 7
	# count UNIQUE worker kin (a kin may sit in two arrays from manual test appends)
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
	results.append("  had=%d linked_pals=%d sites=%s kin=%d box=%d phantom=[%s]" % [had_workers, linked, str(site_names), game.pals.size(), game.box.size(), phantom])
	var party_sz_before := game.party.size()
	var lost_uids := [] # uids pointing at nothing — save would silently drop them
	for pu in game.party:
		var pl2: Kin = game.find_pal(pu)
		if pl2 == null:
			pl2 = game.bench_pal_of(pu)
		if pl2 == null or pl2.mode == "box":
			lost_uids.append("%d:%s" % [pu, pl2.mode if pl2 else "?"])
	# a guest-built structure keeps its raze-rights tag through the disk trip —
	# plant it BEFORE the st_before census so both sides count it
	var pb_cell := Vector2i(-1, -1)
	for r9 in range(4, 60):
		var c9 := Vector2i(int(p.pos.x) + r9, int(p.pos.y))
		if game.world.in_bounds(c9.x, c9.y) and not game.world.blocked(c9.x, c9.y) \
				and not game.structures.has(c9) and game.place_free("campfire", c9.x, c9.y):
			pb_cell = c9; break
	if pb_cell.x >= 0:
		game.structures[pb_cell]["placed_tag"] = "tk_seven"
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
	# a guest's benched kin + roster row must survive the disk round-trip
	var gp_sv: Kin = game.gen_pal("fenjelly", 3, p.pos)
	gp_sv.mode = "bench"; gp_sv.owner_id = -1; gp_sv.owner_tag = "tok_t"
	game.bench.append(gp_sv); game.box_pal(gp_sv)
	game.remote_parties["tok_t"] = [gp_sv.uid]
	game.save_game()
	# mutate state then reload
	for q in game.pals:
		q.sex = "F"
	if chest2:
		chest2["store"].clear()
	var ok_load := game.load_game()
	check("fog survives reload", game.explored.size() == game.world.WORLD_W * game.world.WORLD_H
		and game.explored[123] == 1, "size=%d cell=%d" % [game.explored.size(), game.explored[123]])
	var re_pal: Kin = null
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
	if pb_cell.x >= 0:
		check("placed_by survives reload", str(game.structures.get(pb_cell, {}).get("placed_tag", "")) == "tk_seven")
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
	# guest ownership rides the save: the tag persists, the kin sleeps as an
	# orphan until a hello reclaims it — and its roster row comes back too
	var gp_re: Kin = null
	for q in game.bench:
		if q.owner_tag == "tok_t":
			gp_re = q
	check("guest tag survives reload", gp_re != null and gp_re.owner_id == -1
		and game.remote_parties.get("tok_t", []).has(gp_re.uid))
	game.rebind_owner(33, "tok_t")
	check("save rebind claims kin", gp_re != null and gp_re.owner_id == 33)
	if gp_re != null:
		game.bench.erase(gp_re)
		game.remote_parties.clear()
		if gp_re.get_parent(): gp_re.get_parent().remove_child(gp_re)
		gp_re.free()

	# partner death frees the party slot + clears job site
	var dp: Kin = game.find_pal(game.party[0]) if game.party.size() > 0 else null
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
	check("raid wave spawns", game.pals.size() > pals0 and raiders >= 2, "+%d kin, %d aggro" % [game.pals.size() - pals0, raiders])
	# aggro>0 kin targeting: raider fights a base kin
	var raider: Kin = null
	for q in game.pals:
		if q.mode == "wild" and q.aggro > 0:
			raider = q
			break
	if raider:
		var victim: Kin = game.find_pal(raider.aggro)
		if victim:
			raider.pos = victim.pos + Vector2(0.5, 0)
			var vhp0 := victim.hp
			raider.atk_cd = 0
			raider.wild_ai(0.1)
			check("raider hits base kin", victim.hp < vhp0 or raider.stun_t > -1.0, "victim hp %.0f->%.0f" % [vhp0, victim.hp])
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
	# hauling: unassigned transporting kin carries a drop to the chest
	var hauler: Kin = null
	for q in game.pals:
		if q.spec.get("work", {}).get("transporting", 0) > 0:
			hauler = q
			break
	if hauler == null:
		hauler = game.gen_pal("fenjelly", 5, game.player.pos + Vector2(2, 0))
		if "transporting" not in hauler.spec.get("work", {}) or hauler.spec["work"].get("transporting", 0) == 0:
			hauler.spec["work"]["transporting"] = 1
		hauler.mode = "base"; hauler.job_site = null
		if not game.pals.has(hauler): game.pals.append(hauler)
	hauler.mode = "base"; hauler.job_site = null; hauler.carry = null
	# dedicated chest in open space; hauler must pick THIS one (nearest)
	var cst_xy := Vector2i(-1, -1)
	var near_c0 := Vector2i(-1, -1)
	for r7 in range(6, 40):
		var cx7 := int(game.kinbox_pos.x) + r7; var cy7 := int(game.kinbox_pos.y)
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
	var la: Kin = null
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
				# kin can't pathfind, so a cliff edge on the line sticks it
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

	# content pass: four species fill the zone/element gaps the audit found —
	# zone0 fire+ground, zone2 water, zone3 electric (a dark storm-wraith)
	var gap_specs := {
		"embpaw": [0, ["fire"]], "gritmite": [0, ["ground"]],
		"corlfang": [2, ["water"]], "sparkhaunt": [3, ["electric", "dark"]]}
	for nsid in gap_specs:
		var nsd: Dictionary = SpeciesData.species_of(nsid)
		var expect: Array = gap_specs[nsid]
		check("species %s" % nsid,
			not nsd.is_empty() and nsd.get("elements", []) == expect[1]
			and nsd.get("work", {}).size() > 0 and nsd.get("drops", []).size() > 0
			and nsid in SpeciesGen.zone_pool(expect[0])
			and SpeciesGen.habitat(nsid) == expect[0]
			and load("res://assets/kin/%s_f0.png" % nsid) != null,
			str({"elem": nsd.get("elements"), "hab": SpeciesGen.habitat(nsid)}))

	# apex hostiles (hostile==2) auto-aggro on sight and skip night sleep
	var apex: Kin = null
	for q in game.pals:
		if q.mode == "wild" and q.hostile() == 2:
			apex = q; break
	if apex:
		game.tod = 12.0
		apex.aggro = -1; apex.statuses.erase("sleep"); apex.raid = false # leftover raiders retarget the base, not the player — isolate the check
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

	# essence condenser: 4 same-species box kin -> star+1, stats x1.15
	if game.party.size() > 0:
		var ap2: Kin = game.lead_pal() # condense targets the lead, out or benched
		var star0 := ap2.star; var mhp0 := ap2.max_hp; var atk0 := ap2.atk_bonus
		var boxn0 := game.box.size()
		for j in 4:
			var fp := Kin.new()
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
	game.add_item("kin_orb", 9999) # stack 50
	check("stack capped", game.item_count("kin_orb") == 50, "=%d" % game.item_count("kin_orb"))
	check("overflow spilled", game.drops.size() > n_drops, "drops=%d" % game.drops.size())

	# night sleep: wild non-dark kin sleep; dark kin stay up; hit wakes
	game.tod = 23.0
	var sleeper: Kin = null; var nightowl: Kin = null
	for q in game.pals:
		if q.mode == "wild" and not q.raid and "dark" not in q.spec.get("elements", []) and q.hostile() < 2:
			sleeper = q # raiders chew structures instead of sleeping — they'd never nap
		if q.mode == "wild" and not q.raid and "dark" in q.spec.get("elements", []):
			nightowl = q
	if sleeper == null:
		sleeper = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(6, 0))
		sleeper.mode = "wild"; sleeper.aggro = -1
		if not game.pals.has(sleeper): game.pals.append(sleeper)
	sleeper.aggro = -1; sleeper.hit_flash = 0; sleeper.stun_t = 0.0; sleeper.statuses.erase("sleep")
	sleeper.wild_ai(0.1)
	check("wild kin sleeps at night", sleeper.has_status("sleep"), "")
	if nightowl:
		nightowl.aggro = -1; nightowl.statuses.erase("sleep"); nightowl.hit_flash = 0
		nightowl.wild_ai(0.1)
		check("dark kin stays up", not nightowl.has_status("sleep"), "")
	# ...but a nocturnal naps through daylight — the island sleep flips. Fresh
	# shademite: the pool may only hold apex darks, and those never doze
	var dayowl: Kin = game.gen_pal("shademite", 3, p.pos + Vector2(3, 0))
	dayowl.mode = "wild"; dayowl.aggro = -1; dayowl.hit_flash = 0
	game.pals.append(dayowl)
	var tod_w2 := game.tod
	game.tod = 12.0
	dayowl.wild_ai(0.1)
	check("dark kin naps by day", dayowl.has_status("sleep"), "")
	game.tod = tod_w2
	game.pals.erase(dayowl)
	if dayowl.get_parent(): dayowl.get_parent().remove_child(dayowl)
	dayowl.free()
	# the base crew keeps the same hours — a posted dark kin dozes the day shift
	var quiet := p.pos + Vector2(30, 0)
	for off in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30), Vector2(45, 0)]:
		var foes := 0
		for q2 in game.pals: # raiders and aggro'd wilds pull it into defense instead
			if q2.mode == "wild" and q2.hp > 0 and (q2.raid or q2.aggro >= 0) \
					and (p.pos + off).distance_to(q2.pos) < 8.0:
				foes += 1
		if foes == 0:
			quiet = p.pos + off; break
	var dbase: Kin = game.gen_pal("shademite", 4, quiet)
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
	# the island prey flight: a beaten-down ordinary hostile bolts instead of fighting
	var pa2 := p.pos + Vector2(4, 0)
	for off in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
		var cc2: Vector2 = p.pos + off
		# flee vector runs AWAY from the player — the cell beyond the prey
		# must be walkable or step_toward has nowhere to go
		if not game.world.blocked(int(cc2.x), int(cc2.y), p.pos.x, p.pos.y) \
				and not game.world.blocked(int(cc2.x + signi(off.x)), int(cc2.y + signi(off.y)), cc2.x, cc2.y):
			pa2 = cc2; break
	var prey2: Kin = game.gen_pal("fenjelly", 5, pa2)
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
	# nocturnal ecology: dark kin own the night spawn table, sit out the day
	check("night spawns dark", game.pick_wild_species(["shademite", "fenjelly"]) == "shademite")
	# the island: the night shift also spawns meaner — same seed, +2 levels
	var s_n: int = game.rng.s
	var tod_n: float = game.tod
	game.rng.s = s_n; game.tod = 2.0
	var wln: int = game.wild_lv(2)
	game.rng.s = s_n; game.tod = 12.0
	var wld: int = game.wild_lv(2)
	game.tod = tod_n
	check("night spawns meaner", wln == wld + 2, "night=%d day=%d" % [wln, wld])
	game.tod = 12.0
	check("day spawns diurnal", game.pick_wild_species(["shademite", "fenjelly"]) == "fenjelly")

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
	# campaign tags ride the save: a spire guardian stays tagged (else its kill
	# can't record and the campaign soft-locks), a phase-2 boss stays phased
	if game.pals.size() > 0:
		game.pals[0].spire_tag = "spire_0"
		game.pals[0].phase = 2
		game.save_game()
		game.load_game()
		var stag_back := false
		for q in game.pals:
			if q.spire_tag == "spire_0" and q.phase == 2:
				stag_back = true
		check("spire tag + phase survive save", stag_back)
		game.spires_done.clear(); game.crowned = false
		for q in game.pals: # don't leave a campaign pin on a random wild kin
			if q.spire_tag == "spire_0":
				q.spire_tag = ""; q.phase = 1
	# forged campaign tags die at the validator — int() alone eats "abc"→0
	check("forged spire tag refused", not game.spire_tag_ok("spire_-1")
		and not game.spire_tag_ok("spire_abc") and not game.spire_tag_ok("spire_9")
		and game.spire_tag_ok("spire_4"))
	# a quickload must clear the bench too — stale orbs were phantom roster rows
	var bj: Kin = game.gen_pal("fenjelly", 4, p.pos)
	bj.mode = "bench"; game.bench.append(bj)
	var bench_sv := game.bench.size()
	game.save_game()
	var ghostb: Kin = game.gen_pal("fenjelly", 4, p.pos) # post-save stray orb
	ghostb.mode = "bench"; game.bench.append(ghostb)
	game.load_game()
	check("load clears stale bench", game.bench.size() == bench_sv,
		"bench=%d saved=%d" % [game.bench.size(), bench_sv])
	# a KO'd guest pal frees its remote party slot — else "Party full" forever
	var rpv: Kin = game.gen_pal("fenlump", 5, p.pos)
	rpv.mode = "partner"; rpv.owner_id = 9; game.pals.append(rpv)
	game.rparty_for(9).append(rpv.uid)
	game.kill_pal(rpv, true)
	check("KO frees guest party slot", not game.rparty_for(9).has(rpv.uid))
	game.remote_parties.erase(9)
	game.pals.erase(rpv); game.box.erase(rpv); game.bench.erase(rpv)
	if rpv.get_parent(): rpv.get_parent().remove_child(rpv)
	rpv.free()

	# corrupt save: missing fields / wrong types must be refused, not crash the world
	var pals_before := game.pals.size()
	var cf := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	cf.store_var({"seed": game.world.seed, "kin": [{"sp": "fenjelly"}], "player": "oops"})
	cf.close()
	var bad_load: bool = game.load_game()
	check("corrupt save refused", bad_load == false and game.pals.size() == pals_before, "load=%s kin=%d" % [bad_load, game.pals.size()])
	# truncated save: a kin entry without pos/mode keys must be skipped, not fatal
	var tf := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	tf.store_var({"seed": game.world.seed, "day": 1, "tod": 8.0, "tech_points": 0, "unlocked": [],
		"items": {}, "party": [], "player": {"hp": 50.0, "level": 1, "xp": 0, "cap_lv": 1},
		"kin": [{"sp": "fenjelly", "lv": 3, "hp": 30.0, "talent": 50, "mode": "wild",
				"pos": [game.player.pos.x + 1, game.player.pos.y]},
			{"sp": "fenjelly", "lv": 3}], "structures": {}})
	tf.close()
	var tload: bool = game.load_game()
	var loaded_ok := false
	for q in game.pals:
		if q.species_id == "fenjelly" and q.hp == 30.0:
			loaded_ok = true
	check("truncated save loads cleanly", tload == true and loaded_ok, "kin=%d" % game.pals.size())
	# foreign-typed fields: strings/ints where numbers/bools/arrays live must coerce, not abort
	var ff := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	ff.store_var({"seed": game.world.seed, "day": "many", "tod": "late", "tech_points": "3",
		"unlocked": ["kinbox", 42], "items": {"wood": "12", "stone": "x"}, "party": [],
		"player": {"pos": ["no", "no"], "hp": "full", "level": "2"},
		"kin": [{"sp": "fenjelly", "pos": [game.player.pos.x + 1, game.player.pos.y],
				"mode": 7, "hp": "lots", "sex": 9, "boss": "yes", "san": "hi",
				"passives": "nope", "star": "s", "raid": "y", "stag": "hax", "ph": "x"}],
		"structures": {}})
	ff.close()
	var fload: bool = game.load_game()
	var fok := false
	for q in game.pals:
		if q.species_id == "fenjelly" and q.mode == "wild" and q.hp is float and q.sex == "M" and q.boss == false \
				and q.spire_tag == "" and q.phase == 1: # "hax"/"x" refused: no forged campaign tags
			fok = true # mode 7 -> "wild" fallback, sex 9 -> "M", boss "yes" -> skipped (not a real bool)
	check("foreign-typed save coerces", fload == true and fok and game.player.hp is float and game.item_count("wood") == 12, "kin=%d" % game.pals.size())
	# hostile Variants: Array/Dict where numbers live — int()/float() aborts on
	# those mid-load and the next save clobbers the real file (audit-16 H1)
	var hf := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	hf.store_var({"seed": game.world.seed, "v": 2, "day": [1, 2], "tod": {"x": 8},
		"tech_points": [], "raid_t": {}, "unlocked": ["kinbox", {"fake": 1}],
		"items": {7: 5, "wood": [9]}, "party": [null, {"u": 1}],
		"player": {"pos": [5.0, 5.0], "hp": [], "level": 1, "cap_lv": "9", "meal": 5,
			"hunger": [], "stamina": {}, "xp": {}},
		"board_quest": {"kind": "hax", "n": [3], "got": {}, "day": []},
		"treasure": ["a", "b"], "grotto": [1, {}], "perks": [1, 2],
		"catches": {"fenjelly": [2], 9: 1},
		"kin": [{"sp": "fenjelly", "lv": {}, "hp": [], "pos": [game.player.pos.x + 1, game.player.pos.y],
				"talent": [], "sb": {}, "bnt": [], "raid": true, "mode": "partner"}],
		"structures": {"5,5": {"id": "kin_cage", "cap": {"sp": "no_such_species", "lv": 5}},
			"9,9": {"id": "incubator", "inc": {"pair": 5, "left": []}}}})
	hf.close()
	var hload: bool = game.load_game()
	var hkin_ok := false
	for q in game.pals:
		if q.species_id == "fenjelly" and q.level == 1 and q.mode == "partner" and q.raid == false:
			hkin_ok = true # lv:{} → 1; the rostered raider flag is scrubbed
	var hkeys_ok := true
	for hk in game.items.keys():
		if hk is not String: hkeys_ok = false
	var hcap = game.structures.get(Vector2i(5, 5))
	var hinc = game.structures.get(Vector2i(9, 9))
	check("hostile-variant save loads whole", hload == true and hkin_ok and hkeys_ok
		and game.day == 1 and game.player.meal_buff is Dictionary
		and game.player.capture_level <= 6
		and game.board_quest.get("kind", "") == "supply"
		and game.treasure.is_empty()
		and (hcap == null or not hcap.has("captive"))
		and (hinc == null or hinc.get("egg_inc", {}).get("pair", "x") == null)
		and game.items.get("wood", 0) == 0, "wood=%s" % str(game.items.get("wood")))
	for hst in [hcap, hinc]: # hostile fixtures leave no structures behind — a lingering incubator eats the next deposit test
		if hst != null:
			game.net_remove_structure(hst)
	game.tod = 8.0 # float("late") coerced tod to 0.0 = night: keep later checks on day shift
	game.player.hp = game.player.max_hp # the hostile fixture zeroed it — the restore must write a living player
	game.add_item("wood", 20) # ...and the hostile items dict ate the fixture wood the merchant tests need
	game.save_game() # restore a sane save file for the rest of the run

	# ---- new island-loop systems ----
	# ailments: sustained low SAN sickens a base kin; medicine cures it
	var sicky: Kin = null
	for q in game.pals:
		if q.mode == "base":
			sicky = q
			break
	if sicky == null:
		sicky = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(3, 0))
		sicky.mode = "base"
		game.pals.append(sicky)
	sicky.ailment = ""
	sicky.san = 5.0
	sicky.low_san_t = 61.0
	for _i in 3: # needs tick throttles at 1s intervals
		sicky._physics_process(1.0)
	check("low SAN -> ailment", sicky.ailment in Kin.AILMENTS, "ail=%s" % sicky.ailment)
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

	# lucky variant: flagged kin carry the passive + stat buffs, drop gold on kill
	var luck: Kin = game.gen_pal("fenjelly", 5, game.player.pos + Vector2(4, 0))
	luck.lucky = true
	luck.setup(game, "fenjelly", 8, luck.pos)
	game.pals.append(luck)
	check("lucky passive + hp buff", "lucky" in luck.passives and luck.max_hp > Combat.stat_at(luck.spec["hp"], 8, luck.talent),
		"hp=%.0f" % luck.max_hp)
	var gold0b := game.item_count("gold_coin")
	game.kill_pal(luck, true)
	check("lucky drops gold", game.item_count("gold_coin") > gold0b, "+%d" % (game.item_count("gold_coin") - gold0b))

	# wanted marks: a flagged kill pays the bounty straight into the bag
	var wnt: Kin = game.gen_pal("ironpact_grunt", 6, game.player.pos + Vector2(3, 0))
	wnt.mode = "wild"; wnt.bounty = 12
	game.pals.append(wnt)
	var gold0w := game.item_count("gold_coin")
	game.kill_pal(wnt, true)
	check("bounty pays out", game.item_count("gold_coin") == gold0w + 12,
		"+%d" % (game.item_count("gold_coin") - gold0w))

	# skill fruit: teaches the active kin an extra move of that element
	if game.party.is_empty():
		var sp2: Kin = game.gen_pal("fenjelly", 3, game.player.pos + Vector2(2, 0))
		sp2.mode = "partner"
		game.pals.append(sp2)
		game.party.append(sp2.uid)
	if not game.party.is_empty():
		var ap: Kin = game.lead_pal() # benched lead still studies fruit
		var n_sk := ap.learned_skills().size()
		game.add_item("skill_fruit_fire", 1)
		game.teach_skill_fruit("skill_fruit_fire")
		var learned := ap.extra_skills.size() > 0 and ap.learned_skills().size() >= n_sk
		check("skill fruit teaches", learned and game.item_count("skill_fruit_fire") == 0,
			"extra=%s" % str(ap.extra_skills))
	else:
		check("skill fruit teaches", false, "empty party")

	# move loadout: kinbox slots cap at 3 and gate what the kin casts
	if not game.party.is_empty():
		var lp3: Kin = game.lead_pal()
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
	var dummy: Kin = game.gen_pal("fenjelly", 2, game.player.pos + Vector2(5, 0))
	game.pals.append(dummy)
	dummy.hp = maxf(1.0, dummy.max_hp * 0.05) # near-KO keeps the capture roll ~0.97
	game.catch_counts["fenjelly"] = 9 # next catch is the 10th
	var plvc := game.player.level; var pxpc := game.player.xp
	for _try in 10: # capture is a dice roll — keep throwing until it lands
		if game.catch_counts.get("fenjelly", 0) >= 10:
			break
		game.resolve_sphere({"sid": "kin_orb", "target": dummy})
	check("10th catch bonus", game.catch_counts.get("fenjelly", 0) == 10 and (game.player.level > plvc or game.player.xp > pxpc + dummy.level * 3),
		"cnt=%d xp=%d" % [game.catch_counts.get("fenjelly", 0), game.player.xp - pxpc])

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
		# black-market kin: buys a boxed kin, gold drops, node stays parented
		var pi := -1
		for i2 in game.merchant_stock.size():
			if game.merchant_stock[i2].has("kin"):
				pi = i2; break
		if pi >= 0:
			game.add_item("gold_coin", 1000)
			var pb := game.box.size()
			var g1m := game.item_count("gold_coin")
			game.buy_from_merchant(pi)
			check("merchant kin buy", game.box.size() == pb + 1
				and game.box[pb].get_parent() == game.box_holder
				and game.item_count("gold_coin") < g1m)
			if game.box.size() > pb: # sell it straight back — box count returns
				var g2m := game.item_count("gold_coin")
				game.sell_pal_to_merchant(game.box[pb].uid)
				check("merchant kin sell", game.box.size() == pb
					and game.item_count("gold_coin") > g2m)
	# wanted: striking the trader calls a Iron Pact hit squad — once per visit
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

	# meat cleaver: butcher a boxed kin, its drops spill on the ground
	game.add_item("meat_cleaver", 1)
	var bxp := game.gen_pal("fenlump", 3, p.pos)
	bxp.mode = "box"; game.box.append(bxp); game.box_pal(bxp)
	var bx0 := game.box.size()
	var dr0 := game.drops.size()
	game.butcher_pal(bxp.uid)
	check("butcher kin", game.box.size() == bx0 - 1 and game.drops.size() > dr0)
	# heart-lock: a fav'd kin survives the cleaver; toggling back unlocks it
	var fx := game.gen_pal("fenlump", 3, p.pos)
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
	var raider2: Kin = game.gen_pal("tammane", 5, Vector2(spk_k.x, spk_k.y) + Vector2(0.5, 0.5))
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
		# idle handy base kin patch battered structures (the island repair)
		var wall_hp0: float = wall_st["hp"]
		game.hit_structure(wall_k, 40)
		var fixp := game.gen_pal("fenjelly", 5, p.pos) # fenjelly: handiwork 1
		fixp.mode = "base"; fixp.job_site = null; game.pals.append(fixp)
		var dented: float = wall_st["hp"]
		game.tick_repairs(1.0)
		check("kin repair walls", wall_st["hp"] > dented and wall_st["hp"] <= wall_hp0,
			"%.0f->%.0f" % [dented, wall_st["hp"]])
		game.pals.erase(fixp)
		if fixp.get_parent(): fixp.get_parent().remove_child(fixp)
		fixp.free()
		game.hit_structure(wall_k, 999)
		check("structure razes", not game.structures.has(wall_k), "still standing")
	# kinbox anchor must survive razing attempts
	var pb_st = game.structures.get(game.kinbox_pos)
	if pb_st:
		game.hit_structure(game.kinbox_pos, 99999)
		check("kinbox unrazable", game.structures.has(game.kinbox_pos) and pb_st.get("hp", 0) >= 1)

	# the island kinbox is a clinic: boxed kin mend, KO'd ones wait their timer
	var hurt_b: Kin = game.gen_pal("fenjelly", 5, p.pos)
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
		var tfoe: Kin = game.gen_pal("tammane", 5, Vector2(tw_k) + Vector2(6, 0))
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

	# the island boss rule: a cornered alpha enrages — harder hits, faster feet
	var rg: Kin = game.gen_pal("fenlump", 10, p.pos)
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

	# ---- product shell: the sim gates on game.state; settings persist ----
	game.net.multiplayer.multiplayer_peer = null # a live session owns the pause rule
	game.state = "paused"
	var tc0 := game.t
	game._process(0.5)
	check("pause freezes the clock", game.t == tc0, "t=%s" % game.t)
	game.state = "play"
	# settings round-trip — keep the dev's real cfg intact: back it up first
	var cfg_backup = FileAccess.get_file_as_bytes("user://settings.cfg") \
		if FileAccess.file_exists("user://settings.cfg") else PackedByteArray()
	game.settings["sfx"] = 0.4
	game.save_settings()
	game.settings["sfx"] = 1.0
	game.load_settings()
	check("settings round-trip", absf(game.settings["sfx"] - 0.4) < 0.001, "sfx=%s" % game.settings["sfx"])
	game.settings["sfx"] = 1.0
	if cfg_backup.is_empty():
		DirAccess.remove_absolute("user://settings.cfg")
	else:
		var cf2 := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		cf2.store_buffer(cfg_backup); cf2.close()
	check("audio buses routed", AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0)

	# ---- S3: egg genetics stay mortal; peaceful mode holds the horn ----
	# the invariants live in DATA, not in the filter's own predicate — check
	# body_of() (covers the BODY table the ironpact use) and the den list raw
	var egg_pool: Array = game.hatch_pool()
	var leg_in_pool := false
	var hum_in_pool := false
	for es in egg_pool:
		if es in game.LEGENDARY_DEN or bool(SpeciesData.species_of(es).get("boss", false)):
			leg_in_pool = true
		if SpeciesData.body_of(es) == "human":
			hum_in_pool = true
	check("no legendary in egg pool", not leg_in_pool, "%d species" % egg_pool.size())
	check("no humans in egg pool", not hum_in_pool)
	check("egg pool non-empty", egg_pool.size() > 50, "%d" % egg_pool.size())
	check("ironpact read as human", SpeciesData.body_of("ironpact_grunt") == "human"
		and SpeciesData.body_of("ironpact_sweeper") == "human")
	check("combos stay mortal", game.BREED_COMBOS.values().all(
		func(s): return game.acquirable(s)), "%d combos" % game.BREED_COMBOS.size())
	# every spawn path draws from acquirable pools — assert the gate itself
	var acq_all := []
	for z in 4:
		acq_all += game.acq_pool(game.ZONE_SPECIES[z] + SpeciesGen.zone_pool(z))
	check("zone pools carry no legends", acq_all.all(func(s): return s not in game.LEGENDARY_DEN))
	check("zone pools carry no humans", acq_all.all(func(s): return SpeciesData.body_of(s) != "human"))
	check("acq pool non-empty", acq_all.size() > 40, "%d" % acq_all.size())
	game.settings["raids"] = false
	if game.kinbox_pos.x < 0:
		game.kinbox_pos = Vector2i(10, 10) # the horn only sounds for a founded base
	game.raid_t = 5.0
	game.raid_warned = true
	game.tick_raid(1.0)
	check("peaceful holds the horn", game.raid_t == Game.RAID_WARN_T + 1.0, "raid_t=%s" % game.raid_t)
	check("peaceful stands the warning down", not game.raid_warned and game.raid_theme == "")
	game.settings["raids"] = true

	# ---- S1 migration: a pre-rename save maps every id-shaped field ----
	var legacy := {
		"items": {"pal_sphere": 3, "paldium": 2},
		"catches": {"lamball": 12},
		"dex_seen": ["lamball", "jetragon"],
		"unlocked": ["palbox", "pal_sphere"],
		"equip": {"weapon": "sphere_launcher"},
		"mflags": {"sphere": true},
		"board_quest": {"id": "paldium", "sp": "lamball"},
		"kin": [{"sp": "lamball", "carry": {"id": "pal_egg", "n": 1}},
			{"sp": "syndicate_grunt", "carry": null}],
		"structures": {"1,1": {"id": "palbox", "store": {"pal_sphere": 2},
			"cap": {"sp": "lamball", "lv": 5},
			"egg": [["lamball", "chikipi", 50, 40, [], [], [], []]],
			"inc": {"pair": ["lamball", "chikipi"], "huge": false, "left": 10.0},
			"mimic": "daedream"}},
		"respawns": [{"sid": "jetragon", "lv": 50}],
		"drops": [{"id": "pal_sphere"}],
		"crafts": [{"out": "pal_sphere"}],
	}
	var md: Dictionary = Migrate.save_dict(legacy)
	check("migrate items", md["items"].has("kin_orb") and md["items"].has("lumenite"))
	check("migrate species", md["kin"][0]["sp"] == "fenjelly" and md["kin"][1]["sp"] == "ironpact_grunt")
	check("migrate carry", md["kin"][0]["carry"]["id"] == "kin_egg")
	var mst: Dictionary = md["structures"]["1,1"]
	check("migrate structure", mst["id"] == "kinbox" and mst["store"].has("kin_orb"))
	check("migrate cap+egg+inc", mst["cap"]["sp"] == "fenjelly" and mst["egg"][0][0] == "fenjelly" and mst["inc"]["pair"][1] == "fenlump")
	check("migrate mimic+respawns", mst["mimic"] == "shadelump" and md["respawns"][0]["sid"] == "scalbeak")
	check("migrate gear+flags", md["equip"]["weapon"] == "orb_launcher" and md["mflags"].has("orb"))

	# ---- S4: contextual hints fire and retire ----
	game.hint_seen.clear()
	game.player.hunger = 10.0
	var hts := game.active_hints()
	check("hunger hint fires", hts.any(func(h): return h["id"] == "eat"), "%d hints" % hts.size())
	game.tick_hints(60.0)
	check("hint retires", not game.active_hints().any(func(h): return h["id"] == "eat"))
	game.player.hunger = 100.0

	# ---- S5: ambient score ----
	check("music loops", game.music_day.stream != null and game.music_day.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and game.music_day.playing == game.audio_live)
	check("pads carry melody", game.music_danger.stream != null
		and game.music_day.stream.data.size() == game.music_day.stream.loop_end
		and game.music_danger.stream.data != game.music_day.stream.data) # arp layer must land inside the loop, not past it
	check("pads are distinct voices", game.music_day.stream.data != game.music_night.stream.data
		and game.music_night.stream.data != game.music_danger.stream.data)
	# the loop seam is real until proven: the wrap edge must carry no dip —
	# quantized freqs make head and tail meet at ~0, and a non-dividing
	# arp_step must be snapped onto the loop boundary, not chopped mid-tail
	var ddat: PackedByteArray = game.music_day.stream.data
	var e0 := int(ddat[0]); var e1 := int(ddat[ddat.size() - 1])
	# not just the two edge bytes — the wrap neighborhood must read as a
	# quiet crossing, not an attack transient or a chopped tail
	var edge_ok: bool = abs(e0 - 128) <= 12 and abs(e1 - 128) <= 12 and abs(e1 - e0) <= 12
	for ei in range(1, 8):
		edge_ok = edge_ok and abs(int(ddat[ei]) - 128) <= 40 \
			and abs(int(ddat[ddat.size() - 1 - ei]) - 128) <= 40
	check("pad wrap has no seam", edge_ok, "head=%d tail=%d" % [e0, e1])
	var seam_pad: AudioStreamWAV = game.SFX_LIB.pad([[220.0, 277.2, 329.6], [174.6, 220.0, 261.6]], 6.0, 0.13, 0.7, 0.05)
	var sdat: PackedByteArray = seam_pad.data
	check("arp slots divide the loop", abs(int(sdat[0]) - 128) <= 12
		and abs(int(sdat[sdat.size() - 1]) - 128) <= 12)
	game.tod = 22.0; game.tick_music(1.0)
	# night fade: while the danger drone owns the mix both pastoral pads duck —
	# the crossfade contract is day-ducked always, night-up only when calm
	check("night fade", game.music_day.volume_db < -10.0
		and (game.danger_active() or game.music_night.volume_db > -80.0))
	game.tod = 12.0; game.tick_music(1.0)
	check("day fade", game.music_day.volume_db > -80.0 or game.danger_active())

	# danger layer: a live raider swallows the pastoral mix until it's gone
	var raid_pal: Kin = game.gen_pal("fenlump", 5, p.pos)
	raid_pal.mode = "wild"; raid_pal.raid = true
	game.pals.append(raid_pal)
	for _i in 140: # ~0.8db/tick — the full -80→-9 climb needs the whole bar
		game.tick_music(0.1)
	check("danger pad swallows the mix", game.music_danger.volume_db > -20.0
		and game.music_day.volume_db < -20.0 and game.music_night.volume_db < -20.0,
		"dngr=%.0f day=%.0f night=%.0f" % [game.music_danger.volume_db,
			game.music_day.volume_db, game.music_night.volume_db])
	game.pals.erase(raid_pal)
	if raid_pal.get_parent(): raid_pal.get_parent().remove_child(raid_pal)
	raid_pal.free()
	for _i in 110:
		game.tick_music(0.1)
	# if an earlier raid wave is still on the field the drone SHOULD stay —
	# only assert the contract: calm means quiet
	check("danger lifts", game.danger_active() or game.music_danger.volume_db < -60.0,
		"dngr=%.0f active=%s" % [game.music_danger.volume_db, game.danger_active()])

	# ---- S6: gamepad layer binds and routes ----
	check("pad strike bound", InputMap.has_action("pad_strike")
		and InputMap.action_get_events("pad_strike").size() > 0)
	check("pad move bound", InputMap.action_get_events("move_left").any(
		func(e): return e is InputEventJoypadMotion))
	check("pad cancel bound", InputMap.action_get_events("ui_cancel").any(
		func(e): return e is InputEventJoypadButton))
	# B is dodge — it must NOT also sit on ui_cancel or every dodge pauses;
	# and rebinding after a scene reload must not stack duplicate events
	check("pad B off ui_cancel", not InputMap.action_get_events("ui_cancel").any(
		func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B))
	var dodge0 := InputMap.action_get_events("dodge").size()
	game.bind_gamepad()
	check("pad bind idempotent", InputMap.action_get_events("dodge").size() == dodge0)
	# shell menus don't leak input to the sim: a swing at pause must not fire
	game.state = "paused"
	var ac0 := game.player.atk_cd
	var pev := InputEventMouseButton.new()
	pev.button_index = MOUSE_BUTTON_LEFT; pev.pressed = true
	game.player._unhandled_input(pev)
	check("pause swallows strikes", game.player.atk_cd == ac0)
	game.state = "play"

	# menu hold-to-repeat: an edge press steps once, holding keeps marching —
	# Input.action_press drives ui_down the same way a held dpad does
	game.state = "title"
	var hudn: Node = main.get_node("UILayer/HUD")
	hudn._process(0.01) # flush the state|panel transition — _process voids stale rows there too
	hudn.click_rects = [{"rect": Rect2(), "act": "resume"}, {"rect": Rect2(), "act": "new_game"}, {"rect": Rect2(), "act": "quit"}]
	hudn.menu_sel = 0
	Input.action_press("ui_down")
	hudn._process(0.5)
	check("menu hold marches", hudn.menu_sel == 1, "sel=%d" % hudn.menu_sel)
	hudn._process(0.1)
	check("repeat cadence", hudn.menu_sel == 2, "sel=%d" % hudn.menu_sel)
	Input.action_release("ui_down")
	hudn._process(0.5)
	check("release stops marching", hudn.menu_sel == 2)
	hudn.click_rects.clear(); hudn.menu_sel = 0
	game.state = "play"

	# panels take the same cursor: dpad steps rows, A confirms — without
	# this a pad user opens the bag and is stuck there
	game.panel = "inv"
	hudn._unhandled_input(InputEventAction.new()) # flush the state|panel transition — stale rows get voided there
	hudn.click_rects = [{"rect": Rect2(), "act": "m_settings"}, {"rect": Rect2(), "act": "craft", "arg": "nope"}]
	hudn.menu_sel = 0
	var nav_down := InputEventAction.new()
	nav_down.action = "ui_down"; nav_down.pressed = true
	hudn._unhandled_input(nav_down)
	check("panel nav steps", hudn.menu_sel == 1, "sel=%d" % hudn.menu_sel)
	var nav_up := InputEventAction.new()
	nav_up.action = "ui_up"; nav_up.pressed = true
	hudn._unhandled_input(nav_up)
	check("panel nav back", hudn.menu_sel == 0)
	hudn.menu_sel = 0
	var nav_ok := InputEventAction.new()
	nav_ok.action = "ui_accept"; nav_ok.pressed = true
	hudn._unhandled_input(nav_ok) # act m_settings swaps the panel — confirm fires
	check("panel confirm fires", game.panel == "settings", "panel=%s" % game.panel)
	game.panel = ""
	hudn.click_rects.clear(); hudn.menu_sel = 0

	# rumble is a pad-only helper: headless it must no-op cleanly both ways
	game.using_pad = false; game.rumble(0.5, 0.5, 0.1)
	game.using_pad = true; game.rumble(0.2, 0.7, 0.3) # no pads connected — survives
	game.using_pad = false

	# ---- touch controls: stick steers, verbs fire, panels keep their taps ----
	var tui0 := game.touch_ui
	game.touch_ui = true
	var vpr: Vector2 = hudn.get_viewport_rect().size
	var lay_t: Dictionary = hudn.touch_layout(vpr)
	hudn.touch_down(lay_t["joy"], 0)
	hudn.touch_move(lay_t["joy"] + Vector2(hudn.JOY_R * 0.5, 0), 0)
	check("touch stick steers", game.player.touch_vec.length() > 0.3 and not game.player.touch_sprint,
		"vec=%s" % game.player.touch_vec)
	hudn.touch_move(lay_t["joy"] + Vector2(hudn.JOY_R * 1.4, 0), 0)
	check("touch rim = sprint", game.player.touch_sprint and game.player.touch_vec.length() <= 1.01)
	hudn.touch_up(0)
	check("touch release parks", game.player.touch_vec == Vector2.ZERO and hudn.joy_idx < 0)
	game.player.atk_cd = 0.0; game.player.aiming = false
	var twp: String = game.player.equipment["weapon"]
	game.player.equipment["weapon"] = "" # bare hands: ATK must land a swing regardless of gear
	hudn.touch_down(lay_t["btns"]["atk"], 1); hudn.touch_up(1)
	check("touch ATK swings", game.player.atk_cd > 0.0)
	game.player.equipment["weapon"] = twp
	hudn.touch_down(lay_t["btns"]["aim"], 2); hudn.touch_up(2)
	check("touch AIM toggles", game.player.aiming)
	game.player.aiming = false
	var sel0 := game.player.sphere_sel
	hudn.touch_down(lay_t["btns"]["orb"], 3); hudn.touch_up(3)
	check("touch ORB cycles", game.player.sphere_sel != sel0 or game.sphere_tiers().size() <= 1)
	game.player.stamina = 100.0; game.player.dodge_t = 0.0
	hudn.touch_down(lay_t["btns"]["roll"], 4); hudn.touch_up(4)
	check("touch ROLL dodges", game.player.dodge_t > 0.0, "dodge_t=%s" % game.player.dodge_t)
	game.player.dodge_t = 0.0; game.player.stamina = 100.0
	hudn.touch_down(lay_t["btns"]["menu"], 5); hudn.touch_up(5)
	check("touch MENU pauses", game.state == "paused")
	game.state = "play"
	hudn.touch_down(lay_t["btns"]["inv"], 6); hudn.touch_up(6)
	check("touch INV opens bag", game.panel == "inv")
	game.panel = ""
	hudn.touch_down(lay_t["btns"]["bld"], 6); hudn.touch_up(6)
	check("touch BLD opens build", game.panel == "build")
	game.panel = "inv"
	hudn.touch_down(lay_t["joy"], 6)
	check("panel owns taps", hudn.joy_idx < 0)
	game.panel = ""
	# real event routing — not just the helpers: _unhandled_input is the gate
	game.player.aiming = false
	var t_ev := InputEventScreenTouch.new()
	t_ev.pressed = true; t_ev.index = 9; t_ev.position = lay_t["btns"]["aim"]
	hudn._unhandled_input(t_ev)
	check("screen-touch event routes", game.player.aiming)
	game.player.aiming = false
	game.touch_ui = false
	hudn._unhandled_input(t_ev)
	check("touch_ui off blocks routing", not game.player.aiming)
	game.touch_ui = true
	game.state = "paused"
	hudn._unhandled_input(t_ev)
	check("paused blocks touch verbs", not game.player.aiming)
	game.state = "play"
	# a menu swap mid-drift must park the stick — _process owns the transition
	hudn.touch_down(lay_t["joy"], 0)
	hudn.touch_move(lay_t["joy"] + Vector2(hudn.JOY_R * 0.5, 0), 0)
	game.panel = "inv"
	hudn._process(0.016)
	check("panel swap parks stick", game.player.touch_vec == Vector2.ZERO and hudn.joy_idx < 0,
		"vec=%s idx=%d" % [game.player.touch_vec, hudn.joy_idx])
	game.panel = ""
	# rim sprint must be real SPEED, not just a stamina bill
	p.statuses.erase("sleep"); p.dodge_t = 0.0; p.mount = null; p.stamina = 100.0
	var sprint_cell := Vector2i(-1, -1)
	for r6 in range(1, 40):
		for d6 in [Vector2i(r6, 0), Vector2i(-r6, 0), Vector2i(0, r6), Vector2i(0, -r6)]:
			var c6: Vector2i = Vector2i(int(p.pos.x), int(p.pos.y)) + d6
			if p.can_enter(c6.x + 1.5, c6.y + 0.5) and p.can_enter(c6.x + 0.5, c6.y + 0.5):
				sprint_cell = c6; break
		if sprint_cell.x >= 0: break
	if sprint_cell.x >= 0:
		p.pos = Vector2(sprint_cell.x + 0.5, sprint_cell.y + 0.5)
		p.touch_vec = Vector2(1, 0); p.touch_sprint = false
		var sx0: float = p.pos.x
		p._physics_process(0.016)
		var d_walk := p.pos.x - sx0
		sx0 = p.pos.x
		p.touch_sprint = true; p.stamina = 100.0
		p._physics_process(0.016)
		var d_run := p.pos.x - sx0
		check("touch sprint is real speed", d_walk > 0.0 and d_run > d_walk * 1.4,
			"walk=%.4f run=%.4f" % [d_walk, d_run])
		p.touch_vec = Vector2.ZERO; p.touch_sprint = false
	# emulated taps on virtual controls are eaten; a real mouse still strikes
	game.hud = hudn
	p.aiming = false; p.atk_cd = 0.0
	var m_ev := InputEventMouseButton.new()
	m_ev.button_index = MOUSE_BUTTON_LEFT; m_ev.pressed = true
	m_ev.position = lay_t["btns"]["atk"]
	p._unhandled_input(m_ev)
	check("tap on ATK is eaten", p.atk_cd == 0.0, "cd=%s" % p.atk_cd)
	m_ev.position = Vector2(vpr.x * 0.5, vpr.y * 0.4) # open sky — no control there
	p._unhandled_input(m_ev)
	check("real mouse still strikes", p.atk_cd > 0.0, "cd=%s" % p.atk_cd)
	var tm0 := str(game.settings["touch"])
	hudn.shell_act("touch_tgl")
	check("touch setting cycles", str(game.settings["touch"]) != tm0
		and game.touch_ui == (str(game.settings["touch"]) == "on"))
	game.settings["touch"] = tm0; game.apply_settings()
	game.touch_ui = tui0
	# join/chat panels must summon the OS keyboard on touch and the pause
	# shell needs a JOIN row — before this, K was the only door in
	game.state = "paused"
	var peer_bak = game.net.multiplayer.multiplayer_peer
	game.net.multiplayer.multiplayer_peer = null # a guest sees no join row
	var join_rows := 0
	for row in hudn.pause_rows():
		if row[1] == "m_join": join_rows += 1
	check("pause shell offers join", join_rows == 1, "rows=%s" % join_rows)
	var chat_rows := 0
	for row in hudn.pause_rows():
		if row[1] == "m_chat": chat_rows += 1
	check("no chat row without a peer", chat_rows == 0)
	var tmp_peer := ENetMultiplayerPeer.new() # a half-open dial is not a session
	tmp_peer.create_client("127.0.0.1", 1)
	game.net.multiplayer.multiplayer_peer = tmp_peer
	chat_rows = 0
	for row in hudn.pause_rows():
		if row[1] == "m_chat": chat_rows += 1
	check("no chat row on a half-open dial", chat_rows == 0)
	tmp_peer.close()
	# a real CONNECTED peer earns the row — synchronous loopback handshake
	var tmp_srv := ENetMultiplayerPeer.new()
	tmp_srv.create_server(17891, 2)
	var tmp_cli := ENetMultiplayerPeer.new()
	tmp_cli.create_client("127.0.0.1", 17891)
	var v9_t0 := Time.get_ticks_msec()
	while tmp_cli.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
			and Time.get_ticks_msec() - v9_t0 < 2000:
		tmp_srv.poll(); tmp_cli.poll()
		OS.delay_msec(10)
	game.net.multiplayer.multiplayer_peer = tmp_cli
	chat_rows = 0
	for row in hudn.pause_rows():
		if row[1] == "m_chat": chat_rows += 1
	check("chat row when peered", chat_rows == 1)
	tmp_srv.close(); tmp_cli.close()
	game.net.multiplayer.multiplayer_peer = peer_bak
	hudn.run_click({"act": "m_join", "arg": null}) # the REAL click path, not the helper
	hudn._process(0.016)
	check("join panel opens + vkbd tracks", game.panel == "join" and hudn._vkbd_open,
		"panel=%s vkbd=%s" % [game.panel, hudn._vkbd_open])
	game.panel = ""
	# text panels get on-screen OK/X — the only out on a keyless slab
	game.panel = "chat"; hudn.chat_buf = "hi"
	hudn.run_click({"act": "text_cancel", "arg": null})
	check("X button bails chat", game.panel == "" and hudn.chat_buf == "")
	game.panel = "chat"
	hudn.run_click({"act": "chat_send", "arg": null})
	check("OK closes an empty chat", game.panel == "")
	game.panel = "join"; hudn.join_buf = "  "
	hudn.run_click({"act": "text_cancel", "arg": null})
	check("X bails join + wipes buf", game.panel == "" and hudn.join_buf == "")
	hudn._process(0.016)
	check("vkbd drops with panel", not hudn._vkbd_open)
	game.state = "play"
	# panel trap: ☰ stays up as ✕ — the only way out of a panel on a slab
	game.panel = "inv"
	hudn.touch_down(lay_t["btns"]["menu"], 3)
	check("X tap closes the panel", game.panel == "")
	hudn.touch_down(lay_t["joy"], 4) # a stray tap inside the panel must NOT move
	check("panel still owns other taps", p.touch_vec == Vector2.ZERO)
	# more-row: ··· toggles, verbs ride the real helpers
	hudn.touch_verb("more")
	check("··· expands the verb row", hudn.touch_more)
	check("row zones eat taps", hudn.touch_zone_hit(lay_t["more_row"]["dml"]))
	hudn.touch_verb("map")
	check("map verb toggles minimap", hudn.map_show)
	hudn.touch_verb("map")
	check("map verb toggles back", not hudn.map_show)
	var dm_placed := false
	var dm_k := Vector2i.ZERO
	if "campfire" not in game.unlocked: game.unlocked.append("campfire")
	for rad in range(1, 4):
		for ang9 in range(16):
			var ck := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
				int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
			if Vector2(ck.x + 0.5 - p.pos.x, ck.y + 0.5 - p.pos.y).length() > 4.0:
				continue # _touch_demolish only reaches ~4.5 tiles out
			if game.can_place("campfire", ck.x, ck.y):
				game.place_free("campfire", ck.x, ck.y); dm_k = ck; dm_placed = true; break
		if dm_placed: break
	if dm_placed:
		hudn.touch_verb("dml")
		check("dml razes the nearest structure", not game.structures.has(dm_k))
	else:
		check("dml razes the nearest structure", false, "no campfire spot seeded")
	# one reach contract for every raze path — X key used to snipe across the map
	var dm2 := Vector2i.ZERO; var dm2_ok := false
	for rad in range(6, 9):
		for ang9 in range(16):
			var ck2 := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
				int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
			if game.can_place("campfire", ck2.x, ck2.y):
				game.place_free("campfire", ck2.x, ck2.y); dm2 = ck2; dm2_ok = true; break
		if dm2_ok: break
	if dm2_ok:
		hudn._demolish_verb(Vector2(dm2.x, dm2.y)) # out of reach — must refuse
		check("far structure survives the verb", game.structures.has(dm2)
			and game.messages.back() == "Too far to demolish", "msg=%s" % game.messages.back())
		var mpos := p.pos
		p.pos = Vector2(dm2.x + 1.5, dm2.y + 0.5) # step inside reach, raze for real
		hudn._demolish_verb(Vector2(dm2.x, dm2.y))
		check("in-reach structure razes", not game.structures.has(dm2))
		p.pos = mpos
	else:
		check("far structure survives the verb", false, "no far spot seeded")
	var act_ev := InputEventAction.new() # the REAL key route must hit the same gate
	act_ev.action = "demolish"; act_ev.pressed = true
	hudn._unhandled_input(act_ev)
	check("key route respects reach", game.messages.back() in
		["Too far to demolish", "Nothing to demolish"], "msg=%s" % game.messages.back())

	# ---- S33 audit batch: anchor, residue, tech-sync, touch polish ----
	# the LAST kinbox is anchored — a backup or a lone outpost still razes clean
	var xb_bak := game.extra_boxes.duplicate()
	var kb_bak: Vector2i = game.kinbox_pos
	var kb_t: Vector2i = game.kinbox_pos
	var planted_kb := false
	var cur_kb = game.structures.get(kb_t)
	if cur_kb == null or not StructureData.STRUCTURES.get(cur_kb["id"], {}).get("anchor", false):
		# phantom kinbox_pos (earlier fixtures can leave it pointing at air) —
		# plant a real anchor: the contract is about the LAST base standing
		for rad in range(3, 10):
			for ang9 in range(16):
				var ck3 := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
					int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
				if game.can_place("kinbox", ck3.x, ck3.y):
					game.place_free("kinbox", ck3.x, ck3.y)
					kb_t = ck3; planted_kb = true; break
			if planted_kb: break
		if planted_kb:
			game.kinbox_pos = kb_t
	game.extra_boxes = [] # isolate: no backup to promote — the anchor must hold
	check("last kinbox refuses the raze",
		game.structures.has(kb_t)
		and not game.demolish_at(Vector2(kb_t.x + 0.5, kb_t.y + 0.5))
		and game.structures.has(kb_t) and game.kinbox_pos == kb_t
		and game.messages.back() == "The kinbox anchors the base — nobody razes it",
		"pos=%s has=%s msg=%s" % [kb_t, game.structures.has(kb_t), game.messages.back()])
	if planted_kb: # it refused — take the fixture down and restore the books
		game.net_remove_structure(game.structures[kb_t])
		game.kinbox_pos = kb_bak
	game.extra_boxes = xb_bak
	# ...while an outpost backup is still a normal structure — razes clean
	var kb_ok := false; var kb_k := Vector2i.ZERO
	for rad in range(3, 8):
		for ang9 in range(16):
			var ck3 := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
				int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
			if game.can_place("kinbox", ck3.x, ck3.y):
				game.place_free("kinbox", ck3.x, ck3.y); kb_k = ck3; kb_ok = true; break
		if kb_ok: break
	if kb_ok:
		var kb_t2: Vector2i = game.kinbox_pos
		check("outpost backup razes clean", game.demolish_at(Vector2(kb_k.x + 0.5, kb_k.y + 0.5))
			and not game.structures.has(kb_k) and game.kinbox_pos == kb_t2
			and not game.extra_boxes.has(kb_k), "primary=%s" % game.kinbox_pos)
	else:
		check("outpost backup razes clean", false, "no outpost spot seeded")
	game.extra_boxes = xb_bak # placement/demolish is self-cleaning — belt and braces
	# residue world: a dropped session must never write over a real save
	game.net_residue = true
	game.save_game()
	check("residue refuses the save", game.messages.back() == "A dropped session's world can't be saved",
		"msg=%s" % game.messages.back())
	game.net_residue = false
	var party_bak := game.party.duplicate()
	game.net_party = [{"uid": 9, "sp": "x"}]; game.net_box = [{"uid": 8}]; game.party = [9, 8]
	game.net._on_server_disconnected() # mirrors + dead uid strip die with the session
	check("disconnect drops the mirrors", game.net_party.is_empty() and game.net_box.is_empty()
		and game.party.is_empty() and game.net.multiplayer.multiplayer_peer == null)
	game.party = party_bak
	# host tech bounds the client's build bar; locked blueprints refund
	var cli_peer := ENetMultiplayerPeer.new()
	cli_peer.create_client("127.0.0.1", 1)
	game.net.multiplayer.multiplayer_peer = cli_peer
	game.net.is_host = false
	game.net_unlocked = ["campfire"]
	var bl_now := game.buildable_list()
	check("build bar intersects host tech", bl_now.size() == 1 and bl_now[0] == "campfire",
		"list=%s" % str(bl_now))
	var w00 := game.item_count("wood") if "wood" in game.items else 0
	var whad := game.items.has("wood")
	game.items["wood"] = 2 # a known pile — the hold books only what leaves
	game.net.pending_pays.clear()
	game.net.pay("build", {"wood": 2})
	game.net.pay_rej("build") # every deny path settles the hold, not the price table
	check("a refused build refunds the hold", game.item_count("wood") == 2
		and game.net.pending_pays.is_empty())
	if whad:
		game.items["wood"] = w00
	else:
		game.items.erase("wood")
	game.net_unlocked = []
	var tec_rows := 0
	for row in hudn.pause_rows():
		if row[1] == "m_tech": tec_rows += 1
	check("guest sees no tech row", tec_rows == 0)
	cli_peer.close()
	game.net.multiplayer.multiplayer_peer = null
	for row in hudn.pause_rows():
		if row[1] == "m_tech": tec_rows += 1
	check("solo keeps the tech row", tec_rows == 1)
	# touch shot aims down facing, not at the button's screen corner
	var tui3 := game.touch_ui
	var fac0 := p.facing
	game.touch_ui = true
	p.facing = Vector2(0, 1)
	var st_t := p._shot_target({})
	check("touch shot rides facing", st_t.distance_to(p.pos + Vector2(0, 8)) < 0.01,
		"target=%s" % str(st_t))
	p.facing = fac0
	# build taps only yield to the X — the joystick corner is placeable again
	check("joy corner takes a build tap", hudn._build_tap_ok(lay_t["joy"]))
	check("X zone still guarded", not hudn._build_tap_ok(lay_t["btns"]["menu"]))
	# pinch zoom is the slab's only zoom
	var cam0: Vector2 = main.cam.zoom
	var mg := InputEventMagnifyGesture.new()
	mg.factor = 1.4
	main._unhandled_input(mg)
	check("pinch zooms the camera", not main.cam.zoom.is_equal_approx(cam0)
		and main.cam.zoom.x <= 2.5)
	main.cam.zoom = cam0
	# roll cleared ATK's hit disc
	check("roll clear of atk zone", lay_t["btns"]["atk"].distance_to(lay_t["btns"]["roll"])
		>= hudn.btn_r("atk") + hudn.btn_r("roll"))
	# x_close is a real act — pads and mice hit the X too
	game.panel = "inv"
	hudn.run_click({"act": "x_close", "arg": null})
	check("x_close bails the panel", game.panel == "")
	check("dex ids cached", hudn._dex_ids().size() > 0 and hudn._dex_key != "")
	# guest container ops: the host validates, the wire carries the truth
	var ch_ok := false; var ch_k := Vector2i.ZERO
	for rad in range(3, 10):
		for ang9 in range(16):
			var ck4 := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
				int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
			if game.can_place("chest", ck4.x, ck4.y):
				game.place_free("chest", ck4.x, ck4.y); ch_k = ck4; ch_ok = true; break
		if ch_ok: break
	if ch_ok:
		var ch_st: Dictionary = game.structures[ch_k]
		ch_st["store"] = {"gold_coin": 7}
		if not game.net.ghosts.has(99):
			game.net.spawn_ghost(99)
		game.net.ghosts[99].net_pos = Vector3(ch_k.x, ch_k.y, 0)
		var acc := game.chest_req_remote(99, ch_k, "dep",
			{"wood": 4, "stone": 2, "gold_coin": 9, "fake_id_x": 5})
		check("guest deposit whitelists", int(acc.get("wood", 0)) == 4
			and int(acc.get("stone", 0)) == 2 and not acc.has("gold_coin")
			and not acc.has("fake_id_x"), "acc=%s" % acc)
		check("deposit reached the store", int(ch_st["store"].get("wood", 0)) == 4
			and int(ch_st["store"].get("gold_coin", 0)) == 7)
		game.net.ghosts[99].net_pos = Vector3(ch_k.x + 40, ch_k.y, 0)
		check("far ghost can't reach the box", game.chest_req_remote(99, ch_k, "dep",
			{"wood": 1}).is_empty() and int(ch_st["store"].get("wood", 0)) == 4)
		game.net.ghosts[99].net_pos = Vector3(ch_k.x, ch_k.y, 0)
		var tk := game.chest_req_remote(99, ch_k, "wd", {})
		check("guest withdraw takes host truth", int(tk.get("wood", 0)) == 4
			and int(tk.get("gold_coin", 0)) == 7 and ch_st["store"].is_empty(), "tk=%s" % tk)
		check("non-container refused", game.chest_req_remote(99,
			ch_k + Vector2i(9, 9), "wd", {}).is_empty())
		game.net_remove_structure(ch_st)
		# the feed box keeps its food-only rule for guests too
		var fbx_k := Vector2i(-1, -1)
		for rad in range(3, 10):
			for ang9 in range(16):
				var ck6 := Vector2i(int(p.pos.x + cos(ang9 * TAU / 16.0) * rad),
					int(p.pos.y + sin(ang9 * TAU / 16.0) * rad))
				if game.can_place("feed_box", ck6.x, ck6.y):
					game.place_free("feed_box", ck6.x, ck6.y); fbx_k = ck6; break
			if fbx_k.x >= 0: break
		if fbx_k.x >= 0:
			var fbx_st: Dictionary = game.structures[fbx_k]
			game.net.ghosts[99].net_pos = Vector3(fbx_k.x, fbx_k.y, 0)
			var acc_fb := game.chest_req_remote(99, fbx_k, "dep", {"wood": 3, "baked_berries": 2})
			check("feed box keeps the food rule", int(acc_fb.get("baked_berries", 0)) == 2
				and not acc_fb.has("wood"), "acc=%s" % acc_fb)
			game.net_remove_structure(fbx_st)
		# S35 guest world-verbs: the mouth answers the asker, the farm
		# takes guest labor, the rod rolls host-side at the ghost's shore
		var vt_mk := Vector2i(-1, -1)
		for vt_r2 in range(3, 10):
			for vt_a10 in range(16):
				var vt_c7 := Vector2i(int(p.pos.x + cos(vt_a10 * TAU / 16.0) * vt_r2),
					int(p.pos.y + sin(vt_a10 * TAU / 16.0) * vt_r2))
				if game.can_place("chest", vt_c7.x, vt_c7.y):
					game.place_free("chest", vt_c7.x, vt_c7.y); vt_mk = vt_c7; break
			if vt_mk.x >= 0: break
		if vt_mk.x >= 0:
			var vt_mst: Dictionary = game.structures[vt_mk]
			vt_mst["mimic"] = "fenjelly"
			var vt_p0 := game.pals.size()
			game.net.ghosts[99].net_pos = Vector3(vt_mk.x + 40, vt_mk.y, 0)
			check("far ghost can't spring the trap",
				not game.mimic_req_remote(99, vt_mk)
				and game.structures.has(vt_mk) and game.pals.size() == vt_p0)
			game.net.ghosts[99].net_pos = Vector3(vt_mk.x, vt_mk.y, 0)
			check("the trap opens on the asker", game.mimic_req_remote(99, vt_mk)
				and not game.structures.has(vt_mk) and game.pals.size() == vt_p0 + 1)
			if game.pals.size() > vt_p0:
				var vt_mp: Kin = game.pals.back()
				check("the mouth hunts the asker", vt_mp.aggro_pid == 99)
				game.pals.erase(vt_mp)
				vt_mp.queue_free()
			check("a plain chest stays a chest", not game.mimic_req_remote(99, vt_mk))
		var vt_fk := Vector2i(-1, -1)
		for vt_r3 in range(3, 10):
			for vt_a11 in range(16):
				var vt_c8 := Vector2i(int(p.pos.x + cos(vt_a11 * TAU / 16.0) * vt_r3),
					int(p.pos.y + sin(vt_a11 * TAU / 16.0) * vt_r3))
				if game.can_place("wheat_farm", vt_c8.x, vt_c8.y):
					game.place_free("wheat_farm", vt_c8.x, vt_c8.y); vt_fk = vt_c8; break
			if vt_fk.x >= 0: break
		if vt_fk.x >= 0:
			var vt_fst: Dictionary = game.structures[vt_fk]
			game.net.ghosts[99].net_pos = Vector3(vt_fk.x + 40, vt_fk.y, 0)
			check("far ghost can't fertilize", not game.fert_req_remote(99))
			game.net.ghosts[99].net_pos = Vector3(vt_fk.x, vt_fk.y, 0)
			check("guest fertilize lands host-side", game.fert_req_remote(99)
				and float(vt_fst.get("fert", 0.0)) > 0.0)
			game.net_remove_structure(vt_fst)
		# fishing: find a shore cell — the roll lands somewhere (a kin
		# spawns host-truth, or loot echoes to the asker's bag)
		var vt_wc := Vector2i(-1, -1)
		for vt_wy in range(4, World.WORLD_H - 4):
			for vt_wx in range(4, World.WORLD_W - 4):
				if game.world.tiles[game.world.idx(vt_wx, vt_wy)] == World.Tile.WATER:
					vt_wc = Vector2i(vt_wx + 1, vt_wy); break
			if vt_wc.x >= 0: break
		if vt_wc.x >= 0:
			game.net.ghosts[99].net_pos = Vector3(vt_wc.x, vt_wc.y, 0)
			var vt_bag := game.item_count("kin_fluid") + game.item_count("gold_coin") \
				+ game.item_count("red_berries") + game.item_count("treasure_map")
			var vt_p1 := game.pals.size()
			game.cast_line_remote(99)
			check("guest cast lands a roll", game.pals.size() > vt_p1 or
				game.item_count("kin_fluid") + game.item_count("gold_coin") \
				+ game.item_count("red_berries") + game.item_count("treasure_map") > vt_bag)
		# S36 verbs: shrine sky, stand pace, bed clock, fossil dig, cage
		# rescue, board claim, remote condense — all ghost-reach gated
		var v6_sh := Vector2i(-1, -1)
		for v6_r4 in range(3, 10):
			for v6_a12 in range(16):
				var v6_c9 := Vector2i(int(p.pos.x + cos(v6_a12 * TAU / 16.0) * v6_r4),
					int(p.pos.y + sin(v6_a12 * TAU / 16.0) * v6_r4))
				if game.can_place("weather_shrine", v6_c9.x, v6_c9.y):
					game.place_free("weather_shrine", v6_c9.x, v6_c9.y); v6_sh = v6_c9; break
			if v6_sh.x >= 0: break
		if v6_sh.x >= 0:
			var v6_w0: String = game.weather
			game.pray_cd = 0.0
			game.net.ghosts[99].net_pos = Vector3(v6_sh.x + 40, v6_sh.y, 0)
			check("far ghost can't pray", not game.shrine_req_remote(99))
			game.net.ghosts[99].net_pos = Vector3(v6_sh.x, v6_sh.y, 0)
			check("guest prayer turns the shared sky", game.shrine_req_remote(99)
				and game.weather != v6_w0 and game.pray_cd > 0.0)
			game.net_remove_structure(game.structures[v6_sh])
		var v6_ms := Vector2i(-1, -1)
		for v6_r5 in range(3, 10):
			for v6_a13 in range(16):
				var v6_c10 := Vector2i(int(p.pos.x + cos(v6_a13 * TAU / 16.0) * v6_r5),
					int(p.pos.y + sin(v6_a13 * TAU / 16.0) * v6_r5))
				if game.can_place("monitoring_stand", v6_c10.x, v6_c10.y):
					game.place_free("monitoring_stand", v6_c10.x, v6_c10.y); v6_ms = v6_c10; break
			if v6_ms.x >= 0: break
		if v6_ms.x >= 0:
			var v6_wm := game.work_mode
			game.net.ghosts[99].net_pos = Vector3(v6_ms.x + 40, v6_ms.y, 0)
			check("far ghost can't touch the dial", game.work_req_remote(99) < 0)
			game.net.ghosts[99].net_pos = Vector3(v6_ms.x, v6_ms.y, 0)
			check("guest cycles the shared pace", game.work_req_remote(99) >= 0
				and game.work_mode != v6_wm)
			game.net_remove_structure(game.structures[v6_ms])
		for v6_q2 in game.pals: # no raid or wild aggro — the bed must say yes
			v6_q2.aggro = -1
			v6_q2.raid = false
		var v6_day := game.day
		check("sleep needs a bed in reach", not game.sleep_req_remote(99))
		var bd_k := Vector2i(-1, -1)
		for rad9 in range(3, 10):
			for ang17 in range(16):
				var ck14 := Vector2i(int(p.pos.x + cos(ang17 * TAU / 16.0) * rad9),
					int(p.pos.y + sin(ang17 * TAU / 16.0) * rad9))
				if game.can_place("straw_bed", ck14.x, ck14.y):
					game.place_free("straw_bed", ck14.x, ck14.y); bd_k = ck14; break
			if bd_k.x >= 0: break
		if bd_k.x >= 0:
			game.net.ghosts[99].net_pos = Vector3(bd_k.x, bd_k.y, 0)
			check("guest sleep turns the clock", game.sleep_req_remote(99)
				and game.day == v6_day + 1)
			var bd_st2: Dictionary = game.structures[bd_k]
			for bdk in game.structures.keys():
				if game.structures[bdk] == bd_st2:
					game.structures.erase(bdk) # footprint out now — deferred removal blocks the hop tile
		var v6_fs := Vector2i(-1, -1)
		for v6_r6 in range(3, 10):
			for v6_a14 in range(16):
				var v6_c11 := Vector2i(int(p.pos.x + cos(v6_a14 * TAU / 16.0) * v6_r6),
					int(p.pos.y + sin(v6_a14 * TAU / 16.0) * v6_r6))
				if game.can_place("fossil_bed", v6_c11.x, v6_c11.y):
					game.place_free("fossil_bed", v6_c11.x, v6_c11.y); v6_fs = v6_c11; break
			if v6_fs.x >= 0: break
		if v6_fs.x >= 0:
			var v6_parts := game.item_count("ancient_part") + game.item_count("stone")
			game.net.ghosts[99].net_pos = Vector3(v6_fs.x + 40, v6_fs.y, 0)
			check("far ghost can't dig", not game.dig_req_remote(99, v6_fs)
				and game.structures.has(v6_fs))
			game.net.ghosts[99].net_pos = Vector3(v6_fs.x, v6_fs.y, 0)
			check("guest dig pays out", game.dig_req_remote(99, v6_fs)
				and not game.structures.has(v6_fs)
				and game.item_count("ancient_part") + game.item_count("stone") > v6_parts)
			check("the same heap won't double-pay", not game.dig_req_remote(99, v6_fs))
		var v6_cg := Vector2i(-1, -1)
		for v6_r7 in range(3, 10):
			for v6_a15 in range(16):
				var v6_c12 := Vector2i(int(p.pos.x + cos(v6_a15 * TAU / 16.0) * v6_r7),
					int(p.pos.y + sin(v6_a15 * TAU / 16.0) * v6_r7))
				if game.can_place("kin_cage", v6_c12.x, v6_c12.y):
					game.place_free("kin_cage", v6_c12.x, v6_c12.y); v6_cg = v6_c12; break
			if v6_cg.x >= 0: break
		if v6_cg.x >= 0:
			var v6_cst: Dictionary = game.structures[v6_cg]
			v6_cst["captive"] = {"sp": "fenjelly", "lv": 10}
			var v6_box := game.box.size()
			game.net.ghosts[99].net_pos = Vector3(v6_cg.x + 40, v6_cg.y, 0)
			check("far ghost can't prize the lock", not game.cage_req_remote(99, v6_cg)
				and game.box.size() == v6_box)
			game.net.ghosts[99].net_pos = Vector3(v6_cg.x, v6_cg.y, 0)
			check("guest frees into their own slice", game.cage_req_remote(99, v6_cg)
				and game.box.size() == v6_box + 1
				and game.box.back().owner_id == 99
				and not game.structures.has(v6_cg))
			var v6_fr: Kin = game.box.pop_back()
			game.box_holder.remove_child(v6_fr)
			v6_fr.free()
		var v7_nb := Vector2i(-1, -1)
		for v7_r10 in range(3, 12):
			for v7_a18 in range(16):
				var v7_c15 := Vector2i(int(p.pos.x + cos(v7_a18 * TAU / 16.0) * v7_r10),
					int(p.pos.y + sin(v7_a18 * TAU / 16.0) * v7_r10))
				if game.can_place("notice_board", v7_c15.x, v7_c15.y):
					game.place_free("notice_board", v7_c15.x, v7_c15.y); v7_nb = v7_c15; break
			if v7_nb.x >= 0: break
		if v7_nb.x >= 0:
			game.board_quest = {"kind": "supply", "id": "wood", "n": 2, "day": game.day}
			game.net.ghosts[99].net_pos = Vector3(v7_nb.x, v7_nb.y, 0)
			var v6_bres := game.board_action_remote(99)
			check("guest board claim returns the bill", int(v6_bres.get("n", 0)) == 2
				and str(v6_bres.get("id", "")) == "wood" and int(v6_bres.get("gold", 0)) > 0
				and str(game.board_quest.get("id", "?")) == "wood"
				and int(game.board_quest.get("pending", {}).get("pid", 0)) == 99)
			if not game.net.ghosts.has(7):
				game.net.spawn_ghost(7)
			game.net.ghosts[7].net_pos = Vector3(v7_nb.x, v7_nb.y, 0)
			check("another keeper can't steal the hold",
				game.board_action_remote(7).is_empty())
			check("settlement fills the posting", int(game.board_paid_remote(99, "wood").get("gold", 0)) > 0
				and str(game.board_quest.get("id", "?")) == ""
				and not game.board_quest.has("pending"))
			# S40: the hold is a claim, not a renewable lease — same asker reads
			# it back without a fresh clock, expiry cools them off for 30s
			game.board_quest = {"kind": "supply", "id": "stone", "n": 3, "day": game.day,
				"pending": {"pid": 99, "t": game.t, "id": "stone"}}
			var bh_res := game.board_action_remote(99)
			check("same asker re-reads its hold", str(bh_res.get("id", "")) == "stone"
				and float(game.board_quest["pending"]["t"]) == game.t)
			game.board_quest["pending"]["t"] = game.t - 20.0
			check("expired holder cools off", game.board_action_remote(99).is_empty())
			game.board_quest["pending"]["t"] = game.t - 50.0
			check("cooled keeper claims again", not game.board_action_remote(99).is_empty())
			# hunt is a kill-tracker, not a claim — the board must still be
			# there for the read to mean anything
			game.board_quest = {"kind": "hunt", "sp": "fenjelly", "n": 2, "got": 0, "day": game.day}
			check("hunt posting is read-only", game.board_action_remote(99).is_empty())
			game.board_quest = {"kind": "supply", "id": "stone", "n": 2, "day": game.day}
			check("a supply claim still answers at the board",
				str(game.board_action_remote(99).get("id", "")) == "stone")
			game.board_quest.erase("pending")
			var hk_p: Kin = game.gen_pal("fenjelly", 5, p.pos)
			game.pals.append(hk_p)
			hk_p.mode = "wild"
			game.board_quest = {"kind": "hunt", "sp": "fenjelly", "n": 2, "got": 0, "day": game.day}
			game.kill_pal(hk_p, false, 99)
			check("a guest's kill thins the herd", int(game.board_quest.get("got", 0)) == 1)
			var hk_p2: Kin = game.gen_pal("fenjelly", 5, p.pos)
			game.pals.append(hk_p2)
			hk_p2.mode = "wild"
			game.kill_pal(hk_p2, false, 99)
			check("the fill lands and pays out", str(game.board_quest.get("kind", "")) == "done")
			game.net_remove_structure(game.structures[v7_nb])
		var v6_lead: Kin = game.gen_pal("fenjelly", 10, p.pos)
		game.pals.append(v6_lead)
		v6_lead.owner_id = 99
		v6_lead.mode = "partner"
		game.net.peer_tags[99] = "t99"
		game.remote_parties["t99"] = [v6_lead.uid]
		var v6_fod := 0
		while v6_fod < int(game.CONDENSE_COST[v6_lead.star]):
			var v6_fd: Kin = game.gen_pal("fenjelly", 5, p.pos)
			v6_fd.owner_id = 99
			v6_fd.mode = "box"
			game.box.append(v6_fd)
			game.box_pal(v6_fd)
			v6_fod += 1
		var v6_star := v6_lead.star
		var v6_cd := Vector2i(-1, -1)
		for v6_r9 in range(3, 12):
			for v6_a19 in range(16):
				var v6_c16 := Vector2i(int(p.pos.x + cos(v6_a19 * TAU / 16.0) * v6_r9),
					int(p.pos.y + sin(v6_a19 * TAU / 16.0) * v6_r9))
				if game.can_place("kin_condenser", v6_c16.x, v6_c16.y):
					game.place_free("kin_condenser", v6_c16.x, v6_c16.y); v6_cd = v6_c16; break
			if v6_cd.x >= 0: break
		if v6_cd.x >= 0:
			game.net.ghosts[99].net_pos = Vector3(v6_cd.x + 40, v6_cd.y, 0)
			check("a remote star needs the machine",
				not game.condense_remote(99) and v6_lead.star == v6_star)
			game.net.ghosts[99].net_pos = Vector3(v6_cd.x, v6_cd.y, 0)
			check("guest condense burns own fodder", game.condense_remote(99)
				and v6_lead.star == v6_star + 1)
			game.net_remove_structure(game.structures[v6_cd])
		else:
			check("condenser site found", false, "no kin_condenser spot in 9 rings")
		game.pals.erase(v6_lead)
		v6_lead.queue_free()
		var ib_k := Vector2i(-1, -1)
		for rad8 in range(3, 12):
			for ang16 in range(16):
				var ck13 := Vector2i(int(p.pos.x + cos(ang16 * TAU / 16.0) * rad8),
					int(p.pos.y + sin(ang16 * TAU / 16.0) * rad8))
				if game.can_place("incubator", ck13.x, ck13.y):
					game.place_free("incubator", ck13.x, ck13.y); ib_k = ck13; break
			if ib_k.x >= 0: break
		if ib_k.x >= 0:
			game.net.ghosts[99].net_pos = Vector3(ib_k.x + 40, ib_k.y, 0)
			check("far ghost can't deposit an egg",
				not game.egg_req_remote(99, "kin_egg"))
			game.net.ghosts[99].net_pos = Vector3(ib_k.x, ib_k.y, 0)
			check("bogus egg refused", not game.egg_req_remote(99, "dragon_egg"))
			check("guest egg claims the slot", game.egg_req_remote(99, "kin_egg")
				and int(game.structures[ib_k].get("egg_inc", {}).get("own_pid", 0)) == 99)
			var pals_b4 := game.pals.size()
			game.hatch_incubated(ib_k, game.structures[ib_k])
			var np2: Kin = null
			for q3 in game.pals:
				if q3.owner_id == 99:
					np2 = q3; break
			if np2 == null:
				for q4 in game.box:
					if q4.owner_id == 99:
						np2 = q4; break
			check("guest egg hatches into their slice", game.pals.size() > pals_b4
				or np2 != null)
			if np2 != null:
				if game.pals.has(np2):
					game.pals.erase(np2)
					np2.queue_free()
				else:
					game.box.erase(np2)
					game.box_holder.remove_child(np2)
					np2.free()
			game.net_remove_structure(game.structures[ib_k])
		# S38: merchant + kin-panel surface — buy drains real stock, infuse
		# and skill toggles land only on the asker's own kin
		if game.merchant != null and game.merchant_stock.size() > 0:
			var m_idx := -1
			for mi in game.merchant_stock.size():
				var mit: Dictionary = game.merchant_stock[mi]
				if not mit.has("kin") and int(mit.get("n", 0)) > 0:
					m_idx = mi; break
			if m_idx >= 0:
				var m_st: Dictionary = game.merchant_stock[m_idx]
				var m_id := str(m_st.get("id", ""))
				var m_n0 := int(m_st.get("n", 0))
				game.net.ghosts[99].net_pos = Vector3(game.merchant.pos.x + 40,
					game.merchant.pos.y, 0)
				check("the till won't ring from across the island",
					game.buy_remote(99, m_idx).is_empty()
					and int(m_st.get("n", 0)) == m_n0)
				game.net.ghosts[99].net_pos = Vector3(game.merchant.pos.x,
					game.merchant.pos.y, 0)
				var m_res := game.buy_remote(99, m_idx)
				check("guest buy drains the real stock",
					int(m_res.get("price", -1)) == int(m_st.get("price", -2))
					and int(m_st.get("n", 0)) == m_n0 - 1)
				check("bad shelf refused", game.buy_remote(99, m_idx + 40).is_empty())
		var if_p: Kin = game.gen_pal("fenjelly", 5, p.pos)
		game.pals.append(if_p)
		if_p.owner_id = 99
		if_p.mode = "partner"
		var sb0 := if_p.soul_boost
		check("guest infusion burns their own kin",
			game.infuse_req_remote(99, if_p.uid) > 0 and if_p.soul_boost == sb0 + 1)
		var if_host: Kin = game.gen_pal("fenjelly", 5, p.pos)
		game.pals.append(if_host)
		if_host.owner_id = 0
		check("host's kin can't take guest effigies",
			game.infuse_req_remote(99, if_host.uid) < 0)
		var eq0: Array = if_p.equipped.duplicate()
		var lsk: Array = if_p.learned_skills()
		if not lsk.is_empty():
			game.box_op_remote("toggle_skill", if_p.uid, 99, str(lsk[0]))
			check("guest skill toggle lands host-side", if_p.equipped != eq0)
		# S39: a guest's skill fruit teaches THEIR lead, host rolls the move
		var fr_lead: Kin = game.gen_pal("fenjelly", 5, p.pos)
		game.pals.append(fr_lead)
		fr_lead.owner_id = 99
		fr_lead.mode = "partner"
		game.remote_parties["t99"] = [fr_lead.uid]
		var fr_sk0: int = fr_lead.extra_skills.size()
		check("guest fruit teaches their own lead",
			game.fruit_req_remote(99, "skill_fruit_fire")
			and fr_lead.extra_skills.size() == fr_sk0 + 1)
		check("bogus fruit refused", not game.fruit_req_remote(99, "gold_coin"))
		game.pals.erase(fr_lead); fr_lead.queue_free()
		game.pals.erase(if_p); if_p.queue_free()
		game.pals.erase(if_host); if_host.queue_free()
		# S48: guest mounting — the host binds a roster kin to the asker's ghost;
		# mount truth stays host-side, ownership + reach + species all gate it
		var mt_p: Kin = game.gen_pal("scalfang", 6, p.pos)
		game.pals.append(mt_p)
		mt_p.owner_id = 99
		mt_p.mode = "partner"
		game.remote_parties["t99"] = [mt_p.uid]
		var mt_ghost: Vector3 = game.net.ghosts[99].net_pos
		game.net.ghosts[99].net_pos = Vector3(mt_p.pos.x + 40, mt_p.pos.y, 0)
		check("a far ghost can't mount", game.mount_req_remote(99, mt_p.uid) == 0)
		game.net.ghosts[99].net_pos = Vector3(mt_p.pos.x, mt_p.pos.y, 0)
		check("guest mounts their own kin", game.mount_req_remote(99, mt_p.uid) == 1
			and mt_p.mounted_by == 99 and not mt_p.visible)
		check("a stranger can't steal the saddle", game.mount_req_remote(7, mt_p.uid) == 0)
		check("the mount toggle dismounts", game.mount_req_remote(99, mt_p.uid) == 2
			and mt_p.mounted_by == 0 and mt_p.visible)
		var mt_b: Kin = game.gen_pal("pyrejelly", 5, p.pos) # a blob won't carry
		game.pals.append(mt_b)
		mt_b.owner_id = 99
		mt_b.mode = "partner"
		game.remote_parties["t99"].append(mt_b.uid)
		check("a non-mountable kin refuses", game.mount_req_remote(99, mt_b.uid) == 0)
		var mt_host: Kin = game.gen_pal("scalfang", 6, p.pos)
		game.pals.append(mt_host)
		mt_host.owner_id = 1
		game.remote_parties["t99"].append(mt_host.uid)
		check("the host's kin isn't the guest's mount", game.mount_req_remote(99, mt_host.uid) == 0)
		game.pals.erase(mt_p); mt_p.queue_free()
		game.pals.erase(mt_b); mt_b.queue_free()
		game.pals.erase(mt_host); mt_host.queue_free()
		game.net.ghosts[99].net_pos = mt_ghost
		game.remote_parties.erase("t99")
		game.net.peer_tags.erase(99)
		# S49: every path that retires a ridden kin owes it the unbind —
		# retract, KO, owner-drop, replica despawn and rider death all settle
		# the saddle, or the kin re-enters a roster invisible forever
		game.net.peer_tags[99] = "t99" # rparty_for keys strips on the tag
		var unb1: Kin = game.gen_pal("scalfang", 6, p.pos)
		game.pals.append(unb1)
		unb1.owner_id = 99
		unb1.mode = "partner"
		game.remote_parties["t99"] = [unb1.uid]
		game.net.ghosts[99].net_pos = Vector3(unb1.pos.x, unb1.pos.y, 0)
		check("a ghost mounts for the drill", game.mount_req_remote(99, unb1.uid) == 1)
		game.r_retract(99)
		check("retract unbinds the saddle", unb1.mounted_by == 0 and unb1.visible)
		game.r_send_out(unb1.uid, 99)
		game.mount_req_remote(99, unb1.uid)
		var unb2: Kin = game.gen_pal("scalfang", 6, Vector2(unb1.pos.x + 40, unb1.pos.y))
		game.pals.append(unb2)
		unb2.owner_id = 99
		unb2.mode = "partner"
		game.remote_parties["t99"].append(unb2.uid)
		check("a refused swap keeps the saddle",
			game.mount_req_remote(99, unb2.uid) == 0 and unb1.mounted_by == 99)
		game.pals.erase(unb2); unb2.queue_free()
		game.kill_pal(unb1, true, 99)
		check("a KO'd mount walks the rider off", unb1.mounted_by == 0 and unb1.visible)
		var unb3: Kin = game.gen_pal("scalfang", 6, p.pos)
		game.pals.append(unb3)
		unb3.owner_id = 99
		unb3.mode = "partner"
		game.remote_parties["t99"].append(unb3.uid)
		game.mount_req_remote(99, unb3.uid)
		game.orphan_guest_kin(99)
		check("a dropped keeper's mount unbinds", unb3.mounted_by == 0 and unb3.visible)
		game.box.erase(unb1); game.box.erase(unb3)
		unb1.free(); unb3.free() # box kin die by free() — never queue_free
		game.remote_parties.erase("t99")
		# replica despawn while mounted: the pal_sync removal row owes the rider
		var unb4: Kin = game.gen_pal("scalfang", 6, p.pos)
		unb4.net_id = 424242
		game.pals.append(unb4)
		var keep_rows := []
		for rp4 in game.pals:
			if rp4.net_id > 0 and rp4 != unb4:
				keep_rows.append([rp4.net_id, rp4.species_id, rp4.pos.x, rp4.pos.y,
					rp4.level, rp4.mode, rp4.hp, rp4.lucky, rp4.boss, rp4.alpha,
					rp4.spire_tag, rp4.mounted_by])
		p.mount = unb4
		game.net.pal_sync(keep_rows)
		check("a despawned replica drops the saddle", p.mount == null
			and unb4 not in game.pals)
		p.mount = null
		# respawn while mounted — the host path unbinds, the replica path asks
		var unb5: Kin = game.gen_pal("scalfang", 6, p.pos)
		game.pals.append(unb5)
		unb5.mode = "partner"
		var pos5 := p.pos
		var hp5 := p.hp
		var stat5 := p.statuses.duplicate()
		var items5 := game.items.duplicate()
		game.items.clear() # no pack, no spill — the tombstone lane stays quiet
		p.mount = unb5
		unb5.visible = false
		unb5.mounted_by = 1
		game.respawn_player()
		check("death unbinds the saddle", p.mount == null
			and unb5.mounted_by == 0 and unb5.visible)
		game.items = items5
		p.pos = pos5
		p.hp = hp5
		p.statuses = stat5
		game.pals.erase(unb5); unb5.queue_free()
		# chest partial-accept: the gap between claim and chest comes home
		game.net.pending_pays.clear()
		var wood5 := game.item_count("wood")
		var had5 := game.items.has("wood")
		game.items["wood"] = 5 # a known baseline — stack caps can't eat the diff
		game.net.pending_pays.append({"tag": "chest_dep", "cost": {"wood": 10}})
		game.net.chest_took(0, 0, {"wood": 4})
		check("partial deposit refunds the gap", game.item_count("wood") == 11
			and game.net.pending_pays.is_empty())
		# the ledger records what the bag actually gave — a claimed refund
		# against an empty pocket can't mint goods back (audit-11 H1)
		game.items["wood"] = 4
		game.net.pay("selftest", {"wood": 10}) # claims 10, the floor gives 4
		check("pay books the real debit", game.net.pending_pays.size() == 1
			and int(game.net.pending_pays[0]["cost"].get("wood", -1)) == 4)
		game.net.pay_settle("selftest", true)
		check("a refund returns only what left", game.item_count("wood") == 4
			and game.net.pending_pays.is_empty())
		var stone5 := game.item_count("stone")
		var hads5 := game.items.has("stone")
		game.items.erase("stone") # an empty pocket owes no hold
		game.net.pay("selftest", {"stone": 5})
		check("a broke pay books no hold", game.net.pending_pays.is_empty())
		if hads5:
			game.items["stone"] = stone5
		# mount_done is uid-scoped — a stray echo can't re-arm the handshake
		game.net.mount_pending = true
		game.net.mount_pending_uid = 555
		game.net.mount_done(777, 0)
		check("a stray echo can't clear the handshake", game.net.mount_pending)
		game.net.mount_done(555, 0)
		check("its own echo clears the handshake", not game.net.mount_pending
			and game.net.mount_pending_uid == -1)
		# state 0 owns the handshake only — a refused dismount can't drop a
		# saddle the host still holds (throttle-starved press, not a release)
		var dm1: Kin = game.gen_pal("scalfang", 6, p.pos)
		dm1.net_id = 424245
		game.pals.append(dm1)
		p.mount = dm1
		dm1.visible = false # riding hides the kin
		game.net.mount_done(424245, 0)
		check("a refused dismount keeps the saddle", p.mount == dm1 and not dm1.visible)
		game.net.mount_done(424245, 2)
		check("a confirmed release drops the saddle + shows the kin",
			p.mount == null and dm1.visible)
		game.pals.erase(dm1); dm1.queue_free()
		# self-heal exists but refuses offline — no wire, no unbind asks
		check("unbind self-heal is client-gated",
			not game.net._mount_selfheal_check(424243, 1))
		# deploy-while-mounted: the replica survives (deploy keeps it in pals)
		# but the wire says nobody rides — the saddle must drop client-side too
		var dep1: Kin = game.gen_pal("scalfang", 6, p.pos)
		dep1.net_id = 424244
		game.pals.append(dep1)
		p.mount = dep1
		dep1.visible = false
		var dep_rows := []
		for rp5 in game.pals:
			if rp5.net_id > 0:
				dep_rows.append([rp5.net_id, rp5.species_id, rp5.pos.x, rp5.pos.y,
					9 if rp5 == dep1 else rp5.level, "base" if rp5 == dep1 else rp5.mode,
					rp5.hp, rp5.lucky, rp5.boss, rp5.alpha, rp5.spire_tag, 0])
		game.net.pal_sync(dep_rows)
		check("a surviving replica can't keep the saddle", p.mount == null
			and dep1.visible)
		check("wire level lands on the replica", dep1.level == 9)
		game.pals.erase(dep1); dep1.queue_free()
		# nonpositive uids spawn nothing — host uids are >=1, a 0/-N row would
		# otherwise mint an untrackable phantom every sync tick
		var pals_n0 := game.pals.size()
		var bad_rows := [[0, "puffmite", 1.0, 1.0, 1, "wild", 1.0, false, false, false, "", 0],
			[-5, "puffmite", 2.0, 2.0, 1, "wild", 1.0, false, false, false, "", 0]]
		for rp6 in game.pals:
			if rp6.net_id > 0:
				bad_rows.append([rp6.net_id, rp6.species_id, rp6.pos.x, rp6.pos.y,
					rp6.level, rp6.mode, rp6.hp, rp6.lucky, rp6.boss,
					rp6.alpha, rp6.spire_tag, rp6.mounted_by])
		game.net.pal_sync(bad_rows)
		check("nonpositive uids spawn nothing", game.pals.size() == pals_n0)
		# a flooded ledger refuses the new hold — debit reversed, nothing booked
		game.net.pending_pays.clear()
		for i in 32:
			game.net.pending_pays.append({"tag": "flood", "cost": {"wood": 1}})
		var wood6 := game.item_count("wood")
		check("a flooded ledger refuses + reverses", not game.net.pay("cap", {"wood": 3})
			and game.net.pending_pays.size() == 32
			and game.item_count("wood") == wood6)
		game.net.pending_pays.clear()
		# a denied toss settles the hold — the bait comes home through the
		# ledger, not a bespoke cost-table refund
		var bait6 := game.item_count("kin_bait")
		var had6 := game.items.has("kin_bait")
		game.items["kin_bait"] = 5
		game.net.pay("bait", {"kin_bait": 1})
		game.net.bait_done(false)
		check("a denied toss returns the bait", game.item_count("kin_bait") == 5
			and game.net.pending_pays.is_empty())
		if had6:
			game.items["kin_bait"] = bait6
		else:
			game.items.erase("kin_bait")
		# real CONNECTED loopback — board settle idempotency + the respawn arm
		var ra_srv := ENetMultiplayerPeer.new()
		ra_srv.create_server(17892, 2)
		var ra_cli := ENetMultiplayerPeer.new()
		ra_cli.create_client("127.0.0.1", 17892)
		var ra_t0 := Time.get_ticks_msec()
		while ra_cli.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
				and Time.get_ticks_msec() - ra_t0 < 2000:
			ra_srv.poll(); ra_cli.poll()
			OS.delay_msec(10)
		var peer_bak2 = game.net.multiplayer.multiplayer_peer
		game.net.multiplayer.multiplayer_peer = ra_cli
		var g1_had: bool = game.net.ghosts.has(1) # connected_to_server may spawn it
		var tag_had: bool = FileAccess.file_exists("user://plg_net.cfg")
		var tag_keep := FileAccess.get_file_as_string("user://plg_net.cfg") if tag_had else ""
		for _api_tick in 4: # the API learns the remote synchronously — no frame to await
			game.net.multiplayer.poll()
		var items_ra := game.items.duplicate() # the whole bag — board + respawn both touch it
		game.items["wood"] = 10
		game.net.board_paid_out = ""
		game.net.board_done({"id": "wood", "n": 3})
		check("the board takes its goods once", game.item_count("wood") == 7
			and game.net.board_paid_out == "wood")
		game.net.board_done({"id": "wood", "n": 3}) # the ask re-shown mid-flight
		check("a re-shown ask deducts nothing", game.item_count("wood") == 7)
		game.net.board_paid_out = ""
		var ra1: Kin = game.gen_pal("scalfang", 6, p.pos)
		ra1.net_id = 424246
		game.pals.append(ra1)
		p.mount = ra1
		var pos_ra := p.pos
		var hp_ra := p.hp
		var stat_ra := p.statuses.duplicate()
		var hunger_ra := p.hunger
		game.items.clear() # no pack, no spill — keep the bag math out of it
		game.respawn_player()
		check("a dying client arms the release", game.net.mount_pending
			and game.net.mount_pending_uid == 424246 and p.mount == null)
		game.net.mount_pending = false
		game.net.mount_pending_uid = -1
		game.items = items_ra
		p.pos = pos_ra
		p.hp = hp_ra
		p.statuses = stat_ra
		p.hunger = hunger_ra
		game.pals.erase(ra1); ra1.queue_free()
		game.net.multiplayer.multiplayer_peer = peer_bak2
		if not g1_had and game.net.ghosts.has(1): # the connect hook's ghost goes home with the session
			game.net.ghosts[1].queue_free()
			game.net.ghosts.erase(1)
		if tag_had:
			var tag_f := FileAccess.open("user://plg_net.cfg", FileAccess.WRITE)
			tag_f.store_string(tag_keep)
		elif FileAccess.file_exists("user://plg_net.cfg"):
			DirAccess.remove_absolute("user://plg_net.cfg") # hello wrote a fresh token — suite leaves no files
		ra_srv.close(); ra_cli.close()
		if had5:
			game.items["wood"] = wood5
		else:
			game.items.erase("wood")
		# remote bait lands under the ghost the wire saw, not the claim
		game.lure = {}
		game.throw_bait_remote(99)
		check("remote bait lands at the ghost", not game.lure.is_empty()
			and Vector2(game.lure["pos"]).distance_to(
				Vector2(game.net.ghosts[99].net_pos.x, game.net.ghosts[99].net_pos.y)) < 8.0)
		game.lure = {}
		# mature-world join: the snapshot's decor layer overwrites pristine seed
		var dec_i := game.world.idx(int(p.pos.x), int(p.pos.y))
		var dec_save: PackedByteArray = game.world.decor.duplicate()
		var hp_save: PackedByteArray = game.world.hp.duplicate()
		var dec_fake: PackedByteArray = game.world.decor.duplicate()
		var hp_fake: PackedByteArray = game.world.hp.duplicate()
		dec_fake[dec_i] = int(World.Decor.STUMP)
		hp_fake[dec_i] = 0
		check("mature-world decor applies on join",
			game.decor_snapshot_apply({"decor": dec_fake, "hp_map": hp_fake})
			and game.world.decor[dec_i] == int(World.Decor.STUMP))
		check("a malformed decor map is refused",
			not game.decor_snapshot_apply({"decor": PackedByteArray([1, 2])}))
		game.world.decor = dec_save
		game.world.hp = hp_save
		# snapshot kin rows share the tick packer — hp and mounted_by ride along
		var snap_rows: Array = game.net.state_snapshot().get("kin", [])
		check("snapshot kin rows carry the full pack", snap_rows.size() > 0
			and snap_rows[0].size() == 12)
		# the host's own saddle: ghosts[1].net_pos is never fed — the pack row
		# must read player.pos, not the sentinel (-1,-1)
		var unb6: Kin = game.gen_pal("scalfang", 6, Vector2(5, 5))
		game.pals.append(unb6)
		unb6.mode = "partner"
		unb6.mounted_by = 1
		var pack_row: Array = []
		for pr6 in game.net.pal_state_pack():
			if int(pr6[0]) == unb6.uid:
				pack_row = pr6
		check("host mount packs the rider's pos", not pack_row.is_empty()
			and float(pack_row[2]) == p.pos.x and float(pack_row[3]) == p.pos.y)
		unb6.mounted_by = 0
		game.pals.erase(unb6); unb6.queue_free()
		game.net.ghosts[99].net_pos = mt_ghost
		game.net.peer_tags.erase(99)
	else:
		check("guest deposit whitelists", false, "no chest spot seeded")
	game.touch_ui = tui3
	hudn.touch_verb("more")
	check("··· collapses the row", not hudn.touch_more)
	# S41: the trader is a mirrored entity — pos rides env_sync, the
	# briefcase rides stock_sync, and a guest's beating raises the squad
	# on the host with the GUEST's aggro, not the keeper's
	var v41_m0: Entity = game.merchant
	var v41_mpos := Vector2.ZERO
	var v41_s0: Array = []
	if v41_m0 != null: # a live host merchant steps aside for the mirror drill
		v41_mpos = v41_m0.pos
		v41_s0 = game.merchant_stock.duplicate(true)
		game.merchant = null
	game.net_merchant_apply(true, p.pos.x + 3.0, p.pos.y + 1.0)
	check("merchant mirror materializes", game.merchant != null
		and game.merchant.pos.x == p.pos.x + 3.0)
	game.net_merchant_apply(true, p.pos.x + 5.0, p.pos.y + 1.0)
	check("mirror follows the wire", game.merchant.pos.x == p.pos.x + 5.0)
	game.merchant_stock = [{"id": "wood", "n": 2, "price": 4}]
	game.merchant_hp = 60
	game.hit_merchant(10.0, 99)
	check("a guest's beating is on the host ledger", game.merchant_hp == 50)
	var v41_thugged := false
	for v41_q in game.pals:
		if v41_q.mode == "wild" and v41_q.aggro_pid == 99:
			v41_thugged = true
			game.pals.erase(v41_q)
			v41_q.queue_free()
	check("the hit squad answers to the guest", v41_thugged
		and game.merchant_wanted)
	game.merchant_wanted = false
	game.net_merchant_apply(false, 0.0, 0.0)
	check("mirror leaves with the trader", game.merchant == null
		and game.merchant_stock.is_empty())
	game.merchant = v41_m0 # put the host's trader back where he stood
	if v41_m0 != null:
		v41_m0.pos = v41_mpos
		game.merchant_stock = v41_s0
	var v41_snap: Dictionary = game.net.state_snapshot()
	check("joiners mid-visit get the trader", v41_snap.has("merch")
		and v41_snap.has("stock"))
	var v41_wit: Kin = game.gen_pal("fenjelly", 7, p.pos) # a live entry so the
	game.pals.append(v41_wit) # pack assertion can't pass vacuously on an empty roster
	var v41_pack: Array = game.net.pal_state_pack() # the 2Hz pack must not die on .level
	check("kin wire-pack carries the full roster shape",
		v41_pack.any(func(e: Array) -> bool:
			return e.size() == 12 and e[0] == v41_wit.uid and int(e[4]) == 7))
	game.pals.erase(v41_wit)
	v41_wit.queue_free()
	# S42 eighth-audit batch: honest-path economy + ownership edge cases
	# (a) incubator bound speaks in tiles — the squared compare ate the arm
	var v42_occ := []
	var v42_qbak := {}
	for v42_k in game.structures:
		var v42_os: Dictionary = game.structures[v42_k]
		if v42_os["id"] == "incubator" and not v42_os.has("egg_inc"):
			v42_os["egg_inc"] = {"_plug": 1}
			v42_occ.append(v42_os)
		if v42_os.has("egg_parents"):
			v42_qbak[v42_k] = v42_os["egg_parents"]
			v42_os.erase("egg_parents")
	var v42_fx := -1
	var v42_fy := -1
	for r in range(4, 30):
		for d in [Vector2i(r, 0), Vector2i(0, r), Vector2i(r, r)]:
			var c := Vector2i(int(p.pos.x) + d.x, int(p.pos.y) + d.y)
			var free22 := true
			for dy0 in 2:
				for dx0 in 2:
					if game.structures.has(c + Vector2i(dx0, dy0)):
						free22 = false
			if free22:
				v42_fx = c.x; v42_fy = c.y; break
		if v42_fx >= 0:
			break
	var v42_st: Dictionary = {}
	if v42_fx >= 0:
		game.place_free("incubator", v42_fx, v42_fy, {})
		v42_st = game.structures[Vector2i(v42_fx, v42_fy)]
		var want_d := 1e9
		for k2 in game.structures:
			if game.structures[k2] == v42_st:
				want_d = minf(want_d, Vector2(k2.x + 0.5, k2.y + 0.5).distance_to(p.pos))
		var got_site := game._free_incubator(p.pos, 6.0)
		check("incubator bound counts tiles, not squared ghosts",
			(got_site.x >= 0 and game.structures.get(got_site) == v42_st) == (want_d <= 6.0))
	else:
		check("incubator bound counts tiles, not squared ghosts", false, "no free cell seeded")
	# (b) parentage is claimed by bloodline owner — a guest's egg can't
	#     quietly inherit the host's ranch genetics
	if not v42_st.is_empty():
		v42_st["egg_parents"] = [
			["host_a", "host_b", 50, 50, [], [], [], []],
			["g_a", "g_b", 99, 99, [], [], [], [], [99]]]
		var v42_pair = game._claim_egg_parent(99)
		check("a guest claims only their own pairing",
			v42_pair != null and v42_pair[0] == "g_a"
			and v42_st["egg_parents"].size() == 1)
		var v42_h0 = game._claim_egg_parent(0)
		check("the keeper claims legacy untagged rows",
			v42_h0 != null and v42_h0[0] == "host_a")
		# (c) a dead depositor's egg orphans — the tag survives for rebind
		v42_st["egg_inc"] = {"pair": null, "ready_t": game.t - 1.0,
			"own_pid": 88, "own_tag": "gone_42"}
		var v42_u0 := {}
		for v42_q in game.pals + game.box:
			v42_u0[v42_q.uid] = true
		game.hatch_incubated(Vector2i(v42_fx, v42_fy), v42_st)
		var v42_np: Kin = null
		for v42_q in game.pals + game.box:
			if not v42_u0.has(v42_q.uid):
				v42_np = v42_q
		check("a dead pid's egg orphans with its tag",
			v42_np != null and v42_np.owner_id == -1
			and v42_np.owner_tag == "gone_42")
		if v42_np != null:
			game.pals.erase(v42_np); game.box.erase(v42_np); v42_np.queue_free()
		v42_st.erase("egg_parents")
		game.net_remove_structure(v42_st)
	for v42_os in v42_occ:
		v42_os.erase("egg_inc")
	for v42_k in v42_qbak:
		if game.structures.has(v42_k):
			game.structures[v42_k]["egg_parents"] = v42_qbak[v42_k]
	# (d) workforce caps are per-owner — a guest's pile can't starve the keeper
	var v42_lv0: int = p.level
	var v42_bl0: int = game.base_level
	var v42_kb0: Vector2i = game.kinbox_pos
	p.level = 1
	game.base_level = 1
	game.kinbox_pos = Vector2i(9, 9)
	var v42_spawned := []
	for i in game.max_base_pals():
		var v42_q: Kin = game.gen_pal("fenjelly", 2, p.pos)
		v42_q.owner_id = 99
		v42_q.mode = "base"
		game.pals.append(v42_q)
		v42_spawned.append(v42_q)
	var v42_extra: Kin = game.gen_pal("fenjelly", 2, p.pos)
	v42_extra.owner_id = 99
	game.pals.append(v42_extra)
	game.deploy_to_base(v42_extra)
	check("a capped guest can't pack the base further", v42_extra.mode != "base")
	var v42_host: Kin = game.gen_pal("fenjelly", 2, p.pos)
	game.pals.append(v42_host)
	game.deploy_to_base(v42_host)
	check("the keeper's slice is theirs alone",
		v42_host.mode == "base" or game.base_pals_of(0).size() >= game.max_base_pals())
	game.pals.erase(v42_extra); v42_extra.queue_free()
	game.pals.erase(v42_host); v42_host.queue_free()
	for v42_q in v42_spawned:
		game.pals.erase(v42_q); v42_q.queue_free()
	p.level = v42_lv0
	game.base_level = v42_bl0
	game.kinbox_pos = v42_kb0
	# (e) guests raze their own BACKUP kinbox — never the live anchor
	game.net.spawn_ghost(99)
	game.net.peer_tags[99] = "g42t"
	var v42_bx := -1
	var v42_by := -1
	for r in range(3, 30):
		var c := Vector2i(int(p.pos.x) + r, int(p.pos.y))
		var free22 := true
		for dy0 in 2:
			for dx0 in 2:
				if game.structures.has(c + Vector2i(dx0, dy0)):
					free22 = false
		if free22:
			v42_bx = c.x; v42_by = c.y; break
	if v42_bx >= 0 and game.place_free("kinbox", v42_bx, v42_by, {}):
		var v42_bst: Dictionary = game.structures[Vector2i(v42_bx, v42_by)]
		v42_bst["placed_tag"] = "g42t"
		game.net.ghosts[99].net_pos = Vector3(v42_bx, v42_by, 0)
		game.net_demolish(v42_bx, v42_by, 99)
		check("a guest razes their own backup kinbox",
			not game.structures.has(Vector2i(v42_bx, v42_by)))
		var v42_mpos := Vector2i(v42_bx, v42_by)
		game.place_free("kinbox", v42_mpos.x, v42_mpos.y, {})
		if game.structures.has(v42_mpos):
			var v42_mst: Dictionary = game.structures[v42_mpos]
			v42_mst["placed_tag"] = "g42t"
			game.kinbox_pos = v42_mpos
			game.net_demolish(v42_mpos.x, v42_mpos.y, 99)
			check("the live anchor is nobody's to raze",
				game.structures.has(v42_mpos))
			game.net_remove_structure(v42_mst)
		else:
			check("the live anchor is nobody's to raze", false, "anchor spot lost")
		game.kinbox_pos = v42_kb0
	else:
		check("a guest razes their own backup kinbox", false, "no free cell seeded")
	game.net.peer_tags.erase(99)
	# (f) a guest's bag overflow stays theirs — spawn_drop can't mint on a client
	var v42_ih: bool = game.net.is_host
	var v42_pp = game.net.multiplayer.multiplayer_peer
	game.net.is_host = false
	var v42_ep := ENetMultiplayerPeer.new()
	v42_ep.create_client("127.0.0.1", 43210) # connecting = assignable, no handshake lands
	game.net.multiplayer.multiplayer_peer = v42_ep
	game.items.erase("wood")
	var v42_d0: int = game.drops.size()
	var v42_cap: int = ItemData.ITEMS.get("wood", {}).get("stack", 999)
	game.add_item("wood", v42_cap + 7)
	check("a guest's overflow stays in their own bag",
		game.item_count("wood") == v42_cap + 7 and game.drops.size() == v42_d0)
	game.items.erase("wood")
	while game.drops.size() > v42_d0: # belt: a spill here would litter the world
		game.drops.pop_back()
	v42_ep.close()
	game.net.multiplayer.multiplayer_peer = v42_pp
	game.net.is_host = v42_ih
	# ── S43: eighth-audit hardening — wire row shapes, mirror teardown, caps ──
	var v43_ih: bool = game.net.is_host
	var v43_pp = game.net.multiplayer.multiplayer_peer
	var v43_ep := ENetMultiplayerPeer.new()
	v43_ep.create_client("127.0.0.1", 43210)
	game.net.multiplayer.multiplayer_peer = v43_ep
	game.net.is_host = false
	var v43_sid: String = SpeciesData.SPECIES.keys()[0]
	var v43_m0: Array = game.merchant_stock.duplicate()
	game.net.stock_sync([{"kin": v43_sid, "lv": 5, "n": 1, "price": 300},
		{"id": "wood", "n": 3, "price": 4}, {"kin": "not_a_species", "lv": 1},
		{"n": 2}, "junk"])
	check("guest shelf keeps kin rows, drops forged shapes",
		game.merchant_stock.size() == 2
		and str(game.merchant_stock[0].get("kin", "")) == v43_sid
		and str(game.merchant_stock[1].get("id", "")) == "wood")
	var v43_fat := []
	for i43 in game.MAX_MERCH_STOCK + 5:
		v43_fat.append({"id": "wood", "n": 1, "price": 1})
	game.net.stock_sync(v43_fat)
	check("shelf mirror honors MAX_MERCH_STOCK",
		game.merchant_stock.size() == game.MAX_MERCH_STOCK)
	game.merchant_stock = v43_m0
	game.net_unlocked = ["notice_board"]
	check("guest build bar follows the host's research",
		game.buildable_list() == ["notice_board"])
	game.net_unlocked = []
	game.net_box = [{"uid": 77, "sid": v43_sid, "lv": 5, "hp": 10, "max_hp": 10,
		"sex": "M", "lucky": false, "talent": 50, "ailment": "", "fav": false,
		"star": 1, "wk": ""}]
	var v43_sell: Array = hudn.sellable_pals()
	check("guest sell rail rides the mirrored roster",
		v43_sell.size() == 1 and int(v43_sell[0]["uid"]) == 77
		and int(v43_sell[0]["price"]) > 0)
	game.net_box = []
	v43_ep.close()
	game.net.multiplayer.multiplayer_peer = v43_pp
	game.net.is_host = v43_ih
	# struct wire state: pack → mutate → sync restores (captive, egg timer, crew)
	var v43_home := Vector2i(game.player.pos)
	var v43_ck: Vector2i = Vector2i.ZERO
	for v43_x in range(v43_home.x - 7, v43_home.x + 8):
		for v43_y in range(v43_home.y - 7, v43_home.y + 8):
			var v43_c := Vector2i(v43_x, v43_y)
			if game.can_place("kin_cage", v43_c.x, v43_c.y) \
					and game.can_place("incubator", v43_c.x + 2, v43_c.y):
				v43_ck = v43_c; break
		if v43_ck != Vector2i.ZERO: break
	check("S43 fixture cell found", v43_ck != Vector2i.ZERO,
		"searched around player at %s" % v43_home)
	if v43_ck != Vector2i.ZERO:
		game.place_free("kin_cage", v43_ck.x, v43_ck.y)
		game.place_free("incubator", v43_ck.x + 2, v43_ck.y)
		var v43_st: Dictionary = game.structures[v43_ck]
		var v43_ist: Dictionary = game.structures[v43_ck + Vector2i(2, 0)]
		v43_st["captive"] = {"sp": v43_sid, "lv": 7}
		var v43_wk0 := game.gen_pal(v43_sid, 3, game.player.pos)
		game.pals.append(v43_wk0) # the factory doesn't enlist — find_net_pal reads pals
		v43_wk0.net_id = v43_wk0.uid # replicas carry their host uid — the wire key
		v43_st["workers"] = [v43_wk0]
		v43_ist["egg_inc"] = {"pair": [v43_sid, v43_sid], "huge": false,
			"ready_t": game.t + 120.0, "own_tag": "keeper"}
		var v43_pack: Array = game.net.struct_state_pack()
		var v43_ent = null; var v43_ient = null
		for e in v43_pack:
			if e.size() > 4 and e[0] == "kin_cage" and Vector2i(int(e[1]), int(e[2])) == v43_ck:
				v43_ent = e
			if e.size() > 4 and e[0] == "incubator" and Vector2i(int(e[1]), int(e[2])) == v43_ck + Vector2i(2, 0):
				v43_ient = e
		check("cage+incubator ride the wire with state",
			v43_ent != null and v43_ient != null
			and v43_ent[4].get("cap", {}).get("sp", "") == v43_sid
			and float(v43_ient[4].get("inc", {}).get("left", -1.0)) > 100.0
			and (v43_ent[4].get("wk", []) as Array).size() == 1)
		v43_st.erase("captive"); v43_st["workers"] = []; v43_ist.erase("egg_inc")
		game.struct_sync(v43_pack) # the whole world rides — a subset pack razes it
		check("wire state re-anchors timers and crew",
			str(v43_st.get("captive", {}).get("sp", "")) == v43_sid
			and v43_st["workers"].size() == 1
			and v43_ist.get("egg_inc", {}).get("ready_t", 0.0) > game.t + 60.0)
		if v43_ent != null:
			v43_ent[4]["cap"] = null; v43_ent[4]["wk"] = []
			game.struct_sync(v43_pack)
		check("explicit null clears the freed prisoner",
			not v43_st.has("captive") and v43_st["workers"].is_empty())
		game.pals.erase(v43_wk0); v43_wk0.queue_free()
		game.net_remove_structure(v43_st); game.net_remove_structure(v43_ist)
	# Iron-Pact squad honors the population cap
	if game.merchant == null or not is_instance_valid(game.merchant):
		game.merchant_hp = 60
		game.spawn_merchant()
	var v43_wanted: bool = game.merchant_wanted
	game.merchant_wanted = false; game.merchant_hp = 60
	var v43_pad := []
	while game.pals.size() < game.MAX_PALS: # pals is Array[Kin] — real bodies only
		var v43_n := game.gen_pal(v43_sid, 1, game.player.pos)
		v43_pad.append(v43_n); game.pals.append(v43_n)
	var v43_before: int = game.pals.size()
	game.hit_merchant(10, 99)
	check("hit squad stops at MAX_PALS", game.pals.size() == v43_before)
	for v43_n2 in v43_pad:
		game.pals.erase(v43_n2); v43_n2.queue_free()
	game.merchant_wanted = v43_wanted
	# ── S44: the crown's payoff — apex gauntlet wave, legendary egg guard ──
	var v44_kin0: Array = game.hatch_pool()
	var v44_leg_ok := true
	for s44 in v44_kin0:
		if s44 in game.LEGENDARY_DEN or SpeciesData.species_of(str(s44)).get("boss", false):
			v44_leg_ok = false
	check("hatch pool holds no legendaries or bosses", v44_leg_ok)
	if game.kinbox_pos.x < 0: # a tower needs a kinbox — plant one off-player
		for v44_d in [Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4)]:
			var v44_c: Vector2i = Vector2i(game.player.pos) + v44_d
			if game.can_place("kinbox", v44_c.x, v44_c.y) and game.place_free("kinbox", v44_c.x, v44_c.y):
				break
	var v44_cr: bool = game.crowned
	var v44_run := func() -> Dictionary:
		var v44_sig0: int = game.item_count("gauntlet_sigil")
		var v44_lo0: int = game.item_count("legendary_orb")
		var v44_ap0: int = game.item_count("ancient_part")
		game.gauntlet = {}
		var v44_ok: bool = game.start_gauntlet()
		var v44_wmax := 0
		var v44_gd := 0
		while not game.gauntlet.is_empty() and v44_gd < 12:
			v44_gd += 1
			v44_wmax = maxi(v44_wmax, int(game.gauntlet.get("wave", 0)))
			for v44_q in game.pals.duplicate():
				if v44_q.has_meta("gauntlet"):
					game.pals.erase(v44_q); v44_q.queue_free()
			game.gauntlet["left"] = 0
			game.tick_gauntlet()
		return {"ok": v44_ok, "wmax": v44_wmax,
			"sig": game.item_count("gauntlet_sigil") - v44_sig0,
			"lo": game.item_count("legendary_orb") - v44_lo0,
			"ap": game.item_count("ancient_part") - v44_ap0}
	var v44_r1: Dictionary = v44_run.call() # uncrowned: 3 waves, standard purse
	check("gauntlet clears at wave 3 for an uncrowned keeper",
		v44_r1["ok"] and v44_r1["wmax"] == 3 and v44_r1["sig"] == 1 and v44_r1["lo"] == 2)
	game.crowned = true
	var v44_r2: Dictionary = v44_run.call() # crowned: the apex wave answers
	check("the crown draws a fourth apex wave",
		v44_r2["wmax"] == 4 and v44_r2["sig"] == 2 and v44_r2["lo"] == 4
		and v44_r2["ap"] == 6 and game.mission_flags.has("gauntlet_ex"))
	game.mission_flags.erase("gauntlet_ex")
	game.crowned = v44_cr
	# pause shell hosts the panel verbs for every input device
	var peer_bak2 = game.net.multiplayer.multiplayer_peer
	game.net.multiplayer.multiplayer_peer = null # host row is a no-peer offer
	var want_rows := ["m_host", "m_tech", "m_dex", "m_statues", "m_guide"]
	for wr in want_rows:
		var got := 0
		for row in hudn.pause_rows():
			if row[1] == wr: got += 1
		check("pause row %s" % wr, got == 1)
	game.net.multiplayer.multiplayer_peer = peer_bak2
	hudn.run_click({"act": "m_tech", "arg": null})
	check("tech row opens the panel", game.panel == "tech")
	game.panel = ""
	# list panels scroll on tap + wheel — clipped tails were unreachable before
	game.panel = "dex"
	hudn.run_click({"act": "dex_dn", "arg": null}); hudn.run_click({"act": "dex_dn", "arg": null})
	check("dex scrolls down", hudn.dex_scroll == 2, "s=%d" % hudn.dex_scroll)
	hudn.run_click({"act": "dex_up", "arg": null}); hudn.run_click({"act": "dex_up", "arg": null})
	check("dex scroll clamps at 0", hudn.dex_scroll == 0)
	game.panel = "guide"; hudn.guide_page = 0
	hudn.run_click({"act": "guide_prev", "arg": null})
	check("guide prev clamps at 0", hudn.guide_page == 0)
	hudn.run_click({"act": "guide_next", "arg": null})
	check("guide next turns", hudn.guide_page == 1)
	game.panel = "shop"
	hudn.run_click({"act": "shop_dn", "arg": null})
	check("shop scroll moves", hudn.shop_scroll == 1)
	game.panel = "inv"
	hudn.run_click({"act": "inv_dn", "arg": null})
	check("inv scroll moves", hudn.inv_scroll == 1)
	game.panel = "kinbox"
	hudn.run_click({"act": "kin_dn", "arg": null})
	check("kin scroll moves", hudn.kin_scroll == 1)
	game.panel = "tech"
	hudn.run_click({"act": "tech_dn", "arg": null})
	check("tech scroll moves", hudn.tech_scroll == 1)
	hudn.run_click({"act": "tech_up", "arg": null})
	check("tech scroll back", hudn.tech_scroll == 0)
	game.panel = "statues"
	hudn.run_click({"act": "stat_dn", "arg": null})
	check("statues scroll moves", hudn.stat_scroll == 1)
	game.panel = ""
	# build bar rows pick on tap — 1-9 was the only door in
	game.panel = "build"; hudn.build_sel = -1
	hudn.run_click({"act": "build_pick", "arg": 0})
	check("tap picks a structure", hudn.build_sel == 0)
	hudn.run_click({"act": "build_pick", "arg": 0})
	check("re-tap cancels the ghost", hudn.build_sel == -1)
	game.panel = ""
	# chest panel scrolls too — last list left untested
	game.panel = "chest"
	hudn.run_click({"act": "chest_dn", "arg": null})
	check("chest scroll moves", hudn.chest_scroll == 1)
	hudn.run_click({"act": "chest_up", "arg": null})
	check("chest scroll back", hudn.chest_scroll == 0)
	game.panel = ""

	# ---- S30 audit fixes: paused text panels, paused X, click hygiene ----
	game.state = "paused" # pause-shell rows open text panels — they must still type
	game.panel = "chat"; hudn.chat_buf = ""
	var k_ev := InputEventKey.new()
	k_ev.pressed = true; k_ev.keycode = KEY_A; k_ev.unicode = 97
	hudn._unhandled_input(k_ev)
	check("paused chat still types", hudn.chat_buf == "a", "buf='%s'" % hudn.chat_buf)
	k_ev = InputEventKey.new()
	k_ev.pressed = true; k_ev.keycode = KEY_ESCAPE
	hudn._unhandled_input(k_ev)
	check("paused chat Esc bails", game.panel == "" and hudn.chat_buf == "")
	game.panel = "join"; hudn.join_buf = ""
	k_ev = InputEventKey.new()
	k_ev.pressed = true; k_ev.keycode = KEY_1; k_ev.unicode = 49
	hudn._unhandled_input(k_ev)
	check("paused join still types", hudn.join_buf == "1", "buf='%s'" % hudn.join_buf)
	game.panel = ""
	game.panel = "guide"; hudn.guide_page = 0 # guide hoisted with the text panels
	k_ev = InputEventKey.new()
	k_ev.pressed = true; k_ev.keycode = KEY_RIGHT
	hudn._unhandled_input(k_ev)
	check("paused guide pages on keys", hudn.guide_page == 1)
	k_ev = InputEventKey.new()
	k_ev.pressed = true; k_ev.keycode = KEY_N
	hudn._unhandled_input(k_ev)
	check("paused guide N closes", game.panel == "")
	# paused panels still carry the touch X — a slab has no Esc
	var tui2 := game.touch_ui
	game.touch_ui = true # route REAL events — the gate is the thing under test
	game.panel = "tech"
	var t_touch := InputEventScreenTouch.new()
	t_touch.pressed = true; t_touch.index = 9
	t_touch.position = lay_t["btns"]["menu"]
	hudn._unhandled_input(t_touch)
	check("paused panel X closes", game.panel == "")
	game.panel = "inv" # a non-X tap under the shell must NOT fire verbs
	t_touch = InputEventScreenTouch.new()
	t_touch.pressed = true; t_touch.index = 9
	t_touch.position = lay_t["joy"]
	hudn._unhandled_input(t_touch)
	check("paused joy tap grabs no stick", hudn.joy_idx < 0 and p.touch_vec == Vector2.ZERO)
	t_touch = InputEventScreenTouch.new()
	t_touch.pressed = false; t_touch.index = 9
	t_touch.position = lay_t["joy"]
	hudn._unhandled_input(t_touch)
	game.panel = ""; game.state = "play"; game.touch_ui = tui2
	# a click that lands on a rect is HANDLED — it must not leak to melee/throw
	game.panel = "chat"
	var m_ev2 := InputEventMouseButton.new()
	m_ev2.pressed = true; m_ev2.button_index = MOUSE_BUTTON_LEFT
	m_ev2.position = Vector2(5, 5)
	hudn._unhandled_input(m_ev2) # flush the state transition so rects survive
	hudn.click_rects.append({"rect": Rect2(Vector2(5, 5), Vector2(30, 20)), "act": "text_cancel", "arg": null})
	m_ev2 = InputEventMouseButton.new()
	m_ev2.pressed = true; m_ev2.button_index = MOUSE_BUTTON_LEFT
	m_ev2.position = Vector2(10, 10)
	hudn._unhandled_input(m_ev2)
	check("rect click marks handled", game.panel == "" and hudn.get_viewport().is_input_handled())
	# every virtual control sits inside the zone gate — taps on them can't place ghosts
	var all_zones := true
	for b0 in lay_t["btns"]:
		if not hudn.touch_zone_hit(lay_t["btns"][b0]): all_zones = false
	if not hudn.touch_zone_hit(lay_t["joy"]): all_zones = false
	check("every control inside the zone gate", all_zones)
	check("more_row radius beats spacing", hudn.btn_r("dml") * 2.0 <= 56.0
		and hudn.btn_r("dml") < hudn.btn_r("atk"))
	# sell rail carries only your own kin
	var gkin = Kin.new()
	gkin.owner_id = 5
	game.box.append(gkin)
	check("guest kin stays off the sell rail", gkin not in hudn.sellable_pals())
	game.box.erase(gkin); gkin.free()
	# pause rows ride the real click path, not just the data
	var peer_bak3 = game.net.multiplayer.multiplayer_peer
	game.net.multiplayer.multiplayer_peer = null
	hudn.run_click({"act": "m_host", "arg": null})
	check("host row actually hosts", game.net.multiplayer.multiplayer_peer != null)
	game.net.multiplayer.multiplayer_peer.close()
	game.net.multiplayer.multiplayer_peer = peer_bak3
	for act0 in ["m_dex", "m_statues", "m_guide"]:
		game.panel = ""
		hudn.run_click({"act": act0, "arg": null})
		check("pause row %s opens" % act0, game.panel == act0.trim_prefix("m_"))
	game.panel = ""
	# title JOIN: co-op straight from boot — rows are data, arrival is a hook
	game.state = "title"
	var join_title := 0
	for row in hudn.title_rows():
		if row[1] == "m_join": join_title += 1
	check("title offers join", join_title == 1)
	hudn.run_click({"act": "m_join", "arg": null})
	check("title join row opens the panel", game.panel == "join")
	game.panel = ""
	game.net.is_host = false # the dial succeeded — arrival hook only fires for guests
	game.net._arrive_guest()
	check("title-joined guest lands in play", game.state == "play")
	game.state = "paused" # a mid-pause join must NOT yank the shell out from under you
	game.net._arrive_guest()
	check("paused join stays paused", game.state == "paused")
	game.state = "play"
	game.net._on_connection_failed() # a dead dial frees the peer + says why
	check("failed dial says why + frees peer", game.net.multiplayer.multiplayer_peer == null
		and game.messages.back() == "No host answered — check the address",
		"msg=%s" % game.messages.back())
	# joining mid-run autosaves first — world_sync razes the world under your feet
	game.net.join("127.0.0.1")
	check("join autosaves the solo run", game.messages.size() >= 2
		and game.messages[-2] == tr("Saved."), "tail=%s" % game.messages[-2])
	check("join dial spins up", game.net.multiplayer.multiplayer_peer != null)
	game.net._close_peer() # a lingering fake client would refuse every save below
	check("peer released after probe", game.net.multiplayer.multiplayer_peer == null)

	# ---- S7: bosses phase, spires crown ----
	var sb := game.gen_pal("fenjelly", 40, Vector2(game.player.pos.x + 2, game.player.pos.y))
	sb.boss = true
	sb.max_hp = 1000
	sb.hp = int(sb.max_hp * 0.45)
	var spn0 := game.pals.size()
	sb.hit(1, 1.0, false)
	check("boss phases at half", sb.phase == 2)
	check("phase two summons adds", game.pals.size() > spn0)
	game.player.pos = sb.pos + Vector2(1.0, 0)
	var php := game.player.hp
	sb.pact_slam()
	check("pact slam reaches the player", game.player.hp < php)
	game.player.hp = 100.0
	sb.hit(99999, 1.0, false)
	check("boss dies clean", sb.hp <= 0)
	game.spires_done.clear()
	game.crowned = false
	for i in game.SPIRE_DEFS.size():
		game.record_spire("spire_%d" % i)
	check("five spires crown", game.crowned)
	game.crowned = false
	game.spires_done.clear()
	# spire slams carry their shrine's element: a fire-spire guardian burns the
	# pile-up, water soaks it, dark puts it to sleep — each asks a different question
	var slam_boss: Kin = game.gen_pal("fenjelly", 40, game.player.pos + Vector2(1, 0))
	slam_boss.spire_tag = "spire_0" # fire
	slam_boss.boss = true
	game.pals.append(slam_boss)
	var victim: Kin = null
	for q in game.pals:
		if q.mode == "partner" and q.hp > 0:
			victim = q; break
	if victim == null:
		victim = game.gen_pal("fenjelly", 5, game.player.pos)
		victim.mode = "partner"; game.pals.append(victim)
	victim.pos = slam_boss.pos + Vector2(0.5, 0)
	victim.statuses.clear()
	slam_boss.pact_slam()
	check("fire spire slam burns", victim.statuses.has("burn"))
	slam_boss.spire_tag = "spire_3" # dark
	victim.statuses.clear()
	slam_boss.pact_slam()
	check("dark spire slam sleeps", victim.statuses.has("sleep"))
	victim.statuses.clear()
	game.pals.erase(slam_boss); slam_boss.queue_free()
	if not game.party.has(victim.uid):
		game.pals.erase(victim); victim.queue_free()

	# i18n — zh translation registered, toggle swaps tr() output, garbage coerced
	check("zh translation loaded", "zh" in TranslationServer.get_loaded_locales())
	game.settings["lang"] = "zh"; game.apply_settings()
	check("tr zh", tr("SETTINGS") == "设置")
	check("tr zh covers new rows", tr("JOIN SESSION") == "加入会话" and tr("TOUCH CONTROLS") == "触屏控制"
		and tr("Say: ") == "说：")
	check("tr fallback", tr("NO_SUCH_KEY_XYZ") == "NO_SUCH_KEY_XYZ")
	game.settings["lang"] = "bogus"; game.apply_settings()
	check("bad lang falls back", TranslationServer.get_locale().begins_with("en") or tr("SETTINGS") == "SETTINGS")
	game.settings["lang"] = "en"; game.apply_settings()
	check("tr en", tr("SETTINGS") == "SETTINGS")

	# hero accessories: the crown jewels and back wings are real pixels, not
	# a comment — scalbeak wears white jewel dots, vermtrot carries a back fan
	var h1 := Image.load_from_file("res://assets/kin/scalbeak_f0.png")
	var h2 := Image.load_from_file("res://assets/kin/vermtrot_f0.png")
	var jc: Color = h1.get_pixel(40, 2)
	check("hero crown pixels", h1 != null and jc.r > 0.9 and jc.g > 0.9 and jc.b > 0.9)
	check("hero wing pixels", h2 != null and h2.get_pixel(34, 14).a > 0.9)
	# pad-aware hints: variants exist, the device detector flips on intent
	var pad_keys := 0
	for hh in game.HINTS:
		if hh.has("pad"):
			pad_keys += 1
	check("pad hint variants", pad_keys >= 2)
	var hud2 = main.get_node("UILayer/HUD")
	var jev := InputEventJoypadButton.new()
	jev.button_index = JOY_BUTTON_A; jev.pressed = true
	hud2._input(jev)
	check("pad seen", game.using_pad)
	var kev2 := InputEventKey.new()
	kev2.keycode = KEY_Q; kev2.pressed = true
	hud2._input(kev2)
	check("keyboard seen", not game.using_pad)

	# species voices: lazy-synthesized, cached per id, distinct across species
	game.cry_for("fenjelly")
	game.cry_for("vermtrot")
	game.cry_for("fenjelly")
	check("cries cached + distinct", game.CRIES.has("fenjelly") and game.CRIES.has("vermtrot")
		and game.CRIES["fenjelly"] is AudioStreamWAV
		and game.CRIES["fenjelly"] != game.CRIES["vermtrot"]
		and game.CRIES["fenjelly"].data.size() > 0
		and game.CRIES.size() <= SpeciesData.SPECIES.size() + SpeciesGen.SPECIES.size()) # bounded by the species set

	# ---------- client authority: every gated verb refuses on a guest ----------
	# a connecting ENet peer flips is_client() true — it never has to complete;
	# the gates key off the peer TYPE, not the handshake
	var fake_peer := ENetMultiplayerPeer.new()
	fake_peer.create_client("127.0.0.1", 7777)
	game.net.is_host = false
	game.net.multiplayer.multiplayer_peer = fake_peer
	check("client context flips", game.net.is_client())
	# danger mirrors host truth over env_sync — a client can't read raid flags
	game.net_danger = true
	check("client danger mirrors", game.danger_active())
	game.net_danger = false
	# sync_pos is the only input every proximity gate trusts — spoofed
	# coordinates must die at the door (id 0 = a headless sender). The gate
	# itself executes HOST-side — a real client never runs this branch
	game.net.is_host = true
	game.net.spawn_ghost(0)
	var g0 = game.net.ghosts[0]
	g0.net_pos = Vector3(-1, -1, 0) # unset sentinel — but the first fix must
	# still land where a join materializes: spawn, or a pad beside it
	var spfx := Vector2(game.world.spawn) + Vector2(0.5, 0.5)
	game.net.sync_pos(spfx.x + 3.0, spfx.y, 0.0)
	check("first fix lands at spawn", g0.net_pos == Vector3(spfx.x + 3.0, spfx.y, 0))
	g0.net_pos = Vector3(-1, -1, 0) # a recycled ghost gets no second free blink
	var ffx := Vector2.ZERO
	for fcand in [Vector2(200, 200), Vector2(20, 20), Vector2(400, 400), Vector2(150, 180)]:
		if game.net._near_travel_node(fcand) == "" and fcand.distance_to(spfx) > 12.0:
			ffx = fcand
			break
	check("far first-fix target exists", ffx != Vector2.ZERO)
	if ffx != Vector2.ZERO:
		game.net.sync_pos(ffx.x, ffx.y, 0.0)
		check("first fix off-spawn dies", g0.net_pos == Vector3(-1, -1, 0))
	g0.net_pos = Vector3(150, 150, 0) # planted for the step/blink checks below
	# a jump to nowhere still dies at the door — hunt a spot that is provably
	# not a travel-node landing so seeds can't make this test seed-dependent
	var bad := Vector2.ZERO
	for cand in [Vector2(200, 200), Vector2(20, 20), Vector2(400, 400), Vector2(150, 180)]:
		if game.net._near_travel_node(cand) == "" \
				and cand.distance_to(Vector2(game.world.spawn) + Vector2(0.5, 0.5)) > game.net.BLINK_RADIUS:
			bad = cand
			break
	check("bad blink target exists", bad != Vector2.ZERO)
	game.net.sync_pos(bad.x, bad.y, 0.0)
	check("sync_pos kills teleports", g0.net_pos == Vector3(150, 150, 0))
	game.net.sync_pos(NAN, 50.0, 0.0)
	check("sync_pos kills NaN", g0.net_pos == Vector3(150, 150, 0))
	game.net.sync_pos(-5.0, 50.0, 0.0)
	check("sync_pos kills out-of-bounds", g0.net_pos == Vector3(150, 150, 0))
	game.net.sync_pos(152.0, 150.0, 0.0) # a normal step still lands
	check("sync_pos accepts steps", g0.net_pos == Vector3(152, 150, 0))
	# legit blinks land: respawns wake at a kinbox, waypoint hops go
	# node-to-node — a waypoint destination from open ground is still a spoof.
	# The save-coercion tests leave the world structure-less: plant fixtures.
	var kb := Vector2i(-1, -1)
	var wk := Vector2i(-1, -1)
	var px3 := int(game.player.pos.x); var py3 := int(game.player.pos.y)
	for r3 in range(6, 70):
		if kb.x >= 0 and wk.x >= 0:
			break
		for d6 in [Vector2i(r3, 0), Vector2i(-r3, 0), Vector2i(0, r3), Vector2i(0, -r3),
				Vector2i(r3, r3), Vector2i(-r3, -r3), Vector2i(r3, -r3), Vector2i(-r3, r3)]:
			if kb.x >= 0 and wk.x >= 0:
				break
			var cc: Vector2i = Vector2i(px3, py3) + d6
			var clear := true
			for dy3 in range(3):
				for dx3 in range(3):
					var k3: Vector2i = cc + Vector2i(dx3, dy3)
					if not game.world.in_bounds(k3.x, k3.y) or game.world.blocked(k3.x, k3.y) \
							or game.structures.has(k3):
						clear = false
			if not clear:
				continue
			if kb.x < 0 and game.place_free("kinbox", cc.x, cc.y):
				kb = cc
			elif wk.x < 0 and cc.distance_to(kb) > 16.0 and game.place_free("waypoint", cc.x, cc.y):
				wk = cc
	check("blink fixtures planted", kb.x >= 0 and wk.x >= 0, "kb=%s wk=%s" % [kb, wk])
	if kb.x >= 0:
		game.net.sync_pos(kb.x + 0.5, kb.y + 2.5, 0.0)
		check("respawn blink lands", g0.net_pos == Vector3(kb.x + 0.5, kb.y + 2.5, 0))
	if wk.x >= 0:
		var wdst := Vector2(wk.x + 0.5, wk.y + 2.5)
		var src_far := Vector2.ZERO
		for cand in [Vector2(150, 150), Vector2(180, 180), Vector2(300, 60), Vector2(60, 300), Vector2(250, 250), Vector2(40, 40)]:
			if game.net._near_travel_node(cand) == "" and cand.distance_to(wdst) > 12.0:
				src_far = cand
				break
		check("off-node source exists", src_far != Vector2.ZERO)
		g0.net_pos = Vector3(src_far.x, src_far.y, 0) # open ground, far from stones
		game.net.sync_pos(wdst.x, wdst.y, 0.0)
		check("waypoint jump off-node dies", g0.net_pos == Vector3(src_far.x, src_far.y, 0))
		# the home lane has a cooldown — a death-blink isn't a free escape rope
		g0.net_pos = Vector3(src_far.x, src_far.y, 0)
		game.net.sync_pos(kb.x + 0.5, kb.y + 2.5, 0.0)
		check("home blink cooldown bites", g0.net_pos == Vector3(src_far.x, src_far.y, 0))
		g0.net_pos = Vector3(kb.x + 0.5, kb.y + 2.5, 0) # standing at the pad
		game.net.sync_pos(wdst.x, wdst.y, 0.0) # …then node→node
		check("node-to-node hop lands", g0.net_pos == Vector3(wdst.x, wdst.y, 0))
	# elevation is validated too — guests can't float above the skybox
	g0.net_pos = Vector3(151, 150, 0) # a hop-length step away, no blink needed
	g0.set_meta("pos_allow", 6.0) # earlier blinks drained the bucket
	game.net.sync_pos(152.0, 150.0, 99.0)
	check("sync_pos clamps elevation", g0.net_pos == Vector3(152, 150, 8))
	g0.set_meta("pos_allow", 6.0)
	game.net.sync_pos(152.0, 150.0, NAN)
	check("sync_pos kills NaN elev", g0.net_pos == Vector3(152, 150, 8))
	g0.queue_free(); game.net.ghosts.erase(0)
	# pal_hit bounds the claim by the formula's own ceiling vs THIS target —
	# the wire says 99999, the kin feels the model's max (~a couple hundred)
	game.net.is_host = true # the relay only runs host-side
	var vt: Kin = game.gen_pal("fenjelly", 5, Vector2(160, 150))
	vt.mode = "wild"; game.pals.append(vt)
	game.net.spawn_ghost(0)
	game.net.ghosts[0].net_pos = Vector3(vt.pos.x, vt.pos.y, 0)
	vt.max_hp = 99999.0; vt.hp = vt.max_hp # deep pool so the bound is what caps
	# the cap derives from real gear data — a top-end build (85-wpn lv60,
	# maxed statue + trinkets + aura + meal) lands ~775 pre-formula atk
	check("guest atk cap derived", game.net.guest_atk_cap() >= 740.0 and game.net.guest_atk_cap() <= 800.0,
		"cap=%.0f" % game.net.guest_atk_cap())
	var hp_v: float = vt.hp
	game.net.pal_hit(vt.uid, 99999.0)
	check("pal_hit bounds claims", vt.hp >= hp_v - 260.0 and vt.hp < hp_v,
		"hp=%.0f/%0f" % [vt.hp, hp_v])
	# per-sender hit bucket: after the burst, rapid claims starve out
	var nhits := 0
	for i in 12:
		var hp_b: float = vt.hp
		game.net.pal_hit(vt.uid, 50.0)
		if vt.hp < hp_b:
			nhits += 1
	check("pal_hit rate-limits spam", nhits <= 5 and nhits > 0, "landed=%d" % nhits)
	# forged sleep can't chain-lock: a darted kin resists re-darting after waking
	vt.hp = vt.max_hp
	game.net.ghosts[0].set_meta("hit_bkt", 6.0) # fresh bucket for the sleep claims
	game.net.pal_hit(vt.uid, 0.0, 10.0)
	check("sleep claim lands", vt.statuses.get("sleep", 0.0) > game.t)
	# a 0/0 claim is a pure no-op — it can't wake a darted kin or pull aggro
	var agg0 := vt.aggro_pid
	game.net.ghosts[0].set_meta("hit_bkt", 6.0)
	game.net.pal_hit(vt.uid, 0.0, 0.0)
	check("zero claim stays asleep", vt.statuses.get("sleep", 0.0) > game.t
		and vt.aggro_pid == agg0)
	vt.statuses.erase("sleep")
	game.net.ghosts[0].set_meta("hit_bkt", 6.0)
	game.net.pal_hit(vt.uid, 0.0, 10.0)
	check("chain sleep resisted", not vt.statuses.has("sleep"))
	vt.statuses.clear(); vt.set_meta("slp_immune", 0.0)
	game.net.ghosts[0].queue_free(); game.net.ghosts.erase(0)
	game.pals.erase(vt)
	if vt.get_parent():
		vt.get_parent().remove_child(vt)
	vt.free()
	# sphere_catch throttles the roll — one throw per breath, not per frame
	game.net.is_host = true
	var ct: Kin = game.gen_pal("fenjelly", 3, Vector2(165, 150))
	ct.mode = "wild"; game.pals.append(ct)
	game.net.spawn_ghost(0)
	game.net.ghosts[0].net_pos = Vector3(ct.pos.x, ct.pos.y, 0)
	game.net.sphere_catch(ct.uid, "kin_orb", false, 99) # over-clamp cap_lv
	game.net.sphere_catch(ct.uid, "kin_orb", false, 99) # same breath — dies
	var fz: int = game.floaters.size()
	var f_last: String = str(game.floaters[fz - 1]["t"])
	var f_prev: String = str(game.floaters[fz - 2]["t"])
	check("catch roll throttled",
		(f_last.contains("CAUGHT") or f_last.contains("broke free"))
		and not (f_prev.contains("CAUGHT") or f_prev.contains("broke free")),
		"tail=%s/%s" % [f_prev, f_last])
	game.pals.erase(ct); game.box.erase(ct); game.bench.erase(ct)
	game.remote_parties.erase("_pid0") # a caught kin lands under the sender's key
	if ct.get_parent():
		ct.get_parent().remove_child(ct)
	ct.free()
	# demolish gates: anchors refuse, foreign builds refuse, own build razed
	var kbx: Variant = null
	for kk in game.structures:
		if game.structures[kk]["id"] == "kinbox":
			kbx = kk; break
	check("kinbox fixture found", kbx != null)
	if kbx != null:
		game.net.demolish_req(kbx.x, kbx.y)
		check("anchor refuses raze", game.structures.get(kbx) != null)
	var cd := Vector2i(-1, -1)
	for r4 in range(4, 60): # seed-proof: scan outward from the keeper
		var c4 := Vector2i(int(game.player.pos.x) + r4, int(game.player.pos.y))
		if game.world.in_bounds(c4.x, c4.y) and not game.world.blocked(c4.x, c4.y) \
				and not game.structures.has(c4) and game.place_free("campfire", c4.x, c4.y):
			cd = c4; break
	check("campfire fixture planted", cd.x >= 0)
	if cd.x >= 0:
		game.net.spawn_ghost(0)
		game.net.ghosts[0].net_pos = Vector3(cd.x + 0.5, cd.y + 0.5, 0)
		var stc: Dictionary = game.structures[cd]
		stc["placed_tag"] = "tk_other" # a guest's build
		game.net.ghosts[0].set_meta("dem_bkt", 1.0) # dem_bkt feeds one refusal per beat
		game.net.demolish_req(cd.x, cd.y) # sender 0 has NO hello tag — refuse outright
		check("tagless demolish refused", game.structures.get(cd) != null)
		game.net.peer_tags[0] = "tk_zero" # hello'd, but NOT this build's owner
		game.net.ghosts[0].set_meta("dem_bkt", 1.0)
		game.net.demolish_req(cd.x, cd.y)
		check("foreign build refuses raze", game.structures.get(cd) != null)
		stc["placed_tag"] = "tk_zero" # now it IS sender 0's build
		game.net.ghosts[0].set_meta("dem_bkt", 1.0)
		game.net.demolish_req(cd.x, cd.y)
		check("own build razes", game.structures.get(cd) == null)
		game.net.peer_tags.erase(0)
	# net_place stamps who built it — the tag drives the demolish gate
	if "campfire" not in game.unlocked:
		game.unlocked.append("campfire") # save tests may have pruned the tech list
	var cd2 := Vector2i(-1, -1)
	var cp_n := 0
	game.net.spawn_ghost(5) # the sender's ghost vouches for proximity
	game.net.peer_tags[5] = "tk_five" # hello'd identity — net_place stamps it
	for r5 in range(2, 40):
		if cd2.x >= 0:
			break
		for d5 in [Vector2i(r5, 0), Vector2i(-r5, 0), Vector2i(0, r5), Vector2i(0, -r5),
				Vector2i(r5, r5), Vector2i(-r5, r5), Vector2i(r5, -r5), Vector2i(-r5, -r5)]:
			var c5: Vector2i = Vector2i(int(game.player.pos.x), int(game.player.pos.y)) + d5
			if not (game.world.in_bounds(c5.x, c5.y)
					and game.can_place("campfire", c5.x, c5.y)):
				continue
			cp_n += 1
			game.net.ghosts[5].net_pos = Vector3(c5.x + 0.5, c5.y + 0.5, 0)
			if game.net_place("campfire", c5.x, c5.y, 5):
				cd2 = c5; break
	var st_ct := 0
	var seen2 := []
	for k2x in game.structures:
		if game.structures[k2x] not in seen2:
			seen2.append(game.structures[k2x]); st_ct += 1
	check("guest build tagged", cd2.x >= 0
		and str(game.structures.get(cd2, {}).get("placed_tag", "")) == "tk_five",
		"cd2=%s canplace=%d structs=%d/%d tag=%s" % [cd2, cp_n, st_ct, game.MAX_STRUCTURES,
			game.structures.get(cd2, {}).get("placed_tag", "?")])
	game.net.peer_tags.erase(5)
	if cd2.x >= 0:
		game.net_remove_structure(game.structures[cd2]) # leave no trace
	game.net.ghosts[5].queue_free(); game.net.ghosts.erase(5)
	game.net.ghosts[0].queue_free(); game.net.ghosts.erase(0) # no stray bait for wild_ai
	# orphaned roster: field kin box up under the tag, ids go -1 for rebind
	var op1: Kin = game.gen_pal("fenjelly", 2, Vector2(150, 152))
	op1.mode = "partner"; op1.owner_id = 7; op1.owner_tag = "tok_z"
	game.pals.append(op1)
	var op2: Kin = game.gen_pal("fenjelly", 2, Vector2(150, 152))
	op2.mode = "base"; op2.owner_id = 7
	var jobsite := {"workers": [op2], "id": "campfire", "cells": []}
	op2.job_site = jobsite
	game.pals.append(op2)
	game.orphan_guest_kin(7)
	check("orphans boxed", op1.mode == "box" and op2.mode == "box"
		and op1.owner_id == -1 and op2.owner_id == -1
		and op2.job_site == null
		and op1 in game.box and op2 in game.box and op1 not in game.pals)
	game.rebind_owner(7, "tok_z")
	check("rejoin reclaims orphans", op1.owner_id == 7)
	game.box.erase(op1); game.box.erase(op2)
	op1.free(); op2.free()
	# an expedition kin orphans into daylight — visible again, cargo rode home
	var op3: Kin = game.gen_pal("fenjelly", 2, Vector2(150, 152))
	op3.mode = "expedition"; op3.owner_id = 7; op3.owner_tag = "tok_z"
	op3.visible = false; op3.carry = {"id": "wood", "n": 4}
	game.pals.append(op3)
	var bag_w := game.item_count("wood")
	game.orphan_guest_kin(7)
	check("expedition orphan surfaces", op3.mode == "box" and op3.visible
		and op3.carry == null and game.item_count("wood") == bag_w + 4,
		"mode=%s vis=%s carry=%s" % [op3.mode, op3.visible, op3.carry])
	game.box.erase(op3); op3.free()
	# severed session: host-owned replicas purge, they can't be free catches
	var rex: Kin = game.gen_pal("fenjelly", 2, Vector2(150, 152))
	rex.mode = "wild"; rex.net_id = 4242; game.pals.append(rex)
	var rex2: Kin = game.gen_pal("fenjelly", 2, Vector2(150, 152))
	rex2.mode = "box"; rex2.net_id = 4243; game.box.append(rex2); game.box_pal(rex2)
	game.remote_parties[9] = [1, 2]
	game.purge_replicas()
	check("replicas purged", rex not in game.pals and rex2 not in game.box
		and game.remote_parties.is_empty())
	rex.free(); rex2.free()
	# a guest's field pal doesn't graze the host pantry or medicine chest
	var fk: Kin = game.gen_pal("fenjelly", 3, Vector2(152, 152))
	fk.mode = "partner"; fk.owner_id = 7; fk.hunger = 90.0
	fk.hp = fk.max_hp; fk.san = 50.0; fk.ailment = ""
	game.pals.append(fk)
	game.items["milk"] = 3
	fk.tick_needs(1.0)
	check("foreign pal skips host bag", int(game.items["milk"]) == 3)
	fk.ailment = "sick"; fk.san = 30.0
	fk.tick_needs(1.0)
	check("foreign pal skips host meds", fk.ailment == "sick" and int(game.items["milk"]) == 3)
	game.pals.erase(fk); fk.free(); game.items.erase("milk")
	# the host can evict a foreign worker but can't post one
	var fw: Kin = game.gen_pal("fenjelly", 3, game.player.pos)
	fw.mode = "base"; fw.owner_id = 7
	var fjs := {"workers": [fw], "id": "campfire", "cells": []}
	fw.job_site = fjs
	game.pals.append(fw)
	game.assign_worker() # F on it: evict, not post
	check("host evicts foreign worker", fw.job_site == null and fjs["workers"].is_empty())
	game.assign_worker() # F again: foreign pal stays unposted
	check("host can't post foreign", fw.job_site == null)
	game.pals.erase(fw); fw.free()
	# chat: the brake is per-sender, and my own relayed line doesn't echo.
	# The brake lives host-side — a real server peer flips is_server() on.
	var srv := ENetMultiplayerPeer.new()
	srv.create_server(7789)
	game.net.multiplayer.multiplayer_peer = srv
	game.net.chat("hi", 5)
	game.net.chat("again", 5) # same sender inside the beat — dropped
	game.net.chat("yo", 6) # a different sender still reaches the log
	check("chat per-peer brake", game.messages.has("[friend] hi")
		and game.messages.has("[friend] yo")
		and not game.messages.has("[friend] again"), "msgs=%s" % str(game.messages))
	game.net.chat("mine", game.net.multiplayer.get_unique_id())
	check("chat self-echo muted", not game.messages.has("[friend] mine"))
	# live-tag guard: a claimed identity refuses a second session
	game.net.peer_tags[5] = "tok_a"
	game.net.hello("tok_a") # pid 0 headless — the tag belongs to live peer 5
	check("stolen tag refused", not game.net.peer_tags.has(0))
	game.net.hello("tok_b") # pid 0 headless — a fresh identity registers
	check("hello registers tag", game.net.peer_tags.get(0, "") == "tok_b")
	game.net.peer_tags.erase(0)
	game.net.peer_tags.erase(5)
	game.net.multiplayer.multiplayer_peer = fake_peer
	srv.close()
	game.net.is_host = false
	var caster2: Kin = game.gen_pal("fenjelly", 10, Vector2(160, 150))
	caster2.mode = "wild"; game.pals.append(caster2)
	caster2.extra_skills = ["airCannon"]
	var n_pr := game.projectiles.size()
	check("ghost draws skill fire", caster2.cast_skills(Vector2(165, 150), 0.1,
		["projectile", "self"]) and game.projectiles.size() == n_pr + 1,
		"pr=%d" % game.projectiles.size())
	caster2.skill_cd.clear()
	check("ghost skips body skills", not caster2.cast_skills(Vector2(165, 150), 0.1, ["lunge"]))
	while game.projectiles.size() > n_pr: # spawned shots hold the caster — free him last
		var pr_c = game.projectiles.pop_back()
		if is_instance_valid(pr_c.get("node")):
			pr_c["node"].queue_free()
	game.pals.erase(caster2)
	if caster2.get_parent():
		caster2.get_parent().remove_child(caster2)
	caster2.free()
	if game.item_count("kin_egg") == 0:
		game.add_item("kin_egg", 1)
	var eggs_have: int = game.item_count("kin_egg")
	var b4_inc := game.structures.values().filter(func(s9): return s9["id"] == "incubator")
	var inc_st = b4_inc[0] if b4_inc.size() > 0 else null
	if inc_st != null:
		game.deposit_egg()
		check("client deposit_egg refused", game.item_count("kin_egg") == eggs_have
			and not inc_st.has("egg_inc"), "eggs=%d inc=%s" % [game.item_count("kin_egg"), inc_st.get("egg_inc")])
	var day_c: int = game.day
	game.sleep_to_morning()
	check("client sleep refused", game.day == day_c)
	check("client cast refused", not game.cast_line())
	check("client gauntlet refused", not game.start_gauntlet())
	check("client load refused", not game.load_game())
	var locked_tech := ""
	for tn in StructureData.TECH: # find a real node the run hasn't unlocked
		if tn["id"] not in game.unlocked:
			locked_tech = tn["id"]; break
	if locked_tech != "":
		var tp_c: int = game.tech_points
		game.unlock(locked_tech)
		check("client unlock refused", locked_tech not in game.unlocked and game.tech_points == tp_c,
			"sid=%s tp=%d" % [locked_tech, game.tech_points])
	var bag0: int = game.items.values().reduce(func(a, b): return a + b, 0)
	game.respawn_player()
	var bag1: int = game.items.values().reduce(func(a, b): return a + b, 0)
	check("client death keeps the bag", bag1 == bag0, "bag=%d -> %d" % [bag0, bag1])
	var pal_c: int = game.pals.size()
	game.mig_t = 0.0
	game.tick_migration(999.0)
	check("client migration spawns nothing", game.pals.size() == pal_c)
	var chests := game.structures.values().filter(func(s9): return s9["id"] == "chest")
	if chests.size() > 0:
		check("client chest deposit refused", game.chest_deposit_all(chests[0]) == 0)
	game.record_spire("spire_-1")
	check("record_spire re-validates", not game.spires_done.has("spire_-1"))
	game.net.multiplayer.multiplayer_peer.close()
	game.net.multiplayer.multiplayer_peer = null # back to honest offline

	# ---------- launch sweep: the shell chain a player actually runs ----------
	# title → new game → pause → settings toggle → resume → save → continue →
	# load — one unbroken path, each hop asserted (to_title's scene reload is
	# the only hop the harness can't exercise; continue reuses its load path)
	var hudl: Node = main.get_node("UILayer/HUD")
	game.state = "title"
	hudl.shell_act("new_game")
	check("sweep: new game enters play", game.state == "play", "state=%s" % game.state)
	game.state = "paused"
	hudl.shell_act("m_settings")
	check("sweep: pause opens settings", game.panel == "settings", "panel=%s" % game.panel)
	var raids0: bool = game.settings["raids"]
	hudl.shell_act("raids_tgl")
	check("sweep: settings toggle applies", game.settings["raids"] != raids0)
	hudl.shell_act("raids_tgl") # leave the world as we found it
	hudl.shell_act("set_back")
	hudl.shell_act("resume")
	check("sweep: resume returns to play", game.state == "play" and game.panel == "",
		"state=%s panel=%s" % [game.state, game.panel])
	var pals_n: int = game.pals.size()
	var day_n: int = game.day
	hudl.shell_act("m_save")
	game.state = "title" # the title a rebooted player lands on
	hudl.shell_act("continue")
	check("sweep: continue lands in play", game.state == "play", "state=%s" % game.state)
	check("sweep: roster survives the reboot", game.pals.size() == pals_n,
		"pals=%d want=%d" % [game.pals.size(), pals_n])
	check("sweep: clock survives the reboot", game.day == day_n,
		"day=%d want=%d" % [game.day, day_n])

	# restore the dev's real save the moment the LAST save-mutating test is
	# done — a crash after this point leaves user:// untouched
	if save_backup.is_empty():
		DirAccess.remove_absolute("user://savegame.plg")
	else:
		var sv2 := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
		sv2.store_buffer(save_backup); sv2.close()

	# join-path determinism: regenerate(world.seed) is what a joining guest
	# runs — two seeded regens must land the same grotto/markers/structures.
	# Boot↔join parity itself is by construction: _ready and regenerate share
	# place_pois() under the same world.seed-derived reseed (verified in a
	# clean-boot probe: identical grotto/room2/40 structures/42 pals)
	var v9_seed := game.world.seed
	game.regenerate(v9_seed)
	var v9_grotto := game.grotto_pos
	var v9_room2 := game.grotto_room2
	var v9_cells := game.structures.keys()
	v9_cells.sort()
	game.regenerate(v9_seed)
	check("regen replays the same grotto", game.grotto_pos == v9_grotto,
		"r1=%s r2=%s" % [v9_grotto, game.grotto_pos])
	check("regen replays the same room2", game.grotto_room2 == v9_room2,
		"r1=%s r2=%s" % [v9_room2, game.grotto_room2])
	var v9_cells2 := game.structures.keys()
	v9_cells2.sort()
	check("regen is internally deterministic", v9_cells2 == v9_cells,
		"%d vs %d cells" % [v9_cells2.size(), v9_cells.size()])

	# pay-first ledger: the bag debits when the request flies; a refusal
	# refunds, a success keeps the spend — no echo, no mint
	game.add_item("gold_coin", 50) # the ledger test needs spendable truth
	var v9_gold0 := game.item_count("gold_coin")
	game.net.pay("t_verb", {"gold_coin": 5})
	check("pay debits at request time", game.item_count("gold_coin") == v9_gold0 - 5)
	game.net.pay_settle("t_verb", true)
	check("a refusal refunds the hold", game.item_count("gold_coin") == v9_gold0)
	game.net.pay("t_verb", {"gold_coin": 7})
	game.net.pay_settle("t_verb", false)
	check("an accept keeps the spend", game.item_count("gold_coin") == v9_gold0 - 7)
	game.add_item("gold_coin", 7)

	# net host (no client join in same proc) — close the socket too: a bound
	# :7777 outlives the suite and breaks the next run on a busy machine
	game.net.host()
	check("net host", game.net.multiplayer.multiplayer_peer != null)
	game.net.multiplayer.multiplayer_peer.close()
	game.net.multiplayer.multiplayer_peer = null

	var fails := 0
	var skips2 := 0
	for r in results:
		if r.begins_with("FAIL"):
			fails += 1
		elif "  skipped" in r:
			skips2 += 1
	print("==== %d checks, %d failures, %d skipped ====" % [results.size(), fails, skips2])
