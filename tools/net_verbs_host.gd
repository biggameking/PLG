# S118 host side — deep guest-verb acceptance over a real ENet session.
# Beyond S117's spine (walk/harvest/spoof/disconnect) this proves the
# substantive verbs: a guest CATCH joins their own strip (remote_parties,
# owner_tag), a guest BUILD lands under placed_tag, pal_hit relays are
# clamped to the honest ceiling, far hits/catches/builds fail closed, and
# a leaving keeper's roster ORPHANS under the tag — not deleted.
# Coordination: joiner writes net_verb_*.txt markers BEFORE acting; this
# side snapshots baselines first. Run windowed (shots need a texture).
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
		img.save_png("/tmp/plg-verb-%s.png" % name)
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

# poll a predicate for up to `ms` — returns the last value; never holds a
# node ref across the await (ghosts free on disconnect)
func _until(ms: int, fn: Callable) -> Variant:
	var t0 := Time.get_ticks_msec()
	var v = fn.call()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		v = fn.call()
		if v:
			return v
	return v

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
	for stale in ["res://tools/net_host_state.txt", "res://tools/net_host_out.txt",
			"res://tools/net_walk_join_out.txt", "res://tools/net_verb_join_out.txt"]:
		DirAccess.remove_absolute(stale)
	for m in DirAccess.get_files_at("res://tools/"): # every prior marker dies —
		if m.begins_with("net_verb_"):              # an aborted run never primes
			DirAccess.remove_absolute("res://tools/" + m) # the next
	var fo := FileAccess.open("res://tools/net_host_state.txt", FileAccess.WRITE)
	fo.store_line(str(game.world.seed))
	fo.store_line("%d,%f" % [game.day, game.tod])
	fo.close()

	# ---- land: exactly one ghost, and its hello tag must actually bind —
	# every tag-scoped verdict below depends on the bind having happened
	var g = await _until(30000, func(): return game.net.ghosts.size() == 1)
	_gate("guest ghost lands", g == true, "ghosts=%s" % str(game.net.ghosts.keys()))
	if not g:
		_finish()
		return
	var gid: int = game.net.ghosts.keys()[0]
	var tag: String = await _until(8000,
		func(): return str(game.net.peer_tags.get(gid, "")))
	_gate("hello tag binds", tag != "", "tags=%s" % str(game.net.peer_tags.keys()))
	for i in 30:
		await process_frame

	# ---- ready marker carries the guest's landing claim: the fixture pins
	# kin next to the GHOST'S real spot, not a guess
	var rc := Vector2(-1, -1)
	var rc_seen := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var c := _marker("res://tools/net_verb_ready.txt").split(",")
		if c.size() == 2:
			rc = Vector2(float(c[0]), float(c[1]))
			rc_seen = true
			break
		await process_frame
	_gate("guest ready claim seen", rc_seen, "claim=%s" % str(rc))
	if not rc_seen:
		_finish()
		return

	# ---- fixture: a weak kin (catch bait) and a tank kin (clamp probe)
	# pinned beside the ghost — DISABLED so they can't wander out of the
	# verb rings mid-run. Both stay in pals so pal_sync keeps broadcasting.
	# Anchor on the ghost's LIVE pos, not the ready claim — the claim was
	# sampled before the walk leg; los/range checks run against where the
	# keeper actually stands now
	var gg = game.net.ghosts.get(gid)
	if gg != null:
		rc = Vector2(gg.net_pos.x, gg.net_pos.y)
	var weak: Kin = null
	var tank: Kin = null
	var best_d := INF
	for p in game.pals:
		# the bait must pass the SAME gate the orb answers to — an alpha or
		# den heir refuses catchable() and burns every honest throw (nvC)
		if p.mode == "wild" and p.hp > 0 and game.catchable(p) \
				and p.pos.distance_to(rc) < best_d:
			best_d = p.pos.distance_to(rc)
			weak = p
	var best2 := INF
	for p in game.pals:
		if p.mode == "wild" and p.hp > 0 and p != weak \
				and p.pos.distance_to(rc) < best2:
			best2 = p.pos.distance_to(rc)
			tank = p
	# pin on FREE cells beside the claim — a wall between ghost and bait
	# fails los_clear for a legit reason, which is not the verb under test
	var free_cells := []
	for d3 in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2),
			Vector2(2, 1), Vector2(-2, 1), Vector2(1, 2), Vector2(1, -2)]:
		var c3: Vector2 = rc + d3
		if game.world.in_bounds(int(c3.x), int(c3.y)) \
				and not game.world.blocked(int(c3.x), int(c3.y)) \
				and game.world.los_clear(rc, c3):
			free_cells.append(c3)
	if weak != null and free_cells.size() > 0:
		weak.pos = free_cells[0]
		weak.hp = 3.0 # hp_frac ~0.03 — the honest catch roll sits near cap
		weak.process_mode = Node.PROCESS_MODE_DISABLED
	var tk_hp_fix := -1.0
	if tank != null and free_cells.size() > 1:
		tank.pos = free_cells[1]
		tank.hp = 500.0
		tank.max_hp = 500.0
		tank.process_mode = Node.PROCESS_MODE_DISABLED
		tk_hp_fix = tank.hp # the clamp gate measures the drop from HERE —
		# not from whenever the marker happens to get read (rpc can land first)
	if not game.unlocked.has("torch"):
		game.unlocked.append("torch") # the guest builds host tech — the
		# unlocked row rides env_sync/net_unlocked into their build panel
	var pins := FileAccess.open("res://tools/net_verb_pins.txt", FileAccess.WRITE)
	pins.store_line("%d,%f,%f,%d" % [
		weak.uid if weak != null else -1,
		free_cells[0].x if free_cells.size() > 0 else rc.x,
		free_cells[0].y if free_cells.size() > 0 else rc.y,
		tank.uid if tank != null else -1])
	pins.close()
	_gate("fixture pins planted",
		weak != null and tank != null and free_cells.size() >= 2,
		"weak=%s tank=%s cells=%d" % [weak != null, tank != null,
			free_cells.size()])

	# ---- CATCH: the guest's orb flight -> sphere_catch -> net_catch must
	# land the kin under THEIR tag in remote_parties — not the host roster
	var rp0: int = game.rparty_by_tag(tag).size() if tag != "" else -1
	var caught: Variant = await _until(40000, func():
		if tag == "":
			return false
		var rp: Array = game.rparty_by_tag(tag)
		if rp.size() > rp0:
			for u in rp:
				var p: Kin = game.find_pal(int(u))
				if p != null and p.owner_tag == tag:
					return p
		return false)
	var caught_ok: bool = caught is Kin
	var caught_sid: String = caught.species_id if caught_ok else "" # the ref may
	# be freed by the orphan lane — the species is the stable identity
	_gate("guest catch joins their strip", caught_ok,
		"rp %d→%d owner=%s" % [rp0,
			game.rparty_by_tag(tag).size() if tag != "" else -1,
			caught.owner_tag if caught_ok else "?"])
	if caught_ok:
		_gate("caught kin left the wilds", caught.mode != "wild",
			"mode=%s" % caught.mode)
	await _shot("verb-catch")

	# ---- BUILD: guest picks torch, pays locally, host validates —
	# placed_tag must read THEIR tag (it outlives the pid)
	var bc := Vector2i(-1, -1)
	var bsid := ""
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var bm := _marker("res://tools/net_verb_build.txt").split(",")
		if bm.size() == 3:
			bsid = bm[0]
			bc = Vector2i(int(bm[1]), int(bm[2]))
			break
		await process_frame
	_gate("build marker seen", bc.x >= 0, "cell=%s sid=%s" % [str(bc), bsid])
	if bc.x >= 0:
		# the marker cell is the guest's INTENT — the click resolves through
		# mouse_tile and can honestly land a cell over; the contract under
		# test is that a structure materializes OWNED BY THEIR TAG
		var planted: Variant = await _until(20000, func():
			for k in game.structures:
				var st = game.structures[k]
				if str(st.get("placed_tag", "")) == tag:
					return st
			return false)
		var st_ok: bool = planted is Dictionary
		var pcell := Vector2i(-1, -1)
		if st_ok:
			for k in game.structures:
				if game.structures[k] == planted:
					pcell = k
					break
		_gate("guest build lands under their tag",
			st_ok and planted.get("id") == bsid,
			"id=%s tag=%s cell=%s" % [
				planted.get("id") if st_ok else "?",
				str(planted.get("placed_tag", "")) if st_ok else "?",
				str(pcell)])
		await _shot("verb-build")

	# ---- far catch: a nid >9 tiles from the ghost — fail closed
	var far_nid := -1
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var fm := _marker("res://tools/net_verb_farcatch.txt")
		if fm != "":
			far_nid = int(fm)
			break
		await process_frame
	var far_p: Kin = game.find_pal(far_nid) if far_nid > 0 else null
	var far_mode := far_p.mode if far_p != null else ""
	var far_hp: float = far_p.hp if far_p != null else -1.0
	var far_dist := -1.0
	if far_p != null:
		# freeze the target in place — a wandering far-pal drifting inside
		# the 9.0 ring would turn "refused" into an honest failed roll and
		# the gate can't tell the difference (audit-68 M3)
		far_p.process_mode = Node.PROCESS_MODE_DISABLED
		var fg = game.net.ghosts.get(gid)
		if fg != null:
			far_dist = Vector2(fg.net_pos.x, fg.net_pos.y).distance_to(far_p.pos)
	await _wait_ms(2500)
	var far_p2: Kin = game.find_pal(far_nid) if far_nid > 0 else null
	_gate("far sphere_catch refused",
		far_nid > 0 and far_p2 != null and far_p2.mode == far_mode \
			and far_p2.hp == far_hp and far_p2.mode == "wild" \
			and far_dist > 9.0,
		"nid=%d mode=%s d=%.1f" % [far_nid,
			far_p2.mode if far_p2 != null else "gone", far_dist])

	# ---- locked build: sid the host never unlocked — _pay_rej, no plant
	var lc := Vector2i(-1, -1)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var lm := _marker("res://tools/net_verb_locked.txt").split(",")
		if lm.size() == 3:
			lc = Vector2i(int(lm[1]), int(lm[2]))
			break
		await process_frame
	await _wait_ms(2500)
	var lst = game.structures.get(lc) if lc.x >= 0 else null
	_gate("locked build refused", lc.x >= 0 and lst == null,
		"cell=%s st=%s" % [str(lc), lst.get("id") if lst != null else "none"])

	# ---- far pal_hit: the ghost's 8.0 ring gates the swing, not the claim
	var hit_nid := -1
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var hm := _marker("res://tools/net_verb_farhit.txt")
		if hm != "":
			hit_nid = int(hm)
			break
		await process_frame
	var hit_p: Kin = game.find_pal(hit_nid) if hit_nid > 0 else null
	var hit_hp0: float = hit_p.hp if hit_p != null else -1.0
	await _wait_ms(2500)
	var hit_p2: Kin = game.find_pal(hit_nid) if hit_nid > 0 else null
	_gate("far pal_hit refused",
		hit_nid > 0 and hit_p2 != null and hit_p2.hp == hit_hp0,
		"nid=%d hp=%.0f" % [hit_nid, hit_p2.hp if hit_p2 != null else -1.0])

	# ---- forged damage: the tank is IN ring — only the honest-ceiling
	# clamp separates 1e9 from a real swing
	var tank_nid := -1
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var tm := _marker("res://tools/net_verb_tank.txt")
		if tm != "":
			tank_nid = int(tm)
			break
		await process_frame
	var tk: Kin = game.find_pal(tank_nid) if tank_nid > 0 else null
	var tk_live: bool = tk != null and is_instance_valid(tank) and tk == tank
	# the joiner re-sends until a landing syncs back — measure the LARGEST
	# single-frame drop, not the total: the clamp's promise is per-hit,
	# and a stacked second landing must not read as an unclamped 1e9
	var max_drop := 0.0
	var hp_prev := tk_hp_fix
	var seen := 0.0
	var tw0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw0 < 12000:
		var q = game.find_pal(tank_nid)
		if q != null and q.hp < hp_prev - 0.01:
			max_drop = maxf(max_drop, hp_prev - q.hp)
			hp_prev = q.hp
			seen += 1.0
		if seen > 0.0 and Time.get_ticks_msec() - tw0 > 4000:
			break # landed — a short tail lets a second hit register too
		await process_frame
	var tk2: Kin = game.find_pal(tank_nid) if tank_nid > 0 else null
	_gate("forged pal_hit clamped to honest ceiling",
		tank_nid > 0 and tk_live and seen > 0.0
			and max_drop > 0.0 and max_drop <= 250.0,
		"nid=%d hits=%.0f max_drop=%.0f hp %.0f→%.0f" % [tank_nid, seen,
			max_drop, tk_hp_fix, tk2.hp if tk2 != null else -1.0])

	# ---- ascension altar: the guest's sigil+orbs ring the host's world
	# truth — seal, ghost reach, one live ring — then the wire carries the
	# asc flag so the replica reads as big as the host's heir (audit-73)
	game.accord = true # the seal is world state — the altar answers to it
	var gp_asc: Vector2 = game._ghost_at(gid)
	var ac_cell := Vector2i(-1, -1)
	for ac_d in range(2, 5):
		for ac_s in range(8):
			var ac_try := Vector2i(int(gp_asc.x) + ac_d, int(gp_asc.y) - 3 + ac_s)
			if game.place_free("ascension_altar", ac_try.x, ac_try.y):
				ac_cell = ac_try
				break
		if ac_cell.x >= 0:
			break
	_gate("ascension altar planted in the ghost's reach",
		ac_cell.x >= 0 and gp_asc.distance_to(
			Vector2(ac_cell.x + 0.5, ac_cell.y + 0.5)) <= 5.0,
		"cell=%s ghost=%s" % [str(ac_cell), str(gp_asc)])
	var af := FileAccess.open("res://tools/net_verb_asc.txt", FileAccess.WRITE)
	af.store_string("ready"); af.close()
	var asc_live = await _until(8000, func(): return game._ascendant_live())
	var asc_tot := 0
	for ak in game.den_ascensions:
		asc_tot += int(game.den_ascensions[ak])
	_gate("guest ring calls an ascendant on host truth",
		asc_live != null and asc_live is Kin and asc_live.mode == "wild"
			and asc_live.alpha and asc_live.raid
			and asc_live.species_id in Game.LEGENDARY_DEN and asc_tot == 1,
		"asc=%s tot=%d" % [str(asc_live != null), asc_tot])
	# the second ring must refuse — the joiner fires it after settling
	await _until(8000, func():
		return _marker("res://tools/net_verb_asc2.txt") == "fired2")
	await _wait_ms(600) # let any late wire land before the census
	var asc_cnt := 0; var asc_tot2 := 0
	for ap2 in game.pals:
		if ap2.has_meta("ascendant") and ap2.hp > 0:
			asc_cnt += 1
	for ak2 in game.den_ascensions:
		asc_tot2 += int(game.den_ascensions[ak2])
	_gate("a second guest ring is refused — one walks, ledger still",
		asc_cnt == 1 and asc_tot2 == 1, "cnt=%d tot=%d" % [asc_cnt, asc_tot2])

	# ---- disconnect: ghost+tag release, and the guest's catch ORPHANS
	# under the tag in the box — the roster survives the keeper
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		if not game.net.ghosts.has(gid):
			break
	_gate("disconnect frees the ghost", not game.net.ghosts.has(gid),
		"ghosts=%s" % str(game.net.ghosts.keys()))
	_gate("disconnect frees the tag", tag != "" and not game.net.peer_tags.has(gid),
		"tags=%s" % str(game.net.peer_tags.keys()))
	# the catch may orphan into box (was field) or stay benched under the
	# tag — both are "roster survives"; only a freed/lost kin fails
	var orphan_ok := false
	var orphan_mode := "?"
	if caught_ok:
		for bp in game.box + game.bench:
			if is_instance_valid(bp) and bp.owner_tag == tag \
					and bp.species_id == caught_sid:
				orphan_ok = true
				orphan_mode = bp.mode
				break
	_gate("roster orphans under the tag", orphan_ok,
		"mode=%s tag=%s" % [orphan_mode, tag])
	await _shot("verb-gone")
	_finish()

func _finish() -> void:
	var fo := FileAccess.open("res://tools/net_host_out.txt", FileAccess.WRITE)
	for r in results:
		fo.store_line(r)
	fo.store_line("==== HOST: %d failures ====" % fails)
	fo.close()
	print("==== HOST: %d failures ====" % fails)
	quit(fails)
