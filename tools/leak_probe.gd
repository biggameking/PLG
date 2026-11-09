extends SceneTree
# Soak probe: hammer the lifecycle loops that could leak — spawn/kill, drop/
# collect, structure build/raze, save/load — then diff object counts.
# Any secular rise means a leak slipped past the caps.
func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 120: # let worldgen finish — an early baseline reads warmup as growth
		await process_frame
	var game = main.get_node("Game")
	var rng = RandomNumberGenerator.new()
	rng.seed = 7

	var base_n := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("=== baseline objects=%d pals=%d drops=%d nodes(el)=%d ==="
		% [base_n, game.pals.size(), game.drops.size(), game.entity_layer.get_child_count()])

	for round in 3:
		# 1) spawn + kill churn: wild pals live, drop loot, get collected
		var made := []
		for i in 40:
			var a: float = rng.randf() * TAU
			var at: Vector2 = game.player.pos + Vector2(cos(a), sin(a)) * rng.randf_range(4, 18)
			if game.world.blocked(int(at.x), int(at.y)):
				continue
			var pool: Array = SpeciesGen.zone_pool(game.world.zone_at(int(at.x), int(at.y)))
			var p: Pal = game.gen_pal(pool[rng.randi_range(0, pool.size() - 1)], 5, at)
			p.mode = "wild"
			game.pals.append(p)
			made.append(p)
		for p in made:
			if is_instance_valid(p) and p.mode == "wild":
				p.hit(99999, 1.0, true) # kill_pal path: drops, xp, node freed
		# collect every drop the kills spilled
		for d in game.drops.duplicate():
			game.take_drop(d)
		# 2) structure churn: build + raze a few cheap cells near the player
		game.add_item("wood", 400); game.add_item("stone", 400)
		var built := []
		for i in 12:
			var a2: float = rng.randf() * TAU
			var cell := Vector2i(int(game.player.pos.x + cos(a2) * (4 + i % 4)),
				int(game.player.pos.y + sin(a2) * (4 + i % 4)))
			if game.place_structure("wooden_wall", cell.x, cell.y):
				built.append(cell)
		for c in built:
			if game.structures.has(c):
				game.raze_structure(game.structures[c])
		# 2b) box churn: catch -> box -> butcher round trip on disposable pals
		game.add_item("meat_cleaver", 1)
		for i3 in 6:
			var cp: Pal = game.gen_pal("chikipi", 3, game.player.pos)
			cp.mode = "box"; game.box.append(cp); game.box_pal(cp)
			game.butcher_pal(cp.uid)
		for d2 in game.drops.duplicate():
			game.take_drop(d2)
		# 3) save/load round trip rewrites the world state wholesale
		game.save_game()
		game.load_game()
		for i2 in 120: # let kill floaters/labels age out before counting — transients aren't leaks
			await process_frame
		print("=== round %d objects=%d pals=%d box=%d drops=%d el=%d ==="
			% [round, int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				game.pals.size(), game.box.size(),
				game.drops.size(), game.entity_layer.get_child_count()])

	var end_n := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("=== LEAK? baseline=%d end=%d delta=%d ===" % [base_n, end_n, end_n - base_n])
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
