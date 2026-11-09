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
var bench: Array = []      # party pals in their spheres — Palworld fields ONE out at a time
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
var drops: Array = []        # ground drops {id,n,pos,node,did}
var net_drops := {}          # client-side drop replicas: did -> {id,n,pos,node}
var net_box := []            # client-side mirror of the host's box roster (dicts)
var net_party := []          # client-side mirror of the host's party roster (dicts)
var drops_wanted := {}       # did -> time asked; stops take_drop RPC spam
var next_drop_id := 1        # host: wire key for drop_sync (never reused)
var dirty_decor := {}        # decor cell idx -> value; host ships deltas to clients
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
	# procedural SFX: streams synthesized once, played through a fixed pool —
	# no assets to ship, nothing to leak
	for i in 8:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		sfx_pool.append(ap)
	var SfxLib := preload("res://src/sfx.gd")
	SFX = {
		"throw": SfxLib.noise(0.12, 0.35, 10.0),
		"catch": SfxLib.arp([660, 880, 1320], 0.09, 0.45),
		"fail": SfxLib.tone(220, 0.18, 0.4, 0.7),
		"level": SfxLib.arp([523, 659, 784, 1046], 0.08, 0.4),
		"build": SfxLib.noise(0.2, 0.5, 7.0),
		"break": SfxLib.noise(0.3, 0.55, 12.0),
		"horn": SfxLib.tone(98, 0.8, 0.5, 0.85),
		"ko": SfxLib.tone(160, 0.5, 0.45, 0.6),
		"hit": SfxLib.noise(0.07, 0.3, 14.0),
	}
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

func saddle_for(p: Pal) -> String:
	# Palworld gear rule: every mount wants its own tack — flyers, swimmers
	# and land runners each take a different saddle
	if SpeciesData.body_of(p.species_id) == "bird":
		return "sky_saddle"
	if "water" in p.spec.get("elements", []):
		return "wave_saddle"
	return "saddle"

func has_saddle_for(p: Pal) -> bool:
	return item_count(saddle_for(p)) > 0

func sphere_tiers() -> Array:
	var out := []
	for id in ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]:
		if items.get(id, 0) > 0:
			out.append(id)
	return out

func unequip_if_gone(id: String) -> void:
	if player == null:
		return
	for slot in ["weapon", "armor", "acc1", "acc2"]:
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

# Palworld carry weight: every item pulls on the bag. Kind defaults,
# a few heavy standouts get their own numbers.
const KIND_WT := {
	"material": 2.0, "food": 0.6, "fruit": 0.4, "medicine": 0.5,
	"seed": 0.2, "sphere": 1.5, "ammo": 0.5, "weapon": 8.0,
	"armor": 15.0, "accessory": 2.0, "gear": 10.0,
}
const ITEM_WT := {
	"stone": 3.0, "ore": 5.0, "ingot": 6.0, "coal": 4.0,
	"pal_egg": 5.0, "musket": 12.0, "gold_coin": 0.1, "nails": 1.0,
}

func item_wt(sid: String) -> float:
	var it: Dictionary = ItemData.ITEMS.get(sid, {})
	return float(ITEM_WT.get(sid, KIND_WT.get(it.get("kind", ""), 1.0)))

