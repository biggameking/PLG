extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var game = main.get_node("Game")
	for i in 10:
		await process_frame
	game.tod = 12.0
	var la = null
	for q in game.pals:
		if q.alpha and q.mode == "wild":
			la = q; break
	if la == null:
		print("no alpha this seed")
		quit(); return
	print("sp=", la.species_id, " speed=", la.speed, " spec_spd=", la.spec.get("speed"))
	game.player.pos = la.home
	var spot: Vector2 = la.home + Vector2(0, 11)
	if game.world.blocked(int(spot.x), int(spot.y)):
		spot = la.home + Vector2(11, 0)
	la.pos = spot
	la.aggro = -1
	la.statuses.erase("sleep")
	print("home=", la.home, " pos=", la.pos)
	for i in 5:
		la.wild_ai(0.02)
		print("  step", i, " pos=", la.pos, " aggro=", la.aggro, " dist=", la.pos.distance_to(la.home))
		var nx2 := int(la.pos.x); var ny2 := int(la.pos.y)
		print("    cell blocked=", game.world.blocked(nx2, ny2), " elev=", game.world.elev_at(nx2, ny2) if game.world.has_method("elev_at") else "?")
	quit()
