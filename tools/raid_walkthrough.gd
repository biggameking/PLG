# S114 raid + boss combat walkthrough — real input end to end:
# kinbox -> raid_t horn -> wave lands -> real melee kills a raider ->
# den warden melee fight -> kill + drops.
# The verbs under test are the combat/input path; raid_t, kinbox and
# boss-hp are fixtures (not under test), placed via production helpers.
extends SceneTree

var fails := 0
var game: Node
var hudn: Node
var main: Node

func _initialize() -> void:
	call_deferred("_boot")

func _gate(name: String, cond: bool, info := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not cond:
		fails += 1

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-raid-%s.png" % name)
	print("shot %s" % name)

func _stamp() -> void:
	var out: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], out, true)
	print("RAID run %s sha=%s" % [Time.get_datetime_string_from_system(),
		str(out[0]).strip_edges() if out.size() > 0 else "?"])

func _tap_key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k; ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventKey.new()
	ev2.keycode = k; ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame

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

func _click_row(act_name: String) -> bool:
	for cr in hudn.click_rects:
		if cr["act"] == act_name:
			var c: Vector2 = cr["rect"].get_center()
			await _click(c.x, c.y)
			return true
	return false

func _world_px(w: Vector2) -> Vector2:
	var px: Vector2 = Iso.to_screen(w.x, w.y,
		game.world.elev_at(int(w.x), int(w.y))) # audit-66: dropping
	return root.get_canvas_transform() * px   # elevation clicks the wrong px

func _stand_spot(near: Vector2) -> Vector2:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2(int(near.x) + dx + 0.5, int(near.y) + dy + 0.5)
				if not game.world.blocked(int(c.x), int(c.y)):
					return c
	return near + Vector2(1.5, 0)

func _fight_spot(kin: Kin) -> Vector2: # melee needs reach AND sight —
	for r in range(1, 8):            # los_clear fails across decor and
		for dy in range(-r, r + 1):    # SHEER ELEVATION, not just blocked cells
			for dx in range(-r, r + 1):
				var c := Vector2(int(kin.pos.x) + dx + 0.5, int(kin.pos.y) + dy + 0.5)
				if game.world.blocked(int(c.x), int(c.y)):
					continue
				if game.world.los_clear(c, kin.pos):
					var d: Vector2 = (c - kin.pos).normalized()
					var spot := kin.pos + d * minf(1.25, c.distance_to(kin.pos))
					if not game.world.blocked(int(spot.x), int(spot.y)):
						return spot # the melee point must itself be standable
	return _stand_spot(kin.pos)

func _face_at(from: Vector2, to: Vector2) -> Vector2:
	var f: Vector2 = (to - from).normalized()
	return f if f.length_squared() > 0.01 else Vector2(1, 0)

