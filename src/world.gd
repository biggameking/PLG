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
var terrain_gen := 0 # bumped by generate() — the drawer repaints only when
# this or the visible region changes (tiles/elev/ramp are write-once)

enum Tile { GRASS, TALLGRASS, FLOWER, SAND, WATER, STONEFIELD, DIRT, FARMLAND }
enum Decor { NONE, TREE_A, TREE_B, ROCK, ORE_GOLD, ORE_COAL, BERRY, STUMP }
const SOLID_TILES := [Tile.WATER]
# shot-blockers: TALL decor swats orbs/bolts/swings — stumps and berry
# bushes are shin-high ground cover, everything flies over them. blocked()
# still counts all decor: you path around debris, you just don't shoot
# into it. The clear-cut dead zone this produced is the S125 finding.
const SHOT_BLOCKERS := [Decor.TREE_A, Decor.TREE_B, Decor.ROCK,
	Decor.ORE_GOLD, Decor.ORE_COAL]

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

func climate_at(p: Vector2) -> String:
	# latitude bands: the far north freezes around the clock, the
	# far south scorches under the sun — the midlands keep their mild nights
	if p.y < 30.0:
		return "cold"
	if p.y > WORLD_H - 30.0:
		return "hot"
	return ""

func decor_at(x: int, y: int) -> int:
	return decor[idx(x, y)] if in_bounds(x, y) else Decor.NONE

func elev_at(x: int, y: int) -> int:
	return elev[idx(x, y)] if in_bounds(x, y) else 0

func zone_at(x: int, y: int) -> int:
	return spawn_zone[idx(x, y)] if in_bounds(x, y) else 3

func solid_structure(i: int) -> bool:
	# spikes etc. are structures you can stand on — flagged walkable at placement
	return structures.has(i) and not structures[i].get("walkable", false)

func swim_open(x: int, y: int) -> bool:
	# an aquatic kin may only occupy a water cell that carries nothing else —
	# the old blocked_swim(x,y,x,y) call could never see this: i==fi early-
	# returned false before the decor/structure checks ran (audit-42)
	if not in_bounds(x, y):
		return false
	var i := idx(x, y)
	return tiles[i] == Tile.WATER and decor[i] == Decor.NONE and not solid_structure(i)

func los_clear(a: Vector2, b: Vector2) -> bool:
	# sight-open cells only: no decor, no solid structure, no unramped
	# elevation step — the same wall set blocked() enforces. Combat verbs
	# (melee, bites, novas, orbs, partner actives) must not reach through a
	# sealed ring; detection scans stay distance-only by design (audit-43)
	var span := a.distance_to(b)
	var steps := maxi(1, int(ceil(span * 8.0)))
	var pc := Vector2i(-9999, -9999)
	var pe := -9999
	# the bodies' own cells aren't BETWEEN them — a wall is what separates;
	# teleported/tested entities can sit on cells they couldn't walk into
	var first_c := Vector2i(int(floor(a.x)), int(floor(a.y)))
	var last_c := Vector2i(int(floor(b.x)), int(floor(b.y)))
	for i2 in range(steps + 1):
		var p := a.lerp(b, float(i2) / float(steps))
		var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
		if c == pc:
			continue
		if not in_bounds(c.x, c.y):
			return false
		var i := idx(c.x, c.y)
		if c != first_c and c != last_c \
				and (decor[i] in SHOT_BLOCKERS or solid_structure(i)):
			return false
		if pe != -9999 and elev[i] != pe and not ramp[i] and not ramp[idx(pc.x, pc.y)]:
			return false # a sheer face is a wall even to a nova
		pc = c
		pe = elev[i]
	return true

func blocked_swim(x: int, y: int, from_x: float, from_y: float) -> bool:
	# aquatic kin: water is open, everything else still blocks
	if not in_bounds(x, y):
		return true
	var i := idx(x, y)
	var fi := idx(clampi(int(floor(from_x)), 0, WORLD_W - 1), clampi(int(floor(from_y)), 0, WORLD_H - 1)) # floor() can go -1 at the world rim — a negative index silently wraps
	if i == fi:
		return false # never wall yourself in: an entity inside a solid tile must be able to shift within it and step out
	if decor[i] != Decor.NONE or solid_structure(i):
		return true
	var t := tiles[i]
	if SOLID_TILES.has(t) and t != Tile.WATER:
		return true
	if elev[i] != elev[fi] and not ramp[i] and not ramp[fi]:
		return true
	return false

func blocked(x: int, y: int, from_x := -1.0, from_y := -1.0) -> bool:
	if not in_bounds(x, y):
		return true
	var i := idx(x, y)
	if from_x < 0:
		return SOLID_TILES.has(tiles[i]) or decor[i] != Decor.NONE or solid_structure(i)
	var fi := idx(clampi(int(floor(from_x)), 0, WORLD_W - 1), clampi(int(floor(from_y)), 0, WORLD_H - 1)) # same rim wrap
	if i == fi:
		return false # same-tile shifts always allowed — lets anything wedged inside a solid tile walk out
	if SOLID_TILES.has(tiles[i]) or decor[i] != Decor.NONE or solid_structure(i):
		return true
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
	decor[idx(cx, cy)] = Decor.NONE # the berry/ore pass runs after the spawn
	hp[idx(cx, cy)] = 0            # clearing — the landing cell itself must
	# never roll a bush or a boulder (same-tile escape would free you anyway,
	# but the opening shot matters); clear the stale hp budget with it
	for y in WORLD_H:
		for x in WORLD_W:
			var i := idx(x, y)
			if tiles[i] == Tile.WATER:
				continue
			var e0: int = elev[i]
			var mix := elev_at(x - 1, y) != e0 or elev_at(x + 1, y) != e0 or elev_at(x, y - 1) != e0 or elev_at(x, y + 1) != e0
			ramp[i] = 1 if (mix and Rng.hash2(x, y, seed + 913) < 0.45) else 0
	spawn = Vector2i(cx, cy)
	terrain_gen += 1
	return spawn
