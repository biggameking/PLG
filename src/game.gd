extends Node2D
class_name Game
# Root game state: world, player, pals, inventory, time, messages, floaters.
# Multiplayer-ready seams: all state lives here; sim runs deterministically.

var world := World.new()
var rng: Rng
var player: Player
var net = null
var perks := {"capture": 0, "speed": 0, "atk": 0, "hp": 0, "work": 0, "xp": 0}
var pals: Array[Pal] = []
var items := {}            # item_id -> count
var party: Array[int] = [] # pal uids
var box: Array = []        # Pal data dicts (in palbox)
var spheres_flying := []   # {sid, target, t}
var floaters := []         # {pos, text, color, t}
var messages := []
var t := 0.0               # world seconds
var day := 1
var tod := 8.0             # hour of day
var next_uid_v := 1
var raid_t := 180.0          # countdown to next base raid wave
var drops: Array = []        # ground drops {id,n,pos,node}
var _drop_tex := {}
var _light_tex: Texture2D = null

func light_tex() -> Texture2D:
	if _light_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for yy in 64:
			for xx in 64:
				var dd := Vector2(xx - 32, yy - 32).length() / 32.0
				img.set_pixel(xx, yy, Color(1, 1, 1, maxf(0.0, 1.0 - dd)))
		_light_tex = ImageTexture.create_from_image(img)
	return _light_tex

func add_glow(spr: Sprite2D, radius: int) -> void:
	var L := PointLight2D.new()
	L.texture = light_tex()
	L.texture_scale = radius * 0.8
	L.energy = 0.9
	L.color = Color(1.0, 0.78, 0.45)
	spr.add_child(L)
var structures := {}          # Vector2i -> {id, node, timer, workers:[]}
var palbox_pos := Vector2i(-1, -1)  # base anchor; -1 = no base yet
var tech_points := 0
var unlocked := ["palbox", "pal_bed", "feed_box", "campfire", "workbench", "straw_bed"]
var build_sel := -1           # index into buildable list; -1 off
var craft_target: Node2D = null
var panel := ""
var craft_station := ""
var chest_ref = null
var condense_arm := 0.0
const DAY_LEN := 240.0     # seconds per game day

@onready var entity_layer: Node2D = $YSort/Entities
@onready var drawer = $World/Terrain

func next_uid() -> int:
	next_uid_v += 1
	return next_uid_v

func _ready() -> void:
	rng = Rng.new(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)
	var spawn := world.generate(rng.int_range(1, 99999))
	drawer.setup(world)
	# player
	player = preload("res://src/player.gd").new()
	entity_layer.add_child(player)
	player.setup(self, Vector2(spawn.x + 0.5, spawn.y + 0.5))
	# starter kit
	for id in ["pal_sphere", "pal_sphere", "pal_sphere", "torch"]:
		add_item(id, 1)
	log_msg("Welcome to PLG. Press H for help.")
	spawn_wild()
	spawn_lairs()

func sphere_tiers() -> Array:
	var out := []
	for id in ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]:
		if items.get(id, 0) > 0:
			out.append(id)
	return out

func unequip_if_gone(id: String) -> void:
	if player == null:
		return
	for slot in ["weapon", "armor"]:
		if player.equipment.get(slot) == id and item_count(id) <= 0:
			player.equipment[slot] = ""
			log_msg("%s left your hands" % ItemData.ITEMS.get(id, {}).get("name", id))

func add_item(id: String, n: int) -> void:
	items[id] = items.get(id, 0) + n
	if n > 0:
		# stack cap: overflow spills to the ground instead of vanishing
		var cap: int = ItemData.ITEMS.get(id, {}).get("stack", 999)
		if items[id] > cap:
			var spill: int = items[id] - cap
			items[id] = cap
			if player != null:
				spawn_drop(id, spill, player.pos)
				drops.back()["cool"] = 3.0 # don't vacuum it straight back up
				log_msg("Bag full - %s x%d dropped" % [ItemData.ITEMS[id].get("name", id), spill])
			else:
				items[id] += spill # pre-player init: keep the overflow
	if items[id] <= 0:
		items.erase(id)
	unequip_if_gone(id)

func item_count(id: String) -> int:
	return items.get(id, 0)

func log_msg(msg: String) -> void:
	messages.push_back(msg)
	if messages.size() > 6:
		messages.pop_front()

func floater(pos: Vector2, text: String, color: String) -> void:
	floaters.push_back({"p": pos, "t": text, "c": color, "age": 0.0})

# ---------- wild pals ----------
const ZONE_SPECIES := {
	0: ["lamball", "chikipi", "lifmunk", "cattiva", "tanzee"],
	1: ["foxparks", "jolthog", "fuack", "pengullet", "cremis", "sparkit", "mau"],
	2: ["rushoar", "eikthyrdeer", "mozzarina", "depresso", "daedream"],
	3: ["dumud", "penking", "daedream"],
}

func spawn_wild() -> void:
	var want := 42
	var tries := 0
	var wild_n := 0
	for wp in pals:
		if wp.mode == "wild":
			wild_n += 1
	while wild_n < want and tries < 4000:
		tries += 1
		var x := rng.int_range(4, World.WORLD_W - 5)
		var y := rng.int_range(4, World.WORLD_H - 5)
		if world.blocked(x, y):
			continue
		if player.pos.distance_squared_to(Vector2(x, y)) < 64.0:
			continue # don't pop a pal into existence on top of the player
		var zone := world.zone_at(x, y)
		var pool: Array = ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var sp: Dictionary = SpeciesData.species_of(sid)
		var lv := rng.int_range(1 + zone * 3, 4 + zone * 5)
		var p := preload("res://src/pal.gd").new()
		p.alpha = zone >= 2 and rng.chance(0.08)
		entity_layer.add_child(p)
		p.setup(self, sid, lv + (6 if p.alpha else 0), Vector2(x + 0.5, y + 0.5))
		p.home = p.pos # lair anchor — alphas tether here
		pals.append(p)
		wild_n += 1

func find_pal(uid: int) -> Pal:
	for p in pals:
		if p.uid == uid:
			return p
	return null

func party_pal() -> Pal:
	for uid in party:
		var p := find_pal(uid)
		if p:
			return p
	return null

func kill_pal(p: Pal, by_player: bool) -> void:
	player.dismount_if(p)
	# drops
	var mult := 4 if p.alpha else 1
	if p.boss:
		add_item("legendary_sphere", 1)
		add_item("lifmunk_effigy", 3)
		add_item("gold_coin", 10)
		log_msg("RAID CLEARED! Legendary sphere + loot!")
	for d in p.spec.get("drops", []):
		spawn_drop(d[0], rng.int_range(d[1], d[2]) * mult, p.pos)
	if p.alpha:
		add_item("pal_sphere", 1)
		log_msg("Alpha %s down! Bonus sphere." % p.spec["name"])
		add_item("lifmunk_effigy", 2)
	if p.carry != null: # a hauler's load doesn't die with it
		spawn_drop(p.carry["id"], p.carry["n"], p.pos)
		p.carry = null
	pals.erase(p)
	party.erase(p.uid)  # dead partners must free their party slot
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null # no lingering worker SAN drain or base_ai pull
	if p.mode in ["partner", "base"]: # owned pals are knocked out, not deleted
		p.mode = "box"
		p.revive_t = t + 300.0  # Palworld-style revive timer
		box.append(p)
		entity_layer.remove_child(p)
		log_msg("%s is KO'd - it will recover in the box" % p.spec["name"])
	else:
		p.queue_free()
	gain_xp(p.level * 4)

