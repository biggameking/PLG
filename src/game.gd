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
	# floaters age
	for f in floaters:
		f["age"] += dt
	floaters = floaters.filter(func(f): return f["age"] < 1.2)
	# respawn trickle
	if pals.size() < 30 and rng.chance(dt * 0.15):
		spawn_wild()