func _boot() -> void:
	root.size = Vector2i(1280, 720) # headless boots a 64x64 window —
	# piped mouse events outside it never reach _unhandled_input
	_stamp()
	change_scene_to_file("res://scenes/main.tscn")
	for i in 12:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 30:
		await process_frame
	_gate("boots to title", game.state == "title")
	for i in 3:
		if game.state == "play":
			break
		await _click_row("new_game")
	for i in 10:
		await process_frame
	_gate("NEW GAME enters play", game.state == "play")
	game.player.hp = game.player.max_hp # raiders hit back — fixture HP

	# ---- BASE: a kinbox arms the raid clock (real raids need a base)
	var kb_ok := false
	for r in range(2, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if kb_ok:
					break
				var cx: int = int(game.player.pos.x) + dx
				var cy: int = int(game.player.pos.y) + dy
				if game.place_free("kinbox", cx, cy):
					kb_ok = true
	_gate("kinbox stands", game.kinbox_pos.x >= 0,
		"pos=%s" % str(game.kinbox_pos))

	# ---- HORN: raid_t just above the warn line ticks into the call
	game.raid_t = 30.8
	await create_timer(1.2).timeout # wall-clock — this window runs ~160fps,
	for i in 6:                          # frame counts under-count real seconds
		await process_frame
	var horn_msg := false
	for m in game.messages:
		if "Raid party spotted" in str(m):
			horn_msg = true
	_gate("raid horn sounds", game.raid_warned and horn_msg,
		"warned=%s theme=%s" % [game.raid_warned, game.raid_theme])
	await _shot("horn")

	# ---- WAVE: raid_t hits zero, hostiles land on the field
	game.player.pos = Vector2(game.kinbox_pos.x + 2.5, game.kinbox_pos.y + 2.5)
	for i in 3: # raiders spawn aggro'd — but tdist>14 decays to -1 fast;
		await process_frame  # stand in their arena so the gate reads the intent
	var raiders: Array = []
	for wave_try in 5: # waves can legitimately fizzle on a water-ringed
		if raiders.size() > 0:     # box — a keeper would just take the next horn
			break
		game.raid_t = 0.05
		for i in 15:
			await process_frame
		for q in game.pals:
			if q.raid and is_instance_valid(q) and not raiders.has(q):
				raiders.append(q)
	var raid_msg := false
	for m in game.messages:
		if "!! RAID:" in str(m):
			raid_msg = true
	_gate("raid wave lands", raiders.size() >= 2 and raid_msg,
		"raiders=%d" % raiders.size()) # aggro decays by design at range —
		# the fielded wave + its own declaration is the honest gate
	await _shot("wave")

	# ---- FIGHT: real melee drops a raider — chase-teleport, real clicks
	var mark: Kin = null # pick the raider with a free cell in reach —
	for q in raiders:          # a single dry cell in a lake can't be fought
		var reachable := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not game.world.blocked(int(q.pos.x) + dx, int(q.pos.y) + dy):
					reachable = true
		if reachable:
			mark = q
			break
	if mark != null:
		mark.process_mode = Node.PROCESS_MODE_DISABLED # freeze BOTH loops —
		game.player.hp = game.player.max_hp # physics still walked it away
		var mhp0: float = mark.hp
		for s in 4: # real swings prove the verb — then the near-dead
			if not is_instance_valid(mark) or mark.hp <= 0: # fixture asks
				break                                       # only for the kill
			game.player.pos = _fight_spot(mark)
			game.player.facing = _face_at(game.player.pos, mark.pos)
			game.player.atk_cd = 0.0
			for i in 3:
				await process_frame
			main.cam.global_position = game.player.global_position
			var mp := _world_px(mark.pos)
			await _click(mp.x, mp.y)
			await create_timer(0.55).timeout
			game.player.hp = game.player.max_hp
		_gate("melee bleeds the raider", not is_instance_valid(mark) or mark.hp < mhp0,
			"hp %.0f→%s" % [mhp0, "%.0f" % mark.hp if is_instance_valid(mark) else "dead"])
		if is_instance_valid(mark) and mark.hp > 0:
			mark.hp = minf(mark.hp, 12.0) # level-scaled hp outlasts 14 swings
		for s in 16:                                   # — the kill asks less
			if not is_instance_valid(mark) or mark.hp <= 0:
				break
			game.player.pos = _fight_spot(mark)
			game.player.facing = _face_at(game.player.pos, mark.pos)
			game.player.atk_cd = 0.0
			for i in 3:
				await process_frame
			main.cam.global_position = game.player.global_position
			var mp := _world_px(mark.pos)
			await _click(mp.x, mp.y)
			await create_timer(0.55).timeout
			game.player.hp = game.player.max_hp # the fight must not kill the
		_gate("melee kills a raider",                        # harness mid-gate
			not is_instance_valid(mark) or mark.hp <= 0,
			"hp %.0f→%s" % [mhp0, "%.0f" % mark.hp if is_instance_valid(mark) else "dead"])
	else:
		_gate("melee kills a raider", false, "no raider")
	await _shot("fight")

	# ---- BOSS: den warden — real swings hurt it, low-hp fixture lets the
	# kill land inside the run; drops prove the fight paid out
	var warden: Kin = null # audit-66: the first q.boss may be a grotto
	for q in game.pals:    # warden sealed inside a rock ring — unreachable
		if q.boss and is_instance_valid(q):
			var spot := _fight_spot(q) # pick the first boss a fighter can
			if not game.world.blocked(int(spot.x), int(spot.y)) \
					and game.world.los_clear(spot, q.pos):
				warden = q # actually reach — the fallback order isn't a promise
				break
	if warden == null: # none reachable — take the first boss and fail loudly
		for q in game.pals:
			if q.boss and is_instance_valid(q):
				warden = q
				break
	_gate("den warden found", warden != null,
		"%s" % (warden.species_id if warden else "none"))
	if warden != null:
		warden.process_mode = Node.PROCESS_MODE_DISABLED # leash drift is not
		game.player.hp = game.player.max_hp # the verb under test either
		var bhp0: float = warden.hp
		for s in 8: # the torch ring blocks LOS — retry spots until a swing
			if warden.hp < bhp0:                 # lands inside the arena
				break
			var spot := _fight_spot(warden)
			game.player.pos = spot
			game.player.facing = _face_at(game.player.pos, warden.pos)
			game.player.atk_cd = 0.0
			for i in 3:
				await process_frame
			main.cam.global_position = game.player.global_position
			var wp := _world_px(warden.pos)
			await _click(wp.x, wp.y)
			await create_timer(0.55).timeout
			game.player.hp = game.player.max_hp
		_gate("melee wounds the warden", warden.hp < bhp0,
			"hp %.0f→%.0f" % [bhp0, warden.hp])
		var drops0: int = game.drops.size()
		warden.hp = 8.0 # near-dead fixture — the kill must still be earned
		for s in 12:
			if not is_instance_valid(warden) or warden.hp <= 0:
				break
			game.player.pos = _fight_spot(warden)
			game.player.facing = _face_at(game.player.pos, warden.pos)
			game.player.atk_cd = 0.0
			main.cam.global_position = game.player.global_position
			var wp2 := _world_px(warden.pos)
			await _click(wp2.x, wp2.y)
			await create_timer(0.55).timeout
			game.player.hp = game.player.max_hp
		_gate("warden falls", not is_instance_valid(warden) or warden.hp <= 0)
		for i in 10:
			await process_frame
		_gate("the fight pays out", game.drops.size() > drops0
			or game.item_count("ancient_part") > 0, # audit-66: "ancient_relic"
			"drops %d→%d part=%d" % [drops0, game.drops.size(), # never existed —
				game.item_count("ancient_part")]) # a permanently dead disjunct
	await _shot("boss")

	print("==== RAID-LOOP: %d failures ====" % fails)
	quit(fails)
