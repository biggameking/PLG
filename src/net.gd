extends Node
class_name Net

# LAN co-op scaffold: host shares world seed, peers see each other as ghost
# players. Kin/combat remain locally authoritative for now (sync them next).

const PORT := 7777
var game: Game
var entity_layer: Node2D
var ghosts := {}  # peer_id -> Node2D
var send_timer := 0.0
var is_host := false
var peer_tags := {} # peer_id -> install token — a guest's stable keeper identity

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
	_close_peer() # never swap a live peer — that leaks the session and
	# flips is_client() off, which would open the save gates on a guest
	multiplayer.multiplayer_peer = peer
	is_host = true
	game.log_msg("Hosting on port %d — friends join with K" % PORT)

func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		game.log_msg("Join failed")
		return
	_close_peer()
	is_host = false
	multiplayer.multiplayer_peer = peer
	game.log_msg("Joining %s:%d ..." % [ip, PORT])

func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

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
	game.log_msg("Connected to host")

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

@rpc("any_peer", "call_remote", "reliable")
func hello(tag: String) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	peer_tags[pid] = str(tag).substr(0, 24)
	game.rebind_owner(pid, peer_tags[pid])
	# they may already own kin here — hand the roster over immediately
	rpc_id(pid, "box_sync", box_state_pack(pid), game.rparty_for(pid).duplicate(), party_state_pack(pid))

@rpc("authority", "call_remote", "reliable")
func net_note(msg: String) -> void:
	game.log_msg(str(msg).substr(0, 120)) # a host whisper in the guest's log

@rpc("authority", "call_remote", "reliable")
func net_floater(x: float, y: float, txt: String, col: String) -> void:
	game.floater(Vector2(float(x), float(y)), str(txt).substr(0, 24), str(col))

@rpc("authority", "call_remote", "reliable")
func guest_hit(dmg: float) -> void:
	if multiplayer.is_server():
		return # host wildlife only bites through the wire toward guests
	game.hurt_player(clampf(float(dmg), 1.0, 500.0), null)

@rpc("authority", "call_remote", "reliable")
func guest_skill_hit(power: float, status_kind: String = "", status_dur: float = 0.0) -> void:
	if multiplayer.is_server():
		return # a skill shot mirrors the same formula on the guest's own armor
	if status_kind != "" and status_kind not in ["burn", "soak", "freeze"]:
		status_kind = ""
	game.hurt_player_skill(clampf(float(power), 0.0, 500.0), status_kind,
		clampf(status_dur, 0.0, 12.0))

func _on_peer_disconnected(id: int) -> void:
	if ghosts.has(id):
		ghosts[id].queue_free()
		ghosts.erase(id)
	if is_host:
		game.r_retract(id) # a leaving keeper's field pal balls up under their tag
		peer_tags.erase(id) # the tag survives in remote_parties for a rejoin
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
	# wild/base kin, not an empty world (capped upstream by MAX_PALS)
	var parr := []
	for p in game.pals:
		if p.mode in ["wild", "base", "partner"] and p.hp > 0:
			parr.append([p.species_id, p.pos.x, p.pos.y, p.lv, p.mode, p.lucky, p.uid,
				p.boss, p.alpha, p.spire_tag])
	return {"structures": arr, "tod": game.tod, "day": game.day, "kin": parr}

@rpc("authority", "call_remote", "reliable")
func state_sync(d: Dictionary) -> void:
	for e in d.get("structures", []):
		if e is Array and e.size() >= 3 and (e[1] is float or e[1] is int) and (e[2] is float or e[2] is int):
			game.place_free(str(e[0]), int(e[1]), int(e[2])) # net input is untrusted — validate shape
	game.tod = float(d.get("tod", game.tod))
	game.day = int(d.get("day", game.day))
	# drop the population our own regenerate() spawned — the host's wild/base
	# kin replace it, otherwise clients see every kin twice
	for p in game.pals.duplicate():
		if p.mode in ["wild", "base", "partner"]: # partner replicas are host truth too
			game.pals.erase(p)
			p.queue_free()
	var np := 0
	for e in d.get("kin", []):
		var n0 := game.pals.size()
		game.spawn_net_pal(e) # each entry re-validated game-side
		np += 1 if game.pals.size() > n0 else 0
	game.log_msg("Synced %d structures, %d kin" % [d.get("structures", []).size(), np])

