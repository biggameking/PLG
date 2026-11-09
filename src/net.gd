extends Node
class_name Net

# LAN co-op scaffold: host shares world seed, peers see each other as ghost
# players. Pals/combat remain locally authoritative for now (sync them next).

const PORT := 7777
var game: Game
var entity_layer: Node2D
var ghosts := {}  # peer_id -> Node2D
var send_timer := 0.0
var is_host := false

func setup(g: Game, layer: Node2D) -> void:
	game = g
	entity_layer = layer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT) != OK:
		game.log_msg("Host failed: port %d busy" % PORT)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	game.log_msg("Hosting on port %d — friends join with K" % PORT)

func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		game.log_msg("Join failed")
		return
	multiplayer.multiplayer_peer = peer
	game.log_msg("Joining %s:%d ..." % [ip, PORT])

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
	game.log_msg("Connected to host")

func _on_peer_disconnected(id: int) -> void:
	if ghosts.has(id):
		ghosts[id].queue_free()
		ghosts.erase(id)
	if is_host:
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
	# unique structures by origin cell (first-seen order = placement order)
	var seen := []
	var arr := []
	for k in game.structures:
		var st = game.structures[k]
		if st not in seen:
			seen.append(st)
			arr.append([st["id"], k.x, k.y])
	# share the living population too — a joining client should see the same
	# wild/base pals, not an empty world (capped upstream by MAX_PALS)
	var parr := []
	for p in game.pals:
		if p.mode in ["wild", "base"] and p.hp > 0:
			parr.append([p.species_id, p.pos.x, p.pos.y, p.lv, p.mode, p.lucky, p.uid])
	return {"structures": arr, "tod": game.tod, "day": game.day, "pals": parr}

@rpc("authority", "call_remote", "reliable")
func state_sync(d: Dictionary) -> void:
	for e in d.get("structures", []):
		if e is Array and e.size() >= 3 and (e[1] is float or e[1] is int) and (e[2] is float or e[2] is int):
			game.place_free(str(e[0]), int(e[1]), int(e[2])) # net input is untrusted — validate shape
	game.tod = float(d.get("tod", game.tod))
	game.day = int(d.get("day", game.day))
	# drop the population our own regenerate() spawned — the host's wild/base
	# pals replace it, otherwise clients see every pal twice
	for p in game.pals.duplicate():
		if p.mode in ["wild", "base"]:
			game.pals.erase(p)
			p.queue_free()
	var np := 0
	for e in d.get("pals", []):
		var n0 := game.pals.size()
		game.spawn_net_pal(e) # each entry re-validated game-side
		np += 1 if game.pals.size() > n0 else 0
	game.log_msg("Synced %d structures, %d pals" % [d.get("structures", []).size(), np])

# Live pal population: host rebroadcasts positions/health at 2Hz so replicas
# don't just sit where the join snapshot left them. Replicas are keyed by
# host uid (net_id); unknown ids spawn, missing ids despawn — one packet is
# the whole truth, packet loss self-heals on the next tick.
func pal_state_pack() -> Array:
	var arr := []
	for p in game.pals:
		if p.mode in ["wild", "base"] and p.hp > 0:
			arr.append([p.uid, p.species_id, p.pos.x, p.pos.y, p.lv, p.mode, p.hp, p.lucky])
	return arr

@rpc("authority", "call_remote", "unreliable")
func pal_sync(arr: Array) -> void:
	if is_host:
		return # the host's own broadcast echoes back — it's the authority already
	var seen := {}
	for e in arr:
		if not (e is Array) or e.size() < 6 or not (e[0] is float or e[0] is int):
			continue
		var nid := int(e[0])
		seen[nid] = true
		var p := game.find_net_pal(nid)
		if p == null:
			# [species, x, y, lv, mode, lucky, net_id] — spawn_net_pal's wire shape
			game.spawn_net_pal([e[1], e[2], e[3], e[4], e[5],
				e[7] if e.size() > 7 else false, nid])
		else:
			p.net_target = Vector2(float(e[2]), float(e[3]))
			p.hp = maxf(0.0, float(e[6])) if e.size() > 6 else p.hp
	for p in game.pals.duplicate():
		if p.net_id > 0 and not seen.has(p.net_id): # host dropped it: caught, KO'd, despawned
			game.pals.erase(p)
			p.queue_free()

@rpc("authority", "call_remote", "unreliable")
func peer_pos(id: int, x: float, y: float, elev: float) -> void:
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(float(x), float(y), float(elev))

