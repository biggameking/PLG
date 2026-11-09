extends Entity
class_name Player
# WASD/arrows move · SHIFT sprint · LMB melee/harvest · Q aim sphere ·
# click throws · E interact · SPACE dodge.

var game: Game
var hp := 100.0
var hunger := 80.0          # 0-100; drains ~100 over ~22 min
var stamina := 100.0        # Palworld stamina: sprint/swim/dodge burn it
var stam_wait := 0.0        # regen delay after a drain
var cold_t := 0.0           # night-chill accumulator — resets by the fire
var shield_t := 0.0         # Roly Poly bubble: deadline (game.t)
var shield_n := 0.0         # absorb pool left in the bubble

func absorb_hit(final: int) -> int:
	# Palworld's Lamball partner skill — a plush ball eats the hit for you
	if shield_t <= game.t or final <= 0:
		return final
	var got := mini(final, int(shield_n))
	shield_n -= got
	if shield_n <= 0.0:
		shield_t = 0.0 # the bubble pops once it's spent
	game.floater(pos, "blocked!", "#a8d8ff")
	return final - got
var max_hp := 100.0
var level := 1
var xp := 0
var capture_level := 1
var dodge_t := 0.0
var mount: Pal = null
var facing := Vector2(1, 0)  # last move direction, for harvest/interact
var equipment := {"weapon": "", "armor": "", "acc1": "", "acc2": ""} # Palworld trinkets ride the acc slots
var weapon_wear := -1.0       # uses left; -1 = unbreakable or bare hands
var armor_wear := -1.0        # hits absorbed left; -1 = unarmored/unbreakable
var atk_cd := 0.0
var sphere_sel := 0
var aiming := false
var statuses := {}
var meal_buff := {}          # one active food buff {atk|def|spd: frac} — Palworld meal bonus
var meal_t := 0.0            # seconds left on the meal buff

func setup(g: Game, at: Vector2) -> void:
	game = g
	world = g.world
	pos = at
	speed = 5.0
	setup_visuals("res://assets/pals/player_f0.png", "res://assets/pals/player_f1.png")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		aiming = not aiming
	if event.is_action_pressed("ride"):
		try_mount()
	if event.is_action_pressed("partner_skill"):
		game.partner_skill()
	if event.is_action_pressed("cycle_sphere"):
		sphere_sel = (sphere_sel + 1) % maxi(1, game.sphere_tiers().size())
	if statuses.get("sleep", 0) > game.t:
		return # asleep: no dodge / attack / throw
	if event.is_action_pressed("dodge") and dodge_t <= 0 and stamina >= 15.0:
		dodge_t = 0.35
		stamina -= 15.0; stam_wait = 0.8 # a roll costs a chunk of stamina
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game.panel != "":
			return
		if aiming:
			throw_sphere()
		else:
			melee()

func melee() -> void:
	if atk_cd > 0:
		return
	var w: Dictionary = ItemData.ITEMS.get(equipment["weapon"], {})
	var wd: Dictionary = w.get("weapon", {})
	if w.get("id") == "sphere_launcher":
		launch_sphere(wd)
		return
	if wd.get("range", 0) > 3:
		shoot_weapon(wd)
		wear_tick()
		return
	atk_cd = wd.get("cd", 0.45)
	wear_tick()
	var atk: float = (wd.get("dmg", 15) * 2.0 + level * 4.0) * (1.0 + game.perks["atk"] * 0.08 + acc_total("atk") + game.partner_aura("atk") + meal_bonus("atk"))
	var reach: float = wd.get("range", 1.6)
	var hit_any := false
	for p in game.pals.duplicate():
		if p.mode != "wild" or p.hp <= 0:
			continue
		if pos.distance_to(p.pos) > reach:
			continue
		var mult := Combat.effectiveness("neutral", p.elem())
		var d := Combat.damage(atk, 34, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus * p.def_mult(), mult, game.rng)
		if p.net_id > 0 and game.net != null:
			# host owns replica hp — relay the swing, next snapshot settles it
			game.net.rpc("pal_hit", p.net_id, d)
		else:
			p.hit(d, mult, true)
		hit_any = true
	# Palworld crime: a swung weapon can also strike the trader — expect consequences
	if game.merchant != null and is_instance_valid(game.merchant) \
			and game.merchant_hp > 0 and pos.distance_to(game.merchant.pos) <= reach:
		game.hit_merchant(atk)
		hit_any = true
	if hit_any:
		game.sfx_play("hit")
	else:
		game.try_harvest(pos, facing)

