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
var structures := {}          # Vector2i -> {id, node, timer, workers:[]}
var palbox_pos := Vector2i(-1, -1)  # base anchor; -1 = no base yet
var tech_points := 0
var unlocked := ["palbox", "pal_bed", "feed_box", "campfire", "workbench", "straw_bed"]
var build_sel := -1           # index into buildable list; -1 off
var craft_target: Node2D = null
var panel := ""
var craft_station := ""
var chest_ref = null
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
		var pool: Array = ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var sp: Dictionary = SpeciesData.species_of(sid)
		var lv := rng.int_range(1 + zone * 3, 4 + zone * 5)
		var p := preload("res://src/pal.gd").new()
		p.alpha = zone >= 2 and rng.chance(0.08)
		entity_layer.add_child(p)
		p.setup(self, sid, lv + (6 if p.alpha else 0), Vector2(x + 0.5, y + 0.5))
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
	var mult := 4 if p.alpha else 1
	if p.boss:
		add_item("legendary_sphere", 1)
		add_item("lifmunk_effigy", 3)
		add_item("gold_coin", 10)
		log_msg("RAID CLEARED! Legendary sphere + loot!")
	for d in p.spec.get("drops", []):
		add_item(d[0], rng.int_range(d[1], d[2]) * mult)
		log_msg("Loot: %s x%d" % [ItemData.ITEMS[d[0]]["name"], int(d[2]) * mult])
	if p.alpha:
		add_item("pal_sphere", 1)
		log_msg("Alpha %s down! Bonus sphere." % p.spec["name"])
		add_item("lifmunk_effigy", 2)
	pals.erase(p)
	party.erase(p.uid)  # dead partners must free their party slot
	if p.job_site and p in p.job_site["workers"]:
		p.job_site["workers"].erase(p)
	p.queue_free()
	gain_xp(p.level * 4)

func hurt_player(atk: float, from: Pal) -> void:
	if player.dodge_t > 0:
		return
	var def := 20.0 + player.level * 3.0
	var d := maxi(1, int(round(25.0 * (2.0 * atk) / maxf(1.0, atk + 2.0 * def) * (0.9 + rng.next() * 0.2))))
	player.hp -= maxi(1, d - player.armor_def())
	player.hit_flash = 0.4
	floater(player.pos, "-" + str(d), "#e64533")
	if player.hp <= 0:
		respawn_player()

func sphere_fly(sid: String, target: Pal) -> void:
	spheres_flying.append({"sid": sid, "target": target, "t": 0.0})

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
	for iid in items.keys():
		if iid in ["gold_coin"]:
			continue
		var c: int = items[iid]
		if c > 0:
			st["store"][iid] = st["store"].get(iid, 0) + c
			n += c
			items.erase(iid)
	return n

func chest_withdraw_all(st) -> int:
	var n := 0
	for iid in st.get("store", {}).keys():
		add_item(iid, st["store"][iid])
		n += st["store"][iid]
	st["store"] = {}
	return n

func respawn_player() -> void:
	player.hp = int(player.max_hp * 0.5)
	player.statuses.clear()
	if palbox_pos.x >= 0:
		player.pos = Vector2(palbox_pos.x + 0.5, palbox_pos.y + 2.5)
	log_msg("You wake up battered at base…")

func sleep_to_morning() -> void:
	day += 1
	tod = 6.0
	player.hp = player.max_hp
	for q in pals:
		if q.mode == "base":
			q.hp = q.max_hp
			q.san = 100.0
			q.hunger = 0.0
	log_msg("You sleep until dawn. Day %d" % day)

func summon_raid() -> void:
	if palbox_pos.x < 0:
		log_msg("Need a palbox to summon the raid")
		return
	var pool: Array = SpeciesGen.zone_pool(3)
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	var bp := preload("res://src/pal.gd").new()
	bp.alpha = true
	entity_layer.add_child(bp)
	bp.setup(self, sid, 45, Vector2(palbox_pos.x + 2.5, palbox_pos.y + 2.5))
	bp.boss = true
	bp.max_hp *= 2.0
	bp.hp = bp.max_hp
	bp.sprite.scale = Vector2(2.2, 2.2)
	bp.sprite.position.y = -70.0
	bp.aggro = 0  # player
	pals.append(bp)
	log_msg("RAID BOSS: %s Lv45 approaches your base!" % bp.spec["name"])

