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
const MAX_CRAFT_QUEUE := 8   # Palworld timed crafting: station recipes queue up
var queue_crafts := true     # smoke tests flip this off to keep crafts instant
var craft_queue := []        # {out,n,left,cost} — station builds in progress
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
var palbox_pos := Vector2i(-1, -1)  # primary base anchor; -1 = no base yet
const MAX_EXTRA_BOXES := 2          # Palworld runs up to 3 bases — 1 primary + 2 outposts
var extra_boxes: Array[Vector2i] = [] # outpost palbox origins, shared box network
var tech_points := 0
var unlocked := ["palbox", "pal_bed", "feed_box", "campfire", "workbench", "straw_bed"]
var build_sel := -1           # index into buildable list; -1 off
var craft_target: Node2D = null
var panel := ""
var craft_station := ""
var chest_ref = null
var condense_arm := 0.0
const DAY_LEN := 240.0     # seconds per game day

# ---- hard caps: nothing per-frame/per-event may grow without bound ----
# Any unbounded collection is a memory leak in waiting; every list that
# accepts runtime appends must evict/expire or refuse past these limits.
const MAX_DROPS := 400        # ground loot; oldest decays first anyway
const MAX_PROJECTILES := 200  # raid volleys can spike these hard
const MAX_FLOATERS := 80      # cosmetic text — cheap insurance
const MAX_PALS := 220         # wild + owned + raid; AI tick cost scales with this
const MAX_BOX := 400          # stored pals are out-of-tree nodes — real bytes
const MAX_EGG_QUEUE := 32     # ranch parentage queue (eggs can also be sold/eaten)
const MAX_MERCH_STOCK := 64   # merchant inventory refresh
# Signature breeding pairs (Palworld combos): "a+b" -> offspring species.
# Checked both directions at hatch time; unlisted pairs inherit a parent.
const BREED_COMBOS := {
	"lamball+chikipi": "cattiva",
	"cattiva+lifmunk": "vixy",
	"foxparks+rooby": "flambelle",
	"pengullet+cattiva": "kelpsea",
	"fuack+pengullet": "surfdog",
	"mozzarina+lamball": "melpaca",
	"direhowl+lovander": "loupmoon",
	"mossanda+rayhound": "grizzbolt",
	"helzephyr+anubis": "shadowbeak",
	"relaxaurus+grizzbolt": "stormpuff",
	"jetragon+grizzbolt": "astegon",
	"pengullet+fuack": "penking",
	"eikthyrdeer+cattiva": "galeclaw",
	"mossanda+dinossom": "elphidran",
	"rayhound+direhowl": "univolt",
	"arsox+blazehowl": "ragnahawk",
	"kelpsea+gobfin": "azurobe",
	"cinnamoth+beegarde": "elizabee",
	"anubis+gorirat": "menasting",
	"sweepa+reindrix": "wumpo",
	"flambelle+rooby": "arsox",
	"dumud+maraith": "mirelurk",
	"dazzi+hoocrates": "glimmora",
	"caprity+sweety": "woolipop",
	"tocotoco+chikipi": "beakon",
	"ribbuny+flopie": "verdash",
	"digtoise+fuddler": "reptyro",
	"hydrostar+vapori": "chillet",
	"thornite+cragboar": "dreadmaw",
	"penking+bushi": "anubis",
	"ragnahawk+tombat": "anubis",
	"mossanda+grizzbolt": "rayhound",
	"beakon+helzephyr": "quivern",
	"tanzee+lifmunk": "gorirat",
	"nox+daedream": "tombat",
	"mau+dazzi": "catress",
	"emberwing+cawgnito": "helzephyr",
	"broncherry+dinossom": "petallia",
	"wumpo+caprity": "grintale",
	"depresso+lunaris": "nox",
	"bombird+beakon": "cawgnito",
}

func _exit_tree() -> void:
	# Orphan sweep: nodes DETACHED from the tree are not freed by the engine —
	# box pals are remove_child'd Node2Ds and leak at quit otherwise.
	if OS.has_environment("PLG_ORPHANS"):
		print("_exit_tree sweep: box=%d pals=%d" % [box.size(), pals.size()])
	for bp in box:
		if is_instance_valid(bp):
			bp.free() # not in tree: free(), never queue_free()
	box.clear()
	for bp in pals:
		if is_instance_valid(bp) and bp.get_parent() == null:
			bp.free()
	pals.clear()

@onready var entity_layer: Node2D = $YSort/Entities
@onready var drawer = $World/Terrain
# Detached-node leak prevention: box pals live under this hidden holder instead
# of floating parentless. Every pal is ALWAYS inside the tree — the engine
# reclaims them at exit and no code path can orphan one.
var box_holder: Node2D

func box_pal(p: Pal) -> void:
	# send a live pal to the box: keep it parented (to box_holder) so it can
	# never leak; process is disabled there so stored pals cost nothing.
	if p.get_parent() == box_holder:
		return
	if p.get_parent() == null:
		box_holder.add_child(p)
	else:
		p.reparent(box_holder)

func unbox_pal(p: Pal) -> void:
	if p.get_parent() == entity_layer:
		return
	if p.get_parent() == null:
		entity_layer.add_child(p)
	else:
		p.reparent(entity_layer)

func next_uid() -> int:
	next_uid_v += 1
	return next_uid_v

func _ready() -> void:
	box_holder = Node2D.new()
	box_holder.name = "BoxHolder"
	box_holder.process_mode = Node.PROCESS_MODE_DISABLED # boxed pals don't tick
	add_child(box_holder)
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
				log_msg("Bag full - %s x%d dropped" % [ItemData.ITEMS.get(id, {}).get("name", id), spill])
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
	if floaters.size() >= MAX_FLOATERS:
		floaters.pop_front() # cosmetic spam is evictable
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
	while wild_n < want and pals.size() < MAX_PALS and tries < 4000:
		tries += 1
		var x := rng.int_range(4, World.WORLD_W - 5)
		var y := rng.int_range(4, World.WORLD_H - 5)
		if player.pos.distance_squared_to(Vector2(x, y)) < 64.0:
			continue # don't pop a pal into existence on top of the player
		var zone := world.zone_at(x, y)
		var pool: Array = ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)
		var sid := pick_wild_species(pool)
		var sp: Dictionary = SpeciesData.species_of(sid)
		var aquatic: bool = "water" in sp.get("elements", [])
		var in_water: bool = world.tiles[world.idx(x, y)] == World.Tile.WATER
		if in_water:
			if not aquatic or world.blocked_swim(x, y, x, y):
				continue # landlubbers can't pop up in a lake
		elif world.blocked(x, y):
			continue
		var lv := rng.int_range(1 + zone * 3, 4 + zone * 5)
		var p := preload("res://src/pal.gd").new()
		p.alpha = zone >= 2 and rng.chance(0.08)
		p.lucky = not p.alpha and rng.chance(0.015) # Palworld "Lucky" rare variant
		entity_layer.add_child(p)
		p.setup(self, sid, lv + (6 if p.alpha else 0) + (3 if p.lucky else 0), Vector2(x + 0.5, y + 0.5))
		if p.lucky:
			floater(p.pos, "☆ LUCKY ☆", "#ffd76e")
		p.home = p.pos # lair anchor — alphas tether here
		pals.append(p)
		wild_n += 1

func pick_wild_species(pool: Array) -> String:
	# Palworld day/night ecology: dark pals are nocturnal — they only spawn
	# after dusk, and they dominate the night table in mixed zones.
	var dark := pool.filter(func(s): return "dark" in SpeciesData.species_of(str(s)).get("elements", []))
	if is_night():
		if not dark.is_empty():
			return dark[rng.int_range(0, dark.size() - 1)]
	else:
		var diurnal := pool.filter(func(s): return s not in dark)
		if not diurnal.is_empty():
			return diurnal[rng.int_range(0, diurnal.size() - 1)]
	return pool[rng.int_range(0, pool.size() - 1)]

func gen_pal(sp_id: String, lv: int, at: Vector2, lucky := false) -> Pal:
	# test/dev factory: a live pal in the entity layer; caller picks its mode
	var p := preload("res://src/pal.gd").new()
	p.lucky = lucky # must be set before setup — passives/scale roll there
	entity_layer.add_child(p)
	p.setup(self, sp_id, lv, at)
	p.home = at
	return p

func spawn_net_pal(d) -> void:
	# client-side replica of a host pal — untrusted wire data, validate the shape
	if pals.size() >= MAX_PALS or not (d is Array) or d.size() < 5:
		return
	var sp_id := str(d[0])
	if SpeciesData.species_of(sp_id).is_empty() and SpeciesGen.SPECIES.get(sp_id, {}).is_empty():
		return # foreign species id — drop the entry
	if not (d[1] is float or d[1] is int) or not (d[2] is float or d[2] is int):
		return
	var np := gen_pal(sp_id, clampi(int(d[3]), 1, 60),
		nearest_free(float(d[1]), float(d[2])), bool(d[5]) if d.size() > 5 else false)
	np.mode = "base" if str(d[4]) == "base" else "wild"
	np.net_id = int(d[6]) if d.size() > 6 else 0 # host uid — replicas track by this
	pals.append(np)

