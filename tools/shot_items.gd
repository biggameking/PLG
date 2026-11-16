# S107 item-icon evidence — stocks a deterministic bag + merchant, then
# screenshots the three item-facing panels through the real draw path.
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-shot-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	for i in 30:
		await process_frame
	# deterministic bag: one of every kind + specials riding the relic icon
	var bag := ["kin_egg", "boss_sigil", "ancient_part", "gauntlet_sigil"]
	for iid in ItemData.ITEMS:
		var k: String = ItemData.ITEMS[iid].get("kind", "")
		if k != "" and not bag.any(func(b): return ItemData.ITEMS.get(b, {}).get("kind", "") == k):
			bag.append(iid)
	game.items.clear()
	for iid in bag:
		game.items[iid] = 3
	game.items["gold_coin"] = 999
	var hudn: Node = main.get_node("UILayer/HUD")
	hudn.inv_scroll = 0
	game.panel = "inv"
	for i in 10:
		await process_frame
	await _shot("items-inv")
	game.craft_station = "workbench" # 46 workbench rows outnumber the lone hand recipe
	game.panel = "craft"
	for i in 10:
		await process_frame
	await _shot("items-craft")
	# merchant + stock through the real spawner, then open the shop
	game.spawn_merchant()
	game.gen_merchant_stock()
	if game.merchant != null:
		game.merchant.pos = game.player.pos + Vector2(0.5, 0.5)
	game.panel = "shop"
	for i in 12:
		await process_frame
	await _shot("items-shop")
	quit()

func _process(_dt: float) -> bool:
	return false
