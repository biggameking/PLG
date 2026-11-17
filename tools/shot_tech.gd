# S109 tech-icon evidence — seeds the three unlock states (done / affordable /
# locked) plus ancient-tech violet rows, then screenshots the real panel.
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
	# mix of states: a few unlocked, points+parts for affordable rows, and the
	# untouched tail stays locked/violet
	for t in StructureData.TECH.slice(0, 12):
		game.unlocked.append(t["id"])
	game.tech_points = 8
	game.items["ancient_part"] = 9
	var hudn: Node = main.get_node("UILayer/HUD")
	hudn.tech_scroll = 0
	game.panel = "tech"
	for i in 10:
		await process_frame
	await _shot("tech-p1")
	hudn.tech_scroll = 36 # second column onward — ancient/late nodes live here
	for i in 10:
		await process_frame
	await _shot("tech-p2")
	quit()

func _process(_dt: float) -> bool:
	return false
