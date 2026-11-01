extends Node2D
class_name Game
# Root game state: world, player, pals, inventory, time, messages, floaters.
# Multiplayer-ready seams: all state lives here; sim runs deterministically.

var world := World.new()
var rng: Rng
var player: Player
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
var structures := {}          # Vector2i -> {id, node, timer, workers:[]}
var palbox_pos := Vector2i(-1, -1)  # base anchor; -1 = no base yet
var tech_points := 0
var unlocked := ["palbox", "pal_bed", "feed_box", "campfire", "workbench", "straw_bed"]
var build_sel := -1           # index into buildable list; -1 off
var craft_target: Node2D = null
var panel := ""
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

func sphere_tiers() -> Array:
	var out := []
	for id in ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]:
		if items.get(id, 0) > 0:
			out.append(id)
	return out

func add_item(id: String, n: int) -> void:
	items[id] = items.get(id, 0) + n
	if items[id] <= 0:
		items.erase(id)

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
	while pals.size() < want and tries < 4000:
		tries += 1
		var x := rng.int_range(4, World.WORLD_W - 5)
		var y := rng.int_range(4, World.WORLD_H - 5)
		if world.blocked(x, y):
			continue
		var zone := world.zone_at(x, y)
		var pool: Array = ZONE_SPECIES[zone]
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var sp: Dictionary = SpeciesData.SPECIES[sid]
		var lv := rng.int_range(1 + zone * 3, 4 + zone * 5)
		var p := preload("res://src/pal.gd").new()
		entity_layer.add_child(p)
		p.setup(self, sid, lv, Vector2(x + 0.5, y + 0.5))
		pals.append(p)

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
	# drops
	for d in p.spec.get("drops", []):
		add_item(d[0], rng.int_range(d[1], d[2]))
		log_msg("Loot: %s x%d" % [ItemData.ITEMS[d[0]]["name"], int(d[2])])
	pals.erase(p)
	p.queue_free()
	gain_xp(p.level * 4)

func hurt_player(atk: float, from: Pal) -> void:
	if player.dodge_t > 0:
		return
	var def := 20.0 + player.level * 3.0
	var d := maxi(1, int(round(25.0 * (2.0 * atk) / maxf(1.0, atk + 2.0 * def) * (0.9 + rng.next() * 0.2))))
	player.hp -= d
	player.hit_flash = 0.4
	floater(player.pos, "-" + str(d), "#e64533")
	if player.hp <= 0:
		player.hp = 0
		log_msg("You were knocked out…")

func sphere_fly(sid: String, target: Pal) -> void:
	spheres_flying.append({"sid": sid, "target": target, "t": 0.0})

func resolve_sphere(sp) -> void:
	var target: Pal = sp["target"]
	if not is_instance_valid(target) or target.hp <= 0:
		return
	var behind: float = sign(player.pos.x - target.pos.x) == -target.dir
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var chance := Combat.catch_chance(hp_frac, target.spec["capturePower"],
		ItemData.ITEMS[sp["sid"]].get("spherePower", 26), target.any_status(), behind, player.capture_level)
	if randf() < chance:
		floater(target.pos, "★ CAUGHT!", "#4dd0e1")
		log_msg("Caught %s Lv%d!" % [target.spec["name"], target.level])
		gain_xp(target.level * 3)
		target.mode = "box"
		box.append(target)
		pals.erase(target)
		target.queue_free()
	else:
		floater(target.pos, "…broke free", "#e8963c")
		log_msg("%s broke free (%d%%)" % [target.spec["name"], int(chance * 100)])
		target.aggro = 0 if target.hostile() >= 1 else -1

