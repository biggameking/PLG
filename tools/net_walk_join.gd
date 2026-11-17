# S117 join side — real two-process session acceptance.
# Joins 127.0.0.1:7777, syncs the world, then performs the verbs under
# test in order and reports its own view: seed sync, host ghost visible,
# movement (real held key), harvest_req via the real LMB->melee->
# try_harvest path, decor_delta echo back, then the two spoof attempts.
# Phase markers (net_walk_*.txt) tell the host what to look for; each is
# written BEFORE the act so the host snapshots its baseline first.
extends SceneTree

var fails := 0
var game: Node
var main: Node
var results := []

func _initialize() -> void:
	call_deferred("_boot")

func _gate(name: String, cond: bool, info := "") -> void:
	var line := ("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else "")
	print(line)
	results.append(line)
	if not cond:
		fails += 1

func _click(x: float, y: float) -> void:
	root.warp_mouse(Vector2i(int(x), int(y)))
	await process_frame
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.position = Vector2(x, y)
	p.pressed = true
	Input.parse_input_event(p)
	await process_frame
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.position = Vector2(x, y)
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame

func _write(path: String, txt: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()

func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame

func _tree_stand(from: Vector2, r: int, max_step: float) -> Dictionary:
	# trees are themselves blocked — the stand cell must be free AND (when
	# max_step>0) inside the host's POS_BURST window so the honest claim
	# doesn't eat the same speed-cap the spoof gate tests
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx: int = int(from.x) + dx
			var cy: int = int(from.y) + dy
			if not game.world.in_bounds(cx, cy):
				continue
			var dd: int = game.world.decor_at(cx, cy)
			if dd != World.Decor.TREE_A and dd != World.Decor.TREE_B:
				continue
			for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				# ORTHOGONAL only: a diagonal stand aims facing=(.7,.7) — the
				# dominant-axis pick in try_harvest hits the neighbor cell,
				# not the tree (the relay reaches the host and chops air)
				var st := Vector2(cx + d2.x + 0.5, cy + d2.y + 0.5)
				if game.world.blocked(int(st.x), int(st.y)):
					continue
				if max_step > 0.0 and st.distance_to(from) > max_step:
					continue
				# a wild kin (or the trader) inside melee reach eats the
				# swing (hit_any) — and kin WANDER, so the buffer must
				# outlast the marker wait + swing window, not just reach
				var kin_near := false
				for q2 in game.pals:
					if q2.mode == "wild" and q2.hp > 0 \
							and st.distance_to(q2.pos) <= 3.5:
						kin_near = true
						break
				if not kin_near and game.merchant != null \
						and is_instance_valid(game.merchant):
					kin_near = st.distance_to(game.merchant.pos) <= 3.0
				if not kin_near:
					return {"target": Vector2i(cx, cy), "stand": st}
	return {}

func _boot() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 12:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	for i in 20:
		await process_frame
	# stay in "title": join() save_game()s any non-title state, and at that
	# instant is_client() is still false — the throwaway boot world would be
	# serialized over the REAL save. _arrive_guest flips to play on
	# world_sync, which is the only transition this run needs.
	DirAccess.remove_absolute("user://plg_net.cfg") # a stale tag must not
	# squat on the session — hello claims are per-install, not per-run
	DirAccess.remove_absolute("res://tools/net_walk_join_out.txt") # stale
	# all-PASS evidence must not outlive its own run

	# wait for the host's marker, then join
	var host_seed := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and host_seed < 0:
		var fr := FileAccess.open("res://tools/net_host_state.txt", FileAccess.READ)
		if fr:
			host_seed = int(fr.get_line())
			fr.close()
			break
		await process_frame
	_gate("host marker found", host_seed >= 0)
	if host_seed < 0:
		_finish()
		return
	game.net.join("127.0.0.1")
	t0 = Time.get_ticks_msec()
	var synced := false
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		if game.net.ghosts.has(1) and game.world.seed == host_seed:
			synced = true
			break
	_gate("world seed synced", synced and game.world.seed == host_seed,
		"seed=%d want=%d" % [game.world.seed, host_seed])
	_gate("host ghost visible", game.net.ghosts.has(1),
		"ghosts=%s" % str(game.net.ghosts.keys()))
	if not synced:
		_finish()
		return
	for i in 30:
		await process_frame

	# ---- movement: real held key, then claim the landing spot so the
	# host can prove the ghost actually tracked THIS walk
	var p0: Vector2 = game.player.pos
	# the spawn ring can wall off any one direction (water/decor) — walk the
	# first key that actually moves us; measured displacement is the honest
	# signal, a blocked guess just burns its own attempt
	var walked := false
	for k in [KEY_D, KEY_S, KEY_A, KEY_W]:
		var kp := InputEventKey.new()
		kp.keycode = k; kp.pressed = true
		Input.parse_input_event(kp)
		await _wait_ms(1400)
		var kr := InputEventKey.new()
		kr.keycode = k; kr.pressed = false
		Input.parse_input_event(kr)
		await _wait_ms(300)
		if game.player.pos.distance_to(p0) > 1.0:
			walked = true
			break
	await _wait_ms(600) # let the 20Hz sender ship the landing fix
	_write("res://tools/net_walk_claim.txt", "%f,%f" % [game.player.pos.x, game.player.pos.y])
	_gate("held key walks the keeper", walked,
		"moved %.1f" % game.player.pos.distance_to(p0))
	await _wait_ms(800)

	# ---- harvest: stand beside real decor, face it, real LMB — the
	# click -> melee -> try_harvest -> is_client -> harvest_req relay is
	# the whole verb under test. Write the target BEFORE tapping so the
	# host snapshots the cell's hp first.
	var found := _tree_stand(game.player.pos, 3, 5.2)
	if found.is_empty(): # sparse spawn — hop toward the nearest tree in
		var far2 := _tree_stand(game.player.pos, 60, 0.0) # <=5-tile claims
		if not far2.is_empty():                            # the bucket accepts
			var dir2: Vector2 = (far2["stand"] - game.player.pos).normalized()
			game.player.pos += dir2 * 4.5
			game.player.sync_screen()
			await _wait_ms(600) # POS_RATE refills the burst while we wait
			found = _tree_stand(game.player.pos, 4, 5.2)
	var target: Vector2i = found.get("target", Vector2i(-1, -1))
	var stand: Vector2 = found.get("stand", Vector2(-1, -1))
	_gate("decor target in reach", target.x >= 0, "cell=%s" % str(target))
	if target.x >= 0:
		game.player.pos = stand # an honest stand spot — the host-side ghost
		game.player.sync_screen() # must sit inside net_harvest's 4.0 ring too
		game.player.facing = (Vector2(target.x + 0.5, target.y + 0.5) - stand).normalized()
		_write("res://tools/net_walk_target.txt", "%d,%d" % [target.x, target.y])
		await _wait_ms(1500) # the host must read the marker before the chop
		main.cam.global_position = game.player.global_position
		# one swing is hp-10 — decor_delta only fires on FELLING (decor value
		# change), so the echo gate asks for the full chop: 3 real swings.
		# Budget extra clicks — a wandering wild kin can legally eat one.
		for s in 8:
			var di2: int = game.world.idx(target.x, target.y)
			var dd2: int = game.world.decor[di2]
			if dd2 != World.Decor.TREE_A and dd2 != World.Decor.TREE_B:
				break
			# a wandered-in kin eats the swing (hit_any) — wait it out,
			# bounded; a kin that stays parked just burns its own clicks
			var tw := Time.get_ticks_msec()
			while Time.get_ticks_msec() - tw < 2500:
				var blocked_by := false
				for q3 in game.pals:
					if q3.mode == "wild" and q3.hp > 0 \
							and game.player.pos.distance_to(q3.pos) <= 1.55:
						blocked_by = true
						break
				if not blocked_by and game.merchant != null \
						and is_instance_valid(game.merchant) \
						and game.player.pos.distance_to(game.merchant.pos) <= 1.55:
					blocked_by = true
				if not blocked_by:
					break
				await process_frame
			game.player.atk_cd = 0.0 # fixture pacing — the verb is the relay
			var mp: Vector2 = root.get_canvas_transform() * \
				Iso.to_screen(game.player.pos.x, game.player.pos.y, 0.0)
			await _click(mp.x, mp.y)
			await _wait_ms(600)
		# the host's felling echoes back as decor_delta — the cell flips to
		# stump/none on OUR replica too, not just on theirs
		var echoed := false
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 10000:
			await process_frame
			var di3: int = game.world.idx(target.x, target.y)
			if game.world.decor[di3] != World.Decor.TREE_A \
					and game.world.decor[di3] != World.Decor.TREE_B:
				echoed = true
				break
		_gate("decor_delta echoes the felled tree", echoed,
			"decor=%d" % game.world.decor[game.world.idx(target.x, target.y)])

	# ---- spoof position: jump 50 tiles, let the sender fire the claim —
	# the host's speed bucket should refuse it (it has its own gate; ours
	# is just proving the claim went out). Then walk back into range.
	# pick a FREE in-bounds landing cell ~50 tiles out — a blocked/OOB target
	# gets refused at the bounds check BEFORE the speed bucket, which would
	# pass the host gate without testing the named path
	var spoof_to: Vector2 = game.player.pos + Vector2(50, 0)
	for off in [Vector2(50, 0), Vector2(-50, 0), Vector2(0, 50), Vector2(0, -50),
			Vector2(55, 10), Vector2(-55, -10), Vector2(45, 25), Vector2(-45, -25)]:
		var cand: Vector2 = game.player.pos + off
		if game.world.in_bounds(int(cand.x), int(cand.y)) \
				and not game.world.blocked(int(cand.x), int(cand.y)):
			spoof_to = cand
			break
	game.player.pos = spoof_to
	game.player.sync_screen()
	_write("res://tools/net_walk_claim.txt", "%f,%f" % [spoof_to.x, spoof_to.y])
	_write("res://tools/net_walk_phase.txt", "spoofed")
	await _wait_ms(1200)
	for off in [Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0), Vector2(0, -3), Vector2.ZERO]:
		var home: Vector2 = p0 + off # return to honest range so the
		if not game.world.blocked(int(home.x), int(home.y)):
			game.player.pos = home     # harness ends on a truthful ghost
			break
	game.player.sync_screen()
	await _wait_ms(400)

	# ---- spoof harvest: pick a decor cell far past the 4.0 reach ring,
	# fire harvest_req at it directly — the verb is the wire call; the
	# proximity gate lives host-side
	# the cell must sit >4.0 from wherever the ghost may stand — home AND the
	# harvest stand (if the return claim was refused the ghost lingers there,
	# and a "far" cell inside its ring is a false-FAIL, not a rejection)
	var far := Vector2i(-1, -1)
	for r3 in range(10, 40):
		var cx3: int = int(game.player.pos.x) + r3
		var cy3: int = int(game.player.pos.y)
		if not game.world.in_bounds(cx3, cy3) or game.world.decor_at(cx3, cy3) == 0:
			continue
		var fc := Vector2(cx3 + 0.5, cy3 + 0.5)
		if fc.distance_to(game.player.pos) > 4.0 \
				and (stand.x < 0 or fc.distance_to(stand) > 4.0):
			far = Vector2i(cx3, cy3)
			break
	if far.x >= 0:
		_write("res://tools/net_walk_far.txt", "%d,%d" % [far.x, far.y])
		await _wait_ms(2000) # the host MUST baseline the far cell before
		# this rpc lands — the fired marker lets it detect a missed window
		game.net.rpc("harvest_req", far.x, far.y)
		_write("res://tools/net_walk_far_fired.txt", "1")
		await _wait_ms(800)
		_gate("far harvest_req fired", game.net.is_client(),
			"cell=%s" % str(far))
	else:
		_gate("far harvest_req fired", false, "no far decor cell found")

	await _wait_ms(2500) # let the host evaluate both spoofs, then leave
	_finish()

func _finish() -> void:
	var fo := FileAccess.open("res://tools/net_walk_join_out.txt", FileAccess.WRITE)
	for r in results:
		fo.store_line(r)
	fo.store_line("==== JOIN: %d failures ====" % fails)
	fo.close()
	print("==== JOIN: %d failures ====" % fails)
	quit(fails)