func find_net_pal(nid: int) -> Pal:
	for p in pals:
		if p.net_id == nid and nid > 0:
			return p
	return null

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
	var owned := p.mode in ["partner", "base"]
	if not owned: # only wild/raid pals drop loot or pay xp — KO'd own pals would farm infinitely
		var mult := 4 if p.alpha else (3 if p.lucky else 1)
		if p.lucky:
			add_item("gold_coin", rng.int_range(3, 8)) # lucky pals bleed money
			log_msg("Lucky %s dropped gold!" % p.spec["name"])
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
			add_item("ancient_part", rng.int_range(1, 2)) # ancient tech currency
		if p.boss:
			add_item("ancient_part", rng.int_range(2, 4))
		gain_xp(p.level * 4)
	if p.carry != null: # a hauler's load doesn't die with it
		spawn_drop(p.carry["id"], p.carry["n"], p.pos)
		p.carry = null
	pals.erase(p)
	party.erase(p.uid)  # dead partners must free their party slot
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null # no lingering worker SAN drain or base_ai pull
	if owned: # owned pals are knocked out, not deleted
		p.mode = "box"
		p.statuses.clear() # a KO'd pal shouldn't come out of the box still burning
		p.stun_t = 0.0
		p.revive_t = t + 300.0  # Palworld-style revive timer
		box.append(p)
		box_pal(p)
		log_msg("%s is KO'd - it will recover in the box" % p.spec["name"])
	else:
		if p.has_meta("gauntlet") and not gauntlet.is_empty():
			gauntlet["left"] -= 1
		if (p.alpha or p.boss) and not p.raid and p.home != Vector2.ZERO \
				and boss_respawns.size() < MAX_RESPAWNS:
			# Palworld dens refill: a slain boss returns to its anchor ~1.5 days
			# on. Raid/gauntlet attackers have no den — they stay dead.
			boss_respawns.append({"sid": p.species_id, "lv": p.level,
				"pos": [p.home.x, p.home.y], "alpha": p.alpha, "boss": p.boss,
				"at": t + DAY_LEN * 1.5})
		p.queue_free()

const MAX_RESPAWNS := 64 # scheduled den refills — bounded like every runtime set
var boss_respawns := []  # {sid,lv,pos:[x,y],alpha,boss,at}

func tick_boss_respawns() -> void:
	for i in range(boss_respawns.size() - 1, -1, -1):
		var br: Dictionary = boss_respawns[i]
		if t < br.get("at", INF):
			continue
		boss_respawns.remove_at(i)
		var sid := str(br.get("sid", ""))
		if pals.size() >= MAX_PALS or SpeciesData.species_of(sid).is_empty():
			continue # cap reached or corrupted entry — the den stays empty
		var pp: Array = br.get("pos", [0, 0])
		var at := Vector2(float(pp[0]), float(pp[1])) if pp.size() >= 2 else Vector2.ZERO
		var np := preload("res://src/pal.gd").new()
		np.alpha = bool(br.get("alpha", false))
		np.boss = bool(br.get("boss", false))
		entity_layer.add_child(np)
		np.setup(self, sid, clampi(int(br.get("lv", 30)), 1, 60), at)
		np.home = at
		pals.append(np)
		log_msg("A boss stirs again at its den")

# ---------- gauntlet trial ----------
# Palworld's tower fights, distilled: a sigil starts a 3-wave escalating
# battle at the palbox. Transient like a raid — never saved, never net-synced.
var gauntlet := {} # {"wave": int, "left": int} — empty while idle

func start_gauntlet() -> bool:
	if not gauntlet.is_empty():
		log_msg("A gauntlet is already running")
		return false
	if palbox_pos.x < 0:
		log_msg("The gauntlet needs a palbox to answer to")
		return false
	gauntlet = {"wave": 0, "left": 0}
	gauntlet_next_wave()
	return true

func gauntlet_next_wave() -> void:
	gauntlet["wave"] += 1
	var w: int = gauntlet["wave"]
	# [pool, count, [lv_lo, lv_hi], boss?] — wave 3 caps with a true boss
	var groups := []
	match w:
		1: groups = [[SpeciesGen.zone_pool(2), 2, [20, 26], false]]
		2: groups = [[SpeciesGen.zone_pool(2) + SpeciesGen.zone_pool(3), 2, [30, 36], false]]
		_: groups = [[SpeciesGen.zone_pool(3), 2, [38, 42], false],
			[SpeciesGen.zone_pool(3), 1, [48, 50], true]]
	for grp in groups:
		var pool: Array = grp[0]
		for i in int(grp[1]):
			if pool.is_empty() or pals.size() >= MAX_PALS:
				continue
			var np := preload("res://src/pal.gd").new()
			np.alpha = true
			np.boss = bool(grp[3])
			entity_layer.add_child(np)
			np.setup(self, pool[rng.int_range(0, pool.size() - 1)],
				rng.int_range(int(grp[2][0]), int(grp[2][1])),
				nearest_free(palbox_pos.x + 2.5 + i, palbox_pos.y + 2.5 + i))
			if np.boss:
				np.sprite.scale = Vector2(2.2, 2.2)
				np.sprite.position.y = -70.0
			np.aggro = 0
			np.raid = true # den-respawn skips raiders — the tower stays dead too
			np.set_meta("gauntlet", true)
			np.set_meta("raid_t0", t)
			pals.append(np)
			gauntlet["left"] += 1
	log_msg("Gauntlet wave %d! %d foes" % [w, gauntlet["left"]])

func tick_gauntlet() -> void:
	if gauntlet.is_empty() or gauntlet["left"] > 0:
		return
	if gauntlet["wave"] < 3:
		gauntlet_next_wave()
		return
	gauntlet = {}
	add_item("legendary_sphere", 2)
	add_item("lifmunk_effigy", 5)
	add_item("gold_coin", 150)
	add_item("gauntlet_sigil", 1) # it pays for the next run — if you survive
	log_msg("GAUNTLET CLEARED! Legendary spheres + effigies + gold")
	floater(player.pos, "GAUNTLET CLEARED!", "#ffd76e")

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
		if sg.get("id") == "generator":
			for w in sg["workers"]:
				if is_instance_valid(w) and w.san >= 15.0: # a slacking pal doesn't keep the lights on
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
			if st["id"] == "feed_box" and ItemData.ITEMS.get(iid, {}).get("food", 0) <= 0:
				skipped += c # feed boxes only take food — don't bury it under stone
				continue
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
		var nb := nearest_palbox(player.pos)
		player.pos = nearest_free(nb.x + 0.5, nb.y + 2.5)
	else: # no base yet: back to the landing point, not back into the jaws
		player.pos = nearest_free(world.spawn.x + 0.5, world.spawn.y + 0.5)
	log_msg("You wake up battered at base…")

func use_waypoint() -> void:
	# Palworld fast travel, bounded: a touched waypoint blinks you home —
	# outpost palboxes answer too, so pick whichever is closest
	if palbox_pos.x < 0:
		log_msg("The waypoint hums… but there's no palbox to answer")
		return
	var nb := nearest_palbox(player.pos)
	player.pos = nearest_free(nb.x + 0.5, nb.y + 2.5)
	player.sync_screen()
	floater(player.pos, "blink!", "#7fc8f8")
	log_msg("The waypoint pulls you back to base")

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
	var behind: bool = sign(player.pos.x - target.pos.x) == -target.dir # behind = player opposite the facing side
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var cap_pow: float = target.spec["capturePower"] * (1.35 if target.lucky else 1.0) # luckies resist
	var chance: float = minf(0.97, Combat.catch_chance(hp_frac, cap_pow,
		ItemData.ITEMS[sp["sid"]].get("spherePower", 26), target.any_status(), behind, player.capture_level))
	if randf() < chance:
		if party.size() >= 5 and box.size() >= MAX_BOX: # backstop: an over-stuffed box is real memory
			floater(target.pos, "BOX FULL", "#e8963c")
			log_msg("Palbox is full (%d) - can't store %s" % [MAX_BOX, target.spec["name"]])
			target.aggro = -1
			return
		floater(target.pos, "★ CAUGHT!", "#4dd0e1")
		log_msg("Caught %s Lv%d!" % [target.spec["name"], target.level])
		gain_xp(target.level * 3)
		# Palworld catch-count bonus: every 10th of a species pays a fat bonus
		catch_counts[target.species_id] = catch_counts.get(target.species_id, 0) + 1
		if catch_counts[target.species_id] % 10 == 0:
			var bonus := target.level * 8
			gain_xp(bonus)
			floater(target.pos, "CATCH x%d! +%dxp" % [catch_counts[target.species_id], bonus], "#ffd76e")
			log_msg("%dth %s caught - bonus XP!" % [catch_counts[target.species_id], target.spec["name"]])
		target.statuses.clear()
		target.aggro = -1
		if party.size() < 5: # Palworld rule: catch joins the party until it's full
			target.mode = "partner"
			party.append(target.uid)
			log_msg("%s joins your party (%d/5)" % [target.spec["name"], party.size()])
		else:
			target.mode = "box"
			box.append(target)
			pals.erase(target)
			box_pal(target)
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
	if drops.size() >= MAX_DROPS:
		take_drop(drops.front()) # flood backstop: oldest bag evaporates
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

func take_medicine(from_bag: bool) -> bool:
	# sick pals self-medicate (Palworld): partner eats from the player's bag,
	# base workers pull from the feed box / any chest holding medicine.
	if from_bag:
		for id in items.keys():
			if items[id] > 0 and ItemData.ITEMS.get(id, {}).get("kind") == "medicine":
				add_item(id, -1)
				return true
		return false
	var best = null; var best_id := ""; var best_v := 1 << 30
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] not in ["feed_box", "chest"]:
			continue
		for id in st.get("store", {}).keys():
			var hv: int = ItemData.ITEMS.get(id, {}).get("heal", 0)
			if ItemData.ITEMS.get(id, {}).get("kind") == "medicine" and st["store"][id] > 0 and hv < best_v:
				best_v = hv; best_id = id; best = st
	if best == null:
		return false
	best["store"][best_id] -= 1
	if best["store"][best_id] <= 0:
		best["store"].erase(best_id)
	return true

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

func _process(dt: float) -> void:
	t += dt
	tod += dt / DAY_LEN * 24.0
	if tod >= 24.0:
		tod -= 24.0
		day += 1

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
	tick_merchant(dt)
	tick_boss_respawns()
	tick_gauntlet()
	tick_repairs(dt)
	tick_crafts(dt)
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
	if sid == "palbox" and has_structure("palbox"):
		return false # one base only — ghost must agree with place_structure
	var w: int = s.get("w", 2)
	var h: int = s.get("h", 2)
	if not world.flat_at(tx, ty, w, h):
		return false
	for dy in range(h):
		for dx in range(w):
			var cx0 := tx + dx; var cy0 := ty + dy
			if not world.in_bounds(cx0, cy0):
				return false
			if world.tile_at(cx0, cy0) == World.Tile.WATER:
				return false
			if structures.has(Vector2i(cx0, cy0)):
				return false
			var dc: int = world.decor[world.idx(cx0, cy0)]
			if dc in [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL]:
				return false # trees/bushes clear themselves; outcrops don't
	return true