var SFX := {}
var sfx_pool := []
var sfx_idx := 0
func sfx_play(k: String) -> void:
	var s = SFX.get(k)
	if s == null or sfx_pool.is_empty():
		return
	var ap: AudioStreamPlayer = sfx_pool[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_pool.size()
	ap.stream = s
	ap.play()

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

func wild_lv(zone: int) -> int:
	# Palworld: the night shift spawns meaner — same table, +2 after dusk
	return rng.int_range(1 + zone * 3, 4 + zone * 5) + (2 if is_night() else 0)

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
		var lv := wild_lv(zone)
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
		# Palworld herds: same-species pals roam in loose packs — followers
		# share the leader's species/level band and anchor to its home cell
		if rng.chance(0.35) and not p.alpha:
			for _i in rng.int_range(1, 2):
				if wild_n >= want or pals.size() >= MAX_PALS:
					break
				var mx := x + rng.int_range(-2, 2)
				var my := y + rng.int_range(-2, 2)
				var m_in_water: bool = world.tiles[world.idx(mx, my)] == World.Tile.WATER
				if m_in_water != in_water or (not m_in_water and world.blocked(mx, my)):
					continue
				var mp := preload("res://src/pal.gd").new()
				entity_layer.add_child(mp)
				mp.setup(self, sid, maxi(1, lv + rng.int_range(-2, 2)), Vector2(mx + 0.5, my + 0.5))
				mp.home = p.home
				pals.append(mp)
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
	np.mode = str(d[4]) if str(d[4]) in ["base", "partner", "wild"] else "wild"
	np.net_id = int(d[6]) if d.size() > 6 else 0 # host uid — replicas track by this
	pals.append(np)

func find_net_pal(nid: int) -> Pal:
	for p in pals:
		if p.net_id == nid and nid > 0:
			return p
	return null

func find_box_uid(uid: int) -> Pal:
	for bp in box:
		if is_instance_valid(bp) and bp.uid == uid:
			return bp
	for bb in bench: # spheres answer to the same uid space
		if is_instance_valid(bb) and bb.uid == uid:
			return bb
	return null

func find_pal(uid: int) -> Pal:
	for p in pals:
		if p.uid == uid or (p.net_id > 0 and p.net_id == uid):
			return p
	return null

func party_pal() -> Pal:
	for uid in party:
		var p := find_pal(uid)
		if p and p.mode == "partner": # only the field pal counts — not bench/base
			return p
	return null

func lead_pal() -> Pal:
	# party[0] is the chosen lead — in the field or resting in its ball
	if party.is_empty():
		return null
	var p := find_pal(party[0])
	if p == null:
		p = bench_pal_of(party[0])
	return p

func kill_pal(p: Pal, by_player: bool) -> void:
	player.dismount_if(p)
	var owned := p.mode in ["partner", "base", "bench"]
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
		if p.alpha or p.boss:
			mission_flags["elite"] = true
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
	bench.erase(p)      # a benched pal should never die — but never trust state
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
		sfx_play("ko")
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
	mission_flags["gauntlet"] = true

# ---------- base missions ----------
# Palworld's guide rope: an ordered checklist of base milestones that pays
# out gold + tech points. Checked against live state once a second — never
# event-driven, so a missed signal can only delay a reward, not lose it.
const MISSIONS := [
	{"text": "Build a Palbox", "gold": 30, "tp": 1},
	{"text": "Catch 3 pals", "gold": 40, "tp": 1},
	{"text": "Deploy a pal to base (palbox)", "gold": 40, "tp": 1},
	{"text": "Build a Logging Site", "gold": 50, "tp": 1},
	{"text": "Craft a pal sphere", "gold": 50, "tp": 1},
	{"text": "Build a Ranch", "gold": 60, "tp": 1},
	{"text": "Build a Pal Bed", "gold": 60, "tp": 1},
	{"text": "Defeat an alpha or boss", "gold": 100, "tp": 2},
	{"text": "Hatch a bred egg", "gold": 100, "tp": 2},
	{"text": "Clear the gauntlet sigil", "gold": 200, "tp": 3},
]
const MISSION_KEYS := ["palbox", "catch3", "deploy", "logger", "sphere",
	"ranch", "bed", "elite", "egg", "gauntlet"]
var mission_idx := 0
var mission_flags := {} # event-only goals: crafted sphere, elite kill, ...
var mission_t := 0.0
var dex_seen := {}      # species_id -> true — a wild one came within ~15 cells once
var dex_claimed := 0    # highest 10-species milestone tier already paid
var dex_t := 0.0
var weather := "clear"  # "clear" | "rain" — rolls every couple of game hours
var weather_t := 0.0

func total_catches() -> int:
	var n := 0
	for k in catch_counts:
		n += int(catch_counts[k])
	return n

func mission_done(idx: int) -> bool:
	match MISSION_KEYS[idx]:
		"palbox": return has_structure("palbox")
		"catch3": return total_catches() >= 3
		"deploy": return base_pals().size() >= 1
		"logger": return has_structure("logging_site")
		"sphere": return mission_flags.has("sphere")
		"ranch": return has_structure("ranch")
		"bed": return has_structure("pal_bed")
		"elite": return mission_flags.has("elite")
		"egg": return mission_flags.has("egg")
		"gauntlet": return mission_flags.has("gauntlet")
	return false

func note_crafted(out_id: String) -> void:
	if "sphere" in out_id:
		mission_flags["sphere"] = true

func tick_dex(dt: float) -> void:
	# paldeck cadence — separate accumulator so the dex keeps spotting
	# species long after the mission chain has run dry
	dex_t += dt
	if dex_t < 1.0:
		return
	dex_t = 0.0
	for p in pals: # bounded by MAX_PALS; wild sightings within earshot
		if p.mode == "wild" and p.pos.distance_squared_to(player.pos) < 225.0:
			dex_seen[p.species_id] = true
	var tier := catch_counts.size() / 10 # unique species caught, floored to 10s
	if tier > dex_claimed:
		tech_points += (tier - dex_claimed) * 2
		log_msg("PALDECK: %d species caught! +%d tech" % [catch_counts.size(), (tier - dex_claimed) * 2])
		floater(player.pos, "PALDECK MILESTONE", "#c08cff")
		dex_claimed = tier

func tick_weather(dt: float) -> void:
	# two-state sky, ~half a game day per roll — rain waters the fields
	# and puts water pals in their element
	weather_t += dt
	if weather_t < 120.0:
		return
	weather_t = 0.0
	var next := "rain" if rng.chance(0.35) else "clear"
	if next != weather:
		weather = next
		log_msg("Rain sweeps over the island" if weather == "rain" else "The sky clears")

func tick_missions(dt: float) -> void:
	if mission_idx >= MISSIONS.size():
		return
	mission_t += dt
	if mission_t < 1.0:
		return
	mission_t = 0.0
	while mission_idx < MISSIONS.size() and mission_done(mission_idx): # backlog pays out in order — bounded by MISSIONS.size()
		var m: Dictionary = MISSIONS[mission_idx]
		mission_idx += 1
		add_item("gold_coin", int(m["gold"]))
		tech_points += int(m["tp"])
		log_msg("MISSION: %s — done! +%dg +%d tech" % [m["text"], int(m["gold"]), int(m["tp"])])
		floater(player.pos, "MISSION DONE", "#8ef0ff")

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
	if spheres_flying.size() >= 16: # click-spam cap: the oldest ball misses
		var old = spheres_flying.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
	spheres_flying.append({"sid": sid, "target": target, "t": 0.0,
		"node": spr, "from": player.pos})
	sfx_play("throw")

func generator_active() -> bool:
	for kg in structures:
		var sg = structures[kg]
		if sg.get("id") == "generator":
			for w in sg["workers"]:
				if is_instance_valid(w) and w.san >= 15.0 and w.hunger < 80.0: # a slacking pal doesn't keep the lights on
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

var death_marks: Array[Vector2] = [] # map tombstones where you dropped your pack (session-only)
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
		death_marks.append(player.pos) # Palworld tombstone: the map remembers the spill
		if death_marks.size() > 3:
			death_marks.pop_front() # only the freshest few spills earn a mark
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

func travel_nodes() -> Array:
	# every waypoint stone + every palbox terminal is a node on the net
	var out := []
	for k in structures:
		var sid: String = structures[k]["id"]
		if sid == "waypoint" or sid == "palbox":
			out.append({"key": k, "id": sid,
				"dist": player.pos.distance_to(Vector2(k.x, k.y))})
	out.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return out

func use_waypoint() -> void:
	# Palworld fast travel: touched stone opens the travel net
	if travel_nodes().size() < 2:
		log_msg("The waypoint hums… but there's nowhere to go yet")
		return
	panel = "travel"

func travel_to(k: Vector2i) -> void:
	if not structures.has(k):
		return
	var sid: String = structures[k]["id"]
	if sid != "waypoint" and sid != "palbox":
		return
	player.pos = nearest_free(k.x + 0.5, k.y + 2.5)
	player.sync_screen()
	panel = ""
	floater(player.pos, "blink!", "#7fc8f8")
	log_msg("The waypoint net pulls you across the island")

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
	for qb in bench: # spheres rest too — Palworld party pals wake fresh
		qb.hp = qb.max_hp
		qb.san = 100.0
		qb.hunger = 0.0
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
	if target.net_id > 0 and net != null and net.is_client():
		# a replica can't be rolled locally — the host owns the outcome;
		# the sphere's flight was just theatre, the catch lands by snapshot
		net.rpc("sphere_catch", target.net_id, sp["sid"],
			sign(player.pos.x - target.pos.x) == -target.dir, player.capture_level)
		return
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
		sfx_play("catch")
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
			target.mode = "bench"
			party.append(target.uid)
			bench.append(target)
			pals.erase(target)
			box_pal(target) # spheres ride in the same cold store as the box
			log_msg("%s joins your party (%d/5)" % [target.spec["name"], party.size()])
			if party_pal() == null:
				send_out(target.uid) # an empty slot means the new catch takes the field
		else:
			target.mode = "box"
			box.append(target)
			pals.erase(target)
			box_pal(target)
	else:
		floater(target.pos, "…broke free", "#e8963c")
		sfx_play("fail")
		log_msg("%s broke free (%d%%)" % [target.spec["name"], int(chance * 100)])
		target.aggro = 0 if target.hostile() >= 1 else -1

func net_catch(nid: int, sid: String, behind: bool, cap_lv: int, pid: int) -> void:
	# Host-authoritative catch for a client's throw. The wire id is our own
	# uid (client replicas mirror it). The world is shared, so a caught pal
	# goes to the shared palbox — same as a full-party catch.
	var target: Pal = find_pal(nid)
	if target == null or target.mode != "wild" or target.hp <= 0 or target.boss:
		return
	var sp_pow: float = float(ItemData.ITEMS.get(sid, {}).get("spherePower", 0.0))
	if sp_pow <= 0.0:
		return # forged item ids don't get free rolls
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var cap_pow: float = target.spec["capturePower"] * (1.35 if target.lucky else 1.0)
	var chance: float = minf(0.97, Combat.catch_chance(hp_frac, cap_pow,
		sp_pow, target.any_status(), behind, cap_lv))
	if randf() < chance:
		if box.size() >= MAX_BOX:
			floater(target.pos, "BOX FULL", "#e8963c")
			log_msg("Palbox is full (%d) - %s got away" % [MAX_BOX, target.spec["name"]])
			return
		floater(target.pos, "★ CAUGHT!", "#4dd0e1")
		log_msg("Player %d caught %s Lv%d — into the palbox" % [pid, target.spec["name"], target.level])
		catch_counts[target.species_id] = catch_counts.get(target.species_id, 0) + 1
		target.statuses.clear()
		target.aggro = -1
		target.net_id = 0 # it's our pal now — replicas stop being tracked
		target.mode = "box"
		box.append(target)
		pals.erase(target)
		box_pal(target)
	else:
		floater(target.pos, "…broke free", "#e8963c")
		log_msg("%s broke free from player %d's sphere" % [target.spec["name"], pid])
		target.aggro = 0 if target.hostile() >= 1 else -1

func try_harvest(at: Vector2, face: Vector2) -> void:
	# hit the decor tile on the dominant axis the player faces (was x-only)
	var tx := int(at.x); var ty := int(at.y)
	if absf(face.x) >= absf(face.y):
		tx += int(signf(face.x))
	else:
		ty += int(signf(face.y))
	if net != null and net.is_client():
		# our decor is seed-synced, not truth — the host swings, then tells
		# everyone what changed via decor_delta
		net.rpc("harvest_req", tx, ty)
		return
	harvest_cell(tx, ty)

func harvest_cell(tx: int, ty: int) -> void:
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
		mark_decor(i)
		queue_redraw_decor()

func mark_decor(i: int) -> void:
	if net != null and net.is_host:
		dirty_decor[i] = world.decor[i]

func dirty_decor_pack() -> Array:
	var arr := []
	for i in dirty_decor:
		arr.append([i, dirty_decor[i]])
	dirty_decor.clear()
	return arr

func spawn_drop(id: String, n: int, at: Vector2) -> void:
	# tiny tinted bag icon; drops persist until picked up (player or hauler pal)
	if drops.size() >= MAX_DROPS:
		take_drop(drops.front()) # flood backstop: oldest bag evaporates
	drops.append({"id": id, "n": n, "pos": at, "node": drop_sprite(id, at),
		"cool": 0.0, "age": 0.0, "did": next_drop_id})
	next_drop_id += 1

func drop_sprite(id: String, at: Vector2) -> Sprite2D:
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
	return spr

# client replica set for host drops — same reconcile rules as pal_sync:
# packet carries the whole truth, missing dids despawn
func drop_sync(arr: Array) -> void:
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 5 or not (e[0] is float or e[0] is int):
			continue
		var did := int(e[0])
		seen[did] = true
		if net_drops.has(did):
			continue
		var id := str(e[1])
		var at := Vector2(float(e[3]), float(e[4]))
		net_drops[did] = {"id": id, "n": int(e[2]), "pos": at, "node": drop_sprite(id, at)}
	for did in net_drops.keys():
		if not seen.has(did):
			if is_instance_valid(net_drops[did]["node"]):
				net_drops[did]["node"].queue_free()
			net_drops.erase(did)
			drops_wanted.erase(did)
	for did in drops_wanted.keys(): # a denied ask retries after a beat
		if t - drops_wanted[did] > 3.0:
			drops_wanted.erase(did)

func clear_net_drops() -> void:
	for did in net_drops:
		if is_instance_valid(net_drops[did]["node"]):
			net_drops[did]["node"].queue_free()
	net_drops.clear()
	drops_wanted.clear()

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
	var ap0: Pal = lead_pal()
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
	var ap: Pal = lead_pal()
	if ap == null:
		return
	if ap.star >= CONDENSE_COST.size():
		log_msg("%s is already max star" % ap.spec["name"])
		return
	var need: int = CONDENSE_COST[ap.star]
	# fodder = same-species pals in the box (weakest first, active excluded)
	var fodder: Array = []
	for bp in box:
		if bp.species_id == ap.species_id and bp.uid != ap.uid and not bp.fav:
			fodder.append(bp) # heart-locked pals are never fodder
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
		if st["id"] in ["feed_box", "chest"] and not st.get("loot", false) \
				and not st.get("store", {}).is_empty():
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
		if st["id"] not in ["feed_box", "chest"] or st.get("loot", false):
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
			if st["id"] != kind or st.get("loot", false):
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
	if net == null or not net.is_client(): # clients take tod from env_sync — the host's clock owns the sky
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
	tick_assign(dt)
	tick_missions(dt)
	tick_dex(dt)
	tick_weather(dt)
	update_projectiles(dt)
	tick_box(dt)
	tick_death_marks()
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
			if "egg" in d["id"]:
				anger_nesters(d["pos"]) # Palworld: parents guard their nests — egg thieves get swarmed
			take_drop(d)
	# client-side drop replicas: we ask, the host decides (and pays via got_loot)
	if net != null and net.is_client():
		for did in net_drops.keys():
			if drops_wanted.has(did):
				continue
			var dd: Dictionary = net_drops[did]
			if player.pos.distance_squared_to(dd["pos"]) < 0.55:
				drops_wanted[did] = t
				net.rpc("take_drop", did)
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
			mark_decor(ri)
			world.hp[ri] = 30
			queue_redraw_decor()
	# base raid waves
	tick_raid(dt)
	tick_supply(dt)
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
	if sid == "palbox" and palbox_count() >= 1 + MAX_EXTRA_BOXES:
		return false # ghost must agree with place_structure's outpost cap
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
	if net != null and net.is_client():
		# shared world: pay locally, the host validates + plants it, and it
		# lands on our screen with the next struct_sync broadcast
		if not can_place(sid, tx, ty):
			log_msg("Can't build there")
			return false
		for c in s.get("cost", []):
			if item_count(c[0]) < c[1]:
				log_msg("Need %d %s" % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])])
				return false
		for c in s.get("cost", []):
			add_item(c[0], -c[1])
		net.rpc("build_req", sid, tx, ty)
		return true
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
		"walkable": s.get("walkable", false), "spike": s.get("spike", 0),
		"turret": s.get("turret", 0),
		"pos": Vector2i(tx, ty)}
	for dy in range(h):
		for dx in range(w):
			var ci0 := world.idx(tx + dx, ty + dy)
			if world.decor[ci0] != World.Decor.NONE: # trees/berries under the footprint are cleared
				world.decor[ci0] = World.Decor.NONE
				world.hp[ci0] = 0
				mark_decor(ci0)
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
	sfx_play("build")
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
		"walkable": s.get("walkable", false), "spike": s.get("spike", 0),
		"turret": s.get("turret", 0),
		"pos": Vector2i(tx, ty)}
	for dy in range(h):
		for dx in range(w):
			var ci1 := world.idx(tx + dx, ty + dy)
			if world.decor[ci1] != World.Decor.NONE: # clear whatever the footprint lands on
				world.decor[ci1] = World.Decor.NONE
				world.hp[ci1] = 0
				mark_decor(ci1)
			structures[Vector2i(tx + dx, ty + dy)] = st
			world.structures[ci1] = st
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
	if net != null and net.is_client():
		# host razes it; the refund goes to the shared base store, not our bag
		net.rpc("demolish_req", int(at.x), int(at.y))
		return true
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
		if q.mode == "base" and q.hp > 0 and q.san >= 15.0 and q.hunger < 80.0 and q.job_site == null \
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
	note_crafted(r["out"][0])
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
			note_crafted(cq["out"])
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
	for qb in bench: # benched pals share the field lesson too (Palworld party xp)
		pal_gain_xp(qb, int(n * 0.25))
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
		stat_pts += 1 # Palworld: every level banks a stat point for the statue
		log_msg("Level up! Lv%d (+2 tech, +1 stat)" % player.level)
		sfx_play("level")

