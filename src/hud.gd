extends Control
# HUD + panels: HP/XP, orbs, log, time, party; B build / I inv / T tech /
# E interact (craft near workbench, kinbox mgmt near kinbox); ESC closes.

var game: Game
var font: Font = ThemeDB.fallback_font
var show_help := false
var guide_page := 0
var dex_scroll := 0
var chest_scroll := 0
var craft_scroll := 0
var shop_scroll := 0
var inv_scroll := 0
var kin_scroll := 0
var tech_scroll := 0
var stat_scroll := 0
var build_sel := -1
var menu_sel := 0 # pad/arrow-key cursor over shell menus
var click_rects := []   # [{rect, act, arg}]
var chat_buf := ""
var join_buf := ""
var joy_idx := -1        # which finger owns the on-screen stick
const JOY_R := 56.0      # stick travel radius (screen px)
const BTN_R := 27.0      # verb button radius (atk is bigger)

var map_img: Image = null
var map_tex: ImageTexture = null # cached — was rebuilt every frame the map was open
var fog_img: Image = null        # the island fog of war — dark where unexplored
var fog_tex: ImageTexture = null
var fog_t := 0.0                 # rebake throttle while the map is open
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
	bake_fog()

func bake_fog() -> void:
	# the island fog: one alpha layer over the baked terrain — dark until walked
	var W := game.world
	if fog_img == null or fog_img.get_width() != W.WORLD_W:
		fog_img = Image.create(W.WORLD_W, W.WORLD_H, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0.015, 0.025, 0.05, 0.8))
	var i := 0
	for y in W.WORLD_H:
		for x in W.WORLD_W:
			if i < game.explored.size() and game.explored[i] != 0:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0))
			i += 1
	fog_tex = ImageTexture.create_from_image(fog_img)
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pf = load("res://fonts/PressStart2P-Regular.ttf")
	if pf != null:
		pf.fallbacks = [font] # CJK and icons fall through to the system face
		font = pf # the island's own voice: pixel type, not the engine default

var nav_hold := 0.0 # menu hold-to-repeat clock — edge press moves once, hold marches
func _process(dt: float) -> void:
	queue_redraw()
	# a held direction emits no events — catch the transition here too or the
	# old hold would keep marching into the new menu with no fresh 0.42s delay
	var mk2 := "%s|%s" % [game.state, game.panel]
	if game != null and mk2 != _menu_key:
		_menu_key = mk2
		click_rects.clear()
		menu_sel = 0
		nav_hold = 0.0
		_release_stick() # state/panel swap mid-drift parks the joystick here too
	# arrows and dpad share the ui_* actions; after a 0.42s first step the
	# cursor keeps marching on a 0.09s cadence — a long list stops being a
	# button-mash. Edge presses still come from _input's action_pressed.
	if game != null and (game.state in ["title", "paused"] or game.panel != "") and not click_rects.is_empty():
		var dir := int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up"))
		if dir == 0:
			nav_hold = 0.0
		else:
			nav_hold += dt
			if nav_hold >= 0.42:
				menu_sel = wrapi(menu_sel + dir, 0, click_rects.size())
				nav_hold = 0.33
	else:
		nav_hold = 0.0
	if game != null and game.panel != "" and touch_more:
		touch_more = false # panels own the taps — collapse the verb row out of the way
	# text panels on touch need the OS keyboard — it never appears on its own
	var texty := game != null and game.panel in ["join", "chat"]
	if texty != _vkbd_open:
		_vkbd_open = texty
		if game.touch_ui:
			if texty: DisplayServer.virtual_keyboard_show("")
			else: DisplayServer.virtual_keyboard_hide()

var _menu_key := "" # last drawn "state|panel" — rects belong to exactly one menu
var _vkbd_open := false

func _release_stick() -> void: # one path for every "the stick must go home"
	joy_idx = -1
	if game != null and game.player:
		game.player.touch_vec = Vector2.ZERO
		game.player.touch_sprint = false

func _input(event: InputEvent) -> void:
	# last-seen device drives hint phrasing — sticks drift, so gate on intent
	if event is InputEventJoypadButton:
		game.using_pad = event.pressed or game.using_pad
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.4:
			game.using_pad = true
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		game.using_pad = false

