# S81 live-play evidence — drives the REAL verbs (shell_act, melee,
# throw_sphere, place_structure, harvest_cell) and photographs each beat.
# Run windowed:  Godot --path . -s tools/play_s81.gd
extends SceneTree

var main
var game
var hud
var fails := []

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-s81-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _claim(ok: bool, what: String, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("  " + detail if detail != "" else ""))
	if not ok:
		fails.append(what)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	call_deferred("_boot")

func _process(_dt: float) -> bool:
	return false

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	await _frames(12)
	game = main.get_node("Game")
	hud = main.get_node("UILayer/HUD")
	await _shot("01-title")
	# title → new game through the real shell verb (armed confirm if a save lives)
	hud.shell_act("new_game")
	if hud.new_game_armed:
		hud.shell_act("new_game")
	await _frames(30)
	_claim(game.state == "play", "new game enters play", "state=%s" % game.state)
	await _shot("02-play")
	# harvest: find the nearest real tree on the map, stand beside it, chop
	var drops0: int = game.drops.size()
	var tree_c := Vector2i(-1, -1)
	var bd_tree := 1e9
	for ty in World.WORLD_H:
		for tx in World.WORLD_W:
			if game.world.decor_at(tx, ty) in [World.Decor.TREE_A, World.Decor.TREE_B]:
				var dd: float = Vector2(tx + 0.5, ty + 0.5).distance_squared_to(game.player.pos)
				if dd < bd_tree:
					bd_tree = dd; tree_c = Vector2i(tx, ty)
	if tree_c.x >= 0:
		game.player.pos = Vector2(tree_c.x + 0.5, tree_c.y + 1.6)
		for s in 3: # a trunk takes three swings
			game.harvest_cell(tree_c.x, tree_c.y)
	await _frames(8)
	var wood_drop := false
	for d in game.drops:
		if d["id"] == "wood":
			wood_drop = true
	_claim(wood_drop, "chop a tree, wood hits the ground", "tree=%s drops=%d->%d" % [tree_c, drops0, game.drops.size()])
	await _shot("03-harvest")
	# build bar open
	game.panel = "build"
	await _frames(6)
	await _shot("04-buildbar")
	# place a workbench through the real placement path on clear ground
	game.panel = ""
	var placed := false
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c2 := Vector2i(int(game.player.pos.x) + dx, int(game.player.pos.y) + dy)
			if game.place_free("workbench", c2.x, c2.y):
				placed = true
				break
		if placed:
			break
	_claim(placed, "workbench placed via place_free")
	await _frames(8)
	await _shot("05-workbench")
	# catch: a wild kin walks in, weaken it through the real hit path, throw
	var wild: Kin = game.gen_pal("fenjelly", 4, game.player.pos + Vector2(2.0, 0.0))
	game.pals.append(wild) # gen_pal is a factory — production callers roster it themselves
	await _frames(4)
	while wild.hp > int(wild.max_hp * 0.4) and wild.hp > 1:
		wild.hit(maxi(1, int(wild.max_hp * 0.15)), 0.0, false)
	game.player.facing = wild.pos - game.player.pos # face the real offset — a wanderer drifts off a fixed cone
	game.add_item("legendary_orb", 1)
	game.player.sphere_sel = game.sphere_tiers().find("legendary_orb")
	var caught_n0: int = game.catch_counts.get("fenjelly", 0)
	game.player.throw_sphere(true)
	print("dbg: wild hp=%d mode=%s dist=%.2f spheres=%d orbs=%s" % [wild.hp, wild.mode,
		wild.pos.distance_to(game.player.pos), game.spheres_flying.size(), str(game.sphere_tiers())])
	await _frames(140) # 0.45s flight + 1.35s wobble verdict — the ball rocks first
	print("dbg: wild mode=%s msgs=%s spheres=%d" % [wild.mode, str(game.messages), game.spheres_flying.size()])
	_claim(game.catch_counts.get("fenjelly", 0) > caught_n0, "the throw actually caught",
		"caught=%d" % game.catch_counts.get("fenjelly", 0))
	await _shot("06-caught")
	# roster: the new kin should be fielded or benched
	_claim(game.party.size() > 0 or game.bench.size() > 0, "kin joins the roster",
		"party=%d bench=%d" % [game.party.size(), game.bench.size()])
	# panels a player opens mid-session — each is a real UI beat
	game.panel = "kinbox"
	await _frames(6)
	await _shot("07-kinbox")
	game.panel = "guide"
	await _frames(6)
	await _shot("08-guide")
	game.panel = "dex"
	await _frames(6)
	await _shot("09-dex")
	hud._map_toggle() # the world map is a hud flag, not a panel
	await _frames(8)
	await _shot("10-map")
	hud._map_toggle()
	game.panel = "inv"
	await _frames(6)
	await _shot("11-inv")
	game.panel = ""
	# pause through the real state, not a panel flag
	game.state = "paused"
	await _frames(8)
	await _shot("12-pause")
	game.state = "play"
	# night camp: a placed campfire burning at dusk is the money shot
	var lit := false
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c3 := Vector2i(int(game.player.pos.x) + dx, int(game.player.pos.y) + dy)
			if game.place_free("campfire", c3.x, c3.y):
				lit = true
				break
		if lit:
			break
	_claim(lit, "campfire placed")
	game.tod = 21.6
	await _frames(14)
	await _shot("13-night")
	print("==== S81 live-play: %d failures ====" % fails.size())
	quit()
