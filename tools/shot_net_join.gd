# windowed net client: waits for the host marker, joins, waits for the
# host ghost + seed sync, screenshots the remote keeper on screen.
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
	# stay in "title" — join() save_game()s non-title states and would clobber
	# the real save with this boot world; _arrive_guest flips to play on sync
	DirAccess.remove_absolute("user://plg_net.cfg")
	var host_seed := -1
	for i in 600:
		await process_frame
		var fr := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ)
		if fr:
			host_seed = int(fr.get_line())
			fr.close()
			break
	game.net.join("127.0.0.1")
	var t0 := Time.get_ticks_msec()
	var synced := false
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		if game.net.ghosts.has(1) and game.world.seed == host_seed:
			synced = true
			break
	# step a few tiles away so the host's ghost reads as a second figure
	# instead of a sprite stacked under the local player — and land on a tile
	# the HOST also considers walkable, or its anti-spoof gate drops our fix
	for off in [Vector2(5, 3), Vector2(3, 5), Vector2(6, 0), Vector2(-5, -3), Vector2(0, -6)]:
		var t: Vector2 = game.player.pos + off
		if not game.world.blocked(int(t.x), int(t.y)):
			game.player.pos = t
			break
	game.player.sync_screen()
	for i in 150: # ghost lerp + a beat of pos sync both ways
		await process_frame
	var g1: Node2D = game.net.ghosts.get(1)
	print("join: synced=%s ghosts=%s seed=%d(want %d) pals=%d" % [
		synced, str(game.net.ghosts.keys()), game.world.seed, host_seed, game.pals.size()])
	if g1:
		print("join: host-ghost screen=%s player screen=%s" % [
			str(g1.position), str(game.player.position)])
	await _shot("net-join")
	for i in 260: # outlive the host's late frame — quitting early frees our ghost
		await process_frame
	quit()
