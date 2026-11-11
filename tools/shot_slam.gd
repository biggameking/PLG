# S70/S71 combat evidence — five frames:
#   windup: phase-2 boss rooted mid-telegraph, "IT REARS UP" up
#   slam:   the ring lands — "PACT SLAM" + the player eating it
#   fan:    packVolley's three-shot fan mid-flight
#   pierce: arcLance bolt running a two-kin line
#   drain:  soulSiphon paying the caster back (+N over its head)
# /tmp/plg-slam-*.png
extends SceneTree

var main
var game

func _initialize() -> void:
	call_deferred("_boot")

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-slam-%s.png" % name)
	print("shot %s %s" % [name, img.get_size()])

# a verified projectile lane: `len` cells from `o` along `d` with no
# elevation rise, decor or structure — same wall rules as
# update_projectiles, so the bolt provably reaches its target
func _lane(o: Vector2, d: Vector2, len: int) -> bool:
	if not game.world.in_bounds(int(o.x), int(o.y)):
		return false
	var ev: int = game.world.elev_at(int(o.x), int(o.y))
	for i in range(len + 1):
		var cx := int(o.x + d.x * i)
		var cy := int(o.y + d.y * i)
		if not game.world.in_bounds(cx, cy) \
				or game.world.elev_at(cx, cy) > ev \
				or game.world.decor[game.world.idx(cx, cy)] != World.Decor.NONE \
				or game.structures.has(Vector2i(cx, cy)):
			return false
	return true

func _find_lane(len: int) -> Array: # [origin, dir] of the first clear lane
	var p0: Vector2 = game.player.pos
	for r in range(-10, 11):
		for c in range(-10, 11):
			var s: Vector2 = p0 + Vector2(c, r)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				if _lane(s, d, len):
					return [s, d]
	return [p0, Vector2(1, 0)]

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
	var p = game.player
	var cam = main.get_node("Camera2D")
	cam.zoom = Vector2(2.0, 2.0)

	# ---- frame 1+2: telegraphed slam ----
	var spot: Vector2 = game.nearest_free(p.pos.x + 3.0, p.pos.y)
	var boss: Kin = game.gen_pal("snovstride", 30, spot)
	boss.mode = "wild"
	game.pals.append(boss)
	boss.boss = true
	boss.phase = 2
	boss.aggro = 0
	boss.home = boss.pos
	boss.spec = boss.spec.duplicate() # private copy — strip its cast list so
	boss.spec["skills"] = []        # the only floater is the telegraph itself
	game.tod = 12.0 # noon — no clock-sleep swallowing the fixture
	boss.summon_t = 5.0 # the next AI tick arms the windup
	for i in 3:
		await process_frame # ~1 tick: summon_t crosses, "IT REARS UP" lands
	await _shot("windup")
	print("windup: slam_windup=%.2f" % boss.slam_windup)
	# the ring is a 2.6-tile zone — step inside it so the land is visible pain
	p.pos = boss.pos + Vector2(2.0, 0.5)
	var hp0 := int(p.hp)
	for i in 150: # ride the real 0.8s countdown — kin AI ticks are
		await process_frame # rate-limited, so the telegraph needs ~100 frames
		if boss.slam_windup <= 0.0:
			break
	for i in 4:
		await process_frame # "PACT SLAM" + hit numbers fresh on screen
	await _shot("slam")
	print("slam: player hp %d -> %d dist=%.2f windup=%.3f boss=%s aggro=%d" % [
		hp0, p.hp, boss.pos.distance_to(p.pos), boss.slam_windup,
		str(boss.pos), boss.aggro])

	# ---- frame 3: packVolley fan ----
	game.pals.erase(boss)
	boss.queue_free()
	var fl := _find_lane(8)
	var lo: Vector2 = fl[0]
	var fd: Vector2 = fl[1]
	var fan_kin: Kin = game.gen_pal("fenjelly", 25, lo)
	fan_kin.mode = "partner"
	game.pals.append(fan_kin)
	var pack: Array = []
	for j in 3:
		var w: Kin = game.gen_pal("fenlump", 10,
			game.nearest_free(lo.x + fd.x * (3.0 + j), lo.y + fd.y * (3.0 + j)))
		w.mode = "wild"
		w.hp = 9999
		game.pals.append(w)
		pack.append(w)
	p.pos = lo - fd * 2.0 # park the keeper at the lane mouth — the camera
	game.floaters.clear()  # follows him, and last scene's tags have faded
	for i in 6:
		await process_frame
	game.cast_skill(fan_kin, pack[1], SkillData.SKILLS["packVolley"])
	for i in 5:
		await process_frame # ~0.08s — the three orbs are visibly spread
	await _shot("fan")
	print("fan: shots=%d" % game.projectiles.size())

	# ---- frame 4: arcLance pierce ----
	var lane := _find_lane(8)
	var lp: Vector2 = lane[0]
	var ld: Vector2 = lane[1]
	var caster2: Kin = game.gen_pal("voltgoo", 25, lp)
	caster2.mode = "partner"
	game.pals.append(caster2)
	var l1: Kin = game.gen_pal("corlmite", 10, lp + ld * 3)
	l1.mode = "wild"
	l1.hp = 9999
	game.pals.append(l1)
	l1.statuses["sleep"] = game.t + 30.0 # pinned — a wandering target leaves
	var l2: Kin = game.gen_pal("marlump", 10, lp + ld * 6)
	l2.mode = "wild"
	l2.hp = 9999
	game.pals.append(l2)
	l2.statuses["sleep"] = game.t + 30.0 # the lane before the bolt arrives
	print("pierce lane: o=%s d=%s l1=%s l2=%s" % [str(lp), str(ld), str(l1.pos), str(l2.pos)])
	p.pos = lp - ld * 2.0
	game.floaters.clear()
	for i in 6:
		await process_frame
	game.cast_skill(caster2, l2, SkillData.SKILLS["arcLance"])
	for i in 45: # bolt at 15 t/s — leave margin for the reduced AI tick rate
		await process_frame
		for pr in game.projectiles:
			if pr.get("skill", {}).get("id") == "arcLance":
				print("lance@%d pos=%s dir=%s" % [i, str(pr["pos"]), str(pr["dir"])])
		if l1.hp < 9999 and l2.hp < 9999:
			break
	await _shot("pierce")
	print("pierce: l1=%d l2=%d shots=%d" % [l1.hp, l2.hp, game.projectiles.size()])

	# ---- frame 5: soulSiphon drain ----
	caster2.hp = 120 # wounded but sturdy — a 40hp partner dies to ambient
	caster2.max_hp = 200 # wildlife during the fade-out wait
	caster2.pos = l2.pos - ld * 1.2 # lunge range is 1.6 — park it in reach
	game.floaters.clear()
	for i in 6:
		await process_frame
	game.cast_skill(caster2, l2, SkillData.SKILLS["soulSiphon"])
	for i in 14:
		await process_frame # lunge lands, +N heal floater over the caster
	await _shot("drain")
	print("drain: caster hp=%d" % caster2.hp)

	for w in pack:
		game.pals.erase(w)
		if w.get_parent():
			w.queue_free()
	for w in [fan_kin, caster2, l1, l2]:
		game.pals.erase(w)
		if w.get_parent():
			w.queue_free()
	quit()

func _process(_dt: float) -> bool:
	return false