# Live kin population: host rebroadcasts positions/health at 2Hz so replicas
# don't just sit where the join snapshot left them. Replicas are keyed by
# host uid (net_id); unknown ids spawn, missing ids despawn — one packet is
# the whole truth, packet loss self-heals on the next tick.
func pal_state_pack() -> Array:
	var arr := []
	for p in game.pals:
		if p.mode in ["wild", "base", "partner"] and p.hp > 0:
			arr.append([p.uid, p.species_id, p.pos.x, p.pos.y, p.lv, p.mode, p.hp, p.lucky, p.boss,
				p.alpha, p.spire_tag])
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
			# [species, x, y, lv, mode, lucky, net_id, boss, alpha, spire_tag] — spawn_net_pal's wire shape
			game.spawn_net_pal([e[1], e[2], e[3], e[4], e[5],
				e[7] if e.size() > 7 else false, nid,
				e[8] if e.size() > 8 else false,
				e[9] if e.size() > 9 else false,
				e[10] if e.size() > 10 else ""])
		else:
			p.net_target = Vector2(float(e[2]), float(e[3]))
			p.hp = maxf(0.0, float(e[6])) if e.size() > 6 else p.hp
	for p in game.pals.duplicate():
		if p.net_id > 0 and not seen.has(p.net_id): # host dropped it: caught, KO'd, despawned
			game.pals.erase(p)
			p.queue_free()

@rpc("authority", "call_remote", "unreliable")
func env_sync(tod: float, day: int, weather: String, danger: bool = false) -> void:
	if is_host:
		return
	game.tod = float(tod) # the host's clock owns the sky — a client's own tick just guesses
	game.day = int(day)
	game.net_danger = danger == true # raids are host truth; the drone mirrors it
	var w := str(weather)
	if w in ["clear", "rain", "storm", "drought"]:
		game.weather = w

@rpc("authority", "call_remote", "unreliable")
func peer_pos(id: int, x: float, y: float, elev: float) -> void:
	if not (is_finite(float(x)) and is_finite(float(y))):
		return
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(float(x), float(y), float(elev))

func _on_server_disconnected() -> void:
	for gid in ghosts.keys(): # frozen ghosts shouldn't outlive the session
		if is_instance_valid(ghosts[gid]):
			ghosts[gid].queue_free()
	ghosts.clear()
	game.clear_net_drops() # replica loot dies with the session too
	is_host = false
	multiplayer.multiplayer_peer = null # a dead peer must not keep net_live() true
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
	if not ghosts.has(id):
		return
	var nx := float(x); var ny := float(y)
	if not (is_finite(nx) and is_finite(ny)):
		return # NaN/infinity coordinates are not a place anyone can stand
	if nx < 0.0 or ny < 0.0 or nx >= World.WORLD_W or ny >= World.WORLD_H:
		return # every proximity gate trusts this position — keep it inside the island
	var g = ghosts[id]
	if g.net_pos.x >= 0 and Vector2(nx, ny).distance_to(Vector2(g.net_pos.x, g.net_pos.y)) > 12.0:
		return # guests have no legit teleport — a jump this big is a spoofed anchor
	g.net_pos = Vector3(nx, ny, float(elev))
	if is_host:
		rpc("peer_pos", id, nx, ny, float(elev))  # relay so clients see each other

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
	p.hit(clampf(float(dmg), 0.0, 2000.0), 1.0, false, pid) # the guest who swung takes the aggro — the host doesn't tank for remote blows
	if sleep_s > 0.0 and p.hp > 0: # a tranq dart lands after the sting — same rule as the host's own shot
		p.statuses["sleep"] = game.t + clampf(float(sleep_s), 0.5, 15.0)
		game.floater(p.pos, "zzz", "#9ad8ff")

@rpc("any_peer", "call_remote", "reliable")
func sphere_catch(nid: int, sid: String, behind: bool, cap_lv: int) -> void:
	if not is_host:
		return
	game.net_catch(int(nid), str(sid), behind == true, clampi(int(cap_lv), 1, 10),
		multiplayer.get_remote_sender_id())

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
	for d in game.drops:
		if d.get("did", -1) != int(did):
			continue
		if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(d["pos"]) > 2.5:
			return # fail closed: loot needs a witnessed ghost within arm's reach
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

# Shared box: the host's kinbox is the one real roster. Clients get a
# lightweight mirror (uid/species/level/vitals, no Kin nodes) and their
# kinbox clicks travel back as box_req ops the host validates + runs.
var box_sig := -1
var box_resend := 0.0

