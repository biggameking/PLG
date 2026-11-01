extends Node2D
# Main scene: camera follow + zoom, decor sprite pool (y-sorted), sphere/floater draw.

var cam: Camera2D
var game: Game
var decor_tex := {}
var pool: Array[Sprite2D] = []
var pool_used := {}

func _ready() -> void:
	game = $Game
	cam = $Camera2D
	# decor textures
	for k in ["tree_a", "tree_b", "rock", "ore_gold", "ore_coal", "berry_bush", "stump"]:
		decor_tex[k] = load("res://assets/decor/%s.png" % k)
	game.connect("decor_dirty", _on_decor_dirty)
	$UILayer/HUD.game = game
	var net := preload("res://src/net.gd").new()
	add_child(net)
	net.setup(game, game.entity_layer)
	game.net = net

func _on_decor_dirty() -> void:
	pass # pool keys by world cell; pool refresh reads live data

const DECOR_KIND := {
	World.Decor.TREE_A: "tree_a", World.Decor.TREE_B: "tree_b",
	World.Decor.ROCK: "rock", World.Decor.ORE_GOLD: "ore_gold",
	World.Decor.ORE_COAL: "ore_coal", World.Decor.BERRY: "berry_bush",
	World.Decor.STUMP: "stump",
}

func _process(_dt: float) -> void:
	var pl := game.player
	if not pl:
		return
	# day/night tint: 6-18 bright, dusk/dawn warm, night dark blue
	var h := game.tod
	var col: Color
	if h < 5 or h > 20:
		col = Color(0.42, 0.48, 0.72)
	elif h < 7:
		col = Color(0.85, 0.72, 0.62).lerp(Color.WHITE, (h - 5) / 2)
	elif h < 17:
		col = Color.WHITE
	elif h < 20:
		col = Color.WHITE.lerp(Color(0.9, 0.6, 0.5), (h - 17) / 3).lerp(Color(0.42, 0.48, 0.72), maxf(0, h - 18.5) / 1.5)
	$CanvasModulate.color = col
	cam.global_position = cam.global_position.lerp(pl.global_position, 0.12)
	refresh_decor()
	game.drawer.region = visible_tiles()
	game.drawer.queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("zoom_in"):
		cam.zoom = (cam.zoom * 1.15).clampf(0.35, 2.5) * Vector2.ONE
	if e.is_action_pressed("zoom_out"):
		cam.zoom = (cam.zoom / 1.15).clampf(0.35, 2.5) * Vector2.ONE

func visible_tiles() -> Rect2i:
	var r := get_viewport_rect().size / cam.zoom.x
	var c := cam.global_position
	var xs := []
	var ys := []
	for corner in [Vector2(c.x - r.x / 2, c.y - r.y / 2 - 100), Vector2(c.x + r.x / 2, c.y - r.y / 2 - 100),
			Vector2(c.x - r.x / 2, c.y + r.y / 2 + 100), Vector2(c.x + r.x / 2, c.y + r.y / 2 + 100)]:
		var t := Iso.from_screen(corner.x, corner.y, 1.5)
		xs.append(t.x)
		ys.append(t.y)
	var x0 := maxi(0, int(xs.min()) - 3)
	var y0 := maxi(0, int(ys.min()) - 3)
	return Rect2i(x0, y0, mini(World.WORLD_W - x0, int(xs.max()) - x0 + 6),
		mini(World.WORLD_H - y0, int(ys.max()) - y0 + 6))

func refresh_decor() -> void:
	var w := game.world
	var vis := visible_tiles()
	var need := {}
	for y in range(vis.position.y, vis.end.y):
		for x in range(vis.position.x, vis.end.x):
			var d := w.decor_at(x, y)
			if d == World.Decor.NONE:
				continue
			need[x + y * 1000] = [d, x, y]
	for key in pool_used:
		if not need.has(key):
			var spr: Sprite2D = pool_used[key]
			spr.hide()
			pool.append(spr)
			pool_used.erase(key)
	for key in need:
		if pool_used.has(key):
			continue
		var d: int = need[key][0]
		var spr: Sprite2D
		if pool.is_empty():
			spr = Sprite2D.new()
			game.entity_layer.add_child(spr)
		else:
			spr = pool.pop_back()
			spr.show()
		spr.texture = decor_tex[DECOR_KIND[d]]
		var x: int = need[key][1]
		var y: int = need[key][2]
		var p := Iso.to_screen(x + 0.5, y + 0.5, w.elev_at(x, y))
		var tex: Texture2D = spr.texture
		spr.position = Vector2(p.x, p.y - tex.get_height() * 0.5)
		pool_used[key] = spr

func _draw() -> void:
	pass