func palbox_count() -> int:
	var seen := []
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] == "palbox" and st not in seen:
			seen.append(st) # footprint cells share one st dict — dedupe
	return seen.size()

func nearest_palbox(at: Vector2) -> Vector2i:
	var best := palbox_pos
	var bd := INF
	if palbox_pos.x >= 0:
		bd = at.distance_to(Vector2(palbox_pos))
	for bx2 in extra_boxes:
		var dd := at.distance_to(Vector2(bx2))
		if dd < bd:
			bd = dd; best = bx2
	return best

const MAX_STRUCTURES := 400 # build cap: dicts keyed per-cell; 400 bases is already silly

func place_structure(sid: String, tx: int, ty: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES[sid]
	if sid == "palbox" and palbox_count() >= 1 + MAX_EXTRA_BOXES:
		log_msg("Max %d palboxes (base + outposts)" % (1 + MAX_EXTRA_BOXES))
		return false
	var seen_st := []
	for k in structures:
		if structures[k] not in seen_st:
			seen_st.append(structures[k]) # dedupe footprint cells → true count
	if seen_st.size() >= MAX_STRUCTURES:
		log_msg("Build limit reached (%d)" % MAX_STRUCTURES)
		return false
	for c in s.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg("Need %d %s" % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])])
			return false
	var e0: int = world.elev_at(tx, ty)
	for dy0 in range(s.get("h", 2)):
		for dx0 in range(s.get("w", 2)):
			if not world.in_bounds(tx + dx0, ty + dy0):
				log_msg("Can't build off the map")
				return false
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				log_msg("Blocked: something already built there")
				return false
			if world.decor[world.idx(tx + dx0, ty + dy0)] in [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL]:
				log_msg("Can't build on exposed rock")
				return false # ore/rock outcrops are terrain — clear trees but not these
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
	if spr.texture == null: # missing art must not crash placement (or orphan the node)
		spr.texture = load("res://assets/structures/chest.png")
	var w: int = s.get("w", 2)
	var h: int = s.get("h", 2)
	var p := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
	spr.position = Vector2(p.x, p.y - spr.texture.get_height() * 0.5 + 8)
	entity_layer.add_child(spr)
	if s.get("light", 0) > 0:
		add_glow(spr, s["light"])
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {},
		"hp": s.get("hp", 4000 if s.get("anchor", false) else 200),
		"walkable": s.get("walkable", false), "spike": s.get("spike", 0)}
	for dy in range(h):
		for dx in range(w):
			var ci0 := world.idx(tx + dx, ty + dy)
			if world.decor[ci0] != World.Decor.NONE: # trees/berries under the footprint are cleared
				world.decor[ci0] = World.Decor.NONE
				world.hp[ci0] = 0
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[ci0] = st
	if sid == "palbox":
		if palbox_pos.x < 0:
			palbox_pos = Vector2i(tx, ty)
			log_msg("Base established! Assign pals with F.")
		else:
			extra_boxes.append(Vector2i(tx, ty))
			log_msg("Outpost palbox online — shared box network")
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
			if not world.in_bounds(tx + dx0, ty + dy0):
				return false
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				return false
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/structures/%s.png" % sid)
	if spr.texture == null: # missing art must not crash placement (or orphan the node)
		spr.texture = load("res://assets/structures/chest.png")
	var p := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
	spr.position = Vector2(p.x, p.y - spr.texture.get_height() * 0.5 + 8)
	entity_layer.add_child(spr)
	if s.get("light", 0) > 0:
		add_glow(spr, s["light"])
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {},
		"hp": s.get("hp", 4000 if s.get("anchor", false) else 200),
		"walkable": s.get("walkable", false), "spike": s.get("spike", 0)}
	for dy in range(h):
		for dx in range(w):
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[world.idx(tx + dx, ty + dy)] = st
	if sid == "palbox":
		var o := Vector2i(tx, ty)
		if palbox_pos.x < 0:
			palbox_pos = o
		elif o != palbox_pos and o not in extra_boxes:
			extra_boxes.append(o)
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
	st["store"] = {} # refunded — an open chest panel must not re-withdraw these
	for c in StructureData.STRUCTURES[sid].get("cost", []):
		add_item(c[0], int(ceil(c[1] * 0.5)))
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null # the panel's container just died — stop referencing it
	if sid == "palbox":
		var origin: Vector2i = cells[0]
		for cc in cells:
			if cc.x < origin.x or (cc.x == origin.x and cc.y < origin.y):
				origin = cc
		if origin == palbox_pos:
			palbox_pos = extra_boxes.pop_front() if not extra_boxes.is_empty() else Vector2i(-1, -1)
			if palbox_pos.x >= 0:
				log_msg("Outpost promoted to primary base")
		else:
			extra_boxes.erase(origin)
	log_msg("Demolished %s (50%% refund)" % StructureData.STRUCTURES[sid]["name"])
	return true

# raiders chew on the base itself (Palworld): structures carry hp and drop
# their contents when razed. The palbox is hardened — losing the anchor
# would orphan every base pal's job and the respawn point.
func tick_repairs(dt: float) -> void:
	# Palworld: free hands patch the base up — idle handiwork-suitable pals
	# slowly mend damaged structures (assigned pals are busy elsewhere)
	var fixers := 0.0
	for q in pals:
		if q.mode == "base" and q.hp > 0 and q.san >= 15.0 and q.job_site == null \
				and not q.has_status("sleep") \
				and q.spec.get("work", {}).get("handiwork", 0) > 0:
			fixers += 1.0
	if fixers <= 0.0:
		return
	var seen := []
	for k in structures:
		var st: Dictionary = structures[k]
		if st in seen:
			continue # footprint cells share one st dict
		seen.append(st)
		var sd: Dictionary = StructureData.STRUCTURES.get(st["id"], {})
		var mx: float = float(sd.get("hp", 4000 if sd.get("anchor", false) else 200))
		if st.get("hp", mx) < mx:
			st["hp"] = minf(mx, st.get("hp", mx) + 4.0 * fixers * dt)

func hit_structure(cell: Vector2i, dmg: int) -> void:
	var st = structures.get(cell)
	if st == null:
		return
	var anchor: bool = StructureData.STRUCTURES.get(st["id"], {}).get("anchor", false)
	if anchor: # the palbox holds every stored pal — losing it would orphan the box
		st["hp"] = maxf(1.0, st.get("hp", 4000) - dmg)
		floater(Vector2(cell.x + 0.5, cell.y + 0.5), "ANCHORED", "#4dd0e1")
		return
	st["hp"] = st.get("hp", 200) - dmg
	floater(Vector2(cell.x + 0.5, cell.y + 0.5), "-%d" % dmg, "#e8963c")
	if st["hp"] <= 0:
		raze_structure(st)

func raze_structure(st) -> void:
	var sid: String = st.get("id", "?")
	var cells := []
	for k in structures:
		if structures[k] == st:
			cells.append(k)
	for w in st["workers"].duplicate():
		st["workers"].erase(w)
		w.job_site = null
	for it in st.get("store", {}).keys(): # contents spill as loot — no vanishing stock
		if not cells.is_empty():
			spawn_drop(it, st["store"][it], Vector2(cells[0].x + 0.5, cells[0].y + 0.5))
	st["store"] = {}
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	if is_instance_valid(st.get("node")):
		st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null
	if sid == "palbox":
		palbox_pos = Vector2i(-1, -1)
	log_msg("%s was destroyed in the raid!" % StructureData.STRUCTURES.get(sid, {}).get("name", sid))

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
	if item_count("ancient_part") < t.get("parts", 0): # ancient-tech nodes eat boss drops
		log_msg("Need %d ancient parts" % t.get("parts", 0))
		return
	if int(t.get("parts", 0)) > 0:
		add_item("ancient_part", -int(t["parts"]))
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
	if queue_crafts and stn != "hand":
		# Palworld bench rule: station crafts take real time; idle handy base
		# pals pitch in and hurry the queue along
		if craft_queue.size() >= MAX_CRAFT_QUEUE:
			log_msg("Craft queue is full")
			return
		for c in r.get("cost", []):
			add_item(c[0], -c[1])
		var costs := []
		for c in r.get("cost", []):
			costs.append([c[0], c[1]])
		craft_queue.append({"out": r["out"][0], "n": r["out"][1],
			"left": float(r.get("work", 20)) / 10.0, "cost": costs})
		log_msg("Crafting %s… (%ds)" % [ItemData.ITEMS[r["out"][0]]["name"],
			int(craft_queue.back()["left"])])
		return
	for c in r.get("cost", []):
		add_item(c[0], -c[1])
	add_item(r["out"][0], r["out"][1])
	log_msg("Crafted %s x%d" % [ItemData.ITEMS[r["out"][0]]["name"], r["out"][1]])

func tick_crafts(dt: float) -> void:
	if craft_queue.is_empty():
		return
	# idle handiwork-suitable base pals hurry the bench — 1.5x per helper
	var helpers := 0.0
	for q in pals:
		if q.mode == "base" and q.hp > 0 and q.job_site == null \
				and not q.has_status("sleep") \
				and q.spec.get("work", {}).get("handiwork", 0) > 0:
			helpers += 1.0
	var speed := 1.0 + 0.5 * helpers
	for i in range(craft_queue.size() - 1, -1, -1):
		var cq: Dictionary = craft_queue[i]
		cq["left"] -= dt * speed
		if cq["left"] <= 0:
			add_item(cq["out"], cq["n"])
			log_msg("Crafted %s x%d" % [ItemData.ITEMS[cq["out"]]["name"], cq["n"]])
			craft_queue.remove_at(i)

