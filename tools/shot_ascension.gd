# visual-evidence capture for the Ascension Altar + an ascendant heir —
# plants the altar via place_free (the world-gen placement path) and
# summons through the real _spawn_ascendant lane. Windowed only.
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
	root.size = Vector2i(1280, 720)
	var kp: Vector2 = game.player.pos
	# plant the altar two tiles ahead of the keeper
	var placed := false
	for rad in range(2, 10):
		for ang in range(16):
			var c := Vector2i(int(kp.x + cos(ang * TAU / 16.0) * rad),
				int(kp.y + sin(ang * TAU / 16.0) * rad))
			var ok := true
			for dy in range(2):
				for dx in range(2):
					var k := Vector2i(c.x + dx, c.y + dy)
					if game.structures.has(k) or not game.world.in_bounds(k.x, k.y):
						ok = false
			if ok and game.place_free("ascension_altar", c.x, c.y):
				placed = true
				break
		if placed:
			break
	print("altar placed: ", placed)
	# summon a real ascendant — dreadwyrm for silhouette, star-3 ledger
	game.den_ascensions["dreadwyrm"] = 3
	var asc: Kin = game._spawn_ascendant("dreadwyrm", kp + Vector2(4, 2))
	asc.aggro = -1 # freeze for the portrait — a live tier-3 heir would lunge
	for i in 45:
		await process_frame
	await _shot("s121-ascension")
	quit()
