extends Entity
class_name Kin
# A kin in the world: wild (wander/flee/aggro), partner (follows player,
# auto-attacks), or base worker (job site later).

var game: Game
var uid := 0
var species_id := ""
var level := 1
var xp := 0
var hp := 1.0
var max_hp := 1.0
var san := 80.0
var hunger := 0.0
var talent := 0
var mode := "wild"           # wild | partner | base
var statuses := {}           # kind -> until_t
var aggro := -1              # -1 none, 0 player, >0 pal uid
var wander_t := 0.0
var train_t := 0.0            # sparring clock at a training dummy
var bed_seek := 0.0           # seconds spent shuffling toward a bed at night
var sleep_rested := false    # reached a real bed — a floor nap recovers less
var carry = null             # {id,n} while hauling
var haul_scan_t := 0.0       # rescan clock — keeps the O(cells) sweeps off the per-frame path
var haul_cell := Vector2i(-1, -1) # cached chest cell while carrying
var haul_dest := Vector2.ZERO     # last scanned walk target for the pickup leg
var carry_hold_t := 0.0     # seconds on-paw — an unreachable stash drops the goods eventually
var stall_warn_t := 0.0     # throttles the "nowhere to stash" floater
var foe_scan_t := 0.0       # guard-scan clock — keeps the O(pals) sweep off the per-frame path
var foe_cache: Kin = null   # last raider seen — valid until the next rescan
var bed_scan_t := 0.0       # bed-scan clock + structure generation — memoized like nearest_heat
var bed_scan_gen := -1
var bed_cell := Vector2i(-1, -1)
var dummy_scan_t := 0.0     # sparring-scan clock — same memo shape as the bed scan
var dummy_scan_gen := -1
var dummy_cell := Vector2i(-1, -1)
var home := Vector2.ZERO     # spawn anchor; alphas tether to their lair
var target := Vector2.ZERO
var atk_cd := 0.0
var spec: Dictionary = {}
var job_site = null
var sex := "M"
var alpha := false
var fav := false            # heart-locked: butcher/sell/condense all skip it
var soul_boost := 0         # statue infusions, 0..10 — +4% stats each
var boss := false
var passives := []
var extra_skills := []        # taught via skill fruits — survives beyond the level table
var ai_accum := 0.0
var needs_t := 0.0
var skill_cd := {}
var stun_t := 0.0
var revive_t := 0.0         # >0 while knocked out in the box
var ailment := ""           # "" | depressed | sprain | ulcer | weakened (the island SAN sickness)
var berserk_t := 0.0        # a depressed base pal at zero SAN chews the yard until it burns out
var stance := "auto"        # pal command: auto defends / aggressive hunts / passive holds
var petted_t := -60.0       # last pet timestamp — affection runs on a per-pal cooldown
var bounty := 0             # >0: wanted mark — the kill pays gold on the spot
var equipped := []          # up to 3 moves slotted at the kinbox — empty = everything learned
var low_san_t := 0.0        # sustained seconds under SAN 15 — onset timer
var lucky := false          # rare "Lucky" variant: big, strong, golden drops
var net_id := 0             # >0: host-authoritative replica on a client (keyed by host uid)
var net_target := Vector2.INF # last host-reported world pos (INF = none yet)
var owner_id := 0           # multiplayer owner: 0 = the keeper (host/local), >0 = a client's peer id
var mounted_by := 0         # peer id of the rider — a bound mount follows its rider, never wanders.
	# transient by design: rides pal_state_pack (wire field 11) but not the
	# save — a kin saved mid-ride reloads as a free, visible partner; the
	# rider's mount ref dies with player.mount=null on load anyway
var owner_tag := ""         # keeper's stable install token — survives save/load across sessions

func setup(g: Game, sp_id: String, lv: int, at: Vector2) -> void:
	game = g
	world = g.world
	species_id = sp_id
	spec = SpeciesData.species_of(sp_id)
	swims = "water" in spec.get("elements", [])
	level = lv
	talent = game.rng.int_range(0, 100)
	max_hp = Combat.stat_at(spec["hp"], level, talent)
	hp = max_hp
	san = spec.get("san", 80)
	pos = at
	target = at
	home = at
	speed = base_move_speed()
	uid = game.next_uid()
	sex = "M" if game.rng.chance(0.5) else "F"
	name = "pal_%s_%d" % [sp_id, uid] # debuggable in orphan/crash dumps
	roll_passives()
	if lucky and "lucky" not in passives:
		passives.push_front("lucky") # signature passive always survives the 4-slot trim
		while passives.size() > 4:
			passives.pop_back()
	apply_bonuses() # folds passives + star/alpha/boss hp multipliers into max_hp
	hp = max_hp
	setup_visuals("res://assets/kin/%s_f0.png" % sp_id, "res://assets/kin/%s_f1.png" % sp_id)
	if alpha:
		sprite.scale = Vector2(1.6, 1.6)
		sprite.position.y = -51.0
	elif lucky:
		sprite.scale = Vector2(1.5, 1.5)
		sprite.position.y = -48.0

func base_move_speed() -> float:
	# species.gd stores tiles/sec (2-3.5); species_gen.gd carries stat-scale
	# values (40-88+) — normalize both onto a sane tiles/sec curve
	var s: float = spec.get("speed", 2.6)
	if s > 10.0:
		return 1.8 + s * 0.035
	return s

func hostile() -> int:
	return spec.get("hostile", 1)

func add_status(kind: String, dur: float) -> void:
	statuses[kind] = game.t + dur

func has_status(kind: String) -> bool:
	return statuses.get(kind, 0.0) > game.t

func any_status() -> bool:
	for k in statuses:
		if statuses[k] > game.t:
			return true
	return false

