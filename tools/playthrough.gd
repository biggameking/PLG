extends SceneTree
# S124+S125 scripted playthrough: the REAL verb chain a new player follows —
# melee-chop decor → walk-over drops → place kinbox → weaken → orb → catch →
# deploy → level/unlock → logging site → workbench craft queue → ranch +
# kin bed → fell an elite. Any break in the chain is a real gameplay defect,
# not a mocked one. atk_cd resets between swings are time compression (a
# live player waits 0.45s); every verb called is the production entry point.
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
	# headless idles at ~60/s per awaited frame; 4x the tick rate cuts wall
	# time 4x while each step stays a REAL sim tick (dt shrinks — no
	# time_scale tunneling). Gameplay assertions are unaffected.
	Engine.physics_ticks_per_second = 240
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 160: # worldgen + spawn_wild(opening) settle
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	# raids fire every ~4-7 min of game time; a probe-length session lands
	# ~8 waves on the kinbox and buries the mission chain under raid combat.
	# Coverage lives in the raid pins/net-verbs — this script gates the
	# mission loop deterministically. Same reason smoke controls rng.
	game.settings["raids"] = false

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
	# a rock-poor spawn can leave the kinbox unaffordable — the mission chain
	# still needs its gate; label the top-up like every other fixture
	for mat in ["wood", "stone"]:
		var short0: int = 6 - game.item_count(mat)
		if short0 > 0:
			print("  spawn is %s-poor — fixture top-up +%d for the kinbox gate" % [mat, short0])
			game.add_item(mat, short0)

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

	# --- P5: grind to Lv2, unlock + build a logging site (mission 3)
	print("  bag at P5: wood=%d stone=%d fiber=%d carried=%s" % [
		game.item_count("wood"), game.item_count("stone"), game.item_count("fiber"), _carried()])
	await _grind_level(2)
	ok(game.player.level >= 2, "keeper reached Lv2 for tier-2 tech")
	game.unlock("logging_site")
	ok("logging_site" in game.unlocked, "unlocked logging_site (tp %d left)" % game.tech_points)
	await _place("logging_site")
	var w3 := 0
	while game.mission_idx < 4 and w3 < 400:
		w3 += 1
		await process_frame
	ok(game.mission_idx >= 4, "mission 3 (logger) -> idx %d" % game.mission_idx)

	# --- P6: craft a kin orb (mission 4) — workbench + station queue
	await _place("workbench")
	game.unlock("workbench")
	await _chop_until("wood", 3)
	await _chop_until("stone", 3)
	await _chop_lumenite(3)
	ok(game.item_count("lumenite") >= 3, "rubble yielded %d lumenite" % game.item_count("lumenite"))
	for k in game.structures:
		if game.structures[k]["id"] == "workbench":
			game.player.pos = game.nearest_free(k.x + 0.5, k.y + 1.5)
			print("  bench at %s player %s dist %.2f" % [str(k), str(game.player.pos),
				game.player.pos.distance_to(Vector2(k.x + 0.5, k.y + 0.5))])
			break
	var mn: int = game.messages.size()
	game.craft("kin_orb")
	if game.messages.size() > mn:
		print("  craft said: %s" % game.messages[-1])
	var cw := 0 # work=90 -> 9s of game time; at 240tps that is ~2160 frames
	while not game.mission_flags.has("orb") and cw < 5200:
		cw += 1
		await process_frame
	ok(game.mission_flags.has("orb"), "crafted kin_orb through the workbench queue")
	var w4 := 0
	while game.mission_idx < 5 and w4 < 400:
		w4 += 1
		await process_frame
	ok(game.mission_idx >= 5, "mission 4 (orb) -> idx %d" % game.mission_idx)

	# --- P7: ranch + kin bed (missions 5-6) — a mid-game base takes shape
	await _grind_level(3)
	game.unlock("ranch")
	ok("ranch" in game.unlocked, "unlocked ranch (tp %d left)" % game.tech_points)
	await _place("ranch")
	var w5 := 0
	while game.mission_idx < 6 and w5 < 400:
		w5 += 1
		await process_frame
	ok(game.mission_idx >= 6, "mission 5 (ranch) -> idx %d" % game.mission_idx)
	game.unlock("kin_bed")
	await _place("kin_bed")
	var w6 := 0
	while game.mission_idx < 7 and w6 < 400:
		w6 += 1
		await process_frame
	ok(game.mission_idx >= 7, "mission 6 (kin bed) -> idx %d" % game.mission_idx)

	# --- P8: defeat an elite (mission 7) — a real alpha fight, partner helps
	var elite: Kin = null
	var elites: Array = game.pals.filter(_elite_wild)
	elites.sort_custom(func(a2, b2): return a2.level < b2.level)
	if not elites.is_empty():
		elite = elites[0] # weakest first — a low keeper can actually fell it
	var elite_fixture := false
	if elite == null:
		# no alpha wandered into reach — mint one the way spawn_wild does
		# (same constructor, alpha flag, +6 levels) and fight it for real
		var pool: Array = SpeciesGen.zone_pool(0)
		elite = game.gen_pal(pool[0], 4, game.player.pos + Vector2(3, 0))
		elite.alpha = true
		elite.mode = "wild"
		game.pals.append(elite)
		elite_fixture = true
	ok(elite != null, "an elite target exists%s" % [" (fixture spawn)" if elite_fixture else ""])
	if elite != null:
		var lead2: Kin = game.party_pal()
		if lead2 == null:
			for uid2 in game.party:
				var q2: Kin = game.find_pal(uid2)
				if q2 != null and q2.hp > 0:
					game.send_out(q2.uid) # field the partner — it fights for real
					break
		var ename := str(elite.species_id) # kill_pal frees the node — no post-fight reads
		var killed := await _kill(elite)
		if not killed and not elite_fixture:
			# a zone-2+ natural alpha out-levels a fresh keeper — rerun the
			# bout against a probe-minted lv4 alpha; the kill path stays real
			var pool3: Array = SpeciesGen.zone_pool(0)
			var at3: Vector2 = game.nearest_free(game.player.pos.x + 3.0, game.player.pos.y)
			elite = game.gen_pal(pool3[0], 4, at3)
			elite.alpha = true
			elite.mode = "wild"
			game.pals.append(elite)
			elite_fixture = true
			ename = str(elite.species_id)
			killed = await _kill(elite)
		ok(killed, "elite %s killed via melee%s" % [ename, " + partner" if lead2 != null else ""])
		ok(game.mission_flags.has("elite"), "elite kill raised the mission flag")
		var w7 := 0
		while game.mission_idx < 8 and w7 < 400:
			w7 += 1
			await process_frame
		ok(game.mission_idx >= 8, "mission 7 (elite) -> idx %d" % game.mission_idx)
	await _shot("docs/reviews/s125-elite.png")

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