func pal_gain_xp(q: Pal, n: int) -> void:
	if q.hp <= 0 or n <= 0:
		return
	q.xp += n
	while q.xp >= q.level * 25:
		q.xp -= q.level * 25
		if q.level >= 60: # cap — surplus xp just burns off
			q.xp = 0
			break
		q.level += 1
		q.apply_bonuses() # recompute max_hp incl star/alpha/boss
		q.hp = q.max_hp
		log_msg("%s grew to Lv%d!" % [q.spec["name"], q.level])

func gain_xp(n: int) -> void:
	n = int(n * (1.0 + perks["xp"] * 0.08))
	for q in pals:
		if q.mode == "partner":
			pal_gain_xp(q, int(n * 0.5))
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
	var powered := 1.5 if generator_active() else 1.0 # one check — the SAN-aware helper
	var stand := 1.4 if has_structure("monitoring_stand") else 1.0 # overseer speed-up
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
		if st["id"] == "incubator":
			var inc = st.get("egg_inc")
			if inc is Dictionary and t >= float(inc.get("ready_t", 0.0)):
				hatch_incubated(key, st)
			continue
		if st.get("spike", 0) > 0:
			st["timer"] += dt # damage hostiles standing on the spikes every half second
			if st["timer"] >= 0.5:
				st["timer"] = 0.0
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and (p.raid or p.aggro >= 0) \
							and Vector2i(int(p.pos.x), int(p.pos.y)) == key:
						p.take_dps(int(st["spike"]))
		var prod: Array = job.get("produces", [])
		var active: Array = st["workers"].filter(func(w): return w.san >= 15.0 and not w.has_status("sleep"))
		if prod.is_empty() or active.is_empty():
			continue
		var cons: Array = job.get("consumes", [])
		if not cons.is_empty() and not consume_ready(cons):
			continue # starved for inputs — no free production
		var work_sum := 0.0 # each worker contributes by its Artisan/etc passives; sick pals drag
		for w in active:
			work_sum += w.passive_mult("work") * w.work_mult()
		st["timer"] += (dt * (1.0 + perks["work"] * 0.1)) * powered * stand * work_sum
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
			for w in active: # Palworld: base workers level from honest work
				pal_gain_xp(w, 3)
			for pr in prod: # goods pile up at the site; haulers move them
				st["store"][pr[0]] = st["store"].get(pr[0], 0) + pr[1]
			var t := ""
			for pr in prod:
				t += "+%d %s  " % [pr[1], pr[0]]
			floater(Vector2(key.x + 0.5, key.y + 0.5), t.strip_edges(), "#a8e6a1")

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

func make_active(uid: int) -> void:
	# Palworld "send out": reorder the party so this pal leads — partner
	# skills, mounts, skill fruits and the condenser all key on party[0]
	var i := party.find(uid)
	if i <= 0:
		return
	party.remove_at(i)
	party.push_front(uid)
	var mp := find_pal(uid)
	log_msg("%s leads the party" % (mp.spec["name"] if mp else "?"))

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
	bp.pos = nearest_free(player.pos.x + 1.2, player.pos.y) # box-out must not land inside a cliff/lake
	unbox_pal(bp) # box pals live under box_holder — move them back to the world
	log_msg("%s joined %s" % [bp.spec["name"], bp.mode])

const MAX_BASE_PALS := 20 # absolute workforce cap — more mouths than this starve the loop anyway

func max_base_pals() -> int:
	# Palworld palbox growth: workforce slots scale with the player's level
	# (8+lvl, hard-capped by MAX_BASE_PALS) instead of one static number
	return mini(8 + player.level, MAX_BASE_PALS)

func deploy_to_base(p: Pal) -> void:
	# Palworld: drop a pal at the palbox and it joins the base workforce
	if p.hp <= 0:
		log_msg("%s is KO'd - wait for it to recover" % p.spec["name"])
		return
	if palbox_pos.x < 0:
		log_msg("Need a palbox to deploy pals")
		return
	if base_pals().size() >= max_base_pals() and p.mode != "base":
		log_msg("Base is full (%d pals — level up for more slots)" % max_base_pals())
		return
	player.dismount_if(p)
	party.erase(p.uid)
	box.erase(p)
	if p.mode == "box":
		unbox_pal(p) # back into the live tree before it starts working
	if p not in pals:
		pals.append(p)
	p.mode = "base"
	p.job_site = null
	var db := nearest_palbox(p.pos)
	p.pos = nearest_free(db.x + 2.0, db.y + 2.5)
	log_msg("%s deployed at base" % p.spec["name"])