func hit(dmg: int, mult: float, by_player: bool, provoked_pid: int = 0) -> void:
	if net_id > 0:
		return # replicas take wounds only through the host's pal_sync — a local
		# hit would spawn ghost adds (phase 2) and ghost respawn timers
	hp -= dmg
	hit_flash = 0.4
	if hp > 0 and rage_mult() > 1.0 and not _enraged:
		_enraged = true
		game.floater(pos, tr("ENRAGED!"), "#ff5544")
	if boss and phase == 1 and hp > 0 and hp < max_hp * 0.5:
		enter_phase_two()
	game.floater(pos, str(dmg) + ("!" if mult >= 2 else ("·" if mult <= 0.6 else "")),
		"#e8d44d" if mult >= 2 else "#e8f0f2")
	if hp <= 0:
		game.kill_pal(self, by_player, provoked_pid)
	else:
		statuses.erase("sleep") # any hit wakes, whatever the mode
		if mode == "wild":
			if by_player:
				# the island focus fire: the partner kin piles onto your target
				game.focus_target = self
				game.focus_t = game.t + 4.0
			if hostile() == 0 and game.rng.chance(0.5):
				aggro = -1
				aggro_pid = 0
			else:
				aggro = 0
				aggro_pid = provoked_pid # the blow's owner takes the heat — a guest's swing must not make the host tank
			# the island herds turn as one: a packmate under attack pulls the
			# whole flock into the same fight-or-flight stance
			for m in game.pals:
				if m != self and m.mode == "wild" and m.hp > 0 and m.home == home \
						and m.home != Vector2.ZERO and m.aggro < 0:
					m.aggro = aggro
					m.aggro_pid = aggro_pid if aggro == 0 else 0
					m.statuses.erase("sleep")

# ---- boss phases: at half health the guardian changes the fight ----
var phase := 1
var summon_t := 0.0 # transient by design — a save mid-charge just re-arms
var slam_windup := 0.0 # rooted telegraph before the ring lands — dodge
# window. transient by design: phase (the durable bit) is serialized;
# a reload during the tell simply re-arms the cadence
var spire_tag := "" # non-empty on Pact-spire guardians; game.record_spire reads it

func enter_phase_two() -> void:
	phase = 2
	game.screen_shake(0.6)
	game.floater(pos, tr("IT CALLS THE PACK"), "#ff9966")
	game.sfx_play("horn")
	game.cry_for(species_id) # the boss roars in its own voice
	# two loyal adds answer the roar — capped per boss, capped by MAX_PALS
	var n := 0
	for q in game.pals:
		if q.mode == "wild" and q.hp > 0 and q.get_meta("summoner", -1) == uid:
			n += 1
	while n < 2 and game.pals.size() < game.MAX_PALS:
		var m := preload("res://src/kin.gd").new()
		game.entity_layer.add_child(m)
		m.setup(game, species_id, maxi(1, level - 10),
			game.nearest_free(pos.x + 1.0, pos.y))
		m.set_meta("summoner", uid)
		m.aggro = 0
		m.aggro_pid = aggro_pid
		m.home = home
		game.pals.append(m)
		n += 1

func pact_slam() -> int:
	# phase-two signature: a shock ring that punishes the pile-up — and at a
	# Pact spire the ring carries the shrine's element, so each guardian's
	# slam asks a different question of the roster you brought. Returns the
	# victim count so tests can see the zone hit who it should.
	game.floater(pos, tr("PACT SLAM"), "#ff5544")
	var hits := 0
	var ail := ""
	if game.spire_tag_ok(spire_tag): # int() eats garbage→0; the validator doesn't
		var si := int(spire_tag.trim_prefix("spire_"))
		ail = {"fire": "burn", "water": "soak", "grass": "poison",
			"dark": "sleep", "dragon": ""}.get(str(game.SPIRE_DEFS[si]["elem"]), "")
	var pl = game.player
	if pl != null and pos.distance_to(pl.pos) <= 2.6:
		game.hurt_player(spec.get("atk", 50) * 0.8 * rage_mult(), self)
		hits += 1
		if ail != "": # the ring carries the shrine's element — everyone in it
			game.player_status(ail, 3.0)
	if aggro_pid > 0 and game.net != null: # the ring is a zone — a guest inside it eats it too
		var gp2 = game.net.ghosts.get(aggro_pid)
		if gp2 != null and gp2.net_pos.x >= 0 \
				and pos.distance_to(Vector2(gp2.net_pos.x, gp2.net_pos.y)) <= 2.6:
			if game.net_live(): # a dead peer can't take the rpc — the count still stands
				game.net.rpc_id(aggro_pid, "guest_skill_hit",
					spec.get("atk", 50) * 0.8 * rage_mult(), ail, 3.0)
			hits += 1 # the zone contained them — the rpc is the delivery, not the verdict
	# hit→kill_pal erases pals — snapshot or the next victim walks free
	for q in game.pals.duplicate():
		if q != self and q.hp > 0 and q.mode == "partner" \
				and pos.distance_to(q.pos) <= 2.6: # punish the pile-up, not parked farmhands
			q.hit(maxi(2, int(spec.get("atk", 40) * 0.5 * rage_mult())), 1.0, false)
			hits += 1
			if ail != "":
				q.add_status(ail, 3.0)
	return hits

func elem() -> Array:
	return spec.get("elements", ["neutral"])

func status_speed_mult() -> float:
	var m := 1.0
	if has_status("freeze"):
		m *= 0.5
	if has_status("soak"):
		m *= 0.7
	if ailment == "sprain":
		m *= 0.6
	return m

# the island ailments: a sick kin underperforms until it gets medicine.
const AILMENTS := ["depressed", "sprain", "ulcer", "weakened"]
func work_mult() -> float:
	var bond := 1.1 if petted_t > game.t else 1.0 # a recently petted pal works lighter
	match ailment:
		"depressed": return 0.4 * bond
		"sprain": return 0.6 * bond
		_: return bond
