# S117 host side — real two-process session acceptance.
# Hosts on :7777, publishes seed/day in net_host_state.txt, then gates
# what the JOIN process does: ghost lands, movement tracks, harvest_req
# relays to a real chop, spoofed pos/harvest are refused, disconnect
# frees the ghost. Phases coordinate through tools/net_walk_*.txt —
# the joiner writes a marker BEFORE acting so the host can snapshot a
# baseline before the effect lands. Run windowed (shots need a texture).
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

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("/tmp/plg-net-%s.png" % name)
		print("shot %s" % name)

func _marker(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text().strip_edges()
	f.close()
	return s

func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame

func _boot() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 12:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	for i in 20:
		await process_frame
	game.state = "play"
	game.net.host()
	_gate("host binds :7777", game.net.is_host)
	if not game.net.is_host:
		_finish()
		return
	# wipe every marker AND stale output — an aborted run must not prime the
	# next with old claims, and a previous all-PASS report is not evidence
	for stale in ["res://tools/net_walk_target.txt", "res://tools/net_walk_far.txt",
			"res://tools/net_walk_far_fired.txt", "res://tools/net_walk_phase.txt",
			"res://tools/net_walk_claim.txt", "res://tools/net_host_state.txt",
			"res://tools/net_host_out.txt", "res://tools/net_walk_join_out.txt"]:
		DirAccess.remove_absolute(stale)
	var fo := FileAccess.open("res://tools/net_host_state.txt", FileAccess.WRITE)
	fo.store_line(str(game.world.seed))
	fo.store_line("%d,%f" % [game.day, game.tod])
	fo.close()

	# ---- guest lands: a registered ghost is the whole session's hinge
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and game.net.ghosts.is_empty():
		await process_frame
	_gate("guest ghost lands", game.net.ghosts.size() == 1, # exactly one —
		"ghosts=%s" % str(game.net.ghosts.keys())) # a stray second client
	if game.net.ghosts.size() != 1:                     # would fork the verdicts
		_finish()
		return
	var gid: int = game.net.ghosts.keys()[0]
	for i in 40: # let the first fix settle
		await process_frame
	var g = game.net.ghosts.get(gid) # ghosts free on disconnect — re-fetch,
	var pos0 := Vector2.ZERO        # never hold a possibly-freed reference
	if g != null:
		pos0 = Vector2(g.net_pos.x, g.net_pos.y)
	# the teardown gates must prove something EXISTED — capture the tag bind
	var tag_seen := false
	var t_tag := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_tag < 8000:
		await process_frame
		if game.net.peer_tags.has(gid):
			tag_seen = true
			break
	await _shot("net-guest")

	# ---- movement: guest walks with a real held key; its claim tells us
	# where it went — the ghost must end up near the claimed spot, not
	# merely "somewhere different" (a drift could fake a bare delta)
	var moved_ok := false
	var claim := Vector2(-1, -1)
	var gpos := pos0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000: # wall-clock — frame counts lie
		await process_frame                      # at non-60fps
		g = game.net.ghosts.get(gid)
		if g == null:
			break
		gpos = Vector2(g.net_pos.x, g.net_pos.y)
		var c := _marker("res://tools/net_walk_claim.txt").split(",")
		if c.size() == 2:
			claim = Vector2(float(c[0]), float(c[1]))
			# near the claim AND provably away from the landing fix — a
			# claim ≈ spawn must not pass on zero tracked movement
			if gpos.distance_to(claim) < 3.0 \
					and gpos.distance_to(pos0) > 1.0:
				moved_ok = true
				break
	_gate("ghost tracks guest movement", moved_ok,
		"ghost=%s claim=%s start=%s" % [str(gpos), str(claim), str(pos0)])

	# ---- harvest relay: guest writes its target, THEN taps LMB — the
	# baseline snapshot must land before the chop does
	var hp0 := -1
	var dec0 := -1
	var tc := Vector2i(-1, -1)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var m := _marker("res://tools/net_walk_target.txt").split(",")
		if m.size() == 2:
			tc = Vector2i(int(m[0]), int(m[1]))
			var ti: int = game.world.idx(tc.x, tc.y)
			hp0 = game.world.hp[ti]
			dec0 = game.world.decor[ti]
			break
		await process_frame
	_gate("harvest target received", tc.x >= 0, "cell=%s" % str(tc))
	if tc.x >= 0:
		var chopped := false
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 15000:
			await process_frame
			var ti2: int = game.world.idx(tc.x, tc.y)
			if game.world.hp[ti2] < hp0 or game.world.decor[ti2] != dec0:
				chopped = true
				break
		_gate("guest harvest_req chops the host cell", chopped,
			"hp %d→%d decor %d→%d" % [hp0, game.world.hp[game.world.idx(tc.x, tc.y)],
				dec0, game.world.decor[game.world.idx(tc.x, tc.y)]])
	await _shot("net-chop")

	# ---- hostile pos: the guest claims a 50-tile teleport with no travel
	# pad — the speed bucket must starve it at the door
	g = game.net.ghosts.get(gid)
	var pre_spoof := gpos if g == null else Vector2(g.net_pos.x, g.net_pos.y)
	var spoof_claim := Vector2(-1, -1)
	var marker_seen := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var s := _marker("res://tools/net_walk_phase.txt")
		if s == "spoofed":
			var sc := _marker("res://tools/net_walk_claim.txt").split(",")
			if sc.size() == 2:
				spoof_claim = Vector2(float(sc[0]), float(sc[1]))
				marker_seen = true
			break
		await process_frame
	# poll the WHOLE window — a single endpoint sample races the joiner's
	# return-home blink (a transiently-accepted spoof would read refused)
	var ever_reached := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		g = game.net.ghosts.get(gid)
		if g != null and spoof_claim.x >= 0 \
				and Vector2(g.net_pos.x, g.net_pos.y).distance_to(spoof_claim) < 15.0:
			ever_reached = true
			break
	g = game.net.ghosts.get(gid)
	var gpos2 := gpos if g == null else Vector2(g.net_pos.x, g.net_pos.y)
	var drifted := gpos2.distance_to(pre_spoof)
	_gate("spoofed 50-tile claim refused", marker_seen and not ever_reached,
		"ghost=%s claim=%s drift=%.1f" % [str(gpos2), str(spoof_claim), drifted])

	# ---- hostile harvest: a cell far outside the ghost's reach ring —
	# net_harvest's 4.0 proximity gate must refuse it
	var far_c := Vector2i(-1, -1)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var fm := _marker("res://tools/net_walk_far.txt").split(",")
		if fm.size() == 2:
			far_c = Vector2i(int(fm[0]), int(fm[1]))
			break
		await process_frame
	# a missing marker FAILS — a silently-skipped gate reads as a pass
	var far_ok := false
	var far_info := "no marker"
	if far_c.x >= 0:
		var fi: int = game.world.idx(far_c.x, far_c.y)
		var fhp0: int = game.world.hp[fi]
		var fdec0: int = game.world.decor[fi]
		# if the joiner's rpc already landed before this baseline the
		# "unchanged" verdict is vacuous — the fired marker exposes the race
		var raced: bool = FileAccess.file_exists(
			"res://tools/net_walk_far_fired.txt")
		g = game.net.ghosts.get(gid)
		var gdist := -1.0
		if g != null:
			gdist = Vector2(g.net_pos.x, g.net_pos.y).distance_to(
				Vector2(far_c.x + 0.5, far_c.y + 0.5))
		await _wait_ms(2500)
		# honest refusal needs: decor present (NONE early-returns before the
		# gate), the ghost REALLY out of ring (a refused return-home leaves
		# it at the harvest stand), and the baseline not raced
		far_ok = fdec0 != World.Decor.NONE and not raced and gdist > 4.0 \
			and game.world.hp[fi] == fhp0 and game.world.decor[fi] == fdec0
		far_info = "cell=%s decor=%d gdist=%.1f raced=%s hp=%d" % [
			str(far_c), fdec0, gdist, raced, game.world.hp[fi]]
	_gate("out-of-reach harvest_req refused", far_ok, far_info)

	# ---- disconnect: the guest quits — ghost, tag and relay all release
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		if not game.net.ghosts.has(gid):
			break
	_gate("disconnect frees the ghost", not game.net.ghosts.has(gid),
		"ghosts=%s" % str(game.net.ghosts.keys()))
	# tag_seen was captured at land — teardown proves something was released
	_gate("disconnect frees the tag", tag_seen and not game.net.peer_tags.has(gid),
		"seen=%s tags=%s" % [tag_seen, str(game.net.peer_tags.keys())])
	await _shot("net-gone")
	_finish()

func _finish() -> void:
	var fo := FileAccess.open("res://tools/net_host_out.txt", FileAccess.WRITE)
	for r in results:
		fo.store_line(r)
	fo.store_line("==== HOST: %d failures ====" % fails)
	fo.close()
	print("==== HOST: %d failures ====" % fails)
	quit(fails)
