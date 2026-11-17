# visual-evidence capture for the S108 den wardens — spawns the four new
# legendaries at warden scale (2.5x, the same form spawn_legendary_den
# uses) beside the keeper, then once more at heir (catchable) scale.
# Windowed only.
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

func _spawn_warden(sid: String, at: Vector2, scale: float, boss := true) -> void:
	var bp := preload("res://src/kin.gd").new()
	bp.alpha = true
	bp.boss = boss
	game.entity_layer.add_child(bp)
	bp.setup(game, sid, 50, at)
	if scale != 1.0: # warden form — den code's own 2.5x + -78px profile
		bp.sprite.scale = Vector2(scale, scale)
		bp.sprite.position.y = -78.0 * scale / 2.5
	bp.home = bp.pos
	game.pals.append(bp)
	# frozen for the portrait — a live tier-3 warden would walk to the
	# keeper and unload its signature before the shutter falls
	bp.set_process(false)
	bp.set_physics_process(false)
	bp.sync_screen() # position sync lives in the tick we just froze

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
	var kp: Vector2 = game.player.pos
	# find a clear 16-wide row: fresh seeds can bury the keeper under canopy
	# and the frozen wardens stay wherever they were told to stand
	var row_y := -1
	var row_x := -1
	for ty in range(int(kp.y) - 8, int(kp.y) + 9):
		for tx in range(int(kp.x) - 12, int(kp.x) + 5):
			var clear := true
			for dx in range(16):
				# ORDER MATTERS: blocked() bounds-checks before decor's idx()
				# — idx() itself has no clamp (audit-61 L10a)
				if game.world.blocked(tx + dx, ty) \
						or game.world.decor[game.world.idx(tx + dx, ty)] != 0:
					clear = false; break
			if clear:
				row_x = tx; row_y = ty; break
		if row_y >= 0: break
	if row_y < 0:
		print("WARN no clear row — wardens may hide under canopy")
		row_x = int(kp.x) - 8; row_y = int(kp.y)
	var rc := Vector2(row_x + 8.0, row_y + 0.5)
	game.player.pos = rc
	var ids := ["dreadwyrm", "gloamwing", "cragmaw", "hexfiend"]
	for i in ids.size():
		_spawn_warden(ids[i], rc + Vector2(-6.0 + i * 4.0, -0.6), 2.5)
	for i in 20:
		await process_frame
	game.tod = 10.0
	await _shot("den-wardens")
	# heir scale — the catchable form the den calls next
	for p in game.pals.duplicate():
		if is_instance_valid(p) and p.species_id in ids:
			game.pals.erase(p); p.queue_free()
	for i in 5:
		await process_frame
	for i in ids.size():
		_spawn_warden(ids[i], rc + Vector2(-6.0 + i * 4.0, -0.6), 1.0, false)
	for i in 20:
		await process_frame
	await _shot("den-heirs")
	quit()

func _process(_dt: float) -> bool:
	return false
