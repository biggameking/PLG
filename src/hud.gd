extends Control
# HUD + panels: HP/XP, spheres, log, time, party; B build / I inv / T tech /
# E interact (craft near workbench, palbox mgmt near palbox); ESC closes.

var game: Game
var font := ThemeDB.fallback_font
var show_help := false
var dex_scroll := 0
var build_sel := -1
var click_rects := []   # [{rect, act, arg}]
var chat_buf := ""
var join_buf := ""

var map_img: Image = null
var map_tex: ImageTexture = null # cached — was rebuilt every frame the map was open
var map_show := false

func bake_minimap() -> void:
	var W := game.world
	map_img = Image.create(W.WORLD_W, W.WORLD_H, false, Image.FORMAT_RGB8)
	var cols := {
		W.Tile.WATER: Color(0.13, 0.34, 0.62), W.Tile.SAND: Color(0.85, 0.76, 0.53),
		W.Tile.GRASS: Color(0.24, 0.55, 0.24), W.Tile.TALLGRASS: Color(0.16, 0.44, 0.18),
		W.Tile.FLOWER: Color(0.42, 0.62, 0.30), W.Tile.STONEFIELD: Color(0.48, 0.48, 0.52),
		W.Tile.DIRT: Color(0.55, 0.42, 0.28), W.Tile.FARMLAND: Color(0.62, 0.48, 0.28)}
	for y in W.WORLD_H:
		for x in W.WORLD_W:
			var c: Color = cols.get(W.tile_at(x, y), Color.BLACK)
			var e := W.elev_at(x, y)
			if W.tile_at(x, y) != W.Tile.WATER and W.tile_at(x, y) != W.Tile.SAND:
				c = c.lightened(e * 0.09)
			map_img.set_pixel(x, y, c)

	map_tex = ImageTexture.create_from_image(map_img)
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	# chat input mode (net only)
	if game.panel == "chat" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if chat_buf.strip_edges() != "" and game.net:
				game.net.rpc("chat", chat_buf, multiplayer.get_unique_id())
				game.log_msg("[you] " + chat_buf)
			chat_buf = ""; game.panel = ""
		elif event.keycode == KEY_ESCAPE:
			chat_buf = ""; game.panel = ""
		elif event.keycode == KEY_BACKSPACE:
			chat_buf = chat_buf.left(-1)
		elif event.unicode >= 32 and event.unicode < 127:
			chat_buf += char(event.unicode)
		get_viewport().set_input_as_handled()
		return
	# join-ip input mode
	if game.panel == "join" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			var ip := join_buf.strip_edges()
			if ip == "": ip = "127.0.0.1"
			if game.net: game.net.join(ip)
			join_buf = ""; game.panel = ""
		elif event.keycode == KEY_ESCAPE:
			join_buf = ""; game.panel = ""
		elif event.keycode == KEY_BACKSPACE:
			join_buf = join_buf.left(-1)
		elif event.unicode >= 33 and event.unicode < 127 and not event.unicode == 32:
			join_buf += char(event.unicode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER 		and game.panel == "" and game.net and multiplayer.multiplayer_peer != null:
		game.panel = "chat"; chat_buf = ""
		return
	if event.is_action_pressed("help"):
		show_help = not show_help
		return
	if event.is_action_pressed("ui_cancel") and game.panel != "":
		game.panel = ""
		return
	if event.is_action_pressed("build"):
		game.panel = "" if game.panel == "build" else "build"
		build_sel = -1
		return
	if event.is_action_pressed("inv"):
		game.panel = "" if game.panel == "inv" else "inv"
		return
	if event.is_action_pressed("tech"):
		game.panel = "" if game.panel == "tech" else "tech"
		return
	if event.is_action_pressed("statues"):
		game.panel = "" if game.panel == "statues" else "statues" # U: lifmunk effigy upgrades
		return
	if event.is_action_pressed("dex"):
		game.panel = "" if game.panel == "dex" else "dex" # P: paldeck
		dex_scroll = 0
		return
	if game.panel == "dex" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dex_scroll = maxi(0, dex_scroll - 1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dex_scroll += 1
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("party_toggle"):
		game.assign_worker()
		return
	if event.is_action_pressed("demolish"):
		game.demolish_at(mouse_tile())
		return
	if event.is_action_pressed("map"):
		map_show = not map_show
		if map_show:
			bake_minimap() # rebake every open — terrain/decor change and load_game swaps the world
		return
	if event.is_action_pressed("interact"):
		interact()
		return
	if event.is_action_pressed("save"):
		game.save_game()
		return
	if event.is_action_pressed("load_save"):
		game.load_game()
		return
	if event.is_action_pressed("host_net"):
		if game.net: game.net.host() # J: host on :7777 — these actions were bound but unwired
		return
	if event.is_action_pressed("join_net"):
		if game.net and game.panel == "":
			game.panel = "join"; join_buf = "" # K: type the host's IP, Enter to join
		return
	if event is InputEventKey and event.pressed and game.panel == "build":
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			var lst := game.buildable_list()
			var i := k - KEY_1
			build_sel = i if i < lst.size() else -1
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for cr in click_rects:
			if cr["rect"].has_point(event.position):
				run_click(cr)
				return
		if game.panel == "build" and build_sel >= 0:
			place_ghost()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and game.panel == "build":
		build_sel = -1
		game.panel = ""

func run_click(cr: Dictionary) -> void:
	match cr["act"]:
		"craft":
			game.craft(cr["arg"])
		"tech":
			game.unlock(cr["arg"])
		"box_out":
			game.box_to_party(cr["arg"])
		"party_in":
			game.party_to_box(cr["arg"])
		"lead":
			game.make_active(cr["arg"])
		"deploy":
			game.deploy_to_base(cr["arg"])
		"base_in":
			game.base_to_box(cr["arg"])
		"use_item":
			use_item(cr["arg"])
		"buy":
			game.buy_from_merchant(cr["arg"])
		"sell":
			game.sell_to_merchant(cr["arg"])
		"sell_pal":
			game.sell_pal_to_merchant(cr["arg"])
		"butcher":
			game.butcher_pal(cr["arg"])
		"fav":
			game.toggle_fav(cr["arg"])
		"travel":
			game.travel_to(cr["arg"])
		"equip":
			game.equip(cr["arg"])
		"perk":
			game.upgrade_perk(cr["arg"])
		"infuse":
			game.soul_infuse(cr["arg"])
		"chest_dep", "chest_wd":
			var st = game.chest_ref
			var cc: Vector2i = game.cell_of(st) if st != null else Vector2i(-1, -1)
			if cc.x < 0 or game.player.pos.distance_to(Vector2(cc.x + 0.5, cc.y + 0.5)) > 5.0:
				game.chest_ref = null
				game.panel = "" # walked too far — the container is out of reach
				return
			if cr["act"] == "chest_dep":
				game.log_msg("Stored %d items" % game.chest_deposit_all(st))
			else:
				game.log_msg("Took %d items" % game.chest_withdraw_all(st))

func interact() -> void:
	if game.merchant != null and game.player.pos.distance_to(game.merchant.pos) < 2.4:
		game.panel = "shop"
		return
	var f: Vector2 = game.player.facing
	var probe := Vector2(signf(f.x), 0) if absf(f.x) >= absf(f.y) else Vector2(0, signf(f.y))
	var st = game.structure_at(game.player.pos + probe * 0.8)
	if not st:
		st = game.structure_at(game.player.pos)
	if not st: # facing misses big structures diagonally — fall back to nearest
		var bd := 2.2
		for k in game.structures:
			var dd: float = game.player.pos.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
			if dd < bd:
				bd = dd; st = game.structures[k]
	if st:
		match st["id"]:
			"workbench", "campfire":
				game.craft_station = st["id"]
				game.panel = "craft"
				return
			"furnace", "mill", "crusher", "logging_site", "stone_pit", "gathering_site", "ore_mine", "berry_farm", "wheat_farm", "oil_extractor", "pharmacy", "generator", "ranch", "cooler":
				# automated sites: E reports the stockpile, no crafting here
				var sdef: Dictionary = StructureData.STRUCTURES.get(st["id"], {})
				var eggs: String = "  %d egg(s)" % st["store"].get("pal_egg", 0) if st["id"] == "ranch" and st.get("store", {}).get("pal_egg", 0) > 0 else ""
				if st.get("store", {}).is_empty():
					game.log_msg("%s: %d workers, nothing stored" % [sdef.get("name", st["id"]), st["workers"].size()])
				else:
					game.log_msg("%s stores: %s%s" % [sdef.get("name", st["id"]), str(st["store"]), eggs])
				return
			"feed_box":
				game.chest_ref = st # pals eat out of it; it's still a container
				game.panel = "chest"
				return
			"pal_bed":
				game.log_msg("Pal bed: base pals resting here recover SAN")
				return
			"palbox":
				game.panel = "palbox"
				return
			"straw_bed":
				game.sleep_to_morning()
				return
			"waypoint":
				game.use_waypoint()
				return
			"chest":
				game.chest_ref = st
				game.panel = "chest"
				return
			"monitoring_stand":
				game.cycle_work_mode()
				return
			"pal_condenser":
				game.condense_active()
				return
			"incubator":
				var inc = st.get("egg_inc")
				if inc is Dictionary:
					var hint: String = game.egg_hint(inc.get("pair"))
					game.log_msg("Incubating %s: %ds left" % [hint if hint != "" else "egg",
						int(maxi(0.0, float(inc.get("ready_t", 0.0)) - game.t))])
				elif game.item_count("pal_egg") > 0:
					game.deposit_egg()
				else:
					game.log_msg("Incubator empty - bring a pal egg")
				return
			"wooden_wall", "spikes":
				game.log_msg("%s (HP %d)" % [StructureData.STRUCTURES[st["id"]]["name"], int(st.get("hp", 0))])
				return
	if game.has_structure("palbox"):
		game.panel = "palbox"
		return
	game.log_msg("Nothing to interact with")

func mouse_tile() -> Vector2:
	var m := get_global_mouse_position()
	var c: Camera2D = get_viewport().get_camera_2d()
	var w := (m - get_viewport_rect().size / 2) / c.zoom.x + c.global_position
	return Iso.from_screen(w.x, w.y, game.player.elev())

func place_ghost() -> void:
	var tw := mouse_tile()
	var bl := game.buildable_list()
	if build_sel >= bl.size(): # list shrank since the bar was drawn
		build_sel = maxi(0, bl.size() - 1)
		return
	game.place_structure(bl[build_sel], int(tw.x), int(tw.y))

func w2s(p: Vector2) -> Vector2:
	var c: Camera2D = get_viewport().get_camera_2d()
	return (p - c.global_position) * c.zoom.x + get_viewport_rect().size / 2

func _draw() -> void:
	if not game or not game.player:
		return
	click_rects = []
	var pl := game.player
	var r := get_viewport_rect().size
	draw_rect(Rect2(12, 10, 224, 18), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(14, 12, int(220 * clampf(pl.hp / pl.max_hp, 0, 1)), 14), Color("#4caf50"))
	draw_rect(Rect2(12, 30, 224, 10), Color(0, 0, 0, 0.55))
	var hc: Color = Color("#e6a23c") if pl.hunger >= 25 else Color("#e0503c")
	draw_rect(Rect2(14, 32, int(220 * clampf(pl.hunger / 100.0, 0, 1)), 6), hc)
	draw_string(font, Vector2(16, 25), "HP %d/%d  Lv%d  XP%d" % [int(pl.hp), int(pl.max_hp), pl.level, pl.xp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var tiers := game.sphere_tiers()
	var sx := 12
	for id in ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]:
		var n := game.item_count(id)
		if n <= 0:
			continue
		var sel := tiers.find(id) == pl.sphere_sel
		draw_rect(Rect2(sx, 44, 70, 20), Color(0, 0, 0, 0.55))
		if sel:
			draw_rect(Rect2(sx, 44, 70, 20), Color("#4dd0e1"), false, 1.5)
		draw_string(font, Vector2(sx + 4, 49), "%s x%d" % [ItemData.ITEMS[id]["name"].left(7), n],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		sx += 74
	draw_equipment_line() # was never called — gear row under the sphere chips
	if pl.aiming:
		draw_string(font, Vector2(12, 96), "AIM — click a pal to throw (Q cancel)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#4dd0e1"))
		# Palworld throw preview: hovering a wild pal shows the catch odds
		var tiers2 := game.sphere_tiers()
		if not tiers2.is_empty():
			var sid2: String = tiers2[clampi(pl.sphere_sel, 0, tiers2.size() - 1)]
			var mp2 := get_global_mouse_position()
			var tw2: Vector2 = Iso.from_screen(mp2.x, mp2.y, pl.elev())
			var bp2: Pal = null
			var bd2 := 1.6
			for q in game.pals:
				if q.mode != "wild" or q.hp <= 0:
					continue
				var dd := q.pos.distance_to(tw2)
				if dd < bd2:
					bd2 = dd
					bp2 = q
			if bp2:
				var cap_pow2: float = bp2.spec["capturePower"] * (1.35 if bp2.lucky else 1.0)
				var ch := minf(0.97, Combat.catch_chance(maxf(0.0, bp2.hp) / bp2.max_hp, cap_pow2,
					ItemData.ITEMS[sid2].get("spherePower", 26), bp2.any_status(), false, pl.capture_level))
				var col := Color("#a8e6a1") if ch >= 0.5 else (Color("#e8963c") if ch >= 0.2 else Color("#e8452f"))
				draw_string(font, Vector2(12, 112), "Catch %s Lv%d: %d%%" % [bp2.spec["name"], bp2.level, int(ch * 100)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_rect(Rect2(r.x - 140, 10, 128, 20), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(r.x - 132, 25), "Day %d  %02d:00%s" % [game.day, int(game.tod),
		"  ☂" if game.weather == "rain" else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color("#7fb8e8") if game.weather == "rain" else Color("#e8f0f2"))
	if game.raid_t < 30.0 and game.palbox_pos.x >= 0: # Palworld raid horn
		draw_rect(Rect2(r.x / 2 - 80, 8, 160, 22), Color(0.5, 0.06, 0.06, 0.7))
		draw_string(font, Vector2(r.x / 2 - 62, 24), "RAID IN %ds" % int(ceilf(game.raid_t)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff8d7e"))
	# boss bar: nearest alpha/boss in the fray gets a name + hp strip
	var boss: Pal = null
	var bd := 18.0
	for q in game.pals:
		if q.hp <= 0 or not (q.boss or q.alpha):
			continue
		if q.mode == "box" or q.mode == "partner":
			continue
		var dd: float = q.pos.distance_to(game.player.pos)
		if dd < bd:
			bd = dd; boss = q
	if boss:
		var frac: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		var bw := 240.0
		draw_rect(Rect2(r.x / 2 - bw / 2, 34, bw, 16), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.x / 2 - bw / 2 + 1, 35, (bw - 2) * frac, 14),
			Color("#c0392b") if boss.boss else Color("#e8963c"))
		draw_string(font, Vector2(r.x / 2 - bw / 2 + 4, 47),
			"%s %s Lv%d" % ["BOSS" if boss.boss else "α", boss.spec["name"], boss.level],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	if game.mission_idx < game.MISSIONS.size(): # Palworld guide rope
		draw_rect(Rect2(r.x - 220, 32, 208, 18), Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(r.x - 214, 45), "★ %s" % game.MISSIONS[game.mission_idx]["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8ef0ff"))
	var my := r.y - 24
	for i in range(game.messages.size()):
		var m: String = game.messages[game.messages.size() - 1 - i]
		draw_string(font, Vector2(14, my - i * 18), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	var py := 38
	for uid in game.party:
		var p := game.find_pal(uid)
		if not p:
			continue
		draw_rect(Rect2(r.x - 150, py, 138, 16), Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(r.x - 144, py + 13), "%s Lv%d %s" % [p.spec["name"], p.level,
			"●" if p.mode == "partner" else "○"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f0d0"))
		py += 18
	# build ghost preview
	if game.panel == "build" and build_sel >= 0:
		var tw := mouse_tile()
		var sid: String = game.buildable_list()[build_sel]
		var s: Dictionary = StructureData.STRUCTURES[sid]
		var w: int = s.get("w", 2)
		var h: int = s.get("h", 2)
		var ok := game.can_place(sid, int(tw.x), int(tw.y))
		var col := Color(0.3, 0.9, 0.4, 0.45) if ok else Color(0.95, 0.3, 0.2, 0.45)
		for dy in range(h):
			for dx in range(w):
				var e: int = game.world.elev_at(int(tw.x) + dx, int(tw.y) + dy)
				var pc := Iso.to_screen(int(tw.x) + dx + 0.5, int(tw.y) + dy + 0.5, e)
				var sc := w2s(pc)
				draw_colored_polygon([sc + Vector2(0, -16), sc + Vector2(32, 0), sc + Vector2(0, 16), sc + Vector2(-32, 0)], col)
	match game.panel:
		"build":
			draw_build_bar(r)
		"tech":
			draw_tech(r)
		"statues":
			draw_statues(r)
		"craft":
			draw_craft(r)
		"chest":
			draw_chest(r)
		"inv":
			draw_inv(r)
		"palbox":
			draw_palbox(r)
		"shop":
			draw_shop(r)
		"dex":
			draw_dex(r)
		"travel":
			draw_travel(r)
		"chat":
			draw_chat(r)
		"join":
			draw_join(r)
	if show_help:
		var lines := [
			"MOVE wasd/arrows  SPRINT shift  DODGE space",
			"MELEE/CHOP lmb  AIM q  THROW lmb  BALL tab",
			"BUILD b (1-9 pick, lmb place, rmb cancel)  INV i  TECH t",
			"INTERACT e (workbench=craft, palbox=manage)  ASSIGN f  HELP h",
			"MAP m    DEMOLISH x (under cursor)  RIDE r  PAL-SKILL g  STATUES u  PALDECK p  CHAT enter",
			"HOST j   JOIN k (type host IP, enter)  MERCHANT e (when visiting)",
			"Glider descends cliffs. Sick pals need medicine in feed box/bag.",
		]
		draw_rect(Rect2(10, r.y - 136, 580, 96), Color(0, 0, 0, 0.7))
		for i in range(lines.size()):
			draw_string(font, Vector2(20, r.y - 116 + i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dfe8ea"))

	# minimap (M): baked world image + live player/palbox markers
	if map_show and map_img != null:
		var vw := get_viewport_rect().size.x
		var ms := 176.0
		var mr := Rect2(vw - ms - 10, 10, ms, ms)
		draw_rect(mr.grow(2), Color(0, 0, 0, 0.7))
		if map_tex != null:
			draw_texture_rect(map_tex, mr, false)
		var plp := game.player.pos
		var pp := mr.position + Vector2(plp.x / game.world.WORLD_W * ms, plp.y / game.world.WORLD_H * ms)
		draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
		if game.palbox_pos.x >= 0:
			var pb := mr.position + Vector2(game.palbox_pos.x / float(game.world.WORLD_W) * ms, game.palbox_pos.y / float(game.world.WORLD_H) * ms)
			draw_rect(Rect2(pb - Vector2(2, 2), Vector2(4, 4)), Color(1, 0.55, 0.1))

func draw_build_bar(r: Vector2) -> void:
	var lst := game.buildable_list()
	var bx := 10.0
	var by := r.y - 200.0
	draw_rect(Rect2(bx, by, 620, 56), Color(0, 0, 0, 0.75))
	draw_string(font, Vector2(bx + 8, by + 16), "BUILD — pick 1-9" + ("  (placing: %s)" % StructureData.STRUCTURES[game.buildable_list()[build_sel]]["name"] if build_sel >= 0 else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#4dd0e1"))
	for i in range(mini(9, lst.size())):
		var s: Dictionary = StructureData.STRUCTURES[lst[i]]
		var cost := ""
		for c in s.get("cost", []):
			cost += "%d%s " % [c[1], c[0].left(4)]
		var col := Color("#4dd0e1") if i == build_sel else Color.WHITE
		var x := bx + 8 + (i % 5) * 122
		var y := by + 32 + (i / 5) * 14
		draw_string(font, Vector2(x, y), "%d %s %s" % [i + 1, s["name"].left(7), cost.left(9)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

func draw_tech(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 120, 480, 360)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "TECH  (pts: %d)" % game.tech_points,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d44d"))
	var colw := 232.0
	for ti in StructureData.TECH.size():
		var t: Dictionary = StructureData.TECH[ti]
		var k: String = t["id"]
		var has: bool = k in game.unlocked
		var afford: bool = game.tech_points >= t.get("cost", 0) \
			and game.item_count("ancient_part") >= t.get("parts", 0)
		var col := Color("#5a6068") if has else (Color.WHITE if afford else Color("#7a6a55"))
		if t.get("parts", 0) > 0 and not has:
			col = Color("#9c8bd4") if afford else Color("#5a4a80") # ancient tech is purple
		var label := "T%d %s [%d]%s%s" % [t.get("tier", 1), t.get("name", k).left(14), t.get("cost", 0),
			"+%d❖" % t["parts"] if t.get("parts", 0) > 0 else "", " ✓" if has else ""]
		var cx0: float = rr.position.x + 12 + (ti / 18) * colw
		var cy0: float = rr.position.y + 44 + (ti % 18) * 17
		if cy0 > rr.end.y - 10:
			continue # click rects only for rows actually drawn
		var rect := Rect2(cx0, cy0 - 12, colw - 14, 17)
		if not has:
			click_rects.append({"rect": rect, "act": "tech", "arg": k})
		draw_string(font, Vector2(cx0, cy0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

func draw_chest(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 220, 150, 440, 300)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "CHEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8c97a"))
	var st = game.chest_ref
	if st == null:
		return
	var y := rr.position.y + 52
	var rect1 := Rect2(rr.position.x + 16, y - 12, 200, 20)
	var rect2 := Rect2(rr.position.x + 230, y - 12, 190, 20)
	click_rects.append({"rect": rect1, "act": "chest_dep", "arg": null})
	click_rects.append({"rect": rect2, "act": "chest_wd", "arg": null})
	draw_string(font, rect1.position, "[ deposit all ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8e6a1"))
	draw_string(font, rect2.position, "[ take all ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8e6a1"))
	y += 28
	for iid in st.get("store", {}).keys():
		draw_string(font, Vector2(rr.position.x + 16, y), "%s  x%d" % [ItemData.ITEMS.get(iid, {}).get("name", iid), st["store"][iid]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		y += 18
		if y > rr.end.y - 16:
			break

func draw_craft(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 60, 480, 560)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8963c"))
	var y := rr.position.y + 48
	for rec in ItemData.RECIPES:
		if rec.get("station") not in [game.craft_station, "hand"]:
			continue
		if rec.get("tech", "") != "" and rec["tech"] not in game.unlocked:
			continue
		var afford := true
		var cost := ""
		for c in rec.get("cost", []):
			cost += "%d %s, " % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])]
			if game.item_count(c[0]) < c[1]:
				afford = false
		cost = cost.left(-2)
		var out_name: String = ItemData.ITEMS.get(rec["out"][0], {}).get("name", rec["out"][0])
		if y > rr.end.y - 16:
			break # don't leave click rects for rows that were never drawn
		var rect := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rect, "act": "craft", "arg": rec["id"]})
		draw_string(font, Vector2(rect.position.x, y), "%s x%d  <-  %s" % [out_name, rec["out"][1], cost.left(50)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if afford else Color("#5a6068"))
		y += 20
		if y > rr.end.y - 16:
			break
	if not game.craft_queue.is_empty(): # Palworld bench queue: builds tick down live
		y += 8
		draw_string(font, Vector2(rr.position.x + 16, y), "QUEUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8963c"))
		y += 16
		for cq in game.craft_queue:
			if y > rr.end.y - 14:
				break
			var nm: String = ItemData.ITEMS.get(cq["out"], {}).get("name", cq["out"])
			draw_string(font, Vector2(rr.position.x + 16, y), "  %s x%d  %.0fs" % [nm, cq["n"], cq["left"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a8e6a1"))
			y += 15

func draw_inv(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 230, 60, 460, 500)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#a8e6a1"))
	var keys := game.items.keys()
	keys.sort()
	var colw := 222.0
	var rows: int = int((rr.size.y - 66) / 16) # ~27 rows per column
	for ki in range(keys.size()):
		var k: String = keys[ki]
		var cx0: float = rr.position.x + 12 + (ki / rows) * colw
		var y0: float = rr.position.y + 46 + (ki % rows) * 16
		if cx0 + colw - 10 > rr.end.x: # third column would spill — stop
			break
		var nm: String = ItemData.ITEMS.get(k, {}).get("name", k)
		var usable: bool = ItemData.ITEMS.get(k, {}).get("usable", false)
		var equipable: bool = ItemData.ITEMS.get(k, {}).has("weapon") or ItemData.ITEMS.get(k, {}).has("armor") \
			or ItemData.ITEMS.get(k, {}).has("acc")
		var rect := Rect2(cx0, y0 - 12, colw - 12, 16)
		if equipable:
			click_rects.append({"rect": rect, "act": "equip", "arg": k})
			var worn: bool = game.player.equipment["acc1"] == k or game.player.equipment["acc2"] == k \
				or game.player.equipment["weapon"] == k or game.player.equipment["armor"] == k
			nm += "  [eq'd]" if worn else "  [eq]"
		elif usable:
			click_rects.append({"rect": rect, "act": "use_item", "arg": k})
			nm += "  [use]"
		draw_string(font, Vector2(cx0, y0), "%s x%d" % [nm.left(16), game.items[k]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd76e") if usable else Color.WHITE)

func draw_palbox(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 40, 600, 540)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "PALBOX — click to swap party/base",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4dd0e1"))
	var y := rr.position.y + 44
	draw_string(font, Vector2(rr.position.x + 16, y), "PARTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c8f0d0"))
	y += 18
	for uid in game.party:
		var p := game.find_pal(uid)
		if not p:
			continue
		var lead: bool = uid == game.party[0]
		var rect := Rect2(rr.position.x + 24, y - 11, 250, 17)
		click_rects.append({"rect": rect, "act": "party_in", "arg": uid})
		click_rects.append({"rect": Rect2(rect.position + Vector2(254, 0), Vector2(52, 17)), "act": "deploy", "arg": p})
		draw_string(font, Vector2(rect.position + Vector2(254, 13)), "[>base]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#a8e6a1"))
		if not lead:
			click_rects.append({"rect": Rect2(rect.position + Vector2(310, 0), Vector2(30, 17)), "act": "lead", "arg": uid})
			draw_string(font, Vector2(rect.position + Vector2(312, 13)), "[*]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd76e"))
		draw_string(font, Vector2(rect.position.x, y), "%s%s%s %s%s Lv%d T%d %s HP%d/%d" % [
			"★ " if lead else "", p.spec["name"],
			"☆" if p.lucky else "", p.sex, star_str(p), p.level, p.talent,
			(p.ailment + "! ") if p.ailment != "" else passive_str(p).left(14), int(p.hp), int(p.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8a0a0") if p.ailment != "" else Color.WHITE)
		y += 17
	# deployed workforce (Palworld: pals working the base live in the world)
	var workers := game.base_pals()
	if not workers.is_empty():
		y += 8
		draw_string(font, Vector2(rr.position.x + 16, y), "BASE (%d/%d) — click to recall" % [workers.size(), game.max_base_pals()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8dff0"))
		y += 18
		for wp in workers:
			var wrect := Rect2(rr.position.x + 24, y - 11, 250, 17)
			click_rects.append({"rect": wrect, "act": "base_in", "arg": wp})
			draw_string(font, Vector2(wrect.position.x, y), "%s%s %s Lv%d T%d %s%s" % [wp.spec["name"],
				"☆" if wp.lucky else "", wp.sex, wp.level, wp.talent,
				wp.job_site["id"] if wp.job_site else "idle",
				" [%s]" % wp.ailment if wp.ailment != "" else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d06a6a") if wp.ailment != "" else Color("#a8dff0"))
			y += 17
	y += 10
	draw_string(font, Vector2(rr.position.x + 16, y), "BOX (%d)" % game.box.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8963c"))
	y += 18
	var colw := 288.0
	var rows: int = int((rr.end.y - y - 8) / 16)
	for bi in range(game.box.size()):
		var bp: Pal = game.box[bi]
		var cx0: float = rr.position.x + 16 + (bi / rows) * colw
		var y0: float = y + (bi % rows) * 16
		if cx0 + colw - 8 > rr.end.x:
			break
		var butcher := game.item_count("meat_cleaver") > 0
		var rect := Rect2(cx0, y0 - 11, colw - (56 if butcher else 34), 16)
		click_rects.append({"rect": rect, "act": "box_out", "arg": bp})
		var frect := Rect2(cx0 + colw - (52 if butcher else 30), y0 - 11, 20, 16)
		click_rects.append({"rect": frect, "act": "fav", "arg": bp.uid})
		draw_string(font, Vector2(frect.position.x + 3, y0), "♥" if bp.fav else "♡",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e86a92") if bp.fav else Color(0.55, 0.55, 0.55))
		if butcher:
			var brect := Rect2(cx0 + colw - 30, y0 - 11, 22, 16)
			click_rects.append({"rect": brect, "act": "butcher", "arg": bp.uid})
			draw_string(font, Vector2(brect.position.x + 3, y0), "[x]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c0392b"))
		var ko: bool = bp.hp <= 0
		var label := "%s%s %s%s Lv%d T%d HP%d/%d%s%s" % [bp.spec["name"], "☆" if bp.lucky else "", bp.sex, star_str(bp), bp.level, bp.talent,
			int(maxi(0, bp.hp)), int(bp.max_hp), " [KO %ds]" % int(maxi(0.0, bp.revive_t - game.t)) if ko else "",
			" [%s]" % bp.ailment if bp.ailment != "" else ""]
		draw_string(font, Vector2(cx0, y0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d06a6a") if ko or bp.ailment != "" else Color("#c8d3d5"))

func draw_shop(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 60, 600, 480)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position.x + 16, rr.position.y + 24),
		"MERCHANT  (gold: %d)" % game.item_count("gold_coin"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d44d"))
	if game.merchant == null:
		draw_string(font, rr.position + Vector2(16, 50), "The merchant has left.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c8d3d5"))
		return
	var y := rr.position.y + 48
	draw_string(font, Vector2(rr.position.x + 16, y), "BUY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8e6a1"))
	draw_string(font, Vector2(rr.position.x + 316, y), "SELL (50%)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8963c"))
	y += 20
	var sy := y
	for i in range(game.merchant_stock.size()):
		var it: Dictionary = game.merchant_stock[i]
		var nm: String
		if it.has("pal"):
			var sp: Dictionary = SpeciesData.species_of(str(it["pal"]))
			nm = "Lv%d %s" % [it["lv"], sp.get("name", it["pal"])]
		else:
			nm = ItemData.ITEMS.get(it["id"], {}).get("name", it["id"])
		var rect := Rect2(rr.position.x + 16, y - 12, 270, 16)
		if it["n"] > 0:
			click_rects.append({"rect": rect, "act": "buy", "arg": i})
		var col := Color.WHITE if it["n"] > 0 else Color(0.45, 0.45, 0.45)
		draw_string(font, Vector2(rect.position.x, y), "%s x%d  %dg" % [nm.left(16), it["n"], it["price"]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		y += 17
		if y > rr.end.y - 14:
			break
	y = sy
	var skeys := game.items.keys()
	skeys.sort()
	for k in skeys:
		var price: int = ItemData.ITEMS.get(k, {}).get("price", 0)
		if price <= 0 or k == "gold_coin" or game.items[k] <= 0:
			continue
		var rect := Rect2(rr.position.x + 316, y - 12, 270, 16)
		click_rects.append({"rect": rect, "act": "sell", "arg": k})
		draw_string(font, Vector2(rect.position.x, y), "%s x%d  +%dg" % [ItemData.ITEMS[k]["name"].left(16),
			game.items[k], maxi(1, int(price * 0.5))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		y += 17
		if y > rr.end.y - 14:
			break
	var shown := 0
	for bp in game.box: # black-market: sell spare pals for coin
		if y > rr.end.y - 14 or shown >= 12:
			break
		var rect := Rect2(rr.position.x + 316, y - 12, 270, 16)
		click_rects.append({"rect": rect, "act": "sell_pal", "arg": bp.uid})
		draw_string(font, Vector2(rect.position.x, y), "Lv%d %s  +%dg" % [bp.level,
			String(bp.spec["name"]).left(14), game.pal_sell_price(bp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8963c"))
		y += 17
		shown += 1

func use_item(k: String) -> void:
	match k:
		"boss_sigil":
			if game.summon_raid():
				game.add_item(k, -1)
		"gauntlet_sigil":
			if game.start_gauntlet():
				game.add_item(k, -1)
		"pal_egg":
			game.deposit_egg()  # needs a free incubator nearby
		"fishing_rod":
			game.cast_line() # reusable — the rod never leaves the pack
		_:
			if k.begins_with("skill_fruit_"):
				game.teach_skill_fruit(k)
				return
			var it: Dictionary = ItemData.ITEMS.get(k, {})
			if it.get("heal", 0) > 0:
				if game.player.hp >= game.player.max_hp:
					game.log_msg("HP already full")
					return # don't burn the medicine
				game.player.hp = mini(game.player.max_hp, game.player.hp + it["heal"])
				game.add_item(k, -1)
				game.log_msg("+%d HP" % it["heal"])
			elif it.get("food", 0) > 0:
				if game.player.hunger >= 100.0:
					game.log_msg("Not hungry")
					return # don't waste the food at full satiety
				game.player.hunger = minf(100.0, game.player.hunger + it["food"])
				game.add_item(k, -1)
				game.log_msg("+%d food" % it["food"])
			else:
				game.log_msg("Can't use " + k)

func draw_join(r: Vector2) -> void:
	var rr := Rect2(10, r.y - 58, 520, 44)
	draw_rect(rr, Color(0, 0, 0, 0.8))
	draw_string(font, rr.position + Vector2(10, 19), "Join IP (blank=localhost): " + join_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9fd8ff"))

func draw_travel(r: Vector2) -> void:
	var nodes := game.travel_nodes()
	var rr := Rect2(r.x / 2 - 200, 80, 400, 90 + nodes.size() * 20)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, rr.position + Vector2(16, 24), "WAYPOINT NET",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#7fc8f8"))
	var y := rr.position.y + 50
	var me := Vector2i(game.player.pos)
	for n in nodes:
		var k: Vector2i = n["key"]
		var nm := "Palbox" if n["id"] == "palbox" else "Waypoint"
		var here := (k - me).length() < 3.0
		var rect := Rect2(rr.position.x + 16, y - 12, 360, 18)
		if not here:
			click_rects.append({"rect": rect, "act": "travel", "arg": k})
		var col := Color(0.5, 0.55, 0.6) if here else Color.WHITE
		draw_string(font, Vector2(rect.position.x, y), "%s%s  (%d,%d)  %dm" %
			[nm, "  ·here·" if here else "", k.x, k.y, int(n["dist"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		y += 20
	draw_string(font, Vector2(rr.position.x + 16, rr.end.y - 14),
		"click a node to blink there · esc closes", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.65))

func draw_dex(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 40, 600, 560)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	# caught first (most caught on top), then spotted, then the unknown dark
	var ids := []
	for sid in SpeciesData.SPECIES:
		ids.append(sid)
	for sid in SpeciesGen.SPECIES:
		if not SpeciesData.SPECIES.has(sid):
			ids.append(sid)
	ids.sort_custom(func(a, b):
		var ca: int = game.catch_counts.get(a, 0); var cb: int = game.catch_counts.get(b, 0)
		var sa: bool = ca > 0 or game.dex_seen.has(a); var sb: bool = cb > 0 or game.dex_seen.has(b)
		if ca != cb: return ca > cb
		if sa != sb: return sa
		return str(SpeciesData.species_of(a).get("name", a)) < str(SpeciesData.species_of(b).get("name", b)))
	var caught := game.catch_counts.size()
	var seen_n: int = game.dex_seen.size()
	draw_string(font, rr.position + Vector2(16, 24),
		"PALDECK   %d/%d caught · %d seen" % [caught, ids.size(), seen_n],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#c08cff"))
	var rows := 32
	dex_scroll = clampi(dex_scroll, 0, maxi(0, ids.size() - rows))
	var y := rr.position.y + 48
	for i in range(dex_scroll, mini(ids.size(), dex_scroll + rows)):
		var sid: String = ids[i]
		var sp: Dictionary = SpeciesData.species_of(sid)
		var cc: int = game.catch_counts.get(sid, 0)
		if cc > 0:
			var els: String = "/".join(sp.get("elements", []))
			draw_string(font, Vector2(rr.position.x + 16, y), "%s %s" % [sp.get("glyph", "?"), str(sp.get("name", sid)).left(18)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
			draw_string(font, Vector2(rr.position.x + 320, y), "%s  ×%d" % [els.left(14), cc],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fd8a0"))
		elif game.dex_seen.has(sid):
			draw_string(font, Vector2(rr.position.x + 16, y), "%s %s  ·spotted·" % [sp.get("glyph", "?"), str(sp.get("name", sid)).left(18)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.65, 0.72))
		else:
			draw_string(font, Vector2(rr.position.x + 16, y), "?  ?????",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.35, 0.4))
		y += 15
	draw_string(font, Vector2(rr.position.x + 16, rr.end.y - 16),
		"wheel scroll · every 10 species caught pays +2 tech", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.65))

func draw_chat(r: Vector2) -> void:
	var rr := Rect2(12, r.y - 40, 480, 28)
	draw_rect(rr, Color(0, 0, 0, 0.8))
	draw_string(font, rr.position + Vector2(10, 19), "Say: " + chat_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1"))

func star_str(p: Pal) -> String:
	var s := ""
	for i in p.star:
		s += "*"
	if s != "":
		s = " " + s
	return s

func passive_str(p: Pal) -> String:
	var s := ""
	for k in p.passives:
		var pv: Dictionary = PassiveData.PASSIVES.get(k, {})
		if pv.is_empty():
			continue # stale key from an older save — skip instead of crashing
		s += "[" + pv["name"] + "]"
	return s

const PERK_LABEL := {"capture": "Capture Power", "speed": "Move Speed", "atk": "Attack",
 "hp": "Max HP", "work": "Work Speed", "xp": "XP Gain"}

func _eq_line() -> String:
	var wn: String = ItemData.ITEMS.get(game.player.equipment["weapon"], {}).get("name", "Fists")
	var an: String = ItemData.ITEMS.get(game.player.equipment["armor"], {}).get("name", "None")
	var acc := ""
	for s in ["acc1", "acc2"]:
		var a: String = ItemData.ITEMS.get(game.player.equipment[s], {}).get("name", "")
		if a != "":
			acc += "  " + a
	return "Wpn: %s   Arm: %s%s" % [wn, an, acc]

func draw_statues(r: Vector2) -> void:
	var y := r.y + 40.0
	draw_string(font, Vector2(r.x + 16, y - 16), "Stat points: %d   Lifmunk Effigies: %d" % [game.stat_pts, game.item_count("lifmunk_effigy")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9be8a0"))
	for k in game.perks:
		var lvl: int = game.perks[k]
		var cost := 2 + lvl * 2
		var txt := "%s  Lv%d/5  (cost %d)" % [PERK_LABEL.get(k, k), lvl, cost] # foreign saves can inject unknown perk keys
		var rect := Rect2(r.x + 16, y - 12, 360, 20)
		var col := Color.WHITE if lvl < 5 else Color(0.5, 0.5, 0.5)
		if lvl < 5:
			click_rects.append({"rect": rect, "act": "perk", "arg": k})
		draw_string(font, Vector2(rect.position.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 24
	# soul infusion: the same effigies harden a pal you own
	y += 10
	draw_string(font, Vector2(r.x + 16, y - 16), "SOUL INFUSION (+4%/soul)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c08cff"))
	var infused := []
	for uid in game.party:
		var qp: Pal = game.find_pal(uid)
		if qp != null:
			infused.append(qp)
	for bp2 in game.box:
		infused.append(bp2)
	for q2 in infused:
		var cost2: int = 1 + q2.soul_boost
		var full: bool = q2.soul_boost >= 10
		var rect2 := Rect2(r.x + 16, y - 12, 360, 20)
		if not full:
			click_rects.append({"rect": rect2, "act": "infuse", "arg": q2.uid})
		var col2 := Color(0.5, 0.5, 0.5) if full else Color.WHITE
		draw_string(font, Vector2(rect2.position.x, y), "%s Lv%d  soul+%d  (cost %d)" %
			[str(q2.spec["name"]).left(14), q2.level, q2.soul_boost, cost2],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col2)
		y += 20

func draw_equipment_line() -> void:
	draw_string(font, Vector2(14, 80), _eq_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9d8e8"))
