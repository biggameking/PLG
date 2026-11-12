extends Node
class_name Net

# LAN co-op scaffold: host shares world seed, peers see each other as ghost
# players. Kin/combat remain locally authoritative for now (sync them next).

const PORT := 7777
const MAX_PEERS := 8 # co-op scale — ghosts/tags/fan-out all grow per peer
var game: Game
var entity_layer: Node2D
var ghosts := {}  # peer_id -> Node2D
var send_timer := 0.0
# Pay-first ledger: cost verbs debit the bag when the request flies, not when
# the echo lands — a dropped wire strands the payment as a loss on the payer,
# never as goods minted into shared/durable truth. Reliable ordering makes
# settles arrive FIFO, so each pops the oldest matching tag.
var pending_pays: Array = []
const MAX_PENDING_PAYS := 32 # in-flight holds — every verb settles or rejs, but the ledger still answers to rule 1
var mount_pending := false # a mount_req is in flight — the button can't double-toggle before mount_done lands
var mount_pending_uid := -1 # which handshake is out — a stray echo can't re-arm the button early
var unbind_retry_t := 0.0 # self-heal cooldown — the host keeps hearing "let go" until it does
var board_paid_out := "" # goods already asserted for this ask — a re-shown board_done can't double-deduct
func pay(tag: String, cost: Dictionary) -> bool:
	# the ledger records what the bag ACTUALLY gave, not what the click
	# claimed — add_item floors at zero, and a claimed refund would mint
	var debited := {}
	for k in cost:
		var had := game.item_count(str(k))
		game.add_item(str(k), -int(cost[k]))
		var took: int = had - game.item_count(str(k))
		if took > 0:
			debited[str(k)] = took
	if debited.is_empty():
		return true # nothing left the bag — a free verb still flies, no hold
	if pending_pays.size() >= MAX_PENDING_PAYS:
		# refuse BEFORE the request flies: evicting a booked hold would let its
		# echo settle a *different* same-tag request — cap means "come back in a
		# beat", never "the oldest hold evaporates"
		for k in debited:
			game.add_item(str(k), int(debited[k]))
		game.log_msg(tr("Too many open offers — try again in a breath"))
		return false
	pending_pays.append({"tag": tag, "cost": debited})
	return true
func pay_hold(tag: String) -> Dictionary:
	# peek the recorded hold — echoes reconcile against what the bag ACTUALLY
	# gave, never against the number the wire asserts
	for h in pending_pays:
		if h["tag"] == tag:
			return h["cost"]
	return {}

func pay_settle(tag: String, refund: bool) -> void:
	for i in pending_pays.size():
		if pending_pays[i]["tag"] == tag:
			if refund:
				for k in pending_pays[i]["cost"]:
					game.add_item(str(k), int(pending_pays[i]["cost"][k]))
			pending_pays.remove_at(i)
			return
@rpc("authority", "call_remote", "reliable")
func pay_rej(tag: String) -> void:
	if is_host:
		return
	pay_settle(str(tag), true)
	game.log_msg(tr("Request refused — goods returned"))
# host-side: every refused paid verb owes the asker a refund echo
func _pay_rej(pid: int, tag: String) -> void:
	if multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
			and multiplayer.get_peers().has(pid):
		rpc_id(pid, "pay_rej", tag)
var is_host := false
var peer_tags := {} # peer_id -> install token — a guest's stable keeper identity

func setup(g: Game, layer: Node2D) -> void:
	game = g
	entity_layer = layer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	multiplayer.server_relay = false # leaf guests must not hear each other —
	# the host relays what they need (peer_pos/peer_joined/chat), and a guest's
	# broadcast reaching other guests prints every chat line twice in a trio
	if peer.create_server(PORT, MAX_PEERS) != OK:
		game.log_msg(tr("Host failed: port %d busy") % PORT)
		return
	_close_peer() # never swap a live peer — that leaks the session and
	# flips is_client() off, which would open the save gates on a guest
	multiplayer.multiplayer_peer = peer
	is_host = true
	game.log_msg(tr("Hosting on port %d — friends join with K") % PORT)

func join(ip: String) -> void:
	if game.state != "title": # world_sync razes this world — an unsaved solo run would evaporate
		game.save_game() # clients self-refuse inside save_game — safe from every state
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		game.log_msg(tr("Join failed"))
		return
	_close_peer()
	is_host = false
	multiplayer.multiplayer_peer = peer
	game.log_msg(tr("Joining %s:%d ...") % [ip, PORT])

func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	# peer-swap is the choke — no hold or handshake may leak into the next dial.
	# (ghosts/net_party/mirrors are owned by _on_server_disconnected or the
	# scene reload — every caller here either has no live session or is
	# to_title, which razes the whole tree a line later)
	pending_pays.clear()
	mount_pending = false
	mount_pending_uid = -1
	unbind_retry_t = 0.0
	board_paid_out = ""
	game.chest_ref = null

func is_client() -> bool:
	# "not host" alone is also true offline — and a headless/offline run
	# still carries an OfflineMultiplayerPeer, so null-checks lie. A real
	# client is exactly: not host AND a live ENet peer.
	return not is_host and multiplayer.multiplayer_peer is ENetMultiplayerPeer

func _on_peer_connected(id: int) -> void:
	if is_host:
		rpc_id(id, "world_sync", game.world.seed)
		rpc_id(id, "state_sync", state_snapshot())
		# inform every client about every peer (star topo: clients never see peer_connected)
		for pid in multiplayer.get_peers():
			rpc("peer_joined", pid)
		rpc("peer_joined", id)
	spawn_ghost(id)

func _on_connected_to_server() -> void:
	spawn_ghost(1)  # host
	rpc("hello", my_tag()) # our install token claims our pals on their world
	game.log_msg(tr("Connected to host"))

func my_tag() -> String:
	# one random token per install — lets a guest's kin find their keeper
	# again across sessions without any account system
	var cf := ConfigFile.new()
	var t := ""
	if cf.load("user://plg_net.cfg") == OK:
		t = str(cf.get_value("net", "tag", ""))
	if t == "":
		t = "%x%x" % [randi(), int(Time.get_unix_time_from_system() * 1000) & 0x7FFFFFFF]
		cf.set_value("net", "tag", t)
		cf.save("user://plg_net.cfg")
	return t

func _throttle(pid: int, key: String, rate: float, burst: float) -> bool:
	# shared abuse brake: one token bucket per verb per ghost — honest clicks
	# never clip, a scripted 60Hz spam converges to the rate
	var g = ghosts.get(pid)
	if g == null:
		return false
	var now: float = Time.get_ticks_msec() / 1000.0
	var a: float = minf(float(g.get_meta(key, burst)) \
		+ (now - float(g.get_meta(key + "_t", now))) * rate, burst)
	g.set_meta(key + "_t", now)
	if a < 1.0:
		g.set_meta(key, a)
		return false
	g.set_meta(key, a - 1.0)
	return true