func base_to_box(p: Pal) -> void:
	# recall a worker into cold storage — job and cargo are dropped first
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null
	if p.carry != null:
		add_item(p.carry["id"], p.carry["n"])
		p.carry = null
	pals.erase(p)
	p.mode = "box"
	box.append(p)
	box_pal(p)
	log_msg("%s -> box" % p.spec["name"])

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
	box_pal(p)
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
		if jb.get("produces", []).is_empty() and structures[k]["id"] != "ranch" and jb.get("kind") != "power":
			continue # sites with no output aren't assignable (except generator/ranch) — campfire's [] sneaks past a null check
		var need: String = jb.get("workType", "")
		if need != "" and best.spec.get("work", {}).get(need, 0) == 0 \
				and not (s.get("farmField", false) and best.spec.get("work", {}).get("watering", 0) > 0):
			continue  # can't work this site — farm fields also take waterers (Palworld)
		if structures[k]["workers"].size() >= 4:
			continue # site is fully crewed — piling more pals on one site scales unbounded
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
			# pass caster pos so elevation is actually checked — 2-arg blocked skips it
			if not world.blocked(int(land.x), int(land.y), caster.pos.x, caster.pos.y):
				caster.pos = land
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
			if projectiles.size() >= MAX_PROJECTILES:
				var old = projectiles.pop_front()
				if is_instance_valid(old.get("node")):
					old["node"].queue_free() # volley backstop: oldest shot fizzles
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
		var final := maxi(1, int(sk.get("power", 10) * 0.6) - player.armor_def())
		player.hp -= final
		player.hit_flash = 0.4
		floater(player.pos, "-" + str(final), "#e64533") # show post-armor damage like hurt_player
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
		var d := Combat.damage(Combat.stat_at(caster.spec["atk"], caster.level, caster.talent) * caster.atk_bonus * caster.atk_mult(),
			sk.get("power", 10), Combat.stat_at(tp.spec["def"], tp.level, tp.talent) * tp.def_bonus * tp.def_mult(), mult, rng)
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
						var d := Combat.damage(pr["dmg"] * 2.0, 20, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus * p.def_mult(), mult, rng)
						p.hit(d, mult, true)
						dead = true
						break
			if dead:
				n.queue_free()
				projectiles.erase(pr)
			continue
		var caster: Pal = pr["from"]
		if not is_instance_valid(caster): # caster died while the shot was in flight
			dead = true
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
			"star": p.star, "xp": p.xp, "raid": p.raid, "ail": p.ailment,
			"lucky": p.lucky, "extra": p.extra_skills,
			"rt0": t - p.get_meta("raid_t0", t) if p.raid else 0.0})
	for bp in box:
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "box", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "carry": bp.carry,
			"ail": bp.ailment, "lucky": bp.lucky, "extra": bp.extra_skills,
			"revive": maxf(0.0, bp.revive_t - t)})
	var structs := {}
	var seen_st := {} # one entry per structure — footprint cells share a st; writing
	# them as separate records made rebuild order-dependent and ate buildings
	for k in structures:
		var st = structures[k]
		if seen_st.has(st):
			continue
		seen_st[st] = true
		var inc = st.get("egg_inc")
		structs["%d,%d" % [k.x, k.y]] = {"id": st["id"], "store": st.get("store", {}), "egg": st.get("egg_parents"), "timer": st.get("timer", 0.0), "hp": st.get("hp", 200),
			"inc": ({"pair": inc.get("pair"), "left": maxf(0.0, float(inc.get("ready_t", 0.0)) - t)} if inc is Dictionary else null)}
	var d := {
		"seed": world.seed, "day": day, "tod": tod, "tech_points": tech_points,
		"raid_t": raid_t,
		"unlocked": unlocked, "items": items, "party": party,
		"party_idx": party.map(func(u): return pals.find(find_pal(u))),
		"perks": perks, "equip": player.equipment,
		"pals": pals_data, "structures": structs, "catches": catch_counts,
		"drops": drops.map(func(dd): return {"id": dd["id"], "n": dd["n"], "x": dd["pos"].x, "y": dd["pos"].y}),
		"crafts": craft_queue.slice(0, MAX_CRAFT_QUEUE).map(
			func(cq): return {"out": cq["out"], "n": cq["n"], "left": cq["left"]}),
		"respawns": boss_respawns.slice(0, MAX_RESPAWNS).map(
			func(br):
				var r: Dictionary = br.duplicate()
				r["at"] = maxf(0.0, br["at"] - t) # store remaining time — t restarts on load
				return r),
		"pbx": [palbox_pos.x, palbox_pos.y], # which palbox is primary
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
	for req in ["day", "tod", "tech_points", "unlocked", "items", "party", "player", "pals", "structures"]:
		if not d.has(req):
			log_msg("Save missing field '%s' - starting fresh" % req)
			return false # below this point every field is assumed present
	if d["player"] is not Dictionary or d["pals"] is not Array or d["structures"] is not Dictionary \
			or d["items"] is not Dictionary or d["party"] is not Array or d["unlocked"] is not Array:
		log_msg("Save has wrong field types - starting fresh")
		return false
	player.mount = null # pals are about to be freed and rebuilt — mount ref would dangle
	despawn_merchant() # the trader's stock and node don't cross a load
	for p in pals:
		p.queue_free()
	pals.clear()
	for bp1 in box: # box pals aren't in the scene tree — clear() alone leaks them
		bp1.free()
	box.clear()
	for pr in projectiles:
		pr["node"].queue_free()
	projectiles.clear()
	for sp0 in spheres_flying: # sphere sprites + stale targets must not cross a load
		if is_instance_valid(sp0["node"]):
			sp0["node"].queue_free()
	spheres_flying.clear()
	for dd0 in drops:
		if is_instance_valid(dd0["node"]):
			dd0["node"].queue_free()
	drops.clear()
	gauntlet = {} # a save can't pause mid-trial — survivors stay plain raiders
	for k in structures.keys():
		structures[k]["node"].queue_free()
	structures.clear()
	world.structures.clear()
	world.generate(d["seed"])
	if d.get("decor") is PackedByteArray and d["decor"].size() == world.decor.size() \
			and d.get("hp_map") is PackedByteArray and d["hp_map"].size() == world.hp.size():
		world.decor = d["decor"]
		world.hp = d["hp_map"]
	else: # world size/type changed since this save — keep fresh terrain, skip stale layout
		log_msg("Save layout predates the current world format - fresh terrain")
	queue_redraw_decor() # decor pool still holds the pre-load world's sprites
	day = maxi(int(d["day"]), 1); tod = clampf(float(d["tod"]), 0.0, 24.0) # typed vars — a foreign string would throw on assignment; tod>24 would fast-forward a day per frame until under 24
	raid_t = float(d.get("raid_t", raid_t))
	for dd0 in d.get("drops", []):
		if dd0 is Dictionary and dd0.has("id") and dd0.has("x") and dd0.has("y") \
				and (dd0["x"] is float or dd0["x"] is int) and (dd0["y"] is float or dd0["y"] is int):
			spawn_drop(str(dd0["id"]), maxi(int(dd0.get("n", 1)), 0), Vector2(float(dd0["x"]), float(dd0["y"]))) # negative n would corrupt the item ledger
	boss_respawns.clear()
	for rb in d.get("respawns", []):
		if rb is Dictionary and rb.get("pos") is Array and boss_respawns.size() < MAX_RESPAWNS:
			var rr: Dictionary = rb.duplicate()
			rr["at"] = t + maxf(0.0, float(rb.get("at", DAY_LEN))) # saved as remaining → back to absolute
			boss_respawns.append(rr)
	craft_queue.clear()
	for rc in d.get("crafts", []):
		if rc is Dictionary and ItemData.ITEMS.has(str(rc.get("out", ""))) \
				and craft_queue.size() < MAX_CRAFT_QUEUE:
			craft_queue.append({"out": str(rc["out"]), "n": maxi(int(rc.get("n", 1)), 0),
				"left": maxf(float(rc.get("left", 1.0)), 0.1), "cost": []})
	tech_points = maxi(int(d["tech_points"]), 0)
	unlocked = d["unlocked"].filter(func(u): return u is String)
	var saved_perks: Dictionary = d.get("perks", {})
	for pk in perks: # merge over defaults — a save missing a newer perk would poison every perks[k] read
		perks[pk] = int(saved_perks.get(pk, perks[pk]))
	catch_counts.clear()
	if d.get("catches") is Dictionary:
		for ck in d["catches"]:
			catch_counts[str(ck)] = maxi(int(d["catches"][ck]), 0) # foreign counts can't poison the %10 bonus
	var seq = d.get("equip", {})
	if seq is Dictionary: # merge over defaults — a foreign equip dict missing a slot would throw on equipment["slot"] reads
		for slot in ["weapon", "armor"]:
			var ev = seq.get(slot, "")
			player.equipment[slot] = str(ev) if ItemData.ITEMS.has(str(ev)) else "" # unknown ids equip to nothing
	items.clear() # element-wise int() — foreign saves can carry string counts that would break items[id]+n arithmetic later
	for ik in d["items"]:
		items[ik] = maxi(int(d["items"][ik]), 0) # negative inventory is corrupt state
	party.clear()
	for u in d["party"]: # typed-array assignment rejects untyped arrays from foreign saves
		party.append(int(u))
	var ppos = d["player"].get("pos", [player.pos.x, player.pos.y])
	if ppos is Array and ppos.size() >= 2 and (ppos[0] is float or ppos[0] is int) and (ppos[1] is float or ppos[1] is int):
		player.pos = Vector2(float(ppos[0]), float(ppos[1])) # corrupt pos keeps spawn point instead of aborting
	if not world.in_bounds(int(player.pos.x), int(player.pos.y)) or world.blocked(int(player.pos.x), int(player.pos.y)):
		player.pos = nearest_free(world.spawn.x + 0.5, world.spawn.y + 0.5) # OOB/blocked pos from a foreign save = softlock (every move rejected)
	player.hp = float(d["player"].get("hp", player.hp)); player.level = clampi(int(d["player"].get("level", 1)), 1, 60) # level<=0 makes derived max_hp negative
	player.xp = maxi(int(d["player"].get("xp", 0)), 0); player.capture_level = clampi(int(d["player"].get("cap_lv", 1)), 1, 20)
	player.hunger = clampf(float(d["player"].get("hunger", player.hunger)), 0.0, 100.0)
	player.max_hp = 100 + (player.level - 1) * 10 + perks.get("hp", 0) * 12 # never saved — derive it
	player.hp = minf(player.hp, player.max_hp)
	var pending_jobs := []
	for pd in d["pals"]:
		if pd is not Dictionary:
			continue # corrupt entry — keep loading the rest
		if SpeciesData.species_of(pd.get("sp", "")).is_empty():
			log_msg("Skipped unknown species in save: %s" % pd.get("sp", "?"))
			continue # corrupt entry — don't crash on spec lookups
		var ppos2 = pd.get("pos", [player.pos.x, player.pos.y])
		if ppos2 is not Array or ppos2.size() < 2 or not (ppos2[0] is float or ppos2[0] is int) or not (ppos2[1] is float or ppos2[1] is int):
			continue # no usable position — drop the entry
		if not world.in_bounds(int(ppos2[0]), int(ppos2[1])):
			if str(pd.get("mode", "")) == "box":
				ppos2 = [player.pos.x, player.pos.y] # box pals are never in the world — pos is a placeholder anyway
			else:
				ppos2 = [world.spawn.x, world.spawn.y] # OOB pal could never move again — re-anchor at spawn, don't delete it
		var np := preload("res://src/pal.gd").new()
		np.setup(self, pd["sp"], clampi(int(pd.get("lv", 1)), 1, 60), Vector2(float(ppos2[0]), float(ppos2[1]))) # lv<=0 makes stat_at return negative max_hp — an instant corpse
		np.home = np.pos # loaded pals re-anchor at their saved spot
		var m0 := str(pd.get("mode", "wild"))
		np.mode = m0 if m0 in ["wild", "partner", "base", "box"] else "wild" # foreign strings would poison every mode check
		np.hp = float(pd.get("hp", np.max_hp)); np.talent = clampi(int(pd.get("talent", np.talent)), 0, 100) # talent outside [0,100] flips stat_at's multiplier negative
		if pd.get("sex") != null:
			np.sex = "F" if str(pd["sex"]) == "F" else "M"
		if pd.get("passives") is Array:
			np.passives = pd["passives"].filter(func(k): return PassiveData.PASSIVES.has(k)) # drop passives removed in newer builds
		if pd.get("alpha"):
			np.alpha = true
			np.sprite.scale = Vector2(1.6, 1.6)
		if pd.get("boss") is bool:
			np.boss = pd["boss"] # only a real bool assigns — GDScript has no bool() ctor and String==true throws
		np.san = clampf(float(pd.get("san", np.san)), 0.0, 200.0)
		np.hunger = clampf(float(pd.get("hunger", 0.0)), 0.0, 100.0)
		var cv2 = pd.get("carry")
		if cv2 is Dictionary and cv2.has("id") and (cv2.get("n", 0) is float or cv2.get("n", 0) is int):
			np.carry = {"id": str(cv2["id"]), "n": maxi(int(cv2["n"]), 0)} # haul_ai reads carry["id"]/carry["n"] — a dict missing either crashes every frame
		else:
			np.carry = null
		np.star = clampi(int(pd.get("star", 0)), 0, 4) # CONDENSE_COST tops at 4 — a foreign star=999 makes pow(1.15,999) overflow the stat line
		np.xp = maxi(int(pd.get("xp", 0)), 0)
		if pd.get("raid") is bool:
			np.raid = pd["raid"]
		var al := str(pd.get("ail", ""))
		if al in Pal.AILMENTS:
			np.ailment = al # unknown/blank ailments fall to healthy
		if pd.get("lucky") is bool:
			np.lucky = pd["lucky"]
		if np.lucky and "lucky" not in np.passives:
			np.passives.append("lucky") # setup() ran before the flag landed — inject its passive here
		if pd.get("extra") is Array:
			np.extra_skills = pd["extra"].filter(func(k): return SkillData.SKILLS.has(k)) # drop skills removed in newer builds
		if np.lucky:
			np.sprite.scale = Vector2(1.5, 1.5)
			np.sprite.position.y = -48.0
		if np.raid:
			np.set_meta("raid_t0", t - float(pd.get("rt0", 0.0))) # preserve despawn countdown
		var rvs = pd.get("revive", 0.0)
		np.revive_t = t + float(rvs) if (rvs is float or rvs is int) and float(rvs) > 0.0 else 0.0 # revive_t=t+0 fires the moment the pal later enters the box — wiping a healthy pal to 30% hp
		np.apply_bonuses()
		if pd.get("job") is String:
			pending_jobs.append([np, pd["job"]])
		if np.mode == "box":
			box.append(np)
			box_pal(np) # box pals live under the hidden holder — never parentless
		else:
			entity_layer.add_child(np)
			pals.append(np)
	if d.has("party_idx"):
		party.clear()
		for pi in d["party_idx"]:
			if pi is int and pi >= 0 and pi < pals.size():
				party.append(pals[pi].uid)
	else: # pre-party_idx saves stored raw uids — new pals got fresh uids, so old refs are dead
		party = party.filter(func(u): return find_pal(u) != null)
	var pbx_sv := Vector2i(-9999, -9999) # saved primary palbox, if the save is new enough
	var pv = d.get("pbx", [])
	if pv is Array and pv.size() >= 2:
		pbx_sv = Vector2i(int(pv[0]), int(pv[1]))
	palbox_pos = Vector2i(-1, -1) # rebuilt below — stale state must not skip the first palbox
	extra_boxes.clear()
	for ks in d["structures"]:
		var parts: PackedStringArray = ks.split(",")
		if parts.size() < 2:
			continue # malformed cell key — skip rather than abort the load
		var sv = d["structures"][ks]
		var sid: String = str(sv.get("id", "")) if sv is Dictionary else str(sv)
		if not StructureData.STRUCTURES.has(sid):
			log_msg("Skipped unknown structure in save: %s" % sid)
			continue # structure type removed in a newer build — don't brick the load
		var s: Dictionary = StructureData.STRUCTURES[sid]
		var tx := int(parts[0]); var ty := int(parts[1])
		var ww: int = s.get("w", 2); var hh: int = s.get("h", 2)
		if tx < 0 or ty < 0 or tx + ww > World.WORLD_W or ty + hh > World.WORLD_H:
			continue # OOB footprint would register junk cells in world.structures and park a sprite off-map
		if structures.has(Vector2i(tx, ty)):
			continue  # footprint cell of an already-rebuilt structure
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/structures/%s.png" % sid)
		if spr.texture == null: # a bad texture must not abort the rest of the load
			spr.texture = load("res://assets/structures/chest.png")
		var w: int = s.get("w", 2); var h: int = s.get("h", 2)
		var pp := Iso.to_screen(tx + w * 0.5, ty + h * 0.5, world.elev_at(tx, ty))
		spr.position = Vector2(pp.x, pp.y - spr.texture.get_height() * 0.5 + 8)
		entity_layer.add_child(spr)
		var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": {},
			"hp": clampi(int(sv.get("hp", 200)) if sv is Dictionary else 200, 1, 99999),
			"walkable": s.get("walkable", false), "spike": s.get("spike", 0)}
		if sv is Dictionary:
			if sv.get("store") is Dictionary:
				for sk2 in sv["store"]: # counts used in +/- arithmetic everywhere — coerce, skip junk
					var cv = sv["store"][sk2]
					if cv is float or cv is int:
						st["store"][str(sk2)] = maxi(int(cv), 0) # negative stock would make chest math lie
			st["timer"] = maxf(float(sv.get("timer", 0.0)), 0.0) # negative timer fires production instantly; st["timer"] += dt arithmetic follows — a string would throw
			if sv.get("egg"):
				st["egg_parents"] = sv["egg"]
			if sv.get("inc") is Dictionary and sid == "incubator":
				var inc_d: Dictionary = sv["inc"]
				st["egg_inc"] = {"pair": inc_d.get("pair"), "ready_t": t + maxf(float(inc_d.get("left", 30.0)), 1.0)}
		for dy in range(h):
			for dx in range(w):
				structures[Vector2i(tx + dx, ty + dy)] = st
				world.structures[world.idx(tx + dx, ty + dy)] = st
		if sid == "palbox":
			var o := Vector2i(tx, ty)
			if o == pbx_sv:
				if palbox_pos.x >= 0 and palbox_pos != o and palbox_pos not in extra_boxes:
					extra_boxes.append(palbox_pos) # earlier guess demoted
				palbox_pos = o
			elif palbox_pos.x < 0:
				palbox_pos = o
			elif o != palbox_pos and o not in extra_boxes and extra_boxes.size() < MAX_EXTRA_BOXES:
				extra_boxes.append(o)
	for pj in pending_jobs:
		var parts2: PackedStringArray = pj[1].split(",")
		if parts2.size() < 2:
			continue # malformed job cell key
		var cell := Vector2i(int(parts2[0]), int(parts2[1]))
		if structures.has(cell) and pj[0].mode == "base" and pj[0] not in structures[cell]["workers"]:
			structures[cell]["workers"].append(pj[0])
			pj[0].job_site = structures[cell]
	log_msg("Loaded.")
	return true