func tick_box(dt: float) -> void: # Palworld palbox is a clinic — wounds mend inside
	for bp in box:
		if bp.revive_t > 0:
			if t > bp.revive_t:
				bp.revive_t = 0
				bp.hp = int(bp.max_hp * 0.3)
				log_msg("%s has recovered" % bp.spec["name"])
		elif bp.hp < bp.max_hp:
			bp.hp = minf(bp.max_hp, bp.hp + bp.max_hp * 0.03 * dt)
	for bp in bench: # spheres rest in the same clinic light
		if bp.hp < bp.max_hp:
			bp.hp = minf(bp.max_hp, bp.hp + bp.max_hp * 0.03 * dt) # ~33s to full

func tick_production(dt: float) -> void:
	var powered := 1.5 if generator_active() else 1.0 # one check — the SAN-aware helper
	var has_stand := has_structure("monitoring_stand")
	var stand := (1.4 * float(WORK_MODES[work_mode]["prod"])) if has_stand else 1.0
	cur_san_mult = float(WORK_MODES[work_mode]["san"]) if has_stand else 1.0
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
			if inc is Dictionary:
				# Palworld temperature rule, continuous: a campfire within 6
				# cells keeps the egg toasty — countdown runs 1.5x while it burns
				var warm := false
				for k3 in structures:
					if structures[k3]["id"] == "campfire" \
							and Vector2(k3.x - key.x, k3.y - key.y).length() <= 6.0:
						warm = true
						break
				if warm:
					inc["ready_t"] = float(inc["ready_t"]) - dt * 0.5
				if t >= float(inc.get("ready_t", 0.0)):
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
		if int(st.get("turret", 0)) > 0:
			st["turret_cd"] = float(st.get("turret_cd", 0.0)) - dt
			if float(st["turret_cd"]) <= 0.0:
				st["turret_cd"] = 2.5
				var tgt: Pal = null
				var tr := 12.0 # Palworld defense towers plink raiders on approach
				for p in pals:
					if p.mode != "wild" or p.hp <= 0 or not (p.raid or p.aggro >= 0):
						continue
					var dd: float = p.pos.distance_to(Vector2(key))
					if dd < tr:
						tr = dd; tgt = p
				if tgt:
					tgt.hit(int(st["turret"]), 1.0, false)
		var prod: Array = job.get("produces", [])
		var active: Array = st["workers"].filter(func(w): return w.san >= 15.0 and w.hunger < 80.0 and not w.has_status("sleep"))
		if prod.is_empty() or active.is_empty():
			continue
		var cons: Array = job.get("consumes", [])
		if not cons.is_empty() and not consume_ready(cons):
			continue # starved for inputs — no free production
		var work_sum := 0.0 # each worker contributes by its Artisan/etc passives; sick pals drag
		var wtype: String = job.get("workType", "")
		var night := is_night()
		for w in active:
			# Palworld: suitability LEVEL matters — a lv4 logger outworks a lv1
			var lv: int = int(w.spec.get("work", {}).get(wtype, 0))
			if s.get("farmField", false):
				lv = maxi(lv, int(w.spec.get("work", {}).get("watering", 0)))
			# dark pals ARE the night shift — a little faster after dusk
			var dusk := 1.15 if night and "dark" in w.spec.get("elements", []) else 1.0
			# rain is a water pal's home turf
			var dew := 1.15 if weather == "rain" and "water" in w.spec.get("elements", []) else 1.0
			# talent shows in the palbox — make it earn its keep on the crew too
			var iv: float = 0.9 + w.talent * 0.004 # T0 → 0.9, T100 → 1.3
			var cond: float = 1.0 + w.star * 0.1 # Palworld: a condensed pal outworks its kin
			work_sum += (0.5 + 0.5 * maxi(1, lv)) * w.passive_mult("work") * w.work_mult() * dusk * dew * iv * cond
		var wet := 1.25 if weather == "rain" and s.get("farmField", false) else 1.0 # rain does the watering
		st["timer"] += (dt * (1.0 + perks["work"] * 0.1)) * powered * stand * work_sum * wet
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
			if sc["id"] in ["chest", "feed_box"] and not sc.get("loot", false): # haulers stock food in the feed box — inputs count it too
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

