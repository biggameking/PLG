# close-up capture for art review — spawns a kin beside the player,
# zooms in, saves /tmp/plg-kin-<sid>.png then quits.
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-kin-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	var sid := "fenjelly"
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	for i in 30:
		await process_frame
	# park a few of the species right at the player's feet
	for i in 3:
		var p = game.gen_pal(sid, 5, game.player.pos + Vector2(0.6 + i * 0.7, -0.3 + i * 0.4))
		if p:
			p.mode = "idle"
	var cam = main.get_node("Camera2D")
	cam.zoom = Vector2(2.2, 2.2)
	for i in 10:
		await process_frame
	await _shot(sid)
	quit()

func _process(_dt: float) -> bool:
	return false