@rpc("any_peer", "call_remote", "reliable")
func hello(tag: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if ghosts.has(pid) and not _throttle(pid, "hello_bkt", 1.0, 4.0):
		return # a re-hello is one breath, a script is not — its own slow bucket
	var tag_s := str(tag).substr(0, 24)
	if tag_s == "" or tag_s.begins_with("_pid"):
		tag_s = "_pid%d" % pid # the _pid namespace is reserved — a guest can't claim another peer's fallback row
	if peer_tags.has(pid):
		if peer_tags[pid] != tag_s:
			rpc_id(pid, "net_note", "Keeper tag already bound for this session")
		return # first hello wins — a bound pid can't slide onto a dead keeper's identity
	for other in peer_tags:
		if other != pid and peer_tags[other] == tag_s:
			rpc_id(pid, "net_note", "That keeper tag is already claimed")
			return # a live session holds this identity — don't clobber its roster
	peer_tags[pid] = tag_s
	game.rebind_owner(pid, peer_tags[pid])
	# they may already own kin here — hand the roster over immediately
	rpc_id(pid, "box_sync", box_state_pack(pid), game.rparty_for(pid).duplicate(), party_state_pack(pid))

@rpc("authority", "call_remote", "reliable")
func net_note(msg: Variant, args: Variant = []) -> void:
	# a host whisper in the guest's log — the key + raw args travel; we translate
	var a := []
	if args is Array:
		for x in args:
			if a.size() >= 6:
				break
			if x is String:
				a.append(tr(str(x).substr(0, 48)))
			elif x is int or x is float or x is bool:
				a.append(x)
	var t := tr(str(msg).substr(0, 120))
	game.log_msg(t % a if a.size() else t)

@rpc("authority", "call_remote", "reliable")
func net_floater(x: float, y: float, txt: String, col: String) -> void:
	if not is_finite(x) or not is_finite(y):
		return
	game.floater(Vector2(float(x), float(y)), tr(str(txt).substr(0, 24)), str(col))

@rpc("authority", "call_remote", "reliable")
func catch_credit(sid) -> void:
	# the keeper's own catch ledger — the host's world book already logged
	# this catch for accord/dex; this local copy is what the guest's kindex
	# and mission chain read, so it must only count THEIR throws
	if game == null or multiplayer.is_server():
		return
	game.credit_catch_local(str(sid))

@rpc("authority", "call_remote", "reliable")
func guest_hit(dmg: float) -> void:
	if multiplayer.is_server() or not is_finite(dmg):
		return # host wildlife only bites through the wire toward guests — NaN bites nothing
	if not _throttle(1, "hurt_bkt", 10.0, 16.0):
		return # a scripted packet storm can't out-DPS honest wildlife
	game.hurt_player(clampf(float(dmg), 1.0, 500.0), null)

@rpc("authority", "call_remote", "reliable")
func guest_skill_hit(power: float, status_kind: String = "", status_dur: float = 0.0) -> void:
	if multiplayer.is_server() or not is_finite(power) or not is_finite(status_dur):
		return # a skill shot mirrors the same formula on the guest's own armor
	if not _throttle(1, "hurt_bkt", 10.0, 16.0):
		return
	if status_kind != "" and status_kind not in ["burn", "soak", "freeze", "poison", "sleep"]:
		status_kind = "" # kinds the player body actually supports — "shock" and
		# kin-only ailments stay off the wire
	game.hurt_player_skill(clampf(float(power), 0.0, 500.0), status_kind,
		clampf(status_dur, 0.0, 12.0))

func _on_peer_disconnected(id: int) -> void:
	if ghosts.has(id):
		ghosts[id].queue_free()
		ghosts.erase(id)
	if is_host:
		game.r_retract(id) # a leaving keeper's field pal balls up under their tag
		game.orphan_guest_kin(id) # roster survives under the tag for a rejoin
		peer_tags.erase(id) # the tag survives in remote_parties for a rejoin
		chat_last.erase(id) # a dead pid's spam brake shouldn't park a reuse
		rpc("peer_left", id)

@rpc("authority", "call_remote", "reliable")
func peer_joined(id: int) -> void:
	if id != multiplayer.get_unique_id() and not ghosts.has(id):
		spawn_ghost(id)

@rpc("authority", "call_remote", "reliable")
func peer_left(id: int) -> void:
	if ghosts.has(id):
		ghosts[id].queue_free()
		ghosts.erase(id)

func state_snapshot() -> Dictionary:
	# one pack path for snapshots and ticks — a footprint key cell is not an
	# origin, and state fields (egg timers, workers) join for free
	var arr := struct_state_pack()
	# share the living population too — a joining client should see the same
	# wild/base kin, not an empty world (capped upstream by MAX_PALS). One
	# packer for snapshots and ticks: the joiner gets hp/mounted_by too.
	var parr := pal_state_pack()
	var mp := {}
	if game.merchant != null and is_instance_valid(game.merchant):
		mp = {"on": true, "x": game.merchant.pos.x, "y": game.merchant.pos.y}
	return {"structures": arr, "tod": game.tod, "day": game.day, "kin": parr,
		# a mature world's decor isn't the seed's decor — the joiner lands on
		# regenerated geometry, then these rows overwrite every harvest,
		# regrowth and footprint clear the island remembers
		"decor": game.world.decor.duplicate(), "hp_map": game.world.hp.duplicate(),
		"unlocked": game.unlocked.duplicate(), # the host's tech bounds the client's build bar
		"cr": game.crowned, "acc": game.accord, # the campaign spine lands with
		"sn": game.spires_done.size(), "dn": game.den_caught(), # its tallies too —
		# the world — box_sync can follow immediately without starving the cap
		"merch": mp, "stock": game.merchant_stock.duplicate()} # a joiner mid-visit still sees the trader

@rpc("authority", "call_remote", "reliable")
func state_sync(d: Dictionary) -> void:
	# mature-world decor lands BEFORE the structure rows — place_free reads
	# decor, so host truth must be on the ground before a lair chest can
	# claim its cell (regenerate() left the seed's pristine layer behind)
	game.decor_snapshot_apply(d)
	# joining replaces every local structure with the host's rows — a leftover
	# from our own regenerate() would shadow its host twin (loot, cages, HP)
	# and place_free would refuse the cell outright
	for k0 in game.structures.keys():
		var n0 = game.structures[k0].get("node")
		if is_instance_valid(n0):
			n0.queue_free()
	game.structures.clear()
	game.world.structures.clear()
	game._struct_gen += 1 # a zero-structure snapshot still invalidates the heat memo
	for e in (d["structures"] if d.get("structures") is Array else []): # a scalar/nil here aborts the whole rebuild — after the world was already razed
		if e is Array and e.size() >= 3 and Game._fin(e[1]) and Game._fin(e[2]):
			var st_store := {}
			if e.size() > 3 and e[3] is Dictionary: # same per-entry coercion struct_sync runs — raw wire values don't reach store math
				for sk2 in e[3]:
					st_store[str(sk2)] = maxi(Game._i(e[3][sk2]), 0)
			if game.place_free(str(e[0]), int(e[1]), int(e[2]), st_store) \
					and e.size() > 4 and e[4] is Dictionary:
				var sk := Vector2i(int(e[1]), int(e[2]))
				if game.structures.has(sk):
					game._struct_wire_apply(game.structures[sk], e[4]) # same wire shape as struct_sync
	if d.get("unlocked") is Array:
		game.net_unlocked = d["unlocked"] # the host's tech bounds our build bar
	game.tod = clampf(Game._f(d.get("tod", game.tod), game.tod), 0.0, 24.0) # an INF tod fast-forwards a day per frame — same clamp the save path runs
	game.day = maxi(Game._i(d.get("day", game.day), game.day), 1)
	game.crowned = d.get("cr") is bool and d["cr"] # the spine lands before
	game.accord = d.get("acc") is bool and d["acc"] # any box_sync strip arrives
	game.net_spires = clampi(Game._i(d.get("sn", 0)), 0, Game.SPIRE_DEFS.size())
	game.net_den = clampi(Game._i(d.get("dn", 0)), 0, Game.LEGENDARY_DEN.size())
	# drop the population our own regenerate() spawned — the host's wild/base
	# kin replace it, otherwise clients see every kin twice
	for p in game.pals.duplicate():
		if p.mode in ["wild", "base", "partner"]: # partner replicas are host truth too
			if game.player.mount == p:
				game.player.mount = null # a re-synced world can't keep the saddle — same contract as purge_replicas
			game.pals.erase(p)
			p.queue_free()
	var np := 0
	for e in (d["kin"] if d.get("kin") is Array else []):
		if not (e is Array) or e.size() < 7:
			continue
		var n0 := game.pals.size()
		# kin rows ship in pal_state_pack shape — the same reorder pal_sync
		# runs before spawn_net_pal applies its wire shape
		game.spawn_net_pal([e[1], e[2], e[3], e[4], e[5],
			e[7] if e.size() > 7 else false, Game._i(e[0]),
			e[8] if e.size() > 8 else false,
			e[9] if e.size() > 9 else false,
			e[10] if e.size() > 10 else "",
			e[11] if e.size() > 11 else 0,
			e[12] if e.size() > 12 else 0]) # join-spawned replicas keep their keeper too
		np += 1 if game.pals.size() > n0 else 0
	var md: Dictionary = d.get("merch", {}) if d.get("merch") is Dictionary else {}
	game.net_merchant_apply(md.get("on") == true,
		Game._f(md.get("x", 0.0)), Game._f(md.get("y", 0.0)))
	stock_sync(d.get("stock", []) if d.get("stock") is Array else [])
	var nst: int = d["structures"].size() if d.get("structures") is Array else 0
	game.log_msg(tr("Synced %d structures, %d kin") % [nst, np])

# Live kin population: host rebroadcasts positions/health at 2Hz so replicas
# don't just sit where the join snapshot left them. Replicas are keyed by
# host uid (net_id); unknown ids spawn, missing ids despawn — one packet is
# the whole truth, packet loss self-heals on the next tick.
func pal_state_pack() -> Array:
	var arr := []
	for p in game.pals:
		if p.mode in ["wild", "base", "partner"] and p.hp > 0:
			if p.mounted_by == 1:
				# the host's own rider: ghosts[1].net_pos is never fed —
				# player.pos is the honest source (peer_pos_of's own fallback)
				p.pos = game.player.pos
			elif p.mounted_by > 0 and ghosts.has(p.mounted_by):
				# a bound mount lives where its rider is — the ghost's validated
				# pos is the only honest source, and every watcher needs it
				var rg = ghosts[p.mounted_by]
				p.pos = Vector2(rg.net_pos.x, rg.net_pos.y)
			arr.append([p.uid, p.species_id, p.pos.x, p.pos.y, p.level, p.mode, p.hp, p.lucky, p.boss,
				p.alpha, p.spire_tag, p.mounted_by, p.owner_id])
	return arr

@rpc("authority", "call_remote", "unreliable")
func pal_sync(arr: Array) -> void:
	if is_host:
		return # the host's own broadcast echoes back — it's the authority already
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 6 or not Game._fin(e[0]):
			continue
		var nid := int(e[0])
		if nid <= 0:
			continue # host uids are >=1 — a zero/negative row would spawn an untrackable phantom every tick
		seen[nid] = true
		var p := game.find_net_pal(nid)
		if p == null:
			# [species, x, y, lv, mode, lucky, net_id, boss, alpha, spire_tag,
			#  mounted_by, owner_id] — spawn_net_pal's wire shape
			game.spawn_net_pal([e[1], e[2], e[3], e[4], e[5],
				e[7] if e.size() > 7 else false, nid,
				e[8] if e.size() > 8 else false,
				e[9] if e.size() > 9 else false,
				e[10] if e.size() > 10 else "",
				e[11] if e.size() > 11 else 0,
				e[12] if e.size() > 12 else 0])
		else:
			p.net_target = Vector2(Game._f(e[2]), Game._f(e[3]))
			p.hp = maxf(0.0, Game._f(e[6])) if e.size() > 6 else p.hp
			if e.size() > 4:
				p.level = clampi(Game._i(e[4]), 1, 60) # host-side xp growth must reach the replica
			if e.size() > 5 and str(e[5]) in ["wild", "base", "partner"]:
				p.mode = str(e[5]) # a replica's post can change mid-session — deploy rides the wire too
			p.owner_id = maxi(Game._i(e[12]), 0) if e.size() > 12 else p.owner_id # claims ride along too
			p.mounted_by = maxi(Game._i(e[11]), 0) if e.size() > 11 else 0 # negative ids hide the replica's rider state
			var myid := 0 # no peer → 0; the mounted_by==0 lane below needs no uid
			if multiplayer.multiplayer_peer != null:
				myid = multiplayer.get_unique_id()
			if p == game.player.mount and (p.mounted_by == 0 or p.mounted_by != myid):
				# host released the saddle on a kin that STAYS alive — deploy/sell/KO
				# free the replica, but deploy_to_base leaves it; without this the
				# client keeps riding an invisible base worker
				game.player.mount = null
				p.visible = true
			elif p != game.player.mount: # the rider's own mount hides via player.gd
				p.visible = p.mounted_by == 0
			_mount_selfheal_check(nid, p.mounted_by)
	for p in game.pals.duplicate():
		if p.net_id > 0 and not seen.has(p.net_id): # host dropped it: caught, KO'd, despawned
			if game.player.mount == p:
				game.player.mount = null # a despawned mount can't stay saddled — freed-instance derefs every frame otherwise
			game.pals.erase(p)
			p.queue_free()

@rpc("authority", "call_remote", "unreliable")
func env_sync(tod: float, day: int, weather: String, danger: bool = false,
		bq: Dictionary = {}, merch: Dictionary = {}, wmode: int = -1,
		unl: Array = [], cr: bool = false, acc: bool = false,
		sn: int = -1, dn: int = -1, sm: int = -1) -> void:
	if is_host:
		return
	game.crowned = cr == true # campaign spine is host truth — the crown and
	game.accord = acc == true # the accord gate party_cap + the HUD tally alike
	if sn >= 0: # the spine counters ride the same packet — a guest's HUD
		game.net_spires = mini(sn, Game.SPIRE_DEFS.size()) # tallies the host's
		game.net_den = mini(dn, Game.LEGENDARY_DEN.size()) # ledger, not its own
	if sm >= 0: # broken-spire bits are replica truth — hollow map markers draw
		for smi in Game.SPIRE_DEFS.size(): # from the tag set, never the count
			var smt := "spire_%d" % smi
			if sm & (1 << smi):
				game.spires_done[smt] = true
			else:
				game.spires_done.erase(smt)
	game.tod = clampf(Game._f(tod, game.tod), 0.0, 24.0) # the host's clock owns the sky — a NaN/INF tod still can't reach it
	game.day = maxi(Game._i(day), 1)
	game.net_danger = danger == true # raids are host truth; the drone mirrors it
	var w := str(weather)
	if w in ["clear", "rain", "storm", "drought"]:
		game.weather = w
	# bq always rides the packet — an empty one means "no posting", not
	# "keep the old world's quest" (absent-on-wire is not keep-local)
	game.board_quest = {"kind": str(bq.get("kind", "supply")), "id": str(bq.get("id", "")),
		"n": Game._i(bq.get("n", 0)), "day": Game._i(bq.get("day", -1), -1),
		"sp": str(bq.get("sp", "")), "got": Game._i(bq.get("got", 0))}
	# the wandering trader rides the same tick — position only; the
	# briefcase travels stock_sync, the till stays host-side
	game.net_merchant_apply(merch.get("on") == true,
		Game._f(merch.get("x", 0.0)), Game._f(merch.get("y", 0.0)))
	if wmode >= 0: # work-mode flips belong to the island, not the caller
		game.work_mode = clampi(int(wmode), 0, game.WORK_MODES.size() - 1)
	if not unl.is_empty(): # mid-session research reaches guests inside a tick
		game.net_unlocked = unl.duplicate()

@rpc("authority", "call_remote", "unreliable")
func peer_pos(id: int, x: float, y: float, elev: float) -> void:
	if not (is_finite(float(x)) and is_finite(float(y)) and is_finite(float(elev))):
		return
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(float(x), float(y), float(elev))

func _on_connection_failed() -> void:
	# a dead dial isn't a session — free the peer so net_live()/retry stay honest
	is_host = false
	multiplayer.multiplayer_peer = null
	pending_pays.clear() # unpaid claims die with the dial — never settle them into a later session
	game.chest_ref = null # no chest was ever reached — the ref would mislead the next session
	mount_pending = false # the mount handshake died with the dial too
	mount_pending_uid = -1
	unbind_retry_t = 0.0
	board_paid_out = ""
	game.log_msg(tr("No host answered — check the address"))

func _on_server_disconnected() -> void:
	for gid in ghosts.keys(): # frozen ghosts shouldn't outlive the session
		if is_instance_valid(ghosts[gid]):
			ghosts[gid].queue_free()
	ghosts.clear()
	game.clear_net_drops() # replica loot dies with the session too
	game.purge_replicas() # statue kin can't linger as free catches post-session
	mount_pending = false # the mount handshake died with the wire
	mount_pending_uid = -1
	unbind_retry_t = 0.0
	board_paid_out = ""
	game.net_merchant_apply(false, 0.0, 0.0) # the mirrored trader leaves with the host
	game.merchant_hp = 0
	game.merchant_wanted = false
	game.party.clear() # host-uid party strip — dead references, not your roster
	game.net_party = [] # the mirrors were the host's truth — stop showing them
	game.net_box = []
	game.net_unlocked = []
	pending_pays.clear() # in-flight pays die as a loss — refunding locally would
	# mint goods the host may already have banked (loss, never mint)
	game.chest_ref = null # a chest open at drop can't follow into the next session
	is_host = false
	multiplayer.multiplayer_peer = null # a dead peer must not keep net_live() true
	game.net_danger = false # the raid verdict belonged to the session — rejoin clean
	game.crowned = false # the borrowed campaign spine leaves with the host —
	game.accord = false # a residue world never fields the host's sixth slot
	game.spires_done.clear() # borrowed marks die with the session too
	game.net_spires = 0 # nor tallies the host's spires/heirs as its own
	game.net_den = 0
	game.log_msg(tr("Host disconnected"))

func spawn_ghost(id: int) -> void:
	if ghosts.has(id):
		return # a reused peer id must not stack a second ghost
	if ghosts.size() >= MAX_PEERS:
		return # a forged peer_joined can't mint ghost nodes past the lobby cap
	var g := preload("res://src/ghost.gd").new()
	g.game = game
	entity_layer.add_child(g)
	ghosts[id] = g
	game.log_msg(tr("Player %d joined") % id)

@rpc("authority", "call_remote", "reliable")
func world_sync(s: int) -> void:
	game.regenerate(int(s))
	game.net_residue = true # this world came down the wire — a dropped session must not save it
	game.log_msg(tr("Synced world seed %d") % int(s))
	_arrive_guest()

func _arrive_guest() -> void: # a title-screen join lands IN the world, not on the menu
	if game.state == "title" and not is_host:
		game.state = "play"

@rpc("any_peer", "call_remote", "unreliable")
func sync_pos(x: float, y: float, elev: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host and id != 1:
		return # another guest's position arrives via the host's peer_pos relay — direct claims are noise
	if not ghosts.has(id):
		return
	var g = ghosts[id]
	if is_host:
		# packet-rate cap, separate from the distance bucket: a flood of
		# bucket-conformant baby steps still forces a relay per packet —
		# the cap starves the amplification before the claims are read
		var now0: float = Time.get_ticks_msec() / 1000.0
		var pps: float = minf(float(g.get_meta("pos_pps", POS_PPS_BURST)) \
			+ (now0 - float(g.get_meta("pos_pps_t", now0))) * POS_PPS, POS_PPS_BURST)
		g.set_meta("pos_pps_t", now0)
		if pps < 1.0:
			return
		g.set_meta("pos_pps", pps - 1.0)
	var nx := float(x); var ny := float(y); var nz := float(elev)
	if not (is_finite(nx) and is_finite(ny) and is_finite(nz)):
		return # NaN/infinity coordinates are not a place anyone can stand
	if nx < 0.0 or ny < 0.0 or nx >= World.WORLD_W or ny >= World.WORLD_H:
		return # every proximity gate trusts this position — keep it inside the island
	if g.net_pos.x < 0:
		# the first fix is where the join actually materializes — spawn, or a
		# pad beside it. Anything else stays -1 and keeps failing every gate.
		# The HOST's own avatar is the authority itself — it can't spoof itself,
		# and gating it strands it invisible anywhere past spawn+12
		if not is_host and id == 1:
			g.net_pos = Vector3(nx, ny, nz)
			return
		var sp := Vector2(game.world.spawn) + Vector2(0.5, 0.5)
		if Vector2(nx, ny).distance_to(sp) > 12.0 and _near_travel_node(Vector2(nx, ny)) == "":
			return
	elif not (not is_host and id == 1):
		# token-bucket speed cap: allowance accrues at POS_RATE tiles/sec up to
		# POS_BURST, so honest packets (and lossy-network clumping) always fit
		# while sustained spoofed walking converges to the cap — and legit big
		# moves (waypoint hops, death respawns) take the shaped blink lane.
		# Host packets on a client skip this entirely — authority positions are
		# truth, and a host teleport policed by the guest bucket freezes its
		# ghost until it drifts back into range
		var now: float = Time.get_ticks_msec() / 1000.0
		var allow: float = minf(float(g.get_meta("pos_allow", POS_BURST)) \
			+ (now - float(g.get_meta("pos_t", now))) * POS_RATE, POS_BURST)
		var step := Vector2(nx, ny).distance_to(Vector2(g.net_pos.x, g.net_pos.y))
		if step > allow and not _legit_blink(g, Vector2(g.net_pos.x, g.net_pos.y), Vector2(nx, ny)):
			g.set_meta("pos_t", now) # time accrues even when a spoof dies at the door
			g.set_meta("pos_allow", allow)
			return # a jump this big that lands on no pad is a spoofed anchor
		g.set_meta("pos_t", now)
		g.set_meta("pos_allow", allow - minf(step, allow))
	# a blink drains the bucket too: a guest that just teleported has no
	# honest need to be sprinting the very next frame
	g.net_pos = Vector3(nx, ny, clampf(nz, -1.0, 8.0))
	if is_host and multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc("peer_pos", id, nx, ny, g.net_pos.z)  # relay the CLAMPED z, not the claim — and only onto a live wire

const BLINK_RADIUS := 5.0 # landing tolerance: nearest_free can shove a few tiles
const POS_RATE := 40.0 # mounted sprint peaks ~29 u/s; cap leaves 38% headroom
const POS_BURST := 6.0 # absorbs ~5 dropped 20Hz packets before honest steps clip
const BLINK_CD := 3.0 # home-lane cooldown — deaths are minutes apart, not seconds
const POS_PPS := 45.0 # honest senders fire ~20-30Hz; the cap admits that + jitter
const POS_PPS_BURST := 60.0 # absorbs a burst without letting a flood through

var _tn_stamp := -1
var _tn_t := 0.0
var _tn_cells := {}
func _travel_cells() -> Dictionary:
	# the blink-pad census is O(structures) — rebuild on count change or a
	# 3s TTL so a same-count swap still converges, not per spoofed packet
	var now: float = Time.get_ticks_msec() / 1000.0
	if _tn_stamp != game.structures.size() or now - _tn_t > 3.0:
		_tn_stamp = game.structures.size()
		_tn_t = now
		_tn_cells.clear()
		for k in game.structures:
			var st = game.structures[k]
			if st["id"] == "waypoint" or st["id"] == "kinbox":
				_tn_cells[k] = st["id"]
	return _tn_cells

func _near_travel_node(p: Vector2) -> String:
	# waypoint stones and kinbox terminals are the only sanctioned blink pads —
	# the same set the travel panel offers
	var cells := _travel_cells()
	for k in cells:
		if p.distance_to(Vector2(k.x + 0.5, k.y + 0.5)) <= BLINK_RADIUS:
			return cells[k]
	return ""

func _legit_blink(g, from: Vector2, to: Vector2) -> bool:
	# a big jump is only honest when it lands where the game's own teleports do
	var dst := _near_travel_node(to)
	if dst == "kinbox" or \
			to.distance_to(Vector2(game.world.spawn) + Vector2(0.5, 0.5)) <= BLINK_RADIUS:
		# respawns come from wherever death found the keeper — but a home-blink
		# is also the cheapest escape, so the free lane gets a cooldown
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - float(g.get_meta("blink_t", -60.0)) < BLINK_CD:
			return false
		g.set_meta("blink_t", now)
		return true
	# waypoint hops have a visible departure too — the stone you stood on
	return dst == "waypoint" and _near_travel_node(from) != ""

var _guest_atk_cap := 0.0
func guest_atk_cap() -> float:
	# honest ceiling for a guest's damage claim: the best forgeable weapon,
	# a lv60 keeper, a maxed atk statue (5), two +12% trinkets, a +10%
	# partner aura and a cooked meal. Anything past this is a mod, not a build.
	if _guest_atk_cap <= 0.0:
		var wmax := 0.0
		for iid in ItemData.ITEMS:
			var wd: Dictionary = ItemData.ITEMS[iid].get("weapon", {})
			wmax = maxf(wmax, float(wd.get("dmg", 0)))
		_guest_atk_cap = (wmax * 2.0 + 60 * 4.0) * (1.0 + 5 * 0.08 + 0.24 + 0.10 + 0.15)
	return _guest_atk_cap

@rpc("any_peer", "call_remote", "unreliable")
func pal_hit(nid: int, dmg: float, sleep_s: float = 0.0) -> void:
	# Client→host combat relay: a client's swing lands on the host's real kin.
	# The wire id IS the host uid (clients mirror it into net_id) — find_pal,
	# not find_net_pal: host-side kin carry net_id=0.
	if not is_host:
		return
	var p := game.find_pal(int(nid))
	if p == null or p.hp <= 0 or p.mode != "wild":
		return # guests can fight the wilds — not another keeper's roster or base crew
	var pid := multiplayer.get_remote_sender_id()
	var gp = ghosts.get(pid)
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(p.pos) > 8.0:
		return # fail closed: the swing has to come from somewhere real
	if not is_finite(dmg) or not is_finite(sleep_s):
		return # NaN slips past every comparison — clampf passes it and int(NaN) poisons hp
	if float(dmg) <= 0.0 and float(sleep_s) <= 0.0:
		return # a 0-damage claim still wakes tranq'd kin and pulls aggro — pure grief
	if not _throttle(pid, "hit_bkt", 3.0, 6.0):
		return # honest swings top out ~2.2/s — a 60Hz claim feed is a script
	var bound := Combat.damage(guest_atk_cap(), 34.0,
		Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus * p.def_mult(),
		2.2, game.rng) # the honest build ceiling against THIS target's def
	p.hit(clampf(float(dmg), 0.0, minf(bound * 1.3, 250.0)), 1.0, false, pid)
	# the guest who swung takes the aggro — the host doesn't tank remote blows
	if sleep_s > 0.0 and p.hp > 0:
		game.apply_sleep_claim(p, clampf(float(sleep_s), 0.5, 15.0))

@rpc("any_peer", "call_remote", "reliable")
func sphere_catch(nid: int, sid: String, behind: bool, cap_lv: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "catch_bkt", 0.7, 1.0):
		return # honest throws pay flight+wobble seconds — not one per frame
	# cap_lv honest range is 1..6 — capture_level = 1 + statue(≤5)
	game.net_catch(int(nid), str(sid), behind == true, clampi(int(cap_lv), 1, 6), pid)

# Ground loot rides the same 2Hz broadcast as kin. A client never owns a
# drop: it walks over a replica, asks with take_drop, and the host pays out
# with got_loot — dids are monotonic so a recycled slot can't be re-looted.
func drop_state_pack() -> Array:
	var arr := []
	for d in game.drops:
		if not d.has("did"): # pre-drop-sync saves load without one — re-key it
			d["did"] = game.next_drop_id
			game.next_drop_id += 1
		arr.append([d["did"], d["id"], d["n"], d["pos"].x, d["pos"].y])
	return arr

@rpc("authority", "call_remote", "unreliable")
func drop_sync(arr: Array) -> void:
	if is_host:
		return
	game.drop_sync(arr)

@rpc("any_peer", "call_remote", "reliable")
func take_drop(did: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	var gp = ghosts.get(pid)
	if gp == null:
		return # a ghostless sender buys nothing — not even the drops loop
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return # loot mashing is human; a per-frame vacuum is a script
	for d in game.drops:
		if d.get("did", -1) != int(did):
			continue
		if Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(d["pos"]) > 2.5:
			return # fail closed: loot needs a witnessed ghost within arm's reach
		var id := String(d["id"]); var n := int(d["n"])
		game.take_drop(d)
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "got_loot", id, n)
		return

@rpc("authority", "call_remote", "reliable")
func got_loot(id: String, n: int) -> void:
	var it: Dictionary = ItemData.ITEMS.get(str(id), {})
	if it.is_empty():
		return
	var ln := clampi(n, 0, 999) # a negative echo drains the bag — loot only ever adds
	game.add_item(str(id), ln)
	game.floater(game.player.pos, tr("+%d %s") % [ln, tr(str(it.get("name", id)))], "#ffe08a")

# Shared-world editing: clients ask, the host validates + mutates, everyone
# converges on the next broadcast. Same trust rules as take_drop — the
# sender's ghost must actually be standing near the thing it touches.
func struct_state_pack() -> Array:
	var seen := []
	var arr := []
	for k in game.structures:
		var st = game.structures[k]
		if st not in seen:
			seen.append(st)
			var o: Vector2i = st.get("pos", k) # origin cell — the wire key
			arr.append([st["id"], o.x, o.y, st.get("store", {}),
				game.struct_wire_state(st)])
	return arr

@rpc("authority", "call_remote", "unreliable")
func struct_sync(arr: Array) -> void:
	if is_host:
		return
	game.struct_sync(arr)

@rpc("authority", "call_remote", "unreliable")
func decor_delta(arr: Array) -> void:
	if is_host:
		return
	game.decor_sync(arr)

@rpc("any_peer", "call_remote", "reliable")
func harvest_req(tx: int, ty: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	game.net_harvest(int(tx), int(ty), pid)

@rpc("any_peer", "call_remote", "reliable")
func build_req(sid: String, tx: int, ty: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "build_bkt", 0.7, 1.0):
		_pay_rej(pid, "build") # materials were paid at click — a silent drop eats them
		return # one blueprint per breath — a fill script can't pave the island
	if not game.unlocked.has(str(sid)):
		# an honest client CAN out-tech the host (developed save joins fresh
		# host) — deny + refund; bags are client-authoritative anyway so a
		# forger gains nothing either way
		_pay_rej(pid, "build")
		return
	if game.net_place(str(sid), int(tx), int(ty), pid):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "build_done", str(sid)) # planted — the hold settles, materials stay spent
	else:
		_pay_rej(pid, "build") # site contested mid-click — the hold refunds

@rpc("authority", "call_remote", "reliable")
func build_done(_sid: String) -> void:
	if is_host:
		return
	pay_settle("build", false) # the ledger releases the hold — the island keeps the goods

@rpc("any_peer", "call_remote", "reliable")
func demolish_req(tx: int, ty: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "dem_bkt", 1.0, 1.0):
		return # razing is deliberate — a sweep script gets one refusal per beat
	game.net_demolish(int(tx), int(ty), pid)

@rpc("any_peer", "call_remote", "reliable")
func chest_req(op: String, tx: float, ty: float, payload: Dictionary = {}) -> void:
	if not is_host:
		return
	if not is_finite(tx) or not is_finite(ty):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "chest_bkt", 1.0, 1.0):
		if str(op) == "dep":
			_pay_rej(pid, "chest_dep")
		return # a bulk-macro gets one container op per beat
	var cell := Vector2i(int(tx), int(ty))
	var res := game.chest_req_remote(pid, cell, str(op), payload)
	if res.is_empty():
		if str(op) == "dep":
			_pay_rej(pid, "chest_dep") # refused AFTER payment — refund it
		return # refused — nothing moved, nothing to echo
	if multiplayer.get_peers().has(pid):
		rpc_id(pid, "chest_grant" if str(op) == "wd" else "chest_took",
			int(tx), int(ty), res)
	elif str(op) == "wd": # the keeper vanished mid-reach — goods go back, not to the void
		var st2 = game.structures.get(cell)
		if st2 != null:
			for id in res:
				st2["store"][id] = int(st2["store"].get(id, 0)) + int(res[id])
	# dep: goods already reached the shared store — a vanished keeper just
	# never hears the ack, which is fine: the truth moved, the echo is a nicety

@rpc("authority", "call_remote", "reliable")
func chest_grant(_tx: int, _ty: int, items: Dictionary) -> void:
	if is_host:
		return
	var n := 0
	for id in items:
		var iid := str(id)
		if not ItemData.ITEMS.has(iid):
			continue # forged ids don't get bag keys
		var c := clampi(Game._i(items[id]), 0, 999)
		game.add_item(iid, c)
		n += c
	game.log_msg(tr("Took %d items") % n)

@rpc("authority", "call_remote", "reliable")
func chest_took(_tx: int, _ty: int, items: Dictionary) -> void:
	if is_host:
		return
	# the host accepted an intersection of our claim — the gap between what
	# left the bag and what landed in the chest comes back, or goods vanish
	for i in pending_pays.size():
		if pending_pays[i]["tag"] == "chest_dep":
			for id in pending_pays[i]["cost"]:
				var gap: int = Game._i(pending_pays[i]["cost"][id]) - Game._i(items.get(id, 0))
				if gap > 0:
					game.add_item(str(id), gap)
			break
	pay_settle("chest_dep", false) # goods left the bag when the request flew
	var n := 0
	for id in items:
		n += maxi(Game._i(items[id]), 0)
	game.log_msg(tr("Stored %d items") % n)

@rpc("any_peer", "call_remote", "reliable")
func bait_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "bait_done", false) # the bait left the bag on the click — the hold refunds it
		return
	var landed := game.throw_bait_remote(pid) # the pile lands under the ghost the wire saw
	if multiplayer.get_peers().has(pid):
		rpc_id(pid, "bait_done", landed) # settle or refund — a hold never hangs

