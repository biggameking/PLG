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
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