func hurt_player(atk: float, from: Pal) -> void:
	if player.dodge_t > 0:
		return
	var def := 20.0 + player.level * 3.0
	var d := maxi(1, int(round(25.0 * (2.0 * atk) / maxf(1.0, atk + 2.0 * def) * (0.9 + rng.next() * 0.2))))
	var final := maxi(1, d - player.armor_def())
	player.hp -= final
	player.hit_flash = 0.4
	floater(player.pos, "-" + str(final), "#e64533")
	if player.hp <= 0:
		respawn_player()

func sphere_fly(sid: String, target: Pal) -> void:
	var spr := Sprite2D.new()
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var c := Color(ItemData.ITEMS.get(sid, {}).get("col", "#e05050"))
	img.fill(Color(0, 0, 0, 0))
	for yy in range(2, 8):
		for xx in range(2, 8):
			img.set_pixel(xx, yy, c)
	for xx in range(3, 7):
		img.set_pixel(xx, 2, Color.WHITE) # top glint
	spr.texture = ImageTexture.create_from_image(img)
	var p0 := Iso.to_screen(player.pos.x, player.pos.y, world.elev_at(int(player.pos.x), int(player.pos.y)))
	spr.position = Vector2(p0.x, p0.y - 14)
	entity_layer.add_child(spr)
	spheres_flying.append({"sid": sid, "target": target, "t": 0.0,
		"node": spr, "from": player.pos})

func generator_active() -> bool:
	for kg in structures:
		var sg = structures[kg]
		if sg.get("id") == "generator" and not sg["workers"].is_empty():
			return true
	return false

func chest_deposit_all(st) -> int:
	var n := 0
	if not st.has("store"):
		st["store"] = {}
	var skipped := 0
	for iid in items.keys():
		if iid in ["gold_coin"]:
			continue
		var c: int = items[iid]
		if c > 0:
			if not chest_can_take(st, iid):
				skipped += c
				continue
			st["store"][iid] = st["store"].get(iid, 0) + c
			n += c
			items.erase(iid)
			unequip_if_gone(iid)
	if skipped > 0:
		log_msg("Chest full - %d item(s) kept in bag" % skipped)
	return n

func chest_withdraw_all(st) -> int:
	var n := 0
	for iid in st.get("store", {}).keys():
		add_item(iid, st["store"][iid])
		n += st["store"][iid]
	st["store"] = {}
	return n

func respawn_player() -> void:
	# Palworld rule: your pack spills where you fell; walk back to reclaim
	var dropped := 0
	for id in items.keys():
		if items[id] > 0:
			var a := rng.next() * TAU
			spawn_drop(id, items[id], player.pos + Vector2(cos(a), sin(a)) * (0.4 + rng.next() * 0.8))
			dropped += items[id]
			items.erase(id) # don't leave ghost "x0" rows in the bag
			unequip_if_gone(id)
	if dropped > 0:
		log_msg("You dropped %d items where you fell!" % dropped)
	if player.mount != null: # dead men don't ride
		player.mount.visible = true
		player.mount = null
	player.hp = int(player.max_hp * 0.5)
	player.hunger = 40.0
	player.statuses.clear()
	if palbox_pos.x >= 0:
		player.pos = nearest_free(palbox_pos.x + 0.5, palbox_pos.y + 2.5)
	else: # no base yet: back to the landing point, not back into the jaws
		player.pos = nearest_free(world.spawn.x + 0.5, world.spawn.y + 0.5)
	log_msg("You wake up battered at base…")

func is_night() -> bool:
	return tod >= 21.0 or tod < 5.0

func sleep_to_morning() -> void:
	for q in pals:
		if q.hp > 0 and (q.raid or (q.mode == "wild" and q.aggro >= 0)):
			log_msg("Can't sleep - hostiles are after you!")
			return
	day += 1
	tod = 6.0
	player.hp = player.max_hp
	for q in pals:
		if q.mode == "base" or q.mode == "partner":
			q.hp = q.max_hp
			q.san = 100.0
			q.hunger = 0.0
	log_msg("You sleep until dawn. Day %d" % day)

func summon_raid() -> bool:
	if palbox_pos.x < 0:
		log_msg("Need a palbox to summon the raid")
		return false
	var pool: Array = SpeciesGen.zone_pool(3)
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	var bp := preload("res://src/pal.gd").new()
	bp.alpha = true
	bp.boss = true # set before setup so apply_bonuses folds the 2x in once
	entity_layer.add_child(bp)
	bp.setup(self, sid, 45, nearest_free(palbox_pos.x + 2.5, palbox_pos.y + 2.5))
	bp.sprite.scale = Vector2(2.2, 2.2)
	bp.sprite.position.y = -70.0
	bp.aggro = 0  # player
	bp.raid = true
	bp.set_meta("raid_t0", t)
	pals.append(bp)
	log_msg("RAID BOSS: %s Lv45 approaches your base!" % bp.spec["name"])
	return true

func resolve_sphere(sp) -> void:
	var target: Pal = sp["target"]
	if not is_instance_valid(target) or target.hp <= 0 or target.mode != "wild":
		return # dead, freed, or already caught by another sphere in flight
	if target.boss:
		floater(target.pos, "IMMUNE", "#e8452f")
		return
	var behind: float = sign(player.pos.x - target.pos.x) == -target.dir
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var chance: float = minf(0.97, Combat.catch_chance(hp_frac, target.spec["capturePower"],
		ItemData.ITEMS[sp["sid"]].get("spherePower", 26), target.any_status(), behind, player.capture_level) * (1.0 + perks["capture"] * 0.05))
	if randf() < chance:
		floater(target.pos, "★ CAUGHT!", "#4dd0e1")
		log_msg("Caught %s Lv%d!" % [target.spec["name"], target.level])
		gain_xp(target.level * 3)
		target.mode = "box"
		target.statuses.clear()
		target.aggro = -1
		box.append(target)
		pals.erase(target)
		entity_layer.remove_child(target)
	else:
		floater(target.pos, "…broke free", "#e8963c")
		log_msg("%s broke free (%d%%)" % [target.spec["name"], int(chance * 100)])
		target.aggro = 0 if target.hostile() >= 1 else -1

func try_harvest(at: Vector2, face: Vector2) -> void:
	# hit the decor tile on the dominant axis the player faces (was x-only)
	var tx := int(at.x); var ty := int(at.y)
	if absf(face.x) >= absf(face.y):
		tx += int(signf(face.x))
	else:
		ty += int(signf(face.y))
	var d := world.decor_at(tx, ty)
	if d == World.Decor.NONE:
		return
	var i := world.idx(tx, ty)
	world.hp[i] = max(0, world.hp[i] - 10)
	floater(Vector2(tx + 0.5, ty + 0.5), "thwack", "#c8d3d5")
	if world.hp[i] == 0:
		var loot: String = {World.Decor.TREE_A: "wood", World.Decor.TREE_B: "wood",
			World.Decor.ROCK: "stone", World.Decor.ORE_GOLD: "ore",
			World.Decor.ORE_COAL: "coal", World.Decor.BERRY: "red_berries",
			World.Decor.STUMP: "wood"}[d]
		var n: int = 1 if d == World.Decor.BERRY else rng.int_range(1, 3)
		spawn_drop(loot, n, Vector2(tx + 0.5, ty + 0.5))
		world.decor[i] = World.Decor.STUMP if (d == World.Decor.TREE_A or d == World.Decor.TREE_B) else World.Decor.NONE
		world.hp[i] = 0
		queue_redraw_decor()

