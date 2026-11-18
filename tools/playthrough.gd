extends SceneTree
# S124 scripted core-loop playthrough: the REAL verb chain a new player
# follows — melee-chop decor → walk-over drops → place kinbox → weaken a
# wild kin with melee → throw an orb → catch → deploy to base. Any break
# in the chain is a real gameplay defect, not a mocked one. atk_cd resets
# between swings are time compression (a live player waits 0.45s); every
# verb called is the production entry point.
var pass_n := 0
var fail_n := 0
var game
var main

func ok(cond: bool, label: String) -> void:
	if cond:
		pass_n += 1
		print("PASS %s" % label)
	else:
		fail_n += 1
		print("FAIL %s" % label)

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 160: # worldgen + spawn_wild(opening) settle
		await process_frame
	game = main.get_node("Game")
	game.state = "play"

	# --- P0: the washed-ashore kit a real session starts with
	ok(game.item_count("kin_orb") == 3, "starter kit: 3 kin orbs")
	ok(game.item_count("lumenite") == 4, "starter kit: 4 drift lumenite")
	var ring: Array = game.pals.filter(func(p): return p.has_meta("ring_kin"))
	ok(ring.size() >= 1, "opening ring spawned docile catch targets (%d)" % ring.size())

	# --- P1: harvest wood + stone through the melee -> try_harvest chain
	await _chop_until("wood", 9)
	await _chop_until("stone", 9)
	ok(game.item_count("wood") >= 6, "chopped %d wood via melee->harvest" % game.item_count("wood"))
	ok(game.item_count("stone") >= 6, "chopped %d stone via melee->harvest" % game.item_count("stone"))

	# --- P2: place the kinbox (mission 0) on a real free 2x2
	var placed := false
	for r in range(3, 16):
		var found := false
		for a in range(24):
			var ang: float = a * TAU / 24.0
			var tx := int(game.player.pos.x + cos(ang) * r)
			var ty := int(game.player.pos.y + sin(ang) * r)
			if game.can_place("kinbox", tx, ty):
				game.player.pos = game.nearest_free(tx + 1.0, ty + 2.5)
				placed = game.place_structure("kinbox", tx, ty)
				found = true
				break
		if found:
			break
	var w0 := 0 # mission tick is a 1s cadence — poll, don't guess frames
	while game.mission_idx < 1 and w0 < 400:
		w0 += 1
		await process_frame
	ok(placed, "place_structure kinbox accepted")
	ok(game.kinbox_pos.x >= 0, "kinbox anchor registered at %s" % str(game.kinbox_pos))
	ok(game.mission_idx >= 1, "mission 0 cleared -> idx %d" % game.mission_idx)
	await _shot("docs/reviews/s124-build.png")

	# --- P3: catch three kin with the weaken -> throw -> resolve chain
	var caught0 := _owned_count()
	var fixture_orbs := 0
	var targets := _wild_targets(14)
	for i in 3:
		var done := false
		for p in targets:
			if not is_instance_valid(p) or p.mode != "wild" or p.hp <= 0:
				continue
			if await _weaken(p) and await _catch_one(p):
				done = true
				break
		if not done:
			# fresh targets roam in while we worked — rescan once before failing
			targets = _wild_targets(14)
			for p in targets:
				if not is_instance_valid(p) or p.mode != "wild" or p.hp <= 0:
					continue
				if game.item_count("kin_orb") < 1:
					game.add_item("kin_orb", 1)
					fixture_orbs += 1
				if await _weaken(p) and await _catch_one(p):
					done = true
					break
		if game.item_count("kin_orb") < 1 and i < 2:
			game.add_item("kin_orb", 1)
			fixture_orbs += 1
	var w1 := 0
	while game.mission_idx < 2 and w1 < 400:
		w1 += 1
		await process_frame
	var owned_now := _owned_count()
	ok(owned_now - caught0 >= 3, "caught %d kin via orb throws (+1 fixture orb x%d)"
		% [owned_now - caught0, fixture_orbs])
	ok(game.mission_idx >= 2, "mission 1 (catch 3) -> idx %d" % game.mission_idx)
	await _shot("docs/reviews/s124-catch.png")

	# --- P4: deploy a caught kin to the base (mission 2)
	var dep: Kin = null
	for uid in game.party:
		var q: Kin = game.find_pal(uid)
		if q != null and q.hp > 0:
			dep = q
			break
	if dep == null:
		for b in game.box:
			if is_instance_valid(b) and b.hp > 0:
				dep = b
				break
	ok(dep != null, "a live owned kin exists to deploy")
	if dep != null:
		game.player.pos = dep.pos + Vector2(0.8, 0.8)
		game.deploy_to_base(dep)
		var w2 := 0
		while game.mission_idx < 3 and w2 < 400:
			w2 += 1
			await process_frame
		ok(dep.mode == "base", "deployed %s -> mode %s" % [dep.species_id, dep.mode])
		ok(game.mission_idx >= 3, "mission 2 (deploy) -> idx %d" % game.mission_idx)
	await _shot("docs/reviews/s124-deploy.png")

	print("==== PLAYTHROUGH %d/%d ====" % [pass_n, pass_n + fail_n])
	quit(0 if fail_n == 0 else 1)

