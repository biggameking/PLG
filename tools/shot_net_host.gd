# windowed net host: hosts a session, waits for a guest ghost, screenshots
# it on screen, then waits out the join client's own shot. Run first.
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-shot-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	game.net.host()
	if not game.net.is_host: # bind refused (a stale host still owns the port)
		# — writing the state file would hand the joiner a dead handshake
		push_error("host bind failed — a previous host may still hold the port")
		quit(1)
		return
	var fo := FileAccess.open("res://tools/net_host_state.txt", FileAccess.WRITE)
	fo.store_line(str(game.world.seed))
	fo.store_line("%d,%f" % [game.day, game.tod])
	fo.close()
	# wait for the guest to join and its ghost to appear
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		if game.net.ghosts.size() > 0:
			break
	for i in 60: # let the ghost lerp to its synced spot
		await process_frame
	await _shot("net-host")
	# stay up a while so the join shot's own frame can sync too — the guest
	# walks a few tiles after sync, so the late frame shows its ghost moved
	for i in 300:
		await process_frame
	var gk: Array = game.net.ghosts.keys()
	if gk.size() > 0:
		var g0: Node2D = game.net.ghosts[gk[0]]
		print("host: guest-ghost screen=%s player screen=%s" % [
			str(g0.position), str(game.player.position)])
	await _shot("net-host2")
	quit()
