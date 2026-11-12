extends SceneTree

# Timing budgets (~4x the local baseline, audit-45 M8): a probe that only
# prints lets a 5x regression ship green. FAIL = exit code 1.
var fails := 0

func check_perf(what: String, elapsed_ms: int, budget_ms: int) -> void:
	var ok := elapsed_ms <= budget_ms
	if not ok:
		fails += 1
	print("=== %s PERF %s: %d ms (budget %d) ===" % ["PASS" if ok else "FAIL", what, elapsed_ms, budget_ms])

func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
	# PLG_STRESS=N: top the world up to N wild kin before measuring — this is
	# the MAX_PALS CPU guard check, not just a smoke of the spawn state.
	var want := int(OS.get_environment("PLG_STRESS"))
	var rng = RandomNumberGenerator.new()
	while want > 0 and game.pals.size() < min(want, game.MAX_PALS):
		var a: float = rng.randf() * TAU
		var at: Vector2 = game.player.pos + Vector2(cos(a), sin(a)) * rng.randf_range(4, 20)
		if game.world.blocked(int(at.x), int(at.y)):
			continue
		var pool: Array = SpeciesGen.zone_pool(game.world.zone_at(int(at.x), int(at.y)))
		var sid: String = pool[rng.randi_range(0, pool.size() - 1)]
		game.pals.append(game.gen_pal(sid, rng.randi_range(2, 10), at))
	print("=== kin now %d ===" % game.pals.size())
	# kin AI: call _physics_process on each kin
	var t0 = Time.get_ticks_msec()
	for i in 200:
		for p in game.pals:
			p._physics_process(0.016)
	var kin_ms: int = Time.get_ticks_msec() - t0
	print("=== PERF kin-tick: %d ms for 200 rounds x %d kin ===" % [kin_ms, game.pals.size()])
	# baseline ~0.004ms/kin/round → 4x headroom per kin-round
	check_perf("kin-tick", kin_ms, maxi(400, game.pals.size() * 200 / 60))
	# game-level tick
	t0 = Time.get_ticks_msec()
	for i in 200:
		game._process(0.016)
	var gt_ms: int = Time.get_ticks_msec() - t0
	print("=== PERF game-tick: %d ms for 200 ticks, structures=%d ===" % [gt_ms, game.structures.size()])
	check_perf("game-tick", gt_ms, 200) # baseline 9ms
	# raid-stress: PLG_RAID=N — a hostile wave under tower fire is the
	# heaviest live combat scene this game produces
	var raid_n := int(OS.get_environment("PLG_RAID"))
	if raid_n > 0:
		var bc: Vector2 = game.kinbox_pos if game.kinbox_pos.x >= 0 else game.player.pos
		var spawned := []
		var guard := 0
		while spawned.size() < raid_n and guard < raid_n * 40:
			guard += 1
			var a2: float = rng.randf() * TAU
			var at2: Vector2 = bc + Vector2(cos(a2), sin(a2)) * rng.randf_range(6, 12)
			if game.world.blocked(int(at2.x), int(at2.y)):
				continue
			var rp: Kin = game.gen_pal("ironpact_grunt", rng.randi_range(5, 15), at2)
			rp.mode = "wild"; rp.raid = true; rp.aggro = 0
			rp.set_meta("raid_t0", game.t)
			game.pals.append(rp)
			spawned.append(rp)
		# four towers ringing the box — placement pays materials, so fund it
		for c in StructureData.STRUCTURES["watch_tower"].get("cost", []):
			game.add_item(c[0], int(c[1]) * 4)
		var placed := 0
		for a3 in range(16):
			var at3: Vector2 = bc + Vector2(cos(a3 * TAU / 16.0), sin(a3 * TAU / 16.0)) * 3
			if game.place_structure("watch_tower", int(at3.x), int(at3.y)):
				placed += 1
				if placed >= 4:
					break
		print("=== raid-stress: %d raiders vs %d towers ===" % [spawned.size(), placed])
		t0 = Time.get_ticks_msec()
		for i in 400:
			for q in spawned: # raider AI lives in physics_process, not the game tick
				if is_instance_valid(q):
					q._physics_process(0.016)
			game._process(0.016)
		var raid_ms: int = Time.get_ticks_msec() - t0
		print("=== PERF raid-tick: %d ms for 400 ticks (raiders=%d alive, projectiles=%d) ===" % [
			raid_ms, spawned.filter(func(q): return is_instance_valid(q) and q.hp > 0).size(),
			game.projectiles.size()])
		check_perf("raid-tick", raid_ms, 1500) # baseline ~220ms
		for rp in spawned:
			if is_instance_valid(rp):
				game.pals.erase(rp)
				rp.free()
	# base-stress: PLG_BASE=N — a full yard of staffed production sites is the
	# busiest steady-state loop (tick_production walks every structure, every
	# worker, every chest, every frame)
	var base_n := mini(int(OS.get_environment("PLG_BASE")), 60)
	if base_n > 0:
		var kinds := ["ore_mine", "logging_site", "furnace", "wheat_farm",
			"sphere_factory", "ranch", "kin_bed"]
		var workers := []
		var sites := []
		var bc2: Vector2 = game.kinbox_pos if game.kinbox_pos.x >= 0 else game.player.pos
		var placed2 := 0
		var gx := 0
		# ring the box in a rough grid — place_free skips cost/tech for probes
		while placed2 < base_n and gx < 400:
			var ring: int = 2 + gx / 8
			var cell: Vector2i = Vector2i(int(bc2.x) + (gx % 8) - 4 + ring, int(bc2.y) + ring + (gx % 3))
			if game.place_free(kinds[gx % kinds.size()], cell.x, cell.y):
				sites.append(game.structures[cell])
				placed2 += 1
			gx += 1
		# storage + inputs so every consumption loop has real work to do
		var ch_k: Vector2i = Vector2i(int(bc2.x) + 1, int(bc2.y) + 3)
		game.place_free("chest", ch_k.x, ch_k.y)
		var ch = game.structures.get(ch_k)
		if ch:
			for it in ["ore", "wood", "lumenite", "stone", "cake", "berries"]:
				ch["store"][it] = 500
		for st2 in sites:
			if st2 == null or st2.get("workers") == null:
				continue
			var wp: Kin = game.gen_pal("fenjelly", 8, Vector2(bc2.x, bc2.y))
			wp.mode = "base"; wp.san = 90.0
			game.pals.append(wp)
			st2["workers"].append(wp); wp.job_site = st2
			workers.append(wp)
		print("=== base-stress: %d sites, %d workers, structures=%d ===" % [
			sites.size(), workers.size(), game.structures.size()])
		t0 = Time.get_ticks_msec()
		for i in 400:
			for w2 in workers:
				if is_instance_valid(w2):
					w2._physics_process(0.016)
			game._process(0.016)
		var base_ms: int = Time.get_ticks_msec() - t0
		print("=== PERF base-tick: %d ms for 400 ticks (workers=%d live) ===" % [
			base_ms, workers.filter(func(w): return is_instance_valid(w)).size()])
		check_perf("base-tick", base_ms, 1500) # baseline ~200ms
		for st3 in sites:
			if st3 != null:
				st3["workers"] = []
		for wp2 in workers:
			if is_instance_valid(wp2):
				game.pals.erase(wp2)
				wp2.job_site = null
				wp2.free()
	print("=== perf probe: %d budget failures ===" % fails)
	quit(1 if fails > 0 else 0)
func _initialize() -> void:
	call_deferred("_boot")