func spawn_drop(id: String, n: int, at: Vector2) -> void:
	# tiny tinted bag icon; drops persist until picked up (player or hauler pal)
	if not _drop_tex.has(id):
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		var c := Color(ItemData.ITEMS.get(id, {}).get("col", "#c8b070"))
		img.fill(c.darkened(0.35))
		for yy in range(2, 8):
			for xx in range(2, 8):
				img.set_pixel(xx, yy, c)
		_drop_tex[id] = ImageTexture.create_from_image(img)
	var spr := Sprite2D.new()
	spr.texture = _drop_tex[id]
	var p := Iso.to_screen(at.x, at.y, world.elev_at(int(at.x), int(at.y)))
	spr.position = Vector2(p.x, p.y - 2)
	entity_layer.add_child(spr)
	drops.append({"id": id, "n": n, "pos": at, "node": spr, "cool": 0.0, "age": 0.0})

func take_drop(d: Dictionary) -> void:
	drops.erase(d)
	if is_instance_valid(d["node"]):
		d["node"].queue_free()

# condense costs: star 0->1 needs 4 fodder, then 16/32/64 (Palworld ladder)
const CONDENSE_COST := [4, 16, 32, 64]

func condense_active() -> void:
	if party.is_empty():
		log_msg("No active pal to condense")
		return
	var ap0: Pal = find_pal(party[0])
	if ap0 != null and ap0.star < CONDENSE_COST.size():
		var need0: int = CONDENSE_COST[ap0.star]
		var have0 := 0
		for bp0 in box:
			if bp0.species_id == ap0.species_id:
				have0 += 1
		if have0 >= need0:
			if t > condense_arm: # first E previews; second E within 4s commits
				condense_arm = t + 4.0
				log_msg("Press E again to consume %d %s -> star %d" % [need0, ap0.spec["name"], ap0.star + 1])
				return
			condense_arm = 0.0
	var ap: Pal = find_pal(party[0])
	if ap == null:
		return
	if ap.star >= CONDENSE_COST.size():
		log_msg("%s is already max star" % ap.spec["name"])
		return
	var need: int = CONDENSE_COST[ap.star]
	# fodder = same-species pals in the box (weakest first, active excluded)
	var fodder: Array = []
	for bp in box:
		if bp.species_id == ap.species_id and bp.uid != ap.uid:
			fodder.append(bp)
	fodder.sort_custom(func(a, b): return a.level < b.level)
	if fodder.size() < need:
		log_msg("Need %d same-species pals for star %d (have %d)" % [need, ap.star + 1, fodder.size()])
		return
	for i in need:
		var fp: Pal = fodder[i]
		box.erase(fp)
		fp.free() # box pals aren't in the scene tree — free() not queue_free()
	ap.condense()
	log_msg("%s condensed to star %d!" % [ap.spec["name"], ap.star])

func eat_food_item() -> int:
	# feed-box rule: pals eat the cheapest stored food — feed_box store
	# first, then any chest's store (never the player's bag remotely)
	var best = null; var best_id := ""; var best_v := 1 << 30
	var stores := []
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] in ["feed_box", "chest"] and not st.get("store", {}).is_empty():
			stores.append(st)
	for st2 in stores:
		for id in st2["store"].keys():
			var it: Dictionary = ItemData.ITEMS.get(id, {})
			var fv: int = it.get("food", 0)
			if fv > 0 and st2["store"][id] > 0 and fv < best_v:
				best_v = fv; best_id = id; best = st2
	if best == null:
		return 0
	best["store"][best_id] -= 1
	if best["store"][best_id] <= 0:
		best["store"].erase(best_id)
	return best_v

func eat_from_bag() -> int:
	# party pals eat straight from the player's inventory (Palworld rule)
	var best_id := ""; var best_v := 1 << 30
	for id in items.keys():
		var it: Dictionary = ItemData.ITEMS.get(id, {})
		var fv: int = it.get("food", 0)
		if fv > 0 and items[id] > 0 and fv < best_v:
			best_v = fv; best_id = id
	if best_id == "":
		return 0
	add_item(best_id, -1)
	return best_v

func chest_can_take(st: Dictionary, id: String) -> bool:
	var store: Dictionary = st.get("store", {})
	if store.has(id):
		return true
	var cap: int = StructureData.STRUCTURES.get(st["id"], {}).get("storage", 12)
	return store.size() < cap # N distinct stacks per chest

func nearest_chest_cell(at: Vector2, id: String = "") -> Vector2i:
	# food prefers the feed box; a full feed box falls back to chests
	var kinds := ["chest"]
	if id != "" and ItemData.ITEMS.get(id, {}).get("food", 0) > 0 and has_structure("feed_box"):
		kinds = ["feed_box", "chest"]
	for kind in kinds:
		var best := Vector2i(-1, -1); var bd := 1e9
		for k in structures:
			var st: Dictionary = structures[k]
			if st["id"] != kind:
				continue
			if id != "" and not chest_can_take(st, id):
				continue
			var dd := at.distance_squared_to(Vector2(k.x, k.y))
			if dd < bd:
				bd = dd; best = k
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

signal decor_dirty
func queue_redraw_decor() -> void:
	decor_dirty.emit()

var starve_acc := 0.0
func _process(dt: float) -> void:
	t += dt
	tod += dt / DAY_LEN * 24.0
	if tod >= 24.0:
		tod -= 24.0
		day += 1
	# hunger actually burns — ~100 to 0 over ~8 real minutes
	player.hunger = maxf(0.0, player.hunger - dt * 0.2)
	if player.hunger <= 0.0:
		starve_acc += dt
		if starve_acc > 3.0: # starving ticks 1hp every 3s — can kill
			starve_acc = 0.0
			player.hp -= 1
			floater(player.pos, "starving", "#e0503c")
			if player.hp <= 0:
				respawn_player()
	else:
		starve_acc = 0.0
	# spheres
	for sp in spheres_flying.duplicate():
		sp["t"] += dt
		var tg: Pal = sp["target"]
		if is_instance_valid(tg):
			var f: float = minf(1.0, sp["t"] / 0.45)
			var tp: Vector2 = tg.pos
			var fp: Vector2 = sp["from"]
			var cur: Vector2 = fp + (tp - fp) * f
			var arc: float = sin(f * PI) * 24.0 # lobbed arc
			var pp := Iso.to_screen(cur.x, cur.y, world.elev_at(int(cur.x), int(cur.y)))
			sp["node"].position = Vector2(pp.x, pp.y - 14 - arc)
		if sp["t"] > 0.45:
			if is_instance_valid(sp["node"]):
				sp["node"].queue_free()
			resolve_sphere(sp)
			spheres_flying.erase(sp)
	tick_production(dt)
	update_projectiles(dt)
	for bp in box: # knocked-out pals recover on a timer
		if bp.revive_t > 0 and t > bp.revive_t:
			bp.revive_t = 0
			bp.hp = int(bp.max_hp * 0.3)
			log_msg("%s has recovered" % bp.spec["name"])
	# floaters age
	for f in floaters:
		f["age"] += dt
	floaters = floaters.filter(func(f): return f["age"] < 1.2)
	# ground-drop pickup on walk-over
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d["age"] = d.get("age", 0.0) + dt
		if d["age"] > 600.0: # old loot decays — else the world fills with bags
			take_drop(d)
			continue
		if d["cool"] > 0.0:
			d["cool"] = d["cool"] - dt
			continue
		if player.pos.distance_squared_to(d["pos"]) < 0.55:
			add_item(d["id"], d["n"])
			floater(d["pos"], "+%d %s" % [d["n"], ItemData.ITEMS.get(d["id"], {}).get("name", d["id"])], "#ffe08a")
			take_drop(d)
	# respawn trickle
	var wild_n := 0
	for wp in pals:
		if wp.mode == "wild":
			wild_n += 1
	if wild_n < 30 and rng.chance(dt * 0.15):
		spawn_wild()
	# stumps regrow into trees over a few in-game days
	if rng.chance(dt * 0.02):
		var ri := rng.int_range(0, world.decor.size() - 1)
		if world.decor[ri] == World.Decor.STUMP:
			world.decor[ri] = World.Decor.TREE_A if rng.chance(0.5) else World.Decor.TREE_B
			world.hp[ri] = 30
			queue_redraw_decor()
	# base raid waves
	if palbox_pos.x >= 0:
		raid_t -= dt
		if raid_t <= 0:
			raid_t = 240.0 + rng.next() * 180.0
			start_raid()
		for q in pals.duplicate(): # stale raiders wander off instead of stacking up
			if q.mode == "wild" and q.raid and not q.boss and t - q.get_meta("raid_t0", t) > 240.0:
				pals.erase(q)
				q.queue_free()

