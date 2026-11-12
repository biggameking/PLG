extends Node2D
# Draws the visible terrain each frame in _draw(): pass 1 = ground diamonds,
# pass 2 = cliff walls / stair ramps. Decor objects are real sprites in the
# y-sorted container (managed by DecorPool below).

var world: World
var atlas: Texture2D
var cells := {}            # name -> Rect2 (source rect in atlas)
var region := Rect2i()     # visible tile bounds, set by game before redraw

func setup(w: World) -> void:
	world = w
	atlas = load("res://assets/tiles.png")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles.json"))
	for name in manifest["tiles"]:
		var c: Array = manifest["tiles"][name]
		cells[name] = Rect2(c[0] * 64, c[1] * 64, 64, 64)

func _draw() -> void:
	if world == null or cells.is_empty():
		return
	# pass 1: ground tiles in painter order (x+y ascending)
	for y in range(region.position.y, region.end.y + 1):
		for x in range(region.position.x, region.end.x + 1):
			draw_ground(x, y)
	# pass 2: walls & stairs, same order so upper cells' faces overlay lower tops
	for y in range(region.position.y, region.end.y + 1):
		for x in range(region.position.x, region.end.x + 1):
			draw_faces(x, y)

const GROUND_NAMES := {
	World.Tile.GRASS: "grass", World.Tile.TALLGRASS: "tallgrass",
	World.Tile.FLOWER: "flower", World.Tile.SAND: "sand",
	World.Tile.WATER: "water", World.Tile.STONEFIELD: "stonefield",
	World.Tile.DIRT: "dirt", World.Tile.FARMLAND: "farmland",
}

# Variant names are prebaked per tile type — the old per-tile string concat
# ("base_%d" % v) allocated ~15k strings/frame at max zoom-out (audit-45).
static var _VNAMES := {}

static func _vnames() -> Dictionary:
	if _VNAMES.is_empty():
		for t in [World.Tile.GRASS, World.Tile.TALLGRASS, World.Tile.FLOWER,
				World.Tile.SAND, World.Tile.WATER, World.Tile.STONEFIELD,
				World.Tile.DIRT, World.Tile.FARMLAND]:
			var base: String = GROUND_NAMES[t]
			var n := 4 if t == World.Tile.GRASS else 2
			var a := []
			for i in n:
				a.append(base + "_" + str(i))
			_VNAMES[t] = a
	return _VNAMES

func draw_ground(x: int, y: int) -> void:
	var t: int = world.tile_at(x, y)
	var names: Array = _vnames().get(t, _vnames()[World.Tile.GRASS])
	var v := int(Rng.hash2(x, y, world.seed + 55) * 4.0)
	var name: String = names[v if t == World.Tile.GRASS else (v % 2)]
	if not cells.has(name):
		name = "grass_0"
	var p := Iso.to_screen(x + 0.5, y + 0.5, world.elev_at(x, y))
	draw_texture_rect_region(atlas, Rect2(p.x - 32, p.y - 16, 64, 64), cells[name])

# exposed faces: +x edge (right-down) and +y edge (left-down) of the upper tile
func draw_faces(x: int, y: int) -> void:
	if not world.in_bounds(x, y):
		return
	var e: int = world.elev_at(x, y)
	if e == 0:
		return
	var dx := e - world.elev_at(x + 1, y)
	var dy := e - world.elev_at(x, y + 1)
	if dx <= 0 and dy <= 0:
		return
	var p := Iso.to_screen(x + 0.5, y + 0.5, e)
	var is_ramp := world.ramp[world.idx(x, y)] == 1
	for level in maxi(dx, dy):
		var fx := level < dx
		var fy := level < dy
		var face := "corner" if (fx and fy) else ("sx" if fx else "sy")
		var name := ("stair_" if (is_ramp and level == 0) else "wall_") + face
		draw_texture_rect_region(atlas, Rect2(p.x - 32, p.y - 16 + level * Iso.ELEV_STEP, 64, 64), cells[name])