func atk_mult() -> float:
	return (0.7 if ailment == "weakened" else 1.0) * rage_mult()

# the island boss rule: cornered giants fight meaner — under 30% hp they hit
# and run 40% harder
func rage_mult() -> float:
	return 1.4 if (boss or alpha) and hp > 0 and hp < max_hp * 0.3 else 1.0
var _enraged := false
func def_mult() -> float:
	return 0.7 if ailment == "weakened" else 1.0

func _notification(what: int) -> void:
	# dev trace: a kin detached from the tree without landing in the box is a
	# leak — UNPARENTED fires on every remove_child, so we report the mode too.
	if what == NOTIFICATION_UNPARENTED and OS.has_environment("PLG_ORPHANS") and game != null:
		print("unparented: %s mode=%s in_box=%s in_pals=%s" % [name, mode, game.box.has(self), game.pals.has(self)])
		for frame in get_stack().slice(0, 4):
			print("   <- %s:%d %s" % [frame.get("source", "?"), frame.get("line", 0), frame.get("function", "?")])

func _physics_process(dt: float) -> void:
	if hp <= 0:
		return
	if mounted_by > 0:
		# bound to a rider — AI sleeps, but a replica still renders the host's
		# reported pos (the rider's own copy also gets pos-set by player.gd)
		if net_id > 0 and net_target.x < 1e17:
			pos = pos.lerp(net_target, minf(1.0, dt * 6.0))
			sync_screen()
		return
	if game != null and game.state == "paused" and not game.net_live():
		return # pause freezes wildlife; the title lets it wander for ambience
	if net_id > 0:
		# host-authoritative replica: render the reported state, never simulate —
		# local AI would fight the host's corrections and drift the two worlds apart
		if net_target.x < 1e17:
			pos = pos.lerp(net_target, minf(1.0, dt * 6.0))
		sync_screen()
		return
	tick_statuses(dt)
	stun_t -= dt
	if has_status("sleep") or stun_t > 0:
		if mode == "base" and has_status("sleep"):
			san = minf(100.0, san + (3.0 if sleep_rested else 1.0) * dt)
			# the island: a night in a real bed knits wounds; floor naps help less
			hp = minf(max_hp, hp + max_hp * (0.004 if sleep_rested else 0.0015) * dt)
		sync_screen()
		return
	speed = base_move_speed() * speed_bonus * status_speed_mult() * rage_mult() # passive speed must survive the per-frame recompute
	atk_cd -= dt
	# far wild kin tick their AI at ~8Hz (accumulated dt keeps speeds honest)
	var far := mode == "wild" and pos.distance_squared_to(game.player.pos) > 784.0
	ai_accum += dt
	if far and ai_accum < 0.12:
		sync_screen()
		return
	var adt: float = ai_accum if far else dt
	ai_accum = 0.0
	if mode != "wild":
		tick_needs(dt)
	match mode:
		"wild":
			wild_ai(adt)
		"partner":
			partner_ai(dt)
		"base":
			base_ai(dt)
	sync_screen()

func chew_adjacent_structure() -> bool:
	# raid pressure (the island): walls and buildings are obstacles raiders break
	var c := Vector2i(int(pos.x), int(pos.y))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k: Vector2i = c + d
		var st = game.structures.get(k)
		if st != null and not st.get("walkable", false):
			atk_cd = 1.1
			game.hit_structure(k, maxi(3, int(spec.get("atk", 40) * 0.25)))
			return true
	return false