func launch_sphere(wd: Dictionary) -> void:
	# Palworld's sphere launcher: slings the selected ball downrange at the
	# wild pal nearest the facing line — long-range catch, no stealth crawl
	var tiers := game.sphere_tiers()
	if tiers.is_empty():
		game.log_msg("No spheres loaded!")
		return
	sphere_sel = clampi(sphere_sel, 0, tiers.size() - 1)
	var sid: String = tiers[sphere_sel]
	var best: Pal = null
	var best_dot := 0.3
	var reach: float = wd.get("range", 8.0)
	for p in game.pals:
		if p.mode != "wild" or p.hp <= 0:
			continue
		var off: Vector2 = p.pos - pos
		var d := off.length()
		if d > reach or d < 0.5:
			continue
		var dot := off.normalized().dot(facing.normalized())
		if dot > best_dot:
			best_dot = dot; best = p
	if best == null:
		game.log_msg("No pal in the line of fire")
		return
	atk_cd = wd.get("cd", 1.0)
	wear_tick()
	game.add_item(sid, -1)
	game.sphere_fly(sid, best)

func throw_sphere() -> void:
	var tiers := game.sphere_tiers()
	if tiers.is_empty():
		game.log_msg("No spheres! Craft pal_sphere at a workbench.")
		aiming = false
		return
	sphere_sel = clampi(sphere_sel, 0, tiers.size() - 1)
	var sid: String = tiers[sphere_sel]
	var mpos := get_global_mouse_position()
	var tw := Iso.from_screen(mpos.x, mpos.y, elev())
	var best: Pal = null
	var bd := 1.6
	for p in game.pals:
		if p.mode != "wild" or p.hp <= 0:
			continue
		var d := p.pos.distance_to(tw)
		if d < bd:
			bd = d
			best = p
	if not best:
		return
	game.add_item(sid, -1)
	game.sphere_fly(sid, best)

func flying() -> bool:
	return mount != null and SpeciesData.body_of(mount.species_id) == "bird"

func can_enter(nx: float, ny: float) -> bool:
	var tx := int(nx); var ty := int(ny)
	if not world.blocked(tx, ty, pos.x, pos.y):
		return true
	# flying mount (Palworld): a bird carries you over water and cliffs both ways
	if flying() and world.in_bounds(tx, ty):
		var i := world.idx(tx, ty)
		if world.decor[i] == World.Decor.NONE and not world.solid_structure(i):
			return true
		return false # trees/rocks/walls still block a flyer
	# swimming mount (Palworld): a water-element mount ferries you across water —
	# nothing else about terrain changes: decor, structures and cliffs still block
	if mount != null and world.in_bounds(tx, ty):
		var i2 := world.idx(tx, ty)
		if world.tiles[i2] == World.Tile.WATER and "water" in mount.spec.get("elements", []):
			return world.decor[i2] == World.Decor.NONE and not world.solid_structure(i2)
	# swimming on foot (Palworld): deep water is crossable without a mount —
	# just slow and tiring
	if mount == null and world.in_bounds(tx, ty):
		var i3 := world.idx(tx, ty)
		if world.tiles[i3] == World.Tile.WATER:
			return world.decor[i3] == World.Decor.NONE and not world.solid_structure(i3)
	# glider (Palworld): riding the wind down a cliff is safe — uphill is not
	var fi := world.idx(clampi(int(pos.x), 0, World.WORLD_W - 1), clampi(int(pos.y), 0, World.WORLD_H - 1))
	if game.item_count("glider") > 0 and world.in_bounds(tx, ty):
		var i := world.idx(tx, ty)
		if world.tiles[i] != World.Tile.WATER and world.decor[i] == World.Decor.NONE \
				and not world.solid_structure(i) and world.elev[i] < world.elev[fi]:
			return true
	# grappling hook (Palworld): the hook hauls you UP a ledge — one-way
	if game.item_count("grappling_hook") > 0 and world.in_bounds(tx, ty):
		var i := world.idx(tx, ty)
		if world.tiles[i] != World.Tile.WATER and world.decor[i] == World.Decor.NONE \
				and not world.solid_structure(i) and world.elev[i] > world.elev[fi]:
			return true
	return false

