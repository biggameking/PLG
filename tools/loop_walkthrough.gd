# S112 first-day loop walkthrough — the core product claim driven by real
# input events end-to-end: weaken a wild kin → aim+throw orb → CATCH →
# open build bar → place kinbox → E opens the box → deploy the catch to
# base → night → E on the straw bed → day advances.
# Fixture-planted state (materials, tod, spawn) is NOT the path under
# test — every gate asserts on what a real click/key must accomplish.
extends SceneTree

var main
var game
var hudn
var fails := 0

func _initialize() -> void:
	call_deferred("_boot")

func _gate(name: String, cond: bool, info := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not cond:
		fails += 1

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-loop-%s.png" % name)
	print("shot %s" % name)

func _stamp() -> void: # run manifest — proves which tree produced the shots
	var out: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], out, true)
	print("LOOP run %s sha=%s" % [Time.get_datetime_string_from_system(),
		str(out[0]).strip_edges() if out.size() > 0 else "?"])

func _tap_key(k: Key) -> void: # real keycode — a dead binding must fail
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventKey.new()
	ev2.keycode = k
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame

func _click(px: float, py: float, btn := MOUSE_BUTTON_LEFT) -> void:
	root.warp_mouse(Vector2(px, py)) # the OS pointer is the hand
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	ev.position = Vector2(px, py)
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = btn
	ev2.pressed = false
	ev2.position = Vector2(px, py)
	Input.parse_input_event(ev2)
	await process_frame

func _world_px(tp: Vector2) -> Vector2:
	var wp := Iso.to_screen(tp.x, tp.y, game.world.elev_at(int(tp.x), int(tp.y)))
	return root.get_canvas_transform() * wp

func _stand_spot(center: Vector2, min_d := 1.6, max_d := 4.0) -> Vector2:
	# a real standable cell within reach of `center` on its own shelf —
	# teleports must land where a keeper could actually stand
	var e0: int = game.world.elev_at(int(center.x), int(center.y))
	for r in range(int(minf(min_d, 1.0)), int(max_d) + 1):
		for a in range(0, 360, 30):
			var c: Vector2 = center + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
			var ci := Vector2i(int(c.x), int(c.y))
			if game.world.in_bounds(ci.x, ci.y) and not game.world.blocked(ci.x, ci.y) \
					and game.world.elev_at(ci.x, ci.y) == e0:
				return Vector2(ci.x + 0.5, ci.y + 0.5)
	return center

func _pick_row(sid: String, max_pages := 4) -> bool:
	# real row clicks only — page through the bar if the row isn't visible
	for page in max_pages:
		var bll: Array = game.buildable_list()
		for cr in hudn.click_rects:
			if cr["act"] == "build_pick" and cr["arg"] is int \
					and int(cr["arg"]) < bll.size() and bll[int(cr["arg"])] == sid:
				var c: Vector2 = cr["rect"].get_center()
				await _click(c.x, c.y)
				return hudn.build_sel_sid == sid
		var paged := false
		for cr in hudn.click_rects:
			if cr["act"] == "build_pg" and int(cr["arg"]) > 0:
				var c2: Vector2 = cr["rect"].get_center()
				await _click(c2.x, c2.y)
				for j in 4:
					await process_frame
				paged = true
				break
		if not paged:
			return false
	return false

func _rect_free(px: float, py: float) -> bool:
	# a ghost click that lands inside ANY panel rect is eaten by run_click
	# before it reaches place_ghost — the cell must clear the whole sheet
	for cr in hudn.click_rects:
		if cr["rect"].has_point(Vector2(px, py)):
			return false
	return true

func _open_cell(near: Vector2, w: int, h: int, max_r := 10) -> Vector2i:
	# a w×h footprint that place_structure would accept — flat, on the
	# keeper's own shelf (mouse_tile back-projects through player.elev(),
	# so a ledge cell clicks onto the wrong tile entirely)
	var pe: int = game.world.elev_at(int(game.player.pos.x), int(game.player.pos.y))
	for r in range(1, max_r):
		for a in range(0, 360, 20):
			var ci := Vector2i(int(near.x + cos(deg_to_rad(a)) * r),
				int(near.y + sin(deg_to_rad(a)) * r))
			var ok := true
			for dy in range(h):
				for dx in range(w):
					var c := ci + Vector2i(dx, dy)
					if not game.world.in_bounds(c.x, c.y) or game.world.blocked(c.x, c.y) \
							or game.structures.has(c) \
							or game.world.elev_at(c.x, c.y) != pe:
						ok = false
			if ok:
				var cp := _world_px(Vector2(ci.x + 0.5, ci.y + 0.5))
				if _rect_free(cp.x, cp.y):
					return ci
	return Vector2i(-1, -1)

