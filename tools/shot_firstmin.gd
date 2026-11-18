# first-session evidence: boots a new island, walks the first minutes,
# captures title/spawn/hint/mission frames into docs/reviews/.
# Run WINDOWED (root.get_texture needs a real swapchain):
#   Godot --path . -s tools/shot_firstmin.gd
extends SceneTree

var main
var game
var frame := 0
var shots := {}

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://docs/reviews/s123-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	game = main.get_node("Game")
	await _shot("title")
	# start a fresh island the way CONTINUE/NEW does
	game.state = "play"
	for i in 30:
		await process_frame
	await _shot("spawn")
	# the kinbox hint fires on spawn (cond: kinbox_pos.x < 0) — give it a beat
	for i in 60:
		await process_frame
	await _shot("hint")
	# open the guide overlay the way N does
	game.panel = "guide"
	for i in 10:
		await process_frame
	await _shot("guide")
	game.panel = ""
	quit()

func _process(_dt: float) -> bool:
	return false
