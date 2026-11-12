# capture theatre evidence — spawns a weak wild kin, lobs an orb at it,
# saves three frames: mid-arc, wobble, resolved. /tmp/plg-catch-*.png
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-catch-%s.png" % name)
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
	# a weakened wild kin in catch range — hp=1 makes the verdict a lock so
	# the third frame shows the success side of the theatre
	var k: Kin = game.gen_pal("fenjelly", 5, game.player.pos + Vector2(2.5, -0.5))
	k.mode = "wild"
	k.hp = 1
	game.add_item("ultra_orb", 5)
	var cam = main.get_node("Camera2D")
	cam.zoom = Vector2(2.0, 2.0)
	for i in 8:
		await process_frame
	# seeded rng — the first throw can deterministically roll "broke free";
	# keep lobbing (5 in the bag) until the verdict lands caught
	var first := true
	while k.mode == "wild" and game.item_count("ultra_orb") > 0:
		game.sphere_fly("ultra_orb", k)
		game.add_item("ultra_orb", -1)
		for i in 12: # t≈0.25 — orb mid-arc over the target
			await process_frame
		if first:
			await _shot("arc")
		for i in 22: # wobble theatre: the landed ball rocks its three shakes
			await process_frame
		if first:
			await _shot("wobble")
			first = false
		for i in 100: # verdict lands at t≈1.8s — past the wobble, floater up
			await process_frame
	await _shot("resolved")
	print("catch verdict: mode=%s party=%d" % [k.mode, game.party.size()])
	quit()

func _process(_dt: float) -> bool:
	return false