# ---------- building / tech / crafting / base ----------

func buildable_list() -> Array:
	# only tech nodes that are actual structures — spear/sphere/axe techs
	# unlock recipes, not buildings (selecting them crashed place_structure)
	return unlocked.filter(func(id): return StructureData.STRUCTURES.has(id))

func can_place(sid: String, tx: int, ty: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty():
		return false
	var w: int = s.get("w", 2)
	var h: int = s.get("h", 2)
	if not world.flat_at(tx, ty, w, h):
		return false
	for dy in range(h):
		for dx in range(w):
			if world.blocked(tx + dx, ty + dy):
				return false
			if structures.has(Vector2i(tx + dx, ty + dy)):
				return false
	return true

func place_structure(sid: String, tx: int, ty: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES[sid]
	if sid == "palbox" and has_structure("palbox"):
		log_msg("You can only run one base")  # palbox_pos is a single anchor
		return false
	for c in s.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg("Need %d %s" % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])])
			return false
	var e0: int = world.elev_at(tx, ty)
	for dy0 in range(s.get("h", 2)):
		for dx0 in range(s.get("w", 2)):
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				log_msg("Blocked: something already built there")
				return false
			if world.tile_at(tx + dx0, ty + dy0) == World.Tile.WATER:
				log_msg("Can't build on water")
				return false
			if world.elev_at(tx + dx0, ty + dy0) != e0:
				log_msg("Can't build across a ledge")
				return false
	for c in s.get("cost", []):
		add_item(c[0], -c[1])
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/structures/%s.png" % sid)
	var w: int = s.get("w", 2)
	var h: int = s.get("h", 2)
	var p := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
	spr.position = Vector2(p.x, p.y - spr.texture.get_height() * 0.5 + 8)
	entity_layer.add_child(spr)
	if s.get("light", 0) > 0:
		add_glow(spr, s["light"])
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {}}
	for dy in range(h):
		for dx in range(w):
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[world.idx(tx + dx, ty + dy)] = st
	if sid == "palbox":
		palbox_pos = Vector2i(tx, ty)
		log_msg("Base established! Assign pals with F.")
	log_msg("Built %s" % s["name"])
	return true

func place_free(sid: String, tx: int, ty: int) -> bool:
	# Cost-free placement used by net state_sync and world-gen lair markers.
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty():
		return false
	var w: int = s.get("w", 2); var h: int = s.get("h", 2)
	for dy0 in range(h):
		for dx0 in range(w):
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				return false
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/structures/%s.png" % sid)
	var p := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
	spr.position = Vector2(p.x, p.y - spr.texture.get_height() * 0.5 + 8)
	entity_layer.add_child(spr)
	if s.get("light", 0) > 0:
		add_glow(spr, s["light"])
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {}}
	for dy in range(h):
		for dx in range(w):
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[world.idx(tx + dx, ty + dy)] = st
	if sid == "palbox":
		palbox_pos = Vector2i(tx, ty)
	return true

# X-key demolish: removes the structure under a tile, refunds half cost,
# returns chest contents, unassigns workers.
func demolish_at(at: Vector2) -> bool:
	var st = structure_at(at)
	if not st:
		log_msg("Nothing to demolish")
		return false
	var sid: String = st["id"]
	var cells := []
	for k in structures:
		if structures[k] == st:
			cells.append(k)
	for w in st["workers"].duplicate():
		st["workers"].erase(w)
		w.job_site = null
	for it in st.get("store", {}).keys():
		add_item(it, st["store"][it])
	for c in StructureData.STRUCTURES[sid].get("cost", []):
		add_item(c[0], int(ceil(c[1] * 0.5)))
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	st["node"].queue_free()
	if sid == "palbox":
		palbox_pos = Vector2i(-1, -1)
	log_msg("Demolished %s (50%% refund)" % StructureData.STRUCTURES[sid]["name"])
	return true

func tech_node(sid: String) -> Dictionary:
	for t in StructureData.TECH:
		if t["id"] == sid:
			return t
	return {}

func unlock(sid: String) -> void:
	if sid in unlocked:
		return
	var t := tech_node(sid)
	if t.is_empty():
		return
	if player.level < t.get("tier", 0):
		log_msg("Reach Lv%d to unlock %s" % [t.get("tier", 0), t.get("name", sid)])
		return
	if tech_points < t.get("cost", 0):
		log_msg("Need %d tech points" % t.get("cost", 0))
		return
	tech_points -= t.get("cost", 0)
	unlocked.append(sid)
	log_msg("Unlocked %s" % t.get("name", sid))

func recipe(rid: String) -> Dictionary:
	for r in ItemData.RECIPES:
		if r["id"] == rid:
			return r
	return {}

func craft(recipe_id: String) -> void:
	var r := recipe(recipe_id)
	if r.is_empty():
		return
	# station-gated recipes require standing at the station
	var stn: String = r.get("station", "hand")
	if stn != "hand":
		var near := false
		for k in structures:
			if structures[k]["id"] == stn and player.pos.distance_to(Vector2(k.x + 0.5, k.y + 0.5)) < 4.0:
				near = true
				break
		if not near:
			log_msg("Need to be at a %s" % stn)
			return
	if r.get("tech", "") != "" and r["tech"] not in unlocked:
		log_msg("Unlock %s in the tech tree first" % r["tech"])
		return
	for c in r.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg("Missing materials")
			return
	for c in r.get("cost", []):
		add_item(c[0], -c[1])
	add_item(r["out"][0], r["out"][1])
	log_msg("Crafted %s x%d" % [ItemData.ITEMS[r["out"][0]]["name"], r["out"][1]])

func gain_xp(n: int) -> void:
	n = int(n * (1.0 + perks["xp"] * 0.08))
	for q in pals:
		if q.mode == "partner" and q.hp > 0:
			q.xp += int(n * 0.5)
			while q.xp >= q.level * 25:
				q.xp -= q.level * 25
				q.level += 1
				q.apply_bonuses() # recompute max_hp incl star/alpha/boss
				q.hp = q.max_hp
				log_msg("%s grew to Lv%d!" % [q.spec["name"], q.level])
	player.xp += n
	while true: # a big kill can cross several levels
		var need := 30 + player.level * 20
		if player.xp < need:
			break
		player.xp -= need
		player.level += 1
		player.max_hp += 10
		player.hp = player.max_hp
		tech_points += 2
		log_msg("Level up! Lv%d (+2 tech pts)" % player.level)

