# S75 first-session evidence — fresh-boot spawn ring, kinbox hint, build bar
# costs, help overlay GUIDE row, and the armed NEW GAME confirm row.
# Windowed run (headless has a dummy renderer); writes /tmp/plg-s75-*.png.
extends SceneTree

var main
var game
var hud

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-s75-%s.png" % name)
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
		await process_frame # settle: camera, hints, ring kin all tick in
	await _shot("spawn") # ring kin + starter hints on a fresh island
	game.panel = "build"
	hud.build_sel = game.buildable_list().find("kinbox")
	for i in 8:
		await process_frame
	await _shot("buildbar") # selected row shows the full recipe, short rows dim
	game.panel = ""
	hud.build_sel = -1
	hud.show_help = true
	for i in 8:
		await process_frame
	await _shot("help") # the GUIDE row
	hud.show_help = false
	game.has_save = true
	game.state = "title"
	for i in 8:
		await process_frame
	hud.shell_act("new_game") # arm — the row turns into the red SURE? line
	for i in 8:
		await process_frame
	await _shot("confirm")
	quit()

func _process(_dt: float) -> bool:
	return false
