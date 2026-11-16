# build-bar icon + paging + ghost evidence — unlocks enough structures
# to need paging, opens the bar, picks a structure to show the sprite ghost.
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
	# unlock a page-and-a-half so the bar pages — count the FILTERED list,
	# unlocked carries non-structure ids too
	for sid in StructureData.STRUCTURES.keys():
		if game.buildable_list().size() >= 14:
			break
		if not game.unlocked.has(sid):
			game.unlocked.append(sid)
	var hudn: Node = main.get_node("UILayer/HUD")
	game.panel = "build"
	for i in 10:
		await process_frame
	await _shot("build-bar")
	hudn.run_click({"act": "build_pg", "arg": 1})
	for i in 10:
		await process_frame
	await _shot("build-page2")
	# pick a page-2 slot through the real click path — an off-page absolute
	# index demos nothing and sid-pinning would now refuse the mismatch
	hudn.run_click({"act": "build_pick", "arg": 10})
	# park the cursor on a real tile — the ghost trails the mouse and the
	# default position sits nowhere near the player
	root.warp_mouse(Vector2(700, 380))
	for i in 12:
		await process_frame
	await _shot("build-ghost")
	quit()

func _process(_dt: float) -> bool:
	return false