func tick_production(dt: float) -> void:
	for key in structures:
		var st = structures[key]
		if key != cell_of(st):
			continue # tick once per structure
		var s: Dictionary = StructureData.STRUCTURES.get(st["id"], {})
		var job: Dictionary = s.get("job", {})
		var seen := []
		for w in st["workers"].duplicate(): # hygiene first — every site incl. ranch: dedupe + drop stale refs
			if not is_instance_valid(w) or w.job_site != st or w.mode != "base" or w in seen:
				st["workers"].erase(w)
			else:
				seen.append(w)
		if st["id"] == "ranch":
			tick_ranch(key, st, dt)
			continue
		var prod: Array = job.get("produces", [])
		var active: Array = st["workers"].filter(func(w): return w.san >= 15.0)
		if prod.is_empty() or active.is_empty():
			continue
		var cons: Array = job.get("consumes", [])
		if not cons.is_empty() and not consume_ready(cons):
			continue # starved for inputs — no free production
		var powered := 1.0
		for kg in structures:
			var sg = structures[kg]
			if sg.get("id") == "generator" and not sg["workers"].is_empty():
				powered = 1.5
		var work_sum := 0.0 # each worker contributes by its Artisan/etc passives
		for w in active:
			work_sum += w.passive_mult("work")
		st["timer"] += (dt * (1.0 + perks["work"] * 0.1)) * powered * work_sum
		var rate: float = job.get("amount", 30)
		if st["timer"] >= rate:
			st["timer"] -= rate
			for cn in cons: # inputs come out of the base's storage network
				var need: int = cn[1]
				for kc in structures:
					var sc: Dictionary = structures[kc]
					if sc["id"] not in ["chest", "feed_box"] or need <= 0:
						continue
					var take: int = mini(need, sc["store"].get(cn[0], 0))
					if take > 0:
						sc["store"][cn[0]] -= take
						if sc["store"][cn[0]] <= 0:
							sc["store"].erase(cn[0])
						need -= take
			for pr in prod: # goods pile up at the site; haulers move them
				st["store"][pr[0]] = st["store"].get(pr[0], 0) + pr[1]
			var t := ""
			for pr in prod:
				t += "+%d %s  " % [pr[1], pr[0]]
			floaters.push_back({"p": Vector2(key.x + 0.5, key.y + 0.5), "t": t.strip_edges(), "c": "#a8e6a1", "age": 0.0})

func consume_ready(cons: Array) -> bool:
	for cn in cons:
		var have := 0
		for kc in structures:
			var sc: Dictionary = structures[kc]
			if sc["id"] in ["chest", "feed_box"]: # haulers stock food in the feed box — inputs count it too
				have += sc["store"].get(cn[0], 0)
		if have < cn[1]:
			return false
	return true

func nearest_free(x: float, y: float) -> Vector2:
	# spiral out from a desired spot until a walkable cell turns up
	var c := Vector2i(int(x), int(y))
	if not world.blocked(c.x, c.y):
		return Vector2(c.x + 0.5, c.y + 0.5)
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue # ring cells only
				if not world.blocked(c.x + dx, c.y + dy):
					return Vector2(c.x + dx + 0.5, c.y + dy + 0.5)
	return Vector2(x, y) # give up: original spot

func cell_of(st) -> Vector2i:
	for k in structures:
		if structures[k] == st:
			return k
	return Vector2i(-1, -1)

func structure_at(tw: Vector2):
	var st = structures.get(Vector2i(int(tw.x), int(tw.y)))
	if st:
		return st
	# try the 8 neighbors for multi-cell footprints
	for dy in range(-2, 1):
		for dx in range(-2, 1):
			st = structures.get(Vector2i(int(tw.x) + dx, int(tw.y) + dy))
			if st:
				return st
	return null

func has_structure(sid: String) -> bool:
	for k in structures:
		if structures[k]["id"] == sid:
			return true
	return false

func base_pals() -> Array:
	return pals.filter(func(p): return p.mode == "base")

func box_to_party(bp: Pal) -> void:
	if bp.hp <= 0:
		log_msg("%s is KO'd - wait for it to recover" % bp.spec["name"])
		return
	if party.size() >= 5:
		log_msg("Party full (5) - send someone to the box first")
		return
	box.erase(bp)
	pals.append(bp)
	bp.mode = "partner"
	party.append(bp.uid)
	var spawn_p := player.pos + Vector2(1.2, 0)
	bp.pos = spawn_p
	entity_layer.add_child(bp)
	log_msg("%s joined %s" % [bp.spec["name"], bp.mode])

func party_to_box(uid: int) -> void:
	var mp := find_pal(uid)
	if mp:
		player.dismount_if(mp)
	var p := find_pal(uid)
	if not p:
		return
	party.erase(uid)
	pals.erase(p)
	if p.job_site: # leaving for the box drops the job too
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null
	p.mode = "box"
	if p.carry != null: # hauling cargo doesn't vanish into the box
		add_item(p.carry["id"], p.carry["n"])
		log_msg("%s dropped off %d %s" % [p.spec["name"], p.carry["n"], p.carry["id"]])
		p.carry = null
	box.append(p)
	entity_layer.remove_child(p)
	log_msg("%s -> box" % p.spec["name"])

func assign_worker() -> void:
	# toggle nearest base pal between wander and assigned to nearest workplace
	var best: Pal = null
	var bd := 3.0
	for p in base_pals():
		var d := player.pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	if not best:
		log_msg("No base pal nearby")
		return
	if best.job_site != null:
		best.job_site["workers"].erase(best)
		best.job_site = null
		log_msg("%s unassigned" % best.spec["name"])
		return
	var site = null
	var sd := 6.0
	for k in structures:
		var s: Dictionary = StructureData.STRUCTURES.get(structures[k]["id"], {})
		var jb: Dictionary = s.get("job", {})
		if jb.get("produces") == null and structures[k]["id"] != "ranch" and jb.get("kind") != "power":
			continue # sites with no output aren't assignable (except generator/ranch)
		var need: String = jb.get("workType", "")
		if need != "" and best.spec.get("work", {}).get(need, 0) == 0:
			continue  # this pal can't work this site — keep looking
		var d := best.pos.distance_to(Vector2(k.x, k.y))
		if d < sd:
			sd = d
			site = structures[k]
	if site:
		if best not in site["workers"]:
			site["workers"].append(best) # idempotent — a stale entry must not duplicate
		best.job_site = site
		log_msg("%s -> %s" % [best.spec["name"], StructureData.STRUCTURES[site["id"]]["name"]])
	else:
		log_msg("No workplace nearby")

# ---------- skills / projectiles / statuses ----------
const ELEM_ORB_IDX := {"neutral": 0, "fire": 1, "water": 2, "grass": 3, "electric": 4,
	"ice": 5, "ground": 6, "dark": 7, "dragon": 8}
var projectiles := []
var orb_tex: Texture2D = preload("res://assets/ui/element_orbs.png")