func swimming() -> bool:
	return mount == null and world.in_bounds(int(pos.x), int(pos.y)) \
		and world.tiles[world.idx(int(pos.x), int(pos.y))] == World.Tile.WATER

# Palworld carry weight: the bag pulls you down once it tops capacity
func carry_wt() -> float:
	var w := 0.0
	for sid in game.items:
		w += game.item_wt(sid) * int(game.items[sid])
	return w

func carry_cap() -> float:
	return 300.0 + (level - 1) * 10.0 + game.partner_aura("carry")

func speed_mult() -> float:
	var m := 1.0
	if swimming():
		m *= 0.5
	if mount != null:
		# Palworld: mounts differ — a swift deer outruns a sluggish boar
		m *= 1.3 + minf(float(mount.spec.get("speed", 2.6)), 5.0) * 0.2
	if hunger < 25.0:
		m *= 0.8
	if statuses.get("freeze", 0) > game.t:
		m *= 0.5
	if statuses.get("soak", 0) > game.t:
		m *= 0.7
	m *= 1.0 + game.perks["speed"] * 0.06 + acc_total("spd") + game.partner_aura("speed") + meal_bonus("spd")
	var cap := carry_cap()
	var wt := carry_wt()
	if wt > cap:
		m *= maxf(0.15, 1.5 - wt / cap) # over-encumbered crawl (Palworld)
	return m

func _physics_process(dt: float) -> void:
	atk_cd -= dt
	dodge_t -= dt
	for k in statuses.keys():
		if statuses[k] <= game.t:
			statuses.erase(k)
	# DoT statuses on the player (were cosmetic-only)
	if statuses.get("burn", 0) > game.t and int(game.t * 5) != int((game.t - dt) * 5):
		hp = maxf(1.0, hp - max_hp * 0.02)
	if statuses.get("poison", 0) > game.t and int(game.t * 3) != int((game.t - dt) * 3):
		hp = maxf(1.0, hp - max_hp * 0.012)
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if iv.length_squared() > 0.01:
		facing = iv.normalized()
	hunger = maxf(0.0, hunger - dt * 0.075 * (3.0 if swimming() else 1.0)) # a swim works up an appetite
	if meal_t > 0.0:
		meal_t -= dt
		if meal_t <= 0.0:
			meal_buff = {} # the meal wore off
	# Palworld stamina: swimming burns it — run dry mid-water and you drown
	var stam_drain := 0.0
	if swimming():
		stam_drain = 4.0 * dt
		if stamina <= 0.0:
			hp = maxf(1.0, hp - dt * 3.0) # exhausted swimmer: sinking damage
	if iv.length() > 0 and Input.is_action_pressed("sprint") and mount == null:
		stam_drain += 12.0 * dt
	if stam_drain > 0.0:
		stamina = maxf(0.0, stamina - stam_drain); stam_wait = 0.8
	else:
		stam_wait -= dt
		if stam_wait <= 0.0:
			stamina = minf(100.0, stamina + 25.0 * dt) # quick catch-up
	if hunger <= 0.0:
		hp = maxf(1.0, hp - dt * 0.4)   # starving: slow drain to 1hp
	# Palworld night chill + latitude bands: past dusk and away from
	# firelight the cold bleeds hp — never below 30%. The far north freezes
	# all day; the far south scorches by day (a swim or cooling armor saves
	# you) and snaps cold again after dark, desert-style.
	var warm := float(ItemData.ITEMS.get(equipment["armor"], {}).get("warm", 0))
	var cool := float(ItemData.ITEMS.get(equipment["armor"], {}).get("cool", 0))
	var cl: String = game.world.climate_at(pos)
	var swim: bool = game.world.tile_at(int(pos.x), int(pos.y)) == World.Tile.WATER
	var freezing: bool = cl == "cold" or game.is_night()
	var scorching: bool = cl == "hot" and not game.is_night() and not swim and cool <= 0.0
	if hp > max_hp * 0.3 and ((freezing and game.nearest_heat(pos) > 10.0 + warm * 4.0) or scorching):
		cold_t += dt
		if cold_t >= 4.0:
			cold_t = 0.0
			hp = maxf(max_hp * 0.3, hp - 2.0)
			game.floater(pos, "heat…" if scorching else "cold…",
				"#ff9a4a" if scorching else "#9fd8ff")
	else:
		cold_t = 0.0
	var spd_mult := speed_mult()
	if statuses.get("sleep", 0) > game.t:
		iv = Vector2.ZERO
	if mount != null:
		mount.pos = pos # ridden pal travels with the player
	if iv.length() > 0 and dodge_t <= 0:
		var sp := speed * spd_mult * (1.7 if Input.is_action_pressed("sprint") \
				and (stamina > 0.0 or mount != null) else 1.0)
		var step := iv.normalized() * sp * dt
		var nx: float = pos.x + step.x
		var ny: float = pos.y + step.y
		if can_enter(nx, pos.y):
			pos.x = nx
		if can_enter(pos.x, ny):
			pos.y = ny
		moving = true
		if iv.x > 0.02:
			dir = 1
		elif iv.x < -0.02:
			dir = -1
	elif dodge_t > 0:
		# dodge roll: burst along the real facing (dir is x-only)
		var v := facing * 0.4 + Input.get_vector("move_left", "move_right", "move_up", "move_down") * 0.6
		var nx: float = pos.x + v.normalized().x * 9.0 * dt
		var ny: float = pos.y + v.normalized().y * 9.0 * dt
		if can_enter(nx, pos.y):
			pos.x = nx
		if can_enter(pos.x, ny):
			pos.y = ny
		moving = true
	sync_screen()