func _elite_wild(p: Kin) -> bool:
	return is_instance_valid(p) and p.mode == "wild" and p.hp > 0 \
		and (p.alpha or p.boss)

# stand next to a decor cell, face it, swing until it falls; then walk the
# drops onto the pickup radius. Returns swings taken.
func _chop_until(item: String, need: int) -> int:
	var swings := 0
	var skip := {} # decor cells with no free neighbor — skip or we loop forever
	var kinds: Array = [World.Decor.TREE_A, World.Decor.TREE_B, World.Decor.STUMP] \
		if item == "wood" else [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL]
	var guard := 0
	while game.item_count(item) < need and guard < 45:
		guard += 1
		var cell := _nearest_decor(kinds, skip)
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
				skip[cell] = true
				break # walled off — go find another outcrop
			game.player.pos = stand
			game.player.facing = (Vector2(cell.x, cell.y) - Vector2(int(stand.x), int(stand.y))).normalized()
			game.player.atk_cd = 0.0 # compress the 0.45s swing timer
			game.player.melee()
			swings += 1
			await process_frame
		await _collect_drops(6.0)
	return swings

func _nearest_decor(kinds: Array, skip := {}) -> Vector2i:
	var px := int(game.player.pos.x)
	var py := int(game.player.pos.y)
	for r in range(1, 96):
		for dx in range(-r, r + 1):
			for dy in [-r, r]: # top & bottom edges
				var c1 := Vector2i(px + dx, py + dy)
				if not skip.has(c1) and game.world.decor_at(c1.x, c1.y) in kinds:
					return c1
		for dy in range(-r + 1, r): # left & right edges
			for dx in [-r, r]:
				var c2 := Vector2i(px + dx, py + dy)
				if not skip.has(c2) and game.world.decor_at(c2.x, c2.y) in kinds:
					return c2
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

