extends SceneTree
func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
	# PLG_STRESS=N: top the world up to N wild pals before measuring — this is
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
	print("=== pals now %d ===" % game.pals.size())
	# pals AI: call _physics_process on each pal
	var t0 = Time.get_ticks_msec()
	for i in 200:
		for p in game.pals:
			p._physics_process(0.016)
	print("=== PERF pals-tick: %d ms for 200 rounds x %d pals ===" % [Time.get_ticks_msec() - t0, game.pals.size()])
	# game-level tick
	t0 = Time.get_ticks_msec()
	for i in 200:
		game._process(0.016)
	print("=== PERF game-tick: %d ms for 200 ticks, structures=%d ===" % [Time.get_ticks_msec() - t0, game.structures.size()])
	# raid-stress: PLG_RAID=N — a hostile wave under tower fire is the
	# heaviest live combat scene this game produces
	var raid_n := int(OS.get_environment("PLG_RAID"))
	if raid_n > 0:
		var bc: Vector2 = game.palbox_pos if game.palbox_pos.x >= 0 else game.player.pos
		var spawned := []
		var guard := 0
		while spawned.size() < raid_n and guard < raid_n * 40:
			guard += 1
			var a2: float = rng.randf() * TAU
			var at2: Vector2 = bc + Vector2(cos(a2), sin(a2)) * rng.randf_range(6, 12)
			if game.world.blocked(int(at2.x), int(at2.y)):
				continue
			var rp: Pal = game.gen_pal("syndicate_grunt", rng.randi_range(5, 15), at2)
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
		print("=== PERF raid-tick: %d ms for 400 ticks (raiders=%d alive, projectiles=%d) ===" % [
			Time.get_ticks_msec() - t0, spawned.filter(func(q): return is_instance_valid(q) and q.hp > 0).size(),
			game.projectiles.size()])
		for rp in spawned:
			if is_instance_valid(rp):
				game.pals.erase(rp)
				rp.free()
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
