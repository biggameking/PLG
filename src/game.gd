extends Node2D
class_name Game
# Root game state: world, player, kin, inventory, time, messages, floaters.
# Multiplayer-ready seams: all state lives here; sim runs deterministically.

var world := World.new()
var rng: Rng
var player: Player
var net = null
var hud = null # UILayer/HUD — main.gd wires it; touch routing needs the zone map
var perks := {"capture": 0, "speed": 0, "atk": 0, "hp": 0, "work": 0, "xp": 0}
const PERK_LABEL := {"capture": "Capture Power", "speed": "Move Speed", "atk": "Attack",
	"hp": "Max HP", "work": "Work Speed", "xp": "XP Gain"}
var pals: Array[Kin] = []
var items := {}            # item_id -> count
var party: Array[int] = [] # pal uids
var box: Array = []        # Kin data dicts (in kinbox)
var bench: Array = []      # party pals in their orbs — the island fields ONE out at a time
var spheres_flying := []   # {sid, target, t}
var floaters := []         # {pos, text, color, t}
var messages := []
var t := 0.0               # world seconds
var day := 1
var tod := 8.0             # hour of day
var next_uid_v := 1
var raid_t := 180.0          # countdown to next base raid wave
const MAX_CRAFT_QUEUE := 8   # the island timed crafting: station recipes queue up
var queue_crafts := true     # smoke tests flip this off to keep crafts instant
var craft_queue := []        # {out,n,left,cost} — station builds in progress
var drops: Array = []        # ground drops {id,n,pos,node,did}
var net_drops := {}          # client-side drop replicas: did -> {id,n,pos,node}
var net_box := []            # client-side mirror of the host's box roster (dicts)
var net_party := []          # client-side mirror of the host's party roster (dicts)
var net_residue := false     # this world came down the wire — never write it over a real save
var net_unlocked := []       # host's tech list mirror; empty = not a client / no constraint
var net_spires := 0          # host's spire tally mirror — the HUD's spine counter
var net_den := 0             # host's legend-heir tally mirror — the DEN counter
var remote_parties := {}     # multiplayer: owner_tag -> [pal uids] — each guest's own party strip
const MAX_REMOTE_TAGS := 32  # a roster row per keeper — enough guests for any sane co-op night
const MAX_BENCH := 6 + MAX_REMOTE_TAGS * 6  # own strip plus every guest's — an accorded co-op world legitimately reaches ~198 orbs
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
var kinbox_pos := Vector2i(-1, -1)  # primary base anchor; -1 = no base yet
const MAX_EXTRA_BOXES := 2          # the island runs up to 3 bases — 1 primary + 2 outposts
var extra_boxes: Array[Vector2i] = [] # outpost kinbox origins, shared box network
var tech_points := 0
var unlocked := ["kinbox", "kin_bed", "feed_box", "campfire", "workbench", "straw_bed"]
var craft_target: Node2D = null
var state := "title" # title | play | paused — sim and player input gate on this
var panel := ""
var settings := {"master": 1.0, "music": 1.0, "sfx": 1.0, "fullscreen": false, "raids": true, "lang": "en", "touch": "auto"}
var craft_station := ""
var chest_ref = null
var condense_arm := 0.0
var load_arm := -1.0 # F4 quick-load confirmation arm — a stray tap can't vaporize a session
const DAY_LEN := 240.0     # seconds per game day
const SAVE_VER := 2        # 1 = pre-rename ids (Migrate handles); 2 = kinbound ids

# ---- hard caps: nothing per-frame/per-event may grow without bound ----
# Any unbounded collection is a memory leak in waiting; every list that
# accepts runtime appends must evict/expire or refuse past these limits.
const MAX_DROPS := 400        # ground loot; oldest decays first anyway
const MAX_PROJECTILES := 200  # raid volleys can spike these hard
const MAX_FLOATERS := 80      # cosmetic text — cheap insurance
const MAX_PALS := 220         # wild + owned + raid; AI tick cost scales with this
const DEMOLISH_REACH := 4.5   # razing needs a hand on the structure — all input paths share this
const MAX_BOX := 400          # stored pals are out-of-tree nodes — real bytes
const MAX_EGG_QUEUE := 32     # ranch parentage queue (eggs can also be sold/eaten)
const MAX_MERCH_STOCK := 64   # merchant inventory refresh
# Untrusted-input coercion (rule 5): int()/float() abort on Array/Dict/Object,
# and a mid-load abort leaves a gutted world the next save would clobber.
# These helpers are the ONLY way save/RPC values may reach numeric vars.
static func _i(v, dflt: int = 0) -> int:
	if v is bool or v is int:
		return int(v)
	if v is float:
		return int(v) if is_finite(v) else dflt # int(NaN) is impl-defined, never 0
	if v is String:
		return int(v)
	return dflt

static func _f(v, dflt: float = 0.0) -> float:
	if v is bool or v is int:
		return float(v)
	if v is float:
		return v if is_finite(v) else dflt # maxf(0, NaN) returns NaN — never let it through
	if v is String:
		var r := float(v)
		return r if is_finite(r) else dflt
	return dflt

# numeric AND finite — NaN/INF pass "is float" and poison every position,
# timer and seed they land in. One gate covers the whole class.
static func _fin(v) -> bool:
	return v is int or (v is float and is_finite(v))

# a parentage row is [sp, sp, talent, talent, ...] — hatch reads pair[0]/[1]
# into a typed String and pair[2]/[3] through int(), so an entry with foreign
# heads or non-numeric tails is a per-frame abort waiting for the egg to
# finish. Anything malformed normalizes to null = wild genetics, never lost.
static func _norm_pair(p) -> Variant:
	if p is Array and p.size() >= 4 and p[0] is String and p[1] is String \
			and _fin(p[2]) and _fin(p[3]):
		return p
	return null

# Signature breeding pairs (the island combos): "a+b" -> offspring species.
# Checked both directions at hatch time; unlisted pairs inherit a parent.
const BREED_COMBOS := {
	"fenjelly+fenlump": "puffmite",
	"puffmite+sprigmelt": "doztail",
	"cindlump+branpurr": "pyrejelly",
	"corlmite+puffmite": "bubwrith",
	"quackbill+corlmite": "dewmane",
	"piplump+fenjelly": "mimtrot",
	"tammane+hushsmith": "noctmane",
	"fernchim+zaptrot": "statchew",
	"noctplume+terrkin": "veilplume",
	"ripbell+statchew": "faradwisp",
	"scalbeak+statchew": "noctfang",
	"corlmite+quackbill": "marlump",
	"dozantler+puffmite": "bramplume",
	"fernchim+briarmaw": "ripwrith",
	"zaptrot+tammane": "statstride",
	"scalfang+cindpaw": "pyreplume",
	"bubwrith+bubgoo": "ripwrith",
	"mosswisp+wortling": "mossveil",
	"terrkin+puffchim": "sparkhaunt",
	"rimemane+snovfawn": "snovmool",
	"pyrejelly+branpurr": "scalfang",
	"loammelt+shadewisp": "lazburr",
	"sparkwhisk+shadehand": "sprigveil",
	"petalantler+mossjelly": "mimspike",
	"tambeak+fenlump": "zapplume",
	"hushnib+thornmelt": "briarchim",
	"loamquill+terrnib": "grithoof",
	"dewpuff+bubgloom": "frostfang",
	"wortquill+digsnout": "noctfang",
	"marlump+branling": "grithoof",
	"pyreplume+duskwing": "noctfang",
	"fernchim+statchew": "zaptrot",
	"zapplume+noctplume": "frostfang",
	"briargoo+sprigmelt": "puffchim",
	"shadegloom+shadelump": "duskwing",
	"shademelt+sparkwhisk": "duskpurr",
	"soltalon+murkwing": "noctplume",
	"leaftrot+briarmaw": "floraling",
	"snovmool+petalantler": "tawtail",
	"shademite+grimling": "shadegloom",
	"brancrest+zapplume": "murkwing",
}

func _exit_tree() -> void:
	# Orphan sweep: the engine frees in-tree children, but anything parented to
	# box_holder or otherwise detached needs an explicit hand — belt & suspenders
	# over box_pal's keep-everything-parented design.
	if OS.has_environment("PLG_ORPHANS"):
		print("_exit_tree sweep: box=%d kin=%d" % [box.size(), pals.size()])
	for bp in box:
		if is_instance_valid(bp):
			bp.free() # not in tree: free(), never queue_free()
	box.clear()
	for bp in pals:
		if is_instance_valid(bp) and bp.get_parent() == null:
			bp.free()
	pals.clear()
	# streams+playbacks still in flight at quit count as ObjectDB leaks —
	# silence the pool and drop every ref the dicts/players hold
	for ap in sfx_pool:
		ap.stop(); ap.stream = null
	if music_day != null:
		music_day.stop(); music_day.stream = null
	if music_night != null:
		music_night.stop(); music_night.stream = null
	if music_danger != null:
		music_danger.stop(); music_danger.stream = null
	SFX.clear()
	CRIES.clear()

@onready var entity_layer: Node2D = $YSort/Entities
@onready var drawer = $World/Terrain
# Detached-node leak prevention: box kin live under this hidden holder instead
# of floating parentless. Every kin is ALWAYS inside the tree — the engine
# reclaims them at exit and no code path can orphan one.
var box_holder: Node2D

func _unbind_mount(p: Kin) -> void:
	# any path that retires, relocates or frees a ridden kin owes it this:
	# no rider claims it, and it stops hiding under a rider that no longer
	# exists. Every sibling site calls this or the kin re-enters a roster
	# invisible and unmountable forever.
	p.mounted_by = 0
	p.visible = true

func box_pal(p: Kin) -> void:
	# send a live kin to the box: keep it parented (to box_holder) so it can
	# never leak; process is disabled there so stored kin cost nothing.
	if p.get_parent() == box_holder:
		return
	if p.get_parent() == null:
		box_holder.add_child(p)
	else:
		p.reparent(box_holder)

func unbox_pal(p: Kin) -> void:
	if p.get_parent() == entity_layer:
		return
	if p.get_parent() == null:
		entity_layer.add_child(p)
	else:
		p.reparent(entity_layer)
	p.visible = true # cold-storage daylight: a pal KO'd mid-expedition kept
	# its invisibility into the box — re-entering the world clears it

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
		"lucky": SfxLib.arp([880, 1174, 1568, 2093], 0.07, 0.35),
		"click": SfxLib.tone(880, 0.05, 0.28),
		"quest": SfxLib.arp([659, 784, 988], 0.09, 0.4),
		"craft": SfxLib.arp([392, 523, 659], 0.1, 0.35),
		"hatch": SfxLib.arp([784, 988, 1319], 0.08, 0.4),
		"coin": SfxLib.tone(1174, 0.09, 0.3, 1.3),
		"eat": SfxLib.noise(0.09, 0.3, 9.0),
		"drop": SfxLib.tone(180, 0.09, 0.35, 0.5),
	}
	# audio buses: Master owns Music + SFX; settings.cfg holds the mix
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")
	for ap0 in sfx_pool:
		ap0.bus = "SFX"
	# the Dummy driver never mixes: play() would orphan a playback object per
	# call that the ObjectDB sweep reports as a leak — synth+cache still runs
	# headless (tests assert on it), only the actual output is skipped
	audio_live = AudioServer.get_driver_name() != "Dummy"
	# ambient score: day and night pad loops crossfaded on the Music bus —
	# no assets, synthesized at boot like the SFX bank
	music_day = AudioStreamPlayer.new()
	music_day.stream = SfxLib.pad([[220.0, 277.2, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7], [164.8, 220.0, 261.6]], 6.0, 0.13, 0.75, 0.05)
	music_day.bus = "Music"
	music_day.volume_db = -10.0
	add_child(music_day)
	if audio_live:
		music_day.play()
	music_night = AudioStreamPlayer.new()
	music_night.stream = SfxLib.pad([[146.8, 174.6, 220.0], [130.8, 155.6, 196.0], [110.0, 146.8, 174.6], [123.5, 164.8, 196.0]], 6.0, 0.12, 1.0, 0.04)
	music_night.bus = "Music"
	music_night.volume_db = -80.0
	add_child(music_night)
	if audio_live:
		music_night.play()
	# the danger layer: a low minor drone that swallows the pastoral pads when
	# a raid wave, gauntlet or phase-two boss is on the field
	music_danger = AudioStreamPlayer.new()
	music_danger.stream = SfxLib.pad([[110.0, 130.8, 164.8], [103.8, 123.5, 155.6], [98.0, 116.5, 146.8], [110.0, 138.6, 164.8]], 6.0, 0.14, 0.3, 0.07)
	music_danger.bus = "Music"
	music_danger.volume_db = -80.0
	add_child(music_danger)
	if audio_live:
		music_danger.play()
	load_settings()
	bind_gamepad()
	has_save = FileAccess.file_exists("user://savegame.plg") # stat once at boot
	var spawn := world.generate(rng.int_range(1, 99999))
	drawer.setup(world)
	# player
	player = preload("res://src/player.gd").new()
	entity_layer.add_child(player)
	player.setup(self, Vector2(spawn.x + 0.5, spawn.y + 0.5))
	grant_starter_kit()
	log_msg(tr("Welcome to Kinbound. Press H for help."))
	log_msg(tr("You washed ashore with 3 orbs and some drift lumenite."))
	# POIs roll off the world seed even at boot — the same lane regenerate()
	# uses, or a guest of a fresh-boot host gets phantom walls where the host
	# sees floor (the join path replays placement from world.seed)
	var rsav := rng.s
	rng.s = (world.seed ^ 0x9E3779B9) & 0xFFFFFFFF
	place_pois()
	rng.s = rsav # gameplay rolls resume from the session stream

func grant_starter_kit() -> void:
	# starter kit: three orbs and the drift cargo — four lumenite is
	# exactly a kinbox's share, so mission 1 is solvable on day 1
	for id in ["kin_orb", "kin_orb", "kin_orb"]:
		add_item(id, 1)
	add_item("lumenite", 4)

func saddle_for(p: Kin) -> String:
	# the island gear rule: every mount wants its own tack — flyers, swimmers
	# and land runners each take a different saddle
	if SpeciesData.body_of(p.species_id) == "bird":
		return "sky_saddle"
	if "water" in p.spec.get("elements", []):
		return "wave_saddle"
	return "saddle"

func has_saddle_for(p: Kin) -> bool:
	return item_count(saddle_for(p)) > 0

func sphere_tiers() -> Array:
	var out := []
	for id in ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]:
		if items.get(id, 0) > 0:
			out.append(id)
	return out

func unequip_if_gone(id: String) -> void:
	if player == null:
		return
	for slot in ["weapon", "armor", "acc1", "acc2"]:
		if player.equipment.get(slot) == id and item_count(id) <= 0:
			player.equipment[slot] = ""
			log_msg(tr("%s left your hands") % tr(str(ItemData.ITEMS.get(id, {}).get("name", id))))

func add_item(id: String, n: int) -> void:
	items[id] = items.get(id, 0) + n
	if n > 0:
		# stack cap: overflow spills to the ground instead of vanishing
		var cap: int = ItemData.ITEMS.get(id, {}).get("stack", 999)
		if items[id] > cap:
			if net != null and net.is_client():
				pass # a guest's bag is their own truth — no shared ground to spill on
			else:
				var spill: int = items[id] - cap
				items[id] = cap
				if player != null:
					spawn_drop(id, spill, player.pos)
					if not drops.is_empty():
						drops.back()["cool"] = 3.0 # don't vacuum it straight back up
					log_msg(tr("Bag full - %s x%d dropped") % [tr(str(ItemData.ITEMS.get(id, {}).get("name", id))), spill])
				else:
					items[id] += spill # pre-player init: keep the overflow
	if items[id] <= 0:
		items.erase(id)
	unequip_if_gone(id)

func item_count(id: String) -> int:
	return items.get(id, 0)

func give_remote(pid: int, id: String, n: int) -> void:
	# a remote-owned kin's produce routes to its keeper's bag over the wire;
	# host kin keep the local path — and a peer that dropped mid-op spills
	# into ours rather than vanishing
	if pid > 0 and net != null and multiplayer.multiplayer_peer != null \
			and multiplayer.get_peers().has(pid):
		net.rpc_id(pid, "got_loot", id, n)
	else:
		add_item(id, n)

func tr_args(args: Array) -> Array:
	# wire args arrive as raw english/data keys — the receiving client localizes.
	# INVARIANT: callers pass untranslated names/ids only — feeding an already-
	# localized string back through tr() double-translates (audit-44)
	var a := []
	for x in args:
		a.append(tr(str(x)) if x is String else x)
	return a

func note_remote(pid: int, msg: String, args: Array = []) -> void:
	# wire protocol: the english key + raw args travel; the far end translates
	if pid > 0 and net != null and multiplayer.multiplayer_peer != null \
			and multiplayer.get_peers().has(pid):
		net.rpc_id(pid, "net_note", msg, args)
	else:
		log_msg(tr(msg) % tr_args(args) if args.size() else tr(msg))

# kill rewards answer to the killer's keeper — a guest's loot rides the
# loot wire, their xp the xp wire; the host's bag stays the fallback
func _kill_loot(pid: int, id: String, n: int) -> void:
	give_remote(pid, id, n)

func _kill_xp(pid: int, n: int) -> void:
	if pid > 0 and net != null and multiplayer.multiplayer_peer != null \
			and multiplayer.get_peers().has(pid):
		net.rpc_id(pid, "xp_gain", n)
	else:
		gain_xp(n)

func peer_pos_of(pid: int) -> Vector2:
	# where a remote keeper stands — their ghost's last synced position
	if net != null:
		var g = net.ghosts.get(pid)
		if g != null and g.net_pos.x >= 0:
			return Vector2(g.net_pos.x, g.net_pos.y)
	return player.pos

func owns_pid(p: Kin, pid: int) -> bool:
	return p != null and p.owner_id == pid

func rparty_by_tag(tag: String) -> Array:
	# a guest's party strip keyed by their install token — stable across
	# sessions (peer ids are not), bounded by the same party_cap() as ours
	if not remote_parties.has(tag):
		if remote_parties.size() >= MAX_REMOTE_TAGS:
			# evict a cold keeper's row — their kin cold-store in the box and
			# rebind rebuilds the strip if they ever say hello again. Leaving
			# them on the bench grew it ~5 per eviction cycle (rule 1).
			var live: Array = net.peer_tags.values() if net != null else []
			var victim := ""
			for k in remote_parties:
				if k not in live:
					victim = k
					break
			var vtag: String = victim if victim != "" else remote_parties.keys()[0]
			remote_parties.erase(vtag)
			for bk in bench.duplicate():
				if is_instance_valid(bk) and bk.owner_tag == vtag:
					bench.erase(bk)
					bk.mode = "box"
					if box.size() < MAX_BOX + 32:
						box.append(bk)
					else:
						bk.queue_free() # double-cap: dies clean under box_holder
		remote_parties[tag] = []
	return remote_parties[tag]

# one cap for every strip lane: the bench is bounded like every runtime set.
# A saturated bench overflows into the box; a saturated world frees clean.
# Returns true only when the kin actually landed on the bench — callers
# append the strip uid only on the true lane.
func _bench_add(cur: Kin) -> bool:
	pals.erase(cur)
	if bench.size() < MAX_BENCH:
		cur.mode = "bench"
		bench.append(cur)
		box_pal(cur)
		return true
	cur.mode = "box" # strip's full — the box takes what the bench can't
	if box.size() < MAX_BOX + 32:
		box.append(cur)
		box_pal(cur)
	else:
		cur.queue_free() # box+bench both capped — dies clean, no third store
	return false

func rparty_for(pid: int) -> Array:
	# resolve a peer id to its strip; a guest that never said hello still
	# gets a private row keyed by session id, never the keeper's roster
	var tag := ""
	if net != null:
		tag = str(net.peer_tags.get(pid, ""))
	return rparty_by_tag(tag if tag != "" else "_pid%d" % pid)

func box_count_of(pid: int) -> int:
	var n := 0
	for bp in box:
		if bp.owner_id == pid:
			n += 1
	return n

func rebind_owner(pid: int, tag: String) -> void:
	# a guest says hello with their install token: every kin carrying it
	# (including ones restored from the save) comes back under their hand
	if tag == "":
		return
	for coll in [pals, box, bench]:
		for p in coll:
			# a live peer's kin are not up for grabs — only orphans (-1) and
			# this caller's own session id can rebind to the tag
			if is_instance_valid(p) and p.owner_tag == tag and (p.owner_id <= 0 or p.owner_id == pid):
				p.owner_id = pid
	# rebuild the strip from the kin themselves — it survives row eviction
	# and any drift between the roster and the bench it describes
	var kept := []
	for p2 in bench:
		if p2.owner_id == pid:
			kept.append(p2.uid)
	for p3 in pals:
		if p3.mode == "partner" and p3.owner_id == pid:
			kept.push_front(p3.uid) # the field pal leads its keeper's strip
	if not remote_parties.has(tag):
		rparty_by_tag(tag) # a fresh tag's row goes through the cap/eviction lane — never a raw write past 32
	remote_parties[tag] = kept.slice(0, party_cap())

func box_op_remote(op: String, uid: int, pid: int, extra := "") -> void:
	# a client's kinbox click, host-validated: only the kin's owner may move
	# it — box, party strip and work posts are all private
	var p: Kin = find_pal(uid)
	if p == null:
		p = find_box_uid(uid)
	if p == null or not owns_pid(p, pid):
		return
	if pid <= 0: # sender 0 means the keeper's own machine — local paths
		match op:
			"box_to_party": box_to_party(p)
			"party_to_box": party_to_box(p.uid)
			"deploy_to_base": deploy_to_base(p)
			"base_to_box": base_to_box(p)
			"toggle_fav": toggle_fav(p.uid)
			"make_active": make_active(p.uid)
			"cycle_stance": cycle_stance(p.uid)
			"butcher_pal": butcher_pal(p.uid)
			"sell_pal": sell_pal_to_merchant(p.uid)
			"toggle_skill": toggle_skill(p, extra)
		return
	match op:
		"box_to_party": r_box_to_party(p, pid)
		"party_to_box": r_party_to_box(p, pid)
		"deploy_to_base": deploy_to_base(p)
		"base_to_box": r_base_to_box(p, pid)
		"toggle_fav": toggle_fav(p.uid)
		"make_active": r_make_active(p.uid, pid)
		"cycle_stance": cycle_stance(p.uid)
		"butcher_pal": r_butcher(p, pid)
		"sell_pal": r_sell_pal(p, pid)
		"toggle_skill": toggle_skill(p, extra)

func r_out_pal(pid: int) -> Kin:
	for p in pals:
		if p.mode == "partner" and p.owner_id == pid:
			return p
	return null

func r_retract(pid: int) -> void:
	var cur := r_out_pal(pid)
	if cur == null:
		return
	_unbind_mount(cur) # a mount called back to the bench can't stay claimed
	var rc_name: String = str(cur.spec["name"]) # capture before the overflow lane can free it
	if not _bench_add(cur):
		rparty_for(pid).erase(cur.uid) # saturated lanes boxed/freed it — the strip can't keep a ghost uid
	note_remote(pid, "%s recalled", [rc_name])

func r_send_out(uid: int, pid: int) -> void:
	var bp := bench_pal_of(uid)
	if bp == null or bp.hp <= 0 or not owns_pid(bp, pid):
		return
	r_retract(pid)
	var rp := rparty_for(pid)
	if not rp.has(uid) and rp.size() >= party_cap():
		return # a stray bench uid must not overflow the guest's strip
	rp.erase(uid)
	rp.push_front(uid)
	bench.erase(bp)
	pals.append(bp)
	bp.mode = "partner"
	var anchor := peer_pos_of(pid)
	bp.pos = nearest_free(anchor.x + 1.2, anchor.y, anchor)
	unbox_pal(bp)
	cry_for(bp.species_id)
	note_remote(pid, "%s sent out!", [bp.spec["name"]])

func r_make_active(uid: int, pid: int) -> void:
	var cur := r_out_pal(pid)
	if cur != null and cur.uid == uid:
		r_retract(pid) # tapping the field pal calls it back
		return
	r_send_out(uid, pid)

func r_box_to_party(bp: Kin, pid: int) -> void:
	if bp.hp <= 0 or bp.mode != "box":
		return
	var rp := rparty_for(pid)
	if rp.size() >= party_cap():
		note_remote(pid, "Party full (%d)", [party_cap()])
		return
	box.erase(bp)
	rp.erase(bp.uid) # a stale mirror or double-promote must not dup the slot
	if _bench_add(bp): # saturated bench lands it back in the box, mode corrected
		rp.append(bp.uid)
		note_remote(pid, "%s joined your party (%d/%d)", [bp.spec["name"], rp.size(), party_cap()])
		if r_out_pal(pid) == null:
			r_send_out(bp.uid, pid)
	else:
		note_remote(pid, "Bench is full - %s stays in the box", [bp.spec["name"]])

func r_party_to_box(p: Kin, pid: int) -> void:
	if box.size() >= MAX_BOX: # full box refuses BEFORE the unbind/job drop — the kin stays put whole
		note_remote(pid, "Kinbox is full")
		return
	_unbind_mount(p) # boxed kin can't stay bound — a mount belongs to the field
	var rp := rparty_for(pid)
	rp.erase(p.uid)
	pals.erase(p)
	bench.erase(p)
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null
	p.mode = "box"
	if p.carry != null:
		give_remote(pid, p.carry["id"], p.carry["n"])
		p.carry = null
	if p not in box:
		box.append(p)
	box_pal(p)
	note_remote(pid, "%s -> box", [p.spec["name"]])

func r_base_to_box(p: Kin, pid: int) -> void:
	# a guest recalls their own worker — job dropped, cargo goes to their bag
	if box.size() >= MAX_BOX:
		note_remote(pid, "Kinbox is full")
		return
	_unbind_mount(p)
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null
	if p.carry != null:
		give_remote(pid, p.carry["id"], p.carry["n"])
		p.carry = null
	pals.erase(p)
	p.mode = "box"
	if p not in box:
		box.append(p)
	box_pal(p)
	note_remote(pid, "%s -> box", [p.spec["name"]])

func r_butcher(p: Kin, pid: int) -> void:
	# the cleaver is host-side property, but a guest's own kin is theirs to
	# spend — the goods spill at their feet, not ours. Trust note: the local
	# gate is the client's own bag (cleaver count), which the host never sees —
	# bounded by the same bag-trust lane as every guest inventory claim.
	if p.mode != "box" or p.fav:
		return
	_unbind_mount(p) # impossible in practice — the cleaver doesn't take mounts — but the teardown contract is per-path, not per-hope
	box.erase(p)
	var mult := 3 if p.lucky else 1
	for dr in p.spec.get("drops", []):
		spawn_drop(dr[0], rng.int_range(dr[1], dr[2]) * mult, peer_pos_of(pid))
	p.free() # box-holder path — same teardown as condense/sell
	note_remote(pid, "You butchered %s… it dropped its goods", [p.spec["name"]])

func r_sell_pal(p: Kin, pid: int) -> void:
	if p.mode != "box" or p.fav or merchant == null \
			or not _ghost_reaches(pid, merchant.pos, 6.0):
		return # deals close face-to-face — a remote sell is a forged handshake
	_unbind_mount(p) # sold mounts settle the same bill — every exit path unbinds
	var gain := pal_sell_price(p)
	box.erase(p)
	p.free()
	give_remote(pid, "gold_coin", gain)
	note_remote(pid, "Sold %s for %dg", [p.spec["name"], gain])

func assign_remote(pid: int, at: Vector2) -> void:
	# a guest's F: nearest of THEIR base kin toggles its post — the shared
	# yard takes any hand, but nobody touches another keeper's kin
	var best: Kin = null
	var bd := 3.0
	for p in base_pals():
		if not owns_pid(p, pid):
			continue
		var d := at.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	if best == null:
		note_remote(pid, "No kin of yours nearby to assign", [])
		return
	if best.job_site != null:
		best.job_site["workers"].erase(best)
		best.job_site = null
		return
	var site: Variant = find_work_site(best, 6.0)
	if site:
		if best.carry != null: # cargo goes home to the asker's bag, not hostage
			give_remote(pid, best.carry["id"], best.carry["n"])
			best.carry = null
			best.carry_hold_t = 0.0
		if best not in site["workers"]:
			site["workers"].append(best)
		best.job_site = site

# the island carry weight: every item pulls on the bag. Kind defaults,
# a few heavy standouts get their own numbers.
const KIND_WT := {
	"material": 2.0, "food": 0.6, "fruit": 0.4, "medicine": 0.5,
	"seed": 0.2, "orb": 1.5, "ammo": 0.5, "weapon": 8.0,
	"armor": 15.0, "accessory": 2.0, "gear": 10.0,
}
const ITEM_WT := {
	"stone": 3.0, "ore": 5.0, "ingot": 6.0, "coal": 4.0,
	"kin_egg": 5.0, "bred_kin_egg": 5.0, "huge_kin_egg": 8.0, "musket": 12.0, "gold_coin": 0.1, "nails": 1.0,
}

func item_wt(sid: String) -> float:
	var it: Dictionary = ItemData.ITEMS.get(sid, {})
	return float(ITEM_WT.get(sid, KIND_WT.get(it.get("kind", ""), 1.0)))

var SFX := {}
var sfx_pool := []
const SFX_LIB := preload("res://src/sfx.gd")
var CRIES := {} # species_id -> one synthesized warble — bounded by species count

func cry_for(sid: String) -> void:
	# a kin keeps one voice forever: synth lazily, cache, reuse the sfx pool
	if not CRIES.has(sid):
		CRIES[sid] = SFX_LIB.cry(int(sid.hash()) & 0x7FFFFFFF)
	var s: AudioStream = CRIES[sid]
	if s == null or sfx_pool.is_empty():
		return
	var ap: AudioStreamPlayer = sfx_pool[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_pool.size()
	ap.stream = s
	if audio_live:
		ap.play()

var music_day: AudioStreamPlayer
var music_night: AudioStreamPlayer
var music_danger: AudioStreamPlayer
var sfx_idx := 0
var audio_live := true
func sfx_play(k: String) -> void:
	var s = SFX.get(k)
	if s == null or sfx_pool.is_empty():
		return
	var ap: AudioStreamPlayer = sfx_pool[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_pool.size()
	ap.stream = s
	if audio_live:
		ap.play()

func log_msg(msg: String) -> void:
	messages.push_back(msg)
	if messages.size() > 6:
		messages.pop_front()

func floater(pos: Vector2, text: String, color: String) -> void:
	if floaters.size() >= MAX_FLOATERS:
		floaters.pop_front() # cosmetic spam is evictable
	floaters.push_back({"p": pos, "t": text, "c": color, "age": 0.0})

func rumble(weak: float, strong: float, dur: float) -> void:
	# pad feedback: first connected pad only, and only when the last-seen
	# device was a pad — a kb/m player never paid for a motor
	if not using_pad:
		return
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		Input.start_joy_vibration(pads[0], weak, strong, dur)

func client_locked() -> bool:
	# the island authority contract: a guest may LOOK at a replica chest,
	# egg slot, fossil bed, cage, shrine or statue — but verbs that spend
	# items or mutate structure/world state belong to the host. One helper,
	# every world-mutating interaction routes through it.
	if net != null and net.is_client():
		log_msg(tr("Only the host can change the island"))
		return true
	return false

# ---------- wild kin ----------
const ZONE_SPECIES := {
	0: ["fenjelly", "fenlump", "sprigmelt", "puffmite", "briargoo"],
	1: ["cindlump", "faradlump", "quackbill", "corlmite", "nibjelly", "voltgoo", "shademelt"],
	2: ["loampuff", "dozantler", "piplump", "shademite", "shadelump"],
	3: ["loammelt", "marlump", "shadelump"],
}

func wild_lv(zone: int) -> int:
	# the island: the night shift spawns meaner — same table, +2 after dusk
	return rng.int_range(1 + zone * 3, 4 + zone * 5) + (2 if is_night() else 0)

func spawn_wild(opening := false) -> void:
	if net != null and net.is_client():
		return # host owns the wild roster — ours arrive as pal_sync replicas
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
		var pool: Array = acq_pool(ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone))
		var sid := pick_wild_species(pool)
		if sid == "":
			continue # an empty zone pool spawns nothing — not a ghost row
		var sp: Dictionary = SpeciesData.species_of(sid)
		var aquatic: bool = "water" in sp.get("elements", [])
		var in_water: bool = world.tiles[world.idx(x, y)] == World.Tile.WATER
		if in_water:
			if not aquatic or not world.swim_open(x, y):
				continue # landlubbers can't pop up in a lake
		elif world.blocked(x, y):
			continue
		var lv := wild_lv(zone)
		var p := preload("res://src/kin.gd").new()
		p.alpha = zone >= 2 and rng.chance(0.08)
		p.lucky = not p.alpha and rng.chance(0.015) # the island "Lucky" rare variant
		entity_layer.add_child(p)
		p.setup(self, sid, lv + (6 if p.alpha else 0) + (3 if p.lucky else 0), Vector2(x + 0.5, y + 0.5))
		if p.lucky:
			floater(p.pos, tr("☆ LUCKY ☆"), "#ffd76e")
			if player.pos.distance_to(p.pos) < 24.0:
				sfx_play("lucky") # shiny jingle — rare luck within earshot
		if p.alpha and rng.chance(0.4):
			p.bounty = p.level * 2 # wanted marks: some alphas carry a price on their head
		p.home = p.pos # lair anchor — alphas tether here
		pals.append(p)
		wild_n += 1
		# the island herds: same-species kin roam in loose packs — followers
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
				var mp := preload("res://src/kin.gd").new()
				entity_layer.add_child(mp)
				mp.setup(self, sid, maxi(1, lv + rng.int_range(-2, 2)), Vector2(mx + 0.5, my + 0.5))
				mp.home = p.home
				pals.append(mp)
				wild_n += 1
	if opening: # the opening beat: a few docile kin inside the spawn ring —
		var ring_n := 0 # a new keeper shouldn't have to hunt for a first catch
		var ring_tries := 0
		var z0: Array = acq_pool(ZONE_SPECIES[0] + SpeciesGen.zone_pool(0))
		z0 = z0.filter(func(s): return SpeciesData.species_of(str(s)).get("hostile", 0) == 0)
		while ring_n < 3 and ring_tries < 60 and pals.size() < MAX_PALS:
			ring_tries += 1
			var a9 := rng.next() * TAU
			var r9 := 4.5 + rng.next() * 3.0 # outside the pop-radius, on the first screen
			var rx := int(player.pos.x + cos(a9) * r9)
			var ry := int(player.pos.y + sin(a9) * r9)
			if rx < 4 or ry < 4 or rx >= World.WORLD_W - 5 or ry >= World.WORLD_H - 5 \
					or world.blocked(rx, ry) \
					or world.tiles[world.idx(rx, ry)] == World.Tile.WATER or z0.is_empty():
				continue
			var rp2 := preload("res://src/kin.gd").new()
			entity_layer.add_child(rp2)
			rp2.setup(self, pick_wild_species(z0), wild_lv(0), Vector2(rx + 0.5, ry + 0.5))
			rp2.home = rp2.pos
			rp2.set_meta("ring_kin", true) # opening catch targets stay near home — idle-at-
			pals.append(rp2) # title wandering can't walk them off the first screen.
			# transient by design (rule 20): the meta is a first-minutes guard, and wild
			# kin respawn unmarked on load — a returning keeper needs no tethered prey
			ring_n += 1

func pick_wild_species(pool: Array) -> String:
	# the island day/night ecology: dark kin are nocturnal — they only spawn
	# after dusk, and they dominate the night table in mixed zones.
	# NOTE: this branches on is_night() inside the seeded placement lane —
	# rng CONSUMPTION is identical either way (one int_range), so stream
	# parity and coordinates hold; only species CONTENT varies by tod.
	# Never pick POSITIONS by tod inside this lane (audit-42).
	if pool.is_empty():
		return "" # callers guard — an empty zone pool must not mint index 0
	var dark := pool.filter(func(s): return "dark" in SpeciesData.species_of(str(s)).get("elements", []))
	if is_night():
		if not dark.is_empty():
			return dark[rng.int_range(0, dark.size() - 1)]
	else:
		var diurnal := pool.filter(func(s): return s not in dark)
		if not diurnal.is_empty():
			return diurnal[rng.int_range(0, diurnal.size() - 1)]
	return pool[rng.int_range(0, pool.size() - 1)]

# One canonical gate for "a species that enters mortal pools": no legends,
# no humans. Legends live in LEGENDARY_DEN and are picked deliberately by
# dens/grottos/sigil raids — every spawn path that can produce a wild or
# bred kin must route through acq_pool. body_of() covers both body
# representations (inline "body" key and the BODY table the ironpact use).
func acquirable(sid: String) -> bool:
	return sid not in LEGENDARY_DEN and SpeciesData.body_of(sid) != "human"

# ownable = "may join a roster" — the superset of acquirable the two catch
# gates answer to. Legends stay out of spawn/breed/raid pools, but a den
# legend that roams again is earned the hard way: fight it, then catch it.
func ownable(sid: String) -> bool:
	# legend heirs are the den's whole promise — a knight-shaped legend is
	# still a legend: human body can't bar a den heir from the roster, or
	# the Accord's tenth name can never be earned (audit-33)
	return SpeciesData.body_of(sid) != "human" or sid in LEGENDARY_DEN

func acq_pool(pool: Array) -> Array:
	var out := []
	for s in pool:
		if s not in out and acquirable(str(s)):
			out.append(s)
	return out

func gen_pal(sp_id: String, lv: int, at: Vector2, lucky := false) -> Kin:
	# test/dev factory: a live kin in the entity layer; caller picks its mode
	var p := preload("res://src/kin.gd").new()
	p.lucky = lucky # must be set before setup — passives/scale roll there
	entity_layer.add_child(p)
	p.setup(self, sp_id, lv, at)
	p.home = at
	return p

func spawn_net_pal(d) -> void:
	# client-side replica of a host kin — untrusted wire data, validate the shape
	if pals.size() >= MAX_PALS or not (d is Array) or d.size() < 5:
		return
	var sp_id := str(d[0])
	if SpeciesData.species_of(sp_id).is_empty() and SpeciesGen.SPECIES.get(sp_id, {}).is_empty():
		return # foreign species id — drop the entry
	if not _fin(d[1]) or not _fin(d[2]):
		return # non-finite wire coords spawn an unreachable ghost
	# every wire cast lands before gen_pal — an abort after add_child would leak
	# an in-tree kin that never ran setup and no roster can ever reach
	var nlv := clampi(_i(d[3]), 1, 60)
	var nlucky: bool = d.size() > 5 and d[5] is bool and d[5]
	var nnid := _i(d[6]) if d.size() > 6 else 0
	var nboss: bool = d.size() > 7 and d[7] is bool and d[7]
	var nalpha: bool = d.size() > 8 and d[8] is bool and d[8]
	if nnid <= 0:
		return # replicas only exist shadowing a host uid — a 0/-N row would mint an untrackable local kin
	var nmount := maxi(_i(d[10]), 0) if d.size() > 10 else 0
	var np := gen_pal(sp_id, nlv, nearest_free(float(d[1]), float(d[2])), nlucky)
	np.mode = str(d[4]) if str(d[4]) in ["base", "partner", "wild"] else "wild"
	np.net_id = nnid # host uid — replicas track by this
	if np.net_id > 0:
		np.uid = -np.net_id # replicas live in negative-uid space: local uids are
			# always positive, so find_pal's dual-space lookup can never alias
			# a real kin with a wire shadow that shares its number
	np.boss = nboss # den/grotto bosses keep their orb immunity on clients too
	np.alpha = nalpha
	var nstag := str(d[9]) if d.size() > 9 else ""
	if spire_tag_ok(nstag):
		np.spire_tag = nstag # same whitelist the save path uses
	np.mounted_by = nmount
	np.owner_id = maxi(_i(d[11]), 0) if d.size() > 11 else 0 # whose kin this
		# shadow is — the kinbox [recall]/[mv] verbs key off it for guests
	np.soul_boost = clampi(_i(d[12]), 0, 10) if d.size() > 12 else 0 # the
		# statue panel prices off the replica — a stale 0 under-charged guests
		# for every infusion until the row rode the wire (audit-41)
	np.visible = np.mounted_by == 0 # a ridden mount hides under its rider
	pals.append(np)

func find_net_pal(nid: int) -> Kin:
	for p in pals:
		if p.net_id == nid and nid > 0:
			return p
	return null

func find_box_uid(uid: int) -> Kin:
	for bp in box:
		if is_instance_valid(bp) and bp.uid == uid:
			return bp
	for bb in bench: # orbs answer to the same uid space
		if is_instance_valid(bb) and bb.uid == uid:
			return bb
	return null

func find_pal(uid: int) -> Kin:
	# dual-space on purpose: positive uid space is local kin, a replica's
	# net_id is its host's uid — replicas carry uid = -net_id so the two
	# spaces can't collide (see spawn_net_pal)
	for p in pals:
		if p.uid == uid or (p.net_id > 0 and p.net_id == uid):
			return p
	return null

func party_pal() -> Kin:
	for uid in party:
		var p := find_pal(uid)
		if p and p.mode == "partner": # only the field pal counts — not bench/base
			return p
	return null

func lead_pal() -> Kin:
	# party[0] is the chosen lead — in the field or resting in its ball
	if party.is_empty():
		return null
	var p := find_pal(party[0])
	if p == null:
		p = bench_pal_of(party[0])
	return p

func kill_pal(p: Kin, by_player: bool, pid := 0) -> void:
	# pid carries the killer's peer id for guest swings (pal_hit threads it
	# through hit's provoked_pid) — loot, xp and hunt credit answer to THEM,
	# not to whichever bag happens to be local on the host
	if p.net_id > 0:
		return # replicas die by host snapshot, never by local simulation
	player.dismount_if(p)
	_unbind_mount(p) # a KO'd mount can't stay bound — the rider walks it off
	var owned := p.mode in ["partner", "base", "bench", "expedition"]
	# an expedition pal is still ours — a raider biting the invisible gatherer
	# KOs it to the box; it must not die as loot-dropping wild fauna
	if not owned: # only wild/raid pals drop loot or pay xp — KO'd own pals would farm infinitely
		var mult := 4 if p.alpha else (3 if p.lucky else 1)
		if p.lucky:
			_kill_loot(pid, "gold_coin", rng.int_range(3, 8)) # lucky pals bleed money
			log_msg(tr("Lucky %s dropped gold!") % tr(str(p.spec["name"])))
		if p.boss:
			_kill_loot(pid, "legendary_orb", 1)
			_kill_loot(pid, "sprigmelt_effigy", 3)
			_kill_loot(pid, "gold_coin", 10)
			log_msg(tr("RAID CLEARED! Legendary orb + loot!"))
		if p.alpha or p.boss:
			mission_flags["elite"] = true
		if p.bounty > 0:
			_kill_loot(pid, "gold_coin", p.bounty)
			floater(p.pos, tr("BOUNTY +%dg") % p.bounty, "#ffd76e")
			log_msg(tr("Bounty claimed on %s: +%d gold") % [tr(str(p.spec["name"])), p.bounty])
		for d in p.spec.get("drops", []):
			spawn_drop(d[0], rng.int_range(d[1], d[2]) * mult, p.pos)
		if p.alpha:
			_kill_loot(pid, "kin_orb", 1)
			log_msg(tr("Alpha %s down! Bonus orb.") % tr(str(p.spec["name"])))
			_kill_loot(pid, "sprigmelt_effigy", 2)
			_kill_loot(pid, "ancient_part", rng.int_range(1, 2)) # ancient tech currency
			if rng.chance(0.15):
				spawn_drop("huge_kin_egg", 1, p.pos) # huge eggs hide on alphas
			if rng.chance(0.08): # the island schematics drop off elites
				var sch: String = "schematic_bow" if rng.chance(0.5) else "schematic_musket"
				_kill_loot(pid, sch, 1)
				log_msg(tr("Found a %s!") % tr(str(ItemData.ITEMS[sch]["name"])))
			if rng.chance(0.15): # alphas carry the odd boss sigil — a dare in your pocket
				_kill_loot(pid, "boss_sigil", 1)
				log_msg(tr("Found a Boss Sigil!"))
		if p.boss and rng.chance(0.3): # bosses teach the good blueprints
			var sch2: String = "schematic_bow" if rng.chance(0.5) else "schematic_musket"
			_kill_loot(pid, sch2, 1)
			log_msg(tr("Found a %s!") % tr(str(ItemData.ITEMS[sch2]["name"])))
		if p.boss:
			_kill_loot(pid, "ancient_part", rng.int_range(2, 4))
		if by_player or pid > 0: # a guest's kill is still a keeper's kill
			board_hunt_credit(p.species_id, pid)
		_kill_xp(pid, p.level * 4)
	if p.carry != null: # a hauler's load doesn't die with it
		spawn_drop(p.carry["id"], p.carry["n"], p.pos)
		p.carry = null
	pals.erase(p)
	party.erase(p.uid)  # dead partners must free their party slot
	for rp in remote_parties.values(): # a KO'd guest pal frees its slot too —
		rp.erase(p.uid)                 # an unscrubbed uid is a phantom "Party full"
	bench.erase(p)      # a benched pal should never die — but never trust state
	if p.job_site:
		if p in p.job_site["workers"]:
			p.job_site["workers"].erase(p)
		p.job_site = null # no lingering worker SAN drain or base_ai pull
	if owned: # owned pals are knocked out, not deleted
		p.mode = "box"
		p.statuses.clear() # a KO'd pal shouldn't come out of the box still burning
		p.stun_t = 0.0
		p.berserk_t = 0.0 # a rampage dies with the KO — redeploy starts calm
		p.revive_t = t + 300.0  # the island-style revive timer
		if box.size() < MAX_BOX + 32: # KO'd kin get a small overflow lane past the
			box.append(p)             # catch cap — losing a downed partner to an
			box_pal(p)                # off-by-one box eviction is not a feature
			sfx_play("ko")
			if p.hunger >= 100.0:
				log_msg(tr("%s starved out - it will recover in the box (build a feed box!)") % tr(str(p.spec["name"])))
			else:
				log_msg(tr("%s is KO'd - it will recover in the box") % tr(str(p.spec["name"])))
		else: # even the overflow lane is full — the wild reclaims it, KO'd
			p.mode = "wild"
			p.owner_id = 0
			p.owner_tag = "" # released means released — no tag to rebind into a free kin
			p.revive_t = 0.0 # the KO clock dies with ownership — a later catch+box must not fire it
			p.hp = 1
			pals.append(p) # pals.erase ran above — re-enter or it orphans in-tree
			log_msg(tr("%s is KO'd - the full kinbox can't take it; it limps back to the wild") % tr(str(p.spec["name"])))
	else:
		if p.has_meta("gauntlet") and not gauntlet.is_empty():
			gauntlet["left"] -= 1
		if p.spire_tag != "":
			record_spire(p.spire_tag)
		elif p.boss and p.home != Vector2.ZERO:
			# a guardian that lost its tag (pre-stag save, forged row) still
			# guards a marked spire — derive it by proximity so the kill
			# records instead of walling the campaign forever (audit-40)
			for tg2 in spire_pos:
				if not spires_done.has(str(tg2)) \
						and Vector2(spire_pos[tg2]).distance_to(p.home) <= 8.0:
					record_spire(str(tg2))
					break
		if (p.alpha or p.boss) and not p.raid and p.spire_tag == "" and p.home != Vector2.ZERO \
				and boss_respawns.size() < MAX_RESPAWNS:
			# the island dens refill: a slain boss returns to its anchor ~1.5 days
			# on. Raid/gauntlet attackers have no den — they stay dead. A den
			# may only queue one heir: catch → KO-overflow → rewild → re-kill
			# would otherwise stack doubles and spawn twins (audit-40)
			var den_dup := false
			for br in boss_respawns:
				if br.get("sid") == p.species_id and br.get("pos") is Array \
						and Vector2(br["pos"][0], br["pos"][1]).distance_to(p.home) <= 4.0:
					den_dup = true
					break
			if not den_dup:
				boss_respawns.append({"sid": p.species_id, "lv": p.level,
					"pos": [p.home.x, p.home.y], "alpha": p.alpha, "boss": p.boss,
					"at": t + DAY_LEN * 1.5})
		p.queue_free()

const MAX_RESPAWNS := 64 # scheduled den refills — bounded like every runtime set
var boss_respawns := []  # {sid,lv,pos:[x,y],alpha,boss,at}

func tick_boss_respawns() -> void:
	if net != null and net.is_client():
		return # respawn timers are world state — the host decides who comes back
	for i in range(boss_respawns.size() - 1, -1, -1):
		var br: Dictionary = boss_respawns[i]
		if t < br.get("at", INF):
			continue
		var sid := str(br.get("sid", ""))
		if pals.size() >= MAX_PALS:
			# a full world defers, never drops — a discarded legend respawn
			# silences the den forever and strands the Accord (audit-33)
			if sid in LEGENDARY_DEN and not br.get("warned", false):
				br["warned"] = true # one voice per den — not a 60-second drum
				log_msg(tr("The den calls, but the island is too crowded to answer"))
			br["at"] = t + 60.0
			continue
		boss_respawns.remove_at(i)
		if SpeciesData.species_of(sid).is_empty():
			continue # corrupted entry — the den stays empty
		var legend := sid in LEGENDARY_DEN
		if legend:
			# a legendary den never re-raises the same warden — it calls a NEW
			# legend, and this one roams catchable: legendary orbs finally have
			# a target, and the ten-name collection loop closes
			var lpool := LEGENDARY_DEN.filter(
				func(s): return not SpeciesGen.SPECIES.get(s, {}).is_empty())
			if lpool.is_empty():
				continue # legend data trimmed — the den stays quiet
			# the den calls an heir you haven't proven yet — a pilgrimage,
			# not a lottery: uniform rolls could stall the tenth name for
			# dozens of cycles (audit-33 pacing)
			var fresh := lpool.filter(
				func(s): return int(catch_counts.get(s, 0)) <= 0)
			var pick_pool: Array = fresh if not fresh.is_empty() else lpool
			sid = pick_pool[rng.int_range(0, pick_pool.size() - 1)]
		var pp: Array = br.get("pos", [0, 0])
		var at := Vector2(float(pp[0]), float(pp[1])) if pp.size() >= 2 else Vector2.ZERO
		var np := preload("res://src/kin.gd").new()
		np.alpha = legend or bool(br.get("alpha", false)) # a re-den'd legend is always the heir — a forged non-alpha record would roam immune forever
		np.boss = bool(br.get("boss", false)) and not legend
		entity_layer.add_child(np)
		np.setup(self, sid, clampi(int(br.get("lv", 30)), 1, 60), at)
		np.home = at
		pals.append(np)
		log_msg(tr("A legend roams the old den — this one can be caught!") if legend
			else tr("A boss stirs again at its den"))

# ---------- gauntlet trial ----------
# tower fights, distilled: a sigil starts a 3-wave escalating
# battle at the kinbox. Transient like a raid — never saved, never net-synced.
var gauntlet := {} # {"wave": int, "left": int} — empty while idle

func start_gauntlet() -> bool:
	if client_locked():
		return false
	if not gauntlet.is_empty():
		log_msg(tr("A gauntlet is already running"))
		return false
	if kinbox_pos.x < 0:
		log_msg(tr("The gauntlet needs a kinbox to answer to"))
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
		1: groups = [[acq_pool(SpeciesGen.zone_pool(2)), 2, [20, 26], false]]
		2: groups = [[acq_pool(SpeciesGen.zone_pool(2) + SpeciesGen.zone_pool(3)), 2, [30, 36], false]]
		3: groups = [[acq_pool(SpeciesGen.zone_pool(3)), 2, [38, 42], false],
			[acq_pool(SpeciesGen.zone_pool(3)), 1, [48, 50], true]]
		_: # crowned EX — the tower's last question, heavier than anything it asks below
			groups = [[acq_pool(SpeciesGen.zone_pool(3)), 3, [46, 54], false],
				[acq_pool(SpeciesGen.zone_pool(3)), 1, [56, 60], true]]
	for grp in groups:
		var pool: Array = grp[0]
		for i in int(grp[1]):
			if pool.is_empty() or pals.size() >= MAX_PALS:
				continue
			var np := preload("res://src/kin.gd").new()
			np.alpha = true
			np.boss = bool(grp[3])
			entity_layer.add_child(np)
			np.setup(self, pool[rng.int_range(0, pool.size() - 1)],
				rng.int_range(int(grp[2][0]), int(grp[2][1])),
				nearest_free(kinbox_pos.x + 2.5 + i, kinbox_pos.y + 2.5 + i))
			if np.boss:
				np.sprite.scale = Vector2(2.2, 2.2)
				np.sprite.position.y = -70.0
			np.aggro = 0
			np.aggro_pid = np.nearest_body_pid() # a guest holding the base draws the wave too
			np.raid = true # den-respawn skips raiders — the tower stays dead too
			np.set_meta("gauntlet", true)
			np.set_meta("raid_t0", t)
			pals.append(np)
			gauntlet["left"] += 1
	if gauntlet["left"] == 0:
		gauntlet["wave"] -= 1 # a field at the pal cap answers no questions — retry when there's room, never score an empty wave as cleared
	else:
		log_msg(tr("Gauntlet wave %d! %d foes") % [w, gauntlet["left"]])

func tick_gauntlet() -> void:
	if net != null and net.is_client():
		return # the trial is a host event — its raiders arrive as replicas
	if gauntlet.is_empty():
		return
	if gauntlet["left"] > 0:
		# reconcile against live raiders — any despawn path that forgot to
		# decrement (culls, unloads) would stall the trial forever otherwise
		var live := 0
		for q in pals:
			if q.has_meta("gauntlet"):
				live += 1
		if live < gauntlet["left"]:
			gauntlet["left"] = live
			if live == 0: # every raider gone and nobody cleared them — void the run
				log_msg(tr("The tower reclaims its question — the gauntlet ends unanswered"))
				gauntlet = {}
				return
		if gauntlet["left"] > 0:
			return
	var apex: int = 4 if crowned else 3 # a crowned keeper gets one more question
	if gauntlet["wave"] < apex:
		gauntlet_next_wave()
		return
	var ex: bool = gauntlet["wave"] >= 4
	gauntlet = {}
	add_item("legendary_orb", 4 if ex else 2)
	add_item("sprigmelt_effigy", 5)
	add_item("gold_coin", 500 if ex else 150)
	add_item("gauntlet_sigil", 2 if ex else 1) # it pays for the next run — if you survive
	if ex:
		add_item("ancient_part", 6)
		add_item("huge_kin_egg", 2)
		log_msg(tr("APEX GAUNTLET CLEARED — the tower kneels to its crowned keeper"))
	else:
		log_msg(tr("GAUNTLET CLEARED! Legendary orbs + effigies + gold"))
	floater(player.pos, tr("APEX CLEARED!") if ex else tr("GAUNTLET CLEARED!"), "#ffd76e")
	mission_flags["gauntlet"] = true
	if ex:
		mission_flags["gauntlet_ex"] = true

# ---------- base missions ----------
# guide rope: an ordered checklist of base milestones that pays
# out gold + tech points. Checked against live state once a second — never
# event-driven, so a missed signal can only delay a reward, not lose it.
const MISSIONS := [
	{"text": "Build a Kinbox", "gold": 30, "tp": 1},
	{"text": "Catch 3 kin", "gold": 40, "tp": 1},
	{"text": "Deploy a kin to base (kinbox)", "gold": 40, "tp": 1},
	{"text": "Build a Logging Site", "gold": 50, "tp": 1},
	{"text": "Craft a kin orb", "gold": 50, "tp": 1},
	{"text": "Build a Ranch", "gold": 60, "tp": 1},
	{"text": "Build a Kin Bed", "gold": 60, "tp": 1},
	{"text": "Defeat an alpha or boss", "gold": 100, "tp": 2},
	{"text": "Hatch a bred egg", "gold": 100, "tp": 2},
	{"text": "Clear the gauntlet sigil", "gold": 200, "tp": 3},
]
const MISSION_KEYS := ["kinbox", "catch3", "deploy", "logger", "orb",
	"ranch", "bed", "elite", "egg", "gauntlet"]
var mission_idx := 0
var mission_flags := {} # event-only goals: crafted orb, elite kill, ...
var mission_t := 0.0
var dex_seen := {}      # species_id -> true — a wild one came within ~15 cells once
var dex_claimed := 0    # highest 10-species milestone tier already paid
var dex_t := 0.0
var dex_full := false   # every ownable species caught — the cataloger's seal
var _ownable_n := -1    # lazily counted: species tables are large consts

func ownable_species_count() -> int:
	if _ownable_n < 0:
		_ownable_n = 0
		for sid in SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys():
			if ownable(str(sid)):
				_ownable_n += 1
	return _ownable_n
var accord := false     # the Wildmere Accord — crown + all ten legend heirs
# + the EX gauntlet. Sealed once per save; the island fields a sixth slot.

func party_cap() -> int:
	return 6 if accord else 5

func den_caught() -> int:
	# legend heirs banked — the DEN tally the accord checks and the HUD shows
	var n := 0
	for ls in LEGENDARY_DEN:
		if int(catch_counts.get(ls, 0)) > 0:
			n += 1
	return n
var weather := "clear"  # "clear" | "rain" | "storm" | "drought" — rolls every couple of game hours
var weather_t := 0.0
var pray_cd := 0.0            # absolute t — shrine prayer cooldown
var explored := PackedByteArray() # fog of war — one byte per world cell
var explored_n := 0 # monotone reveal count — the fog bake's dirty key (transient, derived from explored on load)
var lure := {}                   # thrown bait {pos, till} — one pile at a time
var treasure := {}               # treasure-map dig spot {pos} — one chart at a time
var reveal_t := 0.0               # throttle: sight updates twice a second
var focus_target: Kin = null      # the island focus fire: the pal you last hit
var focus_t := 0.0                # ...stays the partner's priority for 4s

func credit_catch_local(sid: String) -> void:
	# the keeper's own ledger — on a client this counts ONLY their throws
	# (the world book lives host-side); on the host net_catch writes the same
	# dict directly, so this is the guest's slice, never a double-credit
	catch_counts[sid] = int(catch_counts.get(sid, 0)) + 1

func total_catches() -> int:
	var n := 0
	for k in catch_counts:
		n += int(catch_counts[k])
	return n

func mission_done(idx: int) -> bool:
	match MISSION_KEYS[idx]:
		"kinbox": return has_structure("kinbox")
		"catch3": return total_catches() >= 3
		"deploy": return base_pals().size() >= 1
		"logger": return has_structure("logging_site")
		"orb": return mission_flags.has("orb")
		"ranch": return has_structure("ranch")
		"bed": return has_structure("kin_bed")
		"elite": return mission_flags.has("elite")
		"egg": return mission_flags.has("egg")
		"gauntlet": return mission_flags.has("gauntlet")
	return false

func note_crafted(out_id: String) -> void:
	if "orb" in out_id:
		mission_flags["orb"] = true

func tick_dex(dt: float) -> void:
	# kindex cadence — separate accumulator so the dex keeps spotting
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
		log_msg(tr("KINDEX: %d species caught! +%d tech") % [catch_counts.size(), (tier - dex_claimed) * 2])
		floater(player.pos, tr("KINDEX MILESTONE"), "#c08cff")
		dex_claimed = tier
	if not dex_full and catch_counts.size() >= ownable_species_count():
		# the cataloger's seal — every catchable species on record. Pays the
		# best balls in the game: a full ledger earns the tools, not a title
		dex_full = true
		add_item("legendary_orb", 3)
		add_item("ancient_part", 2)
		floater(player.pos, tr("KINDEX COMPLETE"), "#c08cff")
		log_msg(tr("KINDEX COMPLETE — every kin on record. +3 legendary orbs"))
		sfx_play("horn")
		if net != null and multiplayer.multiplayer_peer != null:
			net.rpc("net_floater", player.pos.x, player.pos.y,
				"KINDEX COMPLETE", "#c08cff")
	tick_accord()

func tick_accord() -> void:
	# the Wildmere Accord — the island's last contract. Three seals: the
	# crown, every legend heir caught once, and the EX gauntlet cleared.
	# Seals once per save and widens the field roster for good.
	if accord or not crowned or not mission_flags.get("gauntlet_ex", false):
		return
	for ls in LEGENDARY_DEN:
		if int(catch_counts.get(ls, 0)) <= 0:
			return
	accord = true # every seal proven — the island signs in gold
	floater(player.pos, tr("THE WILDMERE ACCORD"), "#ffd76e")
	log_msg(tr("THE WILDMERE ACCORD — the island kneels to its keeper."))
	log_msg(tr("Your party can field SIX kin from now on."))
	sfx_play("horn")
	rumble(0.5, 0.9, 0.6)
	if net != null and multiplayer.multiplayer_peer != null:
		# every keeper on the island signs it too — not just the host's screen
		net.rpc("net_floater", player.pos.x, player.pos.y,
			"THE WILDMERE ACCORD", "#ffd76e")
		for acp in multiplayer.get_peers():
			note_remote(acp, "THE WILDMERE ACCORD — the island kneels to its keeper.")
			note_remote(acp, "Your party can field SIX kin from now on.")

func reveal_at(c: Vector2, r: float) -> void:
	# the island fog of war: walking peels the dark back a sight-radius at a time
	if explored.size() != world.WORLD_W * world.WORLD_H:
		explored.resize(world.WORLD_W * world.WORLD_H)
	var cx := int(c.x); var cy := int(c.y); var ri := int(ceil(r))
	for y in range(maxi(0, cy - ri), mini(world.WORLD_H - 1, cy + ri) + 1):
		for x in range(maxi(0, cx - ri), mini(world.WORLD_W - 1, cx + ri) + 1):
			if Vector2(x - cx, y - cy).length() <= r:
				var ei := y * world.WORLD_W + x
				if explored[ei] == 0:
					explored[ei] = 1
					explored_n += 1

func tick_weather(dt: float) -> void:
	if net != null and net.is_client():
		return # env_sync carries the host's sky — a local roll would thrash it
	# four-state sky, ~half a game day per roll — rain waters the fields,
	# a drought parches them, and every loud or dry sky has its kin
	weather_t += dt
	if weather_t < 120.0:
		return
	weather_t = 0.0
	var roll: float = rng.randf()
	var next := "storm" if roll < 0.15 else ("rain" if roll < 0.45 else ("drought" if roll < 0.60 else "clear"))
	if next != weather:
		weather = next
		log_msg({"rain": tr("Rain sweeps over the island"), "storm": tr("A thunderstorm rolls in — electric kin crackle"),
			"drought": tr("A drought settles in — the fields thirst"), "clear": tr("The sky clears")}.get(weather, tr("The sky clears")))

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
		log_msg(tr("MISSION: %s — done! +%dg +%d tech") % [tr(str(m["text"])), int(m["gold"]), int(m["tp"])])
		floater(player.pos, tr("MISSION DONE"), "#8ef0ff")
		sfx_play("quest")

var shake := 0.0 # camera kick — decays to nothing, main.gd turns it into a pixel offset
func screen_shake(amt: float) -> void:
	shake = minf(1.0, shake + amt)

func hurt_player(atk: float, from: Kin) -> void:
	# pause is armour only in solo — in a net session the island keeps
	# swinging whether the host's menu is up or not
	if (state != "play" and not net_live()) or player.dodge_t > 0:
		return # the title's ambient wildlife never bleeds into the run
	var def := 20.0 + player.level * 3.0
	var d := maxi(1, int(round(25.0 * (2.0 * atk) / maxf(1.0, atk + 2.0 * def) * (0.9 + rng.next() * 0.2))))
	apply_player_damage(d)

func apply_player_damage(dmg_before_armor: int) -> int:
	# shared keeper-hit pipeline: absorb bubble, then plate wear, flash,
	# thump and death — melee, wild skills and guest relays must not fork it
	var final := player.absorb_hit(maxi(1, dmg_before_armor - player.armor_def()))
	if final <= 0:
		return 0 # the bubble ate it whole — no wear, no flash
	player.hp -= final
	player.hit_flash = 0.4
	screen_shake(0.35)
	rumble(0.0, 0.45, 0.15) # getting bit should thump, not just flash
	floater(player.pos, tr("-") + str(final), "#e64533")
	player.wear_armor() # the island: the plate takes the wear, not the skin
	if player.hp <= 0:
		respawn_player()
	return final

func hurt_player_skill(power: float, status_kind: String, status_dur: float) -> void:
	# guest-side mirror of skill_hit's player branch: same power*0.6 rule,
	# applied against the guest's own armor/absorb locally (host never sees them)
	if (state != "play" and not net_live()) or player.dodge_t > 0:
		return
	if apply_player_damage(maxi(1, int(power * 0.6))) <= 0:
		return
	if status_kind != "":
		player_status(status_kind, status_dur) # the host already rolled the chance

var _sphere_tex := {} # sid -> orb sprite texture — same create-once contract as _drop_tex

func sphere_fly(sid: String, target: Kin) -> void:
	var spr := Sprite2D.new()
	if not _sphere_tex.has(sid):
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		var c := Color(ItemData.ITEMS.get(sid, {}).get("col", "#e05050"))
		img.fill(Color(0, 0, 0, 0))
		for yy in range(1, 9): # ink ring — the orb reads as a thrown print-thing
			for xx in range(1, 9):
				if xx in [1, 8] or yy in [1, 8]:
					img.set_pixel(xx, yy, Ink.INK)
		for yy in range(2, 8):
			for xx in range(2, 8):
				img.set_pixel(xx, yy, c)
		for xx in range(3, 7):
			img.set_pixel(xx, 2, Ink.PAPER) # top glint
		_sphere_tex[sid] = ImageTexture.create_from_image(img)
	spr.texture = _sphere_tex[sid]
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
	if client_locked():
		return 0
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
		log_msg(tr("Chest full - %d item(s) kept in bag") % skipped)
	return n

func chest_withdraw_all(st) -> int:
	if client_locked():
		return 0
	var n := 0
	for iid in st.get("store", {}).keys():
		add_item(iid, st["store"][iid])
		n += st["store"][iid]
	st["store"] = {}
	return n

# host-side validated container ops for guests. The ghost must be witnessed
# next to the box (same rule as demolition); deposits are whitelisted through
# ItemData + the stack cap + the food gate — whatever fails validation simply
# never reaches the store. Returns the accepted payload, {} when refused.
func chest_req_remote(pid: int, cell: Vector2i, op: String, payload: Dictionary) -> Dictionary:
	var st = structures.get(cell)
	if st == null or st["id"] not in ["chest", "feed_box"]:
		return {}
	if str(st.get("mimic", "")) != "":
		return {} # the grin doesn't trade
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(
			Vector2(cell.x + 0.5, cell.y + 0.5)) > 6.0:
		return {}
	if op == "wd":
		var taken := {}
		for iid in st.get("store", {}).keys():
			taken[iid] = int(st["store"][iid])
		st["store"] = {}
		return taken
	if op == "dep":
		var accepted := {}
		var claimed := 0
		for id in payload.keys():
			var iid := str(id)
			if not ItemData.ITEMS.has(iid) or iid == "gold_coin":
				continue # unknown ids and coin don't ride into shared storage
			var c := clampi(_i(payload[id]), 0, 999)
			if c <= 0 or not chest_can_take(st, iid):
				continue # stack cap reached or garbage count
			# a forged claim can only launder what the throttled request rate
			# allows — the per-call cap keeps one packet from dumping a save
			c = mini(c, 9999 - claimed)
			if c <= 0:
				break
			claimed += c
			if st["id"] == "feed_box" and int(ItemData.ITEMS.get(iid, {}).get("food", 0)) <= 0:
				continue # the feed box only takes food — same rule as the local path
			st["store"][iid] = int(st["store"].get(iid, 0)) + c
			accepted[iid] = int(accepted.get(iid, 0)) + c
		return accepted
	return {}

var death_marks: Array[Vector2] = [] # map tombstones where you dropped your pack (session-only)
var wear_by_id := {} # item_id -> remaining durability while unequipped — the
	# repair economy only survives if the count follows the ITEM, not the slot
	# (audit-41). Serialized "wearmap"; bounded by the ITEMS table.
func respawn_player() -> void:
	# the island rule: your pack spills where you fell; walk back to reclaim.
	# Guests skip the spill — spawn_drop is host-authoritative, so a client
	# would delete its bag into the void (drops exist only as net replicas).
	var dropped := 0
	if net == null or not net.is_client():
		for id in items.keys():
			if items[id] > 0:
				var a := rng.next() * TAU
				# corpse bags are mine-flagged: the 600s decay can't eat the
				# gear you died for — only you (or a hauler) takes it back
				var bx := player.pos.x + cos(a) * (0.4 + rng.next() * 0.8)
				var by := player.pos.y + sin(a) * (0.4 + rng.next() * 0.8)
				spawn_drop(id, items[id], nearest_free(bx, by), true) # never
				# inside a wall: an unreachable tombstone is loot lost forever
				dropped += items[id]
				items.erase(id) # don't leave ghost "x0" rows in the bag
				unequip_if_gone(id)
	if dropped > 0:
		log_msg(tr("You dropped %d items where you fell!") % dropped)
		log_msg(tr("Your pack lies where you fell — tombstone on the map (M)"))
		death_marks.append(player.pos) # the island tombstone: the map remembers the spill
		if death_marks.size() > 3:
			death_marks.pop_front() # only the freshest few spills earn a mark
	if player._mount_guard(): # dead men don't ride — and a stale ref can't ride either
		if net != null and net.is_client() and net_live() and player.mount.net_id > 0:
			# the host still thinks we're in the saddle — the replica ref
			# dies here, but mounted_by must be released host-side too.
			# ARM like every other sender: an unarmed release lets the
			# self-heal lane fire a second toggle inside the echo window —
			# and a toggle can't say "release only", so req#2 re-BINDS
			if not (net.mount_pending and net.mount_pending_uid == player.mount.net_id):
				net.mount_pending = true
				net.mount_pending_uid = player.mount.net_id
				net.rpc("mount_req", float(player.mount.net_id))
		else:
			_unbind_mount(player.mount)
		player.mount = null
	player.hp = int(player.max_hp * 0.5)
	player.hunger = 40.0
	player.statuses.clear()
	if kinbox_pos.x >= 0:
		var nb := nearest_kinbox(player.pos)
		player.pos = nearest_free(nb.x + 0.5, nb.y + 2.5)
	else: # no base yet: back to the landing point, not back into the jaws
		player.pos = nearest_free(world.spawn.x + 0.5, world.spawn.y + 0.5)
	log_msg(tr("You wake up battered at base…"))

func travel_nodes() -> Array:
	# every waypoint stone + every kinbox terminal is a node on the net
	var out := []
	for k in structures:
		var sid: String = structures[k]["id"]
		if sid == "waypoint" or sid == "kinbox":
			out.append({"key": k, "id": sid,
				"dist": player.pos.distance_to(Vector2(k.x, k.y))})
	out.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return out

func use_waypoint() -> void:
	# the island fast travel: touched stone opens the travel net
	if travel_nodes().size() < 2:
		log_msg(tr("The waypoint hums… but there's nowhere to go yet"))
		return
	panel = "travel"

func travel_to(k: Vector2i) -> void:
	if not structures.has(k):
		return
	var sid: String = structures[k]["id"]
	if sid != "waypoint" and sid != "kinbox":
		return
	player.pos = nearest_free(k.x + 0.5, k.y + 2.5)
	player.sync_screen()
	panel = ""
	floater(player.pos, tr("blink!"), "#7fc8f8")
	log_msg(tr("The waypoint net pulls you across the island"))

func is_night() -> bool:
	return tod >= 21.0 or tod < 5.0

func sleep_to_morning() -> void:
	if client_locked():
		return
	for q in pals:
		if q.hp > 0 and (q.raid or (q.mode == "wild" and q.aggro >= 0)):
			log_msg(tr("Can't sleep - hostiles are after you!"))
			return
	day += 1
	tod = 6.0
	player.hp = player.max_hp
	for q in pals:
		if q.mode == "base" or q.mode == "partner":
			q.hp = q.max_hp
			q.san = 100.0
			q.hunger = 60.0 # a night's fast, not a reset — the feed loop must matter
	for qb in bench: # orbs rest too — the island party pals wake fresh
		qb.hp = qb.max_hp
		qb.san = 100.0
		qb.hunger = 60.0
	log_msg(tr("You sleep until dawn. Day %d") % day)

func summon_raid() -> bool:
	if net != null and net.is_client():
		return false # the horn is the host's to sound
	if kinbox_pos.x < 0:
		log_msg(tr("Need a kinbox to summon the raid"))
		return false
	if pals.size() >= MAX_PALS:
		log_msg(tr("The island is too crowded for a raid boss"))
		return false # the cap binds attackers too — the horn refuses, sigil kept
	var pool: Array = SpeciesGen.zone_pool(3)
	if pool.is_empty():
		return false # trimmed species data can't mint a raid boss either
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	var bp := preload("res://src/kin.gd").new()
	bp.alpha = true
	bp.boss = true # set before setup so apply_bonuses folds the 2x in once
	entity_layer.add_child(bp)
	bp.setup(self, sid, 45, nearest_free(kinbox_pos.x + 2.5, kinbox_pos.y + 2.5))
	bp.sprite.scale = Vector2(2.2, 2.2)
	bp.sprite.position.y = -70.0
	bp.aggro = 0  # player — or the guest standing closest to the spawn
	bp.aggro_pid = bp.nearest_body_pid()
	bp.raid = true
	bp.set_meta("raid_t0", t)
	pals.append(bp)
	log_msg(tr("RAID BOSS: %s Lv45 approaches your base!") % tr(str(bp.spec["name"])))
	return true

var assist_t := 0.0
var prod_t := 0.0

func tick_spheres(dt: float) -> void:
	# orbs in flight — a tick_* function so the suite can drive the same wall
	# contract the frame loop pays (audit-43)
	for sp in spheres_flying.duplicate():
		sp["t"] += dt
		var tg: Kin = sp["target"]
		if is_instance_valid(tg):
			var f: float = minf(1.0, sp["t"] / 0.45)
			var tp: Vector2 = tg.pos
			var fp: Vector2 = sp["from"]
			var cur: Vector2 = fp + (tp - fp) * f
			var arc: float = sin(f * PI) * 24.0 # lobbed arc — cosmetic; the orb
			# itself is a projectile: it dies on the same walls a bolt does.
			# Lobbing over a sealed ring to poke (or bag) what the ring locks
			# in was free cheese (audit-43)
			var ci43 := Vector2i(int(cur.x), int(cur.y))
			if not world.in_bounds(ci43.x, ci43.y) \
					or world.decor_at(ci43.x, ci43.y) != World.Decor.NONE \
					or world.solid_structure(world.idx(ci43.x, ci43.y)) \
					or world.elev_at(ci43.x, ci43.y) > world.elev_at(int(fp.x), int(fp.y)):
				if is_instance_valid(sp["node"]):
					sp["node"].queue_free()
				spheres_flying.erase(sp)
				floater(cur, tr("clink!"), "#cfd6dd")
				continue # the wall caught it — no roll, no refund (it left your hand)
			var pp := Iso.to_screen(cur.x, cur.y, world.elev_at(int(cur.x), int(cur.y)))
			sp["node"].position = Vector2(pp.x, pp.y - 14 - arc)
		if sp["t"] > 0.45:
			# the island wobble theatre: the ball lands and rocks a beat before
			# the verdict — 3 shakes of tension, then resolve
			if not sp.has("wt"):
				sp["wt"] = 0.0
			sp["wt"] += dt
			if is_instance_valid(tg) and is_instance_valid(sp["node"]):
				var rock: float = sin(sp["wt"] * 18.0) * (6.0 if sp["wt"] < 0.9 else 3.0)
				var wpp := Iso.to_screen(tg.pos.x, tg.pos.y,
					world.elev_at(int(tg.pos.x), int(tg.pos.y)))
				sp["node"].position = Vector2(wpp.x + rock, wpp.y - 14)
			if sp["wt"] < 1.35:
				continue
			if is_instance_valid(sp["node"]):
				sp["node"].queue_free()
			resolve_sphere(sp)
			spheres_flying.erase(sp)

func tick_shadelump() -> void:
	# Shadelump's Dream Chaser (weirdest trick): a shadelump riding
	# BENCHED in your party still takes pot-shots at whatever you're fighting.
	var lead := party_pal()
	if lead == null or lead.mode != "partner" or lead.hp <= 0:
		return
	var d: Kin = null
	for i in range(1, party.size()):
		var bp := bench_pal_of(party[i])
		if bp != null and bp.species_id == "shadelump" and bp.hp > 0:
			d = bp
			break
	if d == null:
		return
	var tgt: Kin = null
	if is_instance_valid(focus_target) and focus_target.hp > 0 and t < focus_t \
			and world.los_clear(lead.pos, focus_target.pos):
		tgt = focus_target # it chases YOUR mark first — it's in the name
	else:
		tgt = nearest_wild(lead.pos, 10.0)
		if tgt != null and not world.los_clear(lead.pos, tgt.pos):
			tgt = null # a benched dream can't shoot through rock either (audit-43)
	if tgt == null or tgt.mode != "wild":
		return
	var datk := Combat.stat_at(d.spec["atk"], d.level, d.talent)
	tgt.hit(Combat.damage(datk, 14, Combat.stat_at(tgt.spec["def"],
		tgt.level, tgt.talent) * tgt.def_bonus * tgt.def_mult(), 1.0, rng), 1.0, true)
	floater(tgt.pos, tr("dream chaser!"), "#b06ee8")

func use_treasure_map() -> void:
	if not items.get("treasure_map", 0):
		return
	# a surveyor's chart picks real ground: open land, a decent walk away
	var spot := Vector2(-1, -1)
	for i in range(60):
		var a: float = rng.next() * TAU
		var d: float = 30.0 + rng.next() * 45.0
		var c := player.pos + Vector2(cos(a), sin(a)) * d
		var ix := int(c.x); var iy := int(c.y)
		if world.in_bounds(ix, iy) and world.tile_at(ix, iy) != World.Tile.WATER:
			spot = Vector2(ix + 0.5, iy + 0.5)
			break
	if spot.x < 0:
		log_msg(tr("The chart is illegible here — nothing to mark"))
		return # map stays in the pack
	items["treasure_map"] -= 1
	if items["treasure_map"] <= 0:
		items.erase("treasure_map")
	treasure = {"pos": spot}
	log_msg(tr("The chart marks a spot — check your map"))
	sfx_play("drop")

func dig_check() -> void: # called on the frame tick — standing on the X digs
	if lure and t > float(lure.get("till", 0.0)):
		lure = {} # the mash went cold — clear the stale pile
	if not treasure:
		return
	if player.pos.distance_to(treasure["pos"]) > 1.4:
		return
	if world.elev_at(int(player.pos.x), int(player.pos.y)) \
			!= world.elev_at(int(treasure["pos"].x), int(treasure["pos"].y)):
		return # a shovel can't reach up a cliff face (audit-43)
	treasure = {}
	var coin := rng.int_range(15, 40)
	add_item("gold_coin", coin)
	var bonus := rng.next()
	if bonus < 0.10:
		add_item("huge_kin_egg", 1)
	elif bonus < 0.45:
		add_item("lumenite", 4)
	elif bonus < 0.80:
		add_item("ingot", 3)
	else:
		add_item("mega_orb", 2)
	floater(player.pos, tr("TREASURE!"), "#ffd76e")
	log_msg(tr("Unearthed a cache: %d gold and a keepsake") % coin)
	sfx_play("level")

func pray_weather() -> void:
	if client_locked():
		return
	# the island weather-shrine: offer lumenite, cycle the sky. One altar's mood
	# is everyone's sky — the cooldown is global, not per building
	if t < pray_cd:
		log_msg(tr("The sky is still settling (%.0fs)") % (pray_cd - t))
		return
	if int(items.get("lumenite", 0)) < 3:
		log_msg(tr("The shrine wants 3 lumenite"))
		return
	var nxt: String = {"clear": "rain", "rain": "storm", "storm": "drought", "drought": "clear"}.get(weather, "rain")
	add_item("lumenite", -3)
	weather = nxt
	weather_t = 0.0 # the forced sky holds until the next natural roll
	pray_cd = t + 600.0
	log_msg({"rain": tr("You offer lumenite — rain answers"), "storm": tr("The altar drinks lumenite — thunder answers"),
		"drought": tr("The altar drinks lumenite — a dry wind answers"),
		"clear": tr("The offering burns off — the sky clears")}.get(nxt, tr("The sky shifts")))
	sfx_play("level")

func throw_bait() -> void:
	if not items.get("kin_bait", 0):
		return
	if net != null and net.is_client():
		# the lure is host truth — the ledger pays, the pile lands under the
		# ghost it saw, and bait_done settles the hold either way
		if net.pay("bait", {"kin_bait": 1}):
			net.rpc("bait_req")
			log_msg(tr("Bait tossed — something hungry will smell it"))
			sfx_play("drop")
		return
	items["kin_bait"] -= 1
	if items["kin_bait"] <= 0:
		items.erase("kin_bait")
	lure = {"pos": player.pos + player.facing * 3.0, "till": t + 25.0}
	log_msg(tr("Bait tossed — something hungry will smell it"))
	sfx_play("drop")

func throw_bait_remote(pid: int) -> bool:
	# host-side bait: the pile lands ahead of the ghost the wire saw, not at
	# a client-claimed spot. The bag debit already happened client-side —
	# bounded by the same bag-trust lane as every guest inventory claim.
	var at := _ghost_at(pid)
	if at.x < -1e8:
		return false # no ghost, no pile — the caller owes the ledger a refund
	if lure and t < float(lure.get("till", 0.0)):
		return false # a live pile is the island's single lure — can't be stomped
	lure = {"pos": at + Vector2(2.0, 0.0), "till": t + 25.0}
	note_remote(pid, "Bait tossed — something hungry will smell it")
	return true

func lure_take(p: Kin) -> void: # first snout to the pile eats it
	lure = {}
	p.hp = mini(p.max_hp, p.hp + int(p.max_hp * 0.1))
	floater(p.pos, tr("yum!"), "#d8b84a")

func fertilize() -> void:
	if client_locked():
		return
	# spread fertilizer on the nearest field — five minutes of surging crops
	var best: Vector2i = Vector2i(-1, -1)
	var bd := 4.5
	for k in structures:
		var st: Dictionary = structures[k]
		if k != st.get("pos"):
			continue
		if not StructureData.STRUCTURES.get(st["id"], {}).get("farmField", false):
			continue
		var d: float = player.pos.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if d < bd:
			bd = d; best = k
	if best.x < 0:
		log_msg(tr("Stand by a farm plot to spread it"))
		return
	structures[best]["fert"] = t + 300.0
	add_item("fertilizer", -1)
	floater(Vector2(best.x + 0.5, best.y + 0.5), tr("fertilized!"), "#a8c84a")
	log_msg(tr("%s surges for five minutes") % tr(str(StructureData.STRUCTURES[structures[best]["id"]]["name"])))

func cap_power_of(target: Kin) -> float:
	return Combat.cap_power(float(target.spec["capturePower"]), target.level, target.lucky)

func resolve_sphere(sp) -> void:
	var target: Kin = sp["target"]
	if not is_instance_valid(target) or target.hp <= 0 or target.mode != "wild":
		return # dead, freed, or already caught by another orb in flight
	if target.net_id > 0 and net != null and net.is_client():
		# a replica can't be rolled locally — the host owns the outcome;
		# the orb's flight was just theatre, the catch lands by snapshot
		net.rpc("sphere_catch", target.net_id, sp["sid"],
			sign(player.pos.x - target.pos.x) == -target.dir, player.capture_level)
		return
	if target.boss:
		floater(target.pos, tr("IMMUNE"), "#e8452f")
		return
	if not catchable(target):
		floater(target.pos, tr("IMMUNE"), "#e8452f")
		return
	var behind: bool = sign(player.pos.x - target.pos.x) == -target.dir # behind = player opposite the facing side
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var cap_pow: float = cap_power_of(target)
	var chance: float = minf(0.97, Combat.catch_chance(hp_frac, cap_pow,
		ItemData.ITEMS[sp["sid"]].get("spherePower", 26), target.any_status(), behind, player.capture_level))
	if randf() < chance:
		if party.size() >= party_cap() and box.size() >= MAX_BOX: # backstop: an over-stuffed box is real memory
			floater(target.pos, tr("BOX FULL"), "#e8963c")
			log_msg(tr("Kinbox is full (%d) - can't store %s") % [MAX_BOX, tr(str(target.spec["name"]))])
			target.aggro = -1
			return
		floater(target.pos, tr("★ CAUGHT!"), "#4dd0e1")
		sfx_play("catch")
		rumble(0.2, 0.7, 0.3) # a catch lands in the hand, not just the log
		cry_for(target.species_id) # a new friend announces itself
		log_msg(tr("Caught %s Lv%d!") % [tr(str(target.spec["name"])), target.level])
		gain_xp(catch_xp(target.level))
		if catch_streak >= 3:
			floater(target.pos, tr("STREAK x%d!") % catch_streak, "#ffd76e")
		# the island catch-count bonus: every 10th of a species pays a fat bonus
		catch_counts[target.species_id] = catch_counts.get(target.species_id, 0) + 1
		board_hunt_credit(target.species_id) # a boxed pal still thins the herd
		if catch_counts[target.species_id] % 10 == 0:
			var bonus := target.level * 8
			gain_xp(bonus)
			floater(target.pos, tr("CATCH x%d! +%dxp") % [catch_counts[target.species_id], bonus], "#ffd76e")
			log_msg(tr("%dth %s caught - bonus XP!") % [catch_counts[target.species_id], tr(str(target.spec["name"]))])
		if catch_counts[target.species_id] == 10: # kindex mastery unlocks — sharpen the whole line
			log_msg(tr("Kindex mastery: %s +10%%") % tr(str(target.spec["name"])))
			for mp in pals:
				if mp.mode != "wild" and mp.species_id == target.species_id:
					mp.apply_bonuses()
		target.statuses.clear()
		target.aggro = -1
		release_event_flags(target)
		_reden_legend(target)
		if party.size() < party_cap(): # the island rule: catch joins the party until it's full
			if _bench_add(target): # orbs ride in the same cold store as the box — a saturated bench overflows there too
				party.append(target.uid)
				log_msg(tr("%s joins your party (%d/%d)") % [tr(str(target.spec["name"])), party.size(), party_cap()])
				if party_pal() == null:
					send_out(target.uid) # an empty slot means the new catch takes the field
			# false → the overflow lane already boxed or freed it — no double add
		else:
			target.mode = "box"
			pals.erase(target)
			if box.size() < MAX_BOX + 32: # same soft cap _bench_add overflows into
				box.append(target)
				box_pal(target)
			else:
				target.queue_free() # every store capped — dies clean, no unbound kin
	else:
		floater(target.pos, tr("…broke free"), "#e8963c")
		sfx_play("fail")
		log_msg(tr("%s broke free (%d%%)") % [tr(str(target.spec["name"])), int(chance * 100)])
		catch_fail()
		target.aggro = 0 if target.hostile() >= 1 else -1
		target.aggro_pid = 0 # the local keeper threw the orb — the heat is his

# one ballability gate for both catch chokes — ownable species, and for
# legends specifically an ALPHA: den heirs roam as alphas, while the same
# species fielded without it (phase-2 adds, sigil raiders, grotto spares)
# stays orb-immune — the den keeps its cadence as the only legend channel
func catchable(c: Kin) -> bool:
	return ownable(c.species_id) and \
		(c.species_id not in LEGENDARY_DEN or c.alpha)

func _reden_legend(c: Kin) -> void:
	# catching the den's legend doesn't kill the site — the ring calls a new
	# warden a day and a half on (a catchable one, like the last)
	if c.species_id in LEGENDARY_DEN and c.alpha and c.home != Vector2.ZERO \
			and boss_respawns.size() < MAX_RESPAWNS:
		boss_respawns.append({"sid": c.species_id, "lv": c.level,
			"pos": [c.home.x, c.home.y], "alpha": true, "boss": false,
			"at": t + DAY_LEN * 1.5})
		log_msg(tr("The den will call a new legend"))

func release_event_flags(p: Kin) -> void:
	# a caught kin stops being an invader: raid/gauntlet metas mark a
	# "temporary attacker" — without this a caught raider keeps the danger
	# drone on, blocks sleep forever, and its gauntlet wave never counts down
	if p.has_meta("gauntlet") and not gauntlet.is_empty():
		gauntlet["left"] -= 1
		p.remove_meta("gauntlet")
	p.raid = false
	if p.has_meta("raid_t0"):
		p.remove_meta("raid_t0")
	if p.has_meta("summoner"):
		p.remove_meta("summoner") # a caught add stops counting for its boss

func catch_xp(lv: float) -> int:
	# streak rewards a steady hand: +5% per consecutive catch, cap +50%
	catch_streak += 1
	return int(round(lv * 3.0 * (1.0 + minf(0.5, catch_streak * 0.05))))

func catch_fail() -> void:
	if catch_streak >= 3:
		log_msg(tr("Catch streak ends at %d") % catch_streak)
	catch_streak = 0

func net_catch(nid: int, sid: String, behind: bool, cap_lv: int, pid: int) -> void:
	# Host-authoritative catch for a client's throw. The wire id is our own
	# uid (client replicas mirror it). The world is shared, the roster is
	# not: the catch answers to the keeper who threw the ball.
	var target: Kin = find_pal(nid)
	if target == null or target.mode != "wild" or target.hp <= 0 or target.boss \
			or not catchable(target): # the catchable gate — same rule as resolve_sphere
		return
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(target.pos) > 9.0:
		return # fail closed: an orb can't land nine tiles from the thrower
	if not world.los_clear(Vector2(gp.net_pos.x, gp.net_pos.y), target.pos):
		return # ...or through a wall — same rule the host's flight pays (audit-43)
	var sp_pow: float = float(ItemData.ITEMS.get(sid, {}).get("spherePower", 0.0))
	if sp_pow <= 0.0:
		return # forged item ids don't get free rolls
	# the client claims "behind" — the host re-derives it from the ghost it
	# actually saw; trust inputs, not conclusions
	behind = sign(gp.net_pos.x - target.pos.x) == -target.dir
	var hp_frac := maxf(0, target.hp) / target.max_hp
	var cap_pow: float = cap_power_of(target)
	var chance: float = minf(0.97, Combat.catch_chance(hp_frac, cap_pow,
		sp_pow, target.any_status(), behind, cap_lv))
	if randf() < chance:
		var rp := rparty_for(pid)
		# per-owner lane AND the global bound: one guest's roster can't push
		# the shared box past what every local path already enforces
		if rp.size() >= party_cap() and (box_count_of(pid) >= MAX_BOX or box.size() >= MAX_BOX):
			floater(target.pos, tr("BOX FULL"), "#e8963c")
			log_msg(tr("Kinbox is full (%d) - %s got away") % [MAX_BOX, tr(str(target.spec["name"]))])
			return
		floater(target.pos, tr("★ CAUGHT!"), "#4dd0e1")
		cry_for(target.species_id)
		if net != null and multiplayer.multiplayer_peer != null \
				and multiplayer.get_peers().has(pid):
			net.rpc_id(pid, "net_floater", target.pos.x, target.pos.y, "★ CAUGHT!", "#4dd0e1")
		log_msg(tr("Player %d caught %s Lv%d — into their kinbox") % [pid, tr(str(target.spec["name"])), target.level])
		note_remote(pid, "You caught %s Lv%d", [target.spec["name"], target.level])
		board_hunt_credit(target.species_id, pid) # a boxed pal still thins the herd — theirs counts too
		_kill_xp(pid, int(round(target.level * 3.0))) # flat rate — catch_xp would feed the HOST'S streak
		catch_counts[target.species_id] = catch_counts.get(target.species_id, 0) + 1
		# world ledger above (accord/dex track the island's whole catalog) —
		# the guest's own ledger rides home so THEIR kindex/missions can tick
		if net.multiplayer.get_peers().has(pid):
			net.rpc_id(pid, "catch_credit", target.species_id)
		if catch_counts[target.species_id] == 10: # kindex mastery unlocks — sharpen the whole line
			log_msg(tr("Kindex mastery: %s +10%%") % tr(str(target.spec["name"])))
			for mp in pals:
				if mp.mode != "wild" and mp.species_id == target.species_id:
					mp.apply_bonuses()
		target.statuses.clear()
		target.aggro = -1
		release_event_flags(target)
		_reden_legend(target)
		target.owner_id = pid
		target.owner_tag = str(net.peer_tags.get(pid, "")) if net != null else ""
		if rp.size() < party_cap(): # a catch joins the party until the strip is full
			if _bench_add(target):
				rp.append(target.uid)
				if r_out_pal(pid) == null:
					r_send_out(target.uid, pid) # an empty strip means the catch takes the field
			# false → the overflow lane already boxed it — no double add
		else:
			target.mode = "box"
			pals.erase(target)
			if box.size() < MAX_BOX + 32: # same soft cap _bench_add overflows into
				box.append(target)
				box_pal(target)
			else:
				target.queue_free() # every store capped — dies clean, no unbound kin
	else:
		floater(target.pos, tr("…broke free"), "#e8963c")
		log_msg(tr("%s broke free from player %d's orb") % [tr(str(target.spec["name"])), pid])
		target.aggro = 0 if target.hostile() >= 1 else -1
		target.aggro_pid = pid if target.aggro == 0 else 0

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
	floater(Vector2(tx + 0.5, ty + 0.5), tr("thwack"), "#c8d3d5")
	if world.hp[i] == 0:
		var loot: String = {World.Decor.TREE_A: "wood", World.Decor.TREE_B: "wood",
			World.Decor.ROCK: "stone", World.Decor.ORE_GOLD: "ore",
			World.Decor.ORE_COAL: "coal", World.Decor.BERRY: "red_berries",
			World.Decor.STUMP: "wood"}[d]
		var n: int = 1 if d == World.Decor.BERRY else rng.int_range(1, 3)
		spawn_drop(loot, n, Vector2(tx + 0.5, ty + 0.5))
		if d in [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL] \
				and rng.next() < 0.12:
			# a rare shard in the rubble — lumenite stays renewable after the
			# drift cargo is spent, or mission 1 could brick on a whim offering
			spawn_drop("lumenite", 1, Vector2(tx + 0.5, ty + 0.5))
			log_msg(tr("A lumenite shard gleams in the rubble"))
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

func spawn_drop(id: String, n: int, at: Vector2, mine := false) -> void:
	if net != null and net.is_client():
		return # every synced bag arrives via net_drops — a local copy would
		# pay twice: once on walk-over, once through the take_drop RPC
	# tiny tinted bag icon; drops persist until picked up (player or hauler kin)
	if drops.size() >= MAX_DROPS:
		var ev: Dictionary = {} # flood backstop: evaporate the oldest plain bag —
		for dd2 in drops: # a corpse bag is NEVER the backstop's victim; at
			if not dd2.get("mine", false): # full-mine saturation the new drop
				ev = dd2 #               simply can't land (audit-41)
				break
		if ev.is_empty():
			return
		take_drop(ev)
	drops.append({"id": id, "n": n, "pos": at, "node": drop_sprite(id, at),
		"cool": 0.0, "age": 0.0, "did": next_drop_id, "mine": mine})
	next_drop_id += 1

func drop_sprite(id: String, at: Vector2) -> Sprite2D:
	var tid := id if ItemData.ITEMS.has(id) else "_unk" # forged wire ids share one texture — the cache can't be flooded
	if not _drop_tex.has(tid):
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		var c := Color(ItemData.ITEMS.get(tid, {}).get("col", "#c8b070"))
		img.fill(Ink.INK) # ink frame — a dropped thing reads as a printed chip
		for yy in range(2, 8):
			for xx in range(2, 8):
				img.set_pixel(xx, yy, c)
		img.set_pixel(2, 2, Ink.PAPER) # paper glint, top-left
		_drop_tex[tid] = ImageTexture.create_from_image(img)
	var spr := Sprite2D.new()
	spr.texture = _drop_tex[tid]
	var p := Iso.to_screen(at.x, at.y, world.elev_at(int(at.x), int(at.y)))
	spr.position = Vector2(p.x, p.y - 2)
	entity_layer.add_child(spr)
	return spr

# client replica set for host drops — same reconcile rules as pal_sync:
# packet carries the whole truth, missing dids despawn
func drop_sync(arr: Array) -> void:
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 5 or not _fin(e[0]):
			continue
		var did := int(e[0])
		seen[did] = true
		if net_drops.has(did):
			continue
		var id := str(e[1])
		var at := Vector2(_f(e[3]), _f(e[4]))
		if net_drops.size() >= MAX_DROPS:
			continue # a hostile or buggy host can't stuff our sprite RAM either
		net_drops[did] = {"id": id, "n": maxi(_i(e[2]), 0), "pos": at, "node": drop_sprite(id, at)}
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

# condense costs: star 0->1 needs 4 fodder, then 16/32/64 (the island ladder)
const CONDENSE_COST := [4, 16, 32, 64]

func condense_active() -> void:
	if party.is_empty():
		log_msg(tr("No active kin to condense"))
		return
	var ap0: Kin = lead_pal()
	if ap0 != null and ap0.star < CONDENSE_COST.size():
		var need0: int = CONDENSE_COST[ap0.star]
		var have0 := 0
		for bp0 in box:
			if bp0.species_id == ap0.species_id and bp0.owner_id == 0:
				have0 += 1
		if have0 >= need0:
			if t > condense_arm: # first E previews; second E within 4s commits
				condense_arm = t + 4.0
				log_msg(tr("Press E again to consume %d %s -> star %d") % [need0, tr(str(ap0.spec["name"])), ap0.star + 1])
				return
			condense_arm = 0.0
	var ap: Kin = lead_pal()
	if ap == null:
		return
	if ap.star >= CONDENSE_COST.size():
		log_msg(tr("%s is already max star") % tr(str(ap.spec["name"])))
		return
	var need: int = CONDENSE_COST[ap.star]
	# fodder = same-species kin in the box (weakest first, active excluded)
	var fodder: Array = []
	for bp in box:
		if bp.species_id == ap.species_id and bp.uid != ap.uid and not bp.fav and bp.owner_id == 0:
			fodder.append(bp) # heart-locked pals are never fodder — nor are guests'
	fodder.sort_custom(func(a, b): return a.level < b.level)
	if fodder.size() < need:
		log_msg(tr("Need %d same-species kin for star %d (have %d)") % [need, ap.star + 1, fodder.size()])
		return
	for i in need:
		var fp: Kin = fodder[i]
		box.erase(fp)
		fp.free() # already erased — free() on the in-tree node is legal and immediate
	ap.condense()
	log_msg(tr("%s condensed to star %d!") % [tr(str(ap.spec["name"])), ap.star])

func eat_food_item() -> int:
	# feed-box rule: kin eat the cheapest stored food — feed_box store
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
	# party kin eat straight from the player's inventory (the island rule)
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
	# sick kin self-medicate (the island): partner eats from the player's bag,
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

# gamepad layer: bindings are added at runtime so project.godot's input map
# stays keyboard-clean, and headless runs bind identically. ui_* actions keep
# Godot's built-in pad defaults (A confirm, dpad/stick nav) — but every action
# we touch is first stripped of joypad events, so binding is idempotent across
# scene reloads and no gameplay button may share a ui_* action (B would dodge
# AND pause). Pad menu cancel lives on Start.
func _pad_erase(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			InputMap.action_erase_event(action, e)

func _pad_btn(action: String, b: int) -> void:
	_pad_erase(action)
	var e := InputEventJoypadButton.new()
	e.button_index = b
	InputMap.action_add_event(action, e)

func _pad_axis(action: String, ax: int, v: float) -> void:
	_pad_erase(action)
	var e := InputEventJoypadMotion.new()
	e.axis = ax
	e.axis_value = v
	InputMap.action_add_event(action, e)

func bind_gamepad() -> void:
	_pad_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_pad_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_pad_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_pad_axis("sprint", JOY_AXIS_TRIGGER_LEFT, 1.0) # LT held = sprint
	if not InputMap.has_action("pad_strike"):
		InputMap.add_action("pad_strike") # RT: swing when idle, throw when aiming
	_pad_axis("pad_strike", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_btn("interact", JOY_BUTTON_A)
	_pad_btn("dodge", JOY_BUTTON_B)
	_pad_btn("aim", JOY_BUTTON_X)
	_pad_btn("cycle_sphere", JOY_BUTTON_Y)
	_pad_btn("party_toggle", JOY_BUTTON_RIGHT_SHOULDER)
	_pad_btn("pal_stance", JOY_BUTTON_LEFT_SHOULDER)
	_pad_btn("build", JOY_BUTTON_BACK)
	_pad_btn("ui_cancel", JOY_BUTTON_START) # erase also drops default B cancel
	# the dpad is the pad's spare hand — a pad-only keeper must eat, ride,
	# open the map and fire the partner skill, not just dodge (audit-34)
	_pad_btn("inv", JOY_BUTTON_DPAD_UP)
	_pad_btn("ride", JOY_BUTTON_DPAD_RIGHT)
	_pad_btn("partner_skill", JOY_BUTTON_DPAD_LEFT)
	_pad_btn("map", JOY_BUTTON_DPAD_DOWN)
	_pad_btn("demolish", JOY_BUTTON_LEFT_STICK) # L3: nearest-structure raze
	if not InputMap.has_action("pad_next_pal"):
		InputMap.add_action("pad_next_pal") # R3: field-swap — the pad's 1-9
	_pad_btn("pad_next_pal", JOY_BUTTON_RIGHT_STICK)
	_pad_axis("zoom_in", JOY_AXIS_RIGHT_Y, -1.0)
	_pad_axis("zoom_out", JOY_AXIS_RIGHT_Y, 1.0)

func net_live() -> bool:
	# presence is not liveness — a half-open dial isn't a session either; only a
	# connected peer keeps the sim's online behavior armed
	var p = null if net == null else net.multiplayer.multiplayer_peer
	return p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

# ---- contextual hints: condition-driven, self-retiring nudges ----
# Each entry: condition lambda -> text. A hint shows while its condition is
# true; most retire permanently once their action happened (or after `once`
# seconds of cumulative display). Max 3 on screen.
var HINTS := [
	{"id": "orb", "once": 20.0,
	 "text": "Q aims — weaken a wild kin first, then throw (low HP catches easier)",
	 "touch": "AIM + ATK throws — weaken it first",
	 "pad": "X aims — weaken it first, then RT throws",
	 "cond": func(g): return g.item_count("kin_orb") > 0 and g.catch_counts.is_empty() and g.player != null},
	{"id": "chop", "once": 15.0,
	 "text": "LMB swings — trees drop wood, rocks drop stone, berries feed you",
	 "touch": "ATK swings — trees drop wood, rocks drop stone",
	 "pad": "RT swings — trees drop wood, rocks drop stone, berries feed you",
	 "cond": func(g): return g.item_count("wood") == 0 and g.item_count("stone") == 0},
	{"id": "build", "once": 25.0,
	 "text": "B builds — a workbench turns wood + stone into gear",
	 "touch": "BLD builds — a workbench turns wood + stone into gear",
	 "pad": "Back builds — a workbench turns wood + stone into gear",
	 "cond": func(g): return g.kinbox_pos.x >= 0 and not g.structures.values().any(func(s): return s["id"] == "workbench")},
	{"id": "kinbox", "once": 30.0,
	 "text": "B builds — your kinbox wants 4 lumenite + 6 wood + 6 stone",
	 "touch": "BLD builds — your kinbox wants 4 lumenite + 6 wood + 6 stone",
	 "pad": "Back builds — your kinbox wants 4 lumenite + 6 wood + 6 stone",
	 "cond": func(g): return g.kinbox_pos.x < 0},
	{"id": "guide", "once": 12.0,
	 "text": "N opens the field guide — every verb lives there",
	 "touch": "≡ → GUIDE — every verb lives there",
	 "pad": "Start → GUIDE — every verb lives there",
	 "cond": func(g): return g.t > 30.0},
	{"id": "eat", "once": 12.0,
	 "text": "You're starving — eat berries or cooked food (I opens the bag)",
	 "touch": "You're starving — eat berries or cooked food (INV opens the bag)",
	 "pad": "You're starving — eat berries or cooked food (dpad-up opens the bag)",
	 "cond": func(g): return g.player != null and g.player.hunger < 25.0},
	{"id": "dusk", "once": 18.0,
	 "text": "Sun's dropping — B builds a campfire (6w 3s), a straw bed sleeps",
	 "touch": "Sun's dropping — BLD builds a campfire, a straw bed sleeps",
	 "pad": "Sun's dropping — Back builds a campfire, a straw bed sleeps",
	 "cond": func(g): return g.tod >= 19.0 and g.tod < 21.0 and g.nearest_heat(g.player.pos) > 10.0},
	{"id": "night", "once": 15.0,
	 "text": "Night bites cold — stand by a campfire or a fire-kin",
	 "cond": func(g): return g.is_night() and g.player != null and g.nearest_heat(g.player.pos) > 10.0},
	{"id": "san", "once": 15.0,
	 "text": "A kin is flagging — feed it and let it rest",
	 "cond": func(g): return g.pals.any(func(q): return q.mode in ["partner", "base"] and q.san < 30.0)},
]
var hint_seen := {} # id -> cumulative seconds shown
var using_pad := false # last-seen device: hints swap Q/click for X/RT
var touch_ui := false    # on-screen stick + verb buttons (auto = touchscreen present)

func active_hints() -> Array:
	if state != "play" or player == null:
		return []
	var out := []
	for h in HINTS:
		if out.size() >= 3:
			break
		if float(hint_seen.get(h["id"], 0.0)) >= h["once"]:
			continue # retired after its fair share of screen time
		if h["cond"].call(self):
			out.append(h)
	return out

func tick_hints(dt: float) -> void:
	for h in active_hints():
		hint_seen[h["id"]] = float(hint_seen.get(h["id"], 0.0)) + dt

# day/night pad crossfade — runs in every state so the title breathes too
var net_danger := false # client's mirror of the host's threat verdict — env_sync keeps it true during raids
func danger_active() -> bool:
	if net != null and net.is_client():
		return net_danger # a client can't see raid flags — the host ships the verdict at 2Hz
	# what makes the island tense: a live raid wave, a running gauntlet,
	# or an enraged (phase-2) boss still standing
	if not gauntlet.is_empty():
		return true
	for q in pals:
		if q.hp > 0 and (q.raid \
				or (q.boss and q.phase == 2 and (q.aggro >= 0 or q.aggro_pid > 0))):
			# a leashed home-walking phase-2 boss is dormant, not danger — the
			# drone stands down until it re-engages (audit-40)
			return true
	return false

func tick_music(dt: float) -> void:
	if music_day == null:
		return
	var night := is_night()
	var danger := danger_active()
	music_danger.volume_db = move_toward(music_danger.volume_db, -9.0 if danger else -80.0, dt * 8.0)
	# while the drone is up the pastoral pads duck fully under it — and they
	# come back faster while it's still ringing, so a raid's end has no dead air
	var ambient_rate := 9.0 if music_danger.volume_db > -40.0 else 6.0
	music_day.volume_db = move_toward(music_day.volume_db, -80.0 if (night or danger) else -10.0, dt * ambient_rate)
	music_night.volume_db = move_toward(music_night.volume_db, -10.0 if (night and not danger) else -80.0, dt * ambient_rate)

func _process(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 3.5)
	tick_music(dt)
	if state != "play" and not net_live():
		return # title/pause freeze the island's clock (net sessions never pause)
	t += dt
	tick_hints(dt)
	if net == null or not net.is_client(): # clients take tod from env_sync — the host's clock owns the sky
		# day 1 runs at half rate: the first dusk lands ~4 min in, not ~2 —
		# the tutorial arc can't fit inside 130 seconds of daylight
		tod += dt / DAY_LEN * 24.0 * (0.5 if day == 1 else 1.0)
		if tod >= 24.0:
			tod -= 24.0
			day += 1

	tick_spheres(dt)
	prod_t += dt # production math is linear in dt — batching to ~4Hz drops the
	if prod_t >= 0.25: # per-frame structure sweeps (consume_ready/banner/well) to a quarter
		tick_production(prod_t)
		prod_t = 0.0
	dig_check()
	tick_merchant(dt)
	tick_boss_respawns()
	assist_t += dt
	if assist_t >= 3.0:
		assist_t = 0.0
		tick_shadelump()
	spoil_t += dt
	if spoil_t >= 480.0: # perishables rot on their own clock — local bag, client-safe
		spoil_t = 0.0
		tick_spoilage()
	tick_gauntlet()
	tick_repairs(dt)
	tick_crafts(dt)
	tick_assign(dt)
	tick_missions(dt)
	reveal_t += dt # fog of war: sight peels twice a second, wherever you stand
	if reveal_t >= 0.5:
		reveal_t = 0.0
		reveal_at(player.pos, 12.0)
	tick_dex(dt)
	tick_weather(dt)
	update_projectiles(dt)
	tick_box(dt)
	tick_death_marks()
	# floaters age
	for f in floaters:
		f["age"] += dt
	floaters = floaters.filter(func(f): return f["age"] < 1.2)
	# ground-drop pickup on walk-over (host only — a client's bags live in
	# net_drops and pay through the take_drop RPC, never this loop)
	if net == null or not net.is_client():
		for i in range(drops.size() - 1, -1, -1):
			var d: Dictionary = drops[i]
			d["age"] = d.get("age", 0.0) + dt
			if d["age"] > 600.0 and not d.get("mine", false):
				# old loot decays — else the world fills with bags; a corpse
				# spill is the player's own pack, it waits for the walk back
				take_drop(d)
				continue
			if d["cool"] > 0.0:
				d["cool"] = d["cool"] - dt
				continue
			if player.pos.distance_squared_to(d["pos"]) < 0.55:
				add_item(d["id"], d["n"])
				floater(d["pos"], tr("+%d %s") % [d["n"], tr(str(ItemData.ITEMS.get(d["id"], {}).get("name", d["id"])))], "#ffe08a")
				if "egg" in d["id"]:
					anger_nesters(d["pos"]) # the island: parents guard their nests — egg thieves get swarmed
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
	# respawn trickle + stump regrow + raid sweep are world mutations —
	# host territory; a client replays them and gets phantom divergence
	if net == null or not net.is_client():
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
		tick_raider_sweep()
	tick_migration(dt) # deliberate local-fauna authority — see tick_migration

func tick_raider_sweep() -> void:
	# stale raiders wander off instead of stacking up. Gauntlet pals are
	# exempt while the trial lives — a timeout that counts as a kill pays the
	# trial for kiting laps; they aggro the keeper till it ends. With no live
	# trial even a boss-flagged raider is a temporary invader: a mid-gauntlet
	# save would otherwise strand it here forever — uncatchable, permanent,
	# sleep-blocking (audit-40).
	for q in pals.duplicate():
		if q.mode == "wild" and q.raid and (gauntlet.is_empty() \
				or (not q.boss and not q.has_meta("gauntlet"))) \
				and t - q.get_meta("raid_t0", t) > 240.0:
			pals.erase(q)
			q.queue_free()

# ---------- building / tech / crafting / base ----------

func buildable_list() -> Array:
	# only tech nodes that are actual structures — spear/orb/axe techs
	# unlock recipes, not buildings (selecting them crashed place_structure)
	var out := unlocked.filter(func(id): return StructureData.STRUCTURES.has(id))
	if net != null and net.is_client() and not net_unlocked.is_empty():
		# the host's tech is the bar — a fresh guest on a developed island
		# builds what the HOST researched, not what their own save knows
		out = net_unlocked.filter(func(id): return StructureData.STRUCTURES.has(id))
	return out

func can_place(sid: String, tx: int, ty: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty():
		return false
	if sid == "kinbox" and kinbox_count() >= 1 + MAX_EXTRA_BOXES:
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
	if s.get("needsWater", false):
		var shore := false
		for dy in range(-1, h + 1):
			for dx in range(-1, w + 1):
				var nx := tx + dx; var ny := ty + dy
				if dx >= 0 and dx < w and dy >= 0 and dy < h:
					continue # footprint itself is land
				if world.in_bounds(nx, ny) and world.tile_at(nx, ny) == World.Tile.WATER:
					shore = true
		if not shore:
			return false
	return true

func kinbox_count() -> int:
	var seen := []
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] == "kinbox" and st not in seen:
			seen.append(st) # footprint cells share one st dict — dedupe
	return seen.size()

func nearest_kinbox(at: Vector2) -> Vector2i:
	var best := kinbox_pos
	var bd := INF
	if kinbox_pos.x >= 0:
		bd = at.distance_to(Vector2(kinbox_pos))
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
			log_msg(tr("Can't build there"))
			return false
		var cost := {}
		for c in s.get("cost", []):
			if item_count(c[0]) < c[1]:
				log_msg(tr("Need %d %s") % [c[1], tr(str(ItemData.ITEMS.get(c[0], {}).get("name", c[0])))])
				return false
			cost[str(c[0])] = int(c[1])
		if not net.pay("build", cost): # ledger full — the click resolves as a refusal, not a silent send
			return false
		net.rpc("build_req", sid, tx, ty) # ledger pays the debit — every deny path refunds the hold, not the price table
		return true
	if sid == "kinbox" and kinbox_count() >= 1 + MAX_EXTRA_BOXES:
		log_msg(tr("Max %d kinboxes (base + outposts)") % (1 + MAX_EXTRA_BOXES))
		return false
	var seen_st := []
	for k in structures:
		if structures[k] not in seen_st:
			seen_st.append(structures[k]) # dedupe footprint cells → true count
	if seen_st.size() >= MAX_STRUCTURES:
		log_msg(tr("Build limit reached (%d)") % MAX_STRUCTURES)
		return false
	for c in s.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg(tr("Need %d %s") % [c[1], tr(str(ItemData.ITEMS.get(c[0], {}).get("name", c[0])))])
			return false
	var e0: int = world.elev_at(tx, ty)
	for dy0 in range(s.get("h", 2)):
		for dx0 in range(s.get("w", 2)):
			if not world.in_bounds(tx + dx0, ty + dy0):
				log_msg(tr("Can't build off the map"))
				return false
			if structures.has(Vector2i(tx + dx0, ty + dy0)):
				log_msg(tr("Blocked: something already built there"))
				return false
			if world.decor[world.idx(tx + dx0, ty + dy0)] in [World.Decor.ROCK, World.Decor.ORE_GOLD, World.Decor.ORE_COAL]:
				log_msg(tr("Can't build on exposed rock"))
				return false # ore/rock outcrops are terrain — clear trees but not these
			if world.tile_at(tx + dx0, ty + dy0) == World.Tile.WATER:
				log_msg(tr("Can't build on water"))
				return false
			if world.elev_at(tx + dx0, ty + dy0) != e0:
				log_msg(tr("Can't build across a ledge"))
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
		"turret": s.get("turret", 0), "snare": s.get("snare", false),
		"pos": Vector2i(tx, ty)}
	for dy in range(h):
		for dx in range(w):
			var ci0 := world.idx(tx + dx, ty + dy)
			if world.decor[ci0] != World.Decor.NONE: # trees/berries under the footprint are cleared
				world.decor[ci0] = World.Decor.NONE
				world.hp[ci0] = 0
				mark_decor(ci0)
			structures[Vector2i(tx + dx, ty + dy)] = st
			_struct_gen += 1
			world.structures[ci0] = st
	if sid == "kinbox":
		if kinbox_pos.x < 0:
			kinbox_pos = Vector2i(tx, ty)
			log_msg(tr("Base established! E on the kinbox posts a kin to the yard."))
			# first-base grace: the island lets a fresh keeper breathe — the
			# opening raid can't land inside the same breath that raised it
			raid_t = maxf(raid_t, DAY_LEN + 60.0)
		else:
			extra_boxes.append(Vector2i(tx, ty))
			log_msg(tr("Outpost kinbox online — shared box network"))
	log_msg(tr("Built %s") % tr(str(s["name"])))
	sfx_play("build")
	return true

func place_free(sid: String, tx: int, ty: int, store: Dictionary = {}) -> bool:
	# Cost-free placement used by net state_sync and world-gen lair markers.
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty():
		return false
	var seen_st := {}
	for k in structures:
		seen_st[structures[k]] = true # cells→structures dedupe, same count as the build verbs
	if seen_st.size() >= MAX_STRUCTURES:
		return false # wire callers bypass the verb caps — the bound lives at the choke point
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
	var st := {"id": sid, "node": spr, "timer": 0.0, "workers": [], "store": store.duplicate(),
		"hp": s.get("hp", 4000 if s.get("anchor", false) else 200),
		"walkable": s.get("walkable", false), "spike": s.get("spike", 0),
		"turret": s.get("turret", 0), "snare": s.get("snare", false),
		"pos": Vector2i(tx, ty)}
	for dy in range(h):
		for dx in range(w):
			var ci1 := world.idx(tx + dx, ty + dy)
			if world.decor[ci1] != World.Decor.NONE: # clear whatever the footprint lands on
				world.decor[ci1] = World.Decor.NONE
				world.hp[ci1] = 0
				mark_decor(ci1)
			structures[Vector2i(tx + dx, ty + dy)] = st
			_struct_gen += 1
			world.structures[ci1] = st
	if sid == "kinbox":
		var o := Vector2i(tx, ty)
		if kinbox_pos.x < 0:
			kinbox_pos = o
			# same first-base grace as the local build path — a guest raising
			# the island's first kinbox buys the yard its quiet day too
			raid_t = maxf(raid_t, DAY_LEN + 60.0)
		elif o != kinbox_pos and o not in extra_boxes and extra_boxes.size() < MAX_EXTRA_BOXES:
			extra_boxes.append(o)
	return true

# X-key demolish: removes the structure under a tile, refunds half cost,
# returns chest contents, unassigns workers.
func demolish_at(at: Vector2) -> bool:
	var st = structure_at(at)
	if not st:
		log_msg(tr("Nothing to demolish"))
		return false
	if StructureData.STRUCTURES.get(st["id"], {}).get("anchor", false):
		if st.get("pos") == kinbox_pos and extra_boxes.is_empty():
			log_msg(tr("The kinbox anchors the base — nobody razes it"))
			return false # the LAST anchor seals the box and the respawn point
		# backups exist or this IS a backup — the box network survives the raze
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
	var xp1: Kin = st.get("exp_pal") # a demolished post recalls its expedition pal
	if is_instance_valid(xp1) and xp1.mode == "expedition":
		xp1.mode = "base"; xp1.visible = true
		xp1.job_site = null
		xp1.pos = Vector2(cells[0].x + 0.5, cells[0].y + 0.5)
	for it in st.get("store", {}).keys():
		add_item(it, st["store"][it])
	var inc_dm: Dictionary = st.get("egg_inc", {}) # razing a loaded incubator refunds the egg — and sends its claimed bloodline home to the ranch ledger
	if not inc_dm.is_empty():
		add_item("huge_kin_egg" if inc_dm.get("huge", false) else ("bred_kin_egg" if inc_dm.get("pair") != null else "kin_egg"), 1)
		if not cells.is_empty():
			_return_egg_parent(inc_dm.get("pair"), Vector2(cells[0].x + 0.5, cells[0].y + 0.5))
	st["store"] = {} # refunded — an open chest panel must not re-withdraw these
	for c in StructureData.STRUCTURES[sid].get("cost", []):
		add_item(c[0], int(ceil(c[1] * 0.5)))
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	_struct_gen += 1
	st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null # the panel's container just died — stop referencing it
	if sid == "kinbox" and not cells.is_empty():
		_kinbox_anchor_gone(cells)
	log_msg(tr("Demolished %s (50%% refund)") % tr(str(StructureData.STRUCTURES[sid]["name"])))
	return true

func _kinbox_anchor_gone(cells: Array) -> void:
	# one rule for every kinbox-removal path: demolish, net teardown, raid
	# raze. The anchor ORIGIN promotes the next outpost; any other cell just
	# leaves the outpost list (audit-41 — raze_structure used to hard-reset
	# kinbox_pos and orphan a surviving outpost's promotion)
	var origin: Vector2i = cells[0]
	for cc in cells:
		if cc.x < origin.x or (cc.x == origin.x and cc.y < origin.y):
			origin = cc
	if origin == kinbox_pos:
		kinbox_pos = extra_boxes.pop_front() if not extra_boxes.is_empty() else Vector2i(-1, -1)
		if kinbox_pos.x >= 0:
			log_msg(tr("Outpost promoted to primary base"))
	else:
		extra_boxes.erase(origin)

# raiders chew on the base itself (the island): structures carry hp and drop
# their contents when razed. The kinbox is hardened — losing the anchor
# would orphan every base kin's job and the respawn point.
func tick_repairs(dt: float) -> void:
	if net != null and net.is_client():
		return # replica hp is host truth — a local patch desyncs the crew
	# the island: free hands patch the base up — idle handiwork-suitable kin
	# slowly mend damaged structures (assigned kin are busy elsewhere)
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
	if net != null and net.is_client():
		return # structure hp is host truth — replica raiders only mime the chew
	var st = structures.get(cell)
	if st == null:
		return
	var anchor: bool = StructureData.STRUCTURES.get(st["id"], {}).get("anchor", false)
	if anchor: # the kinbox holds every stored pal — losing it would orphan the box
		st["hp"] = maxf(1.0, st.get("hp", 4000) - dmg)
		floater(Vector2(cell.x + 0.5, cell.y + 0.5), tr("ANCHORED"), "#4dd0e1")
		return
	st["hp"] = st.get("hp", 200) - dmg
	floater(Vector2(cell.x + 0.5, cell.y + 0.5), tr("-%d") % dmg, "#e8963c")
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
	var xp2: Kin = st.get("exp_pal") # a razed post calls its expedition pal home early
	if is_instance_valid(xp2) and xp2.mode == "expedition":
		xp2.mode = "base"; xp2.visible = true
		xp2.job_site = null
		if not cells.is_empty():
			xp2.pos = Vector2(cells[0].x + 0.5, cells[0].y + 0.5)
	for it in st.get("store", {}).keys(): # contents spill as loot — no vanishing stock
		if not cells.is_empty():
			spawn_drop(it, st["store"][it], Vector2(cells[0].x + 0.5, cells[0].y + 0.5))
	var inc_rz: Dictionary = st.get("egg_inc", {}) # an incubating egg spills too — and its claimed bloodline rides back to the ranch ledger
	if not inc_rz.is_empty() and not cells.is_empty():
		spawn_drop("huge_kin_egg" if inc_rz.get("huge", false) else ("bred_kin_egg" if inc_rz.get("pair") != null else "kin_egg"),
			1, Vector2(cells[0].x + 0.5, cells[0].y + 0.5))
		_return_egg_parent(inc_rz.get("pair"), Vector2(cells[0].x + 0.5, cells[0].y + 0.5))
	st["store"] = {}
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	_struct_gen += 1
	if is_instance_valid(st.get("node")):
		st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null
	if sid == "kinbox" and not cells.is_empty():
		_kinbox_anchor_gone(cells) # an outpost survives → it becomes the anchor
	log_msg(tr("%s was destroyed in the raid!") % tr(str(StructureData.STRUCTURES.get(sid, {}).get("name", sid))))

func tech_node(sid: String) -> Dictionary:
	for t in StructureData.TECH:
		if t["id"] == sid:
			return t
	return {}

func unlock(sid: String) -> void:
	if client_locked():
		return
	if sid in unlocked:
		return
	var t := tech_node(sid)
	if t.is_empty():
		return
	if player.level < t.get("tier", 0):
		log_msg(tr("Reach Lv%d to unlock %s") % [t.get("tier", 0), tr(str(t.get("name", sid)))])
		return
	if tech_points < t.get("cost", 0):
		log_msg(tr("Need %d tech points") % t.get("cost", 0))
		return
	if item_count("ancient_part") < t.get("parts", 0): # ancient-tech nodes eat boss drops
		log_msg(tr("Need %d ancient parts") % t.get("parts", 0))
		return
	if int(t.get("parts", 0)) > 0:
		add_item("ancient_part", -int(t["parts"]))
	tech_points -= t.get("cost", 0)
	unlocked.append(sid)
	log_msg(tr("Unlocked %s") % tr(str(t.get("name", sid))))

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
			log_msg(tr("Need to be at a %s") % tr(str(StructureData.STRUCTURES.get(stn, {}).get("name", stn))))
			return
	var techs: Array = net_unlocked if (net != null and net.is_client()
		and not net_unlocked.is_empty()) else unlocked
	if r.get("tech", "") != "" and r["tech"] not in techs:
		var tn44: String = r["tech"]
		for t44 in StructureData.TECH:
			if t44["id"] == r["tech"]:
				tn44 = tr(str(t44["name"]))
				break
		log_msg(tr("Unlock %s in the tech tree first") % tn44)
		return
	var req: String = r.get("req", "")
	if req != "" and item_count(req) < 1:
		log_msg(tr("Need %s in the bag") % tr(str(ItemData.ITEMS.get(req, {}).get("name", req))))
		return
	for c in r.get("cost", []):
		if item_count(c[0]) < c[1]:
			log_msg(tr("Missing materials"))
			return
	if queue_crafts and stn != "hand":
		# the island bench rule: station crafts take real time; idle handy base
		# kin pitch in and hurry the queue along
		if craft_queue.size() >= MAX_CRAFT_QUEUE:
			log_msg(tr("Craft queue is full"))
			return
		for c in r.get("cost", []):
			add_item(c[0], -c[1])
		var costs := []
		for c in r.get("cost", []):
			costs.append([c[0], c[1]])
		craft_queue.append({"out": r["out"][0], "n": r["out"][1],
			"left": float(r.get("work", 20)) / 10.0, "cost": costs})
		log_msg(tr("Crafting %s… (%ds)") % [tr(str(ItemData.ITEMS[r["out"][0]]["name"])),
			int(craft_queue.back()["left"])])
		return
	for c in r.get("cost", []):
		add_item(c[0], -c[1])
	add_item(r["out"][0], r["out"][1])
	note_crafted(r["out"][0])
	log_msg(tr("Crafted %s x%d") % [tr(str(ItemData.ITEMS[r["out"][0]]["name"])), r["out"][1]])
	sfx_play("craft")

func repair_quote() -> Dictionary:
	return repair_quote_for("weapon")

func repair_quote_armor() -> Dictionary:
	return repair_quote_for("armor")

func repair_quote_for(slot: String) -> Dictionary:
	# the island repair: worn gear mends at its crafting station for half its
	# recipe (rounded up, min 1 each). {} = nothing to repair here.
	var iid: String = player.equipment[slot]
	var wear: float = player.weapon_wear if slot == "weapon" else player.armor_wear
	if iid == "" or wear < 0.0:
		return {}
	var stat_key := "weapon" if slot == "weapon" else "armor"
	var maxdur := int(ItemData.ITEMS.get(iid, {}).get(stat_key, {}).get("dur", -1))
	if maxdur <= 0 or int(wear) >= maxdur:
		return {}
	var rec := {}
	for r0 in ItemData.RECIPES:
		if r0["out"][0] == iid:
			rec = r0
			break
	# hand-recipe gear mends at any bench (its recipes show in every panel
	# anyway); station recipes only at their own station
	var stn0: String = rec.get("station", "hand")
	if rec.is_empty() or craft_station == "" or (stn0 != "hand" and stn0 != craft_station):
		return {}
	var cost := []
	for c in rec.get("cost", []):
		cost.append([c[0], maxi(1, int(ceil(float(c[1]) * 0.5)))])
	var afford := true
	for c in cost:
		if item_count(c[0]) < c[1]:
			afford = false
	return {"cost": cost, "max": maxdur, "afford": afford}

func repair_weapon() -> void:
	var rep := repair_quote()
	if rep.is_empty():
		return
	if not rep["afford"]:
		log_msg(tr("Missing materials"))
		return
	for c in rep["cost"]:
		add_item(c[0], -c[1])
	player.weapon_wear = float(rep["max"])
	log_msg(tr("Repaired %s") % tr(str(ItemData.ITEMS[player.equipment["weapon"]]["name"])))

func repair_armor() -> void:
	var rep := repair_quote_armor()
	if rep.is_empty():
		return
	if not rep["afford"]:
		log_msg(tr("Missing materials"))
		return
	for c in rep["cost"]:
		add_item(c[0], -c[1])
	player.armor_wear = float(rep["max"])
	log_msg(tr("Repaired %s") % tr(str(ItemData.ITEMS[player.equipment["armor"]]["name"])))

func tick_crafts(dt: float) -> void:
	if craft_queue.is_empty():
		return
	# idle handiwork-suitable base kin hurry the bench — 1.5x per helper
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
			log_msg(tr("Crafted %s x%d") % [tr(str(ItemData.ITEMS[cq["out"]]["name"])), cq["n"]])
			sfx_play("craft")
			craft_queue.remove_at(i)

func pal_gain_xp(q: Kin, n: int) -> void:
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
		log_msg(tr("%s grew to Lv%d!") % [tr(str(q.spec["name"])), q.level])

func gain_xp(n: int) -> void:
	n = int(n * (1.0 + perks["xp"] * 0.08))
	for q in pals:
		if q.mode == "partner":
			pal_gain_xp(q, int(n * 0.5))
	for qb in bench: # benched pals share the field lesson too (the island party xp)
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
		stat_pts += 1 # the island: every level banks a stat point for the statue
		log_msg(tr("Level up! Lv%d (+2 tech, +1 stat)") % player.level)
		sfx_play("level")

func tick_box(dt: float) -> void: # the island kinbox is a clinic — wounds mend inside
	for bp in box:
		if bp.revive_t > 0:
			if t > bp.revive_t:
				bp.revive_t = 0
				bp.hp = int(bp.max_hp * 0.3)
				bp.hunger = minf(bp.hunger, 50.0) # the box nurses it back from the
				# brink too — reviving at hunger 100 just re-KOs it ~50s later
				log_msg(tr("%s has recovered") % tr(str(bp.spec["name"])))
		elif bp.hp < bp.max_hp:
			bp.hp = minf(bp.max_hp, bp.hp + bp.max_hp * 0.03 * dt)
	for bp in bench: # orbs rest in the same clinic light
		if bp.hp < bp.max_hp:
			bp.hp = minf(bp.max_hp, bp.hp + bp.max_hp * 0.03 * dt) # ~33s to full

func cooler_active() -> bool:
	# the island cold chain: an ice box with a cooling kin on duty keeps the
	# larder from turning — same SAN/hunger/sleep gates as any work shift
	for key in structures:
		var st = structures[key]
		if key != st.get("pos") or st["id"] != "cooler":
			continue
		for w in st["workers"]:
			if is_instance_valid(w) and w.mode == "base" \
					and w.san >= 15.0 and w.hunger < 80.0 and not w.has_status("sleep"):
				return true
	return false

func tick_spoilage() -> void:
	if cooler_active():
		return
	var rot := 0
	for id in items.keys(): # snapshot: removing keys while iterating is fine on a copy
		var it: Dictionary = ItemData.ITEMS.get(id, {})
		if not it.get("perish"):
			continue
		var n: int = int(items[id])
		if n < 4:
			continue # a leftover handful keeps; real stacks turn
		var gone := mini(n, int(ceil(n * 0.15)))
		add_item(id, -gone)
		add_item("spoiled_food", gone)
		rot += gone
	if rot > 0:
		floater(player.pos, tr("%d food spoiled") % rot, "#8a7a50")
		log_msg(tr("%d perishable item(s) turned — staff an ice box") % rot)

var spoil_t := 0.0

func near_well(at: Vector2) -> bool: # a well keeps its shadow watered even in fair skies
	for k in structures:
		var st = structures[k]
		if st["id"] == "well" and Vector2(k).distance_to(at) <= 6.0:
			return true
	return false

func near_banner(at: Vector2) -> bool:
	# a war banner rallies kin working within sight of its colors
	for k in structures:
		var st = structures[k]
		if st["id"] == "war_banner" and Vector2(k).distance_to(at) <= 8.0:
			return true
	return false

func tick_production(dt: float) -> void:
	if net != null and net.is_client():
		return # the shared base's timers tick on the host — struct_sync mirrors them
	var powered := 1.5 if generator_active() else 1.0 # one check — the SAN-aware helper
	var has_stand := has_structure("monitoring_stand")
	var stand := (1.4 * float(WORK_MODES[work_mode]["prod"])) if has_stand else 1.0
	cur_san_mult = float(WORK_MODES[work_mode]["san"]) if has_stand else 1.0
	for key in structures:
		var st = structures[key]
		if key != st.get("pos"):
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
		if job.get("kind", "") == "mentor":
			tick_dojo(key, st, job, dt)
			continue
		if job.get("kind", "") == "spar":
			tick_spar(key, st, job, dt)
			continue
		if st["id"] == "incubator":
			var inc = st.get("egg_inc")
			if inc is Dictionary:
				# the island temperature rule, continuous: a campfire within 6
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
		if st["id"] == "expedition_post":
			var end: float = float(st.get("exp_end", 0.0))
			if end > 0.0 and t >= end:
				st["exp_end"] = 0.0
				st["exp_cd"] = t + 120.0 # a breather at post before the next march
				var xp: Kin = st.get("exp_pal")
				st["exp_pal"] = null
				if is_instance_valid(xp) and xp.mode == "expedition":
					return_expedition(xp, st, key)
			continue
		if st.get("spike", 0) > 0:
			st["timer"] += dt # damage hostiles standing on the spikes every half second
			if st["timer"] >= 0.5:
				st["timer"] = 0.0
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and (p.raid or p.aggro >= 0) \
							and Vector2i(int(p.pos.x), int(p.pos.y)) == key:
						p.take_dps(int(st["spike"]))
		if st.get("snare", false):
			var snared: Kin = null
			for p in pals:
				if p.mode == "wild" and p.hp > 0 and Vector2i(int(p.pos.x), int(p.pos.y)) == key:
					snared = p; break # curious feet count too — the snare doesn't check flags
			if snared != null:
				snared.stun_t = 4.0
				snared.hit(4, 1.0, false)
				floater(Vector2(key.x + 0.5, key.y + 0.5), tr("Snared!"), "#ffd76e")
				log_msg(tr("%s is caught in the snare!") % tr(str(snared.spec.get("name", snared.species_id))))
				st["snare"] = false # spent — disarm now, remove after the tick (no mid-iteration erase)
				call_deferred("net_remove_structure", st) # one bite and the trap is spent
		if st["id"] == "lightning_rod":
			if weather == "storm":
				st["timer"] += dt # the copper finger only drinks while the sky is loud
				if st["timer"] >= 45.0:
					st["timer"] = 0.0
					add_item("electric_organ", 1)
					floater(Vector2(key.x + 0.5, key.y + 0.5), tr("STRIKE!"), "#f0e060")
					log_msg(tr("Lightning bites the rod — banked an electric organ"))
			else:
				st["timer"] = 0.0
		if st["id"] == "spyglass":
			st["timer"] += dt # the brass glass sweeps a wider arc every half minute
			if st["timer"] >= 30.0:
				st["timer"] = 0.0
				st["spy_r"] = minf(float(st.get("spy_r", 6.0)) + 1.0, 18.0)
				reveal_at(Vector2(key.x + 0.5, key.y + 0.5), float(st["spy_r"]))
		if int(st.get("turret", 0)) > 0:
			st["turret_cd"] = float(st.get("turret_cd", 0.0)) - dt
			if float(st["turret_cd"]) <= 0.0:
				st["turret_cd"] = 2.5
				var tgt: Kin = null
				var tr := 12.0 # the island defense towers plink raiders on approach
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
			# the island: suitability LEVEL matters — a lv4 logger outworks a lv1
			var lv: int = int(w.spec.get("work", {}).get(wtype, 0))
			if s.get("farmField", false):
				lv = maxi(lv, int(w.spec.get("work", {}).get("watering", 0)))
			# dark kin ARE the night shift — a little faster after dusk
			var dusk := 1.15 if night and "dark" in w.spec.get("elements", []) else 1.0
			# wet skies are a water kin's home turf — a storm doubly so
			var dew := 1.0
			if "water" in w.spec.get("elements", []):
				dew = 1.15 if weather == "rain" else (1.25 if weather == "storm" else 1.0)
			elif "electric" in w.spec.get("elements", []) and weather == "storm":
				dew = 1.15 # thunder pals work harder in the storm too
			elif "fire" in w.spec.get("elements", []) and weather == "drought":
				dew = 1.15 # the dry sky is a fire pal's home turf
			# talent shows in the kinbox — make it earn its keep on the crew too
			var iv: float = 0.9 + w.talent * 0.004 # T0 → 0.9, T100 → 1.3
			var cond: float = 1.0 + w.star * 0.1 # the island: a condensed pal outworks its kin
			var rally := 1.15 if near_banner(w.pos) else 1.0 # a war banner lifts the crew's pace
			work_sum += (0.5 + 0.5 * maxi(1, lv)) * w.passive_mult("work") * w.work_mult() * dusk * dew * iv * cond * rally
		var wet := 1.25 if s.get("farmField", false) and (weather in ["rain", "storm"] or near_well(Vector2(key.x + s.get("w", 2) * 0.5, key.y + s.get("h", 2) * 0.5))) else (0.8 if s.get("farmField", false) and weather == "drought" else 1.0) # rain, storm or a well waters; a drought starves every field a well can't reach
		var fert := 1.5 if s.get("farmField", false) and float(st.get("fert", 0.0)) > t else 1.0
		st["timer"] += (dt * (1.0 + perks["work"] * 0.1)) * powered * stand * work_sum * wet * fert
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
			for w in active: # the island: base workers level from honest work
				pal_gain_xp(w, 3)
			for pr in prod: # goods pile up at the site; haulers move them
				st["store"][pr[0]] = st["store"].get(pr[0], 0) + pr[1]
			var t := ""
			for pr in prod:
				t += "+%d %s  " % [pr[1], tr(str(ItemData.ITEMS.get(pr[0], {}).get("name", pr[0])))]
			floater(Vector2(key.x + 0.5, key.y + 0.5), t.strip_edges(), "#a8e6a1")

func return_expedition(p: Kin, st: Dictionary, key: Vector2i) -> void:
	p.mode = "base"
	p.visible = true
	p.pos = Vector2(key.x + 0.5, key.y + 1.4) # lands just south of the post
	# the post holds the gatherer's berth: job survives the trip AND the save —
	# hygiene dropped it from workers[] on departure, the return relinks it
	if p.job_site == st and st["workers"].size() < 4 and p not in st["workers"]:
		st["workers"].append(p)
	elif p.job_site == st:
		p.job_site = null # berth filled while away — tick_assign finds new work
	# the island expeditions tire the crew — the haul costs SAN and a meal
	p.san = maxf(0.0, p.san - 15.0)
	p.hunger = minf(100.0, p.hunger + 25.0)
	var rolls: int = 2 + p.level / 10 + (2 if p.lucky else 0)
	var table := [["wood", 40], ["stone", 40], ["ore", 25], ["fiber", 25],
		["lumenite", 15], ["gold_coin", 8]]
	var oe: String = p.elem()[0] if not p.elem().is_empty() else "neutral"
	if oe != "neutral" and ItemData.ITEMS.has("%s_organ" % oe):
		table.append(["%s_organ" % oe, 12]) # haul matches the pal's element
	var wsum := 0
	for e2 in table:
		wsum += e2[1]
	var got := {}
	for i in rolls:
		var r: int = rng.int_range(1, wsum)
		var pick := "wood"
		for e2 in table:
			r -= e2[1]
			if r <= 0:
				pick = e2[0]
				break
		got[pick] = int(got.get(pick, 0)) + 1 + p.level / 15
	for k in got:
		st["store"][k] = int(st["store"].get(k, 0)) + int(got[k])
	var gtxt := ""
	for k2 in got:
		gtxt += "%s x%d  " % [tr(str(ItemData.ITEMS.get(k2, {}).get("name", k2))), int(got[k2])]
	log_msg(tr("%s returns from expedition: %s") % [tr(str(p.spec.get("name", p.species_id))), gtxt.strip_edges()])
	floater(Vector2(key.x + 0.5, key.y + 0.5), tr("EXPEDITION!"), "#ffe08a")

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

func nearest_free(x: float, y: float, from_pos := Vector2(-1, -1)) -> Vector2:
	# spiral out from a desired spot until a walkable cell turns up. When
	# from_pos is given the cell must also be sight-connected — a deploy
	# can't materialize inside a sealed ring one wall over (audit-43)
	var need_los := from_pos.x >= 0.0
	var c := Vector2i(int(x), int(y))
	if not world.blocked(c.x, c.y) and (not need_los \
			or world.los_clear(from_pos, Vector2(c) + Vector2(0.5, 0.5))):
		return Vector2(c.x + 0.5, c.y + 0.5)
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue # ring cells only
				var cc := Vector2i(c.x + dx, c.y + dy)
				if world.blocked(cc.x, cc.y):
					continue
				if need_los and not world.los_clear(from_pos,
						Vector2(cc) + Vector2(0.5, 0.5)):
					continue
				return Vector2(cc.x + 0.5, cc.y + 0.5)
	if need_los:
		return from_pos # give up at the deployer's feet — never inside the wall
	return Vector2(x, y) # give up: original spot

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
var _heat_at := Vector2.INF # nearest_heat memo: the query point it answers for
var _heat_d := 1e9
var _heat_t := -1.0
var _heat_n := -1 # structure generation the memo answered for — bumps on any cell write
var _struct_gen := 0 # same-size swap (raze A, build B) must still invalidate (audit-36)

func nearest_heat(at: Vector2) -> float:
	# distance to the closest warmth source — the night chill threshold.
	# the island: a fire kin at your side keeps you warm too.
	# memoized for ~0.4s within a tile: the chill check runs per physics frame
	# and the hint lambdas ask twice more — a structures-wide scan is wasted
	# on a position that barely moved
	if t - _heat_t < 0.4 and _heat_n == _struct_gen \
			and at.distance_squared_to(_heat_at) < 0.56:
		return _heat_d
	var bd := 1e9
	for k in structures:
		if structures[k]["id"] in HEAT_IDS:
			bd = minf(bd, at.distance_to(Vector2(k.x + 0.5, k.y + 0.5)))
	for q in pals:
		if q.hp > 0 and q.mode in ["partner", "base"] \
				and "fire" in q.spec.get("elements", []):
			bd = minf(bd, at.distance_to(q.pos)) # only YOUR fire pal snuggles up
	_heat_at = at; _heat_d = bd; _heat_t = t; _heat_n = _struct_gen
	return bd

func base_pals() -> Array:
	return pals.filter(func(p): return p.mode == "base")

func base_pals_of(pid: int) -> Array:
	return pals.filter(func(p): return p.mode == "base" and p.owner_id == pid)

func nearest_bed_cell(at: Vector2) -> Vector2i:
	# where a sleepy kin should pad off to — the closest kin bed or spring
	var bd := 1e9
	var best := Vector2i(-1, -1)
	for k in structures:
		var sid: String = structures[k]["id"]
		if sid != "kin_bed" and sid != "hot_spring":
			continue
		var d := at.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if d < bd:
			bd = d; best = k
	return best

func fish_bite_p() -> float:
	return 0.55 if weather in ["rain", "storm"] else 0.4 # wet skies feed the bite; dry ones don't

func cast_line() -> bool:
	if client_locked():
		return false
	# the island fishing: stand at the water's edge, wait for a bite — mostly
	# loot, sometimes a live aquatic kin surfaces to fight or catch
	var c := Vector2i(int(player.pos.x), int(player.pos.y))
	var wc := _water_cell(c)
	if wc.x < 0:
		log_msg(tr("Cast at the water's edge"))
		return false
	return _fish_roll(wc, 0)

func _water_cell(c: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k: Vector2i = c + d
		if world.in_bounds(k.x, k.y) and world.tiles[world.idx(k.x, k.y)] == World.Tile.WATER:
			return k
	return Vector2i(-1, -1)

# host-side guest cast: the ghost's shore is the honest one — you can't
# fish a coast you aren't standing on
func cast_line_remote(pid: int) -> void:
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null:
		return
	var wc := _water_cell(Vector2i(int(gp.net_pos.x), int(gp.net_pos.y)))
	if wc.x < 0:
		note_remote(pid, "Cast at the water's edge")
		return
	_fish_roll(wc, pid)

func _fish_roll(wc: Vector2i, pid: int) -> bool:
	var roll := rng.next()
	var bite := fish_bite_p() # fish feed in the rain
	if roll < bite and pals.size() < MAX_PALS:
		# a live catch: an aquatic kin from this zone's pool surfaces —
		# always host truth; pal_sync carries it to every client
		var zone := world.zone_at(wc.x, wc.y)
		var pool: Array = acq_pool(ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)).filter(
			func(s): return "water" in SpeciesData.species_of(str(s)).get("elements", []))
		if pool.is_empty():
			pool = SpeciesData.SPECIES.keys().filter(
				func(s): return "water" in SpeciesData.species_of(str(s)).get("elements", []))
		if pool.is_empty():
			return false
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var fp := preload("res://src/kin.gd").new()
		entity_layer.add_child(fp)
		fp.setup(self, sid, rng.int_range(1 + zone * 3, 4 + zone * 5), Vector2(wc.x + 0.5, wc.y + 0.5))
		fp.home = fp.pos
		pals.append(fp)
		note_remote(pid, "A wild %s took the bait!", [fp.spec["name"]])
		floater(fp.pos, tr("SPLASH!"), "#4d9de0")
	elif roll < 0.7:
		var n := rng.int_range(1, 2)
		give_remote(pid, "kin_fluid", n)
		note_remote(pid, "Caught kin fluids x%d", [n])
	elif roll < 0.9:
		var n2 := rng.int_range(4, 12)
		give_remote(pid, "gold_coin", n2)
		note_remote(pid, "A soggy coin purse!")
	elif roll < 0.95:
		give_remote(pid, "red_berries", 2)
		note_remote(pid, "Just weeds and berries.")
	else: # the sea keeps the odd corked promise
		give_remote(pid, "treasure_map", 1)
		note_remote(pid, "A corked bottle — inside, a faded treasure chart!")
	floater(Vector2(wc.x + 0.5, wc.y + 0.5), tr("~splash~"), "#9fd8ff")
	return true

func anger_nesters(at: Vector2) -> void:
	# wild kin near a looted nest turn hostile — egg theft has a price
	for q in pals:
		if q.mode == "wild" and q.hp > 0 and q.aggro < 0 \
				and q.pos.distance_to(at) < 9.0:
			q.aggro = 0
			q.aggro_pid = 0 # egg theft is a keeper verb — the thief pays
			q.statuses.erase("sleep")

func make_active(uid: int) -> void:
	# the island "send out": one ball on the field — picking a lead swaps it in
	var cur := party_pal()
	if cur != null and cur.uid == uid:
		retract_out() # tapping the field pal calls it back
		return
	send_out(uid)

const STANCES := ["auto", "aggressive", "passive"]

# the island partner passives: a fielded species quietly buffs its handler
const PARTNER_AURAS := {
	"tammane": {"speed": 0.08},   # pack-runner keeps your legs quick
	"dozantler": {"speed": 0.06},
	"sprigmelt": {"atk": 0.10},      # gun-happy spotter sharpens your aim
	"cindlump": {"atk": 0.08},
	"briargoo": {"atk": 0.06},
	"loammelt": {"def": 4.0},         # thick hide lessons rub off
	"corlmite": {"def": 3.0},
	"puffmite": {"carry": 120.0},   # iconic pack mule
	"fenjelly": {"carry": 50.0},
}

func partner_aura(stat: String) -> float:
	var p := party_pal()
	if p == null or p.hp <= 0:
		return 0.0
	return float(PARTNER_AURAS.get(p.species_id, {}).get(stat, 0.0))

# the island suit icons, text-style: top work types as two-letter codes
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
		out += "%s%d " % [tr(str(WORK_ABBR.get(k, "?"))), int(w[k])]
	return out.strip_edges()

func cycle_stance(uid: int) -> void:
	# the island kin commands: the field kin obeys a standing order
	var p: Kin = find_pal(uid)
	if p == null:
		p = bench_pal_of(uid)
	if p == null:
		return
	p.stance = STANCES[(STANCES.find(p.stance) + 1) % STANCES.size()]
	log_msg(tr("%s: %s") % [tr(str(p.spec["name"])), tr(str(p.stance))])

func bench_pal_of(uid: int) -> Kin:
	for bp in bench:
		if is_instance_valid(bp) and bp.uid == uid:
			return bp
	return null

func retract_out() -> void:
	# the island: your field kin returns to its orb — one ball out at a time
	var cur := party_pal()
	if cur == null:
		return
	player.dismount_if(cur)
	_unbind_mount(cur)
	var rc_name2: String = tr(str(cur.spec["name"]))
	if not _bench_add(cur):
		party.erase(cur.uid) # the box/freed lane already claimed it — no ghost uid on the strip
	log_msg(tr("%s recalled") % rc_name2)

func send_out(uid: int) -> void:
	# the island send-out: the chosen party member takes the field; whoever was
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
	bp.pos = nearest_free(player.pos.x + 1.2, player.pos.y, player.pos)
	unbox_pal(bp)
	cry_for(bp.species_id)
	log_msg(tr("%s sent out!") % tr(str(bp.spec["name"])))

func cycle_field_pal() -> void:
	# the pad's 1-9: rotate which party member holds the field — deployed
	# steps to the next standing kin; nothing out sends the lead. KO'd
	# members are skipped; a lone out ball comes home (audit-34)
	if net != null and net.is_client():
		return # a guest's bench/party is a wire view — cycling would orphan a replica (audit-36)
	if party.is_empty():
		return
	var cur := party_pal()
	var cur_i := party.find(cur.uid) if cur != null else -1
	for step in range(1, party.size() + 1):
		var ni := (cur_i + step) % party.size()
		var bp := bench_pal_of(party[ni])
		if bp != null and bp.hp > 0:
			send_out(party[ni])
			return
	if cur != null:
		retract_out() # nobody else can stand — the last ball comes home

func box_to_party(bp: Kin) -> void:
	if bp.hp <= 0 or bp.mode != "box": # the remote twin gates the same way — a field pal isn't box cargo
		log_msg(tr("%s is KO'd - wait for it to recover") % tr(str(bp.spec["name"])) if bp.hp <= 0 else tr("%s isn't in the box") % tr(str(bp.spec["name"])))
		return
	if party.size() >= party_cap():
		log_msg(tr("Party full (%d) - send someone to the box first") % party_cap())
		return
	box.erase(bp)
	party.erase(bp.uid) # a stale mirror or double-promote must not dup the slot
	if _bench_add(bp): # the island: new members wait in their ball until sent out
		party.append(bp.uid)
		log_msg(tr("%s joined the bench (%d/%d)") % [tr(str(bp.spec["name"])), party.size(), party_cap()])
		if party_pal() == null:
			send_out(bp.uid)
	else:
		log_msg(tr("Bench is full - %s stays in the box") % tr(str(bp.spec["name"])))

const MAX_BASE_PALS := 20 # absolute workforce cap — more mouths than this starve the loop anyway

# ---------- base level missions ----------
# the island kinbox levels: the terminal grades your base and pays slots
var base_level := 1
const BASE_LEVEL_MAX := 5
const BASE_MISSION_TEXT := {
	1: "deploy 2 kin", 2: "build 8 structures + deploy 4 kin",
	3: "catch 12 kin + build 14 structures", 4: "deploy 8 kin + reach day 5",
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
		log_msg(tr("Base level maxed"))
		return
	if not base_mission_done(base_level):
		log_msg(tr("Base mission: ") + tr(str(BASE_MISSION_TEXT[base_level])))
		return
	base_level += 1
	sfx_play("level")
	log_msg(tr("Base level %d! +2 workforce slots") % base_level)

func max_base_pals() -> int:
	# the island kinbox growth: workforce slots scale with the player's level
	# (8+lvl, hard-capped by MAX_BASE_PALS) plus base-level mission bonus
	return mini(8 + player.level + (base_level - 1) * 2, MAX_BASE_PALS)

func deploy_to_base(p: Kin) -> void:
	# the island: drop a kin at the kinbox and it joins the base workforce
	if p.hp <= 0:
		_deploy_note(p, "%s is KO'd - wait for it to recover", [p.spec["name"]])
		return
	if kinbox_pos.x < 0:
		_deploy_note(p, "Need a kinbox to deploy kin")
		return
	if base_pals_of(p.owner_id).size() >= max_base_pals() and p.mode != "base":
		_deploy_note(p, "Base is full (%d kin — level up for more slots)", [max_base_pals()])
		return
	player.dismount_if(p)
	_unbind_mount(p) # a mount taking a base post leaves the saddle for good
	party.erase(p.uid)
	if p.owner_id > 0:
		rparty_for(p.owner_id).erase(p.uid) # a guest's slot frees when their pal takes a post
	box.erase(p)
	bench.erase(p)
	if p.mode in ["box", "bench"]:
		unbox_pal(p) # back into the live tree before it starts working
	if p not in pals:
		pals.append(p)
	p.mode = "base"
	p.job_site = null
	var db := nearest_kinbox(p.pos)
	p.pos = nearest_free(db.x + 2.0, db.y + 2.5)
	_deploy_note(p, "%s deployed at base", [p.spec["name"]])

# a remote caller's kin owns pid > 0 — its owner gets the notice, not the host
func _deploy_note(p: Kin, msg: String, args: Array = []) -> void:
	if p.owner_id > 0:
		note_remote(p.owner_id, msg, args)
	else:
		log_msg(tr(msg) % tr_args(args) if args.size() else tr(msg))

func base_to_box(p: Kin) -> void:
	# recall a worker into cold storage — job and cargo are dropped first
	if box.size() >= MAX_BOX:
		log_msg(tr("Kinbox is full"))
		return
	_unbind_mount(p)
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
	log_msg(tr("%s -> box") % tr(str(p.spec["name"])))

func party_to_box(uid: int) -> void:
	var p := find_pal(uid)
	if p == null:
		p = bench_pal_of(uid) # benched orbs drop straight into cold storage
	if p == null:
		return
	if box.size() >= MAX_BOX: # refusal precedes the unbind/job drop — a full box keeps the kin put
		log_msg(tr("Kinbox is full"))
		return
	player.dismount_if(p)
	_unbind_mount(p)
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
		log_msg(tr("%s dropped off %d %s") % [tr(str(p.spec["name"])), p.carry["n"],
			tr(str(ItemData.ITEMS.get(p.carry["id"], {}).get("name", p.carry["id"])))])
		p.carry = null
	box.append(p)
	box_pal(p)
	log_msg(tr("%s -> box") % tr(str(p.spec["name"])))

func assign_worker() -> void:
	# toggle nearest base kin between wander and assigned to nearest workplace
	var best: Kin = null
	var bd := 3.0
	for p in base_pals():
		var d := player.pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	if not best:
		log_msg(tr("No base kin nearby"))
		return
	if best.job_site != null:
		best.job_site["workers"].erase(best)
		best.job_site = null
		log_msg(tr("%s unassigned") % tr(str(best.spec["name"])))
		return
	if best.owner_id != 0:
		log_msg(tr("%s answers to its keeper") % tr(str(best.spec["name"])))
		return # the host's yard, the host's call: evict is allowed, posting is not
	var site: Variant = find_work_site(best, 6.0)
	if site:
		if best.carry != null: # a hauler pinned to a job must not strand the goods
			add_item(best.carry["id"], best.carry["n"]) # the keeper's bag takes it
			best.carry = null
			best.carry_hold_t = 0.0
		if best not in site["workers"]:
			site["workers"].append(best) # idempotent — a stale entry must not duplicate
		best.job_site = site
		log_msg(tr("%s -> %s") % [tr(str(best.spec["name"])), StructureData.STRUCTURES[site["id"]]["name"]])
	else:
		log_msg(tr("No workplace nearby"))

var skill_target: Kin = null # kinbox move-loadout panel's subject
func toggle_skill(p: Kin, sid: String) -> void:
	# move loadout: slot up to 3 of the kin's learned moves
	if p == null or sid not in p.learned_skills():
		return
	if sid in p.equipped:
		p.equipped.erase(sid)
	elif p.equipped.size() >= 3:
		log_msg(tr("%s's loadout is full — unslot a move first") % tr(str(p.spec["name"])))
		return
	else:
		p.equipped.append(sid)
	var eqt := []
	for esid in p.equipped:
		eqt.append(tr(str(SkillData.SKILLS.get(esid, {}).get("name", esid))))
	log_msg(tr("%s moves: %s") % [tr(str(p.spec["name"])), ", ".join(eqt)])

func tick_death_marks() -> void:
	# reaching a tombstone retires it — the pack itself is handled by the drops
	for i in range(death_marks.size() - 1, -1, -1):
		if player.pos.distance_to(death_marks[i]) < 2.0:
			death_marks.remove_at(i)

func pet_pal(p: Kin) -> bool:
	# pet: a little affection tops up SAN on a per-kin cooldown
	if p == null or p.hp <= 0 or p.mode not in ["partner", "base"]:
		return false
	if p.petted_t > t:
		return false
	p.petted_t = t + 60.0
	p.san = minf(100.0, p.san + 8.0)
	floater(p.pos, tr("♥"), "#ff8ab0")
	log_msg(tr("You pet %s") % tr(str(p.spec["name"])))
	return true

func find_work_site(p: Kin, reach: float) -> Variant:
	# nearest suitable post within reach — shared suitability rules for the
	# manual assign tap and the idle auto-assign sweep (farm fields take
	# waterers too, the island-style)
	var site = null
	var sd := reach
	for k in structures:
		var s: Dictionary = StructureData.STRUCTURES.get(structures[k]["id"], {})
		var jb: Dictionary = s.get("job", {})
		if jb.get("produces", []).is_empty() and structures[k]["id"] != "ranch" and jb.get("kind") != "power" and jb.get("kind") != "expedition" and jb.get("kind") != "guard" and jb.get("kind") != "mentor" and jb.get("kind") != "spar":
			continue # sites with no output aren't assignable (except generator/ranch) — campfire's [] sneaks past a null check
		var need: String = jb.get("workType", "")
		if need != "" and p.spec.get("work", {}).get(need, 0) == 0 \
				and not (s.get("farmField", false) and p.spec.get("work", {}).get("watering", 0) > 0):
			continue  # can't work this site — farm fields also take waterers (the island)
		if structures[k]["workers"].size() >= 4:
			continue # site is fully crewed — piling more pals on one site scales unbounded
		var d := p.pos.distance_to(Vector2(k.x, k.y))
		if d < sd:
			sd = d
			site = structures[k]
	return site

var assign_t := 0.0
func tick_assign(dt: float) -> void:
	if net != null and net.is_client():
		return # writes job_site/workers on replica structures — host truth
	# the island: idle base kin drift into open posts on their own — the kinbox
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

func cast_skill(caster: Kin, target_ent, sk: Dictionary) -> void:
	var kind: String = sk.get("kind", "projectile")
	var tpos: Vector2 = target_ent if target_ent is Vector2 else target_ent.pos
	match kind:
		"self":
			var heal := caster.max_hp * absf(sk.get("power", 20)) / 100.0
			caster.hp = minf(caster.max_hp, caster.hp + heal)
			floater(caster.pos, tr("+%d %s") % [int(heal), tr(str(sk["name"]))], "#a8e6a1")
		"lunge":
			var land: Vector2 = tpos + (caster.pos - tpos).normalized() * 0.9
			# pass caster pos so elevation is actually checked — 2-arg blocked skips it
			if not world.blocked(int(land.x), int(land.y), caster.pos.x, caster.pos.y):
				caster.pos = land
			if world.los_clear(caster.pos, tpos): # a refused dash can't land the
				skill_hit(caster, target_ent, sk) # hit through the wall (audit-43)
		"burst":
			var radius: float = sk.get("range", 4)
			if caster.mode == "wild":
				if caster.pos.distance_to(player.pos) <= radius \
						and world.los_clear(caster.pos, player.pos): # the ring
					skill_hit(caster, player, sk) # walls the nova (audit-43)
				for p in pals.duplicate():
					if p.mode in ["partner", "base"] and p.hp > 0 \
							and caster.pos.distance_to(p.pos) <= radius \
							and world.los_clear(caster.pos, p.pos):
						skill_hit(caster, p, sk)
			else:
				for p in pals.duplicate():
					if p.mode == "wild" and p.hp > 0 and caster.pos.distance_to(p.pos) <= radius \
							and world.los_clear(caster.pos, p.pos):
						skill_hit(caster, p, sk)
			floater(caster.pos, tr(str(sk["name"])) + tr("!"), "#ffd76e")
		"multi": # a fan of shots — pack-clearing signature
			var n2: int = maxi(2, int(sk.get("shots", 3)))
			var spread := deg_to_rad(float(sk.get("spread_deg", 14.0)))
			var aim := (tpos - caster.pos).normalized()
			for i in n2:
				spawn_shot(caster, aim.rotated(spread * (i - (n2 - 1) / 2.0)), sk)
			floater(caster.pos, tr(str(sk["name"])) + tr("!"), "#ffd76e")
		_: # projectile
			spawn_shot(caster, (tpos - caster.pos).normalized(), sk)

var _orb_atlases := {} # elem -> AtlasTexture — one per element, shared by
# every bolt of that element (create-once, bounded by the element enum)
func _elem_orb(elem: String) -> AtlasTexture:
	var at: AtlasTexture = _orb_atlases.get(elem)
	if at == null:
		at = AtlasTexture.new()
		at.atlas = orb_tex
		at.region = Rect2(ELEM_ORB_IDX.get(elem, 0) * 16, 0, 16, 16)
		at.filter_clip = true
		_orb_atlases[elem] = at
	return at

func spawn_shot(caster: Kin, dir: Vector2, sk: Dictionary) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		var old = projectiles.pop_front()
		if is_instance_valid(old.get("node")):
			old["node"].queue_free() # volley backstop: oldest shot fizzles
	var spr := Sprite2D.new()
	spr.texture = _elem_orb(sk.get("element", "neutral"))
	spr.scale = Vector2(1.5, 1.5)
	entity_layer.add_child(spr)
	projectiles.append({
		"elev": world.elev_at(int(caster.pos.x), int(caster.pos.y)),
		"pos": caster.pos, "dir": dir,
		"speed": sk.get("projectileSpeed", 12), "ttl": sk.get("range", 8) / maxf(1.0, sk.get("projectileSpeed", 12)),
		"skill": sk, "from": caster, "node": spr,
		"pierce": sk.get("pierce", false), "hitset": {}, # pierce: one wound per body
	})

func skill_hit(caster: Kin, target_ent, sk: Dictionary) -> void:
	if not (target_ent is Kin or target_ent is Player):
		return # a bare Vector2 has no body — callers whitelist lunge away from
		# ghosts, but a slip fails closed here rather than typing Kin <- Vector2
	var elem: String = sk.get("element", "neutral")
	if target_ent is Player:
		if (state != "play" and not net_live()) or player.dodge_t > 0:
			return
		var final := apply_player_damage(maxi(1, int(sk.get("power", 10) * 0.6)))
		if final <= 0:
			return
		var dr0 := float(sk.get("drain", 0.0))
		if dr0 > 0.0 and caster.hp > 0:
			var back0 := minf(caster.max_hp - caster.hp, final * dr0) # the bite
			if back0 > 0.0: # feeds its biter — same +N the kin path shows
				caster.hp += back0
				floater(caster.pos, tr("+%d") % int(back0), "#a8e6a1")
		var st = sk.get("status")
		if st and rng.chance(st.get("chance", 1.0)):
			player_status(st["kind"], st.get("dur", 3))
		if player.hp <= 0:
			respawn_player()
	else:
		var tp: Kin = target_ent
		var mult := Combat.effectiveness(elem, tp.elem())
		# STAB (the island): a kin fighting in its own element hits harder
		if elem in caster.spec.get("elements", []):
			mult *= 1.2
		if weather == "rain" or weather == "storm": # wet skies favor water, dampen fire
			if elem == "fire":
				mult *= 0.85
			elif elem == "water":
				mult *= 1.15
			elif elem == "electric" and weather == "storm": # thunderstorm supercharges electric
				mult *= 1.15
		elif weather == "drought" and elem == "fire": # the parch is a flame's weather
			mult *= 1.15
		if tp.has_status("freeze"):
			# a solid-frozen target shatters — the hit lands heavy and thaws it
			# out. Checked before soak so the ice that freezes it this same hit
			# doesn't shatter in the same instant
			mult *= 1.5
			tp.statuses.erase("freeze")
			floater(tp.pos, tr("SHATTERED"), "#7fc8f8")
		if tp.has_status("soak"):
			# the island element combos: a wet target takes the hit differently —
			# electricity arcs through, ice locks solid, fire just boils off
			if elem == "electric":
				mult *= 1.5
			elif elem == "ice":
				tp.statuses.erase("soak")
				tp.add_status("freeze", 2.5)
				floater(tp.pos, tr("FROZEN SOLID"), "#7fc8f8")
			elif elem == "fire":
				tp.statuses.erase("soak")
		var d := Combat.damage(Combat.stat_at(caster.spec["atk"], caster.level, caster.talent) * caster.atk_bonus * caster.atk_mult(),
			sk.get("power", 10), Combat.stat_at(tp.spec["def"], tp.level, tp.talent) * tp.def_bonus * tp.def_mult(), mult, rng)
		tp.hit(d, mult, caster.mode != "wild", caster.owner_id) # a guest's pal provokes the guest
		if tp.hp > 0: # statuses on a corpse die in the box — gate the corpse case
			tp.apply_skill_status(sk)
		var dr := float(sk.get("drain", 0.0))
		if dr > 0.0 and caster.hp > 0:
			var back := minf(caster.max_hp - caster.hp, maxf(1.0, d * dr))
			if back > 0.0:
				caster.hp += back
				floater(caster.pos, tr("+%d") % int(back), "#a8e6a1")
		if caster.mode == "partner":
			gain_xp(maxi(1, d / 4))

func update_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	var pal_snap := pals.duplicate() # one snapshot per tick — raid volleys were allocating per projectile per frame
	for pr in projectiles.duplicate():
		pr["ttl"] -= dt
		var old_pp: Vector2 = pr["pos"]
		pr["pos"] += pr["dir"] * pr["speed"] * dt
		var pp: Vector2 = pr["pos"]
		var n: Sprite2D = pr["node"]
		n.position = Iso.to_screen(pp.x, pp.y, world.elev_at(int(pp.x), int(pp.y))) - Vector2(0, 20)
		var dead: bool = pr["ttl"] <= 0
		# terrain hit: cliff faces above launch height, trees/rocks/buildings.
		# March the travelled segment — a fast bolt on a slow frame used to hop
		# a 1-cell wall between ticks (audit-43), and walkable structures
		# (spike floors) must not eat shots the way a rock does
		if not dead:
			var march := int(ceil(pr["speed"] * dt * 4.0)) + 1
			var pc43 := Vector2i(-9999, -9999)
			for mi in range(march + 1):
				var mp: Vector2 = old_pp.lerp(pp, float(mi) / float(march))
				var c43 := Vector2i(int(mp.x), int(mp.y))
				if c43 == pc43:
					continue
				pc43 = c43
				if not world.in_bounds(c43.x, c43.y):
					dead = true; break
				var ci: int = world.idx(c43.x, c43.y)
				if world.elev_at(c43.x, c43.y) > pr.get("elev", 0) \
						or world.decor[ci] != World.Decor.NONE \
						or world.solid_structure(ci):
					dead = true; break
		if pr["from"] is String and pr["from"] == "player":
			if not dead:
				for p in pal_snap:
					if p.mode == "wild" and p.hp > 0 and pp.distance_to(p.pos) < 0.6:
						var mult := Combat.effectiveness("neutral", p.elem())
						var d := Combat.damage(pr["dmg"] * 2.0 * (1.0 + partner_aura("atk") + player.meal_bonus("atk")), 20, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus * p.def_mult(), mult, rng)
						if net != null and net.is_client() and p.net_id > 0:
							# replicas bleed only on the host's say-so — a local
							# hit() on a replica early-returns, which made guest
							# bows and tranq guns cosmetic
							net.rpc("pal_hit", p.net_id, player.mercy_dmg(d, p), float(pr.get("sleep", 0.0)))
						else:
							p.hit(player.mercy_dmg(d, p), mult, true)
							if float(pr.get("sleep", 0.0)) > 0.0 and p.hp > 0: # a tranq dart lands AFTER the sting — the hit would wake it otherwise
								apply_sleep_claim(p, float(pr["sleep"])) # same anti-chain gate the wire claims use
						dead = true
						break
			if dead:
				n.queue_free()
				projectiles.erase(pr)
			continue
		var caster: Kin = pr["from"] if is_instance_valid(pr["from"]) else null
		if caster == null: # caster died while the shot was in flight
			dead = true
		if not dead:
			if caster.mode == "wild":
				if pp.distance_to(player.pos) < 0.55 and not pr["hitset"].has("@pl"):
					skill_hit(caster, player, pr["skill"])
					pr["hitset"]["@pl"] = true
					dead = not pr["pierce"]
				if not dead and net != null: # a guest standing in the line of fire eats it —
					for pid in net.ghosts: # host computes, the wire delivers
						var g = net.ghosts[pid]
						# "g%d" namespaces the key — a peer id can collide with a kin uid
						if g != null and g.net_pos.x >= 0 and not pr["hitset"].has("g%d" % pid) \
								and pp.distance_to(Vector2(g.net_pos.x, g.net_pos.y)) < 0.55:
							var gk_st: Dictionary = pr["skill"].get("status", {})
							var gk_apply: bool = not gk_st.is_empty() \
								and rng.chance(gk_st.get("chance", 1.0))
							net.rpc_id(pid, "guest_skill_hit",
								float(pr["skill"].get("power", 10)),
								str(gk_st.get("kind", "")) if gk_apply else "",
								float(gk_st.get("dur", 0.0)) if gk_apply else 0.0)
							pr["hitset"]["g%d" % pid] = true
							var gdr := float(pr["skill"].get("drain", 0.0)) # drain
							if gdr > 0.0 and caster.hp > 0: # pays regardless of
								caster.hp = minf(caster.max_hp, caster.hp + # whose armor took
									maxf(1.0, float(pr["skill"].get("power", 10)) * 0.6 * gdr))
							dead = not pr["pierce"]
							break
				if not dead:
					for p in pal_snap:
						if p.mode in ["partner", "base"] and p.hp > 0 and not pr["hitset"].has(p.uid) \
								and pp.distance_to(p.pos) < 0.6:
							skill_hit(caster, p, pr["skill"]) # wild shots hit partners AND base workers
							pr["hitset"][p.uid] = true
							if not pr["pierce"]:
								dead = true
								break
			else:
				for p in pal_snap:
					if p.mode == "wild" and p.hp > 0 and not pr["hitset"].has(p.uid) \
							and pp.distance_to(p.pos) < 0.6:
						skill_hit(caster, p, pr["skill"])
						pr["hitset"][p.uid] = true
						if not pr["pierce"]:
							dead = true
							break
		if dead:
			n.queue_free()
			projectiles.erase(pr)

func player_status(kind: String, dur: float) -> void:
	player.statuses[kind] = t + dur
	floater(player.pos, tr(kind).to_upper(), "#e8963c")

# ---------- save / load ----------
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		for k in settings:
			var v = cf.get_value("main", k, settings[k])
			# settings.cfg is untrusted like any save file — coerce per key
			if k == "lang":
				settings[k] = str(v) if str(v) in ["en", "zh"] else "en"
			elif k == "touch":
				settings[k] = str(v) if str(v) in ["auto", "on", "off"] else "auto"
			elif settings[k] is bool:
				settings[k] = v if v is bool else settings[k]
			elif settings[k] is float or settings[k] is int:
				settings[k] = clampf(float(v) if _fin(v) else settings[k], 0.0, 1.0) # NaN is not a volume
	load_csv_translations()
	apply_settings()

func load_csv_translations() -> void:
	# the csv is the source of truth — the editor's csv_translation importer is
	# flaky headless, so we build the Translation resource at runtime instead
	var f := FileAccess.open("res://locale/zh.csv", FileAccess.READ)
	if f == null:
		return
	var t := Translation.new()
	t.locale = "zh"
	var first := true
	while not f.eof_reached():
		var row := f.get_csv_line()
		if first:
			first = false
			continue
		if row.size() >= 3 and row[0] != "":
			t.add_message(row[0], row[2])
	TranslationServer.add_translation(t)

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("main", k, settings[k])
	cf.save("user://settings.cfg")

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings["master"], 0.001)))
	for b in ["Music", "SFX"]:
		var bi := AudioServer.get_bus_index(b)
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(settings[b.to_lower()], 0.001)))
	TranslationServer.set_locale("zh" if settings.get("lang", "en") == "zh" else "en")
	var tmode := str(settings.get("touch", "auto"))
	touch_ui = tmode == "on" or (tmode == "auto" and DisplayServer.is_touchscreen_available())
	var w := get_window()
	if w != null and DisplayServer.get_name() != "headless" \
			and (w.mode == Window.MODE_FULLSCREEN) != settings["fullscreen"]:
		w.mode = Window.MODE_FULLSCREEN if settings["fullscreen"] else Window.MODE_WINDOWED

func quit_game() -> void:
	save_game()
	get_tree().quit()

func to_title() -> void:
	save_game()
	# reload_current_scene is not teardown: the MultiplayerAPI peer, buses and
	# InputMap all survive it. A live peer would leak the whole session into
	# the fresh scene — close it first.
	if net != null:
		net.is_host = false
		net._close_peer() # graceful drop — the remote end sees a disconnect, not a timeout
	get_tree().reload_current_scene() # fresh boot lands back on the title screen

func save_game() -> void:
	if net != null and net.is_client():
		log_msg(tr("The world lives on the host — nothing to save locally"))
		return # a client's replica snapshot must never clobber the solo save
	if net_residue:
		log_msg(tr("A dropped session's world can't be saved"))
		return # host gone ≠ yours — the Frankenstein snapshot would eat the real save
	var pals_data := []
	for p in pals:
		var jc = null
		if p.mode == "base" or p.mode == "expedition": # only base pals hold jobs; anything else in workers is stale
			for kj in structures:
				if p in structures[kj]["workers"] or structures[kj].get("exp_pal") == p:
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
			"bnt": p.bounty, "eq": p.equipped, "own": p.owner_tag,
			"stag": p.spire_tag, "ph": p.phase, # spire guardians keep their campaign tag; a phase-2 boss must not re-summon on reload
			"rt0": t - p.get_meta("raid_t0", t) if p.raid else 0.0})
	for bp in box:
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "box", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"fav": bp.fav,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "carry": bp.carry, "sb": bp.soul_boost,
			"ail": bp.ailment, "lucky": bp.lucky, "extra": bp.extra_skills, "eq": bp.equipped,
			"own": bp.owner_tag,
			"revive": maxf(0.0, bp.revive_t - t)})
	for bp in bench: # orbs ride in the save too — party state survives a reload
		pals_data.append({"sp": bp.species_id, "lv": bp.level, "pos": [0, 0],
			"mode": "bench", "hp": bp.hp, "talent": bp.talent, "sex": bp.sex,
			"fav": bp.fav,
			"passives": bp.passives, "alpha": bp.alpha, "star": bp.star,
			"xp": bp.xp, "san": bp.san, "hunger": bp.hunger, "sb": bp.soul_boost,
			"ail": bp.ailment, "lucky": bp.lucky, "extra": bp.extra_skills,
			"stance": bp.stance, "eq": bp.equipped, "own": bp.owner_tag})
	var rparties_sv := {} # guests' party strips — indexed like party_idx, keyed by install tag
	for tag in remote_parties:
		var idxs := []
		for u in remote_parties[tag]:
			var pp2: Kin = find_pal(int(u))
			if pp2 == null:
				pp2 = bench_pal_of(int(u))
			if pp2 == null:
				continue
			var i2: int = pals.find(pp2)
			if i2 < 0:
				i2 = box.find(pp2)
				i2 = pals.size() + i2 if i2 >= 0 else -1
			if i2 < 0:
				i2 = bench.find(pp2)
				i2 = pals.size() + box.size() + i2 if i2 >= 0 else -1
			if i2 >= 0:
				idxs.append(i2)
		if not idxs.is_empty():
			rparties_sv[str(tag).substr(0, 24)] = idxs
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
			"exp": ({"left": maxf(0.0, float(st.get("exp_end", 0.0)) - t), "cd": maxf(0.0, float(st.get("exp_cd", 0.0)) - t)} if st["id"] == "expedition_post" else null),
			"inc": ({"pair": inc.get("pair"), "huge": inc.get("huge", false), "left": maxf(0.0, float(inc.get("ready_t", 0.0)) - t), "own": str(inc.get("own_tag", ""))} if inc is Dictionary else null),
			"fert": maxf(0.0, float(st.get("fert", 0.0)) - t) if float(st.get("fert", 0.0)) > t else null,
			"cap": st.get("captive") if st["id"] == "kin_cage" else null,
			"by": str(st.get("placed_tag", "")) if str(st.get("placed_tag", "")) != "" else null,
			"mimic": st.get("mimic") if st["id"] == "chest" else null}
	var spos_sv := {}
	for tk3 in spire_pos:
		var vp3: Vector2i = spire_pos[tk3]
		spos_sv[tk3] = [vp3.x, vp3.y] # arrays are the position schema — a raw Vector2i would fail the loader's `is Array` coercion
	var d := {
		"seed": world.seed, "day": day, "tod": tod, "tech_points": tech_points,
		"raid_t": raid_t, "mdeaths": merchant_deaths,
		"unlocked": unlocked, "items": items, "party": party, "rparties": rparties_sv,
		"party_idx": party.map(func(u):
			var pp: Kin = find_pal(u)
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
		"wearmap": wear_by_id, # durability follows the item id across unequips
		"wear": player.weapon_wear, "awear": player.armor_wear,
		"v": SAVE_VER, "kin": pals_data, "structures": structs, "catches": catch_counts,
		"drops": drops.map(func(dd): return {"id": dd["id"], "n": dd["n"], "x": dd["pos"].x, "y": dd["pos"].y,
			"m": dd.get("mine", false) if dd.get("mine", false) else null}), # corpse bags keep their mercy flag across a reload
		"crafts": craft_queue.slice(0, MAX_CRAFT_QUEUE).map(
			func(cq): return {"out": cq["out"], "n": cq["n"], "left": cq["left"]}),
		"respawns": boss_respawns.slice(0, MAX_RESPAWNS).map(
			func(br):
				var r: Dictionary = br.duplicate()
				r["at"] = maxf(0.0, br["at"] - t) # store remaining time — t restarts on load
				return r),
		"pbx": [kinbox_pos.x, kinbox_pos.y], # which kinbox is primary
		"missions": mission_idx, "mflags": mission_flags,
		"dex_seen": dex_seen.keys(), "dex_claimed": dex_claimed, "dex_full": dex_full,
		"spires": spires_done.keys(), "crowned": crowned, "accord": accord,
		"spos": spos_sv,
		"weather": weather, "wthr_t": weather_t, "wmode": work_mode, "blev": base_level,
		"pray_left": maxf(0.0, pray_cd - t),
		"board_quest": board_quest,
		"explored": explored,
		"treasure": ([treasure["pos"].x, treasure["pos"].y] if treasure else null),
		"grotto": [grotto_pos.x, grotto_pos.y], "grotto2": [grotto_room2.x, grotto_room2.y],
		"player": {"pos": [player.pos.x, player.pos.y], "hp": player.hp,
			"hunger": player.hunger, "stamina": player.stamina,
			"level": player.level, "xp": player.xp, "cap_lv": player.capture_level,
			"meal": player.meal_buff, "meal_t": player.meal_t},
		"decor": world.decor.duplicate(), "hp_map": world.hp.duplicate(),
	}
	var f := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	if f == null:
		log_msg(tr("SAVE FAILED") + tr(" — %s") % error_string(FileAccess.get_open_error()))
		return
	f.store_var(d)
	f.close()
	has_save = true
	log_msg(tr("Saved."))

func load_game() -> bool:
	if net != null and net.is_client():
		log_msg(tr("The world lives on the host — nothing to load locally"))
		return false # a solo save must never rebuild a replica world
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		log_msg(tr("Guests connected — end the session before loading"))
		return false # reloading under guests desyncs their world for good
	if not FileAccess.file_exists("user://savegame.plg"):
		return false
	var f := FileAccess.open("user://savegame.plg", FileAccess.READ)
	if f == null:
		return false
	var dv = f.get_var()
	f.close()
	if dv is not Dictionary or not dv.has("seed"):
		log_msg(tr("Save file corrupt - starting fresh"))
		return false
	var d: Dictionary = Migrate.save_dict(dv) # pre-rename saves keep working under new ids
	if _i(d.get("v", 0)) > SAVE_VER:
		log_msg(tr("Save is from a newer build - not loading"))
		return false # a future schema misreads silently as v2 — refuse it
	for req in ["day", "tod", "tech_points", "unlocked", "items", "party", "player", "kin", "structures"]:
		if not d.has(req):
			log_msg(tr("Save missing field '%s' - starting fresh") % req)
			return false # below this point every field is assumed present
	if d["player"] is not Dictionary or d["kin"] is not Array or d["structures"] is not Dictionary \
			or d["items"] is not Dictionary or d["party"] is not Array or d["unlocked"] is not Array \
			or not _fin(d["seed"]):
		log_msg(tr("Save has wrong field types - starting fresh"))
		return false # seed reaches a typed int parameter — refusing here beats a mid-load abort
	player.mount = null # pals are about to be freed and rebuilt — mount ref would dangle
	despawn_merchant() # the trader's stock and node don't cross a load
	for p in pals:
		p.queue_free()
	pals.clear()
	for bp1 in box: # box pals live under box_holder — still in the tree, so
		bp1.queue_free()  # queue_free is the only legal free for a parented node
	box.clear()
	for bp2 in bench: # bench kin live under box_holder too — a quickload that
		bp2.queue_free()  # forgets them grows a phantom stable every save/load
	bench.clear()
	lure = {} # a live trap must not resurrect across a load
	focus_target = null
	focus_t = 0.0
	raid_warned = false # a 30s horn doesn't survive the reload
	raid_theme = ""
	hint_seen.clear() # onboarding memory belongs to the run, not the file
	death_marks.clear() # tombstones are session-only — a load starts clean
	mission_t = 0.0
	catch_streak = 0 # streak math belongs to the session that earned it
	player.statuses.clear() # the old session's burns don't ride the reload
	last_merchant_day = -1 # the trader's daily visit re-arms on the loaded day
	dirty_decor.clear() # stale deltas must not broadcast a prior world's cells
	for pr in projectiles:
		if is_instance_valid(pr["node"]):
			pr["node"].queue_free() # same guard every sibling sweep carries
	projectiles.clear()
	for sp0 in spheres_flying: # orb sprites + stale targets must not cross a load
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
	_struct_gen += 1
	world.structures.clear()
	world.generate(int(d["seed"])) # numeric-verified above — the typed parameter would abort on anything else
	if d.get("decor") is PackedByteArray and d["decor"].size() == world.decor.size() \
			and d.get("hp_map") is PackedByteArray and d["hp_map"].size() == world.hp.size():
		var ddec: PackedByteArray = d["decor"].duplicate() # clamp a copy — an
		for i2 in ddec.size(): # off-enum byte reaches harvest_cell's literal
			if ddec[i2] > int(World.Decor.STUMP): # lookup; the net path does
				ddec[i2] = World.Decor.NONE    # this, the save path didn't
		world.decor = ddec                     # (audit-42)
		world.hp = d["hp_map"]
	else: # world size/type changed since this save — keep fresh terrain, skip stale layout
		log_msg(tr("Save layout predates the current world format - fresh terrain"))
	queue_redraw_decor() # decor pool still holds the pre-load world's sprites
	day = maxi(_i(d["day"]), 1); tod = clampf(_f(d["tod"]), 0.0, 24.0) # typed vars — a foreign string would throw on assignment; tod>24 would fast-forward a day per frame until under 24
	raid_t = clampf(_f(d.get("raid_t", raid_t)), 0.0, 600.0) # a hostile timer can't pin raids forever or fire one mid-load
	for dd0 in (d["drops"] if d.get("drops") is Array else []): # a scalar/null drops field aborts the loop itself — guard at the door
		if dd0 is Dictionary and dd0.has("id") and dd0.has("x") and dd0.has("y") \
				and ItemData.ITEMS.has(str(dd0["id"])) \
				and _fin(dd0["x"]) and _fin(dd0["y"]):
			spawn_drop(str(dd0["id"]), maxi(_i(dd0.get("n", 1)), 0), Vector2(float(dd0["x"]), float(dd0["y"])),
				dd0.get("m") is bool and dd0["m"]) # negative n would corrupt the item ledger; the corpse flag rides too
	boss_respawns.clear()
	for rb in (d["respawns"] if d.get("respawns") is Array else []):
		var rp = rb.get("pos") if rb is Dictionary else null
		if rp is Array and rp.size() >= 2 and _fin(rp[0]) and _fin(rp[1]) \
				and boss_respawns.size() < MAX_RESPAWNS:
			var rrsid := str(rb.get("sid", ""))
			if SpeciesData.species_of(rrsid).is_empty():
				continue # a removed species' den stays dead — no phantom timer
			var rr: Dictionary = {"sid": rrsid, "pos": [float(rp[0]), float(rp[1])],
				"lv": clampi(_i(rb.get("lv", 30)), 1, 60), # hostile tails never reach gen_pal or a typed read at tick time
				"alpha": rb.get("alpha") is bool and rb["alpha"],
				"boss": rb.get("boss") is bool and rb["boss"],
				"at": t + maxf(0.0, _f(rb.get("at", DAY_LEN), DAY_LEN))} # NaN falls back to a fresh day, not "fire now"
			boss_respawns.append(rr)
	craft_queue.clear()
	for rc in (d["crafts"] if d.get("crafts") is Array else []):
		if rc is Dictionary and ItemData.ITEMS.has(str(rc.get("out", ""))) \
				and craft_queue.size() < MAX_CRAFT_QUEUE:
			craft_queue.append({"out": str(rc["out"]), "n": maxi(_i(rc.get("n", 1)), 0),
				"left": maxf(_f(rc.get("left", 1.0)), 0.1), "cost": []})
	tech_points = maxi(_i(d["tech_points"]), 0)
	var tech_ids := {}
	for t2 in StructureData.TECH:
		tech_ids[str(t2.get("id", ""))] = true # TECH rows are dicts — has() on a dict array never matches an id
	var unlock_ok := func(u): return u is String and (tech_ids.has(u) or StructureData.STRUCTURES.has(u))
	unlocked = d["unlocked"].filter(unlock_ok) # a foreign save can't mint tech, but starter rows aren't all in TECH
	stat_pts = maxi(_i(d.get("stat_pts", 0)), 0)
	var saved_perks: Dictionary = d["perks"] if d.get("perks") is Dictionary else {}
	for pk in perks: # merge over defaults — a save missing a newer perk would poison every perks[k] read
		perks[pk] = clampi(_i(saved_perks.get(pk, perks[pk])), 0, 5) # the grant
		# site caps at 5 — the load path was a second, cap-free consumer
		# (audit-41): forged "hp":9999 meant 120k max_hp, 800x melee
	wear_by_id.clear()
	if d.get("wearmap") is Dictionary:
		for wk in d["wearmap"]: # durability rows: real item ids, finite non-negative wear
			if ItemData.ITEMS.has(str(wk)) and _fin(d["wearmap"][wk]):
				wear_by_id[str(wk)] = maxf(float(d["wearmap"][wk]), 0.0)
	catch_counts.clear()
	if d.get("catches") is Dictionary:
		for ck in d["catches"]:
			if not SpeciesData.species_of(str(ck)).is_empty():
				catch_counts[str(ck)] = maxi(_i(d["catches"][ck]), 0) # foreign counts can't poison the %10 bonus
	dex_seen.clear()
	if d.get("dex_seen") is Array:
		for sid in d["dex_seen"]:
			if not SpeciesData.species_of(str(sid)).is_empty():
				dex_seen[str(sid)] = true # unknown ids from other builds just don't get seen
	dex_claimed = clampi(_i(d.get("dex_claimed", 0)), 0, 64)
	# the cataloger's seal re-derives from the ledger — a bare flag with an
	# empty catches dict is the same lie as a crowned flag with no spires
	dex_full = d.get("dex_full") is bool and d["dex_full"] \
		and catch_counts.size() >= ownable_species_count()
	spires_done.clear()
	spire_pos.clear()
	var spv = d.get("spires", [])
	if spv is Array: # only real spire tags — a foreign save can't forge a crown
		for tg in spv:
			var stg := str(tg)
			if spire_tag_ok(stg):
				spires_done[stg] = true
	crowned = spires_done.size() >= SPIRE_DEFS.size() # the crown re-derives
	# from the ruins themselves — a flag lost in a merged save re-mints, and a
	# forged crowned:false can't dethrone a finished campaign (audit-40)
	var spv2 = d.get("spos", {})
	if spv2 is Dictionary: # arena markers: real tags, in-bounds ints only
		for tk in spv2.keys():
			var tp2 = spv2[tk]
			if spire_tag_ok(str(tk)) and tp2 is Array and tp2.size() == 2 \
					and _fin(tp2[0]) and _fin(tp2[1]) \
					and world.in_bounds(_i(tp2[0]), _i(tp2[1])):
				spire_pos[str(tk)] = Vector2i(_i(tp2[0]), _i(tp2[1]))
	weather = str(d.get("weather", "clear")) if str(d.get("weather", "clear")) in ["clear", "rain", "storm", "drought"] else "clear"
	weather_t = clampf(_f(d.get("wthr_t", 0.0)), 0.0, 120.0)
	merchant_deaths = clampi(_i(d.get("mdeaths", 0)), 0, 100) # the Pact's ledger crosses saves
	var gtv = d.get("grotto", []) # dungeon markers ride the save like everything else
	grotto_pos = Vector2i(_i(gtv[0]), _i(gtv[1])) \
		if gtv is Array and gtv.size() == 2 and _fin(gtv[0]) and _fin(gtv[1]) else Vector2i(-1, -1)
	var gv2 = d.get("grotto2", [])
	grotto_room2 = Vector2i(_i(gv2[0]), _i(gv2[1])) \
		if gv2 is Array and gv2.size() == 2 and _fin(gv2[0]) and _fin(gv2[1]) else Vector2i(-1, -1)
	pray_cd = t + clampf(_f(d.get("pray_left", 0.0)), 0.0, 600.0)
	var bq = d.get("board_quest", {})
	var bqk := str(bq.get("kind", "supply")) if bq is Dictionary else ""
	board_quest = {"kind": bqk if bqk in ["supply", "hunt"] else "supply",
		"id": str(bq.get("id", "")), "sp": str(bq.get("sp", "")),
		"n": clampi(_i(bq.get("n", 0)), 0, 999),
		"got": clampi(_i(bq.get("got", 0)), 0, 999),
		"day": _i(bq.get("day", -1))} if bq is Dictionary else {} # foreign saves can't mint an open contract
	var ex = d.get("explored", null) # fog of war rides the save — or starts dark
	if ex is PackedByteArray and ex.size() == world.WORLD_W * world.WORLD_H:
		explored = ex
	else:
		explored.clear(); explored.resize(world.WORLD_W * world.WORLD_H)
	explored_n = explored.count(1) # the dirty key recovers from the real bytes, forged or not
	var tr = d.get("treasure", null) # a marked X rides the save too
	treasure = {"pos": Vector2(_f(tr[0]), _f(tr[1]))} if tr is Array and tr.size() == 2 \
		and _fin(tr[0]) and _fin(tr[1]) else {}
	work_mode = clampi(_i(d.get("wmode", 1)), 0, WORK_MODES.size() - 1)
	base_level = clampi(_i(d.get("blev", 1)), 1, BASE_LEVEL_MAX) # foreign save can't over-level the base
	mission_idx = clampi(_i(d.get("missions", 0)), 0, MISSIONS.size())
	mission_flags.clear()
	var mf = d.get("mflags", {})
	if mf is Dictionary: # bounded: only real mission keys, bools only
		for mk in MISSION_KEYS + ["gauntlet_ex"]: # chain keys + the EX seal — event flags ride the same dict
			if mf.get(mk) is bool and mf[mk]:
				mission_flags[mk] = true
		if mission_flags.size() >= 64: # paranoia cap — same contract as every runtime set
			mission_flags.clear()
	# the accord rides the save but can't be forged without its seals —
	# crown + EX + every heir caught, same bar tick_accord() checks live
	var heirs := 0
	for ls in LEGENDARY_DEN:
		if int(catch_counts.get(ls, 0)) > 0:
			heirs += 1
	accord = crowned and mission_flags.get("gauntlet_ex", false) \
		and heirs >= LEGENDARY_DEN.size() and d.get("accord") is bool and d["accord"]
	var seq = d.get("equip", {})
	if seq is Dictionary: # merge over defaults — a foreign equip dict missing a slot would throw on equipment["slot"] reads
		for slot in ["weapon", "armor", "acc1", "acc2"]:
			var ev = seq.get(slot, "")
			player.equipment[slot] = str(ev) if ItemData.ITEMS.has(str(ev)) else "" # unknown ids equip to nothing
		var wdur: float = float(ItemData.ITEMS.get(player.equipment["weapon"], {}).get("weapon", {}).get("dur", -1))
		var wv = d.get("wear", wdur) # a foreign save can hand us a string — then trust the item, not the field
		player.weapon_wear = (clampf(float(wv), -1.0, maxf(wdur, 1.0)) if _fin(wv) else wdur) if wdur > 0 else -1.0
		var adur: float = float(ItemData.ITEMS.get(player.equipment["armor"], {}).get("armor", {}).get("dur", -1))
		var av = d.get("awear", adur)
		player.armor_wear = (clampf(float(av), -1.0, maxf(adur, 1.0)) if _fin(av) else adur) if adur > 0 else -1.0
	items.clear() # element-wise int() — foreign saves can carry string counts that would break items[id]+n arithmetic later
	for ik in d["items"]:
		if ItemData.ITEMS.has(str(ik)): # a forged "7" key is a dead id the panels would render raw
			items[str(ik)] = maxi(_i(d["items"][ik]), 0) # non-String keys die here — item_wt(sid: String) would abort every frame
	party.clear()
	for u in d["party"]: # typed-array assignment rejects untyped arrays from foreign saves
		var uu := _i(u)
		if uu != 0 and party.size() < party_cap() and not party.has(uu): # uid 0 names nobody; a forged strip can't duplicate either
			party.append(uu)
	var ppos = d["player"].get("pos", [player.pos.x, player.pos.y])
	if ppos is Array and ppos.size() >= 2 and _fin(ppos[0]) and _fin(ppos[1]):
		player.pos = Vector2(float(ppos[0]), float(ppos[1])) # corrupt pos keeps spawn point instead of aborting
	if not world.in_bounds(int(player.pos.x), int(player.pos.y)) or world.blocked(int(player.pos.x), int(player.pos.y)):
		player.pos = nearest_free(world.spawn.x + 0.5, world.spawn.y + 0.5) # OOB/blocked pos from a foreign save = softlock (every move rejected)
	player.hp = _f(d["player"].get("hp", player.hp)); player.level = clampi(_i(d["player"].get("level", 1)), 1, 60) # level<=0 makes derived max_hp negative
	player.xp = maxi(_i(d["player"].get("xp", 0)), 0); player.capture_level = clampi(_i(d["player"].get("cap_lv", 1)), 1, 6) # honest ceiling: 1 + capture perk (≤5) — same bound as the wire
	player.hunger = clampf(_f(d["player"].get("hunger", player.hunger)), 0.0, 100.0)
	player.stamina = clampf(_f(d["player"].get("stamina", 100.0)), 0.0, 100.0) # old saves start rested
	player.meal_t = clampf(_f(d["player"].get("meal_t", 0.0)), 0.0, 600.0) # cap restored buffs
	player.meal_buff = {} # rebuilt key-by-key: raw values reach int()/float() readers every frame
	if player.meal_t > 0.0 and d["player"].get("meal") is Dictionary: # a dead timer carries no buff — the pair travels together or not at all
		for mk in ["atk", "def", "spd", "warm", "cool", "glow"]:
			var mv = d["player"]["meal"].get(mk)
			if _fin(mv): # only the six stats meals actually grant — a forged key can't reach a consumer
				var fm := clampf(float(mv), 0.0, 10.0)
				if fm > 0.0:
					player.meal_buff[mk] = fm
	player.max_hp = 100 + (player.level - 1) * 10 + perks.get("hp", 0) * 12 # never saved — derive it
	player.hp = clampf(player.hp, 1.0, player.max_hp) # forged saves can't make you immortal or limbo-dead — floor 1: respawn always restores >0
	var pending_jobs := []
	var loaded := []
	for pd in d["kin"]:
		if pd is not Dictionary:
			continue # corrupt entry — keep loading the rest
		if SpeciesData.species_of(str(pd.get("sp", ""))).is_empty():
			log_msg(tr("Skipped unknown species in save: %s") % pd.get("sp", "?"))
			continue # corrupt entry — don't crash on spec lookups
		var m0 := str(pd.get("mode", "wild"))
		if m0 not in ["wild", "partner", "base", "box", "bench", "expedition"]:
			m0 = "wild" # foreign strings would poison every mode check
		if m0 != "wild" and not ownable(str(pd.get("sp", ""))):
			log_msg(tr("Skipped unownable rostered species in save: %s") % pd.get("sp", "?"))
			continue # a forged row can't smuggle a human into a roster lane — wild Iron Pact mobs are legit world fauna and load as wild
		var ppos2 = pd.get("pos", [player.pos.x, player.pos.y])
		if ppos2 is not Array or ppos2.size() < 2 or not _fin(ppos2[0]) or not _fin(ppos2[1]):
			continue # no usable position — drop the entry
		if not world.in_bounds(int(ppos2[0]), int(ppos2[1])):
			if str(pd.get("mode", "")) == "box":
				ppos2 = [player.pos.x, player.pos.y] # box pals are never in the world — pos is a placeholder anyway
			else:
				ppos2 = [world.spawn.x, world.spawn.y] # OOB pal could never move again — re-anchor at spawn, don't delete it
		var np := preload("res://src/kin.gd").new()
		np.setup(self, str(pd.get("sp", "")), clampi(_i(pd.get("lv", 1)), 1, 60), Vector2(float(ppos2[0]), float(ppos2[1]))) # lv<=0 makes stat_at return negative max_hp — an instant corpse; the raw sp Variant can't reach the typed param
		np.home = np.pos # loaded pals re-anchor at their saved spot
		var hm = pd.get("home")
		if hm is Array and hm.size() == 2 and _fin(hm[0]) and _fin(hm[1]):
			np.home = Vector2(float(hm[0]), float(hm[1])) # herd anchors ride the save
		np.mode = m0 # already whitelisted above
		if np.mode == "expedition":
			np.visible = false # off-map until its post calls it home
		var hp_saved := _f(pd.get("hp", -1.0)) # absolute under the OLD
		# max_hp — clamping here against the un-multiplied base would shave an
		# 8x guardian to 1/8 hp on every reload. The real clamp lands after
		# apply_bonuses() re-derives max_hp below (audit-40).
		np.talent = clampi(_i(pd.get("talent", np.talent)), 0, 100) # talent outside [0,100] flips stat_at's multiplier negative
		if pd.get("sex") != null:
			np.sex = "F" if str(pd["sex"]) == "F" else "M"
		if pd.get("passives") is Array:
			np.passives = pd["passives"].filter(func(k): return PassiveData.PASSIVES.has(k)) # drop passives removed in newer builds
		if pd.get("alpha"):
			np.alpha = true
			np.sprite.scale = Vector2(1.6, 1.6)
		if pd.get("boss") is bool:
			np.boss = pd["boss"] # only a real bool assigns — GDScript has no bool() ctor and String==true throws
		var pstg := str(pd.get("stag", ""))
		if spire_tag_ok(pstg):
			np.spire_tag = pstg # same whitelist as the spires_done restore — foreign tags can't forge campaign progress
		np.phase = clampi(_i(pd.get("ph", 1)), 1, 2) # a phase-2 boss reloading at 1 would re-run its summon
		np.san = clampf(_f(pd.get("san", np.san)), 0.0, 200.0)
		np.hunger = clampf(_f(pd.get("hunger", 0.0)), 0.0, 100.0)
		var cv2 = pd.get("carry")
		if cv2 is Dictionary and cv2.has("id") and _fin(cv2.get("n", 0)):
			np.carry = {"id": str(cv2["id"]), "n": maxi(int(cv2["n"]), 0)} # haul_ai reads carry["id"]/carry["n"] — a dict missing either crashes every frame
		else:
			np.carry = null
		np.star = clampi(_i(pd.get("star", 0)), 0, 4) # CONDENSE_COST tops at 4 — a foreign star=999 makes pow(1.15,999) overflow the stat line
		np.xp = maxi(_i(pd.get("xp", 0)), 0)
		np.raid = (pd.get("raid") is bool and pd["raid"]) and np.mode == "wild" # a raider flag on a rostered kin would pin danger_active forever — only wild mobs carry it
		var al := str(pd.get("ail", ""))
		if al in Kin.AILMENTS:
			np.ailment = al # unknown/blank ailments fall to healthy
		var stn := str(pd.get("stance", "auto"))
		if stn in STANCES:
			np.stance = stn # a foreign stance string stays at default
		np.fav = pd.get("fav") is bool and pd["fav"] # anything but a real bool stays unlocked — "x" == true is an abort, not a false
		np.soul_boost = clampi(_i(pd.get("sb", 0)), 0, 10)
		np.bounty = clampi(_i(pd.get("bnt", 0)), 0, 999) # foreign saves can't mint a fortune
		np.owner_tag = str(pd.get("own", "")).substr(0, 24)
		np.owner_id = 0 if np.owner_tag == "" else -1 # foreign-owned pals sleep until their keeper says hello
		if pd.get("lucky") is bool:
			np.lucky = pd["lucky"]
		if np.lucky and "lucky" not in np.passives:
			np.passives.append("lucky") # setup() ran before the flag landed — inject its passive here
		if pd.get("extra") is Array:
			np.extra_skills = pd["extra"].filter(func(k): return SkillData.SKILLS.has(k)) # drop skills removed in newer builds
		if pd.get("eq") is Array:
			np.equipped = pd["eq"].filter(func(k): return SkillData.SKILLS.has(k)).slice(0, 3) # loadout caps at 3
		if np.lucky:
			np.sprite.scale = Vector2(1.5, 1.5)
			np.sprite.position.y = -48.0
		if np.raid:
			np.set_meta("raid_t0", t - clampf(_f(pd.get("rt0", 0.0)), 0.0, 600.0)) # a negative rt0 would pin the raider past its 240s sweep forever
		var rvs = pd.get("revive", 0.0)
		np.revive_t = t + float(rvs) if _fin(rvs) and float(rvs) > 0.0 else 0.0 # revive_t=t+0 fires the moment the pal later enters the box — wiping a healthy pal to 30% hp
		np.apply_bonuses()
		if hp_saved < 0.0:
			np.hp = np.max_hp # a missing field heals full under the REAL max
		else:
			np.hp = clampf(hp_saved, 0.0, np.max_hp) # alpha/boss/star/soul/
			# lucky multipliers landed — the saved absolute hp now clamps
			# against the real max, not the setup-time base (audit-40)
		if np.mode == "box":
			if box.size() < MAX_BOX + 32: # same overflow lane the KO path uses
				box.append(np)
				box_pal(np) # box pals live under the hidden holder — never parentless
			else:
				np.free() # over-cap baggage dies here — it never entered the tree
				continue
		elif np.mode == "bench":
			if bench.size() < MAX_BENCH: # a co-op save's orbs scale with party_cap() × guests — the +32 slack was freeing real kin
				bench.append(np)
				box_pal(np) # orbs rest in the same cold store
			else:
				np.free()
				continue
		elif pals.size() < MAX_PALS:
			entity_layer.add_child(np)
			pals.append(np)
			if np.spire_tag != "" and not spire_pos.has(np.spire_tag):
				# a guardian IS its arena — pre-spos saves and crafted saves
				# alike get their map ping back by derivation, not by fiat
				spire_pos[np.spire_tag] = Vector2i(int(np.pos.x), int(np.pos.y))
		else:
			np.free() # past the AI/cap guard — rule 1 applies to saves too
			continue
		loaded.append(np) # unified load order — party_idx indexes pals+box+bench alike
		if pd.get("job") is String:
			pending_jobs.append([np, pd["job"]]) # queued after placement — an over-cap kin's freed node can never dangle here
	if d.get("party_idx") is Array: # has() alone isn't enough — iterating null/a scalar aborts mid-load
		party.clear()
		for pi in d["party_idx"]:
			if pi is int and pi >= 0 and pi < loaded.size() \
					and party.size() < party_cap() and not party.has(loaded[pi].uid):
				party.append(loaded[pi].uid) # a forged strip can't duplicate or overflow
	else: # pre-party_idx saves stored raw uids — new pals got fresh uids, so old refs are dead
		party = party.filter(func(u): return find_pal(u) != null or bench_pal_of(u) != null)
	remote_parties.clear()
	var rps = d.get("rparties", {})
	if rps is Dictionary:
		for tag in rps:
			if remote_parties.size() >= MAX_REMOTE_TAGS:
				break # same roster cap the runtime path enforces
			var arr := []
			for pi2 in (rps[tag] if rps[tag] is Array else []):
				if _fin(pi2) and int(pi2) >= 0 and int(pi2) < loaded.size() \
						and not arr.has(loaded[int(pi2)].uid):
					arr.append(loaded[int(pi2)].uid) # a forged strip can't pin a guest "full" on dup uids
			var rtk := str(tag).substr(0, 24)
			if not arr.is_empty() and rtk != "": # an empty tag can't own a roster — rebind_owner refuses it too
				remote_parties[rtk] = arr.slice(0, party_cap())
	var pbx_sv := Vector2i(-9999, -9999) # saved primary kinbox, if the save is new enough
	var pv = d.get("pbx", [])
	if pv is Array and pv.size() >= 2 and _fin(pv[0]) and _fin(pv[1]):
		pbx_sv = Vector2i(int(pv[0]), int(pv[1]))
	kinbox_pos = Vector2i(-1, -1) # rebuilt below — stale state must not skip the first kinbox
	extra_boxes.clear()
	var st_built := 0
	for ks in d["structures"]:
		if st_built >= MAX_STRUCTURES:
			break # the build cap is a rule-1 bound, not a suggestion — saves obey it too
		if ks is not String:
			continue # store_var preserves foreign key types — split() on an int key aborts mid-rebuild
		var parts: PackedStringArray = ks.split(",")
		if parts.size() < 2:
			continue # malformed cell key — skip rather than abort the load
		var sv = d["structures"][ks]
		var sid: String = str(sv.get("id", "")) if sv is Dictionary else str(sv)
		if not StructureData.STRUCTURES.has(sid):
			log_msg(tr("Skipped unknown structure in save: %s") % sid)
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
			"hp": clampi(_i(sv.get("hp", 200)) if sv is Dictionary else 200, 1, 99999),
			"walkable": s.get("walkable", false), "spike": s.get("spike", 0),
			"snare": s.get("snare", false), "pos": Vector2i(tx, ty),
			"turret": s.get("turret", 0), # both placement paths write these — a
			# loaded turret that can't shoot and a kinbox that lost its anchor
			# guard are the same defect: rebuild must match the placement schema
			"loot": (sv.get("loot") is bool and sv["loot"]) if sv is Dictionary else false}
		st_built += 1
		if sv is Dictionary:
			if sv.get("mimic") is String and str(sv["mimic"]) != "" and sid == "chest":
				st["mimic"] = str(sv["mimic"]) # a saved hunger survives the save
			if sv.get("cap") is Dictionary and sid == "kin_cage":
				var cap_d: Dictionary = sv["cap"]
				var cap_sp := str(cap_d.get("sp", ""))
				if not SpeciesData.species_of(cap_sp).is_empty(): # an unknown species would abort gen_pal mid-free — the cage loads empty instead
					st["captive"] = {"sp": cap_sp, "lv": clampi(_i(cap_d.get("lv", 5)), 1, 60)}
			if sv.get("store") is Dictionary:
				for sk2 in sv["store"]: # counts used in +/- arithmetic everywhere — coerce, skip junk
					var cv = sv["store"][sk2]
					if _fin(cv):
						st["store"][str(sk2)] = maxi(int(cv), 0) # negative stock would make chest math lie
			st["timer"] = maxf(_f(sv.get("timer", 0.0)), 0.0) # negative timer fires production instantly; st["timer"] += dt arithmetic follows — a string would throw
			if sv.get("egg") is Array: # tick_ranch size()/pop_fronts this — anything else errors per frame
				st["egg_parents"] = []
				for e2 in sv["egg"]:
					if _norm_pair(e2) is Array:
						if e2.size() > 8: # owner column: tags or legacy pids — coerce, cap at 2
							var own_ok := []
							if e2[8] is Array:
								for o in e2[8]:
									if (o is String and o.length() <= 24) or o is int \
											or (o is float and is_finite(o)):
										own_ok.append(o)
									if own_ok.size() >= 2:
										break
							e2 = e2.slice(0, 8) + [own_ok]
						st["egg_parents"].append(e2)
					if st["egg_parents"].size() >= MAX_EGG_QUEUE:
						break # the runtime cap binds loaded rows too — a crafted save can't stuff it
			# S76 migration: a legacy ranch stored its laid eggs under kin_egg —
			# the shared id let any wild egg drain the bloodline queue. Nothing
			# but a pairing ever writes a ranch's store, so every kin_egg found
			# there is a bred egg by definition — rename it once, on the way in.
			if sid == "ranch" and int(st["store"].get("kin_egg", 0)) > 0:
				st["store"]["bred_kin_egg"] = int(st["store"].get("bred_kin_egg", 0)) \
					+ int(st["store"]["kin_egg"])
				st["store"].erase("kin_egg")
			if sv.get("exp") is Dictionary and sid == "expedition_post":
				var exp_d: Dictionary = sv["exp"]
				var left: float = _f(exp_d.get("left", 0.0))
				if left > 0.0:
					st["exp_end"] = t + clampf(left, 1.0, 900.0) # foreign timers can't pin a pal away forever
				st["exp_cd"] = t + maxf(_f(exp_d.get("cd", 0.0)), 0.0)
			if _fin(sv.get("fert")):
				st["fert"] = t + clampf(float(sv["fert"]), 0.0, 300.0) # remaining seconds
			if sv.get("inc") is Dictionary and sid == "incubator":
				var inc_d: Dictionary = sv["inc"]
				var inc_pair = _norm_pair(inc_d.get("pair")) # heads + numeric tails both checked — see _norm_pair
				st["egg_inc"] = {"pair": inc_pair, "huge": inc_d.get("huge") is bool and inc_d["huge"],
					"ready_t": t + maxf(_f(inc_d.get("left", 30.0)), 1.0),
					"own_tag": str(inc_d.get("own", ""))} # pids are session-scoped — the tag is what survives a save
			if sv.get("by") is String and str(sv["by"]) != "":
				st["placed_tag"] = str(sv["by"]).left(24) # keeper tag — pids are session-scoped
		for dy in range(h):
			for dx in range(w):
				structures[Vector2i(tx + dx, ty + dy)] = st
				_struct_gen += 1
				world.structures[world.idx(tx + dx, ty + dy)] = st
		if sid == "kinbox":
			var o := Vector2i(tx, ty)
			if o == pbx_sv:
				if kinbox_pos.x >= 0 and kinbox_pos != o and kinbox_pos not in extra_boxes:
					extra_boxes.append(kinbox_pos) # earlier guess demoted
				kinbox_pos = o
			elif kinbox_pos.x < 0:
				kinbox_pos = o
			elif o != kinbox_pos and o not in extra_boxes and extra_boxes.size() < MAX_EXTRA_BOXES:
				extra_boxes.append(o)
	for pj in pending_jobs:
		var parts2: PackedStringArray = pj[1].split(",")
		if parts2.size() < 2:
			continue # malformed job cell key
		var cell := Vector2i(int(parts2[0]), int(parts2[1]))
		if structures.has(cell) and pj[0].mode in ["base", "expedition"] \
				and pj[0] not in structures[cell]["workers"] \
				and structures[cell]["workers"].size() < 4:
			# same crew cap find_work_site enforces — a crafted save can't stuff a site
			structures[cell]["workers"].append(pj[0])
			pj[0].job_site = structures[cell]
	for lp2 in pals:
		if lp2.mode != "expedition":
			continue
		var home2 := false
		for k2 in structures:
			var s2: Dictionary = structures[k2]
			if s2["id"] == "expedition_post" and lp2 in s2["workers"]:
				s2["exp_pal"] = lp2 # re-link the post so tick_production can call it home
				if float(s2.get("exp_end", 0.0)) <= 0.0:
					s2["exp_end"] = t + 60.0 # save predates the field — bring them home soon
				home2 = true
				break
		if not home2: # the post is gone — the pal walks back in
			lp2.mode = "base"
			lp2.visible = true
	_reset_shell_state()
	net_residue = false # a loaded solo world is yours again — residue lifted
	log_msg(tr("Loaded."))
	return true

func _reset_shell_state() -> void:
	# stale shell state must not leak across a world swap: an armed raid horn,
	# an open panel, a dead chest ref, a held aim — none of them survive it.
	# load_game and regenerate both swap the world — one reset serves both.
	raid_warned = false
	raid_theme = ""
	panel = ""
	chest_ref = null
	skill_target = null
	if player != null:
		player.aiming = false
		player.dodge_t = 0.0
		player.touch_vec = Vector2.ZERO # a swap mid-drift must not inherit the stick
		player.touch_sprint = false
		if hud != null: hud.joy_idx = -1 # ...nor its owner finger

# monitoring stand work pace (the island: normal/hard/super-hard). Needs the
# stand built to mean anything; default 1 preserves the classic x1.4 boost.
var work_mode := 1
var cur_san_mult := 1.0 # written each production tick; pals read it when working
const WORK_MODES := [
	{"name": "Normal", "prod": 1.0, "san": 1.0},
	{"name": "Hard", "prod": 1.4, "san": 1.6},
	{"name": "Overdrive", "prod": 1.9, "san": 2.4},
]

func cycle_work_mode() -> void:
	if client_locked():
		return
	if not has_structure("monitoring_stand"):
		return
	work_mode = (work_mode + 1) % WORK_MODES.size()
	var wm: Dictionary = WORK_MODES[work_mode]
	floater(player.pos, tr("Work: %s") % tr(str(wm["name"])), "#e8d44d")
	log_msg(tr("Monitoring stand: %s pace (output x%.2f, SAN drain x%.1f)")
		% [tr(str(wm["name"])), wm["prod"], wm["san"]])

var supply_t := 300.0 # wandering care package — lands near the player
func tick_supply(dt: float) -> void:
	if net != null and net.is_client():
		return # crate drops are host spawns — replicas arrive via drop_sync
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
		loot.append([["mega_orb", "giga_orb"][mini(day / 6, 1)], rng.int_range(2, 4)])
		loot.append([["baked_berries", "jam_bun", "bread"][rng.int_range(0, 2)], rng.int_range(2, 4)])
		loot.append(["gold_coin", rng.int_range(10, 25)])
		for i in loot.size():
			var li: Array = loot[i]
			spawn_drop(str(li[0]), int(li[1]),
				Vector2(tx + 0.5 + (i % 2) * 0.8, ty + 0.5 + (i / 2) * 0.8))
		floater(Vector2(tx + 0.5, ty + 0.5), tr("SUPPLY DROP!"), "#ffd76e")
		log_msg(tr("A supply crate lands nearby — grab it before the locals do"))
		return

var mig_t := 300.0 # passing herds — a deeper zone's species crosses the map
func tick_migration(dt: float) -> void:
	if net != null and net.is_client():
		return # migrants arrive as host-synced replicas — a local herd would
		# be phantom fauna: real AI, real loot, invisible to the host
	mig_t -= dt
	if mig_t > 0.0:
		return
	mig_t = 420.0 + rng.next() * 420.0 # a herd drifts through every 7-14 minutes
	# migrants come from a deeper band — a taste of what lives one zone over,
	# catchable without walking there. Host-only like spawn_wild — the
	# replicas clients render come through pal_sync, not this roll.
	var zone := rng.int_range(1, 3)
	var pool: Array = acq_pool(ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone))
	if pool.is_empty():
		return
	var sid := pick_wild_species(pool)
	var sp: Dictionary = SpeciesData.species_of(sid)
	var aquatic: bool = "water" in sp.get("elements", [])
	for _try in 60:
		var x := rng.int_range(4, World.WORLD_W - 5)
		var y := rng.int_range(4, World.WORLD_H - 5)
		if player.pos.distance_squared_to(Vector2(x, y)) < 256.0:
			continue # a herd on your boots is an ambush, not a migration
		var in_water: bool = world.tiles[world.idx(x, y)] == World.Tile.WATER
		if in_water:
			if not aquatic or not world.swim_open(x, y):
				continue
		elif world.blocked(x, y):
			continue
		var lv := wild_lv(zone)
		var made: Array = []
		for _i in rng.int_range(4, 6):
			if pals.size() >= MAX_PALS:
				break
			var mx: int = clampi(x + rng.int_range(-3, 3), 1, World.WORLD_W - 2)
			var my: int = clampi(y + rng.int_range(-3, 3), 1, World.WORLD_H - 2)
			var m_in_water: bool = world.tiles[world.idx(mx, my)] == World.Tile.WATER
			if m_in_water != in_water or (not m_in_water and world.blocked(mx, my)):
				continue
			var mp := preload("res://src/kin.gd").new()
			mp.alpha = zone >= 2 and rng.chance(0.08)
			mp.lucky = not mp.alpha and rng.chance(0.015)
			entity_layer.add_child(mp)
			mp.setup(self, sid,
				lv + (6 if mp.alpha else 0) + (3 if mp.lucky else 0),
				Vector2(mx + 0.5, my + 0.5))
			mp.home = Vector2(x + 0.5, y + 0.5) # the herd shares one anchor
			pals.append(mp)
			made.append(mp)
		if made.size() < 3: # a scattered pair isn't a herd — take the strays back
			for mp2 in made:
				pals.erase(mp2)
				mp2.queue_free()
			continue
		floater(Vector2(x + 0.5, y + 0.5), tr("MIGRATION!"), "#ffd76e")
		log_msg(tr("A herd of %s is migrating %s! (%d head)")
			% [tr(str(sp.get("name", sid))), tr("ashore") if in_water else tr("inland"), made.size()])
		return

const RAID_WARN_T := 30.0 # seconds of horn before the wave lands
var raid_warned := false # 30s heads-up — the island flashes the raid horn early
var raid_theme := ""     # element pack for the incoming wave; "" = mixed
func tick_raid(dt: float) -> void:
	if net != null and net.is_client():
		return # raid_t is not synced — a client wave would be phantoms the host
		# never heard of, chewing synced structures it can't really damage
	if kinbox_pos.x < 0:
		return
	if not settings.get("raids", true):
		# peaceful mode: hold the horn just above the warning line — and stand
		# an already-armed warning down so re-enabling re-arms it cleanly
		raid_t = RAID_WARN_T + 1.0
		raid_warned = false
		raid_theme = ""
		return
	raid_t -= dt
	if raid_t < RAID_WARN_T and not raid_warned:
		raid_warned = true
		# the island raids read as packs — mostly one element, sometimes a mob
		var themes := ["fire", "water", "electric", "grass", "dark", "ice", "ground", "dragon"]
		# signature raid: the Iron Pact sends humans, not kin
		raid_theme = "Iron Pact" if rng.chance(0.15) else \
			("" if rng.chance(0.25) else themes[rng.int_range(0, themes.size() - 1)])
		var howl := tr("Iron Pact squad") if raid_theme == "Iron Pact" else \
			((tr("%s pack") % tr(str(raid_theme))) if raid_theme != "" else tr("wild mob"))
		log_msg(tr("Raid party spotted — a %s is coming for the kinbox!") % howl)
		sfx_play("horn")
		floater(player.pos, tr("RAID INCOMING"), "#e8452f")
		if net != null: # guests get the same 30s horn, not just the wave
			for gpid in net.ghosts:
				note_remote(int(gpid), "RAID INCOMING — %s!", [howl])
	if raid_t <= 0:
		raid_t = 240.0 + rng.next() * 180.0
		raid_warned = false # next wave gets its own warning
		start_raid()

func start_raid() -> void:
	if net != null and net.is_client():
		return # only the host field-promotes raiders
	var c := Vector2(kinbox_pos.x + 0.5, kinbox_pos.y + 0.5)
	# the island escalation: raids grow with the campaign — formulas live in
	# Combat so the sim gates the shipped math, not a copy of it
	var day_bonus := Combat.raid_day_bonus(day)
	var n := 3 + rng.int_range(0, 2) + Combat.raid_wave_bonus(day)
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
			# raiders are kin species — ironpact humans stay UNcatchable
			# (ownable=false) even though they ride the same wave — never legends
			var pool: Array = (ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone)).filter(
				func(s): return s not in LEGENDARY_DEN)
			var hostile_pool := pool.filter(func(s): return SpeciesData.species_of(s).get("hostile", 0) >= 1)
			if hostile_pool.is_empty():
				hostile_pool = pool
			var pick_pool: Array
			if raid_theme == "Iron Pact":
				pick_pool = ["ironpact_grunt", "ironpact_sweeper"] # humans ignore zone tables
			else:
				var themed := hostile_pool.filter(func(s): return raid_theme != "" and raid_theme in SpeciesData.species_of(s).get("elements", []))
				pick_pool = themed if not themed.is_empty() else hostile_pool
			var sid: String = pick_pool[rng.int_range(0, pick_pool.size() - 1)]
			if pals.size() >= MAX_PALS:
				break # the cap binds attackers too — a wave can't push past it
			var rp := preload("res://src/kin.gd").new()
			entity_layer.add_child(rp)
			rp.setup(self, sid, rng.int_range(3 + zone * 3 + day_bonus, 6 + zone * 5 + day_bonus), Vector2(tx + 0.5, ty + 0.5))
			if sid.begins_with("ironpact") and rng.chance(0.3): # canonical ids, not the theme string
				rp.bounty = rng.int_range(8, 18) # wanted criminals pay cash on the spot
			# raider picks nearest non-wild kin; falls back to the player
			rp.aggro = 0
			rp.aggro_pid = rp.nearest_body_pid() # or the guest it spawns on top of
			rp.raid = true
			rp.set_meta("raid_t0", t)
			var bp: Kin = null; var bd := 30.0
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
		log_msg(tr("!! RAID: %d hostile kin approach your base !!") % spawned)

# ---------- breeding ----------
func tick_ranch(key: Vector2i, st: Dictionary, dt: float) -> void:
	# grazing produce (the island): every ranch kin drops its species good on its
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
			floater(Vector2(key.x + 0.5, key.y + 0.5),
				tr("+%s") % tr(str(ItemData.ITEMS.get(fm["item"], {}).get("name", fm["item"]))), "#a8e6a1")
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
	# the island rule: breeding burns a cake per egg, pulled from base storage
	if not consume_ready([["cake", 1]]):
		if not st.get("cake_warned", false):
			st["cake_warned"] = true
			floater(Vector2(key.x + 0.5, key.y + 0.5), tr("needs cake!"), "#f2a0b5")
			log_msg(tr("Ranch needs a cake (chest/feed box) to breed"))
		st["timer"] = 0.0
		return
	st["cake_warned"] = false
	st["timer"] += (dt * (1.0 + perks["work"] * 0.1))
	var rate := 60.0
	if st["timer"] < rate:
		return
	st["timer"] -= rate
	var a: Kin = null; var b: Kin = null
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
	# (the island: offspring can hatch knowing a parent's skill)
	var owners := []
	for o in [a.owner_tag, b.owner_tag]: # tags, not pids — a recycled peer id
		if o not in owners:                # can't inherit someone else's genetics
			owners.append(o)
	st["egg_parents"].append([a.species_id, b.species_id, a.talent, b.talent,
		a.passives.duplicate(), b.passives.duplicate(),
		a.learned_skills(), b.learned_skills(), owners])
	st["store"]["bred_kin_egg"] = st["store"].get("bred_kin_egg", 0) + 1 # lays AT the ranch; haulers collect —
	# bred eggs carry their own id so parentage claims can never land on a wild egg
	floater(Vector2(key.x + 0.5, key.y + 0.5), tr("Egg!"), "#f5e6c8")
	log_msg(tr("%s + %s produced an egg!") % [tr(str(a.spec["name"])), tr(str(b.spec["name"]))])

func tick_dojo(key: Vector2i, st: Dictionary, job: Dictionary, dt: float) -> void:
	# kinbox lesson: a posted veteran drills one pupil per bell —
	# youngsters pick up a move the teacher already carries, fruits stay the
	# only way past three taught tricks
	var teacher: Kin = null
	for w in st["workers"]:
		if is_instance_valid(w) and w.job_site == st and w.mode == "base" \
				and w.san >= 15.0 and w.hunger < 80.0 and not w.has_status("sleep"):
			teacher = w
			break
	if teacher == null:
		st["timer"] = 0.0
		return
	st["timer"] += dt
	var rate: float = job.get("amount", 90)
	if st["timer"] < rate:
		return
	st["timer"] -= rate
	var known: Array = teacher.active_skills()
	if known.is_empty():
		return
	var center := Vector2(key.x + 0.5, key.y + 0.5)
	var pupils := []
	for p in pals:
		if p == teacher or p.mode != "base" or p.hp <= 0 or p.has_status("sleep"):
			continue
		if p.pos.distance_to(center) > 10.0 or p.extra_skills.size() >= 3:
			continue
		var pool: Array = known.filter(func(sid): return sid not in p.learned_skills())
		if not pool.is_empty():
			pupils.append(p)
	if pupils.is_empty():
		return
	var pupil: Kin = pupils[rng.int_range(0, pupils.size() - 1)]
	var pool2: Array = known.filter(func(sid): return sid not in pupil.learned_skills())
	var sid: String = pool2[rng.int_range(0, pool2.size() - 1)]
	pupil.extra_skills.append(sid)
	pal_gain_xp(teacher, 4) # drilling others keeps the veteran's own claws sharp
	var sname: String = tr(str(SkillData.SKILLS.get(sid, {}).get("name", sid)))
	floater(center, tr("%s learns %s!") % [tr(str(pupil.spec.get("name", pupil.species_id))), sname], "#ffd97a")
	log_msg(tr("%s taught %s %s") % [tr(str(teacher.spec.get("name", teacher.species_id))),
		tr(str(pupil.spec.get("name", pupil.species_id))), sname])

func tick_spar(key: Vector2i, st: Dictionary, job: Dictionary, dt: float) -> void:
	# paired drills, not solo reps — two posted kin spar on the bell: the
	# winner banks more experience and both walk out a little wearier
	var pair := []
	for w in st["workers"]:
		if is_instance_valid(w) and w.job_site == st and w.mode == "base" \
				and w.san >= 15.0 and w.hunger < 80.0 and not w.has_status("sleep"):
			pair.append(w)
	if pair.size() < 2:
		st["timer"] = 0.0
		return
	st["timer"] += dt
	var rate: float = job.get("amount", 60)
	if st["timer"] < rate:
		return
	st["timer"] -= rate
	var a: Kin = pair[0]; var b: Kin = pair[1]
	# level weighs the bout — a veteran usually wins, but upsets happen
	var a_wins := rng.next() * (a.level + b.level) < a.level
	var champ: Kin = a if a_wins else b
	var loser: Kin = b if a_wins else a
	pal_gain_xp(champ, 8)
	pal_gain_xp(loser, 4)
	for w in [a, b]:
		w.san = maxf(0.0, w.san - 4.0) # a bout costs spirit, not blood
	floater(Vector2(key.x + 0.5, key.y + 0.5), tr("%s wins the bout!") % tr(str(champ.spec.get("name", champ.species_id))), "#ffd97a")

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

func deposit_egg(prefer: String = "") -> void:
	if client_locked():
		return
	# the island: eggs go into an incubator; hatching takes real time.
	# A clicked egg wins when held — else huge > bred > wild, the old order.
	var egg_id := ""
	if prefer in ["kin_egg", "bred_kin_egg", "huge_kin_egg"] and item_count(prefer) > 0:
		egg_id = prefer
	elif item_count("huge_kin_egg") > 0:
		egg_id = "huge_kin_egg"
	elif item_count("bred_kin_egg") > 0:
		egg_id = "bred_kin_egg"
	elif item_count("kin_egg") > 0:
		egg_id = "kin_egg"
	else:
		return
	var site: Vector2i = _free_incubator(player.pos)
	if site.x < 0:
		log_msg(tr("Need a free incubator nearby"))
		return
	add_item(egg_id, -1)
	# only a bred egg carries a pairing claim — wild and huge eggs hatch off
	# the common pool and can never drain the ranch's parentage queue
	var pair = _claim_egg_parent(0) if egg_id == "bred_kin_egg" else null
	var warm_hint := false
	for k3 in structures:
		if structures[k3]["id"] == "campfire" \
				and Vector2(k3.x - site.x, k3.y - site.y).length() <= 6.0:
			warm_hint = true
			break
	structures[site]["egg_inc"] = {"pair": pair, "ready_t": t + 90.0,
		"huge": egg_id == "huge_kin_egg"}
	var hint := egg_hint(pair)
	log_msg(tr("%s incubating - ready in 90s%s%s")
		% [tr("Huge egg") if egg_id == "huge_kin_egg" else tr("Egg"),
			"" if warm_hint else tr(" (a campfire would hurry it)"),
			" — " + hint if hint != "" else ""])

# parentage is claimed by bloodline owner: entry[8] carries the parents'
# owner ids; legacy untagged entries answer the keeper (pid 0) only. A
# guest's wild egg can't quietly inherit the host's ranch genetics.
func _claim_egg_parent(pid: int):
	var tag := str(net.peer_tags.get(pid, "")) if pid > 0 and net != null else ""
	for k2 in structures:
		var q = structures[k2].get("egg_parents")
		if not (q is Array):
			continue
		for i2 in q.size():
			var e9 = q[i2]
			var owners: Array = e9[8] if (e9 is Array and e9.size() > 8
				and e9[8] is Array) else [0]
			if pid == 0:
				if owners.has("") or owners.has(0): # tagged or legacy keeper row
					return q.pop_at(i2)
			elif tag != "" and owners.has(tag):
				return q.pop_at(i2) # oldest matching claim wins
	return null

# a demolished incubator gives the claimed bloodline back: the consumed
# queue row rides home to the nearest ranch with room, so the refunded
# bred egg redeposits onto the SAME parents, not the next pair in line.
func _return_egg_parent(row, near: Vector2) -> void:
	if not (row is Array):
		return
	var best_q = null
	var bd := INF
	for kr in structures:
		var q = structures[kr].get("egg_parents")
		if not (q is Array) or q.size() >= MAX_EGG_QUEUE:
			continue
		var dd := Vector2(kr.x + 0.5, kr.y + 0.5).distance_squared_to(near) # cells are addressed by center — corner math skews "nearest"
		if dd < bd:
			bd = dd; best_q = q
	if best_q != null:
		best_q.append(row) # the claim comes home — same blood, next deposit
	# else: every ranch ledger is full — the record burns with the box after all

func _free_incubator(at: Vector2, bound := 20.0) -> Vector2i:
	# bound is the caller's arm: the keeper's own E stretches across the yard,
	# a witnessed ghost only reaches the usual six tiles
	var site := Vector2i(-1, -1)
	var bd := bound * bound # callers speak in tiles; the compare is squared
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] != "incubator" or st.has("egg_inc"):
			continue
		var dd := at.distance_squared_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd < bd:
			bd = dd; site = k
	return site

# host-side guest deposit: the claimed egg kind is whitelisted, the slot
# carries the depositor's pid so the hatch lands in THEIR slice
func egg_req_remote(pid: int, egg_id: String) -> bool:
	if egg_id not in ["kin_egg", "bred_kin_egg", "huge_kin_egg"]:
		return false
	var at := _ghost_at(pid)
	if at.x < -1e8:
		return false
	var site := _free_incubator(at, 6.0)
	if site.x < 0:
		note_remote(pid, "Need a free incubator nearby")
		return false
	var pair = _claim_egg_parent(pid) if egg_id == "bred_kin_egg" else null
	structures[site]["egg_inc"] = {"pair": pair, "ready_t": t + 90.0,
		"huge": egg_id == "huge_kin_egg", "own_pid": pid,
		"own_tag": str(net.peer_tags.get(pid, "")) if net != null else ""}
	return true

func egg_hint(pair) -> String:
	# the island tells you what's inside: named pairings show their species,
	# anything else just says which bloodline it takes after
	if pair is Array and pair.size() >= 2:
		var combo: String = BREED_COMBOS.get("%s+%s" % [pair[0], pair[1]],
			BREED_COMBOS.get("%s+%s" % [pair[1], pair[0]], ""))
		if combo != "":
			return str(tr(str(SpeciesData.species_of(combo).get("name", combo))))
		var pn: String = tr(str(SpeciesData.species_of(str(pair[0])).get("name", str(pair[0]))))
		return tr("%s line") % pn
	return ""

# Egg genetics stay mortal: legendaries are den bosses, and ironpact humans
# don't come out of eggs. Every unparented hatch (wild eggs, gacha) draws here.
func hatch_pool() -> Array:
	var out := []
	for s in SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys():
		var spec: Dictionary = SpeciesData.species_of(s)
		if s in LEGENDARY_DEN or spec.get("boss", false) or not acquirable(s):
			continue
		if s not in out:
			out.append(s)
	return out

func hatch_incubated(key: Vector2i, st: Dictionary) -> void:
	var inc = st.get("egg_inc")
	st.erase("egg_inc")
	var pair = inc.get("pair") if inc is Dictionary else null
	var huge := bool(inc.get("huge", false)) if inc is Dictionary else false
	var sp_id: String
	var talent_v: int
	var inherited := []
	if pair is Array and pair.size() >= 4:
		# the island breeding: signature pairings produce a fixed third species;
		# everything else inherits one of the two parents.
		var combo: String = BREED_COMBOS.get("%s+%s" % [pair[0], pair[1]],
			BREED_COMBOS.get("%s+%s" % [pair[1], pair[0]], ""))
		sp_id = combo if combo != "" else pair[rng.int_range(0, 1)]
		if not acquirable(sp_id): # a legendary parent can't pass its bloodline on
			sp_id = hatch_pool()[rng.int_range(0, hatch_pool().size() - 1)]
		talent_v = clampi((int(pair[2]) + int(pair[3])) / 2 + rng.int_range(-15, 15), 0, 100)
		if pair.size() >= 6 and pair[4] is Array and pair[5] is Array:
			for pk in pair[4] + pair[5]: # the island: passives run in the bloodline
				if pk not in inherited:
					inherited.append(pk)
	else: # found egg with no recorded parentage — wild genetics
		var pool := hatch_pool()
		sp_id = pool[rng.int_range(0, pool.size() - 1)]
		talent_v = rng.int_range(0, 100)
	if SpeciesData.species_of(sp_id).is_empty() and SpeciesGen.SPECIES.get(sp_id, {}).is_empty():
		var pool2 := hatch_pool()
		sp_id = pool2[rng.int_range(0, pool2.size() - 1)]
	var at: Vector2 = nearest_free(key.x + 1.0, key.y + 2.5) # don't hatch into a wall
	var np := preload("res://src/kin.gd").new()
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
	while np.passives.size() > 4: # 4-trait cap binds bloodlines too
		np.passives.pop_back()
	np.apply_bonuses()
	np.hp = np.max_hp
	if pair is Array and pair.size() >= 8: # egg moves: hatch with a parent skill
		var pool_s: Array = (pair[6] if pair[6] is Array else []) + (pair[7] if pair[7] is Array else [])
		pool_s = pool_s.filter(func(k): return SkillData.SKILLS.has(k) and k not in np.learned_skills())
		if not pool_s.is_empty():
			np.extra_skills.append(pool_s[rng.int_range(0, pool_s.size() - 1)])
	if huge: # huge eggs: a guaranteed golden Lucky hatches out
		np.lucky = true
		sfx_play("lucky")
		if "lucky" not in np.passives:
			np.passives.push_front("lucky")
		while np.passives.size() > 4:
			np.passives.pop_back()
		np.apply_bonuses()
		np.hp = np.max_hp
		np.sprite.scale = Vector2(1.5, 1.5)
		np.sprite.position.y = -48.0
	var opid := int(inc.get("own_pid", 0)) if inc is Dictionary else 0
	var otag := str(inc.get("own_tag", "")) if inc is Dictionary else ""
	if net != null:
		var live: Array = multiplayer.get_peers() if multiplayer.multiplayer_peer != null else []
		if opid > 0 and not live.has(opid):
			opid = 0 # the depositor left mid-incubation — the tag below finds them on rejoin
		if opid <= 0 and otag != "":
			for cand in net.peer_tags:
				if str(net.peer_tags[cand]) == otag and live.has(int(cand)):
					opid = int(cand); break
	if opid > 0 or otag != "": # a guest's deposit hatches into their slice — tagged orphans rebind on hello
		np.owner_id = opid if opid > 0 else -1
		np.owner_tag = otag if otag != "" else (str(net.peer_tags.get(opid, "")) if net != null else "")
	if kinbox_pos.x >= 0 and pals.size() < MAX_PALS and base_pals().size() < max_base_pals():
		np.mode = "base" # the hatch obeys the same caps every other kin path does
		pals.append(np)
	elif box.size() < MAX_BOX + 32: # no base — or a full one: the KO overflow lane
		np.mode = "box"
		box.append(np)
		box_pal(np)
	else:
		np.queue_free() # double-cap: the chick dies clean rather than break rule 1
		log_msg(tr("The egg hatched… but there was no room for the chick"))
	if pair is Array:
		mission_flags["egg"] = true # a bred egg — wild nest finds don't count
	floater(at, tr("* hatched! *"), "#4dd0e1")
	log_msg(tr("Egg hatched: %s%s (talent %d)!") % [tr("LUCKY ") if huge else "",
		tr(str(np.spec["name"])), talent_v])
	sfx_play("hatch")

func spawn_camps() -> void:
	# Iron Pact poacher camps (the island POI): a caged kin under armed guard.
	# The captive exists only as cage data until someone breaks the lock —
	# no entity, no timer, nothing to leak.
	var placed := 0
	var tries := 0
	while placed < 2 and tries < 6000:
		tries += 1
		var tx := rng.int_range(6, World.WORLD_W - 8)
		var ty := rng.int_range(6, World.WORLD_H - 8)
		var zone: int = world.zone_at(tx, ty)
		if zone < 2:
			continue
		var ok := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if world.blocked(tx + dx, ty + dy) or structures.has(Vector2i(tx + dx, ty + dy)):
					ok = false
		if not ok:
			continue
		if not place_free("kin_cage", tx, ty):
			continue
		var pool: Array = acq_pool(ZONE_SPECIES[zone] + SpeciesGen.zone_pool(zone))
		var cst: Dictionary = structures[Vector2i(tx, ty)]
		var csp := pick_wild_species(pool) # "" on an empty pool — a cage that
		if csp != "":                    # can't hold a species holds nothing
			cst["captive"] = {"sp": csp, "lv": rng.int_range(8 + zone * 4, 14 + zone * 6)}
		var gn := 2 + int(rng.chance(0.5))
		for i in gn:
			var gid: String = "ironpact_grunt" if i % 2 == 0 else "ironpact_sweeper"
			var gp := preload("res://src/kin.gd").new()
			entity_layer.add_child(gp)
			gp.setup(self, gid, rng.int_range(12 + zone * 4, 18 + zone * 5),
				Vector2(tx + [0.5, 1.5, -0.5][i % 3], ty + [1.5, -0.5, 1.5][i % 3]))
			gp.home = Vector2(tx + 0.5, ty + 0.5) # den-pack aggro: one shout wakes the camp
			pals.append(gp)
		placed += 1

func free_captive(st: Dictionary) -> void:
	if client_locked():
		return
	# prize the lock — the caged kin joins your box like any catch
	var cap = st.get("captive")
	if not (cap is Dictionary) or str(cap.get("sp", "")) == "":
		log_msg(tr("The cage is empty"))
		return
	if box.size() >= MAX_BOX:
		log_msg(tr("Kinbox is full — the captive won't leave its cage"))
		return
	if not ownable(str(cap["sp"])):
		log_msg(tr("The cage holds something that can't be kept"))
		return # the ownable gate — worldgen cages can't hold this anyway
	var bp := gen_pal(str(cap["sp"]), int(cap["lv"]), player.pos)
	bp.mode = "box"
	box.append(bp)
	box_pal(bp)
	gain_xp(15)
	floater(player.pos, tr("FREED!"), "#8ef0a8")
	log_msg(tr("Freed %s Lv%d — it scurries into your kinbox") % [tr(str(bp.spec["name"])), bp.level])
	net_remove_structure(st)

func spawn_fossils() -> void:
	# old bones heaped in the deep wilds — a one-shot dig, then gone
	var placed := 0
	var tries := 0
	while placed < 4 and tries < 3000:
		tries += 1
		var tx := rng.int_range(6, World.WORLD_W - 8)
		var ty := rng.int_range(6, World.WORLD_H - 8)
		if world.zone_at(tx, ty) < 2 or world.blocked(tx, ty) \
				or structures.has(Vector2i(tx, ty)):
			continue
		if place_free("fossil_bed", tx, ty):
			placed += 1 # haulers key on chest ids — a bone-heap needs no flag

func dig_fossil(st: Dictionary) -> void:
	if client_locked():
		return
	var cell: Vector2i = st.get("pos", Vector2i(-1, -1))
	var pos := Vector2(cell.x + 0.5, cell.y + 0.5)
	net_remove_structure(st) # one dig and the bed is spent
	var n := rng.int_range(2, 4)
	add_item("ancient_part", n)
	add_item("stone", 4)
	var shard := rng.chance(0.25)
	if shard:
		add_item("lumenite", 1)
	floater(pos, tr("+%d ancient parts") % n, "#ffd76e")
	log_msg(tr("Fossil dug: %d ancient parts%s") % [n, tr(" and a lumenite shard") if shard else ""])
	sfx_play("catch")

func open_mimic(st: Dictionary, opener_pid := 0) -> void:
	if client_locked():
		return
	# some dungeon chests are only chest-shaped — open it and it opens back
	var sp: String = str(st.get("mimic", ""))
	if sp == "" or SpeciesData.species_of(sp).is_empty():
		return
	var cell: Vector2i = st.get("pos", Vector2i(-1, -1))
	net_remove_structure(st) # the box was a mouth; deferred so nothing iterates a ghost
	var m: Kin = gen_pal(sp, wild_lv(world.zone_at(cell.x, cell.y)) + 4,
		Vector2(cell.x + 0.5, cell.y + 0.5))
	m.mode = "wild"
	m.aggro = 0 # the mimic picks its fight before you pick yours
	m.aggro_pid = opener_pid # chest-opening is a keeper verb — the opener is the mark
	pals.append(m)
	floater(m.pos, tr("IT GRINS."), "#e8452f")
	log_msg(tr("The chest was a %s — it was never a chest!") % tr(str(m.spec["name"])))
	sfx_play("fail")

# host-side guest probe: clients can't see the mimic flag (the trap stays
# armed on the wire) — they ask, and if it was a mouth it opens on THEM
func mimic_req_remote(pid: int, cell: Vector2i) -> bool:
	var st = structures.get(cell)
	if st == null or str(st.get("mimic", "")) == "":
		return false
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(
			Vector2(cell.x + 0.5, cell.y + 0.5)) > 6.0:
		return false
	open_mimic(st, pid)
	return true

# host-side guest verb helpers: the ghost's witnessed position is the only
# honest reach a client has — everything else they send is a claim
func _ghost_at(pid: int) -> Vector2:
	var gp = net.ghosts.get(pid) if net != null else null
	return Vector2(gp.net_pos.x, gp.net_pos.y) if gp != null else Vector2(-1e9, -1e9)

func _ghost_reaches(pid: int, at: Vector2, reach := 6.0) -> bool:
	return _ghost_at(pid).distance_to(at) <= reach

func _nearest_struct(sid: String, at: Vector2, reach := 4.0) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := reach
	for k in structures:
		var st: Dictionary = structures[k]
		if st["id"] != sid or k != st.get("pos"):
			continue
		var d: float = at.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if d < bd:
			bd = d; best = k
	return best

# host-side guest fertilize: ghost proximity is the honest reach — the
# guest's own bag pays on the fert_done echo, never up front
func fert_req_remote(pid: int) -> bool:
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null:
		return false
	var best := Vector2i(-1, -1)
	var bd := 4.0
	for k in structures:
		var st: Dictionary = structures[k]
		if k != st.get("pos"):
			continue
		if not StructureData.STRUCTURES.get(st["id"], {}).get("farmField", false):
			continue
		var d: float = Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if d < bd:
			bd = d; best = k
	if best.x < 0:
		return false
	structures[best]["fert"] = t + 300.0
	return true

# the shrine takes any keeper's offering — one altar's mood is everyone's
# sky, and the cooldown is global so a guest can't out-pray the host
func shrine_req_remote(pid: int) -> bool:
	var at := _ghost_at(pid)
	if at.x < -1e8 or t < pray_cd \
			or _nearest_struct("weather_shrine", at).x < 0:
		return false
	var nxt: String = {"clear": "rain", "rain": "storm", "storm": "drought",
		"drought": "clear"}.get(weather, "rain")
	weather = nxt
	weather_t = 0.0
	pray_cd = t + 600.0
	return true

# the stand's pace is shared base policy — a guest at the dial can set it
func work_req_remote(pid: int) -> int:
	var at := _ghost_at(pid)
	if at.x < -1e8 or _nearest_struct("monitoring_stand", at).x < 0:
		return -1
	work_mode = (work_mode + 1) % WORK_MODES.size()
	return work_mode

# one keeper's bed turns everyone's clock — hostiles veto it for all, and
# you still have to be AT a bed: remote napping is a heal exploit
func sleep_req_remote(pid: int) -> bool:
	var at := _ghost_at(pid)
	if at.x < -1e8 or _nearest_struct("straw_bed", at, 3.0).x < 0:
		return false # ~the host's own interact reach — no remote napping from mid-yard
	if not is_night(): # a guest nap skips only the dangerous hours — the
		return false    # self-limiting gate: one sleep rolls dawn to 6am
	for q in pals:
		if q.hp > 0 and (q.raid or (q.mode == "wild" and q.aggro >= 0)):
			return false
	sleep_to_morning()
	return true

# a bone-heap is one dig for whoever reaches it first — same one-shot rule
func dig_req_remote(pid: int, cell: Vector2i) -> bool:
	var st = structures.get(cell)
	if st == null or st["id"] != "fossil_bed" \
			or not _ghost_reaches(pid, Vector2(cell.x + 0.5, cell.y + 0.5)):
		return false
	net_remove_structure(st)
	give_remote(pid, "ancient_part", rng.int_range(2, 4))
	give_remote(pid, "stone", 4)
	if rng.chance(0.25):
		give_remote(pid, "lumenite", 1)
	return true

# the lock opens for whoever prizes it — the freed kin joins THEIR slice
# of the shared kinbox, owner_tagged like a catch
func cage_req_remote(pid: int, cell: Vector2i) -> bool:
	var st = structures.get(cell)
	if st == null or st["id"] != "kin_cage" \
			or not _ghost_reaches(pid, Vector2(cell.x + 0.5, cell.y + 0.5)):
		return false
	var cap = st.get("captive")
	if not (cap is Dictionary) or str(cap.get("sp", "")) == "":
		note_remote(pid, "The cage is empty")
		return false
	if box.size() >= MAX_BOX:
		note_remote(pid, "Kinbox is full — the captive won't leave its cage")
		return false
	if not ownable(str(cap["sp"])):
		note_remote(pid, "The cage holds something that can't be kept")
		return false # the ownable gate — same rule as the local verb
	var bp := gen_pal(str(cap["sp"]), int(cap["lv"]), Vector2(cell.x + 0.5, cell.y + 0.5))
	bp.mode = "box"
	bp.owner_id = pid
	bp.owner_tag = str(net.peer_tags.get(pid, "")) if net != null else ""
	box.append(bp)
	box_pal(bp)
	note_remote(pid, "Freed %s Lv%d — it scurries into your kinbox",
		[bp.spec["name"], bp.level])
	net_remove_structure(st)
	return true

# the board is one shared posting — guests see it via env_sync, claim it
# here, and pay their own goods on the board_done echo
func board_action_remote(pid: int) -> Dictionary:
	var bpos := _ghost_at(pid)
	if bpos.x < -1e8 or _nearest_struct("notice_board", bpos, 6.0).x < 0:
		return {} # the posting is read AT the board — remote claiming is forgery
	if int(board_quest.get("day", -1)) != day:
		if rng.chance(0.5): # half the mornings want goods, half want thinning
			var pick: Array = BOARD_POOL[rng.int_range(0, BOARD_POOL.size() - 1)]
			board_quest = {"kind": "supply", "id": pick[0], "n": pick[1], "day": day}
		else:
			board_quest = {"kind": "hunt", "sp": HUNT_POOL[rng.int_range(0, HUNT_POOL.size() - 1)],
				"n": rng.int_range(2, 4), "got": 0, "day": day}
	var qk: String = str(board_quest.get("kind", "supply"))
	if qk == "hunt":
		var sname: String = str(SpeciesData.species_of(board_quest["sp"]).get("name", board_quest["sp"]))
		note_remote(pid, "Notice board: cull %d %s (%d/%d) — kill or capture counts",
			[int(board_quest["n"]), sname, int(board_quest.get("got", 0)), int(board_quest["n"])])
		return {}
	var qid: String = str(board_quest.get("id", ""))
	if qid == "":
		note_remote(pid, "Notice board: today's request is filled — come back at dawn")
		return {}
	# a claim is a 15s hold, not a burn — the goods only settle on board_paid,
	# so a guest who never pays can't torch the day's posting for everyone
	var qn: int = int(board_quest["n"])
	var gold: int = qn * maxi(2, int(ItemData.ITEMS.get(qid, {}).get("price", 2)))
	var pend = board_quest.get("pending")
	if pend is Dictionary:
		var pt: float = float(pend.get("t", 0.0))
		if pt + 15.0 > t:
			if int(pend.get("pid", -1)) != pid:
				note_remote(pid, "Notice board: someone's filling it — give it a moment")
				return {}
			return {"id": qid, "n": qn, "gold": gold} # the same asker re-reading its hold — never a fresh 15s
		if int(pend.get("pid", -1)) == pid and pt + 45.0 > t:
			# an expired hold cools off for 30s — re-claiming on the dot can't
			# starve every other keeper off the daily posting
			note_remote(pid, "Notice board: give another keeper a turn")
			return {}
	board_quest["pending"] = {"pid": pid, "t": t, "id": qid}
	return {"id": qid, "n": qn, "gold": gold}

func board_release_remote(pid: int, qid: String) -> void:
	# an honest "can't pay" frees the board early — the alternative is a broke
	# asker squatting the whole 15s window for nothing
	var pend = board_quest.get("pending")
	if pend is Dictionary and int(pend.get("pid", -1)) == pid \
			and str(pend.get("id", "")) == qid:
		board_quest.erase("pending")

func board_paid_remote(pid: int, qid: String) -> Dictionary:
	# the hold's freshness gate lives on the CLAIM side — the holder settles
	# whenever its goods reach us (a new claimer overwriting `pending` is the
	# only real expiry). The goods themselves ride the same bag-trust lane as
	# every other client inventory.
	var pend = board_quest.get("pending")
	if not (pend is Dictionary) or int(pend.get("pid", -1)) != pid \
			or str(pend.get("id", "")) != qid:
		return {}
	var qn: int = int(board_quest["n"])
	var gold: int = qn * maxi(2, int(ItemData.ITEMS.get(qid, {}).get("price", 2)))
	board_quest["id"] = "" # paid — the board stays quiet until tomorrow
	board_quest.erase("pending")
	return {"gold": gold, "xp": qn * 3} # same bounty math the local fill pays

# remote condense: same fodder rule, filtered to the asker's own slice —
# heart-locked and other keepers' kin are never fuel
# a guest's mount handoff: host binds a roster kin to their ghost — the kin
# stays host truth but its position rides the ghost's (pal_state_pack lane).
# One saddle, one steed: a new pick frees the old mount automatically.
func mount_req_remote(pid: int, uid: int) -> int: # 0 refuse / 1 mount / 2 dismount
	var at := _ghost_at(pid)
	if at.x < -1e8:
		return 0
	for p in pals:
		if p.owner_id == pid and p.mounted_by == pid:
			if p.uid == uid:
				_unbind_mount(p)
				return 2 # same kin = dismount toggle
	for p2 in pals:
		if p2.uid == uid:
			if p2.owner_id != pid or p2.mode != "partner" or not (p2.uid in rparty_for(pid)):
				return 0 # only your own roster carries you
			if p2.mounted_by != 0 or p2.hp <= 0:
				return 0
			if at.distance_to(p2.pos) > 6.0:
				note_remote(pid, "Too far to mount")
				return 0
			if not SpeciesData.mountable(p2.species_id) and SpeciesData.body_of(p2.species_id) != "bird":
				note_remote(pid, "%s won't carry a rider", [p2.spec["name"]])
				return 0
			# validate first, unbind second — a refused swap can't orphan the
			# saddle: the old mount stays claimed until the new one passes
			for p3 in pals:
				if p3.owner_id == pid and p3.mounted_by == pid:
					_unbind_mount(p3)
			p2.mounted_by = pid
			p2.visible = false
			p2.pos = at
			return 1
	return 0

func condense_remote(pid: int) -> bool:
	var at := _ghost_at(pid)
	if at.x < -1e8 or _nearest_struct("kin_condenser", at, 6.0).x < 0:
		return false # the machine does the melding — remote starring is forgery
	var rp := rparty_for(pid)
	if rp.is_empty():
		note_remote(pid, "No active kin to condense")
		return false
	var ap: Kin = null
	for p in pals:
		if p.uid == int(rp[0]) and p.owner_id == pid:
			ap = p
			break
	if ap == null:
		return false
	if ap.star >= CONDENSE_COST.size():
		note_remote(pid, "%s is already max star", [ap.spec["name"]])
		return false
	var need: int = CONDENSE_COST[ap.star]
	var fodder: Array = []
	for bp in box:
		if bp.species_id == ap.species_id and bp.uid != ap.uid and not bp.fav \
				and bp.owner_id == pid:
			fodder.append(bp)
	fodder.sort_custom(func(a, b): return a.level < b.level)
	if fodder.size() < need:
		note_remote(pid, "Need %d same-species kin for star %d (have %d)",
			[need, ap.star + 1, fodder.size()])
		return false
	for i in need:
		var fp: Kin = fodder[i]
		box.erase(fp)
		fp.free() # already erased — free() on the in-tree node is legal and immediate
	ap.condense()
	note_remote(pid, "%s condensed to star %d!", [ap.spec["name"], ap.star])
	return true

var _reach_seed := -1
var _reach_set := {}

func poi_reach() -> Dictionary:
	# cells walkable from spawn under the REAL movement predicate — elevation
	# steps included. Campaign POIs must land reachable or a cliff-locked
	# plateau can wall the run before grapple/birds exist (audit-42 MED).
	# Computed once per world seed — call it BEFORE POI side effects write
	# structures, and it reflects natural terrain only.
	if _reach_seed == world.seed and not _reach_set.is_empty():
		return _reach_set
	_reach_seed = world.seed
	_reach_set = {}
	var q: Array = [world.spawn]
	_reach_set[world.spawn] = true
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d4 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d4
			if _reach_set.has(n):
				continue
			# player reach = walk ∪ swim — can_enter lets a bare swimmer
			# cross water, so a zone locked behind a strait is still in
			# the campaign set (glider/grapple/mounts stay gear-gated)
			if world.blocked(n.x, n.y, float(c.x), float(c.y)) \
					and not world.swim_open(n.x, n.y):
				continue
			_reach_set[n] = true
			q.append(n)
	return _reach_set

func spawn_lairs() -> void:
	# Zone-3 boss lairs: torch ring + an Alpha guarding elite guards
	var placed := 0
	var tries := 0
	poi_reach() # natural-terrain walk-set — computed before any POI writes
	# the pool is position-independent — compute once. An EMPTY pool must
	# skip the lair loop, never return: the whole campaign-POI tail
	# (den/grotto/spires/nests/waypoints) is called below (audit-42)
	var lair_pool := acq_pool(SpeciesGen.zone_pool(3))
	if lair_pool.is_empty():
		lair_pool = acq_pool(SpeciesGen.zone_pool(2))
	while placed < 3 and tries < 6000 and not lair_pool.is_empty():
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
		if not poi_reach().has(Vector2i(tx, ty)):
			ok = false # a boss arena on a sealed plateau walls the run (audit-42)
		if not ok:
			continue
		# torch ring (8 cells around a 5x5 clearing)
		for c in [Vector2i(tx-2,ty-2),Vector2i(tx+2,ty-2),Vector2i(tx-2,ty+2),Vector2i(tx+2,ty+2)]:
			place_free("torch", c.x, c.y)
		# alpha boss at center — alphas are catchable, so the pool is too
		var sid: String = lair_pool[rng.int_range(0, lair_pool.size() - 1)]
		var bp := preload("res://src/kin.gd").new()
		entity_layer.add_child(bp)
		bp.alpha = true # before setup: apply_bonuses folds the 4x into max_hp
		bp.setup(self, sid, rng.int_range(30, 40), Vector2(tx + 0.5, ty + 0.5))
		pals.append(bp)
		# 2 elite guards
		for i in 2:
			var gsid: String = lair_pool[rng.int_range(0, lair_pool.size() - 1)]
			var gp := preload("res://src/kin.gd").new()
			entity_layer.add_child(gp)
			gp.setup(self, gsid, rng.int_range(18, 26), Vector2(tx + 0.5 + (1 if i == 0 else -1), ty + 0.5))
			pals.append(gp)
		# the island den treasure: a stocked chest sits behind the boss —
		# flagged "loot" so base haulers never trek out to rob their own prize
		var ck := Vector2i(tx, ty + 1)
		if place_free("chest", ck.x, ck.y):
			var chst: Dictionary = structures.get(ck)
			if chst != null:
				chst["loot"] = true
				var loot := {"gold_coin": rng.int_range(30, 80), "lumenite": rng.int_range(2, 5)}
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
	spawn_pact_spires()
	spawn_nests()
	spawn_waypoints()
	log_msg(tr("%d boss lairs marked deep in the world") % placed)

func spawn_waypoints() -> void:
	# a fast-travel stones: a few fixed waypoints out in the world,
	# each a one-way blink back to your kinbox once you've walked out
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
		log_msg(tr("%d waypoints hum out in the wilds") % placed)

func spawn_nests() -> void:
	# Wild egg nests (the island): stealable kin_egg drops scattered past zone 1
	var placed := 0
	var tries := 0
	while placed < 7 and tries < 4000:
		tries += 1
		var tx := rng.int_range(4, World.WORLD_W - 5)
		var ty := rng.int_range(4, World.WORLD_H - 5)
		var at := Vector2(tx + 0.5, ty + 0.5)
		var zone := world.zone_at(tx, ty)
		if zone < 1 or world.blocked(tx, ty) \
				or at.distance_to(player.pos) < 15.0:
			continue
		# deeper nests hide the odd huge egg — golden goose chase
		spawn_drop("huge_kin_egg" if rng.chance(0.05 + zone * 0.05) else "kin_egg", 1, at)
		placed += 1

var grotto_pos := Vector2i(-1, -1) # sealed dungeon marker (set at worldgen)
var grotto_room2 := Vector2i(-1, -1) # second chamber center, if the terrain fit it

func spawn_grotto() -> void:
	# the island dungeon flavour: a rock-sealed chamber in deep zone 3 — the only
	# way in is to break the wall — birds can't perch on rock either. Boss + loot inside.
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
		if not poi_reach().has(Vector2i(tx, ty)):
			ok = false # the door cell must be walkable before the seal (audit-42)
		if not ok:
			continue
		# the warden: a zone-3 alpha boss, orb-immune like all dungeon bosses.
		# Check the pool BEFORE sealing the ring — an empty chamber behind
		# unbreakable-looking rock is a lie on the minimap (audit-42)
		var pool := SpeciesGen.zone_pool(3)
		if pool.is_empty():
			return
		# seal the chamber: a rock ring the player has to crack open
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dy)) == 3:
					var i2 := world.idx(tx + dx, ty + dy)
					world.decor[i2] = World.Decor.ROCK
					world.hp[i2] = 60
		var bp := preload("res://src/kin.gd").new()
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
			if rng.chance(0.12): # some chests are only chest-shaped
				st["mimic"] = ["shadelump", "shademelt", "shademite"][rng.int_range(0, 2)]
			else:
				st["store"] = {"gold_coin": rng.int_range(20, 40), "mega_orb": 3,
					"kin_egg": 1, "skill_fruit_" + ["neutral", "fire", "water", "grass",
					"electric", "ice", "ground", "dark", "dragon"][rng.int_range(0, 8)]: 1}
		grotto_pos = Vector2i(tx, ty)
		grotto_room2 = Vector2i(-1, -1)
		# second chamber (the island multi-room dungeon): a 5x5 treasure room in
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
			log_msg(tr("A sealed grotto echoes in the deep wilds"))
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
		var bp2 := preload("res://src/kin.gd").new()
		bp2.alpha = true
		bp2.boss = true
		entity_layer.add_child(bp2)
		bp2.setup(self, pool[rng.int_range(0, pool.size() - 1)], 45, Vector2(bx + 0.5, by + 0.5))
		bp2.home = bp2.pos
		pals.append(bp2)
		if place_free("chest", bx - 1, by - 1):
			var st2: Dictionary = structures[Vector2i(bx - 1, by - 1)]
			st2["loot"] = true
			if rng.chance(0.15): # deeper rooms hold deeper appetites
				st2["mimic"] = ["shadelump", "noctmane"][rng.int_range(0, 1)]
			else:
				st2["store"] = {"gold_coin": rng.int_range(40, 80), "legendary_orb": 2,
					"sprigmelt_effigy": 3, "kin_egg": 2, "huge_kin_egg": 1}
		grotto_room2 = Vector2i(bx, by)
		# third chamber (deepest boss room): chains off room 2 in any
		# cardinal direction that won't double back onto the first chamber.
		var cx3 := -1
		var cy3 := -1
		var door3 := Vector2i.ZERO
		for dir3: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var rx: int = bx + dir3.x * 7
			var ry: int = by + dir3.y * 7
			if rx == tx and ry == ty:
				continue # that's just the way we came
			if rx - 3 < 0 or rx + 3 >= World.WORLD_W or ry - 3 < 0 or ry + 3 >= World.WORLD_H:
				continue
			var fits3 := true
			for dy3 in range(-1, 2):
				for dx3 in range(-1, 2):
					if world.blocked(rx + dx3, ry + dy3) or structures.has(Vector2i(rx + dx3, ry + dy3)):
						fits3 = false
			if fits3:
				cx3 = rx; cy3 = ry
				door3 = Vector2i(bx + dir3.x * 4, by + dir3.y * 4)
				break
		if cx3 >= 0:
			for dy3 in range(-2, 3):
				for dx3 in range(-2, 3):
					if maxi(absi(dx3), absi(dy3)) == 2:
						var j3 := world.idx(cx3 + dx3, cy3 + dy3)
						world.decor[j3] = World.Decor.ROCK
						world.hp[j3] = 60
			var horiz3 := door3.y == by
			for off3 in [-1, 1]:
				var dc3 := door3 + (Vector2i(0, off3) if horiz3 else Vector2i(off3, 0))
				var k3 := world.idx(dc3.x, dc3.y)
				world.decor[k3] = World.Decor.ROCK
				world.hp[k3] = 60
			var bp3 := preload("res://src/kin.gd").new()
			bp3.alpha = true
			bp3.boss = true
			entity_layer.add_child(bp3)
			# the deepest room deserves legendary stock, not just any zone-3 thug
			bp3.setup(self, LEGENDARY_DEN[rng.int_range(0, LEGENDARY_DEN.size() - 1)],
				50, Vector2(cx3 + 0.5, cy3 + 0.5))
			bp3.home = bp3.pos
			pals.append(bp3)
			if place_free("chest", cx3 + 1, cy3 - 1):
				var st3: Dictionary = structures[Vector2i(cx3 + 1, cy3 - 1)]
				st3["loot"] = true
				if rng.chance(0.15):
					st3["mimic"] = ["noctmane", "shademelt", "shadelump"][rng.int_range(0, 2)]
				else:
					st3["store"] = {"gold_coin": rng.int_range(60, 120), "legendary_orb": 3,
						"ancient_part": 2, "huge_kin_egg": 1, "sprigmelt_effigy": 4,
						"boss_sigil": 1,
						"skill_fruit_" + ["neutral", "fire", "water", "grass", "electric",
						"ice", "ground", "dark", "dragon"][rng.int_range(0, 8)]: 1}
			log_msg(tr("A sealed grotto echoes in the deep wilds — something huge breathes within"))
			return
		log_msg(tr("A sealed grotto echoes in the deep wilds — it sounds deep"))
		return

# World bosses that only appear as den guardians — legendary tier.
const LEGENDARY_DEN := ["scalbeak", "snovstride", "nibhand", "shadekin",
	"wyrmhoof", "cindchew", "flarbeak", "tidscale", "scalcrest", "vermtrot"]

# The Pact spires: five element shrines seeded through the island's bands —
# break every guardian and the island crowns you. The campaign's spine: each
# one is an orb-immune boss that phases at half health.
const SPIRE_DEFS := [
	{"elem": "fire", "lv": 25, "zone": 1},
	{"elem": "water", "lv": 30, "zone": 2},
	{"elem": "grass", "lv": 35, "zone": 2},
	{"elem": "dark", "lv": 42, "zone": 3},
	{"elem": "dragon", "lv": 50, "zone": 3},
]
var spires_done := {} # tag -> true — persists with the save
var spire_pos := {}   # tag -> Vector2i arena center — minimap pings (bounded by spire_tag_ok to SPIRE_DEFS.size() entries; worldgen-deterministic,
                      # but serialized anyway so a mid-run schema bump can't lose the trail)
var crowned := false
var has_save := false # cached file_exists for the title row — no per-frame stat syscall

func spire_pick(elem: String) -> String:
	# a guardian that matches the shrine's element; the dragon spire deserves
	# legendary stock — every spire boss is orb-immune regardless of species
	var pool := []
	for s in SpeciesData.SPECIES.keys() + SpeciesGen.SPECIES.keys():
		# a spire boss must be a beast — no ironpact in a robe
		if elem in SpeciesData.species_of(str(s)).get("elements", []) and SpeciesData.body_of(str(s)) != "human":
			pool.append(str(s))
	if elem == "dragon":
		var legs := pool.filter(func(s): return s in LEGENDARY_DEN)
		if not legs.is_empty():
			pool = legs
	if pool.is_empty():
		pool = LEGENDARY_DEN.duplicate()
	return str(pool[rng.int_range(0, pool.size() - 1)])

func spawn_pact_spires() -> void:
	var placed := 0
	# each spire gets its own strict→relaxed attempt — one stubborn index must
	# never block the rest: five spires is a campaign contract
	for si in SPIRE_DEFS.size():
		var sd: Dictionary = SPIRE_DEFS[si]
		for relaxed in [false, true]:
			var done := false
			var tries := 0
			while tries < 8000 and not done:
				tries += 1
				var tx := rng.int_range(8, World.WORLD_W - 10)
				var ty := rng.int_range(8, World.WORLD_H - 10)
				if world.zone_at(tx, ty) != int(sd["zone"]):
					continue
				# relaxed still insists the arena floor itself is standable —
				# a guardian ringing itself inside rock is unreachable
				if world.blocked(tx, ty) or structures.has(Vector2i(tx, ty)):
					continue
				var ok := true
				if not relaxed:
					for dy in range(-3, 4):
						for dx in range(-3, 4):
							if world.blocked(tx + dx, ty + dy) or structures.has(Vector2i(tx + dx, ty + dy)):
								ok = false
				# the south door must open onto ground you can walk in on —
				# the door cell itself AND the approach must pass the real
				# movement predicate (elevation step included)
				if world.blocked(tx, ty + 2, tx + 0.5, ty + 1.5) \
						or world.blocked(tx, ty + 3, tx + 0.5, ty + 2.5):
					ok = false
				if not poi_reach().has(Vector2i(tx, ty + 3)):
					ok = false # coherent door ≠ connected door — a spire on a
					# sealed plateau can't be reached on foot (audit-42)
				if not ok:
					continue
				_place_spire(sd, tx, ty, si)
				placed += 1
				done = true
			if done:
				break
	# last resort: a spire that survived strict AND relaxed still owes the
	# campaign a body — any free standable cell with a real door approach
	# takes it, zone be damned. A missing spire is an uncompletable save;
	# an off-biome one is a story, and a cliff-locked one is the same lie.
	for si in SPIRE_DEFS.size():
		if spire_pos.has("spire_%d" % si):
			continue
		var sd2: Dictionary = SPIRE_DEFS[si]
		var done2 := false
		var tries2 := 0
		while tries2 < 20000 and not done2:
			tries2 += 1
			var tx2 := rng.int_range(4, World.WORLD_W - 6)
			var ty2 := rng.int_range(4, World.WORLD_H - 6)
			if world.blocked(tx2, ty2) or structures.has(Vector2i(tx2, ty2)):
				continue
			if world.blocked(tx2, ty2 + 2, tx2 + 0.5, ty2 + 1.5) \
					or world.blocked(tx2, ty2 + 3, tx2 + 0.5, ty2 + 2.5):
				continue
			if not poi_reach().has(Vector2i(tx2, ty2 + 3)):
				continue # even the last resort owes the campaign a real door —
				# a cliff-locked spire is the same lie as a missing one
			_place_spire(sd2, tx2, ty2, si)
			done2 = true
			placed += 1
			log_msg(tr("A stray spire rose off its biomes — the pact doesn't read maps"))
	if placed < SPIRE_DEFS.size():
		push_warning("only %d of %d pact spires placed — campaign uncompletable on this map" % [placed, SPIRE_DEFS.size()])
		log_msg(tr("Only %d pact spires stand — the island is broken; tell the dev") % placed)
	if placed > 0:
		log_msg(tr("The Iron Pact raised %d spires across the Wildmere — break them all") % placed)

func _place_spire(sd: Dictionary, tx: int, ty: int, placed: int) -> void:
	# rock ring, door facing south — a proper arena, not a field bump
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2 and not (dy == 2 and dx == 0):
				var j := world.idx(tx + dx, ty + dy)
				if world.tiles[j] == World.Tile.WATER \
						or structures.has(Vector2i(tx + dx, ty + dy)):
					continue # the ring can't drown a lake or eat another POI —
					# relaxed/last-resort paths don't pre-verify the rim (audit-42)
				world.decor[j] = World.Decor.ROCK
				world.hp[j] = 60
	var bp := preload("res://src/kin.gd").new()
	bp.boss = true
	bp.alpha = true
	entity_layer.add_child(bp)
	bp.setup(self, spire_pick(str(sd["elem"])), int(sd["lv"]), Vector2(tx + 0.5, ty + 0.5))
	bp.home = bp.pos
	bp.spire_tag = "spire_%d" % placed
	spire_pos[bp.spire_tag] = Vector2i(tx, ty) # the campaign spine earns a map ping
	bp.sprite.scale = Vector2(1.9, 1.9)
	pals.append(bp)
	if place_free("chest", tx - 1, ty - 1):
		var st: Dictionary = structures[Vector2i(tx - 1, ty - 1)]
		st["loot"] = true
		st["store"] = {"gold_coin": 30 + placed * 15, "legendary_orb": 1,
			"ancient_part": 1 + placed}
	else:
		push_warning("spire_%d chest didn't fit — the guardian stands but its tribute is gone" % placed)

func spire_tag_ok(s: String) -> bool:
	# one validator for every reader (save/wire/kill paths): "spire_" + a REAL
	# non-negative int inside the defs table. int() eats "abc"→0 and "-1"→-1 —
	# both forged spire_0 tags without this three-part check
	if not s.begins_with("spire_"):
		return false
	var rest := s.trim_prefix("spire_")
	return rest.is_valid_int() and int(rest) >= 0 and int(rest) < SPIRE_DEFS.size()

func record_spire(tag: String) -> void:
	if not spire_tag_ok(tag):
		return # a crown must never be minted from a forged tag — every
		# writer validates, and the choke point re-checks regardless
	if spires_done.has(tag):
		return # a ruin pays its sigil once — a doubled kill call can't mint two
	spires_done[tag] = true
	var n := spires_done.size()
	log_msg(tr("Pact spire broken! %d of %d") % [n, SPIRE_DEFS.size()])
	# the tower yields its dare: a broken spire is the gauntlet's first source —
	# without this the sigil only ever paid inside its own reward loop
	add_item("gauntlet_sigil", 1)
	log_msg(tr("The tower's sigil is yours — sound it for the gauntlet"))
	if n >= SPIRE_DEFS.size() and not crowned:
		crowned = true
		add_item("legendary_orb", 3)
		add_item("gold_coin", 300)
		add_item("ancient_part", 10)
		log_msg(tr("ISLAND CROWNED — every spire lies broken. The Wildmere is yours."))
		if player != null:
			floater(player.pos, tr("ISLAND CROWNED"), "#ffd76e")

func spawn_legendary_den() -> void:
	# one per world: bigger ring, an orb-immune giant, elite honour guard.
	# The FIRST warden is a kill-fight — its successor respawns catchable
	# (tick_boss_respawns legend branch), and catching that one re-arms the
	# den: the ten-name collection loop runs on this one site
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
		if not poi_reach().has(Vector2i(tx, ty)):
			ok = false # the heir's arena must be walkable-in (audit-42)
		if not ok:
			continue
		var pool := LEGENDARY_DEN.filter(func(s): return not SpeciesGen.SPECIES.get(s, {}).is_empty())
		if pool.is_empty():
			return # species data trimmed — skip the den rather than spawn a
			# ghost. Checked BEFORE the torch ring: an heir-less ring is just
			# debris on the map (audit-42)
		for c in [Vector2i(tx-3,ty-3),Vector2i(tx+3,ty-3),Vector2i(tx-3,ty+3),Vector2i(tx+3,ty+3),
				Vector2i(tx,ty-3),Vector2i(tx,ty+3),Vector2i(tx-3,ty),Vector2i(tx+3,ty)]:
			place_free("torch", c.x, c.y)
		var sid: String = pool[rng.int_range(0, pool.size() - 1)]
		var bp := preload("res://src/kin.gd").new()
		bp.alpha = true
		bp.boss = true # the warden itself is IMMUNE — its re-den'd heir is not
		entity_layer.add_child(bp)
		bp.setup(self, sid, 50, Vector2(tx + 0.5, ty + 0.5))
		bp.sprite.scale = Vector2(2.5, 2.5)
		bp.sprite.position.y = -78.0
		bp.home = bp.pos
		pals.append(bp)
		var guard_pool := acq_pool(SpeciesGen.zone_pool(3))
		for i in mini(3, guard_pool.size()):
			var gp := preload("res://src/kin.gd").new()
			entity_layer.add_child(gp)
			gp.setup(self, guard_pool[rng.int_range(0, guard_pool.size() - 1)],
				rng.int_range(24, 32), Vector2(tx + 1.5 - i, ty + 1.5))
			pals.append(gp)
		log_msg(tr("A legendary %s den glows deep in the wilds") % tr(str(SpeciesData.species_of(sid).get("name", sid))))
		return

func regenerate(s: int) -> void:
	_reset_shell_state() # a swapped world can't keep the old one's open panels
	for p in pals:
		if is_instance_valid(p):
			p.queue_free()
	pals.clear()
	party.clear()
	for bp0 in box: # box pals live under box_holder — in-tree, so queue_free
		bp0.queue_free()
	for bb0 in bench: # orbs live under box_holder — queue_free from the parent
		bb0.queue_free()
	bench.clear()
	box.clear()
	for k in structures:
		if is_instance_valid(structures[k]["node"]):
			structures[k]["node"].queue_free()
	structures.clear()
	_struct_gen += 1
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
	for sp0 in spheres_flying: # in-flight orbs: sprite + stale target would linger
		if is_instance_valid(sp0["node"]):
			sp0["node"].queue_free()
	spheres_flying.clear()
	kinbox_pos = Vector2i(-1, -1)
	extra_boxes.clear() # outpost network dies with the world
	grotto_pos = Vector2i(-1, -1)
	grotto_room2 = Vector2i(-1, -1)
	boss_respawns.clear() # the old world's dens died with it
	spires_done.clear() # a fresh island raises fresh spires
	spire_pos.clear() # and fresh markers for them
	crowned = false
	accord = false # a new island owes nobody its last contract
	gauntlet = {} # and so did any trial in progress
	remote_parties.clear() # guest rosters describe the old world's kin
	clear_net_drops()
	craft_queue.clear() # queued builds die with the world too
	mission_idx = 0 # missions belong to the world they were earned in
	mission_flags.clear()
	dex_seen.clear()
	dex_claimed = 0 # a fresh world hasn't proven its ecology yet
	dex_full = false
	weather = "clear"
	weather_t = 0.0
	pray_cd = 0.0
	explored.clear() # a fresh world is unexplored from edge to edge
	explored.resize(world.WORLD_W * world.WORLD_H)
	explored_n = 0
	work_mode = 1
	mission_t = 0.0
	stat_pts = 0 # level bank restarts with a new character
	dirty_decor.clear() # deltas from the old world must not reach the next session
	player.mount = null # the pal it pointed at is gone — don't chase a freed object
	lure = {}; treasure = {}; board_quest = {} # tossed bait, marked charts and old postings belong to the old world
	hint_seen.clear() # a new island earns its nudges again
	focus_target = null # a dangling Kin ref into the old world
	death_marks.clear() # tombstones mark this island's falls, not the last one's
	raid_warned = false; raid_theme = ""; raid_t = 180.0 # no horn or countdown survives — the clock re-arms, not fires
	catch_counts.clear(); catch_streak = 0 # fresh world, fresh ten-streak math
	player.statuses.clear() # the old world's burns don't carry over
	despawn_merchant() # new world, new route — the trader doesn't follow
	merchant_deaths = 0 # a new keeper hasn't wronged the Pact yet
	world.generate(s)
	drawer.setup(world)
	queue_redraw_decor() # the decor pool is keyed by cell — old-world sprites must be rebuilt
	player.pos = Vector2(world.spawn) + Vector2(0.5, 0.5)
	player.sync_screen()
	# POI placement rolls off the world seed — a joining client lands the same
	# spires/lairs/decor as the host instead of phantom walls it can't see
	var rsav := rng.s
	rng.s = (s ^ 0x9E3779B9) & 0xFFFFFFFF
	place_pois()
	rng.s = rsav # gameplay rolls resume from the session stream

# POI placement lane — boot (_ready) and join/regen (regenerate) share this so
# every peer derives the same spires/lairs/decor from world.seed. Order is
# contract: the seeded rng stream assigns each roll in sequence.
func place_pois() -> void:
	spawn_lairs()
	spawn_camps() # Iron Pact poacher camps — guards spawn locally like lair bosses
	spawn_fossils() # old bones re-spawned with the world
	spawn_wild(true) # after player.pos so the no-spawn radius is measured from the new point

# ---------- effigy statues ----------
const PERK_COST := 2
var stat_pts := 0 # level-up banked points — the statue spends these before effigies
func upgrade_perk(k: String) -> void:
	var lvl: int = perks[k]
	if lvl >= 5:
		log_msg(tr("Statue maxed"))
		return
	var cost := PERK_COST + lvl * 2
	if stat_pts > 0:
		stat_pts -= 1
	elif item_count("sprigmelt_effigy") >= cost:
		add_item("sprigmelt_effigy", -cost)
	else:
		log_msg(tr("Need %d effigies or a stat point (have %d)") % [cost, item_count("sprigmelt_effigy")])
		return
	perks[k] = lvl + 1
	if k == "capture":
		player.capture_level = 1 + perks["capture"] # keep the stat in sync
	if k == "hp":
		player.max_hp = 100 + (player.level - 1) * 10 + perks["hp"] * 12 # level hp + perk hp
		player.hp = player.max_hp
	log_msg(tr("Statue upgraded: %s Lv%d") % [tr(str(PERK_LABEL.get(k, k))), perks[k]])

func respec() -> bool:
	# memory-wiping medicine: every perk rank folds back into
	# stat points — spend them fresh, no effigies refunded
	var total := 0
	for k in perks:
		total += int(perks[k])
	if total == 0:
		log_msg(tr("No perks to forget"))
		return false
	for k in perks:
		perks[k] = 0
	stat_pts += total
	player.capture_level = 1 + perks["capture"]
	player.max_hp = 100 + (player.level - 1) * 10 + perks["hp"] * 12
	player.hp = minf(player.hp, player.max_hp) # forgot the hp ranks — max shrank
	log_msg(tr("Memory wiped: %d stat points returned") % total)
	return true

func soul_infuse(uid: int) -> void:
	if client_locked():
		return
	# the island statue-of-power for kin: feed effigies into one kin's soul
	var target: Kin = null
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
	if item_count("sprigmelt_effigy") < cost:
		log_msg(tr("Need %d effigies to infuse %s") % [cost, tr(str(target.spec["name"]))])
		return
	add_item("sprigmelt_effigy", -cost)
	target.soul_boost += 1
	target.apply_bonuses()
	log_msg(tr("%s's soul burns brighter (+%d)") % [tr(str(target.spec["name"])), target.soul_boost])

# host-side guest infusion: the uid must resolve to the ASKER's kin —
# you can't burn effigies into someone else's soul. Cost echoes back.
func infuse_req_remote(pid: int, uid: int) -> int:
	var target: Kin = null
	for q in pals:
		if q.uid == uid and q.owner_id == pid and q.mode in ["partner", "base"]:
			target = q
	for bp in box:
		if bp.uid == uid and bp.owner_id == pid:
			target = bp
	for bb in bench:
		if bb.uid == uid and bb.owner_id == pid:
			target = bb
	if target == null or target.soul_boost >= 10:
		return -1
	var cost := 1 + target.soul_boost
	target.soul_boost += 1
	target.apply_bonuses()
	return cost

# remote skill fruit: a guest teaches their own lead — the host holds the
# roster's truth, the bag pays only on acceptance (same contract as egg_req)
func fruit_req_remote(pid: int, item_id: String) -> bool:
	var gp = net.ghosts.get(pid) if net != null else null
	if gp == null:
		return false
	var it: Dictionary = ItemData.ITEMS.get(item_id, {})
	var elem := str(it.get("elem", ""))
	if not item_id.begins_with("skill_fruit_") or elem == "":
		return false
	var rp := rparty_for(pid)
	if rp.is_empty():
		note_remote(pid, "No active kin to teach")
		return false
	var p: Kin = null
	for q in pals + bench:
		if q.uid == int(rp[0]) and q.owner_id == pid:
			p = q
			break
	if p == null or p.hp <= 0:
		note_remote(pid, "Lead kin is down")
		return false
	var pool := []
	for sid in SkillData.SKILLS:
		var sk: Dictionary = SkillData.SKILLS[sid]
		if sk.get("element", "neutral") == elem and sk.get("power", 0) > 0:
			pool.append(sid)
	pool = pool.filter(func(s): return s not in p.learned_skills())
	if pool.is_empty():
		note_remote(pid, "%s already knows every %s move", [p.spec["name"], elem])
		return false
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	p.extra_skills.append(sid)
	note_remote(pid, "%s learned %s!", [p.spec["name"], SkillData.SKILLS[sid].get("name", sid)])
	floater(p.pos, tr("+ skill!"), "#a8e6a1")
	return true

# the island signature partner skills: a few species get bespoke actives
# instead of "cast your best learned skill at the cursor"
const PARTNER_SKILLS := {
	"cindlump": {"cd": 6.0, "range": 4.5, "name": "Flamethrower"},
	"sprigmelt": {"cd": 5.0, "range": 7.0, "name": "SMG Burst"},
	"briargoo":  {"cd": 5.0, "range": 8.0, "name": "Rifle Shot"},
	# the island ranch-in-the-field supports — no gear, just produce on tap
	"nibjelly":   {"cd": 30.0, "range": 0.0, "name": "Milk Maker"},
	"piplump":{"cd": 30.0, "range": 0.0, "name": "Milk Maker"},
	"fenlump":  {"cd": 25.0, "range": 0.0, "name": "Egg-cellent Lay"},
	"corlmite":{"cd": 8.0, "range": 9.0, "name": "Penguin Cannon"},
	"fenjelly":  {"cd": 20.0, "range": 0.0, "name": "Roly Poly"},
}

# the island kin gear: a bespoke active needs its species item crafted in the
# pack — the harness/SMG/rifle are what make the skill real, not the kin.
const PARTNER_GEAR := {
	"cindlump": "cindlump_harness", "sprigmelt": "sprigmelt_smg", "briargoo": "briargoo_rifle",
	"corlmite": "corlmite_launcher",
}
func partner_gear_ok(sid: String) -> bool:
	var gid: String = PARTNER_GEAR.get(sid, "")
	return gid == "" or item_count(gid) > 0

func partner_skill() -> void:
	if party.is_empty():
		log_msg(tr("No party kin"))
		return
	var p := party_pal()
	if p == null or p.hp <= 0:
		log_msg(tr("Send out a kin first"))
		return
	var m := player.get_global_mouse_position()
	var tw0: Vector2 = Iso.from_screen(m.x, m.y, player.elev())
	if touch_ui: # no cursor under a slab — fire down the facing line (audit-36)
		var fv := player.facing.normalized() if player.facing.length() > 0.01 else Vector2.RIGHT
		tw0 = player.pos + fv * 4.0
	var psk = PARTNER_SKILLS.get(p.species_id)
	if psk != null and not partner_gear_ok(p.species_id):
		log_msg(tr("%s's %s needs its kin gear — unlock %s in the tech tree")
			% [tr(str(p.spec["name"])), tr(str(psk["name"])),
				tr(str(ItemData.ITEMS.get(PARTNER_GEAR[p.species_id], {}).get("name", PARTNER_GEAR[p.species_id])))])
		psk = null # the pal falls back to its strongest learned move instead
	if psk != null:
		if p.skill_cd.get("partner", 0) > t:
			log_msg(tr("%s is reloading") % tr(str(p.spec["name"])))
			return
		if not run_partner_skill(p, tw0, psk):
			log_msg(tr("%s's %s found no target") % [tr(str(p.spec["name"])), tr(str(psk["name"]))])
			return
		p.skill_cd["partner"] = t + float(psk["cd"])
		log_msg(tr("%s: %s!") % [tr(str(p.spec["name"])), tr(str(psk["name"]))])
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
		log_msg(tr("%s has no usable partner skill") % tr(str(p.spec["name"])))
		return
	p.skill_cd[best["id"]] = t + best.get("cooldown", 2)
	cast_skill(p, tw, best)
	log_msg(tr("%s casts %s!") % [tr(str(p.spec["name"])), tr(str(best["name"]))])

func run_partner_skill(p: Kin, tw: Vector2, psk) -> bool:
	# bespoke actives — returns false when nothing in the cone/aim was worth
	# spending the cooldown on, so the button can fall back to a log line
	var reach: float = psk["range"]
	var p_atk := Combat.stat_at(p.spec["atk"], p.level, p.talent) * p.atk_bonus * p.atk_mult()
	# the pal's weapons aim at the click — but the mark must be somewhere the
	# pal could actually shoot: inside its range AND on a clear line, or a
	# sealed arena becomes a free kill-zone through unbroken rock (audit-43)
	if p.species_id in ["cindlump", "sprigmelt", "briargoo", "corlmite"] \
			and (p.pos.distance_to(tw) > reach or not world.los_clear(p.pos, tw)):
		log_msg(tr("%s can't see a line to that mark") % tr(str(p.spec["name"])))
		return false # no cast happened — same verdict an empty cone reports
	match p.species_id:
		"cindlump": # flamethrower: burn everything in the aim cone
			var hit_any := false
			for q in pals:
				if q.mode != "wild" or q.hp <= 0 or q == p:
					continue
				if q.pos.distance_to(tw) <= reach * 0.5 + 0.6 \
						and world.los_clear(p.pos, q.pos): # cover still covers
					q.hit(Combat.damage(p_atk, 45, Combat.stat_at(q.spec["def"],
						q.level, q.talent) * q.def_bonus * q.def_mult(), 1.0, rng), 1.0, true)
					if rng.chance(0.3):
						q.add_status("burn", 3.0)
					hit_any = true
			return hit_any
		"sprigmelt": # SMG burst: three quick hits on the nearest wild pal to the aim
			var tgt := nearest_wild(tw, reach)
			if tgt == null or not world.los_clear(p.pos, tgt.pos):
				return false
			var tdef := Combat.stat_at(tgt.spec["def"], tgt.level, tgt.talent) * tgt.def_bonus * tgt.def_mult()
			for i in 3:
				if tgt.hp <= 0:
					break
				tgt.hit(Combat.damage(p_atk, 15, tdef, 1.0, rng), 1.0, true)
			return true
		"briargoo": # rifle shot: one heavy hit
			var tgt2 := nearest_wild(tw, reach)
			if tgt2 == null or not world.los_clear(p.pos, tgt2.pos):
				return false
			tgt2.hit(Combat.damage(p_atk, 80, Combat.stat_at(tgt2.spec["def"],
				tgt2.level, tgt2.talent) * tgt2.def_bonus * tgt2.def_mult(), 1.0, rng), 1.0, true)
			return true
		"corlmite": # Penguin Cannon: the bird IS the payload — icy splash at the aim
			var boom := false
			for q in pals:
				if q.mode != "wild" or q.hp <= 0 or q == p:
					continue
				if q.pos.distance_to(tw) <= 2.6 \
						and world.los_clear(p.pos, q.pos):
					q.hit(Combat.damage(p_atk, 55, Combat.stat_at(q.spec["def"],
						q.level, q.talent) * q.def_bonus * q.def_mult(), 1.0, rng), 1.0, true)
					if rng.chance(0.35):
						q.add_status("freeze", 2.5)
					boom = true
			if boom:
				floater(tw, tr("PENGUIN CANNON!"), "#7ec8e3")
			return boom
		"nibjelly": # a squeeze of cream, straight into the bag
			add_item("milk", 1)
			floater(p.pos, tr("milk!"), "#f8f4f0")
			return true
		"piplump": # the big jersey — two bottles per squeeze
			add_item("milk", 2)
			floater(p.pos, tr("milk x2!"), "#f8f4f0")
			return true
		"fenjelly": # Roly Poly: the plush ball rolls under you — an 8s absorb bubble
			player.shield_t = t + 8.0
			player.shield_n = 40.0 + p.level * 2.0
			floater(player.pos, tr("ROLY POLY!"), "#a8d8ff")
			return true
		"fenlump": # it lays, you pocket
			add_item("egg", 1)
			floater(p.pos, tr("an egg!"), "#f0e0a8")
			return true
	return false

func nearest_wild(at: Vector2, reach: float) -> Kin:
	var best: Kin = null
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
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 4.0:
		return # fail closed: no registered ghost means no proximity proof — refuse
	harvest_cell(tx, ty)

func net_place(sid: String, tx: int, ty: int, pid: int) -> bool:
	var s: Dictionary = StructureData.STRUCTURES.get(sid, {})
	if s.is_empty() or sid not in unlocked:
		return false # shared tech is host truth — "paid locally" doesn't research
	var gp = net.ghosts.get(pid)
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 9.0:
		return false # fail closed: no ghost, no build — proximity is mandatory
	var seen_st := []
	for k in structures:
		if structures[k] not in seen_st:
			seen_st.append(structures[k])
	if seen_st.size() >= MAX_STRUCTURES:
		return false
	if not can_place(sid, tx, ty): # terrain/footprint/cap rules still hold
		return false
	if place_free(sid, tx, ty): # the client already paid locally
		var st2 = structures.get(Vector2i(tx, ty))
		if st2 != null:
			# the keeper tag, not the pid — pids die with the session, the tag
			# survives a rejoin (same identity model as remote_parties)
			st2["placed_tag"] = str(net.peer_tags.get(pid, ""))
		log_msg(tr("Player %d built %s") % [pid, tr(str(s.get("name", sid)))])
		return true
	return false

func apply_sleep_claim(p: Kin, dur: float) -> void:
	# chain-sleep is cheese: a darted kin resists re-darting for a beat after
	# it wakes — same rule for the keeper's own tranq and the wire's claim
	if p.get_meta("slp_immune", 0.0) > t:
		return
	p.statuses["sleep"] = t + dur
	p.set_meta("slp_immune", t + dur + 5.0)
	floater(p.pos, tr("zzz"), "#9ad8ff")

func orphan_guest_kin(pid: int) -> void:
	# a leaving keeper's roster waits under its tag — same -1 orphan contract
	# load_game uses for foreign pals. Field kin (partner/base) retreat into
	# cold storage: a pal with no keeper doesn't shadow the host or keep
	# eating the pantry — it waits for the tag to walk back in.
	for p in pals.duplicate():
		if is_instance_valid(p) and p.owner_id == pid:
			player.dismount_if(p)
			_unbind_mount(p) # the rider is gone — the kin unbinds with them
			if p.job_site != null:
				p.job_site["workers"].erase(p)
				p.job_site = null
			if p.carry != null:
				# the peer is already gone — give_remote falls back to the host
				# bag, so the cargo survives instead of stasis-vanishing
				give_remote(pid, str(p.carry["id"]), int(p.carry["n"]))
				p.carry = null
			p.visible = true # an expedition pal enters cold-storage daylight
			pals.erase(p)
			p.mode = "box"
			if box.size() < MAX_BOX + 32:
				box.append(p)
				box_pal(p)
			else: # the overflow lane is full too — release it, tag and all
				p.owner_id = -1
				p.owner_tag = ""
				p.queue_free() # still parented under entity_layer — free() is for parentless nodes only (rule 2)
	for coll in [box, bench]:
		for p in coll:
			if is_instance_valid(p) and p.owner_id == pid:
				p.owner_id = -1

func purge_replicas() -> void:
	# severed session: host-owned statue kin (net_id > 0) die with the wire —
	# left behind they'd be locally catchable clone-pals
	for p in pals.duplicate():
		if p.net_id > 0:
			if player.mount == p:
				player.mount = null # a purged replica can't stay saddled — the ref dies before the node does
			pals.erase(p)
			p.queue_free()
	for q in box.duplicate():
		if q.net_id > 0:
			if player.mount == q:
				player.mount = null
			box.erase(q)
			q.queue_free()
	for q2 in bench.duplicate():
		if q2.net_id > 0:
			if player.mount == q2:
				player.mount = null
			bench.erase(q2)
			q2.queue_free()
	remote_parties.clear()

func net_demolish(tx: int, ty: int, pid: int) -> void:
	var st = structures.get(Vector2i(tx, ty))
	if st == null:
		return
	var t := str(net.peer_tags.get(pid, ""))
	if t == "" or str(st.get("placed_tag", "")) != t:
		note_remote(pid, "That's not your build — guests raze only what they placed")
		return # guests raze only what THEY built — tags outlive pids
	if StructureData.STRUCTURES.get(st["id"], {}).get("anchor", false) \
			and st.get("pos", Vector2i(tx, ty)) == kinbox_pos:
		note_remote(pid, "The kinbox anchors the base — nobody razes it")
		return # the LIVE anchor holds every stored pal — a self-built backup is yours to raze
	var gp = net.ghosts.get(pid)
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(Vector2(tx + 0.5, ty + 0.5)) > 6.0:
		return # fail closed: razing needs a witnessed ghost in range
	# shared world: chest contents spill as drops (anyone can haul them),
	# no bag refund — the builder isn't here to catch it
	for it in st.get("store", {}).keys():
		spawn_drop(str(it), int(st["store"][it]), Vector2(tx + 0.5, ty + 0.5))
	var inc_gd: Dictionary = st.get("egg_inc", {}) # an incubating egg spills too — its claimed bloodline rides home to the ranch ledger
	if not inc_gd.is_empty():
		spawn_drop("huge_kin_egg" if inc_gd.get("huge", false) else ("bred_kin_egg" if inc_gd.get("pair") != null else "kin_egg"),
			1, Vector2(tx + 0.5, ty + 0.5))
		_return_egg_parent(inc_gd.get("pair"), Vector2(tx + 0.5, ty + 0.5))
	st["store"] = {}
	net_remove_structure(st)
	log_msg(tr("Player %d razed %s") % [pid,
		tr(str(StructureData.STRUCTURES.get(st["id"], {}).get("name", st["id"])))])

func net_remove_structure(st: Dictionary) -> void:
	var cells := []
	for k in structures:
		if structures[k] == st:
			cells.append(k)
	for w in st["workers"].duplicate():
		st["workers"].erase(w)
		if is_instance_valid(w):
			w.job_site = null
	var xp3: Kin = st.get("exp_pal") # a razed post recalls its expedition pal
	if is_instance_valid(xp3) and xp3.mode == "expedition":
		xp3.mode = "base"; xp3.visible = true
		xp3.job_site = null
		if not cells.is_empty():
			xp3.pos = Vector2(cells[0].x + 0.5, cells[0].y + 0.5)
	for k in cells:
		structures.erase(k)
		world.structures.erase(world.idx(k.x, k.y))
	_struct_gen += 1
	if is_instance_valid(st["node"]):
		st["node"].queue_free()
	if chest_ref == st:
		chest_ref = null
	if st["id"] == "kinbox" and not cells.is_empty():
		_kinbox_anchor_gone(cells)

# client: reconcile structure replicas against the host's wire truth
# guest-visible structure state — the compact "remaining-time" convention the
# save serializer already uses. mimic and egg_parents stay home deliberately:
# the trap is a spoiler and the genetics queue is the keeper's ledger
func struct_wire_state(st: Dictionary) -> Dictionary:
	var sv := {}
	if st["id"] == "kin_cage":
		sv["cap"] = st.get("captive") # explicit null clears a freed prisoner
	if st["id"] == "incubator":
		var inc = st.get("egg_inc")
		sv["inc"] = ({"pair": inc.get("pair"), "huge": inc.get("huge", false),
			"left": maxf(0.0, float(inc.get("ready_t", 0.0)) - t)} if inc is Dictionary else null)
	if st["id"] == "expedition_post":
		sv["exp"] = {"left": maxf(0.0, float(st.get("exp_end", 0.0)) - t),
			"cd": maxf(0.0, float(st.get("exp_cd", 0.0)) - t)}
		if st.get("exp_pal") is Kin:
			sv["exp_uid"] = st["exp_pal"].uid
	var fleft := float(st.get("fert", 0.0)) - t
	if fleft > 0.0:
		sv["fert"] = fleft
	if st.get("loot", false):
		sv["loot"] = true
	sv["timer"] = float(st.get("timer", 0.0)) # always — a finished timer is truth too
	if st.get("hp") != null:
		sv["hp"] = st["hp"]
	# identity tags (placed_tag, incubator own_tag) never ride the wire — a
	# broadcast tag is a public handle, and hello treats possession as proof
	var wu := []
	for w in st.get("workers", []):
		if w is Kin:
			wu.append(w.uid) # replicas carry it as net_id on the client
	sv["wk"] = wu # always — an empty crew is truth too
	return sv

func _struct_wire_apply(st: Dictionary, sv: Dictionary) -> void:
	if sv.has("cap"):
		if sv["cap"] is Dictionary:
			var cap_sp := str(sv["cap"].get("sp", ""))
			if SpeciesData.species_of(cap_sp).is_empty():
				st.erase("captive") # an unknown species aborts gen_pal mid-free
			else:
				st["captive"] = {"sp": cap_sp,
					"lv": clampi(_i(sv["cap"].get("lv", 1)), 1, 60)}
		else:
			st.erase("captive")
	if sv.has("inc"):
		if sv["inc"] is Dictionary:
			var inc: Dictionary = sv["inc"]
			var inc_pair = _norm_pair(inc.get("pair")) # same normalizer the save path runs — heads + numeric tails
			st["egg_inc"] = {"pair": inc_pair, "huge": inc.get("huge") is bool and inc["huge"],
				"ready_t": t + clampf(_f(inc.get("left", 0.0)), 0.0, 900.0)}
		else:
			st.erase("egg_inc")
	if sv.has("exp") and sv["exp"] is Dictionary:
		st["exp_end"] = t + clampf(_f(sv["exp"].get("left", 0.0)), 0.0, 3600.0)
		st["exp_cd"] = t + clampf(_f(sv["exp"].get("cd", 0.0)), 0.0, 3600.0)
		st["exp_pal"] = find_net_pal(_i(sv.get("exp_uid", -1)))
	if sv.has("fert"):
		st["fert"] = t + clampf(_f(sv["fert"]), 0.0, 600.0)
	elif st.has("fert") and t >= float(st["fert"]):
		st.erase("fert")
	if sv.has("loot"):
		st["loot"] = sv["loot"] is bool and sv["loot"]
	if sv.has("timer"):
		st["timer"] = clampf(_f(sv["timer"]), -3600.0, 3600.0)
	if sv.has("hp"):
		st["hp"] = clampi(_i(sv["hp"]), 0, 99999) # same ceiling the save loader enforces — a forged pack can't mint an unbreakable wall
	# no placed_tag write — the wire stopped carrying keeper tags (audit-29:
	# a broadcast tag let any guest hello-claim a disconnected keeper's
	# roster and raze rights)
	if sv.has("wk") and sv["wk"] is Array: # uids resolve to live replicas —
		var wl := [] # a missing one self-heals on the next tick
		for u in sv["wk"]:
			var r := find_net_pal(_i(u)) # a foreign worker uid can't abort the client's struct_sync
			if r != null:
				wl.append(r)
		st["workers"] = wl

func struct_sync(arr: Array) -> void:
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 3 or not _fin(e[1]) or not _fin(e[2]):
			continue
		var sid := str(e[0])
		if not StructureData.STRUCTURES.has(sid):
			continue
		var k := Vector2i(int(e[1]), int(e[2]))
		seen[k] = sid
		var cur = structures.get(k)
		var has_store: bool = e.size() > 3 and e[3] is Dictionary
		var wire_store := {}
		if has_store: # wire counts are still untrusted — coerce before they reach panel math
			for k2 in e[3]:
				wire_store[str(k2)] = maxi(_i(e[3][k2]), 0)
		var sv: Dictionary = e[4] if e.size() > 4 and e[4] is Dictionary else {}
		if cur != null and cur["id"] == sid and cur.get("pos", k) == k:
			if has_store:
				cur["store"] = wire_store # chest truth rides the wire — refresh it
			if not sv.is_empty():
				_struct_wire_apply(cur, sv)
			continue # a pack without a store field must not zero what's there
		if place_free(sid, k.x, k.y, wire_store) and not sv.is_empty():
			_struct_wire_apply(structures[k], sv)
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

# client: the join snapshot's mature-world layer — seed geometry can't tell a
# joiner which trees the island already lost; host truth overwrites it whole
func decor_snapshot_apply(d: Dictionary) -> bool:
	if d.get("decor") is PackedByteArray and d["decor"].size() == world.decor.size() \
			and d.get("hp_map") is PackedByteArray and d["hp_map"].size() == world.hp.size():
		var raw: PackedByteArray = d["decor"].duplicate() # clamp a copy — the caller's dict isn't ours to mutate
		for i2 in raw.size(): # an off-enum byte reaches harvest_cell's literal lookup — same clamp as decor_sync
			if raw[i2] > int(World.Decor.STUMP):
				raw[i2] = World.Decor.NONE
		world.decor = raw
		world.hp = d["hp_map"]
		queue_redraw_decor()
		return true
	return false

# client: apply host decor deltas (harvests, regrowth, footprint clears)
func decor_sync(arr: Array) -> void:
	var changed := false
	for e in arr:
		if e is Array and e.size() >= 2 and _fin(e[0]) and _fin(e[1]):
			var i := int(e[0])
			if i >= 0 and i < world.decor.size():
				world.decor[i] = clampi(int(e[1]), 0, int(World.Decor.STUMP)) # an off-enum byte kills harvest_cell's literal lookup
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
		"sleep": wd.get("sleep", 0.0),
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
		# twin trinket slots: re-click frees the slot it sits in,
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
			wear_by_id[k] = player.weapon_wear # the slot's wear follows the
			player.weapon_wear = -1.0          # item id — unequip/re-equip is
		elif slot == "armor":                  # not a free repair (audit-41)
			wear_by_id[k] = player.armor_wear
			player.armor_wear = -1.0
		log_msg(tr("Unequipped ") + tr(str(it["name"])))
	else:
		player.equipment[slot] = k
		if slot == "weapon":
			player.weapon_wear = float(wear_by_id.get(k, it["weapon"].get("dur", -1)))
		elif slot == "armor":
			player.armor_wear = float(wear_by_id.get(k, it["armor"].get("dur", -1)))
		log_msg(tr("Equipped ") + tr(str(it["name"])))

func break_weapon(id: String) -> void:
	log_msg(tr("%s broke!") % tr(str(ItemData.ITEMS.get(id, {}).get("name", id))))
	sfx_play("break")
	floater(player.pos, tr("BROKE!"), "#e64533")
	player.weapon_wear = -1.0
	wear_by_id.erase(id) # the counter dies with the item it measured
	add_item(id, -1) # count hits zero → unequip_if_gone clears the slot

func break_armor(id: String) -> void:
	log_msg(tr("%s broke!") % tr(str(ItemData.ITEMS.get(id, {}).get("name", id))))
	sfx_play("break")
	floater(player.pos, tr("ARMOR BROKE!"), "#e64533")
	player.armor_wear = -1.0
	wear_by_id.erase(id)
	add_item(id, -1) # count hits zero → unequip_if_gone clears the slot

func teach_skill_fruit(item_id: String) -> void:
	if client_locked():
		return
	# Skill fruit (the island): teaches the active kin a move of that element
	if party.is_empty():
		log_msg(tr("No active kin to teach"))
		return
	var p := lead_pal() # a benched lead can still study a fruit
	if p == null or p.hp <= 0:
		log_msg(tr("Lead kin is down"))
		return
	var elem: String = ItemData.ITEMS.get(item_id, {}).get("elem", "")
	var pool := []
	for sid in SkillData.SKILLS:
		var sk: Dictionary = SkillData.SKILLS[sid]
		if sk.get("element", "neutral") == elem and sk.get("power", 0) > 0:
			pool.append(sid)
	pool = pool.filter(func(s): return s not in p.learned_skills())
	if pool.is_empty():
		log_msg(tr("%s already knows every %s move") % [tr(str(p.spec["name"])), tr(str(elem))])
		return
	var sid: String = pool[rng.int_range(0, pool.size() - 1)]
	add_item(item_id, -1)
	p.extra_skills.append(sid)
	log_msg(tr("%s learned %s!") % [tr(str(p.spec["name"])), tr(str(SkillData.SKILLS[sid].get("name", sid)))])
	floater(p.pos, tr("+ skill!"), "#a8e6a1")

# ---------- wandering merchant ----------
# A trader visits for the day every so often — buys junk, sells goods for
# gold_coin. Transient by design: never saved, despawns at dusk.
var merchant: Entity = null
var merchant_stock := []
var merchant_home := Vector2.ZERO
var merchant_tgt := Vector2.ZERO # Kin already owns `target` — Entity must not
var merchant_wander_t := 0.0
var last_merchant_day := -1
var _tod_prev := 0.0
var catch_counts := {} # species_id -> caught count (10th-of-kind pays a bonus)
var catch_streak := 0 # consecutive captures — a hand that never fumbles earns more

const BOARD_POOL := [["wood", 10], ["stone", 8], ["fiber", 8], ["red_berries", 8],
	["mushroom", 5], ["wool", 3], ["raw_fish", 3], ["honey", 2], ["milk", 3]]
var board_quest := {} # supply:{kind,id,n,day} hunt:{kind,sp,n,got,day} — one per dawn

const HUNT_POOL := ["fenjelly", "fenlump", "sprigmelt", "puffmite", "briargoo",
	"cindlump", "faradlump", "quackbill", "corlmite", "nibjelly", "voltgoo", "shademelt",
	"loampuff", "dozantler", "piplump", "shademite", "shadelump", "loammelt", "marlump"]

func notice_board_action() -> void:
	if int(board_quest.get("day", -1)) != day:
		if rng.chance(0.5): # half the mornings want goods, half want thinning
			var pick: Array = BOARD_POOL[rng.int_range(0, BOARD_POOL.size() - 1)]
			board_quest = {"kind": "supply", "id": pick[0], "n": pick[1], "day": day}
		else:
			board_quest = {"kind": "hunt", "sp": HUNT_POOL[rng.int_range(0, HUNT_POOL.size() - 1)],
				"n": rng.int_range(2, 4), "got": 0, "day": day}
	var qk: String = str(board_quest.get("kind", "supply"))
	if qk == "hunt":
		var sname: String = tr(str(SpeciesData.species_of(board_quest["sp"]).get("name", board_quest["sp"])))
		log_msg(tr("Notice board: cull %d %s (%d/%d) — kill or capture counts") % \
			[int(board_quest["n"]), sname, int(board_quest.get("got", 0)), int(board_quest["n"])])
		return
	var qid: String = str(board_quest.get("id", ""))
	if qid == "":
		log_msg(tr("Notice board: today's request is filled — come back at dawn"))
		return
	var qn: int = board_quest["n"]
	var iname: String = tr(str(ItemData.ITEMS.get(qid, {}).get("name", qid)))
	if item_count(qid) < qn:
		log_msg(tr("Notice board: bring %d %s (have %d)") % [qn, iname, item_count(qid)])
		return
	add_item(qid, -qn)
	var gold: int = qn * maxi(2, int(ItemData.ITEMS.get(qid, {}).get("price", 2)))
	add_item("gold_coin", gold)
	gain_xp(qn * 3)
	floater(player.pos, tr("+%d gold") % gold, "#ffd76e")
	log_msg(tr("Board request filled: %d %s → +%d gold") % [qn, iname, gold])
	board_quest["id"] = "" # filled — the board stays quiet until tomorrow

const GACHA_COST := 45 # must beat 0.9×lv1-sell + 0.1×huge-sell EV — else it's a mint

func gacha_pull() -> void:
	# feed the brass mouth — the brass takes its cut: eggs resold
	# don't cover the pull, so the machine stays a sink not a mint
	if item_count("gold_coin") < GACHA_COST:
		log_msg(tr("Kin gacha: it wants %d gold in the slot") % GACHA_COST)
		return
	add_item("gold_coin", -GACHA_COST)
	var eid: String = "huge_kin_egg" if rng.chance(0.1) else "kin_egg"
	add_item(eid, 1)
	floater(player.pos, tr("★ %s!") % tr(str(ItemData.ITEMS[eid]["name"])),
		"#ffd76e" if eid == "huge_kin_egg" else "#e8f0f2")
	log_msg(tr("The gacha rattles — out rolls a %s") % tr(str(ItemData.ITEMS[eid]["name"])))
	sfx_play("catch")

func gacha_req_remote(pid: int) -> String:
	# the host feeds the slot for a guest: the asker's bag already gave the
	# gold (net.pay hold — a refusal echoes pay_rej), we only gate on reach
	# and roll the egg with host authority. Returns "" on refusal.
	var at := _ghost_at(pid)
	if at.x < -1e8:
		return ""
	var site := _nearest_struct("kin_gacha", at, 6.0)
	if site.x < 0:
		note_remote(pid, "Stand by the brass mouth to pull")
		return ""
	var eid: String = "huge_kin_egg" if rng.chance(0.1) else "kin_egg"
	give_remote(pid, eid, 1)
	return eid

func board_hunt_credit(sp: String, pid := 0) -> void:
	# the guild pays for thinning whether the kin leaves in a bag or a box —
	# and whoever did the thinning pockets the bounty, keeper or guest
	if str(board_quest.get("kind", "")) != "hunt" \
			or str(board_quest.get("sp", "")) != sp \
			or int(board_quest.get("day", -1)) != day:
		return
	board_quest["got"] = int(board_quest.get("got", 0)) + 1
	var need: int = int(board_quest["n"])
	var sname: String = tr(str(SpeciesData.species_of(sp).get("name", sp)))
	if int(board_quest["got"]) >= need:
		var gold: int = need * 25
		_kill_loot(pid, "gold_coin", gold)
		_kill_xp(pid, need * 15)
		floater(peer_pos_of(pid) if pid > 0 else player.pos,
			tr("HUNT FILLED +%dg") % gold, "#ffd76e")
		log_msg(tr("Hunt filled: %d %s → +%d gold") % [need, sname, gold])
		board_quest["kind"] = "done"
	else:
		log_msg(tr("Hunt: %s %d/%d") % [sname, int(board_quest["got"]), need])

const MERCH_POOL := ["kin_orb", "mega_orb", "low_medical", "medical_supplies",
	"bread", "jam_bun", "berry_seeds", "wheat_seeds", "arrow", "musket_ball",
	"skill_fruit_neutral", "skill_fruit_fire", "skill_fruit_water", "skill_fruit_grass",
	"skill_fruit_electric", "skill_fruit_ice", "skill_fruit_ground", "skill_fruit_dark",
	"skill_fruit_dragon", "cake", "kin_egg", "memory_wipe", "treasure_map"]

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
	# black-market rarity: the odd huge egg slips into the briefcase, marked up
	if rng.chance(0.2):
		var hp_price: int = ItemData.ITEMS.get("huge_kin_egg", {}).get("price", 200)
		merchant_stock.append({"id": "huge_kin_egg", "n": 1, "price": int(hp_price * 1.5)})
	# and sometimes a dare: a boss sigil under the counter, priced to hesitate
	if rng.chance(0.15):
		merchant_stock.append({"id": "boss_sigil", "n": 1, "price": 150})
	# a rarer dare: the gauntlet's ticket — a gold path for keepers who
	# haven't broken a spire yet (spire kills pay one each, guaranteed)
	if rng.chance(0.10):
		merchant_stock.append({"id": "gauntlet_sigil", "n": 1, "price": 120})
	# the Accord's standing order: a sealed keeper can always buy effigies —
	# a real gold sink plumbed into soul_infuse, not a lottery line. Uncapped:
	# 55 per kin is the deepest gold→power conversion the island offers
	if accord:
		merchant_stock.append({"id": "sprigmelt_effigy", "n": 99, "price": 160})
	# black-market kin (the island): a few capturable-free specimens, priced by
	# zone rarity — deep-zone species cost real money
	for i in rng.int_range(2, 3):
		if merchant_stock.size() >= MAX_MERCH_STOCK:
			break # the briefcase is bounded — the cap is a real gate, not a hint
		var z := rng.int_range(0, 2) if rng.chance(0.85) else 3
		var ppool: Array = acq_pool(SpeciesGen.zone_pool(z))
		if ppool.is_empty():
			continue
		var sid: String = ppool[rng.int_range(0, ppool.size() - 1)]
		var plv := rng.int_range(5 + z * 6, 14 + z * 8)
		merchant_stock.append({"kin": sid, "lv": plv, "n": 1,
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
	merchant.setup_visuals("res://assets/kin/player_f0.png", "res://assets/kin/player_f1.png")
	merchant.sprite.modulate = Color(1.5, 1.0, 0.45) # a warmly-dressed stranger
	merchant_home = at
	gen_merchant_stock()
	merchant_hp = 60
	if net != null and multiplayer.multiplayer_peer != null:
		net.rpc("stock_sync", merchant_stock) # guests see the same briefcase
	log_msg(tr("A wandering merchant has arrived! (E to trade)"))
	floater(at, tr("Merchant!"), "#e8d44d")

func despawn_merchant() -> void:
	if merchant == null:
		return
	if is_instance_valid(merchant):
		floater(merchant.pos, tr("safe travels…"), "#c8d3d5")
		merchant.queue_free()
	merchant = null
	merchant_stock.clear()
	merchant_wanted = false
	log_msg(tr("The merchant moved on"))

var merchant_wanted := false # one hit squad per visit — wanted loop
var merchant_deaths := 0     # the Pact remembers every corpse — each one pays less
var merchant_hp := 60          # Entity has no hp field — Kin/Player shadow it

func net_merchant_apply(on: bool, x: float, y: float) -> void:
	# the trader is a host-scheduled guest of honor — clients hold only a
	# visual mirror; stock and hp stay authority-side (env_sync feeds pos)
	if not on:
		if merchant != null and is_instance_valid(merchant):
			merchant.queue_free()
		merchant = null
		merchant_stock.clear()
		return
	if merchant == null or not is_instance_valid(merchant):
		merchant = preload("res://src/entity.gd").new()
		merchant.world = world
		entity_layer.add_child(merchant)
		merchant.setup_visuals("res://assets/kin/player_f0.png", "res://assets/kin/player_f1.png")
	merchant.pos = Vector2(x, y)
	merchant.sync_screen()

func hit_merchant(dmg: float, pid := 0) -> void:
	if net != null and net.is_client():
		net.rpc("merch_hit", dmg) # the beating lands on the host's ledger
		return
	if merchant == null or not is_instance_valid(merchant):
		return
	merchant_hp -= int(dmg)
	merchant.hit_flash = 0.4
	sfx_play("hit")
	if not merchant_wanted:
		merchant_wanted = true
		# crime loop: raise a hand at a peaceful NPC and a Iron Pact
		# hit squad materializes to collect — once per visit, killable like any foe
		var at0: Vector2 = peer_pos_of(pid) if pid > 0 else player.pos
		var squad := mini(2 + int(day / 6.0), 4)
		for i in squad:
			if pals.size() >= MAX_PALS:
				break # the population cap is also a CPU guard — the law waits
			var a := rng.next() * TAU
			var at := nearest_free(at0.x + cos(a) * 5.0, at0.y + sin(a) * 5.0)
			var thug := gen_pal("ironpact_grunt" if i % 2 == 0 else "ironpact_sweeper",
				maxi(3, player.level + rng.int_range(-1, 2)), at)
			thug.mode = "wild"; thug.aggro = 0; thug.aggro_pid = pid; thug.home = at0
			pals.append(thug)
		merchant_tgt = merchant.pos + (merchant.pos - at0).normalized() * 20.0
		log_msg(tr("WANTED! The Iron Pact answers violence with violence"))
		floater(merchant.pos, tr("GUARDS!"), "#ff5544")
	if merchant_hp <= 0:
		merchant_deaths += 1 # repeat murders pay a fraction — not a farm
		var drops_n := maxi(4, rng.int_range(30, 60) / maxi(1, merchant_deaths))
		spawn_drop("gold_coin", drops_n, merchant.pos)
		floater(merchant.pos, tr("+%dg") % drops_n, "#ffd76e")
		log_msg(tr("The merchant is dead. The Iron Pact remembers"))
		despawn_merchant()

func tick_merchant(dt: float) -> void:
	if net != null and net.is_client():
		return # the trader's visit is a host-scheduled event
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
		log_msg(tr("Need %d gold") % it["price"])
		return
	if it.has("kin"):
		var sid := str(it["kin"])
		if SpeciesData.species_of(sid).is_empty():
			it["n"] = 0 # corrupted stock — retire the slot, never sell a ghost
			return
		if box.size() >= MAX_BOX:
			log_msg(tr("Kinbox full - make room first"))
			return
		var np := gen_pal(sid, int(it["lv"]), player.pos)
		np.mode = "box"
		box.append(np)
		box_pal(np) # bought straight into the box — never a loose node
		add_item("gold_coin", -it["price"])
		it["n"] -= 1
		log_msg(tr("Bought a Lv%d %s! (%dg)") % [np.level, tr(str(np.spec["name"])), it["price"]])
		sfx_play("coin")
		return
	add_item("gold_coin", -it["price"])
	add_item(it["id"], 1)
	it["n"] -= 1
	log_msg(tr("Bought %s (%dg)") % [tr(str(ItemData.ITEMS.get(it["id"], {}).get("name", it["id"]))), it["price"]])
	sfx_play("coin")

# host-side guest buy: the stock is the island's — decrementing a mirror
# would just resync and never run out. Items land via give_remote; a kin
# purchase arrives owner-tagged through box_sync. The gold is the bag's
# own business — paid on the bought echo.
func buy_remote(pid: int, idx: int) -> Dictionary:
	if merchant == null or idx < 0 or idx >= merchant_stock.size() \
			or not _ghost_reaches(pid, merchant.pos, 6.0):
		return {} # the till only rings within arm's reach of the trader
	var it: Dictionary = merchant_stock[idx]
	if int(it.get("n", 0)) <= 0:
		return {}
	var price := int(it.get("price", 0))
	if it.has("kin"):
		var sid := str(it["kin"])
		if SpeciesData.species_of(sid).is_empty() or box.size() >= MAX_BOX:
			return {}
		var np := gen_pal(sid, int(it["lv"]), peer_pos_of(pid))
		np.mode = "box"
		np.owner_id = pid
		np.owner_tag = str(net.peer_tags.get(pid, "")) if net != null else ""
		box.append(np)
		box_pal(np)
		it["n"] -= 1
		return {"price": price, "kin": sid}
	var iid := str(it.get("id", ""))
	if not ItemData.ITEMS.has(iid):
		return {}
	if iid in ["boss_sigil", "gauntlet_sigil"]: # host-only verbs — a guest's sigil would be a dead item
		note_remote(pid, "%s — only the keeper can use that", [str(ItemData.ITEMS[iid].get("name", iid))])
		return {}
	it["n"] -= 1
	give_remote(pid, iid, 1)
	return {"price": price}

func pal_sell_price(bp: Kin) -> int:
	# black-market buyback: worth less than the sticker price, more if rare.
	# base 20 not 40: a lv1 hatchling sells for 28 < a 30g kin_egg — else the
	# merchant's own eggs hatch into a +60% money printer (audit-36/S83)
	return 20 + bp.level * 8 + (60 if bp.lucky else 0) + (80 if bp.alpha else 0) \
		+ bp.star * 50

func sell_pal_to_merchant(uid: int) -> void:
	if merchant == null:
		return
	for bp in box:
		if bp.uid == uid:
			if bp.fav:
				log_msg(tr("%s is heart-locked") % tr(str(bp.spec["name"])))
				return
			var gain := pal_sell_price(bp)
			var nm: String = tr(str(bp.spec["name"]))
			box.erase(bp)
			bp.free() # box pals live under box_holder — free() is the teardown path
			add_item("gold_coin", gain)
			log_msg(tr("Sold %s for %dg") % [nm, gain])
			sfx_play("coin")
			return

func toggle_fav(uid: int) -> void:
	# heart-lock a boxed kin — butcher, merchant sale and condense fodder all skip it
	for bp in box:
		if bp.uid == uid:
			bp.fav = not bp.fav
			return

func butcher_pal(uid: int) -> void:
	# meat cleaver: sacrifice a boxed kin, it spills its drops
	if item_count("meat_cleaver") <= 0:
		log_msg(tr("You need a Meat Cleaver for that"))
		return
	for bp in box:
		if bp.uid == uid:
			if bp.fav:
				log_msg(tr("%s is heart-locked") % tr(str(bp.spec["name"])))
				return
			var nm: String = tr(str(bp.spec["name"]))
			var mult := 3 if bp.lucky else 1
			box.erase(bp)
			for dr in bp.spec.get("drops", []):
				spawn_drop(dr[0], rng.int_range(dr[1], dr[2]) * mult, player.pos)
			bp.free() # box-holder path — same teardown as condense/sell
			log_msg(tr("You butchered %s… it dropped its goods") % nm)
			return

func sell_to_merchant(id: String) -> void:
	if merchant == null or item_count(id) <= 0:
		return
	var price: int = int(ItemData.ITEMS.get(id, {}).get("price", 0))
	if price <= 0:
		return # unpriced goods never leave for gold — a 1g pity floor is farmable
	var unit: int = maxi(1, int(price * 0.5))
	add_item(id, -1)
	add_item("gold_coin", unit)
	log_msg(tr("Sold %s (+%dg)") % [tr(str(ItemData.ITEMS.get(id, {}).get("name", id))), unit])