func wild_ai(dt: float) -> void:
	var pl := game.player
	var dist := pos.distance_to(pl.pos)
	if raid and atk_cd <= 0 and chew_adjacent_structure():
		sync_screen()
		return
	# sleep by the clock, not the species: diurnal kin doze after dark,
	# nocturnal dark kin nap through the day — sneaking works at both ends;
	# apex hostiles keep watch around the clock
	var nocturnal_w: bool = "dark" in spec.get("elements", [])
	if game.is_night() != nocturnal_w and aggro < 0 and hit_flash <= 0 and hostile() < 2:
		statuses["sleep"] = game.t + 2.0
		return
	if aggro == 0:
		# raiders storm the BASE: target the nearest defender, not just the player
		if raid:
			var bt: Kin = null; var bd := dist
			for bp in game.pals:
				if bp.mode != "base" or bp.hp <= 0:
					continue
				var dd := pos.distance_to(bp.pos)
				if dd < bd:
					bd = dd; bt = bp
			if bt != null and bd <= 1.1 and atk_cd <= 0:
				atk_cd = 1.1
				bt.hit(maxi(2, int(spec.get("atk", 40) * 0.4 * rage_mult())), 1.0, false)
				return
			elif bt != null:
				if not cast_skills(bt, dt):
					step_toward(bt.pos, dt)
				return
		# fight player if aggressive; timid flees — the target is the nearest
		# warm body: the local player or a connected guest's ghost
		if hostile() >= 1:
			var tpos := target_pos()
			var tdist := pos.distance_to(tpos)
			# the island: beaten-down prey bolts — ordinary hostiles turn tail at
			# low hp; alphas, bosses, raiders and apex species never break
			if hostile() == 1 and hp < max_hp * 0.25 and not alpha and not boss and not raid:
				step_toward(pos + (pos - tpos).normalized() * 5.0, dt)
				if tdist > 16:
					aggro = -1; aggro_pid = 0
				return
			# pact-slam cadence: charge 5s, then a rooted 0.8s telegraph — the
			# ring lands where the boss stood, so the pile-up gets a beat to
			# scatter. Windup check sits before movement or the boss would
			# track victims while "planting" (no dodge, no counterplay)
			if boss and phase == 2:
				if slam_windup > 0.0:
					slam_windup -= dt
					if slam_windup <= 0.0:
						pact_slam()
					return # rooted while the ring charges — scatter or eat it
				summon_t += dt
				if summon_t >= 5.0:
					summon_t = 0.0
					slam_windup = 0.8
					game.floater(pos, tr("IT REARS UP"), "#ffcc44") # the tell
					if game.net != null and game.net.ghosts.size() > 0 \
							and game.net_live(): # a ghost can outlive its peer by a frame
						game.net.rpc("net_floater", pos.x, pos.y,
							"IT REARS UP", "#ffcc44") # guests read the same cue
			# skills aim at whoever holds the aggro — the keeper or a guest's
			# ghost. Ghosts are position-only, so only projectile/self kinds
			# can address them (lunges/bursts need a real body; the melee
			# bite covers what those would have done anyway)
			var shot := false
			if aggro_pid == 0:
				shot = cast_skills(pl, dt)
			elif game.net != null:
				var g = game.net.ghosts.get(aggro_pid)
				if g != null and g.net_pos.x >= 0:
					shot = cast_skills(Vector2(g.net_pos.x, g.net_pos.y), dt,
						["projectile", "multi", "self"])
			if not shot:
				if tdist > 1.1:
					step_toward(tpos, dt)
				elif atk_cd <= 0:
					atk_cd = 1.1
					if aggro_pid > 0:
						if game.net_live(): # bite only ships while the peer can receive it
							game.net.rpc_id(aggro_pid, "guest_hit",
								spec.get("atk", 50) * rage_mult()) # the host's bite lands on the guest
					else:
						game.hurt_player(spec.get("atk", 50) * rage_mult(), self)
			elif tdist > spec.get("reach", 4.0):
				step_toward(tpos, dt)
			if tdist > 14:
				aggro = -1; aggro_pid = 0
		else:
			step_toward(pos + (pos - pl.pos).normalized() * 5.0, dt)
			if dist > 10:
				aggro = -1
		return
	elif aggro > 0:
		var tp: Kin = game.find_pal(aggro)
		if tp == null or tp.hp <= 0:
			aggro = -1
		else:
			var pd := pos.distance_to(tp.pos)
			if not cast_skills(tp, dt):
				if pd > 1.1:
					step_toward(tp.pos, dt)
				elif atk_cd <= 0:
					atk_cd = 1.1
					tp.hit(maxi(2, int(spec.get("atk", 40) * 0.35 * rage_mult())), 1.0, false)
			elif pd > spec.get("reach", 4.0):
				step_toward(tp.pos, dt)
			if pd > 16:
				aggro = -1
		return
	# lair alpha: tethered to its lair; engages only on home ground
	if alpha:
		if pos.distance_squared_to(home) > 81.0:
			step_toward(home, dt)
			return
		if dist < 6.0 and not has_status("sleep"):
			aggro = 0
			aggro_pid = nearest_body_pid() # a guest in the lair is a trespasser too
			return
	# a de-aggro'd raider re-targets the base instead of wandering home
	if raid:
		var bt2: Kin = null; var bd2 := 30.0
		for bp in game.pals:
			if bp.mode != "base" or bp.hp <= 0:
				continue
			var dd2 := pos.distance_to(bp.pos)
			if dd2 < bd2:
				bd2 = dd2; bt2 = bp
		if bt2 != null:
			aggro = bt2.uid
			return
		if dist < 14.0:
			aggro = 0 # base wiped of defenders — turn on the nearest warm body
			aggro_pid = nearest_body_pid()
			return
	# bait: a tossed mash pulls hungry wild kin off their wander — the
	# first snout to reach the pile wolfs it down (the island chum play)
	if mode == "wild" and aggro < 0 and game.lure and game.t < float(game.lure.get("till", 0.0)):
		var lp: Vector2 = game.lure["pos"]
		var ld := pos.distance_to(lp)
		if ld < 14.0:
			if ld > 0.9:
				target = lp
				step_toward(target, dt)
			else:
				game.lure_take(self)
			return
	# wander
	wander_t -= dt
	if wander_t <= 0:
		wander_t = 1.5 + game.rng.next() * 3.0
		var a := game.rng.next() * TAU
		target = pos + Vector2(cos(a), sin(a)) * (1.5 + game.rng.next() * 3.0)
		if has_meta("ring_kin") and home != Vector2.ZERO and target.distance_to(home) > 6.0:
			target = home + Vector2(cos(a), sin(a)) * 2.0 # opening kin hold their ground
	step_toward(target, dt)
	# aggro check — apex pounces from further out, ordinary hostiles at arm's
	# length; the nearest warm body wins, host player or a guest's ghost
	var trigger := 5.0 if hostile() == 2 else 3.5
	if game.is_night() and "dark" in spec.get("elements", []):
		trigger += 2.0 # the island nocturnals: dark pals hunt wider after dusk
	var near_pid := 0
	var nd := dist
	if game.net != null:
		near_pid = nearest_body_pid()
		if near_pid > 0:
			nd = pos.distance_to(target_pos_for(near_pid))
	if hostile() >= 1 and nd < trigger and not has_status("sleep"):
		aggro = 0
		aggro_pid = near_pid

func nearest_body_pid() -> int:
	# the nearest living guest ghost, or 0 when the host player is closest —
	# every "turn on the player" provoke runs through here so a raid can't
	# be kited onto the host while a guest throws the punches
	var best := 0
	var bd := pos.distance_to(game.player.pos)
	if game.net == null:
		return 0
	for pid in game.net.ghosts:
		var g = game.net.ghosts[pid]
		if g == null or g.net_pos.x < 0:
			continue
		var gd := pos.distance_to(Vector2(g.net_pos.x, g.net_pos.y))
		if gd < bd:
			bd = gd; best = pid
	return best

func target_pos_for(pid: int) -> Vector2:
	var g = game.net.ghosts.get(pid)
	return Vector2(g.net_pos.x, g.net_pos.y) if g != null else game.player.pos

