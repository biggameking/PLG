extends SceneTree
var results := []
var main
func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
	DirAccess.remove_absolute("user://plg_net.cfg") # audit-50: no session tag residue
	var host_seed := -1
	# wait for the host marker
	for i in 300:
		await process_frame
		var fr := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ)
		if fr:
			host_seed = int(fr.get_line())
			fr.close()
			break
	game.net.join("127.0.0.1")
	var t0 := Time.get_ticks_msec()
	var synced := false
	while Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		if game.world.seed == host_seed and game.net.ghosts.has(1):
			synced = true
			break
	check("join sees host ghost", game.net.ghosts.has(1), "ghosts=%s" % str(game.net.ghosts.keys()))
	check("world seed synced", game.world.seed == host_seed, "have=%d want=%d" % [game.world.seed, host_seed])
	check("kin respawned locally", game.pals.size() > 0, "%d" % game.pals.size())
	var fr2 := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ)
	var host_day := -1
	if fr2:
		fr2.get_line()
		var l := fr2.get_line().split(",")
		if l.size() >= 2:
			host_day = int(l[0])
		fr2.close()
	check("day synced", host_day >= 0 and game.day == host_day, "day=%d host=%d" % [game.day, host_day])
	# drop loot so host's state_sync snapshot isn't needed for kin — they spawn locally
	var fails := results.filter(func(r): return r.begins_with("FAIL")).size()
	var fo := FileAccess.open("res://tools/net_join_out.txt", FileAccess.WRITE)
	for r in results:
		fo.store_line(r)
	fo.store_line("==== %d checks, %d failures ====" % [results.size(), fails])
	fo.close()
	quit(0 if fails == 0 and synced else 1)
func check(name: String, ok: bool, detail: String = "") -> void:
	results.append("%s %s  %s" % ["PASS" if ok else "FAIL", name, detail])
func _initialize() -> void:
	call_deferred("_boot")