@rpc("authority", "call_remote", "reliable")
func bait_done(ok: bool) -> void:
	if is_host:
		return
	pay_settle("bait", not ok) # a landed pile keeps the bait; a miss refunds the hold
	if not ok:
		game.log_msg(tr("The bait came back — the island didn't hear it"))

@rpc("any_peer", "call_remote", "reliable")
func fish_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "fish_bkt", 0.7, 1.0):
		return # the rod needs a beat between casts
	game.cast_line_remote(pid)

@rpc("any_peer", "call_remote", "reliable")
func mimic_req(tx: float, ty: float) -> void:
	if not is_host:
		return
	if not is_finite(tx) or not is_finite(ty):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "chest_bkt", 1.0, 1.0):
		return
	game.mimic_req_remote(pid, Vector2i(int(tx), int(ty)))
	# a real mimic answers itself: the structure despawns on the wire and
	# a mouth charges the asker — no echo needed, the world is the reply

@rpc("any_peer", "call_remote", "reliable")
func fert_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "fert")
		return
	if game.fert_req_remote(pid):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "fert_done")
	else:
		_pay_rej(pid, "fert")

@rpc("authority", "call_remote", "reliable")
func fert_done() -> void:
	if is_host:
		return
	pay_settle("fert", false) # the fertilizer left the bag at request time
	game.log_msg(tr("Fertilizer spread — five minutes of surge"))

