# UI evidence capture — seeds party/box/dex state so the roster surfaces
# actually render portraits, then shoots kinbox / dex / statues / play.
# Windowed run (headless has a dummy renderer); writes /tmp/plg-zh-*.png.
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-zh-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _seed() -> void:
	# three in the party (one out), five in the box, one deployed worker
	var pt: Vector2 = game.player.pos
	var ids := ["fenjelly", "scalbeak", "snovstride"]
	for i in ids.size():
		var k: Kin = game.gen_pal(ids[i], 6 + i * 3, pt + Vector2(1 + i, 1))
		k.mode = "partner"
		game.pals.append(k)
		game.party.append(k.uid)
	game.make_active(game.party[0])
	for sid in ["vermtrot", "mossjelly", "nibhand", "wyrmhoof", "tidscale"]:
		var b: Kin = game.gen_pal(sid, 8, pt)
		game.pals.append(b)
		game.box.append(b)
		game.box_pal(b)
	var w: Kin = game.gen_pal("loampuff", 7, pt + Vector2(2, 2))
	w.mode = "base"
	game.pals.append(w)
	# dex state: a few caught, a few only spotted
	for sid2 in ["fenjelly", "scalbeak", "snovstride", "vermtrot", "mossjelly"]:
		game.catch_counts[sid2] = 2
	for sid3 in ["nibhand", "wyrmhoof", "shadekin", "cindchew"]:
		game.dex_seen[sid3] = true

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	game.settings["lang"] = "zh"; game.apply_settings()
	for i in 30:
		await process_frame
	_seed()
	for i in 10:
		await process_frame
	await _shot("play")
	game.panel = "kinbox"
	for i in 8:
		await process_frame
	await _shot("kinbox")
	game.panel = "dex"
	for i in 8:
		await process_frame
	await _shot("dex")
	game.panel = "statues"
	for i in 8:
		await process_frame
	await _shot("statues")
	game.panel = ""
	quit()

func _process(_dt: float) -> bool:
	return false