func resolve_sphere(sp) -> void:
	var target: Pal = sp["target"]
	if not is_instance_valid(target) or target.hp <= 0:
		return
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
	update_projectiles(dt)
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
	for dy0 in range(s.get("h", 2)):
		for dx0 in range(s.get("w", 2)):
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				log_msg("Blocked: something already built there")
				return false
			if world.tile_at(tx + dx0, ty + dy0) == World.Tile.WATER:
				log_msg("Can't build on water")
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
	n = int(n * (1.0 + perks["xp"] * 0.08))
	for q in pals:
		if q.mode == "partner" and q.hp > 0:
			q.xp += int(n * 0.5)
			if q.xp >= q.level * 25:
				q.xp = 0
				q.level += 1
				q.max_hp = Combat.stat_at(q.spec["hp"], q.level, q.talent) * (4.0 if q.alpha else 1.0)
				q.hp = q.max_hp
				log_msg("%s grew to Lv%d!" % [q.spec["name"], q.level])
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
		if st["id"] == "ranch":
			tick_ranch(key, st, dt)
			continue
		var prod: Array = job.get("produces", [])
		var active: Array = st["workers"].filter(func(w): return w.san >= 15.0)
		if prod.is_empty() or active.is_empty():
			continue
		var powered := 1.0
		for kg in structures:
			var sg = structures[kg]
			if sg.get("id") == "generator" and not sg["workers"].is_empty():
				powered = 1.5
		st["timer"] += (dt * (1.0 + perks["work"] * 0.1)) * powered * active.size()
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
	if party.size() < 5:
		party.append(bp.uid)
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
		if s.get("job", {}).get("produces") == null:
			continue
		var d := best.pos.distance_to(Vector2(k.x, k.y))
		if d < sd:
			sd = d
			site = structures[k]
	if site:
		var need: String = StructureData.STRUCTURES[site["id"]].get("job", {}).get("workType", "")
		if need != "" and best.spec.get("work", {}).get(need, 0) == 0:
			log_msg("%s can't %s" % [best.spec["name"], need])
			return
		site["workers"].append(best)
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
			caster.hp = minf(caster.max_hp, caster.hp + caster.max_hp * sk.get("power", 20) / 100.0)
			floater(caster.pos, "+" + sk["name"], "#a8e6a1")
		"lunge":
			caster.pos = tpos + (caster.pos - tpos).normalized() * 0.9
			skill_hit(caster, target_ent, sk)
		"burst":
			var radius: float = sk.get("range", 4)
			if caster.mode == "wild":
				if caster.pos.distance_to(player.pos) <= radius:
					skill_hit(caster, player, sk)
			else:
				for p in pals:
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
		if pr["from"] is String and pr["from"] == "player":
			if not dead:
				for p in pals:
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
				for p in pals:
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
		for kj in structures:
			if p in structures[kj]["workers"]:
				jc = "%d,%d" % [kj.x, kj.y]
				break
		pals_data.append({"sp": p.species_id, "lv": p.level, "pos": [p.pos.x, p.pos.y],
			"mode": p.mode, "hp": p.hp, "talent": p.talent, "sex": p.sex,
			"passives": p.passives, "alpha": p.alpha, "boss": p.boss,
			"san": p.san, "hunger": p.hunger, "job": jc})
	for bp in box:
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "box", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"passives": bp.passives, "alpha": bp.alpha})
	var structs := {}
	for k in structures:
		structs["%d,%d" % [k.x, k.y]] = {"id": structures[k]["id"], "store": structures[k].get("store", {}), "egg": structures[k].get("egg_parents")}
	var d := {
		"seed": world.seed, "day": day, "tod": tod, "tech_points": tech_points,
		"unlocked": unlocked, "items": items, "party": party,
		"party_idx": party.map(func(u): return pals.find(find_pal(u))),
		"perks": perks, "equip": player.equipment,
		"pals": pals_data, "structures": structs,
		"player": {"pos": [player.pos.x, player.pos.y], "hp": player.hp,
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
	var d: Dictionary = f.get_var()
	f.close()
	for p in pals:
		p.queue_free()
	pals.clear()
	box.clear()
	for pr in projectiles:
		pr["node"].queue_free()
	projectiles.clear()
	for k in structures.keys():
		structures[k]["node"].queue_free()
	structures.clear()
	world.structures.clear()
	world.generate(d["seed"])
	world.decor = d["decor"]
	world.hp = d["hp_map"]
	day = d["day"]; tod = d["tod"]
	tech_points = d["tech_points"]; unlocked = d["unlocked"]
	perks = d.get("perks", perks)
	player.equipment = d.get("equip", player.equipment)
	items = d["items"]; party = d["party"]
	player.pos = Vector2(d["player"]["pos"][0], d["player"]["pos"][1])
	player.hp = d["player"]["hp"]; player.level = d["player"]["level"]
	player.xp = d["player"]["xp"]; player.capture_level = d["player"]["cap_lv"]
	var pending_jobs := []
	for pd in d["pals"]:
		var np := preload("res://src/pal.gd").new()
		np.setup(self, pd["sp"], pd["lv"], Vector2(pd["pos"][0], pd["pos"][1]))
		np.mode = pd["mode"]; np.hp = pd["hp"]; np.talent = pd["talent"]
		if pd.get("sex") != null:
			np.sex = pd["sex"]
		if pd.get("passives") != null:
			np.passives = pd["passives"]
		if pd.get("alpha"):
			np.alpha = true
			np.max_hp *= 4.0; np.hp = minf(np.hp, np.max_hp)
			np.sprite.scale = Vector2(1.6, 1.6)
		np.boss = pd.get("boss", false)
		np.san = pd.get("san", np.san)
		np.hunger = pd.get("hunger", 0.0)
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
		if structures.has(cell):
			structures[cell]["workers"].append(pj[0])
			pj[0].job_site = structures[cell]
	log_msg("Loaded.")
	return true

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
	var pair := []
	for w in st["workers"]:
		if is_instance_valid(w):
			pair.append(w)
	var a: Pal = pair[0]
	var b: Pal = pair[1] if pair.size() > 1 else pair[0]
	st["egg_parents"] = [a.species_id, b.species_id, a.talent, b.talent]
	add_item("pal_egg", 1)
	floater(Vector2(key.x + 0.5, key.y + 0.5), "Egg!", "#f5e6c8")
	log_msg("%s + %s produced an egg!" % [a.spec["name"], b.spec["name"]])

func hatch_egg() -> void:
	if item_count("pal_egg") <= 0:
		return
	var pair = null
	for k in structures:
		if structures[k].get("egg_parents"):
			pair = structures[k]["egg_parents"]
			structures[k]["egg_parents"] = null
			break
	var sp_id: String
	var talent_v: int
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
	entity_layer.add_child(np)
	np.setup(self, sp_id, 1, at)
	np.talent = talent_v
	np.mode = "base" if palbox_pos.x >= 0 else "wild"
	np.max_hp = Combat.stat_at(np.spec["hp"], 1, talent_v)
	np.hp = np.max_hp
	if np.mode == "base":
		pals.append(np)
	else:
		pals.append(np)
	floater(at, "* hatched! *", "#4dd0e1")
	log_msg("Egg hatched: %s (talent %d)!" % [np.spec["name"], talent_v])

func regenerate(s: int) -> void:
	for p in pals:
		if is_instance_valid(p):
			p.queue_free()
	pals.clear()
	party.clear()
	box.clear()
	for k in structures:
		if is_instance_valid(structures[k]["sprite"]):
			structures[k]["sprite"].queue_free()
	structures.clear()
	world.structures.clear()
	palbox_pos = Vector2i(-1, -1)
	world.generate(s)
	drawer.setup(world)
	spawn_wild()
	player.pos = Vector2(world.spawn) + Vector2(0.5, 0.5)
	player.sync_screen()

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
	if not p:
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
		best = sk
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
		"from": "player", "node": spr})

func equip(k: String) -> void:
	var it: Dictionary = ItemData.ITEMS.get(k, {})
	var slot := ""
	if it.get("kind") == "weapon" or it.has("weapon"):
		slot = "weapon"
	elif it.get("kind") == "armor" or it.has("armor"):
		slot = "armor"
	if slot == "":
		return
	if player.equipment[slot] == k:
		player.equipment[slot] = ""
		log_msg("Unequipped " + it["name"])
	else:
		player.equipment[slot] = k
		log_msg("Equipped " + it["name"])