@rpc("any_peer", "call_remote", "reliable")
func shrine_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "shrine")
		return
	if game.shrine_req_remote(pid):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "shrine_done", game.weather)
	else:
		_pay_rej(pid, "shrine")

@rpc("authority", "call_remote", "reliable")
func shrine_done(nw: String) -> void:
	if is_host:
		return
	var w2 := str(nw)
	if w2 in ["clear", "rain", "storm", "drought"]: # a forged echo can't paint junk skies
		game.weather = w2 # the offering lands; state_sync would catch up anyway
	pay_settle("shrine", false) # the lumenite left the bag at request time
	game.log_msg(tr("The altar drinks your lumenite — the sky shifts"))

@rpc("any_peer", "call_remote", "reliable")
func work_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	var wm := game.work_req_remote(pid)
	if wm >= 0 and multiplayer.get_peers().has(pid):
		rpc_id(pid, "work_done", wm)

@rpc("authority", "call_remote", "reliable")
func work_done(wm: int) -> void:
	if is_host:
		return
	game.work_mode = clampi(int(wm), 0, game.WORK_MODES.size() - 1)
	var d: Dictionary = game.WORK_MODES[game.work_mode]
	game.log_msg(tr("Monitoring stand: %s pace") % d["name"])

@rpc("any_peer", "call_remote", "reliable")
func sleep_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	if not multiplayer.get_peers().has(pid):
		return
	if not game.is_night():
		rpc_id(pid, "net_note", "Can't sleep — it's not night yet")
	elif game.sleep_req_remote(pid):
		rpc_id(pid, "sleep_done") # the shared day rolls on its own; the SLEEPER'S body is theirs to heal
	else:
		rpc_id(pid, "net_note", "Can't sleep — hostiles are after someone")