var aggro_pid := 0 # engaged target: 0 = local player, >0 = a guest's ghost peer id
func target_pos() -> Vector2:
	if aggro_pid > 0 and game.net != null:
		var g = game.net.ghosts.get(aggro_pid)
		if g != null and g.net_pos.x >= 0:
			return Vector2(g.net_pos.x, g.net_pos.y)
		aggro_pid = 0 # the ghost left — fall back to the player
	return game.player.pos

func anchor_pos() -> Vector2:
	# a guest's partner heels to its keeper's ghost, not to our player —
	# host kin keep the old anchor so single-player is untouched
	if owner_id > 0 and game.net != null:
		var g = game.net.ghosts.get(owner_id)
		if g != null and g.net_pos.x >= 0:
			return Vector2(g.net_pos.x, g.net_pos.y)
	return game.player.pos

func partner_ai(dt: float) -> void:
	if not visible:
		pos = anchor_pos()
		return
	# attack nearest wild kin threatening player — stance tunes who counts
	# (the island kin commands: auto defends, aggressive hunts on sight)
	var best: Kin = null
	var bd := 6.0 if stance != "aggressive" else 9.0
	if stance != "passive":
		for p in game.pals:
			if p.mode != "wild" or p.hp <= 0:
				continue
			if stance != "aggressive" \
					and p.aggro != 0 and p.aggro != uid and not p.raid \
					and not (p.aggro > 0 and p.aggro in game.party):
				continue # threats: hunting the player, me, a party member, or raiders
			var d := pos.distance_to(p.pos)
			if d < bd:
				bd = d
				best = p
	# the island focus fire: whatever the player just hit outranks the nearest threat
	var focus: Kin = game.focus_target
	if stance != "passive" and is_instance_valid(focus) and focus.hp > 0 \
			and focus.mode == "wild" and game.t < game.focus_t:
		var fd := pos.distance_to(focus.pos)
		if fd < 10.0:
			best = focus; bd = fd
	if best:
		if not cast_skills(best, dt):
			if bd > 1.0:
				step_toward(best.pos, dt)
			elif atk_cd <= 0:
				atk_cd = 1.0
				var mult := Combat.effectiveness("neutral", best.elem())
				var d := Combat.damage(Combat.stat_at(spec["atk"], level, talent) * atk_bonus * atk_mult(), 30,
					Combat.stat_at(best.spec["def"], best.level, best.talent) * best.def_bonus * best.def_mult(), mult, game.rng)
				best.hit(d, mult, true, owner_id) # a guest's pal provokes the guest, not the host
		elif bd > 5.0:
			step_toward(best.pos, dt)
		return
	# the island fetch: an idle partner pads over to nearby drops and bags them
	var grab = null
	var gd := 16.0
	for d in game.drops:
		var dd := pos.distance_squared_to(d["pos"])
		if dd < gd:
			gd = dd; grab = d
	if grab != null:
		if pos.distance_squared_to(grab["pos"]) > 0.4:
			step_toward(grab["pos"], dt)
		elif grab in game.drops: # a hauler may have beaten us to it
			game.give_remote(owner_id, grab["id"], grab["n"])
			game.floater(grab["pos"], tr("+%d %s") % [grab["n"],
				tr(str(ItemData.ITEMS.get(grab["id"], {}).get("name", grab["id"])))], "#ffe08a")
			game.take_drop(grab)
		return
	var anchor := anchor_pos()
	if pos.distance_to(anchor) > 1.8:
		step_toward(anchor, dt)

func find_foe() -> Kin:
	# nearest flagged hostile on the beat — 12 tiles for a posted sentry,
	# the usual 7 for yard hands; mode/aggro gates live here so tests and AI agree
	var foe: Kin = null
	var fbd := 12.0 if (job_site is Dictionary and job_site.get("id") == "guard_post") else 7.0
	for p in game.pals:
		if p.mode != "wild" or p.hp <= 0:
			continue
		if not p.raid and p.aggro < 0:
			continue
		var dd := pos.distance_to(p.pos)
		if dd < fbd:
			fbd = dd; foe = p
	return foe