func _face_at(from: Vector2, to: Vector2) -> Vector2:
	var f: Vector2 = (to - from).normalized()
	return f if f.length_squared() > 0.01 else Vector2(1, 0)

func _boot() -> void:
	_stamp()
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 30:
		await process_frame
	_gate("boots to title", game.state == "title")

	# real click on NEW GAME (armed-confirm handled by re-clicking the row)
	for i in 3:
		if game.state == "play":
			break
		for cr in hudn.click_rects:
			if cr["act"] == "new_game":
				var c: Vector2 = cr["rect"].get_center()
				await _click(c.x, c.y)
				break
		for j in 8:
			await process_frame
	_gate("NEW GAME enters play", game.state == "play")
	for i in 20:
		await process_frame

	# ---- CATCH: weaken → aim → throw, real events every beat ----
	game.spawn_wild(true)
	for i in 10:
		await process_frame
	var prey: Kin = null
	for p in game.pals:
		if p.mode == "wild" and p.hp > 0 and p.pos.distance_to(game.player.pos) < 14.0 \
				and not p.boss:
			prey = p
			break
	_gate("wild kin to hunt", prey != null)
	var captured := false
	if prey != null:
		game.items["kin_orb"] = maxi(game.items.get("kin_orb", 0), 15)
		game.player.hp = game.player.max_hp
		var hp0: float = prey.hp
		# weaken with real melee taps — CHASE by teleport: a fleeing kin
		# outruns reach, so re-stand next to it before every click
		for s in 10:
			if not is_instance_valid(prey) or prey.hp < prey.max_hp * 0.30:
				break # a swing can kill — stop before freed-ref access
			game.player.pos = _stand_spot(prey.pos)
			game.player.facing = _face_at(game.player.pos, prey.pos)
			game.player.atk_cd = 0.0
			for i in 3:
				await process_frame
			main.cam.global_position = game.player.global_position
			var mp := _world_px(prey.pos)
			await _click(mp.x, mp.y)
			await create_timer(0.5).timeout
		_gate("melee weakens the prey", is_instance_valid(prey) and prey.hp < hp0,
			"hp %.0f→%s" % [hp0, "%.0f" % prey.hp if is_instance_valid(prey) else "gone"])
		# aim + throw until the ball holds — capture is a chance, the
		# keeper retries like a player would
		for attempt in 8:
			if captured or not is_instance_valid(prey):
				break
			if not (prey.mode == "wild" and prey.hp > 0):
				break
			game.player.aiming = false
			await _tap_key(KEY_Q)
			for j in 4:
				await process_frame
			var orbs0: int = game.item_count("kin_orb")
			var tp2 := _world_px(prey.pos)
			await _click(tp2.x, tp2.y)
			for j in 12:
				await process_frame
			print("  throw %d: orbs %d→%d flying=%d prey_hp=%.0f dist=%.1f" % [
				attempt, orbs0, game.item_count("kin_orb"), game.spheres_flying.size(),
				prey.hp, game.player.pos.distance_to(prey.pos)])
			await create_timer(3.2).timeout # the ball rocks its beat
			for j in 10:
				await process_frame
			captured = is_instance_valid(prey) and prey.mode != "wild"
	_gate("orb captures the prey", captured,
		"mode=%s" % (prey.mode if prey != null and is_instance_valid(prey) else "gone"))
	await _shot("catch")

	# ---- BUILD: B opens the bar, real row click picks kinbox, LMB plants it ----
	for c in StructureData.STRUCTURES["kinbox"].get("cost", []):
		game.items[str(c[0])] = int(c[1]) + 2 # cost from data, not memory
	for c in StructureData.STRUCTURES["straw_bed"].get("cost", []):
		game.items[str(c[0])] = maxi(game.items.get(str(c[0]), 0), int(c[1]) + 2)
	await _tap_key(KEY_B)
	for i in 8:
		await process_frame
	_gate("B opens build", game.panel == "build")
	for i in 6:
		await process_frame # click_rects need a draw after the panel opens
	_gate("kinbox row picked", await _pick_row("kinbox"),
		"sel=%s" % hudn.build_sel_sid)
	var cell: Vector2i = _open_cell(game.player.pos, 2, 2)
	_gate("open 2x2 found", cell.x >= 0)
	if cell.x >= 0:
		var gp := _world_px(Vector2(cell) + Vector2(0.5, 0.5))
		await _click(gp.x, gp.y)
		for i in 8:
			await process_frame
	_gate("ghost plants the kinbox", game.structures.get(cell, {}).get("id") == "kinbox",
		"at cell %s" % str(game.structures.get(cell, {}).get("id")))
	await _tap_key(KEY_ESCAPE)
	for i in 4:
		await process_frame
	await _shot("kinbox")

	# ---- DEPLOY: E on the box, click the deploy row, the catch crews in ----
	var kb: Vector2i = game.kinbox_pos
	if kb.x >= 0:
		var spot2: Vector2 = _stand_spot(Vector2(kb.x + 1.0, kb.y + 1.0))
		game.player.pos = spot2
		game.player.facing = _face_at(spot2, Vector2(kb.x + 1.0, kb.y + 1.0))
		for i in 4:
			await process_frame
		await _tap_key(KEY_E)
		for i in 8:
			await process_frame
	_gate("E opens the kinbox", game.panel == "kinbox", "panel=%s" % game.panel)
	var deployed := false
	for cr in hudn.click_rects:
		if cr["act"] == "deploy":
			var c: Vector2 = cr["rect"].get_center()
			await _click(c.x, c.y)
			deployed = true
			break
	for i in 8:
		await process_frame
	_gate("deploy row crews the kin", deployed and game.base_pals().size() >= 1,
		"base=%d clicked=%s" % [game.base_pals().size(), deployed])
	await _shot("deploy")
	await _tap_key(KEY_ESCAPE)
	for i in 4:
		await process_frame

	# ---- SLEEP: straw bed + E at night rolls the day ----
	for c in StructureData.STRUCTURES["straw_bed"].get("cost", []):
		game.items[str(c[0])] = int(c[1]) + 2
	await _tap_key(KEY_B)
	for i in 8:
		await process_frame
	_gate("straw bed row picked", await _pick_row("straw_bed"),
		"sel=%s" % hudn.build_sel_sid)
	var bed: Vector2i = _open_cell(game.player.pos, 2, 1)
	_gate("open 2x1 found", bed.x >= 0)
	if bed.x >= 0:
		var gp2 := _world_px(Vector2(bed.x + 1.0, bed.y + 0.5))
		await _click(gp2.x, gp2.y)
		for i in 8:
			await process_frame
	var bed_ok: bool = game.structures.has(bed) and game.structures[bed]["id"] == "straw_bed"
	_gate("ghost plants the straw bed", bed_ok,
		"cell=%s" % str(game.structures.get(bed, {})))
	await _tap_key(KEY_ESCAPE)
	for i in 4:
		await process_frame
	var day0: int = game.day
	# nightfall is the clock's, not the input's — plant dusk, keep the E real
	game.tod = 22.5
	for p in game.pals: # a prowling kin vetoes sleep — clear the field like dusk patrol would
		if p.mode == "wild":
			p.aggro = -1
	if bed.x >= 0:
		var spot3: Vector2 = _stand_spot(Vector2(bed.x + 1.0, bed.y + 0.5))
		game.player.pos = spot3
		game.player.facing = _face_at(spot3, Vector2(bed.x + 1.0, bed.y + 0.5))
		for i in 4:
			await process_frame
		await _tap_key(KEY_E)
		for i in 12:
			await process_frame
	_gate("E on the bed rolls dawn", game.day > day0 or (not game.is_night() and game.tod < 12.0),
		"day %d→%d tod=%.1f" % [day0, game.day, game.tod])
	await _shot("sleep")

	print("==== LOOP: %d failures ====" % fails)
	quit()

func _process(_dt: float) -> bool:
	return false