const HEAT_IDS := ["campfire", "torch", "furnace", "hot_spring"]
func nearest_heat(at: Vector2) -> float:
	# distance to the closest warmth source — the night chill threshold.
	# Palworld: a fire pal at your side keeps you warm too.
	var bd := 1e9
	for k in structures:
		if structures[k]["id"] in HEAT_IDS:
			bd = minf(bd, at.distance_to(Vector2(k.x + 0.5, k.y + 0.5)))
	for q in pals:
		if q.hp > 0 and q.mode in ["partner", "base"] \
				and "fire" in q.spec.get("elements", []):
			bd = minf(bd, at.distance_to(q.pos)) # only YOUR fire pal snuggles up
	return bd

func base_pals() -> Array:
	return pals.filter(func(p): return p.mode == "base")

func nearest_bed_cell(at: Vector2) -> Vector2i:
	# where a sleepy pal should pad off to — the closest pal bed or spring
	var bd := 1e9
	var best := Vector2i(-1, -1)
	for k in structures:
		var sid: String = structures[k]["id"]
		if sid != "pal_bed" and sid != "hot_spring":
			continue
		var d := at.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if d < bd:
			bd = d; best = k
	return best

func cast_line() -> bool:
	# Palworld fishing: stand at the water's edge, wait for a bite — mostly
	# loot, sometimes a live aquatic pal surfaces to fight or catch
	var c := Vector2i(int(player.pos.x), int(player.pos.y))
	var wc := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k: Vector2i = c + d
		if world.in_bounds(k.x, k.y) and world.tiles[world.idx(k.x, k.y)] == World.Tile.WATER:
			wc = k
			break
	if wc.x < 0:
		log_msg("Cast at the water's edge")
		return false
	var roll := rng.next()
	if roll < 0.4 and pals.size() < MAX_PALS:
		# a live catch: an aquatic pal from this zone's pool surfaces
		var zone := world.zone_at(wc.x, wc.y)
		var pool: Array = (ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)).filter(
			func(s): return "water" in SpeciesData.species_of(str(s)).get("elements", []))
		if pool.is_empty():
			pool = SpeciesData.SPECIES.keys().filter(
				func(s): return "water" in SpeciesData.species_of(str(s)).get("elements", []))
		if pool.is_empty():
			return false
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var fp := preload("res://src/pal.gd").new()
		entity_layer.add_child(fp)
		fp.setup(self, sid, rng.int_range(1 + zone * 3, 4 + zone * 5), Vector2(wc.x + 0.5, wc.y + 0.5))
		fp.home = fp.pos
		pals.append(fp)
		log_msg("A wild %s took the bait!" % fp.spec["name"])
		floater(fp.pos, "SPLASH!", "#4d9de0")
	elif roll < 0.7:
		var n := rng.int_range(1, 2)
		add_item("pal_fluid", n)
		log_msg("Caught pal fluids x%d" % n)
	elif roll < 0.9:
		add_item("gold_coin", rng.int_range(4, 12))
		log_msg("A soggy coin purse!")
	else:
		add_item("red_berries", 2)
		log_msg("Just weeds and berries.")
	floater(Vector2(wc.x + 0.5, wc.y + 0.5), "~splash~", "#9fd8ff")
	return true

func anger_nesters(at: Vector2) -> void:
	# wild pals near a looted nest turn hostile — egg theft has a price
	for q in pals:
		if q.mode == "wild" and q.hp > 0 and q.aggro < 0 \
				and q.pos.distance_to(at) < 9.0:
			q.aggro = 0
			q.statuses.erase("sleep")

func make_active(uid: int) -> void:
	# Palworld "send out": one ball on the field — picking a lead swaps it in
	var cur := party_pal()
	if cur != null and cur.uid == uid:
		retract_out() # tapping the field pal calls it back
		return
	send_out(uid)

const STANCES := ["auto", "aggressive", "passive"]

# Palworld partner passives: a fielded species quietly buffs its handler
const PARTNER_AURAS := {
	"direhowl": {"speed": 0.08},   # pack-runner keeps your legs quick
	"eikthyrdeer": {"speed": 0.06},
	"lifmunk": {"atk": 0.10},      # gun-happy spotter sharpens your aim
	"foxparks": {"atk": 0.08},
	"tanzee": {"atk": 0.06},
	"dumud": {"def": 4.0},         # thick hide lessons rub off
	"pengullet": {"def": 3.0},
	"cattiva": {"carry": 120.0},   # Palworld's iconic pack mule
	"lamball": {"carry": 50.0},
}

func partner_aura(stat: String) -> float:
	var p := party_pal()
	if p == null or p.hp <= 0:
		return 0.0
	return float(PARTNER_AURAS.get(p.species_id, {}).get(stat, 0.0))

# Palworld suit icons, text-style: top work types as two-letter codes
const WORK_ABBR := {
	"kindling": "KI", "watering": "WA", "planting": "PL", "handiwork": "HA",
	"lumbering": "LU", "mining": "MI", "transporting": "TR", "gathering": "GA",
	"farming": "FA", "cooling": "CO", "medicine": "ME", "electricity": "EL",
}
func work_str(spec: Dictionary) -> String:
	var w: Dictionary = spec.get("work", {})
	var ks := w.keys()
	ks.sort_custom(func(a, b): return int(w[a]) > int(w[b]) \
		or (int(w[a]) == int(w[b]) and str(a) < str(b)))
	var out := ""
	for k in ks:
		out += "%s%d " % [WORK_ABBR.get(k, "?"), int(w[k])]
	return out.strip_edges()

func cycle_stance(uid: int) -> void:
	# Palworld pal commands: the field pal obeys a standing order
	var p: Pal = find_pal(uid)
	if p == null:
		p = bench_pal_of(uid)
	if p == null:
		return
	p.stance = STANCES[(STANCES.find(p.stance) + 1) % STANCES.size()]
	log_msg("%s: %s" % [p.spec["name"], p.stance])

func bench_pal_of(uid: int) -> Pal:
	for bp in bench:
		if is_instance_valid(bp) and bp.uid == uid:
			return bp
	return null

func retract_out() -> void:
	# Palworld: your field pal returns to its sphere — one ball out at a time
	var cur := party_pal()
	if cur == null:
		return
	player.dismount_if(cur)
	pals.erase(cur)
	cur.mode = "bench"
	bench.append(cur)
	box_pal(cur)
	log_msg("%s recalled" % cur.spec["name"])

func send_out(uid: int) -> void:
	# Palworld send-out: the chosen party member takes the field; whoever was
	# out goes back into their ball. Lead slot tracks who's out.
	var cur := party_pal()
	if cur != null and cur.uid == uid: # tapping the out pal recalls it
		retract_out()
		return
	var bp := bench_pal_of(uid)
	if bp == null or bp.hp <= 0:
		return
	retract_out()
	party.erase(uid)
	party.push_front(uid)
	bench.erase(bp)
	pals.append(bp)
	bp.mode = "partner"
	bp.pos = nearest_free(player.pos.x + 1.2, player.pos.y)
	unbox_pal(bp)
	log_msg("%s sent out!" % bp.spec["name"])