@rpc("any_peer", "call_remote", "reliable")
func dig_req(tx: float, ty: float) -> void:
	if not is_host:
		return
	if not is_finite(tx) or not is_finite(ty):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	game.dig_req_remote(pid, Vector2i(int(tx), int(ty)))
	# loot echoes through give_remote inside the remote fn

@rpc("any_peer", "call_remote", "reliable")
func cage_req(tx: float, ty: float) -> void:
	if not is_host:
		return
	if not is_finite(tx) or not is_finite(ty):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	game.cage_req_remote(pid, Vector2i(int(tx), int(ty)))
	# the freed kin arrives through box_sync, owner-sliced to the asker

@rpc("any_peer", "call_remote", "reliable")
func board_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	var res := game.board_action_remote(pid)
	if not res.is_empty() and multiplayer.get_peers().has(pid):
		rpc_id(pid, "board_done", res)

@rpc("authority", "call_remote", "reliable")
func board_done(res: Dictionary) -> void:
	if is_host:
		return
	var qid := str(res.get("id", ""))
	var qn := maxi(Game._i(res.get("n", 0)), 0) # a negative ask would mint goods through add_item
	if not ItemData.ITEMS.has(qid):
		return # a forged ask can't deduct ids the board never posts
	if qid != str(game.board_quest.get("id", "")):
		return # the ask must match the mirrored posting — a crafted echo can't invent one
	qn = mini(qn, int(game.board_quest.get("n", 0))) # and can't bill past it
	# the bag pays its goods first, then asserts it — gold arrives via
	# board_paid once the host sees the settlement claim
	if qid == board_paid_out:
		return # already asserted — a re-shown ask can't double-deduct while the gold echo flies
	if game.item_count(qid) < qn:
		game.log_msg(tr("Notice board: the goods weren't in your pack"))
		rpc("board_release", qid) # a leaf client's only remote is the host — an honest miss frees the board early
		return
	game.add_item(qid, -qn)
	board_paid_out = qid
	rpc("board_paid", qid) # tell the host the goods left our pack

