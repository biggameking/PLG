# accord evidence — seals the Wildmere Accord synthetically, captures the
# banner moment + the HUD tag that replaces the den counter. /tmp/plg-accord-*.png
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-accord-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

func _boot() -> void:
	var ps = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	game = main.get_node("Game")
	game.state = "play"
	for i in 20:
		await process_frame
	# stage the three seals, minus the last heir — the tag must read DEN 9/10
	game.spires_done.clear()
	for si in Game.SPIRE_DEFS.size():
		game.spires_done["spire_%d" % si] = true
	game.crowned = true
	game.mission_flags["gauntlet_ex"] = true
	for si2 in Game.LEGENDARY_DEN.size() - 1:
		game.catch_counts[Game.LEGENDARY_DEN[si2]] = 1
	await _shot("den-9of10")
	# the last heir lands — tick_accord seals it (1s dex cadence is skipped:
	# call it straight to keep the shot deterministic)
	game.catch_counts[Game.LEGENDARY_DEN.back()] = 1
	game.floaters.clear()
	game.tick_accord()
	await _shot("sealed")
	quit()