func cast_skill(caster: Pal, target_ent, sk: Dictionary) -> void:
	var kind: String = sk.get("kind", "projectile")
	var elem: String = sk.get("element", "neutral")
	var tpos: Vector2 = target_ent if target_ent is Vector2 else target_ent.pos
	match kind:
		"self":
			var heal := caster.max_hp * absf(sk.get("power", 20)) / 100.0
			caster.hp = minf(caster.max_hp, caster.hp + heal)
			floater(caster.pos, "+%d %s" % [int(heal), sk["name"]], "#a8e6a1")
		"lunge":
			var land: Vector2 = tpos + (caster.pos - tpos).normalized() * 0.9
			if not world.blocked(int(land.x), int(land.y)):
				caster.pos = land # don't lunge into water/cliffs
			skill_hit(caster, target_ent, sk)
		"burst":
			var radius: float = sk.get("range", 4)
			if caster.mode == "wild":
				if caster.pos.distance_to(player.pos) <= radius:
					skill_hit(caster, player, sk)
				for p in pals.duplicate():
					if p.mode in ["partner", "base"] and p.hp > 0 and caster.pos.distance_to(p.pos) <= radius:
						skill_hit(caster, p, sk)
			else:
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and caster.pos.distance_to(p.pos) <= radius:
						skill_hit(caster, p, sk)
			floater(caster.pos, sk["name"] + "!", "#ffd76e")
		_: # projectile
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = orb_tex
			at.region = Rect2(ELEM_ORB_IDX.get(elem, 0) * 16, 0, 16, 16)
			at.filter_clip = true
			spr.texture = at
			spr.scale = Vector2(1.5, 1.5)
			entity_layer.add_child(spr)
			projectiles.append({
				"elev": world.elev_at(int(caster.pos.x), int(caster.pos.y)),
				"pos": caster.pos, "dir": (tpos - caster.pos).normalized(),
				"speed": sk.get("projectileSpeed", 12), "ttl": sk.get("range", 8) / maxf(1.0, sk.get("projectileSpeed", 12)),
				"skill": sk, "from": caster, "node": spr,
			})

func skill_hit(caster: Pal, target_ent, sk: Dictionary) -> void:
	var elem: String = sk.get("element", "neutral")
	if target_ent is Player:
		if player.dodge_t > 0:
			return
		player.hp -= maxi(1, int(sk.get("power", 10) * 0.6) - player.armor_def())
		player.hit_flash = 0.4
		floater(player.pos, "-" + str(int(sk.get("power", 10) * 0.6)), "#e64533")
		var st = sk.get("status")
		if st and rng.chance(st.get("chance", 1.0)):
			player_status(st["kind"], st.get("dur", 3))
		if player.hp <= 0:
			respawn_player()
	else:
		var tp: Pal = target_ent
		var mult := Combat.effectiveness(elem, tp.elem())
		if tp.has_status("soak") and elem == "electric":
			mult *= 1.5
		var d := Combat.damage(Combat.stat_at(caster.spec["atk"], caster.level, caster.talent) * caster.atk_bonus,
			sk.get("power", 10), Combat.stat_at(tp.spec["def"], tp.level, tp.talent) * tp.def_bonus, mult, rng)
		tp.hit(d, mult, caster.mode != "wild")
		tp.apply_skill_status(sk)
		if caster.mode == "partner":
			gain_xp(maxi(1, d / 4))

func update_projectiles(dt: float) -> void:
	for pr in projectiles.duplicate():
		pr["ttl"] -= dt
		pr["pos"] += pr["dir"] * pr["speed"] * dt
		var pp: Vector2 = pr["pos"]
		var n: Sprite2D = pr["node"]
		n.position = Iso.to_screen(pp.x, pp.y, world.elev_at(int(pp.x), int(pp.y))) - Vector2(0, 20)
		var dead: bool = pr["ttl"] <= 0
		# terrain hit: cliff faces above launch height, trees/rocks/buildings
		if not dead:
			var cx: int = int(pp.x); var cy: int = int(pp.y)
			if not world.in_bounds(cx, cy):
				dead = true
			else:
				var ci: int = world.idx(cx, cy)
				var wall: bool = world.elev_at(cx, cy) > pr.get("elev", 0)
				if not wall:
					wall = world.decor[ci] != World.Decor.NONE or world.structures.has(ci)
				if wall:
					dead = true
		if pr["from"] is String and pr["from"] == "player":
			if not dead:
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and pp.distance_to(p.pos) < 0.6:
						var mult := Combat.effectiveness("neutral", p.elem())
						var d := Combat.damage(pr["dmg"] * 2.0, 20, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus, mult, rng)
						p.hit(d, mult, true)
						dead = true
						break
			if dead:
				n.queue_free()
				projectiles.erase(pr)
			continue
		var caster: Pal = pr["from"]
		if not dead:
			if caster.mode == "wild":
				if pp.distance_to(player.pos) < 0.55:
					skill_hit(caster, player, pr["skill"])
					dead = true
				else:
					for p in pals.duplicate():
						if p.mode in ["partner", "base"] and p.hp > 0 and pp.distance_to(p.pos) < 0.6:
							skill_hit(caster, p, pr["skill"]) # wild shots hit partners AND base workers
							dead = true
							break
			else:
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and pp.distance_to(p.pos) < 0.6:
						skill_hit(caster, p, pr["skill"])
						dead = true
						break
		if dead:
			n.queue_free()
			projectiles.erase(pr)

func player_status(kind: String, dur: float) -> void:
	player.statuses[kind] = t + dur
	floater(player.pos, kind.to_upper(), "#e8963c")

# ---------- save / load ----------
func save_game() -> void:
	var pals_data := []
	for p in pals:
		var jc = null
		if p.mode == "base": # only base pals hold jobs; anything else in workers is stale
			for kj in structures:
				if p in structures[kj]["workers"]:
					jc = "%d,%d" % [kj.x, kj.y]
					break
		pals_data.append({"sp": p.species_id, "lv": p.level, "pos": [p.pos.x, p.pos.y],
			"mode": p.mode, "hp": p.hp, "talent": p.talent, "sex": p.sex,
			"passives": p.passives, "alpha": p.alpha, "boss": p.boss,
			"san": p.san, "hunger": p.hunger, "job": jc, "carry": p.carry,
			"star": p.star, "xp": p.xp, "raid": p.raid})
	for bp in box:
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "box", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "carry": bp.carry,
			"revive": maxf(0.0, bp.revive_t - t)})
	var structs := {}
	for k in structures:
		structs["%d,%d" % [k.x, k.y]] = {"id": structures[k]["id"], "store": structures[k].get("store", {}), "egg": structures[k].get("egg_parents")}
	var d := {
		"seed": world.seed, "day": day, "tod": tod, "tech_points": tech_points,
		"unlocked": unlocked, "items": items, "party": party,
		"party_idx": party.map(func(u): return pals.find(find_pal(u))),
		"perks": perks, "equip": player.equipment,
		"pals": pals_data, "structures": structs,
		"drops": drops.map(func(dd): return {"id": dd["id"], "n": dd["n"], "x": dd["pos"].x, "y": dd["pos"].y}),
		"player": {"pos": [player.pos.x, player.pos.y], "hp": player.hp,
			"hunger": player.hunger,
			"level": player.level, "xp": player.xp, "cap_lv": player.capture_level},
		"decor": world.decor.duplicate(), "hp_map": world.hp.duplicate(),
	}
	var f := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	f.store_var(d)
	f.close()
	log_msg("Saved.")