func box_fingerprint() -> int:
	var h := game.box.size() * 131 + game.party.size() * 7919
	for bp in game.box:
		h = (h * 31 + bp.uid + int(bp.hp) + bp.owner_id + (1 if bp.fav else 0)) & 0x7FFFFFFF
	for bb in game.bench:
		h = (h * 31 + bb.uid + int(bb.hp) + bb.owner_id) & 0x7FFFFFFF
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
		if not (e is Array) or e.size() < 5 or not (e[0] is float or e[0] is int):
			continue
		nb.append({"uid": int(e[0]), "sid": str(e[1]), "lv": clampi(int(e[2]), 1, 60),
			"hp": maxi(0, int(e[3])), "max_hp": maxi(1, int(e[4])),
			"sex": "F" if str(e[5]) == "F" else "M",
			"lucky": e.size() > 6 and e[6] == true,
			"talent": clampi(int(e[7]) if e.size() > 7 else 50, 0, 100),
			"ailment": str(e[8]) if e.size() > 8 else "",
			"fav": e.size() > 9 and e[9] == true,
			"star": clampi(int(e[10]) if e.size() > 10 else 0, 0, 4),
			"wk": str(e[11]) if e.size() > 11 else ""})
		if nb.size() >= 512: # hostile/hostile host can't stuff memory either
			break
	game.net_box = nb
	var np := []
	for e2 in prows:
		if not (e2 is Array) or e2.size() < 5 or not (e2[0] is float or e2[0] is int):
			continue
		np.append({"uid": int(e2[0]), "sid": str(e2[1]), "lv": clampi(int(e2[2]), 1, 60),
			"hp": maxi(0, int(e2[3])), "max_hp": maxi(1, int(e2[4])),
			"sex": "F" if str(e2[5]) == "F" else "M",
			"lucky": e2.size() > 6 and e2[6] == true,
			"talent": clampi(int(e2[7]) if e2.size() > 7 else 50, 0, 100),
			"ailment": str(e2[8]) if e2.size() > 8 else "",
			"fav": e2.size() > 9 and e2[9] == true,
			"star": clampi(int(e2[10]) if e2.size() > 10 else 0, 0, 4),
			"out": e2.size() > 11 and e2[11] == true,
			"stance": str(e2[12]) if e2.size() > 12 else "auto",
			"wk": str(e2[13]) if e2.size() > 13 else ""})
		if np.size() >= 8:
			break
	game.net_party = np
	game.party.clear() # typed Array[int] — a plain Array won't assign
	for u in pty:
		if u is float or u is int:
			game.party.append(int(u))
		if game.party.size() >= 8:
			break

@rpc("any_peer", "call_remote", "reliable")
func box_req(op: String, uid: int) -> void:
	if not is_host:
		return
	# every roster is private — the op lands only if the kin answers to the sender
	game.box_op_remote(str(op), int(uid), multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func assign_req(x: float, y: float) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	var at := Vector2(clampf(float(x), 0.0, game.world.WORLD_W), clampf(float(y), 0.0, game.world.WORLD_H))
	var gp = ghosts.get(pid)
	if gp == null or Vector2(gp.net_pos.x, gp.net_pos.y).distance_to(at) > 8.0:
		return # a hand can't post a pal it isn't standing next to
	game.assign_remote(pid, at)

var chat_last := 0.0 # cheap flood brake — one relayed line per tick beat
@rpc("any_peer", "call_remote", "unreliable")
func chat(t: String, from_id: int = 0) -> void:
	# the claimed sender is a lie — the wire's sender_id is the only honest id
	var real_from: int = multiplayer.get_remote_sender_id()
	if real_from == 0: # local call (own echo / host-originated line)
		real_from = from_id
	if real_from == multiplayer.get_unique_id():
		return # the server relayed your own line back — hud already echoed it
	var line: String = str(t).left(160) # the log window can't hold a novel
	if multiplayer.is_server():
		if Time.get_ticks_msec() / 1000.0 - chat_last < 0.25:
			return # a peer spamming chat gets exactly one relay per beat — and no log line either
		chat_last = Time.get_ticks_msec() / 1000.0
	game.log_msg("[friend] " + line)
	if multiplayer.is_server():
		rpc("chat", line, int(real_from)) # ENet is a star: relay to other clients

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
			rpc("env_sync", game.tod, game.day, game.weather, game.danger_active()) # clock + sky + threat are host truth
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
