# crowned-den tracker evidence — sets the campaign spine complete, drops a
# catchable heir legend near the player, saves /tmp/plg-den.png
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

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
	# campaign spine complete → the tracker must offer the next chase
	for s in game.SPIRE_DEFS.size():
		game.spires_done["spire_%d" % s] = true
	game.crowned = true
	for ls in ["scalbeak", "snovstride", "nibhand"]: # three recorded catches
		game.catch_counts[ls] = 1
	var heir: Kin = game.gen_pal("wyrmhoof", 45, game.player.pos + Vector2(3, -1))
	heir.mode = "wild"; heir.alpha = true # a respawned heir: alpha, not boss
	for i in 10:
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-den.png")
	print("shot den %s" % str(img.get_size()))
	quit()

func _process(_dt: float) -> bool:
	return false
