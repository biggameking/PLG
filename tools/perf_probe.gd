extends SceneTree
func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
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