func box_to_party(bp: Pal) -> void:
	if bp.hp <= 0:
		log_msg("%s is KO'd - wait for it to recover" % bp.spec["name"])
		return
	if party.size() >= 5:
		log_msg("Party full (5) - send someone to the box first")
		return
	box.erase(bp)
	party.erase(bp.uid) # a stale mirror or double-promote must not dup the slot
	party.append(bp.uid)
	bp.mode = "bench" # Palworld: new members wait in their ball until sent out
	bench.append(bp)
	log_msg("%s joined the bench (%d/5)" % [bp.spec["name"], party.size()])
	if party_pal() == null:
		send_out(bp.uid)

const MAX_BASE_PALS := 20 # absolute workforce cap — more mouths than this starve the loop anyway

# ---------- base level missions ----------
# Palworld palbox levels: the terminal grades your base and pays slots
var base_level := 1
const BASE_LEVEL_MAX := 5
const BASE_MISSION_TEXT := {
	1: "deploy 2 pals", 2: "build 8 structures + deploy 4 pals",
	3: "catch 12 pals + build 14 structures", 4: "deploy 8 pals + reach day 5",
}
func base_mission_done(lv: int) -> bool:
	match lv:
		1: return base_pals().size() >= 2
		2: return structures.size() >= 8 and base_pals().size() >= 4
		3: return total_catches() >= 12 and structures.size() >= 14
		4: return base_pals().size() >= 8 and day >= 5
	return false

func upgrade_base() -> void:
	if base_level >= BASE_LEVEL_MAX:
		log_msg("Base level maxed")
		return
	if not base_mission_done(base_level):
		log_msg("Base mission: " + BASE_MISSION_TEXT[base_level])
		return
	base_level += 1
	sfx_play("level")
	log_msg("Base level %d! +2 workforce slots" % base_level)

func max_base_pals() -> int:
	# Palworld palbox growth: workforce slots scale with the player's level
	# (8+lvl, hard-capped by MAX_BASE_PALS) plus base-level mission bonus
	return mini(8 + player.level + (base_level - 1) * 2, MAX_BASE_PALS)

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
	bench.erase(p)
	if p.mode in ["box", "bench"]:
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
	var p := find_pal(uid)
	if p == null:
		p = bench_pal_of(uid) # benched spheres drop straight into cold storage
	if p == null:
		return
	player.dismount_if(p)
	party.erase(uid)
	pals.erase(p)
	bench.erase(p)
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
	var site: Variant = find_work_site(best, 6.0)
	if site:
		if best not in site["workers"]:
			site["workers"].append(best) # idempotent — a stale entry must not duplicate
		best.job_site = site
		log_msg("%s -> %s" % [best.spec["name"], StructureData.STRUCTURES[site["id"]]["name"]])
	else:
		log_msg("No workplace nearby")

func tick_death_marks() -> void:
	# reaching a tombstone retires it — the pack itself is handled by the drops
	for i in range(death_marks.size() - 1, -1, -1):
		if player.pos.distance_to(death_marks[i]) < 2.0:
			death_marks.remove_at(i)

func pet_pal(p: Pal) -> bool:
	# Palworld's pet: a little affection tops up SAN on a per-pal cooldown
	if p == null or p.hp <= 0 or p.mode not in ["partner", "base"]:
		return false
	if p.petted_t > t:
		return false
	p.petted_t = t + 60.0
	p.san = minf(100.0, p.san + 8.0)
	floater(p.pos, "♥", "#ff8ab0")
	log_msg("You pet %s" % p.spec["name"])
	return true

func find_work_site(p: Pal, reach: float) -> Variant:
	# nearest suitable post within reach — shared suitability rules for the
	# manual assign tap and the idle auto-assign sweep (farm fields take
	# waterers too, Palworld-style)
	var site = null
	var sd := reach
	for k in structures:
		var s: Dictionary = StructureData.STRUCTURES.get(structures[k]["id"], {})
		var jb: Dictionary = s.get("job", {})
		if jb.get("produces", []).is_empty() and structures[k]["id"] != "ranch" and jb.get("kind") != "power":
			continue # sites with no output aren't assignable (except generator/ranch) — campfire's [] sneaks past a null check
		var need: String = jb.get("workType", "")
		if need != "" and p.spec.get("work", {}).get(need, 0) == 0 \
				and not (s.get("farmField", false) and p.spec.get("work", {}).get("watering", 0) > 0):
			continue  # can't work this site — farm fields also take waterers (Palworld)
		if structures[k]["workers"].size() >= 4:
			continue # site is fully crewed — piling more pals on one site scales unbounded
		var d := p.pos.distance_to(Vector2(k.x, k.y))
		if d < sd:
			sd = d
			site = structures[k]
	return site

