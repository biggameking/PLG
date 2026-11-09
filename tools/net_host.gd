extends SceneTree
var main
func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
	game.net.host()
	var fo := FileAccess.open("res://tools/net_host_state.txt", FileAccess.WRITE)
	fo.store_line(str(game.world.seed))
	fo.store_line("%d,%f" % [game.day, game.tod])
	fo.close()
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		n += 1
		if n % 60 == 0:
			var f2 := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ_WRITE)
			if f2:
				f2.seek_end()
				f2.store_line("ghosts=%d peers=%s" % [game.net.ghosts.size(), str(get_multiplayer().get_peers())])
				f2.close()
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