func base_ai(dt: float) -> void:
	# the island despair: a depressed kin left at zero SAN snaps — it rampages
	# through the yard chewing whatever it can reach until it burns out
	if berserk_t > 0.0:
		berserk_t -= dt
		if not chew_adjacent_structure():
			var bk := Vector2i(-1, -1); var bd2 := 1e9
			for k in game.structures:
				var st2: Dictionary = game.structures[k]
				if st2.get("walkable", false):
					continue
				var dd2 := pos.distance_squared_to(Vector2(k.x + 0.5, k.y + 0.5))
				if dd2 < bd2:
					bd2 = dd2; bk = k
			if bk.x >= 0:
				step_toward(Vector2(bk.x + 0.5, bk.y + 0.5), dt)
		if berserk_t <= 0.0:
			ailment = "weakened" # the fit passes — but it leaves the pal wrung out
			game.log_msg(tr("%s burned out — now weakened") % spec["name"])
			game.floater(pos, tr("burned out"), "#a8a8a8")
		sync_screen()
		return
	# bed_seek re-arms on every sleep instead — a fixed daytime reset would
	# never let a nocturnal kin's 6s walk budget run out before dusk
	# defend the base: raiders beating on workers get fought back (the island's
	# crew covers the yard, not just arm's reach)
	# a posted guard watches a wider beat than a yard hand — the island's
	# sentries pull raids off the workers, not just off their own toes
	foe_scan_t -= dt
	if foe_scan_t <= 0.0:
		foe_scan_t = 0.4 # raiders don't teleport — a short cache beats a per-frame O(pals) sweep
		foe_cache = find_foe()
	elif foe_cache != null and (not is_instance_valid(foe_cache) \
			or foe_cache.hp <= 0 or foe_cache.mode != "wild"):
		foe_cache = null # a KO'd/boxed raider is no target — next rescan re-arms
	var foe: Kin = foe_cache
	if foe != null:
		if not cast_skills(foe, dt):
			if pos.distance_to(foe.pos) > 1.1:
				step_toward(foe.pos, dt)
			elif atk_cd <= 0:
				atk_cd = 1.0
				var mult := Combat.effectiveness("neutral", foe.elem())
				var d := Combat.damage(Combat.stat_at(spec["atk"], level, talent) * atk_bonus * atk_mult(), 25,
					Combat.stat_at(foe.spec["def"], foe.level, foe.talent) * foe.def_bonus * foe.def_mult(), mult, game.rng)
				foe.hit(d, mult, true, owner_id) # a guest's pal provokes the guest, not the host
		return
	# the island night shift: diurnal kin doze off after dark — production skips
	# sleepers; dark-element kin are nocturnal — lights on overnight, napping
	# through the day shift instead (otherwise their SAN never recovers).
	# Tired kin pad over to the nearest kin bed first when one is built.
	var nocturnal: bool = "dark" in spec.get("elements", [])
	if game.is_night() != nocturnal:
		bed_scan_t -= dt
		if bed_scan_t <= 0.0 or bed_scan_gen != game._struct_gen:
			bed_scan_t = 0.4
			bed_scan_gen = game._struct_gen # beds come and go — the cache rides the generation
			bed_cell = game.nearest_bed_cell(pos)
		var bc := bed_cell
		var rested := false
		if bc.x >= 0:
			var bp := Vector2(bc.x + 0.5, bc.y + 0.5)
			if pos.distance_to(bp) > 1.2 and bed_seek < 6.0:
				bed_seek += dt # shuffling to bed beats dozing at the workbench
				step_toward(bp, dt)
				return
			rested = pos.distance_to(bp) <= 1.8
		sleep_rested = rested # the island: a real bed restores SAN far better
		statuses["sleep"] = game.t + 2.0
		bed_seek = 0.0
		return
	if job_site:
		var site_cell: Vector2i = job_site.get("pos", Vector2i(-1, -1)) # the anchor cell — no dict scan needed
		if site_cell.x >= 0:
			var sp2 := Vector2(site_cell.x + 0.5, site_cell.y + 0.5)
			if job_site.get("id") == "expedition_post" and pos.distance_to(sp2) < 1.6 \
					and float(job_site.get("exp_end", 0.0)) <= 0.0 \
					and game.t >= float(job_site.get("exp_cd", 0.0)):
				# the island expedition: the posted gatherer marches off-map and
				# comes back later with a haul keyed to its element
				mode = "expedition"
				visible = false
				var glv: int = int(spec.get("work", {}).get("gathering", 0))
				var dur: float = 600.0 * (1.0 - 0.05 * mini(glv, 4))
				job_site["exp_end"] = game.t + maxf(dur, 240.0)
				job_site["exp_pal"] = self
				game.log_msg(tr("%s sets off on an expedition") % tr(str(spec.get("name", species_id))))
				return
			step_toward(sp2, dt)
	elif spec.get("work", {}).get("transporting", 0) > 0:
		haul_ai(dt)
	else:
		# the island training dummy: an idle kin marches to the nearest straw man
		# and spars — fighters earn their keep between raids instead of
		# milling about the yard
		dummy_scan_t -= dt
		if dummy_scan_t <= 0.0 or dummy_scan_gen != game._struct_gen:
			dummy_scan_t = 0.4
			dummy_scan_gen = game._struct_gen
			dummy_cell = Vector2i(-1, -1)
			var dbd := 100.0
			for k2 in game.structures:
				if game.structures[k2]["id"] != "training_dummy":
					continue
				var dd3 := pos.distance_squared_to(Vector2(k2.x + 0.5, k2.y + 0.5))
				if dd3 < dbd:
					dbd = dd3; dummy_cell = k2
		var dk := dummy_cell
		if dk.x >= 0:
			var dp := Vector2(dk.x + 0.5, dk.y + 0.5)
			if pos.distance_to(dp) > 1.3:
				step_toward(dp, dt)
			else:
				train_t += dt
				if train_t >= 3.0:
					train_t = 0.0
					game.pal_gain_xp(self, 2) # slow honest reps
			return
		wander_t -= dt
		if wander_t <= 0:
			wander_t = 2.0 + game.rng.next() * 3.0
			var a := game.rng.next() * TAU
			target = pos + Vector2(cos(a), sin(a)) * 2.0
		if pos.distance_to(target) > 0.4:
			step_toward(target, dt)