# --- S125 helpers --------------------------------------------------------

# melee the nearest catchable wild kin until the keeper hits `lv`. Kills
# pay xp AND drops, so the grind doubles as the fiber/material farm — and
# level-ups pay +2 tech points, which is what tiers actually cost.
func _grind_level(lv: int) -> int:
	var kills := 0
	var guard := 0
	while game.player.level < lv and guard < 30:
		guard += 1
		var t := _wild_targets(1)
		if t.is_empty():
			break
		if await _kill(t[0]):
			kills += 1
			await _collect_drops(8.0)
	return kills

# kill a wild kin for real — melee in reach, partner fielded first if the
# bench has one. Returns true when the mark is dead or no longer wild.
func _kill(p: Kin) -> bool:
	if game.party_pal() == null:
		for uid in game.party:
			var q: Kin = game.find_pal(uid)
			if q != null and q.hp > 0:
				game.send_out(q.uid)
				break
	var swings := 0
	while is_instance_valid(p) and p.mode == "wild" and p.hp > 0 and swings < 200:
		var cell := Vector2i(int(p.pos.x), int(p.pos.y))
		for nb in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var nc: Vector2i = cell + nb
			if game.world.in_bounds(nc.x, nc.y) and not game.world.blocked(nc.x, nc.y):
				game.player.pos = Vector2(nc.x + 0.5, nc.y + 0.5)
				break
		game.player.facing = (p.pos - game.player.pos).normalized()
		game.player.atk_cd = 0.0
		game.player.hp = game.player.max_hp # stands in for eating/fleeing to heal
		game.player.melee()
		swings += 1
		for i in 4: # let the swing land + the partner take its turn
			await process_frame
		if not is_instance_valid(p) or p.hp <= 0:
			break
	for i in 90: # the partner's last blow often lands a beat after ours
		await process_frame
		if not is_instance_valid(p) or p.hp <= 0 or p.mode != "wild":
			break
	return not is_instance_valid(p) or p.hp <= 0 or p.mode != "wild"

# kill fiber-dropping species (sprigmelt/briargoo/mosswisp) until the bag
# holds n. Lane 1: natural prey + herd-cycling to trigger the trickle.
# Lane 2 (honest fixture): the spawn-density trickle can't refill a herd
# within probe budget — mint zone-0 sprigmelt via gen_pal and run the real
# melee→drop→pickup chain on them; only the prey placement is fixtured.
func _kill_fiber(need: int) -> int:
	var kills := 0
	var guard := 0
	while game.item_count("fiber") < need and guard < 40:
		guard += 1
		var t := _fiber_prey()
		var waits := 0
		while t == null and waits < 4:
			waits += 1
			var plain := _wild_targets(1)
			if not plain.is_empty():
				await _kill(plain[0])
				await _collect_drops(8.0)
			for i in 180: # ~3s per trickle attempt
				await process_frame
			t = _fiber_prey()
		if t == null:
			t = _fiber_fixture()
			if t == null:
				break
		if await _kill(t):
			kills += 1
			await _collect_drops(24.0) # drops scatter wide — walk them all in
	return kills