func try_harvest(at: Vector2, dir: int) -> void:
	# hit the decor tile the player faces
	var tx := int(at.x) + dir
	var ty := int(at.y)
	var d := world.decor_at(tx, ty)
	if d == World.Decor.NONE:
		return
	var i := world.idx(tx, ty)
	world.hp[i] = max(0, world.hp[i] - 10)
	floater(Vector2(tx + 0.5, ty + 0.5), "thwack", "#c8d3d5")
	if world.hp[i] == 0:
		var loot: String = {World.Decor.TREE_A: "wood", World.Decor.TREE_B: "wood",
			World.Decor.ROCK: "stone", World.Decor.ORE_GOLD: "ore",
			World.Decor.ORE_COAL: "coal", World.Decor.BERRY: "berry",
			World.Decor.STUMP: "wood"}[d]
		var n: int = 1 if d == World.Decor.BERRY else rng.int_range(1, 3)
		add_item(loot, n)
		log_msg("+%d %s" % [n, ItemData.ITEMS.get(loot, {}).get("name", loot)])
		world.decor[i] = World.Decor.STUMP if (d == World.Decor.TREE_A or d == World.Decor.TREE_B) else World.Decor.NONE
		world.hp[i] = 0
		queue_redraw_decor()

signal decor_dirty
func queue_redraw_decor() -> void:
	decor_dirty.emit()

func _process(dt: float) -> void:
	t += dt
	tod += dt / DAY_LEN * 24.0
	if tod >= 24.0:
		tod -= 24.0
		day += 1
	# spheres
	for sp in spheres_flying.duplicate():
		sp["t"] += dt
		if sp["t"] > 0.45:
			resolve_sphere(sp)
			spheres_flying.erase(sp)
	tick_production(dt)
	# floaters age
	for f in floaters:
		f["age"] += dt
	floaters = floaters.filter(func(f): return f["age"] < 1.2)
	# respawn trickle
	if pals.size() < 30 and rng.chance(dt * 0.15):
		spawn_wild()

# ---------- building / tech / crafting / base ----------

func buildable_list() -> Array:
	return unlocked.duplicate()

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
	for c in s.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg("Need %d %s" % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])])
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
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": []}
	for dy in range(h):
		for dx in range(w):
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[world.idx(tx + dx, ty + dy)] = st
	if sid == "palbox":
		palbox_pos = Vector2i(tx, ty)
		log_msg("Base established! Assign pals with F.")
	log_msg("Built %s" % s["name"])
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
	for c in r.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg("Missing materials")
			return
	for c in r.get("cost", []):
		add_item(c[0], -c[1])
	add_item(r["out"][0], r["out"][1])
	log_msg("Crafted %s x%d" % [ItemData.ITEMS[r["out"][0]]["name"], r["out"][1]])

func gain_xp(n: int) -> void:
	player.xp += n
	var need := 30 + player.level * 20
	if player.xp >= need:
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
		var prod: Array = job.get("produces", [])
		if prod.is_empty() or st["workers"].is_empty():
			continue
		st["timer"] += dt * st["workers"].size()
		var rate: float = job.get("amount", 30)
		if st["timer"] >= rate:
			st["timer"] -= rate
			for pr in prod:
				add_item(pr[0], pr[1])
			var t := ""
			for pr in prod:
				t += "+%d %s  " % [pr[1], pr[0]]
			floaters.push_back({"p": Vector2(key.x + 0.5, key.y + 0.5), "t": t.strip_edges(), "c": "#a8e6a1", "age": 0.0})

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
	box.erase(bp)
	pals.append(bp)
	bp.mode = "partner" if party.size() < 5 else "base"
	party.append(bp.uid) if party.size() < 5 else 0
	var spawn_p := player.pos + Vector2(1.2, 0)
	bp.pos = spawn_p
	entity_layer.add_child(bp)
	log_msg("%s joined %s" % [bp.spec["name"], bp.mode])

func party_to_box(uid: int) -> void:
	var p := find_pal(uid)
	if not p:
		return
	party.erase(uid)
	pals.erase(p)
	p.mode = "box"
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
		if s.get("produces") == null:
			continue
		var d := best.pos.distance_to(Vector2(k.x, k.y))
		if d < sd:
			sd = d
			site = structures[k]
	if site:
		site["workers"].append(best)
		best.job_site = site
		log_msg("%s -> %s" % [best.spec["name"], StructureData.STRUCTURES[site["id"]]["name"]])
	else:
		log_msg("No workplace nearby")
