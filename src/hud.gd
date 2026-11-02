extends Control
# HUD + panels: HP/XP, spheres, log, time, party; B build / I inv / T tech /
# E interact (craft near workbench, palbox mgmt near palbox); ESC closes.

var game: Game
var font := ThemeDB.fallback_font
var show_help := false
var build_sel := -1
var click_rects := []   # [{rect, act, arg}]
var chat_buf := ""

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
		if game.net: game.net.join("127.0.0.1") # K: join local host — LAN ip by edit
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
		"use_item":
			use_item(cr["arg"])
		"equip":
			game.equip(cr["arg"])
		"perk":
			game.upgrade_perk(cr["arg"])
		"chest_dep":
			if game.chest_ref != null:
				game.log_msg("Stored %d items" % game.chest_deposit_all(game.chest_ref))
		"chest_wd":
			if game.chest_ref != null:
				game.log_msg("Took %d items" % game.chest_withdraw_all(game.chest_ref))

func interact() -> void:
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
			"chest":
				game.chest_ref = st
				game.panel = "chest"
				return
			"pal_condenser":
				game.condense_active()
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
	if pl.aiming:
		draw_string(font, Vector2(12, 76), "AIM — click a pal to throw (Q cancel)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#4dd0e1"))
	draw_rect(Rect2(r.x - 140, 10, 128, 20), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(r.x - 132, 25), "Day %d  %02d:00" % [game.day, int(game.tod)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8f0f2"))
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
		"chat":
			draw_chat(r)
	if show_help:
		var lines := [
			"MOVE wasd/arrows  SPRINT shift  DODGE space",
			"MELEE/CHOP lmb  AIM q  THROW lmb  BALL tab",
			"BUILD b (1-9 pick, lmb place, rmb cancel)  INV i  TECH t",
			"INTERACT e (workbench=craft, palbox=manage)  ASSIGN f  HELP h",
			"MAP m    DEMOLISH x (under cursor)  RIDE r  PAL-SKILL g  STATUES u  CHAT enter (net)",
		]
		draw_rect(Rect2(10, r.y - 126, 580, 76), Color(0, 0, 0, 0.7))
		for i in range(lines.size()):
			draw_string(font, Vector2(20, r.y - 106 + i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dfe8ea"))

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
		var afford: bool = game.tech_points >= t.get("cost", 0)
		var col := Color("#5a6068") if has else (Color.WHITE if afford else Color("#7a6a55"))
		var label := "T%d %s [%d]%s" % [t.get("tier", 1), t.get("name", k).left(14), t.get("cost", 0), " ✓" if has else ""]
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
		var equipable: bool = ItemData.ITEMS.get(k, {}).has("weapon") or ItemData.ITEMS.get(k, {}).has("armor")
		var rect := Rect2(cx0, y0 - 12, colw - 12, 16)
		if equipable:
			click_rects.append({"rect": rect, "act": "equip", "arg": k})
			var slot := "weapon" if ItemData.ITEMS[k].has("weapon") else "armor"
			nm += "  [eq'd]" if game.player.equipment[slot] == k else "  [eq]"
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
		var rect := Rect2(rr.position.x + 24, y - 11, 250, 17)
		click_rects.append({"rect": rect, "act": "party_in", "arg": uid})
		draw_string(font, Vector2(rect.position.x, y), "%s %s%s Lv%d %s HP%d/%d" % [p.spec["name"], p.sex, star_str(p), p.level, passive_str(p).left(14), int(p.hp), int(p.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
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
		var rect := Rect2(cx0, y0 - 11, colw - 10, 16)
		click_rects.append({"rect": rect, "act": "box_out", "arg": bp})
		var ko: bool = bp.hp <= 0
		var label := "%s %s%s Lv%d HP%d/%d%s" % [bp.spec["name"], bp.sex, star_str(bp), bp.level,
			int(maxi(0, bp.hp)), int(bp.max_hp), " [KO %ds]" % int(maxi(0.0, bp.revive_t - game.t)) if ko else ""]
		draw_string(font, Vector2(cx0, y0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d06a6a") if ko else Color("#c8d3d5"))

func use_item(k: String) -> void:
	match k:
		"boss_sigil":
			if game.summon_raid():
				game.add_item(k, -1)
		"pal_egg":
			game.hatch_egg()  # consumes inside
		_:
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
	return "Wpn: %s   Arm: %s" % [wn, an]

func draw_statues(r: Vector2) -> void:
	var y := r.y + 40.0
	draw_string(font, Vector2(r.x + 16, y - 16), "Lifmunk Effigies: %d" % game.item_count("lifmunk_effigy"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9be8a0"))
	for k in game.perks:
		var lvl: int = game.perks[k]
		var cost := 2 + lvl * 2
		var txt := "%s  Lv%d/5  (cost %d)" % [PERK_LABEL[k], lvl, cost]
		var rect := Rect2(r.x + 16, y - 12, 360, 20)
		var col := Color.WHITE if lvl < 5 else Color(0.5, 0.5, 0.5)
		if lvl < 5:
			click_rects.append({"rect": rect, "act": "perk", "arg": k})
		draw_string(font, Vector2(rect.position.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 24

func draw_equipment_line() -> void:
	draw_string(font, Vector2(14, 46), _eq_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9d8e8"))
