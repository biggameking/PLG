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
	var saw_peer := false # audit-50: sample the teardown tail, not just the ghost row
	while Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		n += 1
		if game.net.ghosts.size() > 0:
			saw_peer = true
		if saw_peer and game.net.ghosts.is_empty():
			# disconnect happened — record whether the teardown tail ran:
			# ghost freed AND guest state retracted AND session tags pruned
			var f3 := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ_WRITE)
			f3.seek_end()
			f3.store_line("disconnect: ghosts=0 rparty=%d tags=%d" % [
				game.remote_parties.size(), game.net.peer_tags.size()])
			f3.close()
			break
		if n % 60 == 0:
			var f2 := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ_WRITE)
			if f2:
				f2.seek_end()
				f2.store_line("ghosts=%d peers=%s" % [game.net.ghosts.size(), str(get_multiplayer().get_peers())])
				f2.close()
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