@rpc("any_peer", "call_remote", "reliable")
func board_release(qid: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	# no bucket on a release either — board_release_remote self-guards on the
	# holder's pid, and a starved release squats the ask for its 15s freshness
	game.board_release_remote(pid, str(qid))

@rpc("any_peer", "call_remote", "reliable")
func board_paid(qid: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	# no bucket on a settle: board_paid_remote self-guards (pid+id must match
	# the live hold, and the first success erases it) — a starved settle would
	# eat goods the keeper already shipped. Spam buys a dict lookup, nothing else
	var res := game.board_paid_remote(pid, str(qid))
	if not res.is_empty():
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "board_pay", int(res["gold"]), int(res["xp"]))
	elif multiplayer.get_peers().has(pid):
		rpc_id(pid, "board_rej", str(qid)) # the hold died — free the client's assert flag

@rpc("authority", "call_remote", "reliable")
func board_rej(qid: String) -> void:
	if is_host:
		return
	if str(qid) == board_paid_out:
		board_paid_out = "" # the hold died host-side — the ask may claim it fresh
		game.log_msg(tr("Notice board: the posting was already gone"))

@rpc("authority", "call_remote", "reliable")
func board_pay(gold: int, xp: int) -> void:
	if is_host:
		return
	board_paid_out = "" # the settlement landed — the next ask may deduct again
	game.add_item("gold_coin", maxi(gold, 0)) # a negative bounty can't drain the purse
	game.gain_xp(maxi(int(xp), 0)) # same bounty math the keeper's own fill pays
	game.log_msg(tr("Board request filled — +%d gold") % maxi(int(gold), 0))

@rpc("authority", "call_remote", "reliable")
func xp_gain(n: int) -> void:
	if is_host:
		return
	game.gain_xp(int(n)) # a keeper's kills pay the keeper — wherever they stand

@rpc("authority", "call_remote", "reliable")
func sleep_done() -> void:
	if is_host:
		return
	# one keeper's bed heals every roster through the shared loops — but the
	# sleeper's own body is local state only they can mend
	game.player.hp = game.player.max_hp

@rpc("any_peer", "call_remote", "reliable")
func mount_req(uid: float) -> void:
	if not is_host:
		return
	if not is_finite(uid):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "mount_done", int(uid), 0) # a starved request still resolves the pending handshake
		return
	var r := game.mount_req_remote(pid, int(uid))
	if multiplayer.get_peers().has(pid):
		rpc_id(pid, "mount_done", int(uid), r) # refusals echo too — a pending bind can't wait forever