func _unhandled_input(event: InputEvent) -> void:
	var mk := "%s|%s" % [game.state, game.panel]
	if mk != _menu_key: # a transition just happened: last frame's rows are void
		_menu_key = mk
		click_rects.clear()
		menu_sel = 0
		_release_stick()
	if game.touch_ui and game.state == "play":
		if event is InputEventScreenTouch:
			if event.pressed:
				touch_down(event.position, event.index)
			else:
				touch_up(event.index)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventScreenDrag:
			touch_move(event.position, event.index)
			get_viewport().set_input_as_handled()
			return
	# shell states own the whole input stack — menus don't leak to gameplay
	if game.state == "title" or game.state == "paused":
		if event.is_action_pressed("ui_cancel"):
			if game.panel != "":
				game.panel = "" # Esc leaves settings first, its parent menu second
			elif game.state == "paused":
				game.state = "play"
			get_viewport().set_input_as_handled()
			return
		# pad/dpad menu nav: stick and arrows move the cursor, A/Enter confirms
		if event.is_action_pressed("ui_down"):
			if not click_rects.is_empty():
				menu_sel = wrapi(menu_sel + 1, 0, click_rects.size()) # never park on -1: negative wraps to the last row
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_up"):
			if not click_rects.is_empty():
				menu_sel = wrapi(menu_sel - 1, 0, click_rects.size())
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			if menu_sel >= 0 and menu_sel < click_rects.size():
				run_click(click_rects[menu_sel])
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for cr in click_rects:
				if cr["rect"].has_point(event.position):
					run_click(cr)
					break
		get_viewport().set_input_as_handled() # the shell owns every event here
		return
	# chat input mode (net only)
	if game.panel == "chat" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_chat_submit()
		elif event.keycode == KEY_ESCAPE:
			chat_buf = ""; game.panel = ""
		elif event.keycode == KEY_BACKSPACE:
			chat_buf = chat_buf.left(-1)
		elif event.unicode >= 32:
			chat_buf += char(event.unicode) # CJK keepers chat too — ASCII-only was a cage
		get_viewport().set_input_as_handled()
		return
	# join-ip input mode
	if game.panel == "join" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_join_submit()
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
	if event.is_action_pressed("guide"):
		game.panel = "" if game.panel == "guide" else "guide"
		guide_page = 0
		return
	if game.panel == "guide":
		if event.is_action_pressed("ui_right"):
			guide_page = mini(guide_page + 1, GuideData.PAGES.size() - 1)
		elif event.is_action_pressed("ui_left"):
			guide_page = maxi(guide_page - 1, 0)
	if event.is_action_pressed("ui_cancel") and game.panel != "":
		game.panel = ""
		return
	if event.is_action_pressed("ui_cancel") and game.panel == "":
		game.state = "paused" # Esc with nothing open pulls the shell over the sim
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
		game.panel = "" if game.panel == "statues" else "statues" # U: sprigmelt effigy upgrades
		return
	if event.is_action_pressed("dex"):
		game.panel = "" if game.panel == "dex" else "dex" # P: kindex
		dex_scroll = 0
		return
	if game.panel in ["dex", "chest", "craft", "shop", "inv", "kinbox", "tech", "statues"] and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_panel_scroll(-1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_panel_scroll(1)
			get_viewport().set_input_as_handled()
			return
	# panels take the pad cursor too: dpad/arrows pick a row, A/Enter
	# confirms. The world verbs below already refuse to fire while a panel
	# is up — a menu that can't be driven without a mouse isn't a menu.
	if game.state == "play" and game.panel != "" and not click_rects.is_empty():
		if event.is_action_pressed("ui_down"):
			menu_sel = wrapi(menu_sel + 1, 0, click_rects.size())
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_up"):
			menu_sel = wrapi(menu_sel - 1, 0, click_rects.size())
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			if menu_sel >= 0 and menu_sel < click_rects.size():
				run_click(click_rects[menu_sel])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("party_toggle"):
		if game.panel != "":
			return # assigning crew while reading the roster is a misclick
		_assign_verb()
		return
	if event.is_action_pressed("pal_stance"):
		if game.panel != "":
			return
		_stance_verb()
		return
	if event.is_action_pressed("demolish"):
		if game.panel != "":
			return # razing a real structure while browsing lists is grief
		game.demolish_at(mouse_tile())
		return
	if event.is_action_pressed("map"):
		_map_toggle()
		return
	if event.is_action_pressed("interact"):
		if game.panel != "":
			return # E means "confirm" inside panels, not "use the world"
		interact()
		return
	if event.is_action_pressed("save"):
		game.save_game()
		return
	if event.is_action_pressed("load_save"):
		game.load_game()
		return
	if event.is_action_pressed("host_net"):
		if game.net and game.net.multiplayer.multiplayer_peer == null:
			game.net.host() # J: host on :7777 — refused mid-session:
		elif game.net:                    # a guest re-hosting severs its own
			game.log_msg("End the session first (quit to title)") # replica world
		return
	if event.is_action_pressed("join_net"):
		if game.net and game.panel == "" and game.net.multiplayer.multiplayer_peer == null:
			game.panel = "join"; join_buf = "" # K: type the host's IP, Enter to join
		return
	if event is InputEventKey and event.pressed and game.panel == "":
		# the island party hotbar: 1-5 sends that slot's kin out (again recalls)
		var k2: int = event.keycode
		if k2 >= KEY_1 and k2 <= KEY_5:
			var si2 := k2 - KEY_1
			if game.net != null and game.net.is_client():
				if si2 < game.net_party.size():
					game.net.rpc("box_req", "make_active", int(game.net_party[si2]["uid"]))
			elif si2 < game.party.size():
				game.make_active(game.party[si2])
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

func _panel_scroll(dir: int) -> void: # wheel/tap scroller — draw clamps to real bounds
	match game.panel:
		"dex": dex_scroll = maxi(0, dex_scroll + dir)
		"chest": chest_scroll = maxi(0, chest_scroll + dir)
		"craft": craft_scroll = maxi(0, craft_scroll + dir)
		"shop": shop_scroll = maxi(0, shop_scroll + dir)
		"inv": inv_scroll = maxi(0, inv_scroll + dir)
		"kinbox": kin_scroll = maxi(0, kin_scroll + dir)
		"tech": tech_scroll = maxi(0, tech_scroll + dir)
		"statues": stat_scroll = maxi(0, stat_scroll + dir)

func _scroll_btns(rr: Rect2, up_act: String, dn_act: String, bx := -1.0, stacked := false) -> void:
	# tap scrollers — lists taller than the panel need a slab-reachable tail
	if bx < 0.0:
		bx = rr.end.x - 30
	var up_r := Rect2(bx, rr.position.y + 8, 24, 24)
	var dn_r := Rect2(bx, rr.position.y + 36 if stacked else rr.end.y - 32, 24, 24)
	for b2 in [[up_r, up_act, "▲"], [dn_r, dn_act, "▼"]]:
		draw_rect(b2[0], Color(0.15, 0.18, 0.24, 0.9))
		draw_rect(b2[0], Color(0.5, 0.6, 0.7), false, 1.0)
		draw_string(font, b2[0].position + Vector2(6, 17), b2[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		click_rects.append({"rect": b2[0], "act": b2[1], "arg": null})

func _chat_submit() -> void:
	if chat_buf.strip_edges() != "" and game.net:
		game.net.rpc("chat", chat_buf, multiplayer.get_unique_id())
		game.log_msg("[you] " + chat_buf)
	chat_buf = ""; game.panel = ""

func _join_submit() -> void:
	var ip := join_buf.strip_edges()
	if ip == "": ip = "127.0.0.1"
	if game.net: game.net.join(ip)
	join_buf = ""; game.panel = ""

func run_click(cr: Dictionary) -> void:
	# client kinbox ops are host business: the host owns the one real box.
	# Replica kin carry their wire id in net_id — a replica's own uid is a
	# local number the host has never heard of.
	const KINBOX_OPS := {
		"box_out": "box_to_party", "party_in": "party_to_box",
		"lead": "make_active", "deploy": "deploy_to_base",
		"base_in": "base_to_box", "fav": "toggle_fav",
		"butcher": "butcher_pal", "sell_pal": "sell_pal"}
	if game.net != null and game.net.is_client() and KINBOX_OPS.has(cr["act"]):
		var uid := 0
		if cr["arg"] is Kin:
			uid = cr["arg"].net_id if cr["arg"].net_id > 0 else cr["arg"].uid
		else:
			uid = int(cr["arg"])
		game.net.rpc("box_req", KINBOX_OPS[cr["act"]], uid)
		return
	match cr["act"]:
		"craft":
			game.craft(cr["arg"])
		"repair":
			game.repair_weapon()
		"repair_armor":
			game.repair_armor()
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
		"skills":
			game.skill_target = cr["arg"]
			game.panel = "skills"
		"skill_tgl":
			game.toggle_skill(cr["arg"]["p"], cr["arg"]["sid"])
		"travel":
			game.travel_to(cr["arg"])
		"chat_send":
			_chat_submit()
		"join_go":
			_join_submit()
		"text_cancel": # the touch out — no Esc key on a slab
			chat_buf = ""; join_buf = ""; game.panel = ""
		"dex_up": _panel_scroll(-1)
		"dex_dn": _panel_scroll(1)
		"guide_prev":
			guide_page = maxi(guide_page - 1, 0)
		"guide_next":
			guide_page = mini(guide_page + 1, GuideData.PAGES.size() - 1)
		"chest_up": _panel_scroll(-1)
		"chest_dn": _panel_scroll(1)
		"craft_up": _panel_scroll(-1)
		"craft_dn": _panel_scroll(1)
		"shop_up": _panel_scroll(-1)
		"shop_dn": _panel_scroll(1)
		"inv_up": _panel_scroll(-1)
		"inv_dn": _panel_scroll(1)
		"kin_up": _panel_scroll(-1)
		"kin_dn": _panel_scroll(1)
		"tech_up": _panel_scroll(-1)
		"tech_dn": _panel_scroll(1)
		"stat_up": _panel_scroll(-1)
		"stat_dn": _panel_scroll(1)
		"build_pick": # tap toggles — there's no right-click on glass
			build_sel = -1 if build_sel == int(cr["arg"]) else int(cr["arg"])
		"equip":
			game.equip(cr["arg"])
		"perk":
			game.upgrade_perk(cr["arg"])
		"base_up":
			game.upgrade_base()
		"infuse":
			game.soul_infuse(cr["arg"])
		# ---- shell menu acts (title / pause / settings) ----
		_:
			if cr["act"] in SHELL_ACTS:
				game.sfx_play("click")
				shell_act(cr["act"])
			elif cr["act"] == "chest_dep" or cr["act"] == "chest_wd":
				chest_bulk(cr["act"])

const SHELL_ACTS := ["new_game", "continue", "m_settings", "m_join", "m_host", "m_chat",
	"m_tech", "m_dex", "m_statues", "m_guide", "set_back", "resume",
	"m_save", "to_title", "quit", "vol_master_m", "vol_master_p", "vol_music_m",
	"vol_music_p", "vol_sfx_m", "vol_sfx_p", "fullscreen", "raids_tgl", "lang_tgl", "touch_tgl"]

func shell_act(act: String) -> void:
	match act:
		"new_game":
			game.state = "play"
			game.log_msg(tr("Day 1 on the Wildmere — catch a kin, feed it, put it to work."))
		"continue":
			if game.load_game():
				game.state = "play"
		"m_settings":
			game.panel = "settings"
		"m_join":
			game.panel = "join"; join_buf = ""
		"m_host":
			if game.net != null and multiplayer.multiplayer_peer == null:
				game.net.host()
		"m_chat":
			game.panel = "chat"; chat_buf = ""
		"m_tech":
			game.panel = "tech"
		"m_dex":
			game.panel = "dex"; dex_scroll = 0
		"m_statues":
			game.panel = "statues"
		"m_guide":
			game.panel = "guide"; guide_page = 0
		"set_back":
			game.panel = ""
		"resume":
			game.state = "play"
		"m_save":
			game.save_game()
		"to_title":
			game.to_title()
		"quit":
			if game.state == "title":
				get_tree().quit() # no game in progress — nothing to save
			else:
				game.quit_game()
		"vol_master_m", "vol_master_p", "vol_music_m", "vol_music_p", "vol_sfx_m", "vol_sfx_p":
			var b: String = act.split("_")[1]
			game.settings[b] = clampf(game.settings[b] + (0.1 if act.ends_with("_p") else -0.1), 0.0, 1.0)
			game.apply_settings(); game.save_settings()
		"fullscreen":
			game.settings["fullscreen"] = not game.settings["fullscreen"]
			game.apply_settings(); game.save_settings()
		"raids_tgl":
			game.settings["raids"] = not game.settings["raids"]
			game.apply_settings(); game.save_settings()
		"lang_tgl":
			game.settings["lang"] = "zh" if game.settings.get("lang", "en") == "en" else "en"
			game.apply_settings(); game.save_settings()
		"touch_tgl":
			var order := ["auto", "on", "off"]
			game.settings["touch"] = order[(order.find(game.settings.get("touch", "auto")) + 1) % 3]
			game.apply_settings(); game.save_settings()

func chest_bulk(act: String) -> void:
	var st = game.chest_ref
	var cc: Vector2i = game.cell_of(st) if st != null else Vector2i(-1, -1)
	if cc.x < 0 or game.player.pos.distance_to(Vector2(cc.x + 0.5, cc.y + 0.5)) > 5.0:
		game.chest_ref = null
		game.panel = "" # walked too far — the container is out of reach
		return
	if act == "chest_dep":
		game.log_msg("Stored %d items" % game.chest_deposit_all(st))
	else:
		game.log_msg("Took %d items" % game.chest_withdraw_all(st))

func interact() -> void:
	if game.merchant != null and game.player.pos.distance_to(game.merchant.pos) < 2.4:
		game.panel = "shop"
		return
	# pet: a friendly kin in arm's reach takes the E tap first —
	# deliberate affection shouldn't lose to a structure probe
	var pet: Kin = null
	var pd2 := 1.4
	for q in game.pals:
		if q.mode not in ["partner", "base"] or q.hp <= 0 or q.petted_t > game.t:
			continue
		var dd: float = game.player.pos.distance_to(q.pos)
		if dd < pd2:
			pd2 = dd; pet = q
	if pet != null and game.pet_pal(pet):
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
				var eggs: String = "  %d egg(s)" % st["store"].get("kin_egg", 0) if st["id"] == "ranch" and st.get("store", {}).get("kin_egg", 0) > 0 else ""
				if st.get("store", {}).is_empty():
					game.log_msg("%s: %d workers, nothing stored" % [sdef.get("name", st["id"]), st["workers"].size()])
				else:
					game.log_msg("%s stores: %s%s" % [sdef.get("name", st["id"]), str(st["store"]), eggs])
				return
			"feed_box":
				game.chest_ref = st # pals eat out of it; it's still a container
				game.panel = "chest"
				return
			"kin_bed":
				game.log_msg("Kin bed: base kin resting here recover SAN")
				return
			"kinbox":
				game.panel = "kinbox"
				return
			"straw_bed":
				game.sleep_to_morning()
				return
			"waypoint":
				game.use_waypoint()
				return
			"chest":
				if str(st.get("mimic", "")) != "":
					game.open_mimic(st)
					return
				game.chest_ref = st
				game.panel = "chest"
				return
			"monitoring_stand":
				game.cycle_work_mode()
				return
			"weather_shrine":
				game.pray_weather()
				return
			"notice_board":
				game.notice_board_action()
				return
			"kin_gacha":
				game.gacha_pull()
				return
			"fossil_bed":
				game.dig_fossil(st)
				return
			"kin_cage":
				game.free_captive(st)
				return
			"kin_condenser":
				game.condense_active()
				return
			"incubator":
				var inc = st.get("egg_inc")
				if inc is Dictionary:
					var hint: String = game.egg_hint(inc.get("pair"))
					game.log_msg("Incubating %s: %ds left" % [hint if hint != "" else "egg",
						int(maxi(0.0, float(inc.get("ready_t", 0.0)) - game.t))])
				elif game.item_count("kin_egg") > 0:
					game.deposit_egg()
				else:
					game.log_msg("Incubator empty - bring a kin egg")
				return
			"wooden_wall", "spikes":
				game.log_msg("%s (HP %d)" % [StructureData.STRUCTURES[st["id"]]["name"], int(st.get("hp", 0))])
				return
	if game.has_structure("kinbox"):
		game.panel = "kinbox"
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
	draw_rect(Rect2(12, 30, 224, 6), Color(0, 0, 0, 0.55))
	var hc: Color = Color("#e6a23c") if pl.hunger >= 25 else Color("#e0503c")
	draw_rect(Rect2(14, 31, int(220 * clampf(pl.hunger / 100.0, 0, 1)), 4), hc)
	# the island SP bar under the hunger sliver — sprints and swims burn it
	draw_rect(Rect2(12, 37, 224, 5), Color(0, 0, 0, 0.55))
	var spc: Color = Color("#3cb7e0") if pl.stamina > 15.0 else Color("#e0503c")
	draw_rect(Rect2(14, 38, int(220 * clampf(pl.stamina / 100.0, 0, 1)), 3), spc)
	draw_string(font, Vector2(16, 25), "HP %d/%d  Lv%d  XP%d" % [int(pl.hp), int(pl.max_hp), pl.level, pl.xp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var tiers := game.sphere_tiers()
	var sx := 12
	for id in ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]:
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
	draw_equipment_line() # gear row under the orb chips
	if pl.meal_t > 0.0 and not pl.meal_buff.is_empty(): # the island meal timer chip
		var btxt := ""
		for bk in pl.meal_buff:
			btxt += "%s+%d%% " % [bk.to_upper(), int(float(pl.meal_buff[bk]) * 100)]
		draw_rect(Rect2(240, 24, 112, 16), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(244, 36), "%s %d:%02d" % [btxt.strip_edges(), int(pl.meal_t) / 60, int(pl.meal_t) % 60],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8b95f"))
	if pl.aiming:
		draw_string(font, Vector2(12, 96), "AIM — click a kin to throw (Q cancel)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#4dd0e1"))
		# the island throw preview: hovering a wild kin shows the catch odds
		var tiers2 := game.sphere_tiers()
		if not tiers2.is_empty():
			var sid2: String = tiers2[clampi(pl.sphere_sel, 0, tiers2.size() - 1)]
			var mp2 := get_global_mouse_position()
			var tw2: Vector2 = Iso.from_screen(mp2.x, mp2.y, pl.elev())
			var bp2: Kin = null
			var bd2 := 1.6
			for q in game.pals:
				if q.mode != "wild" or q.hp <= 0:
					continue
				var dd := q.pos.distance_to(tw2)
				if dd < bd2:
					bd2 = dd
					bp2 = q
			if bp2:
				if bp2.boss:
					draw_string(font, Vector2(12, 112), "✦ %s Lv%d — a legend: orbs bounce off" % [bp2.spec["name"], bp2.level],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd76e"))
				else:
					var cap_pow2: float = game.cap_power_of(bp2)
					var ch := minf(0.97, Combat.catch_chance(maxf(0.0, bp2.hp) / bp2.max_hp, cap_pow2,
						ItemData.ITEMS[sid2].get("spherePower", 26), bp2.any_status(), false, pl.capture_level))
					var col := Color("#a8e6a1") if ch >= 0.5 else (Color("#e8963c") if ch >= 0.2 else Color("#e8452f"))
					draw_string(font, Vector2(12, 112), "Catch %s Lv%d: %d%%" % [bp2.spec["name"], bp2.level, int(ch * 100)],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_rect(Rect2(r.x - 140, 10, 128, 20), Color(0, 0, 0, 0.55))
	var wicon := "  ⚡" if game.weather == "storm" else ("  ☂" if game.weather == "rain" else ("  ☀" if game.weather == "drought" else ""))
	var wcol := Color("#b48ef0") if game.weather == "storm" else (Color("#7fb8e8") if game.weather == "rain" else (Color("#e8b45c") if game.weather == "drought" else Color("#e8f0f2")))
	draw_string(font, Vector2(r.x - 132, 25), "Day %d  %02d:00%s" % [game.day, int(game.tod), wicon],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, wcol)
	if game.raid_t < 30.0 and game.kinbox_pos.x >= 0: # the island raid horn
		draw_rect(Rect2(r.x / 2 - 80, 8, 160, 22), Color(0.5, 0.06, 0.06, 0.7))
		draw_string(font, Vector2(r.x / 2 - 62, 24), "RAID IN %ds" % int(ceilf(game.raid_t)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff8d7e"))
	# boss bar: nearest alpha/boss in the fray gets a name + hp strip
	var boss: Kin = null
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
			"%s %s Lv%d%s" % ["BOSS" if boss.boss else "α", boss.spec["name"], boss.level,
				" ☠%dg" % boss.bounty if boss.bounty > 0 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	if game.mission_idx < game.MISSIONS.size(): # the island guide rope
		draw_rect(Rect2(r.x - 220, 32, 208, 18), Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(r.x - 214, 45), "★ %s" % game.MISSIONS[game.mission_idx]["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8d44d"))
	var hy := 62.0
	for h in game.active_hints(): # contextual nudges — retire themselves
		draw_rect(Rect2(r.x - 216, hy - 11, 208, 15), Color(0, 0, 0, 0.45))
		var htxt: String = str(h.get("pad", h["text"])) if game.using_pad else str(h["text"])
		draw_string(font, Vector2(r.x - 212, hy), "» " + tr(htxt),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 0.95))
		hy += 17
	if game.spires_done.size() > 0 or game.crowned: # the campaign spine's tally
		draw_rect(Rect2(r.x - 216, hy - 11, 208, 15), Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(r.x - 212, hy),
			tr("SPIRES %d/%d") % [game.spires_done.size(), game.SPIRE_DEFS.size()]
				+ (tr(" — CROWNED") if game.crowned else ""),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd76e"))
	var my := r.y - 24
	for i in range(game.messages.size()):
		var m: String = game.messages[game.messages.size() - 1 - i]
		draw_string(font, Vector2(14, my - i * 18), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	var py := 38
	for pr in party_rows(): # ● out / ○ in its ball — the island fields one
		draw_rect(Rect2(r.x - 150, py, 138, 16), Color(0, 0, 0, 0.5))
		var tag := "!" if pr["stance"] == "aggressive" else ("." if pr["stance"] == "passive" else "")
		draw_string(font, Vector2(r.x - 144, py + 13), "%s Lv%d %s%s" % [pr["name"], pr["lv"],
			"●" if pr["out"] else "○", tag], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f0d0"))
		py += 18
	# the island partner-skill readout: name + cooldown under the party strip
	var psk_p := game.party_pal()
	if psk_p != null and game.PARTNER_SKILLS.has(psk_p.species_id):
		var cd_left: float = float(psk_p.skill_cd.get("partner", 0.0)) - game.t
		draw_rect(Rect2(r.x - 150, py, 138, 16), Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(r.x - 144, py + 13),
			"%s %s" % [game.PARTNER_SKILLS[psk_p.species_id]["name"],
				"READY" if cd_left <= 0 else "%ds" % ceili(cd_left)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color("#ffd76e") if cd_left <= 0 else Color(0.55, 0.55, 0.6))
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
		"kinbox":
			draw_kinbox(r)
		"shop":
			draw_shop(r)
		"dex":
			draw_dex(r)
		"skills":
			draw_skills(r)
		"travel":
			draw_travel(r)
		"chat":
			draw_chat(r)
		"join":
			draw_join(r)
		"guide":
			draw_guide(r)
		"settings":
			draw_settings(r)
	if show_help:
		var lines := [
			"MOVE wasd/arrows  SPRINT shift  DODGE space",
			"MELEE/CHOP lmb  AIM q  THROW lmb  BALL tab",
			"BUILD b (1-9 pick, lmb place, rmb cancel)  INV i  TECH t",
			"INTERACT e (workbench=craft, kinbox=manage)  ASSIGN f  HELP h",
			"MAP m    DEMOLISH x (under cursor)  RIDE r  KIN-SKILL g  STATUES u  KINDEX p  CHAT enter",
			"1-5 sends that party kin out (press again to recall) — one ball on the field",
			"v cycles the field kin's orders: auto / aggressive / passive",
			"HOST j   JOIN k (type host IP, enter)  MERCHANT e (when visiting)",
			"Glider descends cliffs. Sick kin need medicine in feed box/bag.",
		]
		draw_rect(Rect2(10, r.y - 136, 580, 96), Color(0, 0, 0, 0.7))
		for i in range(lines.size()):
			draw_string(font, Vector2(20, r.y - 116 + i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dfe8ea"))

	# minimap (M): baked world image + live player/kinbox markers

	if map_show and map_img != null:
		var vw := get_viewport_rect().size.x
		var ms := 176.0
		var mr := Rect2(vw - ms - 10, 10, ms, ms)
		draw_rect(mr.grow(2), Color(0, 0, 0, 0.7))
		if map_tex != null:
			draw_texture_rect(map_tex, mr, false)
		fog_t -= 0.016 # draw runs per-frame; rebake the fog ~2x a second
		if fog_t <= 0.0:
			fog_t = 0.5
			bake_fog()
		if fog_tex != null:
			draw_texture_rect(fog_tex, mr, false)
		var plp := game.player.pos
		var pp := mr.position + Vector2(plp.x / game.world.WORLD_W * ms, plp.y / game.world.WORLD_H * ms)
		draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
		if game.kinbox_pos.x >= 0:
			var pb := mr.position + Vector2(game.kinbox_pos.x / float(game.world.WORLD_W) * ms, game.kinbox_pos.y / float(game.world.WORLD_H) * ms)
			draw_rect(Rect2(pb - Vector2(2, 2), Vector2(4, 4)), Color(1, 0.55, 0.1))
		for dm in game.death_marks: # the island tombstones — guide the corpse run
			var dp := mr.position + Vector2(dm.x / game.world.WORLD_W * ms, dm.y / game.world.WORLD_H * ms)
			draw_rect(Rect2(dp - Vector2(2, 2), Vector2(4, 4)), Color(0.95, 0.2, 0.2))
		if game.treasure: # the surveyor's X — follow it and dig
			var tp := mr.position + Vector2(game.treasure["pos"].x / game.world.WORLD_W * ms, game.treasure["pos"].y / game.world.WORLD_H * ms)
			draw_rect(Rect2(tp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.84, 0.28))

	draw_weather_fx(r)
	draw_touch(r)

	# shell overlays come last — they sit over the whole HUD
	if game.state == "title" and game.panel == "":
		draw_title(r)
	elif game.state == "paused" and game.panel == "":
		draw_pause(r)
	if (game.state != "play" or game.panel != "") and not click_rects.is_empty():
		menu_sel = clampi(menu_sel, 0, click_rects.size() - 1) # panels swap rows under the cursor
		var msel: Rect2 = click_rects[menu_sel]["rect"]
		draw_rect(msel, Color(0.55, 0.7, 0.95, 0.9), false, 2.0) # pad/arrow-key cursor
		draw_string(font, Vector2(msel.position.x - 16, msel.position.y + 20), "»",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8ef0ff"))

# ---------- on-screen touch controls ----------
var _lay_key := Vector2(-1, -1)
var _lay_cache := {}

func touch_layout(r: Vector2) -> Dictionary: # cached — draw_touch asks every frame
	if r == _lay_key and not _lay_cache.is_empty():
		return _lay_cache
	_lay_key = r
	_lay_cache = {"joy": Vector2(92, r.y - 108), "btns": {
		"atk": Vector2(r.x - 72, r.y - 92),
		"aim": Vector2(r.x - 152, r.y - 52),
		"roll": Vector2(r.x - 66, r.y - 164),
		"e": Vector2(r.x - 156, r.y - 140),
		"orb": Vector2(r.x - 226, r.y - 92),
		"inv": Vector2(r.x - 226, r.y - 170),
		"bld": Vector2(r.x - 296, r.y - 116),
		"more": Vector2(r.x - 354, r.y - 56),
		"menu": Vector2(r.x - 38, 224)}} # under the minimap, not inside it
	var row := {}
	for i in range(MORE_VERBS.size()):
		row[MORE_VERBS[i]] = Vector2(r.x - 40 - i * 56, r.y - 252)
	_lay_cache["more_row"] = row
	return _lay_cache

const MORE_VERBS := ["asg", "stn", "ksk", "rde", "dml", "map"]
var touch_more := false

func joy_grab_r() -> float: return JOY_R * 1.7 # one radius table — touch_down AND zone gate share it

func btn_r(b: String) -> float: return (36.0 if b == "atk" else BTN_R) + 8.0

func touch_zone_hit(p: Vector2) -> bool: # does this point land on a virtual control?
	var lay := touch_layout(get_viewport_rect().size)
	if p.distance_to(lay["joy"]) <= joy_grab_r():
		return true
	for b in lay["btns"]:
		if p.distance_to(lay["btns"][b]) <= btn_r(b):
			return true
	if touch_more:
		for b in lay["more_row"]:
			if p.distance_to(lay["more_row"][b]) <= btn_r(b):
				return true
	return false

func touch_down(p: Vector2, idx: int) -> void:
	var lay0 := touch_layout(get_viewport_rect().size)
	if game.panel != "":
		# panels own taps — except ☰, which becomes the only way out on a slab
		if p.distance_to(lay0["btns"]["menu"]) <= btn_r("menu"):
			game.panel = ""
		return
	var lay := touch_layout(get_viewport_rect().size)
	if joy_idx < 0 and p.distance_to(lay["joy"]) <= joy_grab_r():
		joy_idx = idx
		touch_steer(p)
		return
	for b in lay["btns"]:
		if p.distance_to(lay["btns"][b]) <= btn_r(b):
			touch_verb(b)
			return
	if touch_more:
		for b in lay["more_row"]:
			if p.distance_to(lay["more_row"][b]) <= btn_r(b):
				touch_verb(b)
				return

func touch_move(p: Vector2, idx: int) -> void:
	if idx == joy_idx:
		touch_steer(p)

func touch_up(idx: int) -> void:
	if idx == joy_idx:
		joy_idx = -1
		game.player.touch_vec = Vector2.ZERO
		game.player.touch_sprint = false

func touch_steer(p: Vector2) -> void:
	var d: Vector2 = p - touch_layout(get_viewport_rect().size)["joy"]
	var v: Vector2 = d / JOY_R
	game.player.touch_sprint = v.length() >= 0.9 # rim-push = sprint
	game.player.touch_vec = v.limit_length(1.0)

func _assign_verb() -> void:
	if game.net != null and game.net.is_client():
		game.net.rpc("assign_req", game.player.pos.x, game.player.pos.y)
	else:
		game.assign_worker()

func _stance_verb() -> void:
	# the island kin command: cycle the field kin's standing order
	if game.net != null and game.net.is_client():
		for d in game.net_party:
			if d.get("out", false):
				game.net.rpc("box_req", "cycle_stance", int(d["uid"]))
				break
	elif game.party_pal() != null:
		game.cycle_stance(game.party_pal().uid)

func _map_toggle() -> void:
	map_show = not map_show
	if map_show:
		bake_minimap() # rebake every open — terrain/decor change and load_game swaps the world

func _touch_demolish() -> void: # no cursor on a slab — raze the nearest structure
	var pt := game.player.pos
	var bt := Vector2i.ZERO; var bd := 4.5
	for k in game.structures:
		var dd: float = pt.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd < bd:
			bd = dd; bt = k
	if bd < 4.5:
		game.demolish_at(bt)
	else:
		game.log_msg("Nothing close enough to demolish")

func touch_verb(b: String) -> void:
	var pl := game.player
	match b:
		"menu":
			game.state = "paused"
		"more":
			touch_more = not touch_more
		"asg":
			_assign_verb()
		"stn":
			_stance_verb()
		"ksk":
			game.partner_skill()
		"rde":
			pl.try_mount()
		"dml":
			_touch_demolish()
		"map":
			_map_toggle()
		"aim":
			pl.aiming = not pl.aiming
		"orb":
			pl.sphere_sel = (pl.sphere_sel + 1) % maxi(1, game.sphere_tiers().size())
		"e":
			interact()
		"inv":
			game.panel = "inv"
		"bld":
			game.panel = "build"
			build_sel = -1
		"roll":
			if pl.can_dodge():
				pl.dodge_t = 0.35; pl.stamina -= 15.0; pl.stam_wait = 0.8
		"atk":
			if pl.statuses.get("sleep", 0) > game.t:
				return
			if pl.aiming:
				pl.throw_sphere(true)
			else:
				pl.melee()

func draw_touch(r: Vector2) -> void:
	if not game.touch_ui or game.state != "play":
		return
	var lay := touch_layout(r)
	if game.panel != "":
		# panels own the taps — but ☰ stays up as ✕, the slab's only way out
		var c: Vector2 = lay["btns"]["menu"]
		draw_circle(c, BTN_R, Color(0.9, 0.5, 0.5, 0.14))
		draw_arc(c, BTN_R, 0, TAU, 24, Color(0.95, 0.6, 0.6, 0.45), 1.5)
		draw_string(font, c - Vector2(font.get_string_size("X", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2, -5), "X",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.8, 0.8, 0.8))
		return
	var jc: Vector2 = lay["joy"]
	draw_circle(jc, JOY_R, Color(0.9, 0.95, 1.0, 0.10))
	draw_arc(jc, JOY_R, 0, TAU, 24, Color(0.9, 0.95, 1.0, 0.30), 1.5)
	var knob := jc + game.player.touch_vec * (JOY_R * 0.55)
	draw_circle(knob, 20, Color(0.3, 0.82, 0.88, 0.55))
	var labels := {"atk": "ATK", "aim": "AIM", "roll": "ROLL", "e": "E", "orb": "ORB",
		"inv": "INV", "bld": "BLD", "more": "···", "menu": "≡",
		"asg": "ASG", "stn": "STN", "ksk": "KSK", "rde": "RDE", "dml": "DML", "map": "MAP"}
	for b in lay["btns"]:
		var c: Vector2 = lay["btns"][b]
		var rad := 36.0 if b == "atk" else BTN_R
		draw_circle(c, rad, Color(0.9, 0.95, 1.0, 0.10))
		draw_arc(c, rad, 0, TAU, 24, Color(0.9, 0.95, 1.0, 0.35), 1.5)
		var tl: String = labels[b]
		draw_string(font, c - Vector2(font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2, -5), tl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
	if touch_more:
		for b in lay["more_row"]:
			var c2: Vector2 = lay["more_row"][b]
			draw_circle(c2, BTN_R - 8, Color(0.85, 0.8, 0.6, 0.14))
			draw_arc(c2, BTN_R - 8, 0, TAU, 24, Color(0.95, 0.9, 0.6, 0.4), 1.5)
			var tl2: String = labels[b]
			draw_string(font, c2 - Vector2(font.get_string_size(tl2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2, -4), tl2,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.98, 0.85, 0.8))

func menu_row(cx: float, y: float, w: float, label: String, act: String, col: Color = Color.WHITE) -> float:
	var rr := Rect2(cx - w / 2, y, w, 30)
	var hov := (game.state != "play" or game.panel != "") and click_rects.size() == menu_sel # cursor row glows
	draw_rect(rr, Color(0.09, 0.12, 0.16, 0.95) if hov else Color(0.05, 0.05, 0.07, 0.9))
	draw_rect(rr, Color(0.35, 0.42, 0.5, 0.8), false, 1.0)
	if hov:
		draw_rect(Rect2(rr.position + Vector2(2, 4), Vector2(3, 22)), Color("#8ef0ff")) # cursor tick — the eye finds the live row before the border
	draw_rect(Rect2(cx - w / 2 + 1, y + 29, w - 2, 1), Color(1, 1, 1, 0.05)) # row separator — list rhythm without noise
	click_rects.append({"rect": rr, "act": act, "arg": null})
	var tl := tr(label)
	draw_string(font, Vector2(cx - font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / 2, y + 20), tl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	return y + 40

func draw_weather_fx(r: Vector2) -> void:
	# screen-space weather reads better than a status glyph alone; all the
	# drops are deterministic lanes driven by game.t, not random allocation
	var t := game.t
	if game.weather == "rain" or game.weather == "storm":
		var drops := 56 if game.weather == "storm" else 40
		var speed := 180.0 if game.weather == "storm" else 120.0
		var rain_col := Color(0.55, 0.75, 1.0, 0.28 if game.weather == "storm" else 0.20)
		for d in drops:
			var dx := fposmod(d * 97.0 + t * speed, r.x + 40.0) - 20.0
			var dy := fposmod(d * 53.0 + t * speed * 1.35, r.y + 40.0) - 20.0
			draw_line(Vector2(dx, dy), Vector2(dx - 4.0, dy + 12.0), rain_col, 1.0)
	elif game.weather == "drought":
		for d in 24:
			var ddx := fposmod(d * 131.0 + t * 12.0, r.x)
			var ddy := r.y * 0.1 + fposmod(d * 67.0 + t * 4.0, r.y * 0.75)
			draw_circle(Vector2(ddx, ddy), 1.1, Color(0.95, 0.65, 0.25, 0.18))
	if game.state == "play" and game.danger_active():
		# a breathing red edge tells the keeper the island is under attack even
		# when the combat happens off-center
		var pulse := 0.10 + 0.07 * (sin(t * 6.0) + 1.0)
		var edge := 5.0
		var danger_col := Color(0.9, 0.08, 0.05, pulse)
		draw_rect(Rect2(0, 0, r.x, edge), danger_col)
		draw_rect(Rect2(0, r.y - edge, r.x, edge), danger_col)
		draw_rect(Rect2(0, 0, edge, r.y), danger_col)
		draw_rect(Rect2(r.x - edge, 0, edge, r.y), danger_col)

func draw_title_sky(r: Vector2) -> void:
	# procedural dawn over the Wildmere — the title should read as a place,
	# not a menu on a dim rectangle. All motion runs off game.t: same seeds,
	# same frame, on any machine.
	var t := game.t
	var sky_top := Color(0.10, 0.18, 0.34)
	var sky_bot := Color(0.58, 0.40, 0.46)
	for i in 16:
		draw_rect(Rect2(0, r.y * i / 16.0, r.x, r.y / 16.0 + 1.0), sky_top.lerp(sky_bot, i / 15.0))
	var sun := Vector2(r.x * 0.72, r.y * 0.28)
	for ring in 4:
		draw_circle(sun, 44.0 + ring * 18.0, Color(1.0, 0.85, 0.45, 0.045))
	draw_circle(sun, 40.0, Color(1.0, 0.87, 0.5))
	for c in 5: # clouds — each on its own slow lane, wrapping forever
		var cxx := fposmod(r.x * (0.08 + c * 0.23) + t * (4.0 + c * 1.3), r.x + 160.0) - 80.0
		var cyy := r.y * (0.10 + c * 0.055)
		for b in 3:
			draw_circle(Vector2(cxx + b * 26.0, cyy - absf(b - 1) * 8.0),
				22.0 - absf(b - 1) * 6.0, Color(1, 1, 1, 0.10))
	var sea_y := r.y * 0.68
	draw_rect(Rect2(0, sea_y, r.x, r.y - sea_y), Color(0.05, 0.16, 0.24))
	for g in 9: # sun path on the water
		var gw := 60.0 - g * 6.0
		draw_rect(Rect2(sun.x - gw / 2, sea_y + g * 14.0, gw, 3.0), Color(1.0, 0.85, 0.5, 0.10 - g * 0.008))
	draw_polygon(PackedVector2Array([Vector2(0, sea_y), Vector2(r.x * 0.18, sea_y - 46),
		Vector2(r.x * 0.34, sea_y - 20), Vector2(r.x * 0.52, sea_y - 64),
		Vector2(r.x * 0.7, sea_y - 30), Vector2(r.x, sea_y - 56), Vector2(r.x, sea_y)]),
		PackedColorArray([Color(0.04, 0.10, 0.14)])) # the island ridge the whole game happens on
	for tri in 14: # tree spikes — cheap silhouette, reads as forest at a glance
		var tx := r.x * (0.06 + tri * 0.068)
		var th := 14.0 + sin(tri * 7.0) * 8.0
		var ty := sea_y - 8.0 - 30.0 * maxf(0.0, sin(tri * 1.7))
		draw_colored_polygon(PackedVector2Array([Vector2(tx, ty - th), Vector2(tx - 7, ty), Vector2(tx + 7, ty)]),
			Color(0.05, 0.14, 0.12))
	for m in 18: # motes drifting up off the water
		var mx := fposmod(m * 137.0 + t * 6.0, r.x)
		var my := r.y * 0.15 + fposmod(m * 89.0 + t * 3.0, r.y * 0.5)
		draw_circle(Vector2(mx, my), 1.2, Color(1, 0.95, 0.7, 0.35))
	draw_rect(Rect2(Vector2.ZERO, r), Color(0.02, 0.03, 0.06, 0.42)) # vignette — menu contrast over the scene

func draw_title(r: Vector2) -> void:
	draw_title_sky(r)
	var cx := r.x / 2
	var ty := r.y * 0.22
	var brand := tr("Kinbound").to_upper() # the logo rides the locale table like everything else
	var bw := font.get_string_size(brand, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	draw_string(font, Vector2(cx - bw / 2 + 2, ty + 2), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(cx - bw / 2, ty), brand,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color("#e8d44d"))
	draw_rect(Rect2(cx - bw / 2, ty + 12, bw, 3), Color("#e8d44d")) # the gold rule under the wordmark
	for orb in [-1, 1]: # the orb motif flanking the mark — the game's own sigil
		var ox: float = cx + orb * (bw / 2 + 34.0)
		draw_circle(Vector2(ox, ty - 16), 10, Color("#e8d44d"))
		draw_circle(Vector2(ox, ty - 16), 6, Color(0.08, 0.14, 0.2))
		draw_circle(Vector2(ox - 2, ty - 19), 2, Color(1, 1, 1, 0.85))
	var tagline := tr("the Wildmere keeps what you catch")
	draw_string(font, Vector2(cx - font.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2, ty + 18), tagline,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.85))
	var y := r.y * 0.42
	if game.has_save:
		y = menu_row(cx, y, 220, "CONTINUE", "continue")
	y = menu_row(cx, y, 220, "NEW GAME", "new_game")
	y = menu_row(cx, y, 220, "SETTINGS", "m_settings")
	y = menu_row(cx, y, 220, "QUIT", "quit", Color(0.85, 0.6, 0.6))
	draw_string(font, Vector2(14, r.y - 12), tr("enter = continue · click a row"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.6))

func draw_pause(r: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, r), Color(0.02, 0.03, 0.05, 0.6))
	var cx := r.x / 2
	var ptxt := tr("MENU — the world keeps running") if game.net_live() else tr("PAUSED")
	var pw := font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(font, Vector2(cx - pw / 2, r.y * 0.3), ptxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("#e8d44d"))
	draw_rect(Rect2(cx - pw / 2, r.y * 0.3 + 6, pw, 2), Color(0.91, 0.83, 0.30, 0.4)) # gold rule under the header
	var rows := pause_rows()
	if rows.size() <= 7:
		var y := r.y * 0.42
		for row in rows:
			y = menu_row(cx, y, 220, row[0], row[1], row[2] if row.size() > 2 else Color.WHITE)
	else: # two columns — a tall stack clips the floor on small screens
		var half := int(ceil(rows.size() / 2.0))
		for i in range(rows.size()):
			var cxx := cx - 125 if i < half else cx + 125
			var yy := r.y * 0.36 + (i if i < half else i - half) * 40
			menu_row(cxx, yy, 220, rows[i][0], rows[i][1], rows[i][2] if rows[i].size() > 2 else Color.WHITE)

func pause_rows() -> Array:
	var rows := [["RESUME", "resume"], ["SAVE GAME", "m_save"], ["SETTINGS", "m_settings"]]
	if game.net != null and multiplayer.multiplayer_peer == null:
		rows.append(["JOIN SESSION", "m_join"])
		rows.append(["HOST SESSION", "m_host"])
	if multiplayer.multiplayer_peer != null:
		rows.append(["CHAT", "m_chat"])
	rows.append(["TECH TREE", "m_tech"])
	rows.append(["KINDEX", "m_dex"])
	rows.append(["STATUES", "m_statues"])
	rows.append(["GUIDE", "m_guide"])
	rows.append(["SAVE & QUIT TO TITLE", "to_title"])
	rows.append(["SAVE & QUIT GAME", "quit", Color(0.85, 0.6, 0.6)])
	return rows

func draw_settings(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 190, r.y * 0.25, 380, 300)
	draw_rect(rr, Color(0.04, 0.05, 0.07, 0.95))
	draw_rect(rr, Color(0.35, 0.42, 0.5, 0.8), false, 1.0)
	draw_string(font, Vector2(rr.position + Vector2(16, 26)), tr("SETTINGS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e8d44d"))
	var y := rr.position.y + 54
	for b in [["master", "MASTER"], ["music", "MUSIC"], ["sfx", "SFX"]]:
		var v: float = game.settings[b[0]]
		draw_string(font, Vector2(rr.position.x + 24, y + 14), "%s  %d%%" % [tr(b[1]), int(v * 100)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		draw_rect(Rect2(rr.position.x + 140, y + 4, 150, 14), Color(0.12, 0.14, 0.16))
		draw_rect(Rect2(rr.position.x + 140, y + 4, 150.0 * v, 14), Color("#4dd0e1"))
		var mr1 := Rect2(rr.position.x + 296, y, 28, 22)
		var mr2 := Rect2(rr.position.x + 330, y, 28, 22)
		click_rects.append({"rect": mr1, "act": "vol_%s_m" % b[0], "arg": null})
		click_rects.append({"rect": mr2, "act": "vol_%s_p" % b[0], "arg": null})
		draw_string(font, mr1.position + Vector2(9, 16), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		draw_string(font, mr2.position + Vector2(8, 16), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 38
	y += 8
	var fs := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": fs, "act": "fullscreen", "arg": null})
	draw_string(font, Vector2(fs.position.x, fs.position.y + 18), "%s  [%s]" % [tr("FULLSCREEN"), tr("ON") if game.settings["fullscreen"] else tr("off")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1") if game.settings["fullscreen"] else Color.WHITE)
	y += 32
	var rd := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": rd, "act": "raids_tgl", "arg": null})
	draw_string(font, Vector2(rd.position.x, rd.position.y + 18), "%s  [%s]" % [tr("BASE RAIDS"), tr("ON") if game.settings["raids"] else tr("off")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1") if game.settings["raids"] else Color(0.7, 0.7, 0.7))
	y += 32
	var lg := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": lg, "act": "lang_tgl", "arg": null})
	draw_string(font, Vector2(lg.position.x, lg.position.y + 18), "%s  [%s]" % [tr("LANGUAGE"), "中文" if game.settings.get("lang", "en") == "zh" else "EN"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	y += 32
	var tg := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": tg, "act": "touch_tgl", "arg": null})
	draw_string(font, Vector2(tg.position.x, tg.position.y + 18), "%s  [%s]" % [tr("TOUCH CONTROLS"), tr(str(game.settings.get("touch", "auto")).to_upper())],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1") if game.touch_ui else Color(0.7, 0.7, 0.7))
	y += 44
	var bk := Rect2(rr.position.x + 24, y, 120, 28)
	click_rects.append({"rect": bk, "act": "set_back", "arg": null})
	draw_string(font, Vector2(bk.position.x + 8, bk.position.y + 19), "[ %s ]" % tr("BACK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1"))

func draw_build_bar(r: Vector2) -> void:
	var lst := game.buildable_list()
	var bx := 10.0
	var by := r.y - 200.0
	draw_rect(Rect2(bx, by, 620, 56), Color(0, 0, 0, 0.75))
	draw_string(font, Vector2(bx + 8, by + 16), "BUILD — tap/1-9 pick, tap again to cancel" + ("  (placing: %s)" % StructureData.STRUCTURES[game.buildable_list()[build_sel]]["name"] if build_sel >= 0 else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#4dd0e1"))
	for i in range(mini(9, lst.size())):
		var s: Dictionary = StructureData.STRUCTURES[lst[i]]
		var cost := ""
		for c in s.get("cost", []):
			cost += "%d%s " % [c[1], c[0].left(4)]
		var col := Color("#4dd0e1") if i == build_sel else Color.WHITE
		var x := bx + 8 + (i % 5) * 122
		var y := by + 32 + (i / 5) * 14
		click_rects.append({"rect": Rect2(x - 4, y - 11, 118, 14), "act": "build_pick", "arg": i})
		draw_string(font, Vector2(x, y), "%d %s %s" % [i + 1, s["name"].left(7), cost.left(9)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

func draw_tech(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 120, 480, 360)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "TECH  (pts: %d)" % game.tech_points,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d44d"))
	var colw := 232.0
	var cap := int((rr.size.x - 24) / colw) * 18 # columns × rows that actually fit
	tech_scroll = clampi(tech_scroll, 0, maxi(0, StructureData.TECH.size() - cap))
	for ti in range(tech_scroll, StructureData.TECH.size()):
		var di := ti - tech_scroll
		var cx0: float = rr.position.x + 12 + (di / 18) * colw
		if cx0 + colw - 10 > rr.end.x:
			break # past the last column — scrolled tail lives behind the arrows
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
		var cy0: float = rr.position.y + 44 + (di % 18) * 17
		var rect := Rect2(cx0, cy0 - 12, colw - 14, 17)
		if not has:
			click_rects.append({"rect": rect, "act": "tech", "arg": k})
		draw_string(font, Vector2(cx0, cy0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	if StructureData.TECH.size() > cap:
		_scroll_btns(rr, "tech_up", "tech_dn")

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
	var skeys: Array = st.get("store", {}).keys()
	chest_scroll = clampi(chest_scroll, 0, maxi(0, skeys.size() - 12))
	for i2 in range(chest_scroll, skeys.size()):
		var iid: String = skeys[i2]
		draw_string(font, Vector2(rr.position.x + 16, y), "%s  x%d" % [ItemData.ITEMS.get(iid, {}).get("name", iid), st["store"][iid]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		y += 18
		if y > rr.end.y - 16:
			break
	if skeys.size() > 12:
		_scroll_btns(rr, "chest_up", "chest_dn")

func draw_craft(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 60, 480, 560)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8963c"))
	var y := rr.position.y + 48
	# the island repair: a worn weapon mends at the bench for half its recipe
	var rep := game.repair_quote()
	if not rep.is_empty():
		var rrect := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rrect, "act": "repair"})
		var rcost := ""
		for c in rep["cost"]:
			rcost += "%d %s, " % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])]
		var wnm: String = ItemData.ITEMS.get(game.player.equipment["weapon"], {}).get("name", "?")
		draw_string(font, Vector2(rrect.position.x, y), "REPAIR %s [%d/%d]  <-  %s" % [wnm,
			int(game.player.weapon_wear), rep["max"], rcost.left(-2).left(46)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8ef0ff") if rep["afford"] else Color("#5a6068"))
		y += 24
	var rep_a := game.repair_quote_armor()
	if not rep_a.is_empty():
		var rrect_a := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rrect_a, "act": "repair_armor"})
		var acost := ""
		for c in rep_a["cost"]:
			acost += "%d %s, " % [c[1], ItemData.ITEMS.get(c[0], {}).get("name", c[0])]
		var anm: String = ItemData.ITEMS.get(game.player.equipment["armor"], {}).get("name", "?")
		draw_string(font, Vector2(rrect_a.position.x, y), "REPAIR %s [%d/%d]  <-  %s" % [anm,
			int(game.player.armor_wear), rep_a["max"], acost.left(-2).left(46)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8ef0ff") if rep_a["afford"] else Color("#5a6068"))
		y += 24
	var vis := []
	for rec in ItemData.RECIPES:
		if rec.get("station") not in [game.craft_station, "hand"]:
			continue
		if rec.get("tech", "") != "" and rec["tech"] not in game.unlocked:
			continue
		vis.append(rec)
	craft_scroll = clampi(craft_scroll, 0, maxi(0, vis.size() - 20))
	for ri in range(craft_scroll, vis.size()):
		var rec: Dictionary = vis[ri]
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
	if vis.size() > 20:
		_scroll_btns(rr, "craft_up", "craft_dn")
	if not game.craft_queue.is_empty(): # the island bench queue: builds tick down live
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
	# the island carry weight: the bag drags once it tops capacity
	var pl := game.player
	var over: bool = pl.carry_wt() > pl.carry_cap()
	draw_string(font, Vector2(rr.position + Vector2(330, 24)), "Wt %d/%d" % [int(pl.carry_wt()), int(pl.carry_cap())],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e0503c") if over else Color("#9fd8ff"))
	var keys := game.items.keys()
	keys.sort()
	var colw := 222.0
	var rows: int = int((rr.size.y - 66) / 16) # ~27 rows per column
	inv_scroll = clampi(inv_scroll, 0, maxi(0, keys.size() - rows))
	for ki in range(inv_scroll, keys.size()):
		var k: String = keys[ki]
		var di := ki - inv_scroll
		var cx0: float = rr.position.x + 12 + (di / rows) * colw
		var y0: float = rr.position.y + 46 + (di % rows) * 16
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
	if keys.size() > rows:
		_scroll_btns(rr, "inv_up", "inv_dn")

func draw_kinbox(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 40, 600, 540)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), "KINBOX — click to swap party/base",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4dd0e1"))
	# the island base level: the terminal grades your base and pays slots
	var blv_txt := "BASE LV%d" % game.base_level
	if game.base_level < game.BASE_LEVEL_MAX:
		var bmet: bool = game.base_mission_done(game.base_level)
		blv_txt += " · next: " + game.BASE_MISSION_TEXT[game.base_level]
		draw_string(font, Vector2(rr.position.x + 330, rr.position.y + 24), blv_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a8e6a1") if bmet else Color(0.6, 0.6, 0.65))
		if bmet and (game.net == null or not game.net.is_client()):
			click_rects.append({"rect": Rect2(rr.position.x + 505, rr.position.y + 12, 80, 20),
				"act": "base_up"})
			draw_string(font, Vector2(rr.position.x + 505, rr.position.y + 26), "[UPGRADE]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffd76e"))
	else:
		draw_string(font, Vector2(rr.position.x + 330, rr.position.y + 24), blv_txt + " MAX",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd76e"))
	var y := rr.position.y + 44
	draw_string(font, Vector2(rr.position.x + 16, y), "PARTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c8f0d0"))
	y += 18
	for pr in party_rows():
		var rect := Rect2(rr.position.x + 24, y - 11, 250, 17)
		click_rects.append({"rect": rect, "act": "party_in", "arg": pr["uid"]})
		click_rects.append({"rect": Rect2(rect.position + Vector2(254, 0), Vector2(52, 17)), "act": "deploy", "arg": pr["arg"]})
		draw_string(font, Vector2(rect.position + Vector2(254, 13)), "[>base]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#a8e6a1"))
		click_rects.append({"rect": Rect2(rect.position + Vector2(310, 0), Vector2(30, 17)), "act": "lead", "arg": pr["uid"]})
		draw_string(font, Vector2(rect.position + Vector2(312, 13)), "[▼]" if pr["out"] else "[*]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd76e"))
		if game.net == null or not game.net.is_client(): # host-owned pals only
			click_rects.append({"rect": Rect2(rect.position + Vector2(342, 0), Vector2(34, 17)), "act": "skills", "arg": pr["arg"]})
			draw_string(font, Vector2(rect.position + Vector2(344, 13)), "[mv]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8ef0ff"))
		draw_string(font, Vector2(rect.position.x, y), "%s%s%s %s%s Lv%d T%d %s HP%d/%d" % [
			"● " if pr["out"] else "○ ", pr["name"],
			"☆" if pr["lucky"] else "", pr["sex"], pr["star_s"], pr["lv"], pr["talent"],
			(pr["ailment"] + "! ") if pr["ailment"] != "" else pr["sub"], pr["hp"], pr["max_hp"]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8a0a0") if pr["ailment"] != "" else Color.WHITE)
		y += 17
	# deployed workforce (the island: kin working the base live in the world)
	var workers := game.base_pals()
	if game.net == null or not game.net.is_client():
		workers = workers.filter(func(wp): return wp.owner_id == 0) # a guest's hands aren't yours to recall
	if not workers.is_empty():
		y += 8
		draw_string(font, Vector2(rr.position.x + 16, y), "BASE (%d/%d) — click to recall" % [workers.size(), game.max_base_pals()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8dff0"))
		y += 18
		for wp in workers:
			var wrect := Rect2(rr.position.x + 24, y - 11, 250, 17)
			if game.net == null or not game.net.is_client():
				click_rects.append({"rect": wrect, "act": "base_in", "arg": wp})
				# a guest reads the crew roster but can't recall the keeper's kin
			draw_string(font, Vector2(wrect.position.x, y), "%s%s %s Lv%d T%d %s%s" % [wp.spec["name"],
				"☆" if wp.lucky else "", wp.sex, wp.level, wp.talent,
				wp.job_site["id"] if wp.job_site else "idle",
				" [%s]" % wp.ailment if wp.ailment != "" else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d06a6a") if wp.ailment != "" else Color("#a8dff0"))
			if game.net == null or not game.net.is_client():
				click_rects.append({"rect": Rect2(wrect.position + Vector2(258, 0), Vector2(34, 17)), "act": "skills", "arg": wp})
				draw_string(font, Vector2(wrect.position.x + 260, y), "[mv]",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8ef0ff"))
			y += 17
	y += 10
	var brows := box_rows()
	draw_string(font, Vector2(rr.position.x + 16, y), "BOX (%d)" % brows.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8963c"))
	y += 18
	var colw := 288.0
	var rows: int = int((rr.end.y - y - 8) / 16)
	kin_scroll = clampi(kin_scroll, 0, maxi(0, brows.size() - rows))
	for bi in range(kin_scroll, brows.size()):
		var rd: Dictionary = brows[bi]
		var di := bi - kin_scroll
		var cx0: float = rr.position.x + 16 + (di / rows) * colw
		var y0: float = y + (di % rows) * 16
		if cx0 + colw - 8 > rr.end.x:
			break
		var butcher := game.item_count("meat_cleaver") > 0
		var rect := Rect2(cx0, y0 - 11, colw - (56 if butcher else 34), 16)
		click_rects.append({"rect": rect, "act": "box_out", "arg": rd["arg"]})
		var frect := Rect2(cx0 + colw - (52 if butcher else 30), y0 - 11, 20, 16)
		click_rects.append({"rect": frect, "act": "fav", "arg": rd["uid"]})
		draw_string(font, Vector2(frect.position.x + 3, y0), "♥" if rd["fav"] else "♡",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e86a92") if rd["fav"] else Color(0.55, 0.55, 0.55))
		if butcher:
			var brect := Rect2(cx0 + colw - 30, y0 - 11, 22, 16)
			click_rects.append({"rect": brect, "act": "butcher", "arg": rd["uid"]})
			draw_string(font, Vector2(brect.position.x + 3, y0), "[x]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c0392b"))
		var label := "%s%s %s%s Lv%d T%d HP%d/%d%s%s %s" % [rd["name"], "☆" if rd["lucky"] else "", rd["sex"], rd["star_s"], rd["lv"], rd["talent"],
			int(maxi(0, rd["hp"])), int(rd["max_hp"]), rd["ko_t"],
			" [%s]" % rd["ailment"] if rd["ailment"] != "" else "",
			str(rd.get("wk", "")).left(15)]
		draw_string(font, Vector2(cx0, y0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d06a6a") if rd["ko"] or rd["ailment"] != "" else Color("#c8d3d5"))
	if brows.size() > rows:
		_scroll_btns(rr, "kin_up", "kin_dn")

func party_rows() -> Array:
	# normalized party rows: ● marks the one kin out of its ball. Host reads
	# Kin objects (world + bench store), a client reads the net_party mirror.
	var out := []
	if game.net != null and game.net.is_client():
		for d in game.net_party:
			var sp: Dictionary = SpeciesData.species_of(str(d["sid"]))
			var st := ""
			for i in int(d["star"]):
				st += "*"
			if st != "":
				st = " " + st
			out.append({"arg": int(d["uid"]), "uid": int(d["uid"]), "name": sp.get("name", str(d["sid"])),
				"lucky": d["lucky"], "sex": d["sex"], "lv": d["lv"], "talent": d["talent"],
				"hp": d["hp"], "max_hp": d["max_hp"], "ailment": d["ailment"],
				"star_s": st, "out": d["out"], "sub": "resting", "stance": str(d.get("stance", "auto")),
				"wk": str(d.get("wk", ""))})
	else:
		var cur := game.party_pal()
		for uid in game.party:
			var p := game.find_pal(uid)
			if p == null:
				p = game.bench_pal_of(uid)
			if p == null:
				continue
			out.append({"arg": p, "uid": p.uid, "name": p.spec["name"], "lucky": p.lucky,
				"sex": p.sex, "lv": p.level, "talent": p.talent, "hp": int(p.hp),
				"max_hp": int(p.max_hp), "ailment": p.ailment,
				"star_s": star_str(p), "out": p == cur, "sub": passive_str(p).left(14),
				"stance": p.stance, "wk": game.work_str(p.spec)})
	return out

func box_rows() -> Array:
	# normalized kinbox rows: host reads live Kin objects, a client reads the
	# synced net_box roster. Same dict shape either way so the panel forks once.
	var out := []
	if game.net != null and game.net.is_client():
		for d in game.net_box:
			var sp: Dictionary = SpeciesData.species_of(str(d["sid"]))
			var st := ""
			for i in int(d["star"]):
				st += "*"
			if st != "":
				st = " " + st
			out.append({"arg": int(d["uid"]), "uid": int(d["uid"]),
				"name": sp.get("name", str(d["sid"])), "lucky": d["lucky"], "sex": d["sex"],
				"lv": d["lv"], "talent": d["talent"], "hp": d["hp"], "max_hp": d["max_hp"],
				"ailment": d["ailment"], "fav": d["fav"], "star_s": st,
				"ko": d["hp"] <= 0, "ko_t": " [KO]" if d["hp"] <= 0 else "",
				"wk": str(d.get("wk", ""))})
	else:
		for bp in game.box:
			if bp.owner_id != 0:
				continue # a guest's stock doesn't show in the keeper's box
			out.append({"arg": bp, "uid": bp.uid, "name": bp.spec["name"], "lucky": bp.lucky,
				"sex": bp.sex, "lv": bp.level, "talent": bp.talent, "hp": int(bp.hp),
				"max_hp": int(bp.max_hp), "ailment": bp.ailment, "fav": bp.fav,
				"star_s": star_str(bp), "ko": bp.hp <= 0,
				"ko_t": " [KO %ds]" % int(maxi(0.0, bp.revive_t - game.t)) if bp.hp <= 0 else "",
				"wk": game.work_str(bp.spec)})
	return out

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
	var sell_n := 0 # sell column counts only rows that actually render
	for k0 in game.items.keys():
		if ItemData.ITEMS.get(k0, {}).get("price", 0) > 0 and k0 != "gold_coin" and game.items[k0] > 0:
			sell_n += 1
	sell_n += mini(game.box.size(), 12)
	shop_scroll = clampi(shop_scroll, 0, maxi(0, maxi(game.merchant_stock.size(), sell_n) - 22))
	for i in range(shop_scroll, game.merchant_stock.size()):
		var it: Dictionary = game.merchant_stock[i]
		var nm: String
		if it.has("kin"):
			var sp: Dictionary = SpeciesData.species_of(str(it["kin"]))
			nm = "Lv%d %s" % [it["lv"], sp.get("name", it["kin"])]
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
	var si := -1 # sell column scrolls with the buy column — one offset, two rails
	for k in skeys:
		var price: int = ItemData.ITEMS.get(k, {}).get("price", 0)
		if price <= 0 or k == "gold_coin" or game.items[k] <= 0:
			continue
		si += 1
		if si < shop_scroll:
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
		si += 1
		if si < shop_scroll:
			continue
		if y > rr.end.y - 14 or shown >= 12:
			break
		var rect := Rect2(rr.position.x + 316, y - 12, 270, 16)
		click_rects.append({"rect": rect, "act": "sell_pal", "arg": bp.uid})
		draw_string(font, Vector2(rect.position.x, y), "Lv%d %s  +%dg" % [bp.level,
			String(bp.spec["name"]).left(14), game.pal_sell_price(bp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8963c"))
		y += 17
		shown += 1
	_scroll_btns(rr, "shop_up", "shop_dn", rr.position.x + 289, true) # column gutter

func use_item(k: String) -> void:
	match k:
		"boss_sigil":
			if game.summon_raid():
				game.add_item(k, -1)
		"gauntlet_sigil":
			if game.start_gauntlet():
				game.add_item(k, -1)
		"kin_egg", "huge_kin_egg":
			game.deposit_egg()  # needs a free incubator nearby — huge eggs take the slot first
		"fishing_rod":
			game.cast_line() # reusable — the rod never leaves the pack
		"memory_wipe":
			if game.respec():
				game.add_item(k, -1)
		"fertilizer":
			game.fertilize()
		"kin_bait":
			game.throw_bait()
		"treasure_map":
			game.use_treasure_map()
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
				var bf: Dictionary = it.get("buff", {})
				if not bf.is_empty(): # the island meal bonus: one timed buff at a time
					game.player.eat_buff(bf)
					var bstr := ""
					for bk in bf:
						if bk != "t":
							bstr += ("+" if bstr == "" else ",+") + str(bk).to_upper()
					game.log_msg("Meal buff: %s for %ds" % [bstr, int(bf.get("t", 300))])
			else:
				game.log_msg("Can't use " + k)

func _text_btns(rr: Rect2, ok_act: String) -> void:
	# on-screen confirm/cancel — the only out when there's no Esc/Enter key
	var ok := Rect2(rr.end.x + 6, rr.position.y, 40, rr.size.y)
	var cx := Rect2(ok.end.x + 6, rr.position.y, 34, rr.size.y)
	draw_rect(ok, Color(0.15, 0.4, 0.2, 0.9))
	draw_rect(ok, Color(0.4, 0.8, 0.5), false, 1.0)
	draw_string(font, ok.position + Vector2(11, rr.size.y - 10), "OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1"))
	draw_rect(cx, Color(0.4, 0.15, 0.15, 0.9))
	draw_rect(cx, Color(0.8, 0.4, 0.4), false, 1.0)
	draw_string(font, cx.position + Vector2(11, rr.size.y - 10), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e6a1a1"))
	click_rects.append({"rect": ok, "act": ok_act, "arg": null})
	click_rects.append({"rect": cx, "act": "text_cancel", "arg": null})

func draw_join(r: Vector2) -> void:
	var rr := Rect2(10, r.y - 58, 520, 44)
	draw_rect(rr, Color(0, 0, 0, 0.8))
	draw_string(font, rr.position + Vector2(10, 19), tr("Join IP (blank=localhost): ") + join_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9fd8ff"))
	_text_btns(rr, "join_go")

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
		var nm := "Kinbox" if n["id"] == "kinbox" else "Waypoint"
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
		"KINDEX   %d/%d caught · %d seen" % [caught, ids.size(), seen_n],
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
			var hz := SpeciesGen.habitat(sid) # Kindex habitat: where to hunt it
			draw_string(font, Vector2(rr.position.x + 320, y), "%s %s×%d" % [els.left(11),
				"z%d  " % hz if hz >= 0 else "", cc],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fd8a0"))
			# field guide: a caught species tells you what it drops
			var dnames := []
			for dr in sp.get("drops", []):
				dnames.append(str(ItemData.ITEMS.get(dr[0], {}).get("name", dr[0])).left(9))
			draw_string(font, Vector2(rr.position.x + 445, y), ", ".join(dnames).left(13),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.65, 0.5))
			# and which posts it can staff — the base-planning half of the entry
			draw_string(font, Vector2(rr.position.x + 530, y), game.work_str(sp).left(10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.75, 0.9))
		elif game.dex_seen.has(sid):
			draw_string(font, Vector2(rr.position.x + 16, y), "%s %s  ·spotted·" % [sp.get("glyph", "?"), str(sp.get("name", sid)).left(18)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.65, 0.72))
		else:
			draw_string(font, Vector2(rr.position.x + 16, y), "?  ?????",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.35, 0.4))
		y += 15
	draw_string(font, Vector2(rr.position.x + 16, rr.end.y - 16),
		"wheel scroll · every 10 species caught pays +2 tech", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.65))
	_scroll_btns(rr, "dex_up", "dex_dn")

func draw_chat(r: Vector2) -> void:
	var rr := Rect2(12, r.y - 40, 480, 28)
	draw_rect(rr, Color(0, 0, 0, 0.8))
	draw_string(font, rr.position + Vector2(10, 19), tr("Say: ") + chat_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a8e6a1"))
	_text_btns(rr, "chat_send")

func star_str(p: Kin) -> String:
	var s := ""
	for i in p.star:
		s += "*"
	if s != "":
		s = " " + s
	return s

func passive_str(p: Kin) -> String:
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
	if game.player.weapon_wear >= 0.0:
		wn += " [%d]" % int(game.player.weapon_wear)
	var an: String = ItemData.ITEMS.get(game.player.equipment["armor"], {}).get("name", "None")
	var acc := ""
	for s in ["acc1", "acc2"]:
		var a: String = ItemData.ITEMS.get(game.player.equipment[s], {}).get("name", "")
		if a != "":
			acc += "  " + a
	return "Wpn: %s   Arm: %s%s" % [wn, an, acc]

func draw_statues(r: Vector2) -> void:
	# panel rect like every sibling — the old body treated the viewport
	# SIZE as a position and painted the whole panel off-screen (dead UI)
	var rr := Rect2(r.x / 2 - 230, 50, 460, r.y - 100)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	draw_string(font, rr.position + Vector2(16, 24), "EFFIGIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#9be8a0"))
	var y := rr.position.y + 56.0
	draw_string(font, Vector2(rr.position.x + 16, y - 16), "Stat points: %d   Sprigmelt Effigies: %d" % [game.stat_pts, game.item_count("sprigmelt_effigy")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9be8a0"))
	for k in game.perks:
		var lvl: int = game.perks[k]
		var cost := 2 + lvl * 2
		var txt := "%s  Lv%d/5  (cost %d)" % [PERK_LABEL.get(k, k), lvl, cost] # foreign saves can inject unknown perk keys
		var rect := Rect2(rr.position.x + 16, y - 12, 360, 20)
		var col := Color.WHITE if lvl < 5 else Color(0.5, 0.5, 0.5)
		if lvl < 5:
			click_rects.append({"rect": rect, "act": "perk", "arg": k})
		draw_string(font, Vector2(rect.position.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 24
	# soul infusion: the same effigies harden a kin you own
	y += 10
	draw_string(font, Vector2(rr.position.x + 16, y - 16), "SOUL INFUSION (+4%/soul)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c08cff"))
	var infused := []
	for uid in game.party:
		var qp: Kin = game.find_pal(uid)
		if qp == null:
			qp = game.bench_pal_of(uid)
		if qp != null:
			infused.append(qp)
	for bp2 in game.box:
		infused.append(bp2)
	var rows2: int = int((rr.end.y - y - 8) / 20)
	stat_scroll = clampi(stat_scroll, 0, maxi(0, infused.size() - rows2))
	for i3 in range(stat_scroll, infused.size()):
		var q2: Kin = infused[i3]
		var cost2: int = 1 + q2.soul_boost
		var full: bool = q2.soul_boost >= 10
		if y > rr.end.y - 14:
			break
		var rect2 := Rect2(rr.position.x + 16, y - 12, 360, 20)
		if not full:
			click_rects.append({"rect": rect2, "act": "infuse", "arg": q2.uid})
		var col2 := Color(0.5, 0.5, 0.5) if full else Color.WHITE
		draw_string(font, Vector2(rect2.position.x, y), "%s Lv%d  soul+%d  (cost %d)" %
			[str(q2.spec["name"]).left(14), q2.level, q2.soul_boost, cost2],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col2)
		y += 20
	if infused.size() > rows2:
		_scroll_btns(rr, "stat_up", "stat_dn")

func draw_equipment_line() -> void:
	draw_string(font, Vector2(14, 80), _eq_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9d8e8"))

func draw_skills(r: Vector2) -> void:
	# the island move loadout: slot up to 3 of the kin's learned moves —
	# an empty loadout means "use everything learned" (the old default)
	var rr := Rect2(r.x / 2 - 220, 140, 440, 300)
	draw_rect(rr, Color(0, 0, 0, 0.85))
	var tp := game.skill_target
	if tp == null or not is_instance_valid(tp):
		draw_string(font, rr.position + Vector2(16, 24), "No kin selected",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		return
	draw_string(font, rr.position + Vector2(16, 24),
		"%s — slot up to 3 moves (Esc closes)" % tp.spec["name"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8ef0ff"))
	var y := rr.position.y + 50
	for sid in tp.learned_skills():
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		var on: bool = sid in tp.equipped
		var rect := Rect2(rr.position.x + 16, y - 12, 400, 18)
		click_rects.append({"rect": rect, "act": "skill_tgl", "arg": {"p": tp, "sid": sid}})
		draw_string(font, Vector2(rect.position.x, y), "%s %s  pow%d  cd%ds" %
			["[x]" if on else "[ ]", str(sk.get("name", sid)).left(18),
				int(sk.get("power", 0)), int(sk.get("cooldown", 2))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color("#ffd76e") if on else Color(0.75, 0.75, 0.8))
		y += 19
	y += 8
	draw_string(font, Vector2(rr.position.x + 16, y),
		"empty loadout = all learned moves fire",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.65))


func draw_guide(r: Vector2) -> void:
	# the Field Guide — a traveler's handbook in the world's own voice
	var w := 620.0
	var h := r.y - 60.0
	var rr := Rect2(Vector2(r.x - w, 10) / 2.0 + Vector2(0, 20), Vector2(w, h - 30))
	draw_rect(rr.grow(3), Color(0.08, 0.05, 0.03, 0.94)) # worn leather
	draw_rect(rr, Color(0.94, 0.88, 0.72, 0.96))          # parchment
	var lines := []
	for raw in GuideData.PAGES[guide_page].split("\n"):
		if raw.length() <= 74:
			lines.append(raw)
			continue
		var rest: String = raw
		while rest.length() > 74:
			var cut: int = rest.rfind(" ", 74)
			if cut < 30:
				cut = 74
			lines.append(rest.substr(0, cut))
			rest = rest.substr(cut + 1)
		lines.append(rest)
	var y := rr.position.y + 22
	for i in range(lines.size()):
		var ln: String = lines[i]
		var head: bool = ln.begins_with("—") or (i < 2 and ln == ln.to_upper() and ln.length() > 3)
		draw_string(font, Vector2(rr.position.x + 22, y), ln,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color("#5a3a1a") if head else Color(0.22, 0.18, 0.12))
		y += 19
	draw_string(font, Vector2(rr.position.x + 22, rr.end.y - 14),
		"n close · ←/→ turn the page · %d / %d" % [guide_page + 1, GuideData.PAGES.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7a6a4a"))
	# tap turners — no arrow keys on a slab
	var pv := Rect2(rr.end.x - 84, rr.end.y - 34, 34, 24)
	var nx := Rect2(rr.end.x - 42, rr.end.y - 34, 34, 24)
	for b3 in [[pv, "guide_prev", "‹"], [nx, "guide_next", "›"]]:
		draw_rect(b3[0], Color(0.55, 0.4, 0.2, 0.85))
		draw_rect(b3[0], Color(0.35, 0.25, 0.1), false, 1.0)
		draw_string(font, b3[0].position + Vector2(11, 18), b3[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#f4e8c8"))
		click_rects.append({"rect": b3[0], "act": b3[1], "arg": null})
