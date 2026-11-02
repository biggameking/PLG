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
	return {"structures": arr, "tod": game.tod, "day": game.day}

@rpc("authority", "call_remote", "reliable")
func state_sync(d: Dictionary) -> void:
	for e in d.get("structures", []):
		game.place_free(e[0], int(e[1]), int(e[2]))
	game.tod = d.get("tod", game.tod)
	game.day = d.get("day", game.day)
	game.log_msg("Synced %d structures" % d.get("structures", []).size())

@rpc("authority", "call_remote", "unreliable")
func peer_pos(id: int, x: float, y: float, elev: float) -> void:
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(x, y, elev)

func spawn_ghost(id: int) -> void:
	var g := preload("res://src/ghost.gd").new()
	g.game = game
	entity_layer.add_child(g)
	ghosts[id] = g
	game.log_msg("Player %d joined" % id)

@rpc("authority", "call_remote", "reliable")
func world_sync(s: int) -> void:
	game.regenerate(s)
	game.log_msg("Synced world seed %d" % s)

@rpc("any_peer", "call_remote", "unreliable")
func sync_pos(x: float, y: float, elev: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if ghosts.has(id):
		ghosts[id].net_pos = Vector3(x, y, elev)
	if is_host:
		rpc("peer_pos", id, x, y, elev)  # relay so clients see each other

@rpc("any_peer", "call_remote", "unreliable")
func chat(t: String, from_id: int = 0) -> void:
	if from_id == multiplayer.get_unique_id():
		return # the server relayed your own line back — hud already echoed it
	game.log_msg("[friend] " + t)
	if multiplayer.is_server():
		rpc("chat", t, from_id) # ENet is a star: relay client chat to the other clients

func _process(dt: float) -> void:
	if multiplayer.multiplayer_peer == null or ghosts.is_empty():
		return
	send_timer += dt
	if send_timer < 0.05:
		return
	send_timer = 0.0
	var p: Player = game.player
	rpc("sync_pos", p.pos.x, p.pos.y, p.elev())
