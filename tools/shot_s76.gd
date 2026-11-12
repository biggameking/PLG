# S76 mid-game evidence — pact spire pings on the minimap: violet squares on
# charted ground (broken ruins draw hollow). Windowed run; /tmp/plg-s76-*.png.
extends SceneTree

var main
var game
var hud

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-s76-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	hud = main.get_node("UILayer/HUD")
	game.state = "play"
	for i in 40:
		await process_frame
	# chart the ground around every spire — the pings only draw on explored
	# cells, the same fog rule the treasure X and tombstones obey
	for tag in game.spire_pos:
		var sp: Vector2i = game.spire_pos[tag]
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var x := sp.x + dx
				var y := sp.y + dy
				if game.world.in_bounds(x, y):
					game.explored[y * game.world.WORLD_W + x] = 1
	# break the first spire on paper — its ping should flip to hollow
	var tags: Array = game.spire_pos.keys()
	if not tags.is_empty():
		game.spires_done[tags[0]] = true
	hud.map_show = true
	hud.bake_minimap()
	hud.bake_fog()
	for i in 10:
		await process_frame
	await _shot("map")
	quit()

func _process(_dt: float) -> bool:
	return false