func load_game() -> bool:
	if not FileAccess.file_exists("user://savegame.plg"):
		return false
	var f := FileAccess.open("user://savegame.plg", FileAccess.READ)
	if f == null:
		return false
	var dv = f.get_var()
	f.close()
	if dv is not Dictionary or not dv.has("seed"):
		log_msg("Save file corrupt - starting fresh")
		return false
	var d: Dictionary = dv
	for p in pals:
		p.queue_free()
	pals.clear()
	box.clear()
	for pr in projectiles:
		pr["node"].queue_free()
	projectiles.clear()
	for dd0 in drops:
		if is_instance_valid(dd0["node"]):
			dd0["node"].queue_free()
	drops.clear()
	for k in structures.keys():
		structures[k]["node"].queue_free()
	structures.clear()
	world.structures.clear()
	world.generate(d["seed"])
	world.decor = d["decor"]
	world.hp = d["hp_map"]
	day = d["day"]; tod = d["tod"]
	for dd0 in d.get("drops", []):
		spawn_drop(dd0["id"], int(dd0["n"]), Vector2(dd0["x"], dd0["y"]))
	tech_points = d["tech_points"]; unlocked = d["unlocked"]
	perks = d.get("perks", perks)
	player.equipment = d.get("equip", player.equipment)
	items = d["items"]; party = d["party"]
	player.pos = Vector2(d["player"]["pos"][0], d["player"]["pos"][1])
	player.hp = d["player"]["hp"]; player.level = d["player"]["level"]
	player.xp = d["player"]["xp"]; player.capture_level = d["player"]["cap_lv"]
	player.hunger = d["player"].get("hunger", player.hunger)
	var pending_jobs := []
	for pd in d["pals"]:
		if SpeciesData.species_of(pd.get("sp", "")).is_empty():
			log_msg("Skipped unknown species in save: %s" % pd.get("sp", "?"))
			continue # corrupt entry — don't crash on spec lookups
		var np := preload("res://src/pal.gd").new()
		np.setup(self, pd["sp"], pd["lv"], Vector2(pd["pos"][0], pd["pos"][1]))
		np.home = np.pos # loaded pals re-anchor at their saved spot
		np.mode = pd["mode"]; np.hp = pd["hp"]; np.talent = pd["talent"]
		if pd.get("sex") != null:
			np.sex = pd["sex"]
		if pd.get("passives") != null:
			np.passives = pd["passives"].filter(func(k): return PassiveData.PASSIVES.has(k)) # drop passives removed in newer builds
		if pd.get("alpha"):
			np.alpha = true
			np.sprite.scale = Vector2(1.6, 1.6)
		np.boss = pd.get("boss", false)
		np.san = pd.get("san", np.san)
		np.hunger = pd.get("hunger", 0.0)
		np.carry = pd.get("carry")
		np.star = pd.get("star", 0)
		np.xp = pd.get("xp", 0)
		np.raid = pd.get("raid", false)
		np.revive_t = t + pd.get("revive", 0.0)
		np.apply_bonuses()
		if pd.get("job"):
			pending_jobs.append([np, pd["job"]])
		if pd["mode"] == "box":
			box.append(np)
		else:
			entity_layer.add_child(np)
			pals.append(np)
	if d.has("party_idx"):
		party.clear()
		for pi in d["party_idx"]:
			if pi is int and pi >= 0 and pi < pals.size():
				party.append(pals[pi].uid)
	for ks in d["structures"]:
		var parts: PackedStringArray = ks.split(",")
		var sv = d["structures"][ks]
		var sid: String = sv["id"] if sv is Dictionary else sv
		var s: Dictionary = StructureData.STRUCTURES[sid]
		var tx := int(parts[0]); var ty := int(parts[1])
		if structures.has(Vector2i(tx, ty)):
			continue  # footprint cell of an already-rebuilt structure
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/structures/%s.png" % sid)
		var w: int = s.get("w", 2); var h: int = s.get("h", 2)
		var pp := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
		spr.position = Vector2(pp.x, pp.y - spr.texture.get_height() * 0.5 + 8)
		entity_layer.add_child(spr)
		var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {}}
		if sv is Dictionary:
			st["store"] = sv.get("store", {})
			if sv.get("egg"):
				st["egg_parents"] = sv["egg"]
		for dy in range(h):
			for dx in range(w):
				structures[Vector2i(tx + dx, ty + dy)] = st
				world.structures[world.idx(tx + dx, ty + dy)] = st
		if sid == "palbox":
			palbox_pos = Vector2i(tx, ty)
	for pj in pending_jobs:
		var parts2: PackedStringArray = pj[1].split(",")
		var cell := Vector2i(int(parts2[0]), int(parts2[1]))
		if structures.has(cell) and pj[0].mode == "base" and pj[0] not in structures[cell]["workers"]:
			structures[cell]["workers"].append(pj[0])
			pj[0].job_site = structures[cell]
	log_msg("Loaded.")
	return true

func start_raid() -> void:
	var c := Vector2(palbox_pos.x + 0.5, palbox_pos.y + 0.5)
	var n := 3 + rng.int_range(0, 2)
	var spawned := 0
	for i in n:
		var placed := false
		for try in 40:
			var ang := rng.next() * TAU
			var r := 12.0 + rng.next() * 12.0
			var tx := int(c.x + cos(ang) * r); var ty := int(c.y + sin(ang) * r)
			if world.blocked(tx, ty):
				continue
			var zone := world.zone_at(tx, ty)
			var pool: Array = ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)
			var hostile_pool := pool.filter(func(s): return SpeciesData.species_of(s).get("hostile", 0) >= 1)
			if hostile_pool.is_empty():
				hostile_pool = pool
			var sid: String = hostile_pool[rng.int_range(0, hostile_pool.size() - 1)]
			var rp := preload("res://src/pal.gd").new()
			entity_layer.add_child(rp)
			rp.setup(self, sid, rng.int_range(4 + zone * 4, 8 + zone * 6), Vector2(tx + 0.5, ty + 0.5))
			# raider picks nearest non-wild pal; falls back to the player
			rp.aggro = 0
			rp.raid = true
			rp.set_meta("raid_t0", t)
			var bp: Pal = null; var bd := 30.0
			for q in pals:
				if q.mode == "wild" or q.hp <= 0:
					continue
				var dd := rp.pos.distance_to(q.pos)
				if dd < bd:
					bd = dd; bp = q
			if bp:
				rp.aggro = bp.uid
			pals.append(rp)
			spawned += 1
			placed = true
			break
	if spawned > 0:
		log_msg("!! RAID: %d hostile pals approach your base !!" % spawned)

# ---------- breeding ----------
func tick_ranch(key: Vector2i, st: Dictionary, dt: float) -> void:
	var has_m := false
	var has_f := false
	for w in st["workers"]:
		if not is_instance_valid(w) or w.mode != "base":
			continue
		if w.sex == "M":
			has_m = true
		else:
			has_f = true
	if not (has_m and has_f):
		st["timer"] = 0.0
		return
	st["timer"] += (dt * (1.0 + perks["work"] * 0.1))
	var rate := 60.0
	if st["timer"] < rate:
		return
	st["timer"] -= rate
	var a: Pal = null; var b: Pal = null
	for w in st["workers"]:
		if not is_instance_valid(w):
			continue
		if w.sex == "M" and a == null:
			a = w
		elif w.sex == "F" and b == null:
			b = w
	if a == null or b == null:
		return
	if not st.has("egg_parents") or st["egg_parents"] == null:
		st["egg_parents"] = []
	st["egg_parents"].append([a.species_id, b.species_id, a.talent, b.talent]) # FIFO queue, one entry per egg
	st["store"]["pal_egg"] = st["store"].get("pal_egg", 0) + 1 # lays AT the ranch; haulers collect
	floater(Vector2(key.x + 0.5, key.y + 0.5), "Egg!", "#f5e6c8")
	log_msg("%s + %s produced an egg!" % [a.spec["name"], b.spec["name"]])

