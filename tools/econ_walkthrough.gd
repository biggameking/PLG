# S115 economy loop walkthrough — real input end to end:
# workbench+E -> craft panel row click -> crafted item ->
# merchant+E -> buy row (gold debited) + sell row (gold credited) ->
# tech key -> node row click -> unlock.
# Materials/levels/gold are fixtures; the verbs under test are the
# interact + panel-row input paths.
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
	img.save_png("/tmp/plg-econ-%s.png" % name)
	print("shot %s" % name)

func _stamp() -> void:
	var out: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], out, true)
	print("ECON run %s sha=%s" % [Time.get_datetime_string_from_system(),
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

func _tap_action(act: String) -> void:
	for ev in InputMap.action_get_events(act):
		if ev is InputEventKey:
			await _tap_key(ev.keycode)
			return
	_gate("action %s has a key" % act, false)

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

func _find_row(act_name: String, arg = null) -> Dictionary:
	for cr in hudn.click_rects:
		if cr["act"] == act_name and (arg == null or cr.get("arg") == arg):
			return cr
	return {}

func _click_row(act_name: String, arg = null) -> bool:
	var cr := _find_row(act_name, arg)
	if cr.is_empty():
		return false
	var c: Vector2 = cr["rect"].get_center()
	await _click(c.x, c.y)
	return true

func _stand_spot(near: Vector2) -> Vector2:
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2(int(near.x) + dx + 0.5, int(near.y) + dy + 0.5)
				if c.distance_to(near) > 2.0: # past the interact probes'
					continue              # reach (2.2 struct / 2.4 merchant)
				if not game.world.blocked(int(c.x), int(c.y)):
					return c
	return near # a blocked fallback would plant the player inside terrain —
	# fail the downstream gate loudly instead

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

	# ---- CRAFT: workbench fixture + E + row click makes a club
	var wb_ok := false
	for r in range(2, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not wb_ok and game.place_free("workbench",
						int(game.player.pos.x) + dx, int(game.player.pos.y) + dy):
					wb_ok = true
	_gate("workbench stands", wb_ok)
	game.add_item("wood", 12)
	var club0: int = game.item_count("wooden_club")
	var wood0: int = game.item_count("wood")
	# stand next to the bench, facing it, real E
	var wb_cell := Vector2i(-1, -1)
	for k in game.structures:
		if game.structures[k]["id"] == "workbench":
			wb_cell = k
			break
	if wb_cell.x >= 0:
		var wc := Vector2(wb_cell.x + 0.5, wb_cell.y + 0.5)
		game.player.pos = _stand_spot(wc)
		game.player.facing = (wc - game.player.pos).normalized()
		for i in 3:
			await process_frame
		await _tap_action("interact")
		for i in 8:
			await process_frame
	_gate("E opens craft", game.panel == "craft",
		"panel=%s st=%s" % [game.panel, game.craft_station])
	await _shot("craft")
	_gate("club row clicked", await _click_row("craft", "club")) # recipe id,
		# not its output item id — the row arg is rec["id"]
	for i in 10:
		await process_frame
	_gate("club crafted", game.item_count("wooden_club") == club0 + 1
		and game.item_count("wood") == wood0 - 5,
		"club=%d wood=%d" % [game.item_count("wooden_club"), game.item_count("wood")])
	# station path: "club" is a hand recipe — it exercises none of the bench
	# gate, the craft_queue or the helper-hurried drain. "flour" is the
	# cheapest tech-free workbench recipe (wheat 3 -> 1; "arrow" looked free
	# too but its *output item* carries tech gating — recipe_tech checks both)
	game.add_item("wheat", 3)
	var fl0: int = game.item_count("flour")
	var wh0: int = game.item_count("wheat")
	var q0: int = game.craft_queue.size()
	_gate("flour row clicked", await _click_row("craft", "flour"))
	for i in 3:
		await process_frame
	_gate("bench craft queues", game.craft_queue.size() == q0 + 1,
		"queue=%d" % game.craft_queue.size())
	for cq in game.craft_queue: # the bench path already ran — hurry the timer
		cq["left"] = 0.02      # so the drain (the verb under test) can be seen
	for i in 12:
		await process_frame
	_gate("flour crafted at bench", game.item_count("flour") == fl0 + 1
		and game.item_count("wheat") == wh0 - 3,
		"flour=%d wheat=%d" % [game.item_count("flour"), game.item_count("wheat")])
	await _tap_key(KEY_ESCAPE)
	for i in 4:
		await process_frame

	# ---- SHOP: merchant fixture + E + buy/sell rows move real gold
	game.tod = 10.0 # pin daylight — a dusk roll could despawn the merchant
	if game.merchant == null:   # mid-leg and fail on a schedule, not a bug
		game.spawn_merchant()
	for i in 4:
		await process_frame
	_gate("merchant arrived", game.merchant != null)
	if game.merchant != null:
		game.player.pos = _stand_spot(game.merchant.pos)
		for i in 3:
			await process_frame
		await _tap_action("interact")
		for i in 8:
			await process_frame
	_gate("E opens shop", game.panel == "shop", "panel=%s" % game.panel)
	game.add_item("gold_coin", 60)
	game.add_item("fertilizer", 6) # sell fodder — wood/jam carry no price
	# cheapest priced row regardless of cost — a ≤40 ceiling would make this
	# pick a stock-roll lottery (audit-65): fund the purse, then assert the
	# exact debit rather than a direction
	var stock_i := -1
	var want := ""
	var price := 0
	for si in game.merchant_stock.size():
		var it: Dictionary = game.merchant_stock[si]
		if str(it.get("id", "")) != "" and int(it.get("n", 0)) > 0:
			var p2: int = int(it.get("price", 999))
			if stock_i < 0 or p2 < price:
				stock_i = si
				want = str(it["id"])
				price = p2
	if stock_i >= 0:
		game.add_item("gold_coin", price)
	var gold0: int = game.item_count("gold_coin")
	await _shot("shop")
	var got0: int = game.item_count(want) if want != "" else 0
	_gate("buy row clicked", stock_i >= 0 and await _click_row("buy", stock_i),
		"stock_i=%d want=%s" % [stock_i, want])
	for i in 8:
		await process_frame
	_gate("buy debits exact price, goods arrive", want != ""
		and game.item_count(want) == got0 + 1
		and game.item_count("gold_coin") == gold0 - price,
		"%s=%d gold %d→%d price=%d" % [want,
			game.item_count(want) if want != "" else -1,
			gold0, game.item_count("gold_coin"), price])
	var gold1: int = game.item_count("gold_coin")
	var fod1: int = game.item_count("fertilizer")
	_gate("sell row clicked", await _click_row("sell", "fertilizer"))
	for i in 8:
		await process_frame
	_gate("sell credits exact half price", game.item_count("gold_coin") ==
		gold1 + Game.sell_value("fertilizer")
		and game.item_count("fertilizer") == fod1 - 1,
		"gold %d→%d (+%d) fert %d→%d" % [gold1, game.item_count("gold_coin"),
			Game.sell_value("fertilizer"),
			fod1, game.item_count("fertilizer")])
	await _tap_key(KEY_ESCAPE)
	for i in 4:
		await process_frame

	# ---- TECH: real key opens the tree, row click spends real points
	game.player.level = 5
	game.tech_points = 15
	game.add_item("ancient_part", 2)
	var pick := ""
	var cost := 0
	for t in StructureData.TECH:
		if int(t.get("tier", 9)) <= 4 and int(t.get("cost", 99)) <= 12 \
				and int(t.get("parts", 0)) <= 1 and str(t["id"]) not in game.unlocked:
			pick = str(t["id"])
			cost = int(t["cost"])
			break
	_gate("affordable tech exists", pick != "", pick)
	await _tap_action("tech")
	for i in 10:
		await process_frame
	_gate("T opens tech", game.panel == "tech", "panel=%s" % game.panel)
	await _shot("tech")
	var pts0: int = game.tech_points
	_gate("tech row clicked", pick != "" and await _click_row("tech", pick),
		"pick=%s" % pick)
	for i in 8:
		await process_frame
	_gate("unlock lands at exact cost", pick in game.unlocked
		and game.tech_points == pts0 - cost,
		"unlocked=%s pts %d→%d cost=%d" % [str(pick in game.unlocked),
			pts0, game.tech_points, cost])

	print("==== ECON-LOOP: %d failures ====" % fails)
	quit(fails)
