# visual evidence — settings + controls panels, windowed for a real frame.
extends SceneTree

var main
var game

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-shot-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	game.panel = "settings"
	for i in 10:
		await process_frame
	await _shot("settings")
	game.panel = "controls"
	for i in 10:
		await process_frame
	await _shot("controls")
	var hudn = main.get_node("UILayer/HUD")
	hudn.rebind_wait = "dodge"
	for i in 6:
		await process_frame
	await _shot("controls-capture")
	quit(0)

func _initialize() -> void:
	call_deferred("_boot")
