# S110 scripted walkthrough — real input events through parse_input_event
# (the same queue hardware feeds), asserting state transitions and shooting
# evidence at every beat: title → play → move → harvest → build → aim →
# throw → pause, then pad-injected verbs. FAIL lines = real input-path bugs.
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
	img.save_png("/tmp/plg-walk-%s.png" % name)
	print("shot %s" % name)

func _tap_key(k: Key) -> void: # a real keycode — the InputMap binding is
	var ev := InputEventKey.new()    # part of what this gate proves
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
	# warp, not motion: injected motion loses to the real cursor in a live
	# window — warp moves the OS pointer, exactly what a hand would do
	root.warp_mouse(Vector2(px, py))
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

func _world_px(tp: Vector2) -> Vector2: # tile coords → viewport px via the live canvas transform
	var wp := Iso.to_screen(tp.x, tp.y, game.world.elev_at(int(tp.x), int(tp.y)))
	return root.get_canvas_transform() * wp

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 30:
		await process_frame
	_gate("boots to title", game.state == "title", "state=%s" % game.state)
	await _shot("title")

	# title → NEW GAME through a real mouse click on the menu row —
	# an existing save arms the overwrite confirm (first click arms,
	# the second commits) — click the row until play, max 3
	for i in 3:
		if game.state == "play":
			break
		var clicked := false
		for cr in hudn.click_rects:
			if cr["act"] == "new_game":
				var c: Vector2 = cr["rect"].get_center()
				await _click(c.x, c.y)
				clicked = true
				break
		if not clicked:
			_gate("new_game row exists", false, "click_rects had no new_game")
		for j in 8:
			await process_frame
	_gate("NEW GAME enters play", game.state == "play", "state=%s" % game.state)
	for i in 30:
		await process_frame
	await _shot("play")

	# movement: pick an open lane from the world, then hold that key through
	# real key events — the sim walks, not the script (spawn seed decides
	# which of WASD has room to run)
	var p0: Vector2 = game.player.pos
	var lane := KEY_D
	var best_room := -1
	for d in [[KEY_D, Vector2(1, 0)], [KEY_A, Vector2(-1, 0)],
			[KEY_S, Vector2(0, 1)], [KEY_W, Vector2(0, -1)]]:
		var room := 0
		for step in range(1, 7):
			var c: Vector2 = p0 + d[1] * step
			if game.world.blocked(int(c.x), int(c.y)) or \
					game.world.decor_at(int(c.x), int(c.y)) != World.Decor.NONE:
				break
			room += 1
		if room > best_room:
			best_room = room
			lane = d[0]
	var ev := InputEventKey.new()
	ev.keycode = lane
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 45:
		await process_frame
	var evr := InputEventKey.new()
	evr.keycode = lane
	evr.pressed = false
	Input.parse_input_event(evr)
	for i in 6:
		await process_frame
	_gate("held key walks the keeper", game.player.pos.distance_to(p0) > 0.8,
		"moved %.2f (lane %s room %d)" % [game.player.pos.distance_to(p0),
		char(lane), best_room])
	await _shot("moved")

	# harvest: a real tree, a real swing — teleport beside it, face it, LMB
	var tree := Vector2i(-1, -1)
	var stand := Vector2.ZERO
	for yy in range(4, World.WORLD_H - 4):
		for xx in range(4, World.WORLD_W - 4):
			if tree.x >= 0:
				continue
			if game.world.decor_at(xx, yy) == World.Decor.TREE_A \
					or game.world.decor_at(xx, yy) == World.Decor.TREE_B:
				var sp := Vector2i(xx, yy - 1)
				if game.world.in_bounds(sp.x, sp.y) and not game.world.blocked(sp.x, sp.y) \
						and game.world.decor_at(sp.x, sp.y) == World.Decor.NONE:
					tree = Vector2i(xx, yy)
					stand = Vector2(sp.x + 0.5, sp.y + 0.5)
	_gate("harvest fixture found", tree.x >= 0)
	var wood0: int = game.item_count("wood")
	var hp0 := 0
	var decor0 := -1
	if tree.x >= 0:
		var tidx: int = game.world.idx(tree.x, tree.y)
		decor0 = game.world.decor_at(tree.x, tree.y)
		game.world.hp[tidx] = 20 # fixture plants a near-dead tree — the gate
		# must prove click→swing→fell→pickup, not luck with refresh pacing
		hp0 = game.world.hp[tidx] # read AFTER the poke — chipping must beat 20
		game.player.pos = stand
		game.player.facing = Vector2(0, 1) # the tree is directly south
		for i in 4:
			await process_frame
		main.cam.global_position = game.player.global_position # lerp would
		# lag a teleport — snap so the click lands where the tree draws
		for i in 6:
			await process_frame
		var tp := _world_px(Vector2(tree) + Vector2(0.5, 0.5))
		for s in 6: # atk_cd is wall-clock 0.45s — idle frames pace wrong on
			await _click(tp.x, tp.y)          # high-refresh displays; timers don't
			await create_timer(0.55).timeout
			game.player.facing = Vector2(0, 1) # fixture — the swing may turn him
	var hp1: int = game.world.hp[game.world.idx(tree.x, tree.y)] if tree.x >= 0 else -1
	_gate("LMB swings chip the tree", tree.x >= 0 and hp1 < hp0,
		"hp %d→%d" % [hp0, hp1])
	_gate("tree actually fells", tree.x >= 0 and hp1 == 0
			and game.world.decor_at(tree.x, tree.y) != decor0,
		"hp=%d decor %d→%d" % [hp1, decor0,
			game.world.decor_at(tree.x, tree.y) if tree.x >= 0 else -1])
	# felled wood lands as a ground drop — step onto the tile to collect
	if tree.x >= 0 and hp1 == 0:
		game.player.pos = Vector2(tree.x + 0.5, tree.y + 0.5)
		await create_timer(0.8).timeout # pickup radius is 0.74 — a beat
		for i in 10:
			await process_frame
	_gate("felled wood reaches the pack", tree.x < 0 or game.item_count("wood") > wood0,
		"wood %d→%d" % [wood0, game.item_count("wood")])
	await _shot("harvest")

	# build panel through the real key route — a physical keycode, so a
	# deleted binding fails instead of matching an action name
	await _tap_key(KEY_B)
	for i in 8:
		await process_frame
	_gate("B opens build", game.panel == "build", "panel=%s" % game.panel)
	await _shot("build")
	await _tap_key(KEY_ESCAPE)
	for i in 6:
		await process_frame
	_gate("Esc closes the panel", game.panel == "")

	# aim + throw at a wild kin the world actually spawned
	game.items["kin_orb"] = maxi(game.items.get("kin_orb", 0), 3)
	game.spawn_wild(true)
	for i in 15:
		await process_frame
	var tgt: Kin = null
	for p in game.pals:
		if p.mode == "wild" and p.pos.distance_to(game.player.pos) < 12.0:
			tgt = p
			break
	_gate("wild kin exists to aim at", tgt != null)
	if tgt != null:
		var w0: int = game.item_count("kin_orb")
		# land the keeper on a standable cell near the target — a blind
		# offset can be water, and a swimming keeper distorts later gates
		var best_spot: Vector2 = tgt.pos + Vector2(-3.0, 0.0)
		var elev_t: int = game.world.elev_at(int(tgt.pos.x), int(tgt.pos.y))
		var spot_score := -1
		for d in [Vector2(-3, 0), Vector2(-2, -2), Vector2(-2, 2), Vector2(-3, -3),
				Vector2(-3, 3), Vector2(0, -3), Vector2(0, 3)]:
			var c: Vector2 = tgt.pos + d
			var ci := Vector2i(int(c.x), int(c.y))
			var score := 0
			if game.world.in_bounds(ci.x, ci.y) and not game.world.blocked(ci.x, ci.y):
				score += 2 # blocked covers water/decor/structure already
				if game.world.elev_at(ci.x, ci.y) == elev_t:
					score += 2 # same shelf — melee LOS and dodge stay honest
				if game.world.tile_at(ci.x, ci.y) != World.Tile.WATER:
					score += 1 # dry land preferred — a swimmer distorts gates
			if score > spot_score:
				spot_score = score
				best_spot = Vector2(ci.x + 0.5, ci.y + 0.5)
		game.player.pos = best_spot
		game.player.facing = (tgt.pos - best_spot).normalized()
		if game.player.facing.length_squared() < 0.01:
			game.player.facing = Vector2(1, 0)
		for i in 4:
			await process_frame
		main.cam.global_position = game.player.global_position
		for i in 6:
			await process_frame
		await _tap_key(KEY_Q)
		for i in 8:
			await process_frame
		_gate("Q aims", game.player.aiming, "aiming=%s" % game.player.aiming)
		await _shot("aim")
		var tp2 := _world_px(tgt.pos)
		await _click(tp2.x, tp2.y)
		for i in 20:
			await process_frame
		_gate("LMB throws the orb", game.item_count("kin_orb") < w0
				or game.spheres_flying.size() > 0,
			"orbs=%d flying=%d" % [game.item_count("kin_orb"), game.spheres_flying.size()])

	# pause shell through Esc — the whole game's stop button
	await _tap_key(KEY_ESCAPE)
	for i in 8:
		await process_frame
	_gate("Esc pauses", game.state == "paused", "state=%s panel=%s" % [game.state, game.panel])
	await _shot("pause")
	await _tap_key(KEY_ESCAPE)
	for i in 8:
		await process_frame
	_gate("Esc resumes", game.state == "play", "state=%s" % game.state)

	# pad class: injected joy events must drive the same verbs hardware would
	game.player.stamina = 100.0 # a tired keeper legitimately can't roll
	var st0: float = game.player.stamina
	var jp := InputEventJoypadButton.new()
	jp.button_index = JOY_BUTTON_B # dodge — a real pad event, not a flag poke
	jp.pressed = true
	Input.parse_input_event(jp)
	for i in 8:
		await process_frame
	_gate("pad B dodges", game.player.dodge_t > 0,
		"dodge_t=%.2f stamina %.0f→%.0f" % [game.player.dodge_t, st0, game.player.stamina])
	_gate("pad sighted", game.using_pad, "using_pad=%s" % game.using_pad)

	# touch class: real ScreenTouch events on the virtual controls — a slab
	# has no keys, so every verb must ride a finger press
	game.touch_ui = true
	await process_frame # one frame — draw_touch lays the buttons out
	var lay: Dictionary = hudn.touch_layout(Vector2(root.size))
	# ATK must do a verb's work: land a real hit on a real wild kin —
	# atk_cd is eaten by free-running physics before we can read it
	var mark: Kin = null
	for p in game.pals: # reuse a wild that exists; spawn only if the field is bare
		if p.mode == "wild" and p.hp > 0:
			mark = p
			break
	if mark == null:
		game.spawn_wild(true)
		for i in 10:
			await process_frame
		for p in game.pals:
			if p.mode == "wild" and p.hp > 0:
				mark = p
				break
	var hp_mark := -1.0
	if mark != null:
		# adjacent cell on the player's own shelf — an elevation step
		# between them blocks melee LOS and fails the gate for nothing
		var pe: int = game.world.elev_at(int(game.player.pos.x), int(game.player.pos.y))
		var adj: Vector2 = game.player.pos + Vector2(1.0, 0.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var c: Vector2 = game.player.pos + d
			var ci := Vector2i(int(c.x), int(c.y))
			if game.world.in_bounds(ci.x, ci.y) and not game.world.blocked(ci.x, ci.y) \
					and game.world.elev_at(ci.x, ci.y) == pe:
				adj = Vector2(ci.x + 0.5, ci.y + 0.5)
				break
		mark.pos = adj
		game.player.facing = (adj - game.player.pos).normalized()
		if game.player.facing.length_squared() < 0.01:
			game.player.facing = Vector2(1, 0)
		hp_mark = mark.hp
		game.player.aiming = false # ATK while aiming throws — melee needs it off
		game.player.atk_cd = 0.0
		var atk_p: Vector2 = lay["btns"]["atk"]
		var tc := InputEventScreenTouch.new()
		tc.index = 0
		tc.pressed = true
		tc.position = atk_p
		Input.parse_input_event(tc)
		await process_frame
		var tc2 := InputEventScreenTouch.new()
		tc2.index = 0
		tc2.pressed = false
		tc2.position = atk_p
		Input.parse_input_event(tc2)
		for i in 6:
			await process_frame
	_gate("ATK button lands a hit", mark != null and is_instance_valid(mark)
			and mark.hp < hp_mark,
		"hp %.0f→%.0f" % [hp_mark,
			mark.hp if (mark != null and is_instance_valid(mark)) else -1.0])

	# joystick drag: finger down on the stick, drag toward an OPEN rim
	# direction — physics runs free here, so read the stick live, not after
	# touch_up wipes it
	var drag_dir := Vector2(40, 0)
	var drag_room := -1
	for d in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
		var room := 0
		var sgn: Vector2 = d.sign()
		for step in range(1, 6):
			var c: Vector2 = game.player.pos + sgn * step
			if game.world.blocked(int(c.x), int(c.y)) or \
					game.world.decor_at(int(c.x), int(c.y)) != World.Decor.NONE:
				break
			room += 1
		if room > drag_room:
			drag_room = room
			drag_dir = d
	var tj := InputEventScreenTouch.new()
	tj.index = 1
	tj.pressed = true
	tj.position = lay["joy"]
	Input.parse_input_event(tj)
	await process_frame
	var td := InputEventScreenDrag.new()
	td.index = 1
	td.position = lay["joy"] + drag_dir
	Input.parse_input_event(td)
	await process_frame
	var vec_live: Vector2 = game.player.touch_vec
	var tp0: Vector2 = game.player.pos
	for i in 40:
		await process_frame
	var moved: float = game.player.pos.distance_to(tp0)
	var tjr := InputEventScreenTouch.new()
	tjr.index = 1
	tjr.pressed = false
	tjr.position = td.position
	Input.parse_input_event(tjr)
	for i in 4:
		await process_frame
	_gate("stick drag steers", vec_live.length() > 0.3,
		"live vec=%s" % vec_live)
	_gate("stick drag walks", moved > 0.5,
		"moved %.2f (dir %s room %d)" % [moved, drag_dir.sign(), drag_room])
	await _shot("touch")

	print("==== WALK: %d failures ====" % fails)
	quit()

func _process(_dt: float) -> bool:
	return false
