class_name World
# World data + procedural generation. Grid: 220x220 tiles.
# tiles[] = ground type; decor[] = standalone object (tree/rock/ore…); elev[] = 0..3.
# Movement between tiles of different elevation is blocked unless a ramp is involved.

const WORLD_W := 220
const WORLD_H := 220

var tiles: PackedByteArray = PackedByteArray()     # Tile enum
var decor: PackedByteArray = PackedByteArray()     # Decor enum
var elev: PackedByteArray = PackedByteArray()      # 0..3
var ramp: PackedByteArray = PackedByteArray()      # 0/1
var hp: PackedByteArray = PackedByteArray()        # decor hit points
var spawn_zone: PackedByteArray = PackedByteArray()
var spawn := Vector2i.ZERO
var structures := {}                                # idx -> structure node id
var seed := 1

enum Tile { GRASS, TALLGRASS, FLOWER, SAND, WATER, STONEFIELD, DIRT, FARMLAND }
enum Decor { NONE, TREE_A, TREE_B, ROCK, ORE_GOLD, ORE_COAL, BERRY, STUMP }
const SOLID_TILES := [Tile.WATER]

func _init() -> void:
	tiles.resize(WORLD_W * WORLD_H)
	decor.resize(WORLD_W * WORLD_H)
	elev.resize(WORLD_W * WORLD_H)
	ramp.resize(WORLD_W * WORLD_H)
	hp.resize(WORLD_W * WORLD_H)
	spawn_zone.resize(WORLD_W * WORLD_H)

func idx(x: int, y: int) -> int:
	return y * WORLD_W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < WORLD_W and y >= 0 and y < WORLD_H

func tile_at(x: int, y: int) -> int:
	return tiles[idx(x, y)] if in_bounds(x, y) else Tile.WATER

func decor_at(x: int, y: int) -> int:
	return decor[idx(x, y)] if in_bounds(x, y) else Decor.NONE

func elev_at(x: int, y: int) -> int:
	return elev[idx(x, y)] if in_bounds(x, y) else 0

func zone_at(x: int, y: int) -> int:
	return spawn_zone[idx(x, y)] if in_bounds(x, y) else 3

func solid_structure(i: int) -> bool:
	# spikes etc. are structures you can stand on — flagged walkable at placement
	return structures.has(i) and not structures[i].get("walkable", false)

func blocked_swim(x: int, y: int, from_x: float, from_y: float) -> bool:
	# aquatic pals: water is open, everything else still blocks
	if not in_bounds(x, y):
		return true
	var i := idx(x, y)
	if decor[i] != Decor.NONE or solid_structure(i):
		return true
	var t := tiles[i]
	if SOLID_TILES.has(t) and t != Tile.WATER:
		return true
	var fi := idx(clampi(int(floor(from_x)), 0, WORLD_W - 1), clampi(int(floor(from_y)), 0, WORLD_H - 1)) # floor() can go -1 at the world rim — a negative index silently wraps
	if elev[i] != elev[fi] and not ramp[i] and not ramp[fi]:
		return true
	return false

func blocked(x: int, y: int, from_x := -1.0, from_y := -1.0) -> bool:
	if not in_bounds(x, y):
		return true
	var i := idx(x, y)
	if SOLID_TILES.has(tiles[i]) or decor[i] != Decor.NONE or solid_structure(i):
		return true
	if from_x < 0:
		return false
	var fi := idx(clampi(int(floor(from_x)), 0, WORLD_W - 1), clampi(int(floor(from_y)), 0, WORLD_H - 1)) # same rim wrap
	if elev[i] != elev[fi] and not ramp[i] and not ramp[fi]:
		return true
	return false

func flat_at(x: int, y: int, w: int, h: int) -> bool:
	var e := elev_at(x, y)
	for dy in h:
		for dx in w:
			if elev_at(x + dx, y + dy) != e:
				return false
	return true

func generate(new_seed: int) -> Vector2i:
	seed = new_seed
	var rng := Rng.new(seed)
	for y in WORLD_H:
		for x in WORLD_W:
			var i := idx(x, y)
			var e := Rng.hash2(x >> 3, y >> 3, seed) * 0.6 + Rng.hash2(x >> 1, y >> 1, seed + 7) * 0.4
			var m := Rng.hash2(x >> 2, y >> 2, seed + 31)
			var t := Tile.GRASS
			var d := Decor.NONE
			if e < 0.30:
				t = Tile.WATER
			elif e < 0.36:
				t = Tile.SAND
			elif m > 0.62 and e > 0.5:
				if rng.chance(0.75):
					d = Decor.TREE_A if rng.chance(0.55) else Decor.TREE_B
				else:
					t = Tile.TALLGRASS
			elif m > 0.58 and e < 0.48:
				t = Tile.STONEFIELD
				if rng.chance(0.6):
					d = Decor.ROCK
				elif rng.chance(0.35):
					d = Decor.ORE_GOLD if rng.chance(0.5) else Decor.ORE_COAL
			elif m < 0.10:
				t = Tile.FLOWER
			elif Rng.hash2(x, y, seed + 77) < 0.06:
				t = Tile.TALLGRASS
			tiles[i] = t
			decor[i] = d
			hp[i] = 30 if d == Decor.TREE_A or d == Decor.TREE_B else (60 if d == Decor.ROCK else (90 if d == Decor.ORE_GOLD or d == Decor.ORE_COAL else (20 if d == Decor.BERRY else 0)))
			var el := Rng.hash2(x >> 4, y >> 4, seed + 911) * 0.7 + Rng.hash2(x >> 1, y >> 1, seed + 912) * 0.3
			elev[i] = 0 if (t == Tile.WATER or t == Tile.SAND) else (1 if el < 0.50 else (2 if el < 0.68 else 3))
			var ddx := x - WORLD_W / 2.0
			var ddy := y - WORLD_H / 2.0
			var dist := sqrt(ddx * ddx + ddy * ddy)
			spawn_zone[i] = 0 if dist < 45 else (1 if dist < 75 else (2 if dist < 95 else 3))
	var cx := WORLD_W / 2
	var cy := WORLD_H / 2
	for y in range(cy - 8, cy + 8):
		for x in range(cx - 8, cx + 8):
			var i := idx(x, y)
			if tiles[i] == Tile.WATER or tiles[i] == Tile.STONEFIELD:
				tiles[i] = Tile.GRASS
				decor[i] = Decor.NONE
			if decor[i] == Decor.TREE_A or decor[i] == Decor.TREE_B:
				if rng.chance(0.5):
					decor[i] = Decor.NONE
			elev[i] = 1
	for y in WORLD_H:
		for x in WORLD_W:
			var i := idx(x, y)
			if tiles[i] == Tile.TALLGRASS and Rng.hash2(x, y, seed + 5) < 0.2:
				decor[i] = Decor.BERRY
				hp[i] = 20
			if tiles[i] == Tile.SAND and Rng.hash2(x, y, seed + 9) < 0.12:
				decor[i] = Decor.ORE_GOLD
				hp[i] = 45
	for y in WORLD_H:
		for x in WORLD_W:
			var i := idx(x, y)
			if tiles[i] == Tile.WATER:
				continue
			var e0: int = elev[i]
			var mix := elev_at(x - 1, y) != e0 or elev_at(x + 1, y) != e0 or elev_at(x, y - 1) != e0 or elev_at(x, y + 1) != e0
			ramp[i] = 1 if (mix and Rng.hash2(x, y, seed + 913) < 0.45) else 0
	spawn = Vector2i(cx, cy)
	return spawn