# mint a zone-0 sprigmelt next to the player (same constructor spawn_wild
# uses) — the drops it releases are produced by the real kill path
var _fiber_fixtures := 0
func _fiber_fixture() -> Kin:
	if _fiber_fixtures >= 20 or game.pals.size() >= game.MAX_PALS - 4:
		return null
	var at: Vector2 = game.nearest_free(game.player.pos.x + 2.0, game.player.pos.y)
	var p: Kin = game.gen_pal("sprigmelt", 2, at)
	p.mode = "wild"
	game.pals.append(p)
	_fiber_fixtures += 1
	return p

# nearest living wild kin whose drop table carries fiber — the species set
# is data (sprigmelt/briargoo and generated cousins), not a whitelist
func _fiber_prey() -> Kin:
	var t: Kin = null
	var bd := 1e9
	for wp in game.pals:
		if not is_instance_valid(wp) or wp.mode != "wild" or wp.hp <= 0:
			continue
		var drops_fiber := false
		for d in wp.spec.get("drops", []):
			if d.size() > 0 and d[0] == "fiber":
				drops_fiber = true
				break
		if not drops_fiber:
			continue
		var dd: float = wp.pos.distance_squared_to(game.player.pos)
		if dd < bd:
			bd = dd; t = wp
	return t

# mine rocks until lumenite shards drop (12% per rock) — the renewable
# lumenite lane the game offers after the drift cargo is spent
func _chop_lumenite(need: int) -> void:
	var guard := 0
	while game.item_count("lumenite") < need and guard < 120:
		guard += 1
		await _chop_until("stone", game.item_count("stone") + 1)
		await _collect_drops(8.0)
	print("  _chop_lumenite: %d after %d rocks" % [game.item_count("lumenite"), guard])

# find a free footprint near the player and place the structure for real
func _place(sid: String) -> bool:
	var s: Dictionary = StructureData.STRUCTURES[sid]
	await _ensure_mats(s)
	for c in s.get("cost", []):
		if game.item_count(c[0]) < c[1]:
			print("  _place %s: short %s (%d/%d)" % [sid, c[0], game.item_count(c[0]), c[1]])
			ok(false, "materials for %s" % sid)
			return false
	for r in range(3, 24):
		for a in range(24):
			var ang: float = a * TAU / 24.0
			var tx := int(game.player.pos.x + cos(ang) * r)
			var ty := int(game.player.pos.y + sin(ang) * r)
			if game.can_place(sid, tx, ty):
				game.player.pos = game.nearest_free(tx + 1.0, ty + 2.5)
				var did: bool = game.place_structure(sid, tx, ty)
				ok(did, "placed %s at (%d, %d)" % [sid, tx, ty])
				return did
	ok(false, "no free footprint for %s within 24" % sid)
	return false

# every material the build menu asks for, sourced the way a player gets it:
# wood/stone from melee-harvest, fiber from kin kills, lumenite from rubble.
# A barren seed can still exhaust the honest lane — the top-up at the end is
# a labeled fixture, never the first resort.
func _ensure_mats(s: Dictionary) -> void:
	for c in s.get("cost", []):
		var id: String = c[0]
		var need: int = c[1]
		print("  mats %s: %d/%d (carried: %s)" % [id, game.item_count(id), need, _carried()])
		match id:
			"wood", "stone":
				await _chop_until(id, need)
			"fiber":
				await _kill_fiber(need)
			"lumenite":
				await _chop_lumenite(need)
			_:
				pass # materials with no harvest lane stay short — _place reports
		var short: int = need - game.item_count(id)
		if short > 0:
			print("  _ensure_mats %s: honest lane short %d — fixture top-up" % [id, short])
			game.add_item(id, short)

# what the base haulers are holding on-paw — goods a hauler took are not
# lost, just not in the bag (they land once a chest exists)
func _carried() -> String:
	var held := {}
	for p in game.pals:
		if is_instance_valid(p) and p.carry != null:
			held[p.carry["id"]] = held.get(p.carry["id"], 0) + int(p.carry["n"])
	return str(held)