@rpc("authority", "call_remote", "reliable")
func mount_done(uid: int, state: int) -> void:
	if is_host:
		return
	var wid := int(uid)
	if mount_pending_uid == wid:
		mount_pending = false # the handshake resolved — mount, dismount, or refuse
		mount_pending_uid = -1
	if int(state) == 1:
		var p := game.find_net_pal(wid)
		if p != null and game.player.mount == null: # a stale bind can't unseat the saddle we already hold
			game.player.mount = p
			p.visible = false # the kin hides — the rider's sprite carries the ride
			game.log_msg(tr("Riding %s") % tr(str(p.spec["name"])))
	elif int(state) == 2 and game.player._mount_guard() and game.player.mount.net_id == wid:
		# host confirms the release — drop the saddle AND show the kin now;
		# a state-0 refusal owns only the handshake, never the saddle
		game.player.mount.visible = true
		game.player.mount = null
		game.log_msg(tr("Dismounted"))

# self-heal: host truth says WE ride this kin while our local ref says we
# don't — an earlier unbind died on the wire (throttle/drop). Ask again,
# bounded to one handshake per cooldown; the verb can't stay wedged.
func _mount_selfheal_check(nid: int, rider: int) -> bool:
	if not is_client() or not game.net_live() or rider != multiplayer.get_unique_id() \
			or mount_pending or unbind_retry_t > 0.0:
		return false
	var p: Kin = game.find_net_pal(nid)
	if p == null or p == game.player.mount:
		return false
	mount_pending = true
	mount_pending_uid = nid
	unbind_retry_t = 2.0
	rpc("mount_req", float(nid))
	return true

@rpc("any_peer", "call_remote", "reliable")
func cond_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	game.condense_remote(pid)

@rpc("any_peer", "call_remote", "reliable")
func egg_req(egg_id: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "egg")
		return
	if game.egg_req_remote(pid, str(egg_id)):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "egg_done", str(egg_id))
	else:
		_pay_rej(pid, "egg")

@rpc("authority", "call_remote", "reliable")
func egg_done(egg_id: String) -> void:
	if is_host:
		return
	pay_settle("egg", false) # the egg left the bag at request time
	game.log_msg(tr("Egg in the incubator — 90s to hatch"))

@rpc("any_peer", "call_remote", "reliable")
func gacha_req() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "gacha")
		return
	var eid := game.gacha_req_remote(pid)
	if eid == "":
		_pay_rej(pid, "gacha") # reach refused — the gold hold comes home
	elif multiplayer.get_peers().has(pid):
		rpc_id(pid, "gacha_done", eid)

@rpc("authority", "call_remote", "reliable")
func gacha_done(eid: String) -> void:
	if is_host:
		return
	pay_settle("gacha", false) # the gold stayed in the slot — the egg is ours
	game.log_msg(tr("The gacha rattles — out rolls a %s") \
		% tr(str(ItemData.ITEMS.get(str(eid), {}).get("name", eid))))

@rpc("any_peer", "call_remote", "reliable")
func infuse_req(uid: float) -> void:
	if not is_host:
		return
	if not is_finite(uid):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "infuse")
		return
	var cost := game.infuse_req_remote(pid, int(uid))
	if cost > 0:
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "infuse_done", float(uid), cost)
	else:
		_pay_rej(pid, "infuse")

@rpc("authority", "call_remote", "reliable")
func infuse_done(uid: float, cost: int) -> void:
	if is_host:
		return
	var held := pay_hold("infuse") # settle against the recorded burn, not the wire's number
	pay_settle("infuse", true) # refund the optimistic burn…
	var true_cost := maxi(cost, 0)
	if held.has("sprigmelt_effigy"):
		true_cost = mini(true_cost, int(held["sprigmelt_effigy"]))
	game.add_item("sprigmelt_effigy", -true_cost) # …then charge the host's truth — a negative cost mints effigies
	var p: Kin = game.find_net_pal(int(uid))
	if p != null:
		p.soul_boost = mini(p.soul_boost + 1, 10) # the mirror learns what the wire doesn't carry — capped like the real verb
	game.log_msg(tr("The offering burns — a soul burns brighter"))

@rpc("any_peer", "call_remote", "reliable")
func fruit_req(item_id: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "fruit")
		return
	if game.fruit_req_remote(pid, str(item_id)):
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "fruit_done", str(item_id))
	else:
		_pay_rej(pid, "fruit")

@rpc("authority", "call_remote", "reliable")
func fruit_done(item_id: String) -> void:
	if is_host:
		return
	pay_settle("fruit", false) # the fruit left the bag at request time

# Shared box: the host's kinbox is the one real roster. Clients get a
# lightweight mirror (uid/species/level/vitals, no Kin nodes) and their
# kinbox clicks travel back as box_req ops the host validates + runs.
var box_sig := -1
var box_resend := 0.0

func box_fingerprint() -> int:
	var h := game.box.size() * 131 + game.party.size() * 7919
	for bp in game.box:
		h = (h * 31 + bp.uid + int(bp.hp) + bp.owner_id + (1 if bp.fav else 0) \
			+ bp.star * 131 + int(bp.level) * 17) & 0x7FFFFFFF
	for bb in game.bench:
		h = (h * 31 + bb.uid + int(bb.hp) + bb.owner_id + bb.star * 131) & 0x7FFFFFFF
	for u in game.party:
		h = (h * 17 + int(u)) & 0x7FFFFFFF
	var out := game.party_pal()
	if out != null:
		h = (h * 13 + int(out.hp)) & 0x7FFFFFFF
	for p2 in game.pals: # a guest's field pal is part of their strip's truth
		if p2.mode == "partner":
			h = (h * 13 + p2.owner_id * 7 + int(p2.hp)) & 0x7FFFFFFF
	for tag in game.remote_parties:
		for u2 in game.remote_parties[tag]:
			h = (h * 17 + int(u2) + str(tag).hash()) & 0x7FFFFFFF
	return h

func box_state_pack(pid: int) -> Array:
	var arr := []
	for bp in game.box:
		if bp.owner_id != pid:
			continue # a guest sees their own roster, nobody else's
		arr.append([bp.uid, bp.species_id, bp.level, int(bp.hp), int(bp.max_hp),
			bp.sex, bp.lucky, bp.talent, str(bp.ailment), bp.fav, int(bp.star),
			game.work_str(bp.spec)])
	return arr

func party_state_pack(pid: int) -> Array:
	# the client's party strip: every party member in order — the out kin and
	# the benched orbs alike (bench kin have no world replica to read)
	var arr := []
	var out_pal: Kin = game.party_pal() if pid == 0 else game.r_out_pal(pid)
	var uids: Array = game.party if pid == 0 else game.rparty_for(pid)
	for u in uids:
		var p: Kin = game.find_pal(u)
		if p == null:
			p = game.bench_pal_of(u)
		if p == null:
			continue
		arr.append([p.uid, p.species_id, p.level, int(p.hp), int(p.max_hp),
			p.sex, p.lucky, p.talent, str(p.ailment), p.fav, int(p.star),
			p == out_pal, p.stance, game.work_str(p.spec)])
		if arr.size() >= 8:
			break
	return arr

@rpc("authority", "call_remote", "unreliable")
func box_sync(arr: Array, pty: Array, prows: Array = []) -> void:
	if is_host:
		return
	var nb := []
	for e in arr:
		if not (e is Array) or e.size() < 5 or not Game._fin(e[0]):
			continue
		nb.append({"uid": Game._i(e[0]), "sid": str(e[1]), "lv": clampi(Game._i(e[2]), 1, 60),
			"hp": maxi(0, Game._i(e[3])), "max_hp": maxi(1, Game._i(e[4])),
			"sex": "F" if e.size() > 5 and str(e[5]) == "F" else "M",
			"lucky": e.size() > 6 and e[6] == true,
			"talent": clampi(Game._i(e[7]) if e.size() > 7 else 50, 0, 100),
			"ailment": str(e[8]) if e.size() > 8 else "",
			"fav": e.size() > 9 and e[9] == true,
			"star": clampi(Game._i(e[10]) if e.size() > 10 else 0, 0, 4),
			"wk": str(e[11]) if e.size() > 11 else ""})
		if nb.size() >= 512: # hostile/hostile host can't stuff memory either
			break
	game.net_box = nb
	var np := []
	for e2 in prows:
		if not (e2 is Array) or e2.size() < 5 or not Game._fin(e2[0]):
			continue
		np.append({"uid": Game._i(e2[0]), "sid": str(e2[1]), "lv": clampi(Game._i(e2[2]), 1, 60),
			"hp": maxi(0, Game._i(e2[3])), "max_hp": maxi(1, Game._i(e2[4])),
			"sex": "F" if e2.size() > 5 and str(e2[5]) == "F" else "M",
			"lucky": e2.size() > 6 and e2[6] == true,
			"talent": clampi(Game._i(e2[7]) if e2.size() > 7 else 50, 0, 100),
			"ailment": str(e2[8]) if e2.size() > 8 else "",
			"fav": e2.size() > 9 and e2[9] == true,
			"star": clampi(Game._i(e2[10]) if e2.size() > 10 else 0, 0, 4),
			"out": e2.size() > 11 and e2[11] == true,
			"stance": str(e2[12]) if e2.size() > 12 else "auto",
			"wk": str(e2[13]) if e2.size() > 13 else ""})
		if np.size() >= 8:
			break
	game.net_party = np
	game.party.clear() # typed Array[int] — a plain Array won't assign
	for u in pty:
		if Game._fin(u) and not game.party.has(int(u)):
			game.party.append(int(u))
		if game.party.size() >= game.party_cap(): # same strip bound the save path enforces
			break