func haul_ai(dt: float) -> void:
	haul_scan_t -= dt
	if carry != null:
		carry_hold_t += dt # goods on-paw too long means the stash is a fiction
		if carry_hold_t > 90.0:
			game.spawn_drop(carry["id"], carry["n"], pos) # give up honestly — the pile waits for a real chest
			carry = null
			carry_hold_t = 0.0
			haul_cell = Vector2i(-1, -1)
			game.floater(pos, tr("%s gave up hauling") % tr(str(spec.get("name", species_id))), "#ffcf7a")
			game.log_msg(tr("%s couldn't reach a chest — goods dropped at its feet") % tr(str(spec.get("name", species_id))))
			return
		if haul_scan_t <= 0.0:
			haul_scan_t = 0.4 # chests don't move — a short cache beats a per-frame dict sweep
			haul_cell = game.nearest_chest_cell(pos, carry["id"])
		if haul_cell.x < 0:
			stall_warn_t -= dt
			if stall_warn_t <= 0.0: # no chest can take it — hold, wander, say so
				stall_warn_t = 15.0
				game.floater(pos, tr("%s has nowhere to stash %s") % \
					[tr(str(spec.get("name", species_id))), tr(str(ItemData.ITEMS.get(carry["id"], {}).get("name", carry["id"])))], "#ffcf7a")
			wander_t -= dt
			if wander_t <= 0:
				wander_t = 2.0 + game.rng.next() * 3.0
				var wa := game.rng.next() * TAU
				target = pos + Vector2(cos(wa), sin(wa)) * 2.0
			if pos.distance_to(target) > 0.4:
				step_toward(target, dt)
			return
		var cp := Vector2(haul_cell.x + 0.5, haul_cell.y + 0.5)
		if pos.distance_to(cp) > 1.8:
			step_toward(cp, dt)
		else:
			if not game.structures.has(haul_cell) or game.structures[haul_cell]["id"] not in ["chest", "feed_box"]:
				haul_cell = Vector2i(-1, -1)
				return # chest was demolished mid-walk — keep holding the goods
			var st: Dictionary = game.structures[haul_cell]
			if not game.chest_can_take(st, carry["id"]):
				return # filled up since it was picked — retarget next frame instead of over-stacking
			st["store"][carry["id"]] = st["store"].get(carry["id"], 0) + carry["n"]
			carry = null
		return
	# between rescans just keep walking the last leg — targets outlive 0.4s easily
	if haul_scan_t > 0.0:
		if pos.distance_to(haul_dest) > 0.4:
			step_toward(haul_dest, dt)
		return
	haul_scan_t = 0.4
	# first: production sites holding goods -> move one stack to a chest
	var bd := 24.0 * 24.0; var bd2 := bd
	var site_pick = null; var site_id := ""
	for k in game.structures:
		var st2: Dictionary = game.structures[k]
		if st2["id"] in ["chest", "feed_box"] or st2.get("store", {}).is_empty():
			continue # feed_box stock is the pals' own food — hauling it out starves the base
		var dd2 := pos.distance_squared_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd2 < bd2:
			bd2 = dd2; site_pick = k
	if site_pick != null:
		var sst: Dictionary = game.structures[site_pick]
		var cp2 := Vector2(site_pick.x + 0.5, site_pick.y + 0.5)
		haul_dest = cp2
		if pos.distance_to(cp2) > 1.6:
			step_toward(cp2, dt)
		else:
			if sst["store"].is_empty():
				return # another hauler emptied it between scan and pickup
			site_id = sst["store"].keys()[0]
			carry = {"id": site_id, "n": sst["store"][site_id]}
			sst["store"].erase(site_id)
			carry_hold_t = 0.0
			haul_cell = Vector2i(-1, -1); haul_scan_t = 0.0 # fresh goods → rescan a chest next frame
		return
	bd2 = bd
	var pick = null
	for d in game.drops:
		var dd := pos.distance_squared_to(d["pos"])
		if dd < bd2:
			bd2 = dd; pick = d
	if pick == null:
		wander_t -= dt
		if wander_t <= 0:
			wander_t = 2.0 + game.rng.next() * 3.0
			var a := game.rng.next() * TAU
			target = pos + Vector2(cos(a), sin(a)) * 2.0
		haul_dest = target
		if pos.distance_to(target) > 0.4:
			step_toward(target, dt)
		return
	haul_dest = pick["pos"]
	if pos.distance_to(pick["pos"]) > 0.6:
		step_toward(pick["pos"], dt)
	else:
		if pick not in game.drops:
			return # a faster hauler already claimed it — no loot duplication
		carry = {"id": pick["id"], "n": pick["n"]}
		game.take_drop(pick)
		carry_hold_t = 0.0
		haul_cell = Vector2i(-1, -1); haul_scan_t = 0.0

func tick_needs(dt: float) -> void:
	needs_t += dt
	if needs_t < 1.0:
		return
	needs_t = 0
	if mode not in ["base", "partner"]: # wild pals have no needs (the island rule) —
		return                       # starvation left them at 0hp forever otherwise
	hunger = minf(100.0, hunger + 0.5 * passive_mult("food") * (2.0 if ailment == "ulcer" else 1.0))  # Glutton eats more; ulcers starve fast
	san = maxf(0.0, san - ((0.2 * game.cur_san_mult) if job_site else 0.05)
		/ passive_mult("san")) # the stand's work pace sets cur_san_mult
	# low SAN is the sickness trigger (the island): sustained misery -> ailment
	if ailment == "":
		if san < 15.0:
			low_san_t += 1.0
			if low_san_t > 60.0:
				ailment = AILMENTS[game.rng.int_range(0, AILMENTS.size() - 1)]
				game.log_msg(tr("%s developed %s! Give it medicine.") % [tr(str(spec["name"])), tr(str(ailment))])
				game.floater(pos, tr(str(ailment)).to_upper(), "#d06a6a")
				low_san_t = 0.0
		else:
			low_san_t = 0.0
	else: # sick pals self-medicate: base stock for workers, the bag for partners
		if owner_id > 0 and mode == "partner":
			pass # a guest's pal can't raid the host's bag — its keeper packs the meds
		elif game.take_medicine(mode == "partner"):
			ailment = ""
			san = minf(100.0, san + 30.0)
			game.log_msg(tr("%s took medicine - recovered") % spec["name"])
			game.floater(pos, tr("cured!"), "#a8e6a1")
		elif ailment == "depressed" and san <= 0.5 and mode == "base" and berserk_t <= 0.0:
			# no medicine in reach and nothing left in the tank — it snaps
			berserk_t = 15.0
			job_site = null # storm off the shift
			game.log_msg(tr("%s is going BERSERK — keep medicine stocked!") % spec["name"])
			game.floater(pos, tr("BERSERK!"), "#e8452f")
	if hunger > 70:
		var ate := 0
		if mode == "base" and game.has_structure("feed_box"):
			ate = game.eat_food_item() # stocked base food
		elif mode == "partner" and owner_id <= 0:
			ate = game.eat_from_bag() # party pals share the player's pack
		if ate > 0:
			hunger = maxf(0, hunger - float(ate) * 2.5)
			san = minf(100, san + 4.0 + ate * 0.5) # the island: a real meal lifts spirits — berries barely help
		elif mode in ["base", "partner"]:
			san = maxf(0.0, san - 0.6)  # starving with no food to find: SAN bleeds
	if hunger >= 100.0:
		hp -= maxi(1, int(max_hp * 0.02)) # prolonged starvation costs real hp
		if hp <= 0 and mode in ["base", "partner"]:
			game.kill_pal(self, false)
	# recovery ladder: a hot spring outranks a straw mat (the island base comfort)
	if mode == "base" and san < 70 and game.has_structure("hot_spring"):
		san = minf(100.0, san + 10.0)
	elif mode == "base" and san < 30 and game.has_structure("kin_bed"):
		san = minf(100.0, san + 6.0)  # resting requires being AT the base
	# the island: a party kin at ease beside you recovers its spirits
	if mode == "partner" and aggro < 0 and san < 60.0:
		san = minf(100.0, san + 2.5)

