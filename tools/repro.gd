extends SceneTree
var game
func _initialize() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	game = main.get_node("Game")
	for m in ["wood","stone","fiber","lumenite","ingot","berry_seeds"]:
		game.add_item(m, 300)
	var pb := false
	var k0 := Vector2i(int(game.player.pos.x) + 3, int(game.player.pos.y) + 3)
	for tries in 300:
		if game.place_structure("kinbox", k0.x + tries % 8, k0.y + tries / 8):
			pb = true; break
	var bx := int(game.kinbox_pos.x); var by := int(game.kinbox_pos.y)
	var placed := false; var fx := -1; var fy := -1
	for r0 in range(2, 30):
		var cells := []
		for dx5 in range(-r0, r0 + 1):
			cells.append(Vector2i(bx + dx5, by - r0)); cells.append(Vector2i(bx + dx5, by + r0))
		for dy5 in range(-r0 + 1, r0):
			cells.append(Vector2i(bx - r0, by + dy5)); cells.append(Vector2i(bx + r0, by + dy5))
		for c0 in cells:
			if game.place_structure("berry_farm", c0.x, c0.y):
				fx = c0.x; fy = c0.y; placed = true; break
		if placed: break
	print("kinbox=", pb, " farm=", placed, " at=", fx, ",", fy)
	if not placed:
		quit(); return
	var st = null
	for k in game.structures:
		if game.structures[k].get("id") == "berry_farm":
			st = game.structures[k]; break
	var p = load("res://src/kin.gd").new()
	game.entity_layer.add_child(p)
	p.setup(game, "fenjelly", 3, Vector2(fx + 3, fy))
	p.mode = "base"; game.pals.append(p)
	st["workers"].append(p); p.job_site = st
	print("kin job=", p.job_site["s"].id if p.job_site else "none", " in_workers=", p in st["workers"])
	var p2 = load("res://src/kin.gd").new()
	game.entity_layer.add_child(p2)
	p2.setup(game, "dozantler", 4, Vector2(fx + 4, fy))
	p2.mode = "base"; game.pals.append(p2)
	st["workers"].append(p2); p2.job_site = st
	print("2 workers on farm")
	game.save_game()
	game.load_game()
	var found = 0
	for k in game.structures:
		if game.structures[k].get("id") == "berry_farm":
			found = game.structures[k]["workers"].size()
	var jobs = 0
	for q in game.pals:
		if q.job_site: jobs += 1
	print("post-load workers=", found, " pals_with_job=", jobs)
	quit()
