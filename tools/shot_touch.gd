# touch-UI evidence: force touch_ui on, capture the verb cluster and the
# expanded more-row. Windowed only (root.get_texture needs a swapchain):
#   Godot --path . -s tools/shot_touch.gd
extends SceneTree

var main
var game

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
	game.state = "play"
	game.touch_ui = true
	# a partner in the field proves the party column flows below the hint
	# cluster instead of overlapping it (audit-76 F5)
	var p = game.gen_pal("petalantler", 5, game.player.pos + Vector2(1.2, 0.4))
	if p:
		p.mode = "partner"
		game.party.append(p.uid) # the roster stores uids, not nodes
	for i in 40:
		await process_frame
	await _shot("touch-verbs")
	main.get_node("UILayer/HUD").touch_more = true # ··· row: asg/stn/ksk/rde/dml/map
	for i in 10:
		await process_frame
	await _shot("touch-more")
	quit()

func _process(_dt: float) -> bool:
	return false
