extends Entity
class_name Player
# WASD/arrows move · SHIFT sprint · LMB melee/harvest · Q aim sphere ·
# click throws · E interact · SPACE dodge.

var game: Game
var hp := 100.0
var hunger := 80.0          # 0-100; drains ~100 over ~22 min
var max_hp := 100.0
var level := 1
var xp := 0
var capture_level := 1
var dodge_t := 0.0
var mount: Pal = null
var facing := Vector2(1, 0)  # last move direction, for harvest/interact
var equipment := {"weapon": "", "armor": ""}
var atk_cd := 0.0
var sphere_sel := 0
var aiming := false
var statuses := {}

func setup(g: Game, at: Vector2) -> void:
	game = g
	world = g.world
	pos = at
	speed = 5.0
	setup_visuals("res://assets/pals/player_f0.png", "res://assets/pals/player_f1.png")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		aiming = not aiming
	if event.is_action_pressed("cycle_sphere"):
		sphere_sel = (sphere_sel + 1) % maxi(1, game.sphere_tiers().size())
	if event.is_action_pressed("dodge") and dodge_t <= 0:
		dodge_t = 0.35
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
	if wd.get("range", 0) > 3:
		shoot_weapon(wd)
		return
	atk_cd = wd.get("cd", 0.45)
	var atk: float = (wd.get("dmg", 15) * 2.0 + level * 4.0) * (1.0 + game.perks["atk"] * 0.08)
	var reach: float = wd.get("range", 1.6)
	var hit_any := false
	for p in game.pals.duplicate():
		if p.mode != "wild" or p.hp <= 0:
			continue
		if pos.distance_to(p.pos) > reach:
			continue
		var mult := Combat.effectiveness("neutral", p.elem())
		var d := Combat.damage(atk, 34, Combat.stat_at(p.spec["def"], p.level, p.talent) * p.def_bonus, mult, game.rng)
		p.hit(d, mult, true)
		hit_any = true
	if not hit_any:
		game.try_harvest(pos, facing)

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

func speed_mult() -> float:
	var m := 1.0
	if mount != null:
		m *= 1.8
	if hunger < 25.0:
		m *= 0.8
	if statuses.get("freeze", 0) > game.t:
		m *= 0.5
	if statuses.get("soak", 0) > game.t:
		m *= 0.7
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
	hunger = maxf(0.0, hunger - dt * 0.075)
	if hunger <= 0.0:
		hp = maxf(1.0, hp - dt * 0.4)   # starving: slow drain to 1hp
	var spd_mult := speed_mult()
	if statuses.get("sleep", 0) > game.t:
		iv = Vector2.ZERO
	if mount != null:
		mount.pos = pos # ridden pal travels with the player
	if iv.length() > 0 and dodge_t <= 0:
		var sp := speed * spd_mult * (1.7 if Input.is_action_pressed("sprint") else 1.0)
		var step := iv.normalized() * sp * dt
		var nx: float = pos.x + step.x
		var ny: float = pos.y + step.y
		if not world.blocked(int(nx), int(pos.y), pos.x, pos.y):
			pos.x = nx
		if not world.blocked(int(pos.x), int(ny), pos.x, pos.y):
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
		if not world.blocked(int(nx), int(pos.y), pos.x, pos.y):
			pos.x = nx
		if not world.blocked(int(pos.x), int(ny), pos.x, pos.y):
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
	var best: Pal = null
	var bd := 1.4
	for p in game.pals:
		if p.uid in game.party and p.mode == "partner" and SpeciesData.mountable(p.species_id):
			var d := pos.distance_to(p.pos)
			if d < bd:
				bd = d
				best = p
	if best:
		mount = best
		best.visible = false
		game.log_msg("Riding %s" % best.spec["name"])
	else:
		game.log_msg("No mountable pal nearby")

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
	return int(ItemData.ITEMS.get(equipment["armor"], {}).get("armor", {}).get("def", 0))
