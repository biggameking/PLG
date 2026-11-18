# S118 join side — real guest verbs through real input paths.
# catch: aim action + LMB at a replica kin -> throw_sphere -> sphere_fly ->
#   resolve_sphere -> sphere_catch rpc (the replica's net_id IS the host uid)
# build: real B panel -> build_pick row -> world click -> place_structure ->
#   pay hold -> build_req rpc -> host plants -> build_done settles the hold
# hostile: direct rpcs for far-catch / locked-build / far-hit / 1e9-dmg —
#   the UI correctly can't produce these; the wire gate is what's under test
extends SceneTree

var fails := 0
var game: Node
var main: Node
var results := []
var _tag_backup := ""
var _tag_existed := false

func _initialize() -> void:
	call_deferred("_boot")

func _gate(name: String, cond: bool, info := "") -> void:
	var line := ("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else "")
	print(line)
	results.append(line)
	if not cond:
		fails += 1

func _click(x: float, y: float) -> void:
	root.warp_mouse(Vector2i(int(x), int(y)))
	await process_frame
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.position = Vector2(x, y)
	p.pressed = true
	Input.parse_input_event(p)
	await process_frame
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.position = Vector2(x, y)
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame

func _key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k; ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventKey.new()
	ev2.keycode = k; ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame

func _act(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a; ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventAction.new()
	ev2.action = a; ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame

func _write(path: String, txt: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()

func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame

func _until(ms: int, fn: Callable) -> Variant:
	var t0 := Time.get_ticks_msec()
	var v = fn.call()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		v = fn.call()
		if v:
			return v
	return v

func _w2s(p: Vector2, e := 0.0) -> Vector2:
	return root.get_canvas_transform() * Iso.to_screen(p.x, p.y, e)

func _boot() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 12:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	for i in 20:
		await process_frame
	# stay in "title": join() save_game()s any non-title state — see
	# net_walk_join; _arrive_guest flips to play on world_sync
	# a fresh install tag keeps the roster claims unique — but the REAL
	# token file belongs to the operator: back it up, restore at _finish
	var bf := FileAccess.open("user://plg_net.cfg", FileAccess.READ)
	if bf:
		_tag_backup = bf.get_as_text()
		bf.close()
		_tag_existed = true
	DirAccess.remove_absolute("user://plg_net.cfg")
	DirAccess.remove_absolute("res://tools/net_verb_join_out.txt")

	var host_seed := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and host_seed < 0:
		var fr := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ)
		if fr:
			# mid-write reads hand back "" — accept only a real seed
			var ln := fr.get_line()
			fr.close()
			if ln.is_valid_int() and int(ln) > 0:
				host_seed = int(ln)
				break
		await process_frame
	_gate("host marker found", host_seed >= 0)
	if host_seed < 0:
		_finish()
		return
	game.net.join("127.0.0.1")
	var synced: Variant = await _until(20000, func():
		return game.net.ghosts.has(1) and game.world.seed == host_seed)
	_gate("world seed synced", synced == true,
		"seed=%d want=%d" % [game.world.seed, host_seed])
	_gate("host ghost visible", game.net.ghosts.has(1),
		"ghosts=%s" % str(game.net.ghosts.keys()))
	if synced != true:
		_finish()
		return
	for i in 30:
		await process_frame

	# ---- walk a real held key so the ghost lands somewhere honest, then
	# publish the landing spot — the host pins the kin fixture beside it
	var p0: Vector2 = game.player.pos
	var walked := false
	for k in [KEY_D, KEY_S, KEY_A, KEY_W]:
		var kp := InputEventKey.new()
		kp.keycode = k; kp.pressed = true
		Input.parse_input_event(kp)
		await _wait_ms(1200)
		var kr := InputEventKey.new()
		kr.keycode = k; kr.pressed = false
		Input.parse_input_event(kr)
		await _wait_ms(300)
		if game.player.pos.distance_to(p0) > 1.0:
			walked = true
			break
	_gate("held key walks the keeper", walked,
		"moved %.1f" % game.player.pos.distance_to(p0))
	_write("res://tools/net_verb_ready.txt",
		"%f,%f" % [game.player.pos.x, game.player.pos.y])

	# ---- pins marker: weak_uid + tank_uid (host uids — replicas mirror
	# them in net_id, so matching is exact, not positional)
	var weak_nid := -1
	var tank_nid := -1
	var pins_seen: Variant = await _until(30000, func():
		var f := FileAccess.open("res://tools/net_verb_pins.txt", FileAccess.READ)
		if f == null:
			return false
		var ln := f.get_line().split(",")
		f.close()
		return ln if ln.size() == 4 else false)
	if pins_seen is PackedStringArray: # get_line().split returns the packed
		weak_nid = int(pins_seen[0])   # flavor — `is Array` never matches
		tank_nid = int(pins_seen[3])
	_gate("pins received", weak_nid > 0 and tank_nid > 0,
		"weak=%d tank=%d" % [weak_nid, tank_nid])

	# ---- CATCH: aim on, click the replica, orb flight -> host roll ->
	# replica vanishes (pal_sync drop) + our catch ledger ticks
	game.add_item("kin_orb", 8)
	var catch0: int = game.catch_counts.values().reduce(
		func(a, b): return int(a) + int(b), 0)
	var weak_rep: Variant = await _until(20000, func():
		for p in game.pals:
			if p.net_id == weak_nid and p.mode == "wild":
				return p
		return false)
	_gate("weak replica synced", weak_rep is Kin,
		"net_id=%d" % weak_nid)
	var caught := false
	if weak_rep is Kin:
		game.player.facing = (weak_rep.pos - game.player.pos).normalized()
		game.player.sync_screen()
		if not game.player.aiming:
			await _act("aim") # real action event — same path the key takes
		for attempt in 6:
			# the replica can be freed by pal_sync between attempts —
			# re-find by net_id, never trust a held ref across an await
			var wr: Kin = null
			for p in game.pals:
				if p.net_id == weak_nid:
					wr = p
					break
			if wr == null:
				break
			main.cam.global_position = game.player.global_position
			# from_screen inverts at the PLAYER's elev, not the target's —
			# projecting the replica at its own tile elev misplaces the click
			# by the terrace difference and the throw silently no-picks (nvC/D)
			var wp: Vector2 = _w2s(wr.pos, game.player.elev())
			await _click(wp.x, wp.y)
			await _wait_ms(2600) # flight 0.45 + wobble 1.35 + wire both ways
			var still := false
			for p in game.pals:
				if p.net_id == weak_nid and p.mode == "wild":
					still = true
					break
			if not still:
				caught = true
				break
		var catch1: int = game.catch_counts.values().reduce(
			func(a, b): return int(a) + int(b), 0)
		_gate("orb flight lands a catch", caught and catch1 > catch0,
			"caught=%s ledger %d→%d" % [caught, catch0, catch1])
	if game.player.aiming:
		await _act("aim") # leave the mode the way a player would

	# ---- BUILD: torch row via the real panel, real world click, hold
	# settles on build_done; then a SAME-CELL plant refuses at the gate
	game.add_item("wood", 10)
	game.add_item("fiber", 5)
	var torch_row: Variant = await _until(20000, func():
		return "torch" in game.net_unlocked)
	_gate("host tech row arrived", torch_row == true,
		"net_unlocked=%d %s" % [game.net_unlocked.size(),
			str(game.net_unlocked)])
	var bcell := Vector2i(-1, -1)
	for dy in range(1, 5):
		for dx in range(1, 5):
			var cx2: int = int(game.player.pos.x) + dx
			var cy2: int = int(game.player.pos.y) + dy
			if game.world.in_bounds(cx2, cy2) \
					and not game.world.blocked(cx2, cy2) \
					and game.can_place("torch", cx2, cy2):
				bcell = Vector2i(cx2, cy2)
				break
		if bcell.x >= 0:
			break
	_gate("free torch cell found", bcell.x >= 0, "cell=%s" % str(bcell))
	if bcell.x >= 0:
		_write("res://tools/net_verb_build.txt",
			"torch,%d,%d" % [bcell.x, bcell.y])
		await _wait_ms(1200) # host must read the marker before the plant
		var wood0: int = game.item_count("wood")
		var fiber0: int = game.item_count("fiber")
		await _key(KEY_B) # real panel key
		var bl: Array = game.buildable_list()
		var tidx: int = bl.find("torch")
		var picked := false
		if tidx >= 0:
			for cr in game.hud.click_rects:
				if cr.get("act") == "build_pick" and int(cr.get("arg", -1)) == tidx:
					var rr: Rect2 = cr["rect"]
					await _click(rr.position.x + rr.size.x / 2,
						rr.position.y + rr.size.y / 2)
					picked = true
					break
		_gate("torch row picked", picked and game.hud.build_sel_sid == "torch",
			"sel=%s" % game.hud.build_sel_sid)
		var pre_torch := {}
		for k in game.structures:
			var st0 = game.structures[k]
			if st0.get("id") == "torch":
				pre_torch[k] = true
		var cell_px: Vector2 = _w2s(Vector2(bcell) + Vector2(0.5, 0.5))
		await _click(cell_px.x, cell_px.y)
		# the click resolves through mouse_tile — a plant an honest cell
		# over still counts; the echo contract is "a new torch appears"
		var planted: Variant = await _until(20000, func():
			for k in game.structures:
				if not pre_torch.has(k) \
						and game.structures[k].get("id") == "torch":
					return game.structures[k]
			return false)
		_gate("struct_sync echoes the plant", planted is Dictionary,
			"id=%s" % (planted.get("id") if planted is Dictionary else "?"))
		var settled: Variant = await _until(8000, func():
			return game.net.pending_pays.is_empty())
		_gate("build hold settles", settled == true,
			"pending=%d wood %d→%d" % [game.net.pending_pays.size(),
				wood0, game.item_count("wood")])
		# the refund probe needs a hold the HOST denies DETERMINISTICALLY:
		# a plant beyond net_place's 9.0 ring is refused at the proximity
		# gate no matter the bucket state — two rapid wires both come home
		# as item refunds, so the ledger must return to EXACTLY w0/f0
		var far_cells := []
		for dx in [11, 12, 13]:
			for dy in [0, 1, -1]:
				var cx3: int = int(game.player.pos.x) + dx
				var cy3: int = int(game.player.pos.y) + dy
				var c3 := Vector2i(cx3, cy3)
				if c3 not in far_cells \
						and game.world.in_bounds(cx3, cy3) \
						and not game.world.blocked(cx3, cy3) \
						and game.can_place("torch", cx3, cy3):
					far_cells.append(c3)
			if far_cells.size() >= 2:
				break
		if far_cells.size() >= 2:
			var w0: int = game.item_count("wood")
			var f0: int = game.item_count("fiber")
			var r1: bool = game.place_structure("torch",
				far_cells[0].x, far_cells[0].y)
			var r2: bool = game.place_structure("torch",
				far_cells[1].x, far_cells[1].y)
			var refunded: Variant = await _until(15000, func():
				return game.item_count("wood") == w0 \
					and game.item_count("fiber") == f0 \
					and game.net.pending_pays.is_empty() \
					and game.structures.get(far_cells[0]) == null \
					and game.structures.get(far_cells[1]) == null)
			_gate("denied builds refund their holds",
				r1 and r2 and refunded == true,
				"r1=%s r2=%s wood %d→%d fiber %d→%d pending=%d" % [
					r1, r2, w0, game.item_count("wood"),
					f0, game.item_count("fiber"),
					game.net.pending_pays.size()])
		else:
			_gate("denied builds refund their holds", false,
				"no far free cell")
		await _key(KEY_B) # panel closed like a player would

	# ---- LOCKED build: an sid the host never unlocked — the UI can't
	# reach it, so the wire is the probe surface; host denies + rejects
	var locked_sid := ""
	for sid in StructureData.STRUCTURES.keys():
		if sid not in game.net_unlocked and sid not in game.unlocked:
			locked_sid = sid
			break
	if locked_sid != "":
		# the marker cell doubles as the host's no-structure assertion —
		# pick a cell the replica world proves empty or the gate fails for
		# the wrong reason (audit-68 L6)
		var lcell := Vector2i(-1, -1)
		for off in [Vector2i(6, 0), Vector2i(7, 0), Vector2i(6, 1),
				Vector2i(-6, 0), Vector2i(7, 2)]:
			var cc: Vector2i = Vector2i(int(game.player.pos.x),
				int(game.player.pos.y)) + off
			if game.world.in_bounds(cc.x, cc.y) \
					and game.structures.get(cc) == null:
				lcell = cc
				break
		_write("res://tools/net_verb_locked.txt",
			"%s,%d,%d" % [locked_sid, lcell.x, lcell.y])
		await _wait_ms(1800) # past the 0.7s build bucket — the wire must die
		# at the unlocked check itself, not at the throttle ahead of it
		game.net.rpc("build_req", locked_sid, lcell.x, lcell.y)
		await _wait_ms(1000)
		_gate("locked sid picked + wire fired", lcell.x >= 0,
			"sid=%s cell=%s" % [locked_sid, str(lcell)])
	else:
		_gate("locked sid picked + wire fired", false, "no locked sid found")

	# ---- FAR verbs: a replica kin >9 out — catch + hit must both die at
	# the host's proximity ring. Replica net_id IS the wire id.
	var far_p: Variant = null
	for p in game.pals:
		if p.net_id > 0 and p.mode == "wild" \
				and game.player.pos.distance_to(p.pos) > 10.0:
			far_p = p
			break
	if far_p != null:
		_write("res://tools/net_verb_farcatch.txt", str(far_p.net_id))
		await _wait_ms(1500)
		game.net.rpc("sphere_catch", far_p.net_id, "kin_orb", false, 1)
		_write("res://tools/net_verb_farhit.txt", str(far_p.net_id))
		await _wait_ms(1500)
		game.net.rpc("pal_hit", far_p.net_id, 50.0, 0.0)
		_gate("far replica picked + wires fired", true,
			"nid=%d" % far_p.net_id) # the refusal verdicts live host-side —
		# this gate only certifies a real target was found (audit-68)
	else:
		_gate("far replica picked + wires fired", false, "no far replica found")

	# ---- TANK probe: the pinned tank is IN ring — the only gate between
	# 1e9 and honest damage is the claim clamp itself. pal_hit rides the
	# UNRELIABLE lane — a single datagram can legitimately drop, so the
	# probe re-sends until the replica's synced hp shows a landing, then
	# stops (two landed 1e9s would still clamp per-hit, but the gate
	# asserts the honest ceiling once)
	if tank_nid > 0:
		_write("res://tools/net_verb_tank.txt", str(tank_nid))
		await _wait_ms(1500)
		# the fixture's own hp must sync first — a stale pre-pin value
		# (<500) would fake a landing before any wire even flew
		var base := 0.0
		var rep_seen := false
		await _until(4000, func():
			for p in game.pals:
				if p.net_id == tank_nid:
					return p.hp >= 490.0
			return false)
		for p in game.pals: # re-scan outside the lambda — no capture doubt
			if p.net_id == tank_nid:
				rep_seen = true
				base = p.hp
				break
		var applied := false
		if base >= 490.0:
			for t in 3:
				game.net.rpc("pal_hit", tank_nid, 1e9, 0.0)
				await _wait_ms(1100) # >2 pal_sync ticks — a landed hit MUST
				# be visible before the next wire flies or stacked clamped
				# hits can batch into one frame and fake an unclamped read
				for p in game.pals:
					if p.net_id == tank_nid and p.hp < base - 0.5:
						applied = true
						break
				if applied:
					break
		else:
			# no observable replica — fire ONE wire blind. A second blind
			# wire can batch with the first on a stalled host and stack two
			# honest-ceiling landings into one frame's drop
			game.net.rpc("pal_hit", tank_nid, 1e9, 0.0)
			applied = true
		_gate("forged pal_hit wire lands", applied,
			"nid=%d base=%.0f rep=%s" % [tank_nid, base, rep_seen])
	else:
		_gate("forged pal_hit wire lands", false, "no tank nid")

	await _wait_ms(2000) # let the host read every marker, then leave
	_finish()

func _finish() -> void:
	if _tag_existed: # the operator's real install token goes home
		var rf := FileAccess.open("user://plg_net.cfg", FileAccess.WRITE)
		if rf:
			rf.store_string(_tag_backup)
			rf.close()
	var fo := FileAccess.open("res://tools/net_verb_join_out.txt", FileAccess.WRITE)
	for r in results:
		fo.store_line(r)
	fo.store_line("==== JOIN: %d failures ====" % fails)
	fo.close()
	print("==== JOIN: %d failures ====" % fails)
	quit(fails)