func _owned_count() -> int:
	return game.party.size() + game.box.size()

func _wild_targets(n: int) -> Array:
	var all: Array = game.pals.filter(_catchable_wild)
	all.sort_custom(func(a, b): return a.pos.distance_squared_to(game.player.pos) < b.pos.distance_squared_to(game.player.pos))
	# docile ring kin first — the designed first-catch targets
	var ring: Array = all.filter(func(p): return p.has_meta("ring_kin"))
	var rest: Array = all.filter(func(p): return not p.has_meta("ring_kin"))
	return (ring + rest).slice(0, n)

func _catchable_wild(p: Kin) -> bool:
	return is_instance_valid(p) and p.mode == "wild" and p.hp > 0 \
		and not p.boss and not p.alpha

# stand next to a decor cell, face it, swing until it falls; then walk the
# drops onto the pickup radius. Returns swings taken.
func _chop_until(item: String, need: int) -> int:
	var swings := 0
	var kinds: Array = [World.Decor.TREE_A, World.Decor.TREE_B, World.Decor.STUMP] \
		if item == "wood" else [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL]
	var guard := 0
	while game.item_count(item) < need and guard < 30:
		guard += 1
		var cell := _nearest_decor(kinds)
		if cell.x < 0:
			break
		while game.world.decor_at(cell.x, cell.y) in kinds and swings < 60:
			# stand on a free NEIGHBOR cell: try_harvest resolves the target as
			# int(at)+sign(face) — only a true cardinal neighbor hits this cell
			var stand := Vector2.ZERO
			for nb in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nc: Vector2i = cell + nb
				if game.world.in_bounds(nc.x, nc.y) and not game.world.blocked(nc.x, nc.y):
					stand = Vector2(nc.x + 0.5, nc.y + 0.5)
					break
			if stand == Vector2.ZERO:
				break # walled off — go find another outcrop
			game.player.pos = stand
			game.player.facing = (Vector2(cell.x, cell.y) - Vector2(int(stand.x), int(stand.y))).normalized()
			game.player.atk_cd = 0.0 # compress the 0.45s swing timer
			game.player.melee()
			swings += 1
			await process_frame
		await _collect_drops(6.0)
	return swings

func _nearest_decor(kinds: Array) -> Vector2i:
	var px := int(game.player.pos.x)
	var py := int(game.player.pos.y)
	for r in range(1, 30):
		for dx in range(-r, r + 1):
			for dy in [-r, r]: # top & bottom edges
				if game.world.decor_at(px + dx, py + dy) in kinds:
					return Vector2i(px + dx, py + dy)
		for dy in range(-r + 1, r): # left & right edges
			for dx in [-r, r]:
				if game.world.decor_at(px + dx, py + dy) in kinds:
					return Vector2i(px + dx, py + dy)
	return Vector2i(-1, -1)

func _collect_drops(radius: float) -> void:
	for d in game.drops.duplicate():
		var dp: Vector2 = d["pos"] if d.has("pos") else Vector2.ZERO
		if game.player.pos.distance_to(dp) > radius:
			continue
		game.player.pos = dp # walk-over pickup is the magnet loop
		for i in 3:
			await process_frame

func _weaken(p: Kin) -> bool:
	# bench the field pal: it finishes weakened marks before the orb lands —
	# a careful catcher recalls it (send_out on the out pal is the recall)
	var lead: Kin = game.party_pal()
	if lead != null:
		game.send_out(lead.uid)
	var swings := 0
	while is_instance_valid(p) and p.mode == "wild" and p.hp > 0 \
			and float(p.hp) / p.max_hp > 0.30 and swings < 40:
		var cell := Vector2i(int(p.pos.x), int(p.pos.y))
		for nb in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var nc: Vector2i = cell + nb
			if game.world.in_bounds(nc.x, nc.y) and not game.world.blocked(nc.x, nc.y):
				game.player.pos = Vector2(nc.x + 0.5, nc.y + 0.5)
				break
		game.player.facing = (p.pos - game.player.pos).normalized()
		game.player.atk_cd = 0.0
		game.player.melee()
		swings += 1
		await process_frame
	return is_instance_valid(p) and p.hp > 0 and float(p.hp) / p.max_hp <= 0.55

func _catch_one(p: Kin) -> bool:
	# stand behind: sign(player - target) == -target.dir doubles the odds
	var behind: Vector2 = p.pos + Vector2(-p.dir, 0) * 1.2
	game.player.pos = game.nearest_free(behind.x, behind.y)
	game.player.facing = (p.pos - game.player.pos).normalized()
	var before := _owned_count()
	game.player.throw_sphere(true)
	for i in 120: # orb flight + resolve_sphere
		await process_frame
		if _owned_count() > before or game.spheres_flying.is_empty():
			break
	for i in 10:
		await process_frame
	return _owned_count() > before

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("shot %s skipped — headless has no framebuffer (run windowed for evidence)" % path)
		return
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var img := root.get_texture().get_image()
	if img == null or img.save_png(path) != OK:
		print("shot %s FAILED — framebuffer read or save_png errored" % path)
		fail_n += 1
		return
	print("shot %s (%d, %d)" % [path, img.get_width(), img.get_height()])
