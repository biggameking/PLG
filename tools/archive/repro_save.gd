extends SceneTree
func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var game = main.get_node("Game")
	# spray one of every placeable structure around the kinbox like a built base
	var bx := int(game.kinbox_pos.x); var by := int(game.kinbox_pos.y)
	var ids: Array = StructureData.STRUCTURES.keys()
	var placed := []
	var r := 3
	for sid in ids:
		if sid == "kinbox":
			continue
		var done := false
		var rr := r
		while rr < 30 and not done:
			for dx in range(-rr, rr + 1):
				for dy in range(-rr, rr + 1):
					if abs(dx) != rr and abs(dy) != rr:
						continue
					if game.place_free(sid, bx + dx, by + dy):
						placed.append(sid)
						done = true
						break
				if done:
					break
			rr += 1
		if not done:
			print("  could not place ", sid)
	var seen := []
	for k in game.structures:
		if game.structures[k] not in seen:
			seen.append(game.structures[k]["id"])
	print("BEFORE (%d): %s" % [seen.size(), str(seen)])
	game.save_game()
	game.load_game()
	var seen2 := []
	for k in game.structures:
		if game.structures[k] not in seen2:
			seen2.append(game.structures[k]["id"])
	print("AFTER (%d): %s" % [seen2.size(), str(seen2)])
	for s in seen:
		if s not in seen2:
			print("LOST: ", s)
	quit(0)
func _initialize() -> void:
	call_deferred("_boot")