func _on_server_disconnected() -> void:
	for gid in ghosts.keys(): # frozen ghosts shouldn't outlive the session
		if is_instance_valid(ghosts[gid]):
			ghosts[gid].queue_free()
	ghosts.clear()
	game.clear_net_drops() # replica loot dies with the session too
	is_host = false
	game.log_msg("Host disconnected")

func spawn_ghost(id: int) -> void:
	if ghosts.has(id):
		return # a reused peer id must not stack a second ghost
	var g := preload("res://src/ghost.gd").new()
	g.game = game
	entity_layer.add_child(g)
	ghosts[id] = g
	game.log_msg("Player %d joined" % id)

@rpc("authority", "call_remote", "reliable")
func world_sync(s: int) -> void:
	game.regenerate(int(s))
	game.log_msg("Synced world seed %d" % int(s))

@rpc("any_peer", "call_remote", "unreliable")
func sync_pos(x: float, y: float, elev: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(float(x), float(y), float(elev))
	if is_host:
		rpc("peer_pos", id, float(x), float(y), float(elev))  # relay so clients see each other

@rpc("any_peer", "call_remote", "unreliable")
func pal_hit(nid: int, dmg: float) -> void:
	# Client→host combat relay: a client's swing lands on the host's real pal.
	# The wire id IS the host uid (clients mirror it into net_id) — find_pal,
	# not find_net_pal: host-side pals carry net_id=0.
	if not is_host:
		return
	var p := game.find_pal(int(nid))
	if p == null or p.hp <= 0:
		return
	p.hit(clampf(float(dmg), 0.0, 2000.0), 1.0, false)

@rpc("any_peer", "call_remote", "reliable")
func sphere_catch(nid: int, sid: String, behind: bool, cap_lv: int) -> void:
	if not is_host:
		return
	game.net_catch(int(nid), str(sid), behind == true, clampi(int(cap_lv), 1, 10),
		multiplayer.get_remote_sender_id())

# Ground loot rides the same 2Hz broadcast as pals. A client never owns a
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
	for d in game.drops:
		if d.get("did", -1) != int(did):
			continue
		if gp != null and Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(d["pos"]) > 2.5:
			return # teleport-looting: too far to have really walked over it
		var id := String(d["id"]); var n := int(d["n"])
		game.take_drop(d)
		rpc_id(pid, "got_loot", id, n)
		return

@rpc("authority", "call_remote", "reliable")
func got_loot(id: String, n: int) -> void:
	var it: Dictionary = ItemData.ITEMS.get(str(id), {})
	if it.is_empty():
		return
	game.add_item(str(id), int(n))
	game.floater(game.player.pos, "+%d %s" % [int(n), it.get("name", id)], "#ffe08a")

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
			arr.append([st["id"], o.x, o.y])
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
	game.net_harvest(int(tx), int(ty), multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func build_req(sid: String, tx: int, ty: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not game.net_place(str(sid), int(tx), int(ty), pid):
		rpc_id(pid, "build_deny", str(sid)) # the client paid up front — refund the bill

@rpc("authority", "call_remote", "reliable")
func build_deny(sid: String) -> void:
	var s: Dictionary = StructureData.STRUCTURES.get(str(sid), {})
	if s.is_empty():
		return
	for c in s.get("cost", []):
		game.add_item(str(c[0]), int(c[1]))
	game.log_msg("Host refused %s - materials refunded" % s.get("name", sid))

@rpc("any_peer", "call_remote", "reliable")
func demolish_req(tx: int, ty: int) -> void:
	if not is_host:
		return
	game.net_demolish(int(tx), int(ty), multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "unreliable")
func chat(t: String, from_id: int = 0) -> void:
	if from_id == multiplayer.get_unique_id():
		return # the server relayed your own line back — hud already echoed it
	game.log_msg("[friend] " + str(t))
	if multiplayer.is_server():
		rpc("chat", str(t), int(from_id)) # ENet is a star: relay client chat to the other clients

var pal_sync_t := 0.0

func _process(dt: float) -> void:
	if multiplayer.multiplayer_peer == null or ghosts.is_empty():
		return
	if is_host:
		pal_sync_t += dt
		if pal_sync_t >= 0.5: # 2Hz — pals drift slowly; anything faster is noise
			pal_sync_t = 0.0
			rpc("pal_sync", pal_state_pack())
			rpc("drop_sync", drop_state_pack())
			rpc("struct_sync", struct_state_pack())
			var dd := game.dirty_decor_pack()
			if not dd.is_empty():
				rpc("decor_delta", dd)
	send_timer += dt
	if send_timer < 0.05:
		return
	send_timer = 0.0
	var p: Player = game.player
	rpc("sync_pos", p.pos.x, p.pos.y, p.elev())