func hatch_egg() -> void:
	if item_count("pal_egg") <= 0:
		return
	var pair = null
	for k in structures:
		var q = structures[k].get("egg_parents")
		if q is Array and q.size() > 0:
			pair = q.pop_front() # oldest egg's parents
			break
	var sp_id: String
	var talent_v: int
	if pair is not Array or pair.size() < 4: # old saves stored a single flat pair, or nothing
		pair = null
	if pair:
		sp_id = pair[rng.int_range(0, 1)]
		talent_v = clampi((int(pair[2]) + int(pair[3])) / 2 + rng.int_range(-15, 15), 0, 100)
	else:
		var keys: Array = SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys()
		sp_id = keys[rng.int_range(0, keys.size() - 1)]
		talent_v = rng.int_range(0, 100)
	add_item("pal_egg", -1)
	var at := player.pos + Vector2(1.0, 0.5)
	var np := preload("res://src/pal.gd").new()
	np.talent = talent_v # set BEFORE setup so apply_bonuses uses it
	entity_layer.add_child(np)
	np.setup(self, sp_id, 1, at)
	if palbox_pos.x >= 0:
		np.mode = "base"
		pals.append(np)
	else: # no base: it goes straight to the box like any caught pal
		np.mode = "box"
		box.append(np)
		entity_layer.remove_child(np)
	floater(at, "* hatched! *", "#4dd0e1")
	log_msg("Egg hatched: %s (talent %d)!" % [np.spec["name"], talent_v])

func spawn_lairs() -> void:
	# Zone-3 boss lairs: torch ring + an Alpha guarding elite guards
	var placed := 0
	var tries := 0
	while placed < 3 and tries < 6000:
		tries += 1
		var tx := rng.int_range(6, World.WORLD_W - 8)
		var ty := rng.int_range(6, World.WORLD_H - 8)
		if world.zone_at(tx, ty) < 3:
			continue
		var ok := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if world.blocked(tx + dx, ty + dy) or structures.has(Vector2i(tx + dx, ty + dy)):
					ok = false
		if not ok:
			continue
		# torch ring (8 cells around a 5x5 clearing)
		for c in [Vector2i(tx-2,ty-2),Vector2i(tx+2,ty-2),Vector2i(tx-2,ty+2),Vector2i(tx+2,ty+2)]:
			place_free("torch", c.x, c.y)
		# alpha boss at center
		var pool := SpeciesGen.zone_pool(3)
		if pool.is_empty():
			pool = SpeciesGen.zone_pool(2)
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var bp := preload("res://src/pal.gd").new()
		entity_layer.add_child(bp)
		bp.alpha = true # before setup: apply_bonuses folds the 4x into max_hp
		bp.setup(self, sid, rng.int_range(30, 40), Vector2(tx + 0.5, ty + 0.5))
		pals.append(bp)
		# 2 elite guards
		for i in 2:
			var gsid: String = pool[rng.int_range(0, pool.size() - 1)]
			var gp := preload("res://src/pal.gd").new()
			entity_layer.add_child(gp)
			gp.setup(self, gsid, rng.int_range(18, 26), Vector2(tx + 0.5 + (1 if i == 0 else -1), ty + 0.5))
			pals.append(gp)
		placed += 1
	log_msg("%d boss lairs marked deep in the world" % placed)

func regenerate(s: int) -> void:
	for p in pals:
		if is_instance_valid(p):
			p.queue_free()
	pals.clear()
	party.clear()
	box.clear()
	for k in structures:
		if is_instance_valid(structures[k]["node"]):
			structures[k]["node"].queue_free()
	structures.clear()
	world.structures.clear()
	for dd0 in drops: # old world's ground loot doesn't carry over
		if is_instance_valid(dd0["node"]):
			dd0["node"].queue_free()
	drops.clear()
	for pr in projectiles:
		if is_instance_valid(pr["node"]):
			pr["node"].queue_free()
	projectiles.clear()
	palbox_pos = Vector2i(-1, -1)
	world.generate(s)
	drawer.setup(world)
	player.pos = Vector2(world.spawn) + Vector2(0.5, 0.5)
	player.sync_screen()
	spawn_wild() # after player.pos so the no-spawn radius is measured from the new point

# ---------- effigy statues ----------
const PERK_COST := 2
func upgrade_perk(k: String) -> void:
	var lvl: int = perks[k]
	if lvl >= 5:
		log_msg("Statue maxed")
		return
	var cost := PERK_COST + lvl * 2
	if item_count("lifmunk_effigy") < cost:
		log_msg("Need %d effigies (have %d)" % [cost, item_count("lifmunk_effigy")])
		return
	add_item("lifmunk_effigy", -cost)
	perks[k] = lvl + 1
	if k == "capture":
		player.capture_level = 1 + perks["capture"] # keep the stat in sync
	if k == "hp":
		player.max_hp = 100 + perks["hp"] * 12
		player.hp = player.max_hp
	log_msg("Statue upgraded: %s Lv%d" % [k, perks[k]])

func partner_skill() -> void:
	if party.is_empty():
		log_msg("No party pal")
		return
	var p: Pal = null
	for q in pals:
		if q.uid == party[0]:
			p = q
			break
	if not p or p.hp <= 0:
		log_msg("Party pal is down")
		return
	var m := player.get_global_mouse_position()
	var tw: Vector2 = Iso.from_screen(m.x, m.y, player.elev())
	var best: Dictionary = {}
	for sid in p.learned_skills():
		if p.skill_cd.get(sid, 0) > t:
			continue
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		if sk.is_empty() or sk.get("kind") == "lunge":
			continue
		if p.pos.distance_to(tw) > sk.get("range", 6) * 2.0:
			continue
		if best.is_empty() or sk.get("power", 0) > best.get("power", 0):
			best = sk # strongest usable skill — skills key damage as "power"
	if best.is_empty():
		log_msg("%s has no usable partner skill" % p.spec["name"])
		return
	p.skill_cd[best["id"]] = t + best.get("cooldown", 2)
	cast_skill(p, tw, best)
	log_msg("%s casts %s!" % [p.spec["name"], best["name"]])

func fire_player_shot(tw: Vector2, wd: Dictionary) -> void:
	var spr := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = orb_tex
	at.region = Rect2(0, 0, 16, 16)
	at.filter_clip = true
	spr.texture = at
	spr.scale = Vector2(1.2, 1.2)
	entity_layer.add_child(spr)
	var spd: float = 14.0
	projectiles.append({"pos": player.pos, "dir": (tw - player.pos).normalized(),
		"speed": spd, "ttl": wd.get("range", 10) / spd, "dmg": wd.get("dmg", 20),
		"elev": world.elev_at(int(player.pos.x), int(player.pos.y)),
		"from": "player", "node": spr})

func equip(k: String) -> void:
	var it: Dictionary = ItemData.ITEMS.get(k, {})
	var slot := ""
	if it.get("kind") == "weapon" or it.has("weapon"):
		slot = "weapon"
	elif it.get("kind") == "armor" or it.has("armor"):
		slot = "armor"
	if slot == "" or item_count(k) <= 0:
		return
	if player.equipment[slot] == k:
		player.equipment[slot] = ""
		log_msg("Unequipped " + it["name"])
	else:
		player.equipment[slot] = k
		log_msg("Equipped " + it["name"])