func active_skills() -> Array:
	# the island loadout: only the slotted three fire; untouched kin run wide
	return equipped if not equipped.is_empty() else learned_skills()

func learned_skills() -> Array:
	var out := []
	for e in spec.get("skills", []):
		if level >= e[0]:
			out.append(e[1])
	for sid in extra_skills: # skill-fruit moves — no level gate once taught
		if sid not in out:
			out.append(sid)
	return out

func tick_statuses(dt: float) -> void:
	for k in statuses.keys():
		if statuses[k] <= game.t:
			statuses.erase(k)
			continue
		match k:
			"burn":
				if int(game.t * 5) != int((game.t - dt) * 5):
					take_dps(maxi(1, int(max_hp * 0.02)))
			"poison":
				if int(game.t * 3) != int((game.t - dt) * 3):
					take_dps(maxi(1, int(max_hp * 0.012)))
			"shock":
				if game.rng.chance(dt * 0.25):
					stun_t = 0.45

func take_dps(n: int) -> void:
	hp -= n
	hit_flash = 0.2
	if hp <= 0:
		game.kill_pal(self, false)

func cast_skills(target_ent, dt: float, kinds := []) -> bool:
	# target_ent may be a Player, a Kin, or a bare Vector2 (a guest ghost has
	# no body — aim the shot at its coordinates instead)
	var tp: Vector2 = target_ent if target_ent is Vector2 else target_ent.pos
	var dist := pos.distance_to(tp)
	var best: Dictionary = {}
	for sid in active_skills():
		if skill_cd.get(sid, 0) > game.t:
			continue
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		if sk.is_empty() or dist > sk.get("range", 1.4):
			continue
		if not kinds.is_empty() and sk.get("kind", "projectile") not in kinds:
			continue
		if best.is_empty() or sk.get("power", 0) > best.get("power", 0):
			best = sk # strongest usable skill, not the lowest-level one
	if best.is_empty():
		return false
	skill_cd[best["id"]] = game.t + best.get("cooldown", 2)
	game.cast_skill(self, target_ent, best)
	return true

func apply_skill_status(sk: Dictionary, is_behind: bool = false) -> void:
	var st = sk.get("status")
	if st and game.rng.chance(st.get("chance", 1.0)):
		add_status(st["kind"], st.get("dur", 3))

func roll_passives() -> void:
	passives.clear()
	var keys := PassiveData.PASSIVES.keys()
	# the island trait slots: 1 guaranteed, then 45%/30%/15% for slots 2-4
	var n := 1
	if game.rng.chance(0.45): n += 1
	if game.rng.chance(0.30): n += 1
	if game.rng.chance(0.15): n += 1
	for i in n:
		var k: String = keys[game.rng.int_range(0, keys.size() - 1)]
		if k not in passives:
			passives.append(k)
	apply_bonuses()

func passive_mult(field: String) -> float:
	var m := 1.0
	for k in passives:
		m *= PassiveData.PASSIVES.get(k, {}).get(field, 1.0) # stale save keys skip safely
	return m

func apply_bonuses() -> void:
	atk_bonus = 1.0
	def_bonus = 1.0
	speed_bonus = 1.0
	var pv: Dictionary
	for k in passives:
		pv = PassiveData.PASSIVES.get(k, {})
		atk_bonus *= pv.get("atk", 1.0)
		def_bonus *= pv.get("def", 1.0)
		speed_bonus *= pv.get("speed", 1.0)
	# star rank stacks on top of passives (the island essence condenser)
	var star_mult := pow(1.15, star)
	atk_bonus *= star_mult
	def_bonus *= star_mult
	max_hp = Combat.stat_at(spec["hp"], level, talent) * star_mult
	# statue souls: each infusion is a flat +4% across the board
	var soul := 1.0 + soul_boost * 0.04
	atk_bonus *= soul; def_bonus *= soul; max_hp *= soul
	# kindex mastery: ten of a kind caught sharpens every one you keep
	if mode != "wild" and game != null and int(game.catch_counts.get(species_id, 0)) >= 10:
		atk_bonus *= 1.1
		def_bonus *= 1.1
	if lucky: # rare variant hits harder and tanks harder
		atk_bonus *= 1.2
		def_bonus *= 1.2
		max_hp *= 1.5
	if alpha:
		max_hp *= 4.0
	if boss:
		max_hp *= 2.0
	hp = minf(hp, max_hp)

# condense: +1 star rank; stats scale, current hp grows proportionally
func condense() -> void:
	star += 1
	var frac := hp / maxf(1.0, max_hp)
	apply_bonuses()
	hp = max_hp * frac

var atk_bonus := 1.0
var def_bonus := 1.0
var speed_bonus := 1.0
var star := 0                # essence-condense rank 0-4; each star multiplies combat stats
var raid := false            # spawned by a raid wave — blocks sleeping