func start_raid() -> void:
	var c := Vector2(palbox_pos.x + 0.5, palbox_pos.y + 0.5)
	# Palworld escalation: raids grow with the campaign — bigger packs and
	# meaner levels as days pass, both capped so day-40 stays survivable
	var day_bonus := mini(day, 20)
	var n := 3 + rng.int_range(0, 2) + mini(day / 4, 4)
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
			rp.setup(self, sid, rng.int_range(4 + zone * 4 + day_bonus, 8 + zone * 6 + day_bonus), Vector2(tx + 0.5, ty + 0.5))
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
	# grazing produce (Palworld): every ranch pal drops its species good on its
	# own timer — wool, eggs, milk, gold — independent of the breeding pair.
	var ft: Dictionary = st.get("farm_t", {})
	st["farm_t"] = ft
	for w in st["workers"]:
		if not is_instance_valid(w) or w.mode != "base" or w.san < 15.0 or w.has_status("sleep"):
			continue
		var fm: Dictionary = w.spec.get("farm", {})
		if fm.is_empty():
			continue
		var acc: float = ft.get(w.uid, 0.0) + dt
		if acc >= float(fm.get("per", 60)):
			acc = 0.0
			st["store"][fm["item"]] = st["store"].get(fm["item"], 0) + 1
			floater(Vector2(key.x + 0.5, key.y + 0.5), "+%s" % fm["item"], "#a8e6a1")
		ft[w.uid] = acc
	for u2 in ft.keys(): # keep the ledger tight — workers come and go
		var still := false
		for w in st["workers"]:
			if is_instance_valid(w) and w.uid == u2:
				still = true
		if not still:
			ft.erase(u2)
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
	# Palworld rule: breeding burns a cake per egg, pulled from base storage
	if not consume_ready([["cake", 1]]):
		if not st.get("cake_warned", false):
			st["cake_warned"] = true
			floater(Vector2(key.x + 0.5, key.y + 0.5), "needs cake!", "#f2a0b5")
			log_msg("Ranch needs a cake (chest/feed box) to breed")
		st["timer"] = 0.0
		return
	st["cake_warned"] = false
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
	pull_from_storage("cake", 1)
	if not st.has("egg_parents") or st["egg_parents"] == null:
		st["egg_parents"] = []
	if st["egg_parents"].size() >= MAX_EGG_QUEUE:
		st["egg_parents"].pop_front() # eggs get sold/eaten/destroyed — oldest parentage is expendable
	# parentage carries species, talent, passives AND the move pool
	# (Palworld: offspring can hatch knowing a parent's skill)
	st["egg_parents"].append([a.species_id, b.species_id, a.talent, b.talent,
		a.passives.duplicate(), b.passives.duplicate(),
		a.learned_skills(), b.learned_skills()])
	st["store"]["pal_egg"] = st["store"].get("pal_egg", 0) + 1 # lays AT the ranch; haulers collect
	floater(Vector2(key.x + 0.5, key.y + 0.5), "Egg!", "#f5e6c8")
	log_msg("%s + %s produced an egg!" % [a.spec["name"], b.spec["name"]])

func pull_from_storage(id: String, need: int) -> int:
	# shared consumer: production inputs and cake come out of chests/feed boxes
	var left := need
	for kc in structures:
		var sc: Dictionary = structures[kc]
		if sc["id"] not in ["chest", "feed_box"] or left <= 0:
			continue
		var take: int = mini(left, sc.get("store", {}).get(id, 0))
		if take > 0:
			sc["store"][id] -= take
			if sc["store"][id] <= 0:
				sc["store"].erase(id)
			left -= take
	return need - left

func deposit_egg() -> void:
	# Palworld: eggs go into an incubator; hatching takes real time
	if item_count("pal_egg") <= 0:
		return
	var site = null; var bd := 20.0
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] != "incubator" or st.has("egg_inc"):
			continue
		var dd := player.pos.distance_squared_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd < bd:
			bd = dd; site = k
	if site == null:
		log_msg("Need a free incubator nearby")
		return
	add_item("pal_egg", -1)
	var pair = null
	for k2 in structures:
		var q = structures[k2].get("egg_parents")
		if q is Array and q.size() > 0:
			pair = q.pop_front() # oldest egg's parentage
			break
	var dur := 90.0
	for k3 in structures: # a warm incubator runs faster (Palworld temperature rule)
		if structures[k3]["id"] == "campfire" and Vector2(k3.x, k3.y).distance_squared_to(Vector2(site.x, site.y)) < 36.0:
			dur = 60.0
			break
	structures[site]["egg_inc"] = {"pair": pair, "ready_t": t + dur}
	log_msg("Egg incubating - ready in %ds%s" % [int(dur), " (warm)" if dur < 90.0 else ""])