var assign_t := 0.0
func tick_assign(dt: float) -> void:
	# Palworld: idle base pals drift into open posts on their own — the palbox
	# crew staffs itself instead of waiting for a manual tap every time.
	# Transporters are exempt: hauling IS their job and a pinned site would
	# freeze the logistics loop.
	assign_t += dt
	if assign_t < 2.0:
		return
	assign_t = 0.0
	for q in pals:
		if q.mode != "base" or q.hp <= 0 or q.job_site != null or q.has_status("sleep"):
			continue
		if q.san < 15.0 or q.hunger >= 80.0 or q.carry != null:
			continue
		if q.spec.get("work", {}).get("transporting", 0) > 0:
			continue
		var site: Variant = find_work_site(q, 12.0)
		if site != null:
			site["workers"].append(q)
			q.job_site = site

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
		# STAB (Palworld): a pal fighting in its own element hits harder
		if elem in caster.spec.get("elements", []):
			mult *= 1.2
		if weather == "rain": # rain favors water's artillery and dampens fire's
			if elem == "fire":
				mult *= 0.85
			elif elem == "water":
				mult *= 1.15
		if tp.has_status("soak"):
			# Palworld element combos: a wet target takes the hit differently —
			# electricity arcs through, ice locks solid, fire just boils off
			if elem == "electric":
				mult *= 1.5
			elif elem == "ice":
				tp.statuses.erase("soak")
				tp.add_status("freeze", 2.5)
				floater(tp.pos, "FROZEN SOLID", "#7fc8f8")
			elif elem == "fire":
				tp.statuses.erase("soak")
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
						var d := Combat.damage(pr["dmg"] * 2.0 * (1.0 + partner_aura("atk")), 20, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus * p.def_mult(), mult, rng)
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
			"home": [p.home.x, p.home.y], # pack members share a leader's anchor — re-anchoring on load would dissolve every herd
			"fav": p.fav,
			"mode": p.mode, "hp": p.hp, "talent": p.talent, "sex": p.sex,
			"passives": p.passives, "alpha": p.alpha, "boss": p.boss,
			"san": p.san, "hunger": p.hunger, "job": jc, "carry": p.carry,
			"star": p.star, "xp": p.xp, "raid": p.raid, "ail": p.ailment, "sb": p.soul_boost,
			"lucky": p.lucky, "extra": p.extra_skills, "stance": p.stance,
			"rt0": t - p.get_meta("raid_t0", t) if p.raid else 0.0})
	for bp in box:
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "box", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"fav": bp.fav,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "carry": bp.carry, "sb": bp.soul_boost,
			"ail": bp.ailment, "lucky": bp.lucky, "extra": bp.extra_skills,
			"revive": maxf(0.0, bp.revive_t - t)})
	for bp in bench: # spheres ride in the save too — party state survives a reload
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "bench", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"fav": bp.fav,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "sb": bp.soul_boost,
			"ail": bp.ailment, "lucky": bp.lucky, "extra": bp.extra_skills,
			"stance": bp.stance})
	var structs := {}
	var seen_st := {} # one entry per structure — footprint cells share a st; writing
	# them as separate records made rebuild order-dependent and ate buildings
	for k in structures:
		var st = structures[k]
		if seen_st.has(st):
			continue
		seen_st[st] = true
		var inc = st.get("egg_inc")
		structs["%d,%d" % [k.x, k.y]] = {"id": st["id"], "store": st.get("store", {}), "egg": st.get("egg_parents"), "timer": st.get("timer", 0.0), "hp": st.get("hp", 200), "loot": st.get("loot", false),
			"inc": ({"pair": inc.get("pair"), "left": maxf(0.0, float(inc.get("ready_t", 0.0)) - t)} if inc is Dictionary else null)}
	var d := {
		"seed": world.seed, "day": day, "tod": tod, "tech_points": tech_points,
		"raid_t": raid_t,
		"unlocked": unlocked, "items": items, "party": party,
		"party_idx": party.map(func(u):
			var pp: Pal = find_pal(u)
			if pp == null:
				pp = bench_pal_of(u)
			if pp == null:
				return -1
			var i: int = pals.find(pp)
			if i >= 0:
				return i
			i = box.find(pp)
			if i >= 0:
				return pals.size() + i
			return pals.size() + box.size() + bench.find(pp)),
		"perks": perks, "stat_pts": stat_pts, "equip": player.equipment,
		"wear": player.weapon_wear,
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
		"missions": mission_idx, "mflags": mission_flags,
		"dex_seen": dex_seen.keys(), "dex_claimed": dex_claimed,
		"weather": weather, "wthr_t": weather_t, "wmode": work_mode, "blev": base_level,
		"player": {"pos": [player.pos.x, player.pos.y], "hp": player.hp,
			"hunger": player.hunger, "stamina": player.stamina,
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
	clear_net_drops()
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
	stat_pts = maxi(int(d.get("stat_pts", 0)), 0)
	var saved_perks: Dictionary = d.get("perks", {})
	for pk in perks: # merge over defaults — a save missing a newer perk would poison every perks[k] read
		perks[pk] = int(saved_perks.get(pk, perks[pk]))
	catch_counts.clear()
	if d.get("catches") is Dictionary:
		for ck in d["catches"]:
			catch_counts[str(ck)] = maxi(int(d["catches"][ck]), 0) # foreign counts can't poison the %10 bonus
	dex_seen.clear()
	if d.get("dex_seen") is Array:
		for sid in d["dex_seen"]:
			if not SpeciesData.species_of(str(sid)).is_empty():
				dex_seen[str(sid)] = true # unknown ids from other builds just don't get seen
	dex_claimed = clampi(int(d.get("dex_claimed", 0)), 0, 64)
	weather = str(d.get("weather", "clear")) if str(d.get("weather", "clear")) in ["clear", "rain"] else "clear"
	weather_t = clampf(float(d.get("wthr_t", 0.0)), 0.0, 120.0)
	work_mode = clampi(int(d.get("wmode", 1)), 0, WORK_MODES.size() - 1)
	base_level = clampi(int(d.get("blev", 1)), 1, BASE_LEVEL_MAX) # foreign save can't over-level the base
	mission_idx = clampi(int(d.get("missions", 0)), 0, MISSIONS.size())
	mission_flags.clear()
	var mf = d.get("mflags", {})
	if mf is Dictionary: # bounded: only real mission keys, bools only
		for mk in MISSION_KEYS:
			if mf.get(mk) is bool and mf[mk]:
				mission_flags[mk] = true
		if mission_flags.size() >= 64: # paranoia cap — same contract as every runtime set
			mission_flags.clear()
	var seq = d.get("equip", {})
	if seq is Dictionary: # merge over defaults — a foreign equip dict missing a slot would throw on equipment["slot"] reads
		for slot in ["weapon", "armor", "acc1", "acc2"]:
			var ev = seq.get(slot, "")
			player.equipment[slot] = str(ev) if ItemData.ITEMS.has(str(ev)) else "" # unknown ids equip to nothing
		var wdur: float = float(ItemData.ITEMS.get(player.equipment["weapon"], {}).get("weapon", {}).get("dur", -1))
		var wv = d.get("wear", wdur) # a foreign save can hand us a string — then trust the item, not the field
		player.weapon_wear = (clampf(float(wv), -1.0, maxf(wdur, 1.0)) if (wv is float or wv is int) else wdur) if wdur > 0 else -1.0
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
	player.stamina = clampf(float(d["player"].get("stamina", 100.0)), 0.0, 100.0) # old saves start rested
	player.max_hp = 100 + (player.level - 1) * 10 + perks.get("hp", 0) * 12 # never saved — derive it
	player.hp = minf(player.hp, player.max_hp)
	var pending_jobs := []
	var loaded := []
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
		var hm = pd.get("home")
		if hm is Array and hm.size() == 2 and (hm[0] is float or hm[0] is int) \
				and (hm[1] is float or hm[1] is int):
			np.home = Vector2(float(hm[0]), float(hm[1])) # herd anchors ride the save
		var m0 := str(pd.get("mode", "wild"))
		np.mode = m0 if m0 in ["wild", "partner", "base", "box", "bench"] else "wild" # foreign strings would poison every mode check
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
		var stn := str(pd.get("stance", "auto"))
		if stn in STANCES:
			np.stance = stn # a foreign stance string stays at default
		np.fav = pd.get("fav") == true # anything but a real bool stays unlocked
		np.soul_boost = clampi(int(pd.get("sb", 0)), 0, 10)
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
		elif np.mode == "bench":
			bench.append(np)
			box_pal(np) # spheres rest in the same cold store
		else:
			entity_layer.add_child(np)
			pals.append(np)
		loaded.append(np) # unified load order — party_idx indexes pals+box+bench alike
	if d.has("party_idx"):
		party.clear()
		for pi in d["party_idx"]:
			if pi is int and pi >= 0 and pi < loaded.size():
				party.append(loaded[pi].uid)
	else: # pre-party_idx saves stored raw uids — new pals got fresh uids, so old refs are dead
		party = party.filter(func(u): return find_pal(u) != null or bench_pal_of(u) != null)
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
			"walkable": s.get("walkable", false), "spike": s.get("spike", 0),
			"loot": sv.get("loot", false) == true if sv is Dictionary else false}
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

# monitoring stand work pace (Palworld: normal/hard/super-hard). Needs the
# stand built to mean anything; default 1 preserves the classic x1.4 boost.
var work_mode := 1
var cur_san_mult := 1.0 # written each production tick; pals read it when working
const WORK_MODES := [
	{"name": "Normal", "prod": 1.0, "san": 1.0},
	{"name": "Hard", "prod": 1.4, "san": 1.6},
	{"name": "Overdrive", "prod": 1.9, "san": 2.4},
]

func cycle_work_mode() -> void:
	if not has_structure("monitoring_stand"):
		return
	work_mode = (work_mode + 1) % WORK_MODES.size()
	var wm: Dictionary = WORK_MODES[work_mode]
	floater(player.pos, "Work: %s" % wm["name"], "#e8d44d")
	log_msg("Monitoring stand: %s pace (output x%.2f, SAN drain x%.1f)"
		% [wm["name"], wm["prod"], wm["san"]])

var supply_t := 300.0 # Palworld's wandering care package — lands near the player
func tick_supply(dt: float) -> void:
	supply_t -= dt
	if supply_t > 0.0:
		return
	supply_t = 360.0 + rng.next() * 300.0
	# a crate scatters a few stacks on open ground within sight-ish range
	for try in 40:
		var ang := rng.next() * TAU
		var r := 8.0 + rng.next() * 18.0
		var tx := int(player.pos.x + cos(ang) * r); var ty := int(player.pos.y + sin(ang) * r)
		if not world.in_bounds(tx, ty) or world.blocked(tx, ty):
			continue
		var loot := [["ancient_part", 2]]
		loot.append([["mega_sphere", "giga_sphere"][mini(day / 6, 1)], rng.int_range(2, 4)])
		loot.append([["baked_berries", "jam_bun", "bread"][rng.int_range(0, 2)], rng.int_range(2, 4)])
		loot.append(["gold_coin", rng.int_range(10, 25)])
		for i in loot.size():
			var li: Array = loot[i]
			spawn_drop(str(li[0]), int(li[1]),
				Vector2(tx + 0.5 + (i % 2) * 0.8, ty + 0.5 + (i / 2) * 0.8))
		floater(Vector2(tx + 0.5, ty + 0.5), "SUPPLY DROP!", "#ffd76e")
		log_msg("A supply crate lands nearby — grab it before the locals do")
		return

var raid_warned := false # 30s heads-up — Palworld flashes the raid horn early
var raid_theme := ""     # element pack for the incoming wave; "" = mixed
func tick_raid(dt: float) -> void:
	if palbox_pos.x < 0:
		return
	raid_t -= dt
	if raid_t < 30.0 and not raid_warned:
		raid_warned = true
		# Palworld raids read as packs — mostly one element, sometimes a mob
		var themes := ["fire", "water", "electric", "grass", "dark", "ice", "ground", "dragon"]
		# Palworld's signature raid: the Rayne Syndicate sends humans, not pals
		raid_theme = "syndicate" if rng.chance(0.15) else \
			("" if rng.chance(0.25) else themes[rng.int_range(0, themes.size() - 1)])
		var howl := "Syndicate squad" if raid_theme == "syndicate" else \
			(("%s pack" % raid_theme.capitalize()) if raid_theme != "" else "wild mob")
		log_msg("Raid party spotted — a %s is coming for the palbox!" % howl)
		sfx_play("horn")
		floater(player.pos, "RAID INCOMING", "#e8452f")
	if raid_t <= 0:
		raid_t = 240.0 + rng.next() * 180.0
		raid_warned = false # next wave gets its own warning
		start_raid()

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
			var pick_pool: Array
			if raid_theme == "syndicate":
				pick_pool = ["syndicate_grunt", "syndicate_sweeper"] # humans ignore zone tables
			else:
				var themed := hostile_pool.filter(func(s): return raid_theme != "" and raid_theme in SpeciesData.species_of(s).get("elements", []))
				pick_pool = themed if not themed.is_empty() else hostile_pool
			var sid: String = pick_pool[rng.int_range(0, pick_pool.size() - 1)]
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
		if sc["id"] not in ["chest", "feed_box"] or sc.get("loot", false) or left <= 0:
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
	var warm_hint := false
	for k3 in structures:
		if structures[k3]["id"] == "campfire" \
				and Vector2(k3.x - site.x, k3.y - site.y).length() <= 6.0:
			warm_hint = true
			break
	structures[site]["egg_inc"] = {"pair": pair, "ready_t": t + 90.0}
	var hint := egg_hint(pair)
	log_msg("Egg incubating - ready in 90s%s%s"
		% ["" if warm_hint else " (a campfire would hurry it)",
			" — " + hint if hint != "" else ""])

func egg_hint(pair) -> String:
	# Palworld tells you what's inside: named pairings show their species,
	# anything else just says which bloodline it takes after
	if pair is Array and pair.size() >= 2:
		var combo: String = BREED_COMBOS.get("%s+%s" % [pair[0], pair[1]],
			BREED_COMBOS.get("%s+%s" % [pair[1], pair[0]], ""))
		if combo != "":
			return str(SpeciesData.species_of(combo).get("name", combo))
		var pn: String = str(SpeciesData.species_of(str(pair[0])).get("name", str(pair[0])))
		return "%s line" % pn
	return ""

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
	while np.passives.size() > 4: # Palworld's 4-trait cap binds bloodlines too
		np.passives.pop_back()
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
	if pair is Array:
		mission_flags["egg"] = true # a bred egg — wild nest finds don't count
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
		# Palworld den treasure: a stocked chest sits behind the boss —
		# flagged "loot" so base haulers never trek out to rob their own prize
		var ck := Vector2i(tx, ty + 1)
		if place_free("chest", ck.x, ck.y):
			var chst: Dictionary = structures.get(ck)
			if chst != null:
				chst["loot"] = true
				var loot := {"gold_coin": rng.int_range(30, 80), "paldium": rng.int_range(2, 5)}
				if rng.chance(0.5):
					loot["ancient_part"] = 1
				if rng.chance(0.4):
					var fr := ["neutral","fire","water","electric","grass","ice","ground","dark","dragon"]
					loot["skill_fruit_" + fr[rng.int_range(0, fr.size() - 1)]] = 1
				if rng.chance(0.6):
					loot["cake"] = rng.int_range(1, 3)
				chst["store"] = loot
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
			st["loot"] = true # dungeon treasure — off the base logistics net
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
			st2["loot"] = true
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
	for bb0 in bench: # spheres live under box_holder — queue_free from the parent
		bb0.queue_free()
	bench.clear()
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
	clear_net_drops()
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
	mission_idx = 0 # missions belong to the world they were earned in
	mission_flags.clear()
	dex_seen.clear()
	dex_claimed = 0 # a fresh world hasn't proven its ecology yet
	weather = "clear"
	weather_t = 0.0
	work_mode = 1
	mission_t = 0.0
	stat_pts = 0 # level bank restarts with a new character
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
var stat_pts := 0 # level-up banked points — the statue spends these before effigies
func upgrade_perk(k: String) -> void:
	var lvl: int = perks[k]
	if lvl >= 5:
		log_msg("Statue maxed")
		return
	var cost := PERK_COST + lvl * 2
	if stat_pts > 0:
		stat_pts -= 1
	elif item_count("lifmunk_effigy") >= cost:
		add_item("lifmunk_effigy", -cost)
	else:
		log_msg("Need %d effigies or a stat point (have %d)" % [cost, item_count("lifmunk_effigy")])
		return
	perks[k] = lvl + 1
	if k == "capture":
		player.capture_level = 1 + perks["capture"] # keep the stat in sync
	if k == "hp":
		player.max_hp = 100 + (player.level - 1) * 10 + perks["hp"] * 12 # level hp + perk hp
		player.hp = player.max_hp
	log_msg("Statue upgraded: %s Lv%d" % [k, perks[k]])

func respec() -> bool:
	# Palworld's memory-wiping medicine: every perk rank folds back into
	# stat points — spend them fresh, no effigies refunded
	var total := 0
	for k in perks:
		total += int(perks[k])
	if total == 0:
		log_msg("No perks to forget")
		return false
	for k in perks:
		perks[k] = 0
	stat_pts += total
	player.capture_level = 1 + perks["capture"]
	player.max_hp = 100 + (player.level - 1) * 10 + perks["hp"] * 12
	player.hp = minf(player.hp, player.max_hp) # forgot the hp ranks — max shrank
	log_msg("Memory wiped: %d stat points returned" % total)
	return true

func soul_infuse(uid: int) -> void:
	# Palworld statue-of-power for pals: feed effigies into one pal's soul
	var target: Pal = null
	for q in pals:
		if q.uid == uid and q.mode in ["partner", "base"]:
			target = q
	for bp in box:
		if bp.uid == uid:
			target = bp
	for bb in bench:
		if bb.uid == uid:
			target = bb
	if target == null or target.soul_boost >= 10:
		return
	var cost := 1 + target.soul_boost
	if item_count("lifmunk_effigy") < cost:
		log_msg("Need %d effigies to infuse %s" % [cost, target.spec["name"]])
		return
	add_item("lifmunk_effigy", -cost)
	target.soul_boost += 1
	target.apply_bonuses()
	log_msg("%s's soul burns brighter (+%d)" % [target.spec["name"], target.soul_boost])

# Palworld signature partner skills: a few species get bespoke actives
# instead of "cast your best learned skill at the cursor"
const PARTNER_SKILLS := {
	"foxparks": {"cd": 6.0, "range": 4.5, "name": "Flamethrower"},
	"lifmunk": {"cd": 5.0, "range": 7.0, "name": "SMG Burst"},
	"tanzee":  {"cd": 5.0, "range": 8.0, "name": "Rifle Shot"},
}

# Palworld pal gear: a bespoke active needs its species item crafted in the
# pack — the harness/SMG/rifle are what make the skill real, not the pal.
const PARTNER_GEAR := {
	"foxparks": "foxparks_harness", "lifmunk": "lifmunk_smg", "tanzee": "tanzee_rifle",
}
func partner_gear_ok(sid: String) -> bool:
	var gid: String = PARTNER_GEAR.get(sid, "")
	return gid == "" or item_count(gid) > 0

func partner_skill() -> void:
	if party.is_empty():
		log_msg("No party pal")
		return
	var p := party_pal()
	if p == null or p.hp <= 0:
		log_msg("Send out a pal first")
		return
	var m := player.get_global_mouse_position()
	var tw0: Vector2 = Iso.from_screen(m.x, m.y, player.elev())
	var psk = PARTNER_SKILLS.get(p.species_id)
	if psk != null and not partner_gear_ok(p.species_id):
		log_msg("%s's %s needs its pal gear — unlock %s in the tech tree"
			% [p.spec["name"], psk["name"], PARTNER_GEAR[p.species_id]])
		psk = null # the pal falls back to its strongest learned move instead
	if psk != null:
		if p.skill_cd.get("partner", 0) > t:
			log_msg("%s is reloading" % p.spec["name"])
			return
		if not run_partner_skill(p, tw0, psk):
			log_msg("%s's %s found no target" % [p.spec["name"], psk["name"]])
			return
		p.skill_cd["partner"] = t + float(psk["cd"])
		log_msg("%s: %s!" % [p.spec["name"], psk["name"]])
		return
	var tw: Vector2 = tw0
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

func run_partner_skill(p: Pal, tw: Vector2, psk) -> bool:
	# bespoke actives — returns false when nothing in the cone/aim was worth
	# spending the cooldown on, so the button can fall back to a log line
	var reach: float = psk["range"]
	var p_atk := Combat.stat_at(p.spec["atk"], p.level, p.talent) * p.atk_bonus * p.atk_mult()
	match p.species_id:
		"foxparks": # flamethrower: burn everything in the aim cone
			var hit_any := false
			for q in pals:
				if q.mode != "wild" or q.hp <= 0 or q == p:
					continue
				if q.pos.distance_to(tw) <= reach * 0.5 + 0.6:
					q.hit(Combat.damage(p_atk, 45, Combat.stat_at(q.spec["def"],
						q.level, q.talent) * q.def_bonus * q.def_mult(), 1.0, rng), 1.0, true)
					if rng.chance(0.3):
						q.add_status("burn", 3.0)
					hit_any = true
			return hit_any
		"lifmunk": # SMG burst: three quick hits on the nearest wild pal to the aim
			var tgt := nearest_wild(tw, reach)
			if tgt == null:
				return false
			var tdef := Combat.stat_at(tgt.spec["def"], tgt.level, tgt.talent) * tgt.def_bonus * tgt.def_mult()
			for i in 3:
				if tgt.hp <= 0:
					break
				tgt.hit(Combat.damage(p_atk, 15, tdef, 1.0, rng), 1.0, true)
			return true
		"tanzee": # rifle shot: one heavy hit
			var tgt2 := nearest_wild(tw, reach)
			if tgt2 == null:
				return false
			tgt2.hit(Combat.damage(p_atk, 80, Combat.stat_at(tgt2.spec["def"],
				tgt2.level, tgt2.talent) * tgt2.def_bonus * tgt2.def_mult(), 1.0, rng), 1.0, true)
			return true
	return false

func nearest_wild(at: Vector2, reach: float) -> Pal:
	var best: Pal = null
	var bd := reach
	for q in pals:
		if q.mode != "wild" or q.hp <= 0:
			continue
		var d := q.pos.distance_to(at)
		if d < bd:
			bd = d
			best = q
	return best

# ---------- shared-world editing (host authority) ----------
func net_harvest(tx: int, ty: int, pid: int) -> void:
	if not world.in_bounds(tx, ty):
		return
	var gp = net.ghosts.get(pid)
	if gp != null and Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 4.0:
		return # swinging at a tree across the map is a no
	harvest_cell(tx, ty)

func net_place(sid: String, tx: int, ty: int, pid: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty():
		return false
	var gp = net.ghosts.get(pid)
	if gp != null and Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 9.0:
		return false # build where you stand, not across the map
	var seen_st := []
	for k in structures:
		if structures[k] not in seen_st:
			seen_st.append(structures[k])
	if seen_st.size() >= MAX_STRUCTURES:
		return false
	if not can_place(sid, tx, ty): # terrain/footprint/cap rules still hold
		return false
	if place_free(sid, tx, ty): # the client already paid locally
		log_msg("Player %d built %s" % [pid, s.get("name", sid)])
		return true
	return false

func net_demolish(tx: int, ty: int, pid: int) -> void:
	var st = structures.get(Vector2i(tx, ty))
	if st == null:
		return
	var gp = net.ghosts.get(pid)
	if gp != null and Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 6.0:
		return
	# shared world: chest contents spill as drops (anyone can haul them),
	# no bag refund — the builder isn't here to catch it
	for it in st.get("store", {}).keys():
		spawn_drop(str(it), int(st["store"][it]), Vector2(tx + 0.5, ty + 0.5))
	st["store"] = {}
	net_remove_structure(st)
	log_msg("Player %d razed %s" % [pid, st["id"]])

func net_remove_structure(st: Dictionary) -> void:
	var cells := []
	for k in structures:
		if structures[k] == st:
			cells.append(k)
	for w in st["workers"].duplicate():
		st["workers"].erase(w)
		if is_instance_valid(w):
			w.job_site = null
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	if is_instance_valid(st["node"]):
		st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null
	if st["id"] == "palbox" and not cells.is_empty():
		var origin: Vector2i = cells[0]
		for cc in cells:
			if cc.x < origin.x or (cc.x == origin.x and cc.y < origin.y):
				origin = cc
		if origin == palbox_pos:
			palbox_pos = extra_boxes.pop_front() if not extra_boxes.is_empty() else Vector2i(-1, -1)
		else:
			extra_boxes.erase(origin)

# client: reconcile structure replicas against the host's wire truth
func struct_sync(arr: Array) -> void:
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 3 or not (e[1] is float or e[1] is int) or not (e[2] is float or e[2] is int):
			continue
		var sid := str(e[0])
		if not StructureData.STRUCTURES.has(sid):
			continue
		var k := Vector2i(int(e[1]), int(e[2]))
		seen[k] = sid
		var cur = structures.get(k)
		if cur != null and cur["id"] == sid and cur.get("pos", k) == k:
			continue # already mirrored at this origin
		place_free(sid, k.x, k.y)
	var uniq := []
	for k in structures.keys():
		var st: Dictionary = structures[k]
		if st not in uniq:
			uniq.append(st)
		if not st.has("pos"): # legacy rows — first-seen cell is the origin
			st["pos"] = k
	for st in uniq:
		if seen.get(st["pos"]) != st["id"]:
			net_remove_structure(st) # host demolished or replaced it

# client: apply host decor deltas (harvests, regrowth, footprint clears)
func decor_sync(arr: Array) -> void:
	var changed := false
	for e in arr:
		if e is Array and e.size() >= 2 and (e[0] is float or e[0] is int):
			var i := int(e[0])
			if i >= 0 and i < world.decor.size():
				world.decor[i] = int(e[1])
				changed = true
	if changed:
		queue_redraw_decor()

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
	elif it.has("acc"):
		# Palworld's twin trinket slots: re-click frees the slot it sits in,
		# a fresh trinket fills the first hole or bumps acc2
		if player.equipment["acc1"] == k:
			slot = "acc1"
		elif player.equipment["acc2"] == k:
			slot = "acc2"
		elif player.equipment["acc1"] == "":
			slot = "acc1"
		else:
			slot = "acc2"
	if slot == "" or item_count(k) <= 0:
		return
	if player.equipment[slot] == k:
		player.equipment[slot] = ""
		if slot == "weapon":
			player.weapon_wear = -1.0
		log_msg("Unequipped " + it["name"])
	else:
		player.equipment[slot] = k
		if slot == "weapon":
			player.weapon_wear = float(it["weapon"].get("dur", -1)) # fresh tool, fresh count
		log_msg("Equipped " + it["name"])

func break_weapon(id: String) -> void:
	log_msg("%s broke!" % ItemData.ITEMS.get(id, {}).get("name", id))
	sfx_play("break")
	floater(player.pos, "BROKE!", "#e64533")
	player.weapon_wear = -1.0
	add_item(id, -1) # count hits zero → unequip_if_gone clears the slot

func teach_skill_fruit(item_id: String) -> void:
	# Skill fruit (Palworld): teaches the active pal a move of that element
	if party.is_empty():
		log_msg("No active pal to teach")
		return
	var p := lead_pal() # a benched lead can still study a fruit
	if p == null or p.hp <= 0:
		log_msg("Lead pal is down")
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
	"skill_fruit_dragon", "cake", "pal_egg", "memory_wipe"]

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
			if bp.fav:
				log_msg("%s is heart-locked" % bp.spec["name"])
				return
			var gain := pal_sell_price(bp)
			var nm: String = bp.spec["name"]
			box.erase(bp)
			bp.free() # box pals live under box_holder — free() is the teardown path
			add_item("gold_coin", gain)
			log_msg("Sold %s for %dg" % [nm, gain])
			return

func toggle_fav(uid: int) -> void:
	# heart-lock a boxed pal — butcher, merchant sale and condense fodder all skip it
	for bp in box:
		if bp.uid == uid:
			bp.fav = not bp.fav
			return

func butcher_pal(uid: int) -> void:
	# Palworld's meat cleaver: sacrifice a boxed pal, it spills its drops
	if item_count("meat_cleaver") <= 0:
		log_msg("You need a Meat Cleaver for that")
		return
	for bp in box:
		if bp.uid == uid:
			if bp.fav:
				log_msg("%s is heart-locked" % bp.spec["name"])
				return
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