func dismount_if(p: Pal) -> void:
	if mount == p:
		mount.visible = true
		mount = null

func try_mount() -> void:
	if mount:
		mount.visible = true
		mount.mode = "partner"
		mount = null
		game.log_msg("Dismounted")
		return
	if game.net != null and game.net.is_client():
		# replicas are host-driven — riding one would fight its net_target lerp
		game.log_msg("Can't ride a host pal over the wire")
		return
	var best: Pal = null
	var bd := 1.4
	for p in game.pals:
		# Palworld: land mounts AND rideable flyers (bird body) — but each
		# wants its own tack (land/sky/wave saddle)
		if p.uid in game.party and p.mode == "partner" and game.has_saddle_for(p) \
				and (SpeciesData.mountable(p.species_id) or SpeciesData.body_of(p.species_id) == "bird"):
			var d := pos.distance_to(p.pos)
			if d < bd:
				bd = d
				best = p
	if best:
		mount = best
		best.visible = false
		game.log_msg("Riding %s" % best.spec["name"])
	else:
		game.log_msg("No mountable pal nearby (right saddle in pack?)")

func shoot_weapon(wd: Dictionary) -> void:
	var ammo_id: String = wd.get("ammo", "")
	if ammo_id != "" and game.item_count(ammo_id) <= 0:
		game.log_msg("Out of " + ammo_id)
		return
	atk_cd = wd.get("cd", 0.7)
	if ammo_id != "":
		game.add_item(ammo_id, -1)
	var m := get_global_mouse_position()
	var tw: Vector2 = Iso.from_screen(m.x, m.y, elev())
	game.fire_player_shot(tw, wd)

func armor_def() -> int:
	return int((ItemData.ITEMS.get(equipment["armor"], {}).get("armor", {}).get("def", 0) + acc_total("def") + game.partner_aura("def")) * (1.0 + meal_bonus("def")))

func meal_bonus(stat: String) -> float:
	# Palworld meal bonus: one cooked-food buff at a time, timed
	if meal_t <= 0.0:
		return 0.0
	return float(meal_buff.get(stat, 0.0))

func eat_buff(b: Dictionary) -> void:
	meal_buff = {"atk": b.get("atk", 0.0), "def": b.get("def", 0.0), "spd": b.get("spd", 0.0)}
	for k in meal_buff.keys(): # keep only the stats the meal actually grants
		if float(meal_buff[k]) <= 0.0:
			meal_buff.erase(k)
	meal_t = float(b.get("t", 300.0))

func wear_tick() -> void: # Palworld tools wear out — a swing costs a use
	if weapon_wear > 0.0:
		weapon_wear -= 1.0
		if weapon_wear <= 0.0:
			game.break_weapon(equipment["weapon"])

func wear_armor() -> void:
	# Palworld armor wears too — every hit taken chews the plate
	if armor_wear > 0.0:
		armor_wear -= 1.0
		if armor_wear <= 0.0:
			game.break_armor(equipment["armor"])

func acc_total(k: String) -> float: # Palworld trinket math — both slots stack
	var t := 0.0
	for s in ["acc1", "acc2"]:
		t += float(ItemData.ITEMS.get(equipment[s], {}).get("acc", {}).get(k, 0.0))
	return t
