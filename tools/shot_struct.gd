# visual-evidence capture for migrated structure sprites — plants the
# S105 batch around the keeper via place_free (the same placement path
# net/worldgen use) and screenshots the base. Windowed only.
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
	# plant the migrated batch on clear grass near the keeper — two rows so
	# y-sorting shows tall pieces behind short ones
	var kp: Vector2 = game.player.pos
	var tx0 := int(kp.x) - 4
	var ty0 := int(kp.y) - 4
	var ids := ["kinbox", "watch_tower", "notice_board", "waypoint", "well", "torch",
		"campfire", "workbench", "chest", "feed_box", "kin_bed", "wooden_wall",
		"furnace", "generator", "crusher", "mill", "incubator", "ore_mine",
		"logging_site", "stone_pit", "gathering_site", "spikes", "cooler",
		"kin_condenser",
		"berry_farm","wheat_farm","ranch","straw_bed","hot_spring",
		"fish_trap","snare_trap","kin_cage","guard_post","training_hall",
		"sparring_ring","training_dummy","war_banner","monitoring_stand",
		"pharmacy","oil_extractor","sphere_factory","sphere_factory_2",
		"compost_bin","apiary","weather_shrine","kin_gacha","fossil_bed",
		"spyglass","lightning_rod","expedition_post"]
	var placed := 0
	for ty in range(ty0, ty0 + 15):
		for tx in range(tx0, tx0 + 15):
			if placed >= ids.size():
				break
			var sid: String = ids[placed]
			if game.place_free(sid, tx, ty):
				placed += 1
	for i in 20:
		await process_frame
	game.tod = 10.0
	await _shot("structures")
	game.tod = 21.5 # campfire/torch glow under ink night
	for i in 10:
		await process_frame
	await _shot("structures-night")
	quit()

func _process(_dt: float) -> bool:
	return false