func hatch_incubated(key: Vector2i, st: Dictionary) -> void:
	var inc = st.get("egg_inc")
	st.erase("egg_inc")
	var pair = inc.get("pair") if inc is Dictionary else null
	var sp_id: String
	var talent_v: int
	var inherited := []
	if pair is Array and pair.size() >= 4:
		# Palworld breeding: signature pairings produce a fixed third species;
		# everything else inherits one of the two parents.
		var combo: String = BREED_COMBOS.get("%s+%s" % [pair[0], pair[1]],
			BREED_COMBOS.get("%s+%s" % [pair[1], pair[0]], ""))
		sp_id = combo if combo != "" else pair[rng.int_range(0, 1)]
		talent_v = clampi((int(pair[2]) + int(pair[3])) / 2 + rng.int_range(-15, 15), 0, 100)
		if pair.size() >= 6 and pair[4] is Array and pair[5] is Array:
			for pk in pair[4] + pair[5]: # Palworld: passives run in the bloodline
				if pk not in inherited:
					inherited.append(pk)
	else: # found egg with no recorded parentage — wild genetics
		var keys: Array = SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys()
		sp_id = keys[rng.int_range(0, keys.size() - 1)]
		talent_v = rng.int_range(0, 100)
	if SpeciesData.species_of(sp_id).is_empty() and SpeciesGen.SPECIES.get(sp_id, {}).is_empty():
		var keys2: Array = SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys()
		sp_id = keys2[rng.int_range(0, keys2.size() - 1)]
	var at: Vector2 = nearest_free(key.x + 1.0, key.y + 2.5) # don't hatch into a wall
	var np := preload("res://src/pal.gd").new()
	entity_layer.add_child(np)
	np.setup(self, sp_id, 1, at)
	np.talent = talent_v # setup() rolls a fresh talent — overwrite then re-derive stats
	np.passives.clear()
	for pk in inherited: # each bloodline passive passes down at 70%
		if PassiveData.PASSIVES.has(pk) and rng.chance(0.7):
			np.passives.append(pk)
	var keys_p := PassiveData.PASSIVES.keys()
	if np.passives.is_empty() or rng.chance(0.15): # mutation keeps breeding interesting
		var npk: String = keys_p[rng.int_range(0, keys_p.size() - 1)]
		if npk not in np.passives:
			np.passives.append(npk)
	np.apply_bonuses()
	np.hp = np.max_hp
	if pair is Array and pair.size() >= 8: # egg moves: hatch with a parent skill
		var pool_s: Array = (pair[6] if pair[6] is Array else []) + (pair[7] if pair[7] is Array else [])
		pool_s = pool_s.filter(func(k): return SkillData.SKILLS.has(k) and k not in np.learned_skills())
		if not pool_s.is_empty():
			np.extra_skills.append(pool_s[rng.int_range(0, pool_s.size() - 1)])
	if palbox_pos.x >= 0:
		np.mode = "base"
		pals.append(np)
	else: # no base: it goes straight to the box like any caught pal
		np.mode = "box"
		box.append(np)
		box_pal(np)
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
	spawn_legendary_den()
	spawn_grotto()
	spawn_nests()
	spawn_waypoints()
	log_msg("%d boss lairs marked deep in the world" % placed)

func spawn_waypoints() -> void:
	# Palworld fast-travel stones: a few fixed waypoints out in the world,
	# each a one-way blink back to your palbox once you've walked out
	var placed := 0
	var tries := 0
	while placed < 4 and tries < 4000:
		tries += 1
		var tx := rng.int_range(6, World.WORLD_W - 7)
		var ty := rng.int_range(6, World.WORLD_H - 7)
		if world.zone_at(tx, ty) < 1 or world.blocked(tx, ty) \
				or Vector2(tx + 0.5, ty + 0.5).distance_to(player.pos) < 20.0:
			continue
		var clash := false
		for k in structures:
			if Vector2(tx, ty).distance_to(Vector2(k.x, k.y)) < 6.0:
				clash = true
		if clash:
			continue
		if place_free("waypoint", tx, ty):
			placed += 1
	if placed > 0:
		log_msg("%d waypoints hum out in the wilds" % placed)

func spawn_nests() -> void:
	# Wild egg nests (Palworld): stealable pal_egg drops scattered past zone 1
	var placed := 0
	var tries := 0
	while placed < 7 and tries < 4000:
		tries += 1
		var tx := rng.int_range(4, World.WORLD_W - 5)
		var ty := rng.int_range(4, World.WORLD_H - 5)
		var at := Vector2(tx + 0.5, ty + 0.5)
		if world.zone_at(tx, ty) < 1 or world.blocked(tx, ty) \
				or at.distance_to(player.pos) < 15.0:
			continue
		spawn_drop("pal_egg", 1, at)
		placed += 1

var grotto_pos := Vector2i(-1, -1) # sealed dungeon marker (set at worldgen)
var grotto_room2 := Vector2i(-1, -1) # second chamber center, if the terrain fit it

func spawn_grotto() -> void:
	# Palworld dungeon flavour: a rock-sealed chamber in deep zone 3 — the only
	# way in is to break the wall (or fly a bird over it). Boss + loot inside.
	var tries := 0
	while tries < 6000:
		tries += 1
		var tx := rng.int_range(8, World.WORLD_W - 10)
		var ty := rng.int_range(8, World.WORLD_H - 10)
		if world.zone_at(tx, ty) < 3:
			continue
		var ok := true
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if world.blocked(tx + dx, ty + dy) or structures.has(Vector2i(tx + dx, ty + dy)):
					ok = false
		if not ok:
			continue
		# seal the chamber: a rock ring the player has to crack open
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dy)) == 3:
					var i2 := world.idx(tx + dx, ty + dy)
					world.decor[i2] = World.Decor.ROCK
					world.hp[i2] = 60
		# the warden: a zone-3 alpha boss, sphere-immune like all dungeon bosses
		var pool := SpeciesGen.zone_pool(3)
		if pool.is_empty():
			return
		var bp := preload("res://src/pal.gd").new()
		bp.alpha = true
		bp.boss = true
		entity_layer.add_child(bp)
		bp.setup(self, pool[rng.int_range(0, pool.size() - 1)], 40, Vector2(tx + 0.5, ty + 0.5))
		bp.home = bp.pos # anchored to its chamber
		pals.append(bp)
		# treasure chest pre-stocked like a dungeon reward
		if place_free("chest", tx + 1, ty + 1):
			var st: Dictionary = structures[Vector2i(tx + 1, ty + 1)]
			st["store"] = {"gold_coin": rng.int_range(20, 40), "mega_sphere": 3,
				"pal_egg": 1, "skill_fruit_" + ["neutral", "fire", "water", "grass",
				"electric", "ice", "ground", "dark", "dragon"][rng.int_range(0, 8)]: 1}
		grotto_pos = Vector2i(tx, ty)
		grotto_room2 = Vector2i(-1, -1)
		# second chamber (Palworld multi-room dungeon): a 5x5 treasure room in
		# any cardinal direction, joined by a 1-wide rock doorway. Meaner
		# warden, richer chest — optional when the terrain won't fit one.
		var bx := -1
		var by := ty
		var door_c: Vector2i
		for dir2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cx: int = tx + dir2.x * 7
			var cy: int = ty + dir2.y * 7
			if cx - 3 < 0 or cx + 3 >= World.WORLD_W or cy - 3 < 0 or cy + 3 >= World.WORLD_H:
				continue
			var fits2 := true
			for dy in range(-1, 2): # 3x3 interior must be open; ring cells become rock
				for dx in range(-1, 2):
					if world.blocked(cx + dx, cy + dy) or structures.has(Vector2i(cx + dx, cy + dy)):
						fits2 = false
			if fits2:
				bx = cx; by = cy
				door_c = Vector2i(tx + dir2.x * 4, ty + dir2.y * 4)
				break
		if bx < 0:
			log_msg("A sealed grotto echoes in the deep wilds")
			return
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if maxi(absi(dx), absi(dy)) == 2:
					var j := world.idx(bx + dx, by + dy)
					world.decor[j] = World.Decor.ROCK
					world.hp[j] = 60
		# doorway: rock chokepoints beside the gap leave a single-tile tunnel —
		# break or squeeze through to reach room 2. E/W doors choke N/S, N/S
		# doors choke E/W.
		var horiz := door_c.y == ty
		for off in [-1, 1]:
			var dc := door_c + (Vector2i(0, off) if horiz else Vector2i(off, 0))
			var k2 := world.idx(dc.x, dc.y)
			world.decor[k2] = World.Decor.ROCK
			world.hp[k2] = 60
		var bp2 := preload("res://src/pal.gd").new()
		bp2.alpha = true
		bp2.boss = true
		entity_layer.add_child(bp2)
		bp2.setup(self, pool[rng.int_range(0, pool.size() - 1)], 45, Vector2(bx + 0.5, by + 0.5))
		bp2.home = bp2.pos
		pals.append(bp2)
		if place_free("chest", bx - 1, by - 1):
			var st2: Dictionary = structures[Vector2i(bx - 1, by - 1)]
			st2["store"] = {"gold_coin": rng.int_range(40, 80), "legendary_sphere": 2,
				"lifmunk_effigy": 3, "pal_egg": 2}
		grotto_room2 = Vector2i(bx, by)
		log_msg("A sealed grotto echoes in the deep wilds — it sounds deep")
		return

# World bosses that only appear as den guardians — Palworld's legendary tier.
const LEGENDARY_DEN := ["jetragon", "frostallion", "paladius", "necromus",
	"astegon", "blazamut", "suzaku", "jormuntide", "quivern", "elphidran"]

func spawn_legendary_den() -> void:
	# one per world: bigger ring, an uncapturable giant, elite honour guard
	var tries := 0
	while tries < 6000:
		tries += 1
		var tx := rng.int_range(8, World.WORLD_W - 10)
		var ty := rng.int_range(8, World.WORLD_H - 10)
		if world.zone_at(tx, ty) < 3:
			continue
		var ok := true
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if world.blocked(tx + dx, ty + dy) or structures.has(Vector2i(tx + dx, ty + dy)):
					ok = false
		if not ok:
			continue
		for c in [Vector2i(tx-3,ty-3),Vector2i(tx+3,ty-3),Vector2i(tx-3,ty+3),Vector2i(tx+3,ty+3),
				Vector2i(tx,ty-3),Vector2i(tx,ty+3),Vector2i(tx-3,ty),Vector2i(tx+3,ty)]:
			place_free("torch", c.x, c.y)
		var pool := LEGENDARY_DEN.filter(func(s): return not SpeciesGen.SPECIES.get(s, {}).is_empty())
		if pool.is_empty():
			return # species data trimmed — skip the den rather than spawn a ghost
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var bp := preload("res://src/pal.gd").new()
		bp.alpha = true
		bp.boss = true # IMMUNE to spheres — legendaries are earned, not caught
		entity_layer.add_child(bp)
		bp.setup(self, sid, 50, Vector2(tx + 0.5, ty + 0.5))
		bp.sprite.scale = Vector2(2.5, 2.5)
		bp.sprite.position.y = -78.0
		bp.home = bp.pos
		pals.append(bp)
		var guard_pool := SpeciesGen.zone_pool(3)
		for i in mini(3, guard_pool.size()):
			var gp := preload("res://src/pal.gd").new()
			entity_layer.add_child(gp)
			gp.setup(self, guard_pool[rng.int_range(0, guard_pool.size() - 1)],
				rng.int_range(24, 32), Vector2(tx + 1.5 - i, ty + 1.5))
			pals.append(gp)
		log_msg("A legendary %s den glows deep in the wilds" % sid)
		return