@rpc("any_peer", "call_remote", "reliable")
func box_req(op: String, uid: int, extra := "") -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	# every roster is private — the op lands only if the kin answers to the sender
	game.box_op_remote(str(op), int(uid), pid, str(extra))

@rpc("any_peer", "call_remote", "reliable")
func buy_req(idx: float) -> void:
	if not is_host:
		return
	if not is_finite(idx):
		return # int(NaN) is 0 — an index claim must be a real number first
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		_pay_rej(pid, "buy")
		return
	var res := game.buy_remote(pid, int(idx))
	if res.is_empty():
		_pay_rej(pid, "buy")
		return
	if multiplayer.get_peers().has(pid):
		rpc_id(pid, "bought", res)
		rpc("stock_sync", game.merchant_stock) # every watcher sees the shelf thin

@rpc("authority", "call_remote", "reliable")
func bought(res: Dictionary) -> void:
	if is_host:
		return
	var held := pay_hold("buy") # the ledger remembers what we actually burned
	pay_settle("buy", true) # refund the mirrored price…
	var price := maxi(Game._i(res.get("price", 0)), 0)
	if held.has("gold_coin"):
		price = mini(price, int(held["gold_coin"])) # an echo can't bill past the recorded hold
	game.add_item("gold_coin", -price) # …then pay the host's truth — a negative price would mint gold
	game.log_msg(tr("Bought %s (%dg)") % ["a kin" if res.has("kin") else "goods",
		Game._i(res.get("price", 0))])

@rpc("authority", "call_remote", "reliable")
func stock_sync(stock: Array) -> void:
	if is_host:
		return
	game.merchant_stock.clear()
	for it in stock: # the shelf is display-only — buys still validate host-side
		if not (it is Dictionary):
			continue
		if str(it.get("kin", "")) != "": # black-market kin row — species whitelisted
			var sid := str(it["kin"])
			if SpeciesData.species_of(sid).is_empty():
				continue
			game.merchant_stock.append({"kin": sid,
				"lv": clampi(Game._i(it.get("lv", 1)), 1, 60), "n": 1,
				"price": maxi(0, Game._i(it.get("price", 0)))})
		elif str(it.get("id", "")) != "" and ItemData.ITEMS.has(str(it["id"])):
			game.merchant_stock.append({"id": str(it["id"]),
				"n": clampi(Game._i(it.get("n", 1)), 0, 999),
				"price": maxi(0, Game._i(it.get("price", 0)))})
		if game.merchant_stock.size() >= game.MAX_MERCH_STOCK:
			break # a hostile pack can't stuff the shelf past its cap

@rpc("any_peer", "call_remote", "reliable")
func merch_hit(dmg: float) -> void:
	if not is_host:
		return
	if not is_finite(dmg):
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "hit_bkt", 3.0, 6.0):
		return
	if game.merchant == null or not game._ghost_reaches(pid, game.merchant.pos, 2.5):
		return # melee reach — a rifle-length beating is a forged swing
	game.hit_merchant(clampf(float(dmg), 0.0, 80.0), pid)

@rpc("any_peer", "call_remote", "reliable")
func assign_req(x: float, y: float) -> void:
	if not is_host:
		return
	if not is_finite(x) or not is_finite(y):
		return # NaN slips every distance check — the gate is the first line
	var pid := multiplayer.get_remote_sender_id()
	if not _throttle(pid, "act_bkt", 8.0, 10.0):
		return
	var at := Vector2(clampf(float(x), 0.0, game.world.WORLD_W), clampf(float(y), 0.0, game.world.WORLD_H))
	var gp = ghosts.get(pid)
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(at) > 8.0:
		return # a hand can't post a pal it isn't standing next to
	game.assign_remote(pid, at)

var chat_last := {} # pid -> last relay time — one spammer can't starve the table
@rpc("any_peer", "call_remote", "unreliable")
func chat(t: String, from_id: int = 0) -> void:
	# the claimed sender is a lie — the wire's sender_id is the only honest id
	var real_from: int = multiplayer.get_remote_sender_id()
	if real_from == 0: # local call (own echo / host-originated line)
		real_from = from_id
	if real_from == multiplayer.get_unique_id():
		return # the server relayed your own line back — hud already echoed it
	if int(from_id) == multiplayer.get_unique_id():
		return # my own line came back through the relay — don't double-print it
	var line: String = str(t).left(160) # the log window can't hold a novel
	if multiplayer.is_server():
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - float(chat_last.get(real_from, -9.0)) < 0.25:
			return # a spamming peer gets one relay per beat — and no log line either
		chat_last[real_from] = now
	game.log_msg(tr("[friend] ") + line)
	if multiplayer.is_server():
		rpc("chat", line, int(real_from)) # ENet is a star: relay to other clients

var pal_sync_t := 0.0

func _process(dt: float) -> void:
	unbind_retry_t = maxf(0.0, unbind_retry_t - dt) # cools even mid-tear — a half-dead session still drains it
	if multiplayer.multiplayer_peer == null or ghosts.is_empty():
		return
	if is_host:
		pal_sync_t += dt
		if pal_sync_t >= 0.5: # 2Hz — pals drift slowly; anything faster is noise
			pal_sync_t = 0.0
			rpc("pal_sync", pal_state_pack())
			rpc("drop_sync", drop_state_pack())
			rpc("struct_sync", struct_state_pack())
			var mp2 := {}
			if game.merchant != null and is_instance_valid(game.merchant):
				mp2 = {"on": true, "x": game.merchant.pos.x, "y": game.merchant.pos.y}
			var bq_send := {"kind": game.board_quest.get("kind", ""), "id": game.board_quest.get("id", ""),
				"n": game.board_quest.get("n", 0), "day": game.board_quest.get("day", -1),
				"sp": game.board_quest.get("sp", ""), "got": game.board_quest.get("got", 0)}
			var spire_sm := 0 # WHICH spires fell rides too — a guest's map needs hollow markers, not just a tally
			for smi in Game.SPIRE_DEFS.size():
				if game.spires_done.has("spire_%d" % smi):
					spire_sm |= 1 << smi
			rpc("env_sync", game.tod, game.day, game.weather, game.danger_active(),
				bq_send, mp2, game.work_mode, game.unlocked,
				game.crowned, game.accord,
				game.spires_done.size(), game.den_caught(), spire_sm) # clock + sky + threat + posting + trader + orders + tech + the campaign spine are host truth — the holder's pid stays home
			box_resend -= 0.5
			var sig := box_fingerprint()
			if sig != box_sig or box_resend <= 0.0: # box rosters ride diffs, not a 2Hz firehose
				box_sig = sig
				box_resend = 15.0
				for pid in multiplayer.get_peers(): # each keeper opens their own box
					rpc_id(pid, "box_sync", box_state_pack(pid), game.rparty_for(pid).duplicate(), party_state_pack(pid))
			var dd := game.dirty_decor_pack()
			if not dd.is_empty():
				rpc("decor_delta", dd)
	send_timer += dt
	if send_timer < 0.05:
		return
	send_timer = 0.0
	var p: Player = game.player
	rpc("sync_pos", p.pos.x, p.pos.y, p.elev())
