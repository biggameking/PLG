# visual-evidence capture — runs windowed (headless has a dummy renderer),
# saves title / play / kinbox / pause PNGs to /tmp/plg-shot-*.png then quits.
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
	await _shot("title")
	game.state = "play"
	game.log_msg("Day 1 on the Wildmere — catch a kin, feed it, put it to work.")
	for i in 40:
		await process_frame
	await _shot("play")
	game.panel = "kinbox"
	for i in 8:
		await process_frame
	await _shot("kinbox")
	game.panel = ""
	game.state = "paused"
	for i in 8:
		await process_frame
	await _shot("pause")
	quit()

func _process(_dt: float) -> bool:
	return false