func regenerate(s: int) -> void:
	for p in pals:
		if is_instance_valid(p):
			p.queue_free()
	pals.clear()
	party.clear()
	for bp0 in box: # box pals were remove_child'd — clear() alone leaks their nodes
		bp0.free()
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
	for sp0 in spheres_flying: # in-flight spheres: sprite + stale target would linger
		if is_instance_valid(sp0["node"]):
			sp0["node"].queue_free()
	spheres_flying.clear()
	palbox_pos = Vector2i(-1, -1)
	extra_boxes.clear() # outpost network dies with the world
	grotto_pos = Vector2i(-1, -1)
	grotto_room2 = Vector2i(-1, -1)
	boss_respawns.clear() # the old world's dens died with it
	gauntlet = {} # and so did any trial in progress
	craft_queue.clear() # queued builds die with the world too
	player.mount = null # the pal it pointed at is gone — don't chase a freed object
	despawn_merchant() # new world, new route — the trader doesn't follow
	world.generate(s)
	drawer.setup(world)
	queue_redraw_decor() # the decor pool is keyed by cell — old-world sprites must be rebuilt
	player.pos = Vector2(world.spawn) + Vector2(0.5, 0.5)
	player.sync_screen()
	spawn_lairs() # joining clients need their own lair bosses (pals are locally authoritative)
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
		player.max_hp = 100 + (player.level - 1) * 10 + perks["hp"] * 12 # level hp + perk hp
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
	if projectiles.size() >= MAX_PROJECTILES:
		var old = projectiles.pop_front()
		if is_instance_valid(old.get("node")):
			old["node"].queue_free()
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

func teach_skill_fruit(item_id: String) -> void:
	# Skill fruit (Palworld): teaches the active pal a move of that element
	if party.is_empty():
		log_msg("No active pal to teach")
		return
	var p := find_pal(party[0])
	if p == null or p.hp <= 0:
		log_msg("Active pal is down")
		return
	var elem: String = ItemData.ITEMS.get(item_id, {}).get("elem", "")
	var pool := []
	for sid in SkillData.SKILLS:
		var sk: Dictionary = SkillData.SKILLS[sid]
		if sk.get("element", "neutral") == elem and sk.get("power", 0) > 0:
			pool.append(sid)
	pool = pool.filter(func(s): return s not in p.learned_skills())
	if pool.is_empty():
		log_msg("%s already knows every %s move" % [p.spec["name"], elem])
		return
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	add_item(item_id, -1)
	p.extra_skills.append(sid)
	log_msg("%s learned %s!" % [p.spec["name"], SkillData.SKILLS[sid].get("name", sid)])
	floater(p.pos, "+ skill!", "#a8e6a1")

# ---------- wandering merchant ----------
# A trader visits for the day every so often — buys junk, sells goods for
# gold_coin. Transient by design: never saved, despawns at dusk.
var merchant: Entity = null
var merchant_stock := []
var merchant_home := Vector2.ZERO
var merchant_tgt := Vector2.ZERO # Pal already owns `target` — Entity must not
var merchant_wander_t := 0.0
var last_merchant_day := -1
var _tod_prev := 0.0
var catch_counts := {} # species_id -> caught count (10th-of-kind pays a bonus)

const MERCH_POOL := ["pal_sphere", "mega_sphere", "low_medical", "medical_supplies",
	"bread", "jam_bun", "berry_seeds", "wheat_seeds", "arrow", "musket_ball",
	"skill_fruit_neutral", "skill_fruit_fire", "skill_fruit_water", "skill_fruit_grass",
	"skill_fruit_electric", "skill_fruit_ice", "skill_fruit_ground", "skill_fruit_dark",
	"skill_fruit_dragon", "cake", "pal_egg"]

func gen_merchant_stock() -> void:
	merchant_stock.clear()
	var pool := MERCH_POOL.duplicate()
	var n := mini(8 + rng.int_range(0, 4), pool.size())
	for i in n:
		var idx := rng.int_range(0, pool.size() - 1)
		var id: String = pool[idx]
		pool.remove_at(idx)
		var price: int = ItemData.ITEMS.get(id, {}).get("price", 15)
		if price <= 0:
			price = 25 # priceless items still trade — at a markup
		merchant_stock.append({"id": id, "n": rng.int_range(1, 4), "price": price})
	# black-market pals (Palworld): a few capturable-free specimens, priced by
	# zone rarity — deep-zone species cost real money
	for i in rng.int_range(2, 3):
		var z := rng.int_range(0, 2) if rng.chance(0.85) else 3
		var ppool: Array = SpeciesGen.zone_pool(z)
		if ppool.is_empty():
			continue
		var sid: String = ppool[rng.int_range(0, ppool.size() - 1)]
		var plv := rng.int_range(5 + z * 6, 14 + z * 8)
		merchant_stock.append({"pal": sid, "lv": plv, "n": 1,
			"price": 90 + plv * 12 + z * 80})

func spawn_merchant() -> void:
	if merchant != null or pals.size() >= MAX_PALS - 1:
		return
	var a := rng.next() * TAU
	var at := nearest_free(player.pos.x + cos(a) * 10.0, player.pos.y + sin(a) * 10.0)
	merchant = preload("res://src/entity.gd").new()
	merchant.world = world
	merchant.pos = at
	merchant.speed = 1.6
	entity_layer.add_child(merchant)
	merchant.setup_visuals("res://assets/pals/player_f0.png", "res://assets/pals/player_f1.png")
	merchant.sprite.modulate = Color(1.5, 1.0, 0.45) # a warmly-dressed stranger
	merchant_home = at
	gen_merchant_stock()
	log_msg("A wandering merchant has arrived! (E to trade)")
	floater(at, "Merchant!", "#e8d44d")

func despawn_merchant() -> void:
	if merchant == null:
		return
	if is_instance_valid(merchant):
		floater(merchant.pos, "safe travels…", "#c8d3d5")
		merchant.queue_free()
	merchant = null
	merchant_stock.clear()
	log_msg("The merchant moved on")

func tick_merchant(dt: float) -> void:
	# arrival roll at 07:00 once per day from day 2 onward; leaves at dusk
	if tod >= 7.0 and _tod_prev < 7.0 and day >= 2 and last_merchant_day != day:
		last_merchant_day = day
		if rng.chance(0.6):
			spawn_merchant()
	_tod_prev = tod
	if merchant == null:
		return
	if tod >= 19.0 or tod < 5.0:
		despawn_merchant()
		return
	merchant_wander_t -= dt
	if merchant_wander_t <= 0:
		merchant_wander_t = 2.5 + rng.next() * 2.5
		var a := rng.next() * TAU
		merchant_tgt = merchant_home + Vector2(cos(a), sin(a)) * 2.0
	merchant.step_toward(merchant_tgt, dt)
	merchant.sync_screen()

func buy_from_merchant(idx: int) -> void:
	if merchant == null or idx < 0 or idx >= merchant_stock.size():
		return
	var it: Dictionary = merchant_stock[idx]
	if it["n"] <= 0:
		return
	if item_count("gold_coin") < it["price"]:
		log_msg("Need %d gold" % it["price"])
		return
	if it.has("pal"):
		var sid := str(it["pal"])
		if SpeciesData.species_of(sid).is_empty():
			it["n"] = 0 # corrupted stock — retire the slot, never sell a ghost
			return
		if box.size() >= MAX_BOX:
			log_msg("Palbox full - make room first")
			return
		var np := gen_pal(sid, int(it["lv"]), player.pos)
		np.mode = "box"
		box.append(np)
		box_pal(np) # bought straight into the box — never a loose node
		add_item("gold_coin", -it["price"])
		it["n"] -= 1
		log_msg("Bought a Lv%d %s! (%dg)" % [np.level, np.spec["name"], it["price"]])
		return
	add_item("gold_coin", -it["price"])
	add_item(it["id"], 1)
	it["n"] -= 1
	log_msg("Bought %s (%dg)" % [ItemData.ITEMS.get(it["id"], {}).get("name", it["id"]), it["price"]])

func pal_sell_price(bp: Pal) -> int:
	# black-market buyback: worth less than the sticker price, more if rare
	return 40 + bp.level * 8 + (60 if bp.lucky else 0) + (80 if bp.alpha else 0) \
		+ bp.star * 50

func sell_pal_to_merchant(uid: int) -> void:
	if merchant == null:
		return
	for bp in box:
		if bp.uid == uid:
			var gain := pal_sell_price(bp)
			var nm: String = bp.spec["name"]
			box.erase(bp)
			bp.free() # box pals live under box_holder — free() is the teardown path
			add_item("gold_coin", gain)
			log_msg("Sold %s for %dg" % [nm, gain])
			return

func butcher_pal(uid: int) -> void:
	# Palworld's meat cleaver: sacrifice a boxed pal, it spills its drops
	if item_count("meat_cleaver") <= 0:
		log_msg("You need a Meat Cleaver for that")
		return
	for bp in box:
		if bp.uid == uid:
			var nm: String = bp.spec["name"]
			var mult := 3 if bp.lucky else 1
			box.erase(bp)
			for dr in bp.spec.get("drops", []):
				spawn_drop(dr[0], rng.int_range(dr[1], dr[2]) * mult, player.pos)
			bp.free() # box-holder path — same teardown as condense/sell
			log_msg("You butchered %s… it dropped its goods" % nm)
			return

func sell_to_merchant(id: String) -> void:
	if merchant == null or item_count(id) <= 0:
		return
	var unit: int = maxi(1, int(ItemData.ITEMS.get(id, {}).get("price", 0) * 0.5))
	add_item(id, -1)
	add_item("gold_coin", unit)
	log_msg("Sold %s (+%dg)" % [ItemData.ITEMS.get(id, {}).get("name", id), unit])
