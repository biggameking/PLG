extends Control
# HUD + panels: HP/XP, orbs, log, time, party; B build / I inv / T tech /
# E interact (craft near workbench, kinbox mgmt near kinbox); ESC closes.

var game: Game
var font: Font = ThemeDB.fallback_font
var show_help := false
var guide_page := 0
var dex_scroll := 0
var guide_scroll := 0 # in-page scroll — a volume taller than the paper still reads
var chest_scroll := 0
var craft_scroll := 0
var shop_scroll := 0
var inv_scroll := 0
var kin_scroll := 0
var tech_scroll := 0
var stat_scroll := 0
var build_sel := -1
var build_scroll := 0 # page offset into buildable_list() — 9 slots per page
var build_sel_sid := "" # the sid the pick pointed at — a list reorder must
# not silently retarget the ghost onto a different building (audit-59)
var _dia_line := PackedVector2Array() # ghost-footprint template — built once
var _dia_poly := PackedVector2Array() # and drawn per cell via draw_set_transform
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
var _fog_seen := -1              # explored_n at last bake — a clean fog isn't re-stamped
var map_show := false

# roster portraits: one lazily-loaded species sprite per row list — the cache
# is bounded by the species table itself and stores misses too, so a bad id
# costs one failed load() ever, not one per frame
var _kin_tex := {}
func kin_tex(sid: String) -> Texture2D:
	if not _kin_tex.has(sid):
		var path := "res://assets/kin/%s_f0.png" % sid
		_kin_tex[sid] = load(path) if ResourceLoader.exists(path) else null
	return _kin_tex[sid]

# structure sprites for build-bar icons + the placement ghost — same
# bounded lazy-cache contract as kin_tex (misses cached once)
var _struct_tex := {}
func struct_tex(sid: String) -> Texture2D:
	if not _struct_tex.has(sid):
		var path := "res://assets/structures/%s.png" % sid
		_struct_tex[sid] = load(path) if ResourceLoader.exists(path) else null
	return _struct_tex[sid]

func draw_portrait(pos: Vector2, sid: String, w := 20.0, h := 16.0) -> void:
	var t := kin_tex(sid)
	if t != null:
		draw_texture_rect(t, Rect2(pos, Vector2(w, h)), false)

func bake_minimap() -> void:
	var W := game.world
	map_img = Image.create(W.WORLD_W, W.WORLD_H, false, Image.FORMAT_RGB8)
	var cols := {
		W.Tile.WATER: Color(0.42, 0.68, 0.84), W.Tile.SAND: Color(0.91, 0.82, 0.58),
		W.Tile.GRASS: Color(0.55, 0.72, 0.42), W.Tile.TALLGRASS: Color(0.42, 0.62, 0.34),
		W.Tile.FLOWER: Color(0.66, 0.74, 0.48), W.Tile.STONEFIELD: Color(0.62, 0.62, 0.66),
		W.Tile.DIRT: Color(0.72, 0.58, 0.40), W.Tile.FARMLAND: Color(0.72, 0.58, 0.36)}
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
	fog_img.fill(Color(0.11, 0.10, 0.18, 0.85)) # ink-dark fog, not pure black
	var i := 0
	for y in W.WORLD_H:
		for x in W.WORLD_W:
			if i < game.explored.size() and game.explored[i] != 0:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0))
			i += 1
	fog_tex = ImageTexture.create_from_image(fog_img)
	_fog_seen = game.explored_n # remember which fog this texture carries
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pf = load("res://fonts/PressStart2P-Regular.ttf")
	if pf != null:
		# fallback ladder: pixel Latin → bundled pixel CJK → bundled symbols →
		# system face. SystemFont can't rasterize on web/Android (audit-45) —
		# the bundled subsets carry every zh + HUD glyph there. load_dynamic_font
		# reads the raw .ttf, so no .import sidecar is needed in the export.
		var cjk := FontFile.new()
		var chain: Array[Font] = []
		if cjk.load_dynamic_font("res://fonts/FusionPixel12px.ttf") == OK:
			chain.append(cjk)
		var syms := FontFile.new()
		if syms.load_dynamic_font("res://fonts/DejaVuSymbols.ttf") == OK:
			chain.append(syms)
		chain.append(font)
		pf.fallbacks = chain
		font = pf # the island's own voice: pixel type, not the engine default

var _memo_t := -1.0      # 4Hz hud-string/scan refresh clock (audit-45)
var _mouse_finger := false # LMB-through-touch active (desktop forced touch_ui)
var _memo_boss: Kin = null
var _memo_den := ""
var _memo_raid_txt := ""
var _memo_mission_txt := ""
var _memo_hints: Array = []

var nav_hold := 0.0 # menu hold-to-repeat clock — edge press moves once, hold marches
func _process(dt: float) -> void:
	queue_redraw()
	# a held direction emits no events — catch the transition here too or the
	# old hold would keep marching into the new menu with no fresh 0.42s delay
	if game != null and "%s|%s" % [game.state, game.panel] != _menu_key:
		_menu_key = "%s|%s" % [game.state, game.panel]
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
	if game != null and not game.touch_ui and joy_idx >= 0:
		_release_stick() # a mid-drag touch toggle can't leave a ghost stick
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
	if game.touch_ui and (game.state == "play" or game.panel != ""):
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
		# desktop "TOUCH CONTROLS: on" — a mouse emits no ScreenTouch, so the
		# row rendered dead buttons that still swallowed clicks (audit-45).
		# Route LMB through the touch path under a synthetic finger index.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if touch_zone_hit(event.position):
					touch_down(event.position, 99)
					_mouse_finger = true
					get_viewport().set_input_as_handled()
					return
			elif _mouse_finger:
				touch_up(99)
				_mouse_finger = false
				get_viewport().set_input_as_handled()
				return
		if _mouse_finger and event is InputEventMouseMotion:
			touch_move(event.position, 99)
			get_viewport().set_input_as_handled()
			return
	# text panels type in EVERY state — the pause shell can open them, so the
	# buffers must live above the shell's eat-everything branch
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
	# guide paging rides the same hoist — pause rows can open it too
	if game.panel == "guide" and event is InputEventKey and event.pressed:
		if event.is_action_pressed("ui_right"):
			guide_page = mini(guide_page + 1, GuideData.pages().size() - 1)
		elif event.is_action_pressed("ui_left"):
			guide_page = maxi(guide_page - 1, 0)
		elif event.is_action_pressed("ui_cancel") or event.keycode == KEY_N or event.keycode == KEY_G:
			game.panel = ""
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
	if event.is_action_pressed("ui_cancel") and game.panel != "":
		game.panel = ""
		return
	if event.is_action_pressed("ui_cancel") and game.panel == "":
		game.state = "paused" # Esc with nothing open pulls the shell over the sim
		return
	if event.is_action_pressed("build"):
		game.panel = "" if game.panel == "build" else "build"
		build_sel = -1
		build_sel_sid = ""
		build_scroll = 0 # menu-state reset — same convention as dex/guide
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
	if game.panel in ["dex", "chest", "craft", "shop", "inv", "kinbox", "tech", "statues", "build"] and event is InputEventMouseButton and event.pressed:
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
		if event is InputEventJoypadButton:
			_touch_demolish() # a stick has no cursor — raze the nearest, like the slab
		else:
			_demolish_verb(mouse_tile())
		return
	if event.is_action_pressed("pad_next_pal"):
		if game.panel != "":
			return
		game.cycle_field_pal() # R3 — the pad's party hotbar
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
		# same overwrite class as NEW GAME — one stray F4 can't vaporize a
		# session. First tap arms and says so; the second within 4s loads.
		if game.load_arm > game.t:
			game.load_arm = -1.0
			game.load_game()
		else:
			game.load_arm = game.t + 4.0
			game.log_msg(tr("Press F4 again to reload the last save — progress since is lost"))
		return
	if event.is_action_pressed("host_net"):
		if game.net and game.net.multiplayer.multiplayer_peer == null:
			game.net.host() # J: host on :7777 — refused mid-session:
		elif game.net:                    # a guest re-hosting severs its own
			game.log_msg(tr("End the session first (quit to title)")) # replica world
		return
	if event.is_action_pressed("join_net"):
		if game.net and game.panel == "" and game.net.multiplayer.multiplayer_peer == null:
			game.panel = "join"; join_buf = "" # K: type the host's IP, Enter to join
		return
	if event is InputEventKey and event.pressed and game.panel == "":
		# the island party hotbar: 1..party_cap sends that slot's kin out (again recalls)
		var k2: int = event.keycode
		if k2 >= KEY_1 and k2 < KEY_1 + game.party_cap():
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
			var i := build_scroll + (k - KEY_1) # keys address the visible page
			build_sel = i if i < lst.size() else -1
			build_sel_sid = lst[build_sel] if build_sel >= 0 else ""
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for cr in click_rects:
			if cr["rect"].has_point(event.position):
				run_click(cr)
				get_viewport().set_input_as_handled() # a panel-closing act must not fall through to melee
				return
		if game.panel == "build" and build_sel >= 0 and _build_tap_ok(event.position):
			place_ghost() # the ✕ tap arrives as a mouse event first — never plant under it
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and game.panel == "build":
		build_sel = -1
		build_sel_sid = ""
		game.panel = ""

func _panel_scroll(dir: int) -> void: # wheel/tap scroller — draw clamps to real bounds
	match game.panel:
		"dex": dex_scroll = maxi(0, dex_scroll + dir)
		"chest": chest_scroll = maxi(0, chest_scroll + dir)
		"craft": craft_scroll = maxi(0, craft_scroll + dir)
		"shop": shop_scroll = maxi(0, shop_scroll + dir)
		"inv": inv_scroll = maxi(0, inv_scroll + dir)
		"kinbox": kin_scroll = maxi(0, kin_scroll + dir)
		"build": build_scroll = maxi(0, build_scroll + dir * 9)
		"tech": tech_scroll = maxi(0, tech_scroll + dir)
		"statues": stat_scroll = maxi(0, stat_scroll + dir)
		"guide": guide_scroll = maxi(0, guide_scroll + dir)

func _scroll_btns(rr: Rect2, up_act: String, dn_act: String, bx := -1.0, stacked := false) -> void:
	# tap scrollers — lists taller than the panel need a slab-reachable tail
	if bx < 0.0:
		bx = rr.end.x - 30
	var up_r := Rect2(bx, rr.position.y + 8, 24, 24)
	var dn_r := Rect2(bx, rr.position.y + 36 if stacked else rr.end.y - 32, 24, 24)
	for b2 in [[up_r, up_act, "▲"], [dn_r, dn_act, "▼"]]:
		draw_rect(b2[0], Ink.PAPER_DARK)
		draw_rect(b2[0], Ink.INK, false, 1.5)
		draw_string(font, b2[0].position + Vector2(6, 17), b2[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK)
		click_rects.append({"rect": b2[0], "act": b2[1], "arg": null})

func _chat_submit() -> void:
	if chat_buf.strip_edges() != "" and game.net:
		game.net.rpc("chat", chat_buf, multiplayer.get_unique_id())
		game.log_msg(tr("[you] ") + chat_buf)
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
		"x_close":
			game.panel = "" # the touch ✕ is also a click target — pads and mice hit it too
		"craft":
			game.craft(cr["arg"])
		"repair":
			game.repair_weapon()
		"repair_armor":
			game.repair_armor()
		"tech":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("Research is the host's to direct"))
			else:
				game.unlock(cr["arg"])
		"box_out":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "box_to_party", int(cr["arg"].uid))
			else:
				game.box_to_party(cr["arg"])
		"party_in":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "party_to_box", int(cr["arg"]))
			else:
				game.party_to_box(cr["arg"])
		"lead":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "make_active", int(cr["arg"]))
			else:
				game.make_active(cr["arg"])
		"deploy":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "deploy_to_base", int(cr["arg"].uid))
			else:
				game.deploy_to_base(cr["arg"])
		"base_in":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "base_to_box", int(cr["arg"].uid))
			else:
				game.base_to_box(cr["arg"])
		"use_item":
			use_item(cr["arg"])
		"buy":
			# the stock is the island's — guests ask, hosts decrement; the bag
			# pays the mirrored price up front and bought settles the truth
			if game.net != null and game.net.is_client():
				var rw: Dictionary = game.merchant_stock[int(cr["arg"])] \
					if int(cr["arg"]) >= 0 and int(cr["arg"]) < game.merchant_stock.size() else {}
				if rw.is_empty():
					game.log_msg(tr("Nothing on the stand"))
				elif game.item_count("gold_coin") < int(rw.get("price", 0)):
					game.log_msg(tr("Not enough gold — %dg asked") % int(rw.get("price", 0)))
				else:
					if game.net.pay("buy", {"gold_coin": int(rw.get("price", 0))}):
						game.net.rpc("buy_req", float(cr["arg"]))
			else:
				game.buy_from_merchant(cr["arg"])
		"sell":
			game.sell_to_merchant(cr["arg"]) # your bag + your gold — local is honest
		"sell_pal":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "sell_pal", int(cr["arg"]))
			else:
				game.sell_pal_to_merchant(cr["arg"])
		"butcher":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "butcher_pal", int(cr["arg"]))
			else:
				game.butcher_pal(cr["arg"])
		"fav":
			if game.net != null and game.net.is_client():
				game.net.rpc("box_req", "toggle_fav", int(cr["arg"]))
			else:
				game.toggle_fav(cr["arg"])
		"skills":
			game.skill_target = cr["arg"]
			game.panel = "skills"
		"skill_tgl":
			if game.net != null and game.net.is_client():
				var skp: Kin = cr["arg"]["p"]
				game.net.rpc("box_req", "toggle_skill",
					skp.net_id if skp.net_id > 0 else skp.uid, str(cr["arg"]["sid"]))
			else:
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
			guide_scroll = 0
		"guide_next":
			guide_page = mini(guide_page + 1, GuideData.pages().size() - 1)
			guide_scroll = 0
		"guide_up": _panel_scroll(-1)
		"guide_dn": _panel_scroll(1)
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
			var bll := game.buildable_list()
			build_sel_sid = bll[build_sel] if build_sel >= 0 and build_sel < bll.size() else ""
		"build_pg":
			build_scroll = maxi(0, build_scroll + int(cr["arg"]) * 9)
			build_sel = -1 # a page flip voids the selection (menu-state rule)
			build_sel_sid = ""
		"equip":
			game.equip(cr["arg"])
		"perk":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("The statue answers the island's keeper")) # perks are the host keeper's own
			else:
				game.upgrade_perk(cr["arg"])
		"base_up":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("The stand answers the island's keeper")) # base level is the host's claim
			else:
				game.upgrade_base()
		"infuse":
			if game.net != null and game.net.is_client():
				var sb := 0 # replica rows carry soul_boost — the panel cost is 1+boost
				for q in game.pals:
					if q.uid == int(cr["arg"]):
						sb = q.soul_boost
						break
				if game.item_count("sprigmelt_effigy") < 1 + sb:
					game.log_msg(tr("Needs %d effigies") % (1 + sb))
				else:
					if game.net.pay("infuse", {"sprigmelt_effigy": 1 + sb}):
						game.net.rpc("infuse_req", float(cr["arg"])) # your kin, host truth
			else:
				game.soul_infuse(cr["arg"])
		# ---- shell menu acts (title / pause / settings) ----
		_:
			if cr["act"] in SHELL_ACTS:
				game.sfx_play("click")
				shell_act(cr["act"])
			elif cr["act"] == "chest_dep" or cr["act"] == "chest_wd":
				chest_bulk(cr["act"])

const SHELL_ACTS := ["new_game", "continue", "m_settings", "m_join", "m_host", "m_chat",
	"m_tech", "m_dex", "m_statues", "m_guide", "m_inv", "set_back", "resume",
	"m_save", "to_title", "quit", "vol_master_m", "vol_master_p", "vol_music_m",
	"vol_music_p", "vol_sfx_m", "vol_sfx_p", "fullscreen", "raids_tgl", "lang_tgl", "touch_tgl"]

var new_game_armed := false # first tap arms — the second confirms the overwrite

func shell_act(act: String) -> void:
	if act != "new_game":
		new_game_armed = false # any other row disarms — no stale confirm lingers
	match act:
		"new_game":
			if game.has_save and not new_game_armed:
				new_game_armed = true # a save exists — make the overwrite explicit
				return
			new_game_armed = false
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
		"m_inv":
			game.panel = "inv"; inv_scroll = 0
		"m_dex":
			game.panel = "dex"; dex_scroll = 0
		"m_statues":
			game.panel = "statues"
		"m_guide":
			game.panel = "guide"; guide_page = 0; guide_scroll = 0
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
	var cc: Vector2i = st.get("pos", Vector2i(-1, -1)) if st != null else Vector2i(-1, -1)
	if cc.x < 0 or game.player.pos.distance_to(Vector2(cc.x + 0.5, cc.y + 0.5)) > 5.0:
		game.chest_ref = null
		game.panel = "" # walked too far — the container is out of reach
		return
	if game.net != null and game.net.is_client():
		# the box is the host's truth — ask it to move the goods; our bag
		# catches chest_grant / pays out on chest_took
		if act == "chest_dep":
			var payload := {}
			for iid in game.items.keys(): # mirror the solo deposit rule
				if iid == "gold_coin":
					continue
				if st["id"] == "feed_box" and int(ItemData.ITEMS.get(iid, {}).get("food", 0)) <= 0:
					continue
				var c := int(game.items[iid])
				if c > 0:
					payload[iid] = c
			if payload.is_empty():
				game.log_msg(tr("Nothing stows here"))
				return
			if game.net.pay("chest_dep", payload): # goods leave the bag on the click
				game.net.rpc("chest_req", "dep", float(cc.x), float(cc.y), payload)
		else:
			if st.get("store", {}).is_empty():
				game.log_msg(tr("Nothing to take"))
				return
			game.net.rpc("chest_req", "wd", float(cc.x), float(cc.y), {})
		return
	if act == "chest_dep":
		game.log_msg(tr("Stored %d items") % game.chest_deposit_all(st))
	else:
		game.log_msg(tr("Took %d items") % game.chest_withdraw_all(st))

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
			"furnace", "mill", "crusher", "logging_site", "stone_pit", "gathering_site", "ore_mine", "berry_farm", "wheat_farm", "oil_extractor", "pharmacy", "generator", "ranch", "cooler", "apiary", "fish_trap", "sphere_factory", "sphere_factory_2", "compost_bin", "expedition_post":
				# automated sites: E takes the stockpile — output shouldn't be
				# hostage to a staffed hauler (audit-32). Bag overflow spills
				# to the ground via add_item's own rule. Replica stores are the
				# host's truth — guests get a refusal, never a local drain.
				var sdef: Dictionary = StructureData.STRUCTURES.get(st["id"], {})
				if game.net != null and game.net.is_client():
					game.log_msg(tr("%s — only the keeper handles the stockpile") % tr(str(sdef.get("name", st["id"]))))
					return
				if st.get("store", {}).is_empty():
					game.log_msg(tr("%s: %d workers, nothing stored") % [tr(str(sdef.get("name", st["id"]))), st["workers"].size()])
				else:
					var took := []
					for iid in st["store"].keys():
						took.append("%s x%d" % [tr(str(ItemData.ITEMS.get(str(iid), {}).get("name", iid))), int(st["store"][iid])])
						game.add_item(str(iid), int(st["store"][iid]))
					st["store"].clear()
					game.log_msg(tr("%s: took %s") % [tr(str(sdef.get("name", st["id"]))), ", ".join(took)])
				return
			"feed_box":
				game.chest_ref = st # pals eat out of it; it's still a container
				game.panel = "chest"
				return
			"kin_bed":
				game.log_msg(tr("Kin bed: base kin resting here recover SAN"))
				return
			"kinbox":
				game.panel = "kinbox"
				return
			"straw_bed":
				if game.net != null and game.net.is_client():
					game.net.rpc("sleep_req")
				elif not game.is_night():
					game.log_msg(tr("It's not night yet"))
				else:
					game.sleep_to_morning()
				return
			"waypoint":
				game.use_waypoint()
				return
			"chest":
				if str(st.get("mimic", "")) != "":
					game.open_mimic(st)
					return
				if game.net != null and game.net.is_client():
					var mcc: Vector2i = st.get("pos", Vector2i(-1, -1))
					game.net.rpc("mimic_req", float(mcc.x), float(mcc.y))
					# the trap isn't on the wire — ask the host; if it was
					# a mouth the structure dies and the answer charges us
				game.chest_ref = st
				game.panel = "chest"
				return
			"monitoring_stand":
				if game.net != null and game.net.is_client():
					game.net.rpc("work_req")
				else:
					game.cycle_work_mode()
				return
			"weather_shrine":
				if game.net != null and game.net.is_client():
					if game.item_count("lumenite") >= 3:
						if game.net.pay("shrine", {"lumenite": 3}):
							game.net.rpc("shrine_req")
					else:
						game.log_msg(tr("The shrine wants 3 lumenite"))
				else:
					game.pray_weather()
				return
			"notice_board":
				if game.net != null and game.net.is_client():
					game.net.rpc("board_req") # the shared posting answers host-side
				else:
					game.notice_board_action()
				return
			"kin_gacha":
				if game.net != null and game.net.is_client():
					if game.net.pay("gacha", {"gold_coin": Game.GACHA_COST}):
						game.net.rpc("gacha_req") # the host rolls and ships the egg
				else:
					game.gacha_pull()
				return
			"fossil_bed":
				if game.net != null and game.net.is_client():
					var dc: Vector2i = st.get("pos", Vector2i(-1, -1))
					game.net.rpc("dig_req", float(dc.x), float(dc.y))
				else:
					game.dig_fossil(st)
				return
			"kin_cage":
				if game.net != null and game.net.is_client():
					var kc: Vector2i = st.get("pos", Vector2i(-1, -1))
					game.net.rpc("cage_req", float(kc.x), float(kc.y))
				else:
					game.free_captive(st)
				return
			"kin_condenser":
				if game.net != null and game.net.is_client():
					game.net.rpc("cond_req") # fodder burns host-side, owner-sliced
				else:
					game.condense_active()
				return
			"incubator":
				var inc = st.get("egg_inc")
				if inc is Dictionary:
					var hint: String = game.egg_hint(inc.get("pair"))
					game.log_msg(tr("Incubating %s: %ds left") % [hint if hint != "" else tr("egg"),
						int(maxi(0.0, float(inc.get("ready_t", 0.0)) - game.t))])
				elif game.item_count("kin_egg") > 0 or game.item_count("bred_kin_egg") > 0 \
						or game.item_count("huge_kin_egg") > 0:
					if game.net != null and game.net.is_client():
						var eg := "huge_kin_egg" if game.item_count("huge_kin_egg") > 0 \
							else ("bred_kin_egg" if game.item_count("bred_kin_egg") > 0 else "kin_egg")
						if game.net.pay("egg", {eg: 1}):
							game.net.rpc("egg_req", eg)
					else:
						game.deposit_egg()
				else:
					game.log_msg(tr("Incubator empty - bring a kin egg"))
				return
			"wooden_wall", "spikes":
				game.log_msg(tr("%s (HP %d)") % [tr(str(StructureData.STRUCTURES[st["id"]]["name"])), int(st.get("hp", 0))])
				return
	if game.has_structure("kinbox"):
		game.panel = "kinbox"
		return
	game.log_msg(tr("Nothing to interact with"))

func mouse_tile() -> Vector2:
	var m := get_global_mouse_position()
	var c: Camera2D = get_viewport().get_camera_2d()
	var w := (m - get_viewport_rect().size / 2) / c.zoom.x + c.global_position
	return Iso.from_screen(w.x, w.y, game.player.elev())

func _build_tap_ok(p: Vector2) -> bool:
	# while the build bar owns the screen the only live touch control is the
	# ✕ — guarding the whole zone table made a third of the slab unplaceable
	if not game.touch_ui:
		return true
	var lay0 := touch_layout(get_viewport_rect().size)
	return p.distance_to(lay0["btns"]["menu"]) > btn_r("menu")

func place_ghost() -> void:
	var tw := mouse_tile()
	var bl := game.buildable_list()
	if build_sel >= bl.size(): # list shrank since the bar was drawn
		build_sel = maxi(0, bl.size() - 1)
		return
	var pick: String = bl[build_sel]
	if pick != build_sel_sid: # a net_unlocked swap can reorder the list
		# without touching the index — don't plant a different building (audit-59)
		build_sel_sid = pick
		return
	game.place_structure(pick, int(tw.x), int(tw.y))

func w2s(p: Vector2) -> Vector2:
	var c: Camera2D = get_viewport().get_camera_2d()
	return (p - c.global_position) * c.zoom.x + get_viewport_rect().size / 2

func wtext(p: Vector2, s: String, col: Color, size := 13) -> void:
	# world-space text: ink underlay keeps bright type readable on any tile
	draw_string(font, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(Ink.INK.r, Ink.INK.g, Ink.INK.b, col.a * 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func draw_floaters() -> void:
	# combat/loot feedback as paper field-tags — they were queued but never
	# rendered, so every catch/damage tick was invisible until now
	for f in game.floaters:
		var p: Vector2 = f["p"]
		var e := 0
		if p.x >= 0 and p.y >= 0 and p.x < game.world.WORLD_W and p.y < game.world.WORLD_H:
			e = game.world.elev_at(int(p.x), int(p.y))
		var sc := w2s(Iso.to_screen(p.x, p.y, e))
		sc.y -= 22 + f["age"] * 26.0
		var a := clampf(1.5 - f["age"], 0.0, 1.0)
		var txt: String = f["t"]
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var rr := Rect2(sc.x - tw / 2 - 5, sc.y - 11, tw + 10, 15)
		Ink.tag(self, rr, a)
		var fc := Color(str(f["c"]))
		if (fc.r + fc.g + fc.b) / 3.0 > 0.62: # cream/gold on cream — pull to readable
			fc = fc.darkened(0.45)
		draw_string(font, rr.position + Vector2(5, 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(fc.r, fc.g, fc.b, a))

func _draw() -> void:
	if not game or not game.player:
		return
	click_rects = []
	var pl := game.player
	var r := get_viewport_rect().size
	Ink.tag(self, Rect2(12, 10, 224, 18))
	draw_rect(Rect2(14, 12, int(220 * clampf(pl.hp / pl.max_hp, 0, 1)), 14), Ink.GREEN)
	Ink.tag(self, Rect2(12, 30, 224, 6))
	var hc: Color = Ink.GOLD if pl.hunger >= 25 else Ink.RED
	draw_rect(Rect2(14, 31, int(220 * clampf(pl.hunger / 100.0, 0, 1)), 4), hc)
	# the island SP bar under the hunger sliver — sprints and swims burn it
	Ink.tag(self, Rect2(12, 37, 224, 5))
	var spc: Color = Ink.TEAL if pl.stamina > 15.0 else Ink.RED
	draw_rect(Rect2(14, 38, int(220 * clampf(pl.stamina / 100.0, 0, 1)), 3), spc)
	draw_string(font, Vector2(16, 25), tr("HP %d/%d  Lv%d  XP%d") % [int(pl.hp), int(pl.max_hp), pl.level, pl.xp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.INK)
	var tiers := game.sphere_tiers()
	var sx := 12
	for id in ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"]:
		var n := game.item_count(id)
		if n <= 0:
			continue
		var sel := tiers.find(id) == pl.sphere_sel
		Ink.tag(self, Rect2(sx, 44, 78, 20))
		if sel:
			draw_rect(Rect2(sx, 44, 78, 20), Ink.ORANGE, false, 1.5)
		draw_string(font, Vector2(sx + 4, 59), tr("%s x%d") % [tr(str(ItemData.ITEMS[id]["name"])).left(7), n],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK)
		sx += 82
	draw_equipment_line() # gear row under the orb chips
	if pl.meal_t > 0.0 and not pl.meal_buff.is_empty(): # the island meal timer chip
		var btxt := ""
		for bk in pl.meal_buff:
			btxt += "%s+%d%% " % [tr(str(bk.to_upper())), int(float(pl.meal_buff[bk]) * 100)]
		Ink.tag(self, Rect2(240, 24, 112, 16))
		draw_string(font, Vector2(244, 36), tr("%s %d:%02d") % [btxt.strip_edges(), int(pl.meal_t) / 60, int(pl.meal_t) % 60],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD)
	if pl.aiming:
		wtext(Vector2(12, 96), tr("AIM — tap a kin to throw") if game.touch_ui else tr("AIM — click a kin to throw (Q cancel)"),
			Ink.TEAL)
		# the island throw preview: hovering a wild kin shows the catch odds
		var tiers2 := game.sphere_tiers()
		if not tiers2.is_empty():
			var sid2: String = tiers2[clampi(pl.sphere_sel, 0, tiers2.size() - 1)]
			var bp2: Kin = null
			if game.touch_ui: # no hover under a thumb — preview the facing-line target
				var bd2t := 0.6 # mirror throw_sphere's pick: best dot, d in [0.4, 5]
				var fv := pl.facing.normalized() if pl.facing.length() > 0.01 else Vector2.RIGHT
				for q in game.pals:
					if q.mode != "wild" or q.hp <= 0:
						continue
					var dq := q.pos.distance_to(pl.pos)
					if dq > 5.0 or dq < 0.4:
						continue
					var dt2: float = (q.pos - pl.pos).normalized().dot(fv)
					if dt2 > bd2t:
						bd2t = dt2
						bp2 = q
			else:
				var mp2 := get_global_mouse_position()
				var tw2: Vector2 = Iso.from_screen(mp2.x, mp2.y, pl.elev())
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
					wtext(Vector2(12, 112), tr("✦ %s Lv%d — a legend: orbs bounce off") % [tr(str(bp2.spec["name"])), bp2.level],
						Ink.GOLD)
				else:
					var cap_pow2: float = game.cap_power_of(bp2)
					var ch := minf(0.97, Combat.catch_chance(maxf(0.0, bp2.hp) / bp2.max_hp, cap_pow2,
						ItemData.ITEMS[sid2].get("spherePower", 26), bp2.any_status(), false, pl.capture_level))
					var col := Ink.GREEN if ch >= 0.5 else (Ink.ORANGE if ch >= 0.2 else Ink.RED)
					wtext(Vector2(12, 112), tr("Catch %s Lv%d: %d%%") % [tr(str(bp2.spec["name"])), bp2.level, int(ch * 100)], col)
	Ink.tag(self, Rect2(r.x - 140, 10, 128, 20))
	var wicon := "  ⚡" if game.weather == "storm" else ("  ☂" if game.weather == "rain" else ("  ☀" if game.weather == "drought" else ""))
	var wcol := Ink.VIOLET if game.weather == "storm" else (Ink.TEAL if game.weather == "rain" else (Ink.GOLD if game.weather == "drought" else Ink.INK))
	draw_string(font, Vector2(r.x - 132, 25), tr("Day %d  %02d:00%s") % [game.day, int(game.tod), wicon],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, wcol)
	# 4Hz memo — the boss/den O(pals) scans, tr() formats, and the string-trim
	# shaping loops all ran per frame here (audit-45). Rebuilt on a tick;
	# drawn every frame from the cache below.
	if game.t - _memo_t > 0.25:
		_memo_t = game.t
		_memo_boss = null
		var bd := 18.0
		for q in game.pals:
			if q.hp <= 0 or not (q.boss or q.alpha):
				continue
			if q.mode == "box" or q.mode == "partner":
				continue
			var dd: float = q.pos.distance_to(game.player.pos)
			if dd < bd:
				bd = dd; _memo_boss = q
		_memo_den = ""
		if game.crowned:
			for q in game.pals:
				if is_instance_valid(q) and q.mode == "wild" and q.species_id in Game.LEGENDARY_DEN:
					_memo_den = tr(" · warden up") if q.boss else tr(" · heir roams")
					break
		_memo_raid_txt = ""
		if game.raid_t < 30.0:
			_memo_raid_txt = tr("RAID IN %ds") % int(ceilf(game.raid_t))
		_memo_mission_txt = ""
		if game.mission_idx < game.MISSIONS.size():
			var mt: String = tr("★ %s") % tr(str(game.MISSIONS[game.mission_idx]["text"]))
			while mt.length() > 4 and font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > 202.0:
				mt = mt.left(mt.length() - 2) # same column contract as the hints below
			_memo_mission_txt = mt
		_memo_hints.clear()
		var hkey: String = "touch" if game.touch_ui else ("pad" if game.using_pad else "")
		for h in game.active_hints():
			var htxt: String = tr("» ") + tr(str(h.get(hkey, h["text"])) if hkey != "" else str(h["text"]))
			while htxt.length() > 4 and font.get_string_size(htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > 200.0:
				htxt = htxt.left(htxt.length() - 2) # clip to the column — unbounded text ran off the screen edge
			_memo_hints.append(htxt)
	if game.raid_t < 30.0 and game.kinbox_pos.x >= 0 and _memo_raid_txt != "": # the island raid horn
		var raid_r := Rect2(r.x / 2 - 80, 8, 160, 22)
		draw_rect(raid_r, Color(Ink.RED, 0.85))
		draw_rect(raid_r, Ink.INK, false, 1.5)
		draw_string(font, Vector2(r.x / 2 - 62, 24), _memo_raid_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.PAPER)
	# boss bar: nearest alpha/boss in the fray gets a name + hp strip
	var boss: Kin = _memo_boss if is_instance_valid(_memo_boss) else null
	if boss:
		var frac: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		var bw := 240.0
		draw_rect(Rect2(r.x / 2 - bw / 2, 34, bw, 16), Color(Ink.INK, 0.65))
		draw_rect(Rect2(r.x / 2 - bw / 2 + 1, 35, (bw - 2) * frac, 14),
			Ink.RED if boss.boss else Ink.ORANGE)
		draw_portrait(Vector2(r.x / 2 - bw / 2 - 26, 32), boss.species_id, 24.0, 19.0)
		draw_string(font, Vector2(r.x / 2 - bw / 2 + 4, 47),
			tr("%s %s Lv%d%s") % [tr("BOSS") if boss.boss else "α", tr(str(boss.spec["name"])), boss.level,
				tr(" ☠%dg") % boss.bounty if boss.bounty > 0 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.PAPER)
	if _memo_mission_txt != "": # the island guide rope
		Ink.tag(self, Rect2(r.x - 220, 32, 208, 18))
		draw_string(font, Vector2(r.x - 214, 45), _memo_mission_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.GOLD)
	var hy := 62.0
	for htxt in _memo_hints: # contextual nudges — retire themselves
		Ink.tag(self, Rect2(r.x - 216, hy - 11, 208, 15))
		draw_string(font, Vector2(r.x - 212, hy), htxt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK)
		hy += 17
	var spire_n: int = game.net_spires if game.net != null and game.net.is_client() \
		else game.spires_done.size() # a guest's tally mirrors the host's ledger
	if spire_n > 0 or game.crowned: # the campaign spine's tally
		Ink.tag(self, Rect2(r.x - 230, hy - 11, 222, 15))
		draw_string(font, Vector2(r.x - 226, hy),
			tr("SPIRES %d/%d") % [spire_n, game.SPIRE_DEFS.size()]
				+ (tr(" — CROWNED") if game.crowned else ""),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD)
		hy += 17
	# post-crown purpose: the den keeps calling catchable heirs — surface
	# the collection count and whether one roams right now, or the chase
	# dies at "CROWNED" with no next step
	if game.crowned:
		var legs := game.net_den if game.net != null and game.net.is_client() \
			else game.den_caught() # a guest's tally is the host's ledger
		var den := _memo_den # the O(pals) roam scan is memoized at 4Hz above
		if den == "":
			var soon := -1.0
			for br in game.boss_respawns:
				if str(br.get("sid", "")) in Game.LEGENDARY_DEN:
					var eta: float = float(br.get("at", 0.0)) - game.t
					if soon < 0.0 or eta < soon:
						soon = eta
			if soon >= 0.0:
				den = tr(" · stirs ~%dh") % maxi(1, int(soon / Game.DAY_LEN * 24.0))
		Ink.tag(self, Rect2(r.x - 230, hy - 11, 222, 15))
		if game.accord:
			draw_string(font, Vector2(r.x - 226, hy),
				tr("ACCORD SEALED ✦"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD)
		else:
			draw_string(font, Vector2(r.x - 226, hy),
				tr("DEN %d/%d") % [legs, Game.LEGENDARY_DEN.size()] + den,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD)
	var my := r.y - 24
	for i in range(game.messages.size()):
		var m: String = game.messages[game.messages.size() - 1 - i]
		wtext(Vector2(14, my - i * 18), m, Color(1, 1, 1, 0.85))
	var py := 38
	for pr in party_rows(): # ● out / ○ in its ball — the island fields one
		Ink.tag(self, Rect2(r.x - 150, py, 138, 16))
		draw_portrait(Vector2(r.x - 172, py), str(pr.get("sid", "")))
		var tag := "!" if pr["stance"] == "aggressive" else ("." if pr["stance"] == "passive" else "")
		draw_string(font, Vector2(r.x - 144, py + 13), tr("%s Lv%d %s%s") % [tr(str(pr["name"])), pr["lv"],
			"●" if pr["out"] else "○", tag], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK)
		py += 18
	# the island partner-skill readout: name + cooldown under the party strip
	var psk_p := game.party_pal()
	if psk_p != null and game.PARTNER_SKILLS.has(psk_p.species_id):
		var cd_left: float = float(psk_p.skill_cd.get("partner", 0.0)) - game.t
		Ink.tag(self, Rect2(r.x - 150, py, 138, 16))
		draw_string(font, Vector2(r.x - 144, py + 13),
			tr("%s %s") % [tr(str(game.PARTNER_SKILLS[psk_p.species_id]["name"])),
				tr("READY") if cd_left <= 0 else tr("%ds") % ceili(cd_left)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Ink.GOLD if cd_left <= 0 else Ink.INK_SOFT)
	# build ghost preview
	var blx: Array = game.buildable_list() if game.panel == "build" else []
	if build_sel >= 0 and build_sel < blx.size():
		var tw := mouse_tile()
		var sid: String = blx[build_sel]
		var s: Dictionary = StructureData.STRUCTURES[sid]
		var w: int = s.get("w", 2)
		var h: int = s.get("h", 2)
		var ok := game.can_place(sid, int(tw.x), int(tw.y))
		var col := Color(Ink.GREEN, 0.45) if ok else Color(Ink.RED, 0.45)
		if _dia_line.is_empty(): # one template, translated per cell — the ghost
			# loop used to allocate two arrays × w×h × frame (audit-59)
			_dia_line = PackedVector2Array([Vector2(0, -16), Vector2(32, 0),
				Vector2(0, 16), Vector2(-32, 0), Vector2(0, -16)])
			_dia_poly = PackedVector2Array([Vector2(0, -16), Vector2(32, 0),
				Vector2(0, 16), Vector2(-32, 0)])
		for dy in range(h):
			for dx in range(w):
				var e: int = game.world.elev_at(int(tw.x) + dx, int(tw.y) + dy)
				var pc := Iso.to_screen(int(tw.x) + dx + 0.5, int(tw.y) + dy + 0.5, e)
				draw_set_transform(w2s(pc))
				draw_polyline(_dia_line, Ink.INK, 1.5)
				draw_colored_polygon(_dia_poly, col)
		draw_set_transform(Vector2.ZERO)
		# ghost sprite — the same anchor math place_structure uses, tinted
		# by placeability so the player sees what actually lands
		var gt := struct_tex(sid)
		if gt != null:
			var ge: int = game.world.elev_at(int(tw.x), int(tw.y))
			var gp := Iso.to_screen(int(tw.x) + w * 0.5, int(tw.y) + h * 0.5, ge)
			var gs := w2s(gp)
			draw_texture_rect(gt, Rect2( # Sprite2D centers the texture — the
				# rect's top edge sits a full height up, not half (audit-59)
				gs + Vector2(-gt.get_width() * 0.5, -gt.get_height() + 8),
				Vector2(gt.get_width(), gt.get_height())), false,
				Color(0.5, 1.0, 0.6, 0.55) if ok else Color(1.0, 0.45, 0.4, 0.55))
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
			tr("MOVE wasd/arrows  SPRINT shift  DODGE space"),
			tr("MELEE/CHOP lmb  AIM q  THROW lmb  BALL tab"),
			tr("BUILD b (1-9 pick, lmb place, rmb cancel)  INV i  TECH t"),
			tr("INTERACT e (workbench=craft, kinbox=manage)  ASSIGN f  HELP h"),
			tr("MAP m    DEMOLISH x (under cursor)  RIDE r  KIN-SKILL g  STATUES u  KINDEX p  CHAT enter"),
			tr("1-%d sends that party kin out (press again to recall) — one ball on the field") % game.party_cap(),
			tr("v cycles the field kin's orders: auto / aggressive / passive"),
			tr("HOST j   JOIN k (type host IP, enter)  MERCHANT e   F1 save / F4 reload(armed)"),
			tr("GUIDE n — the field manual"),
			tr("GLIDER descends cliffs. Sick kin need medicine."),
		]
		if game.using_pad:
			lines.append(tr("PAD  dpad: up=bag right=ride left=kin-skill down=map   L3 demolish   R3 swap kin"))
		Ink.card(self, Rect2(10, r.y - 30 - lines.size() * 17, 580, lines.size() * 17 + 22))
		for i in range(lines.size()):
			draw_string(font, Vector2(20, r.y - 18 - (lines.size() - i) * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.INK)

	# minimap (M): baked world image + live player/kinbox markers

	if map_show and map_img != null:
		var vw := get_viewport_rect().size.x
		var ms := 176.0
		var mr := Rect2(vw - ms - 10, 10, ms, ms)
		Ink.tag(self, mr.grow(2))
		if map_tex != null:
			draw_texture_rect(map_tex, mr, false)
		fog_t -= 0.016 # draw runs per-frame; poll ~2x a second, bake only on new reveals
		if fog_t <= 0.0:
			fog_t = 0.5
			if game.explored_n != _fog_seen:
				bake_fog() # 48k set_pixel + a GPU upload is real work on a phone — only when the fog changed
		if fog_tex != null:
			draw_texture_rect(fog_tex, mr, false)
		var plp := game.player.pos
		var pp := mr.position + Vector2(plp.x / game.world.WORLD_W * ms, plp.y / game.world.WORLD_H * ms)
		draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), Ink.ORANGE)
		if game.kinbox_pos.x >= 0:
			var pb := mr.position + Vector2(game.kinbox_pos.x / float(game.world.WORLD_W) * ms, game.kinbox_pos.y / float(game.world.WORLD_H) * ms)
			draw_rect(Rect2(pb - Vector2(2, 2), Vector2(4, 4)), Ink.TEAL)
		for dm in game.death_marks: # the island tombstones — guide the corpse run
			var dp := mr.position + Vector2(dm.x / game.world.WORLD_W * ms, dm.y / game.world.WORLD_H * ms)
			draw_rect(Rect2(dp - Vector2(2, 2), Vector2(4, 4)), Ink.RED)
		if game.treasure: # the surveyor's X — follow it and dig
			var tp := mr.position + Vector2(game.treasure["pos"].x / game.world.WORLD_W * ms, game.treasure["pos"].y / game.world.WORLD_H * ms)
			draw_rect(Rect2(tp - Vector2(3, 3), Vector2(6, 6)), Ink.GOLD)
		for stk in game.spire_pos: # pact spires ping once their ground is charted
			var spos: Vector2i = game.spire_pos[stk]
			if spos.y * game.world.WORLD_W + spos.x >= game.explored.size() \
					or game.explored[spos.y * game.world.WORLD_W + spos.x] == 0:
				continue
			var spp := mr.position + Vector2(spos.x / float(game.world.WORLD_W) * ms, spos.y / float(game.world.WORLD_H) * ms)
			if game.spires_done.has(stk):
				draw_rect(Rect2(spp - Vector2(3, 3), Vector2(6, 6)), Ink.VIOLET, false, 1.0)
			else:
				draw_rect(Rect2(spp - Vector2(3, 3), Vector2(6, 6)), Ink.VIOLET)

	draw_floaters()
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
		draw_rect(msel, Ink.ORANGE, false, 2.0) # pad/arrow-key cursor
		draw_string(font, Vector2(msel.position.x - 16, msel.position.y + 20), "»",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.ORANGE)

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
		"roll": Vector2(r.x - 66, r.y - 178), # clear of ATK's hit disc — fat-finger arcs need 79px
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
const MORE_BTN_R := 19.0 # drawn AND hit-tested smaller — 56px spacing can't take BTN_R+8
const BTN_LABELS := {"atk": "ATK", "aim": "AIM", "roll": "ROLL", "e": "E", "orb": "ORB",
	"inv": "INV", "bld": "BLD", "more": "···", "menu": "≡",
	"asg": "ASG", "stn": "STN", "ksk": "KSK", "rde": "RDE", "dml": "DML", "map": "MAP"}
var touch_more := false

func joy_grab_r() -> float: return JOY_R * 1.7 # one radius table — touch_down AND zone gate share it

func btn_r(b: String) -> float:
	if b in MORE_VERBS: return MORE_BTN_R + 8.0 # 27 < 28 half-spacing — no edge bleed
	return (36.0 if b == "atk" else BTN_R) + 8.0

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
	if game.state != "play" and game.panel == "":
		return # verbs sleep under the shell; only the ✕ works in a panel
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

func _demolish_verb(tw: Vector2) -> void: # one reach contract for cursor AND slab
	if game.player.pos.distance_to(tw + Vector2(0.5, 0.5)) > game.DEMOLISH_REACH:
		game.log_msg(tr("Too far to demolish"))
		return
	game.demolish_at(tw)

func _touch_demolish() -> void: # no cursor on a slab — raze the nearest structure
	var pt := game.player.pos
	var bt := Vector2i.ZERO; var bd := game.DEMOLISH_REACH
	for k in game.structures:
		var dd: float = pt.distance_to(Vector2(k.x + 0.5, k.y + 0.5))
		if dd < bd:
			bd = dd; bt = k
	if bd < game.DEMOLISH_REACH:
		game.demolish_at(bt)
	else:
		game.log_msg(tr("Nothing close enough to demolish"))

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
			build_sel_sid = ""
			build_scroll = 0 # same reset the keybind path applies
		"roll":
			pl.dodge()
		"atk":
			if pl.statuses.get("sleep", 0) > game.t:
				return
			if pl.aiming:
				pl.throw_sphere(true)
			else:
				pl.melee()

func draw_touch(r: Vector2) -> void:
	if not game.touch_ui:
		return
	var lay := touch_layout(r)
	if game.panel != "":
		# panels own the taps — but ☰ stays up as ✕, the slab's only way out
		var c: Vector2 = lay["btns"]["menu"]
		click_rects.append({"rect": Rect2(c - Vector2(btn_r("menu"), btn_r("menu")),
			Vector2(btn_r("menu"), btn_r("menu")) * 2.0), "act": "x_close", "arg": null})
		draw_circle(c, BTN_R, Color(Ink.RED, 0.14))
		draw_arc(c, BTN_R, 0, TAU, 24, Color(Ink.RED, 0.5), 1.5)
		draw_string(font, c - Vector2(font.get_string_size("X", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2, -5), "X",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ink.RED, 0.85))
		return
	if game.state != "play":
		return
	var jc: Vector2 = lay["joy"]
	draw_circle(jc, JOY_R, Color(Ink.PAPER, 0.10))
	draw_arc(jc, JOY_R, 0, TAU, 24, Color(Ink.PAPER, 0.35), 1.5)
	var knob := jc + game.player.touch_vec * (JOY_R * 0.55)
	draw_circle(knob, 20, Color(Ink.TEAL, 0.6))
	for b in lay["btns"]:
		var c: Vector2 = lay["btns"][b]
		var rad := 36.0 if b == "atk" else BTN_R
		draw_circle(c, rad, Color(Ink.PAPER, 0.10))
		draw_arc(c, rad, 0, TAU, 24, Color(Ink.PAPER, 0.4), 1.5)
		var tl: String = tr(BTN_LABELS[b])
		draw_string(font, c - Vector2(font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2, -5), tl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ink.PAPER, 0.8))
	if touch_more:
		for b in lay["more_row"]:
			var c2: Vector2 = lay["more_row"][b]
			draw_circle(c2, MORE_BTN_R, Color(Ink.GOLD, 0.14))
			draw_arc(c2, MORE_BTN_R, 0, TAU, 24, Color(Ink.GOLD, 0.45), 1.5)
			var tl2: String = tr(BTN_LABELS[b])
			draw_string(font, c2 - Vector2(font.get_string_size(tl2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2, -4), tl2,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Ink.GOLD, 0.85))

func menu_row(cx: float, y: float, w: float, label: String, act: String, col: Color = Color.WHITE) -> float:
	var rr := Rect2(cx - w / 2, y, w, 30)
	var hov := (game.state != "play" or game.panel != "") and click_rects.size() == menu_sel # cursor row glows
	Ink.tag(self, rr, 1.0, Ink.PAPER_DARK if hov else Ink.PAPER)
	if hov:
		draw_rect(Rect2(rr.position + Vector2(3, 4), Vector2(3, 22)), Ink.ORANGE) # cursor tick — the eye finds the live row before the border
	click_rects.append({"rect": rr, "act": act, "arg": null})
	var tl := tr(label)
	var tc := Ink.INK if col == Color.WHITE else Ink.RED # pale red = the quit row
	var fs := 14
	var tw := font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > w - 14: # long labels shrink to fit the tag instead of spilling onto dark world
		fs = maxi(11, int(floor(fs * (w - 14.0) / tw)))
		tw = font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(cx - tw / 2, y + 20), tl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	return y + 40

func draw_weather_fx(r: Vector2) -> void:
	# screen-space weather reads better than a status glyph alone; all the
	# drops are deterministic lanes driven by game.t, not random allocation
	var t := game.t
	if game.weather == "rain" or game.weather == "storm":
		var drops := 56 if game.weather == "storm" else 40
		var speed := 180.0 if game.weather == "storm" else 120.0
		var rain_col := Color(Ink.LILAC, 0.34 if game.weather == "storm" else 0.24) # ink-lilac rain, not neon blue
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
	# procedural morning over the Wildmere — a printed travel poster: flat
	# sky bands, a sun with a dotted halo, an ink ridge. All motion runs off
	# game.t: same seeds, same frame, on any machine.
	var t := game.t
	var sky_top := Color(0.75, 0.90, 0.93)  # pale cyan field
	var sky_bot := Color(0.55, 0.82, 0.89)  # #8fd3e6
	for i in 16:
		draw_rect(Rect2(0, r.y * i / 16.0, r.x, r.y / 16.0 + 1.0), sky_top.lerp(sky_bot, i / 15.0))
	var sun := Vector2(r.x * 0.72, r.y * 0.28)
	for i in 22: # the COO halo: rings of ink dots, never a glow
		var a := i * TAU / 22.0
		draw_circle(sun + Vector2(cos(a), sin(a)) * 64.0, 2.8, Ink.ORANGE)
	for i in 12:
		var a2 := i * TAU / 12.0 + 0.26
		draw_circle(sun + Vector2(cos(a2), sin(a2)) * 52.0, 1.6, Ink.GOLD)
	draw_circle(sun, 46.0, Ink.PAPER.lerp(Ink.GOLD, 0.3))
	draw_arc(sun, 46.0, 0, TAU, 48, Ink.INK, 2.0)
	draw_circle(sun + Vector2(-13, -12), 16.0, Ink.GOLD) # cel shade on the disc
	draw_circle(sun + Vector2(14, 14), 12.0, Ink.PAPER.lerp(Ink.GOLD, 0.5))
	for c in 5: # paper clouds — flat blobs with an ink lip, each on its own slow lane
		var cxx := fposmod(r.x * (0.08 + c * 0.23) + t * (4.0 + c * 1.3), r.x + 160.0) - 80.0
		var cyy := r.y * (0.10 + c * 0.055)
		for b in 3:
			var cp := Vector2(cxx + b * 26.0, cyy - absf(b - 1) * 8.0)
			var cr := 22.0 - absf(b - 1) * 6.0
			draw_circle(cp, cr, Ink.PAPER)
			draw_arc(cp, cr, PI * 0.9, PI * 2.1, 20, Ink.INK, 1.2) # ink lip on the lit edge only
	var sea_y := r.y * 0.68
	draw_rect(Rect2(0, sea_y, r.x, r.y - sea_y), Color(0.16, 0.32, 0.42))
	Ink.dots(self, Rect2(0, sea_y, r.x, r.y - sea_y), 0.14) # halftone swell on the water
	for g in 9: # sun path on the water — flat gold strokes
		var gw := 60.0 - g * 6.0
		draw_rect(Rect2(sun.x - gw / 2, sea_y + g * 14.0, gw, 3.0), Color(Ink.GOLD, 0.22 - g * 0.015))
	draw_polygon(PackedVector2Array([Vector2(0, sea_y), Vector2(r.x * 0.18, sea_y - 46),
		Vector2(r.x * 0.34, sea_y - 20), Vector2(r.x * 0.52, sea_y - 64),
		Vector2(r.x * 0.7, sea_y - 30), Vector2(r.x, sea_y - 56), Vector2(r.x, sea_y)]),
		PackedColorArray([Ink.EDGE])) # the island ridge the whole game happens on
	for tri in 14: # tree spikes — cheap silhouette, reads as forest at a glance
		var tx := r.x * (0.06 + tri * 0.068)
		var th := 14.0 + sin(tri * 7.0) * 8.0
		var ty := sea_y - 8.0 - 30.0 * maxf(0.0, sin(tri * 1.7))
		draw_colored_polygon(PackedVector2Array([Vector2(tx, ty - th), Vector2(tx - 7, ty), Vector2(tx + 7, ty)]),
			Ink.INK)
	for m in 18: # motes drifting up off the water
		var mx := fposmod(m * 137.0 + t * 6.0, r.x)
		var my := r.y * 0.15 + fposmod(m * 89.0 + t * 3.0, r.y * 0.5)
		draw_circle(Vector2(mx, my), 1.2, Color(Ink.PAPER, 0.55))
	draw_rect(Rect2(Vector2.ZERO, r), Color(Ink.INK, 0.30)) # vignette — menu contrast over the scene

func draw_title(r: Vector2) -> void:
	draw_title_sky(r)
	var cx := r.x / 2
	var ty := r.y * 0.22
	var brand := tr("Kinbound").to_upper() # the logo rides the locale table like everything else
	var bw := font.get_string_size(brand, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	draw_string(font, Vector2(cx - bw / 2 + 3, ty + 4), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Ink.INK) # hard offset shadow
	draw_string(font, Vector2(cx - bw / 2 - 1.5, ty - 1.5), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(Ink.RED, 0.5)) # misregistered plate
	draw_string(font, Vector2(cx - bw / 2, ty), brand,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Ink.PAPER)
	draw_rect(Rect2(cx - bw / 2, ty + 12, bw, 3), Ink.ORANGE) # the signal rule under the wordmark
	for orb in [-1, 1]: # the orb motif flanking the mark — the game's own sigil
		var ox: float = cx + orb * (bw / 2 + 34.0)
		draw_circle(Vector2(ox, ty - 16), 10, Ink.GOLD)
		draw_arc(Vector2(ox, ty - 16), 10, 0, TAU, 24, Ink.INK, 1.5)
		draw_circle(Vector2(ox, ty - 16), 6, Ink.INK)
		draw_circle(Vector2(ox - 2, ty - 19), 2, Ink.PAPER)
	var tagline := tr("the Wildmere keeps what you catch")
	wtext(Vector2(cx - font.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2, ty + 34), tagline,
		Ink.PAPER) # baseline clears the wordmark's underline (draw_string y = baseline)
	var y := r.y * 0.42
	for row in title_rows():
		y = menu_row(cx, y, 220, row[0], row[1], row[2])
	draw_string(font, Vector2(14, r.y - 12),
		tr("enter = continue · click a row") if game.has_save else tr("enter = new game · click a row"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ink.PAPER, 0.6))

func title_rows() -> Array: # the title menu's rows as data — pad nav and smoke both read this
	var rows := []
	if game.has_save:
		rows.append(["CONTINUE", "continue", Color.WHITE])
	rows.append(["OVERWRITE the save?" if new_game_armed else "NEW GAME",
		"new_game", Color(0.95, 0.55, 0.5) if new_game_armed else Color.WHITE])
	if game.net != null and multiplayer.multiplayer_peer == null:
		rows.append(["JOIN SESSION", "m_join", Color.WHITE]) # co-op straight from boot
	rows.append(["SETTINGS", "m_settings", Color.WHITE])
	if not OS.has_feature("web"): # quit() on web just freezes the canvas
		rows.append(["QUIT", "quit", Color(0.85, 0.6, 0.6)])
	return rows

func draw_pause(r: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, r), Color(Ink.INK, 0.55))
	var cx := r.x / 2
	var ptxt := tr("MENU — the world keeps running") if game.net_live() else tr("PAUSED")
	var pw := font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(font, Vector2(cx - pw / 2 + 2, r.y * 0.3 + 2), ptxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Ink.INK)
	draw_string(font, Vector2(cx - pw / 2, r.y * 0.3), ptxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Ink.PAPER)
	draw_rect(Rect2(cx - pw / 2, r.y * 0.3 + 14, pw, 2), Ink.ORANGE) # signal rule clears 40px descenders
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
	var rows := [["RESUME", "resume"], ["SAVE GAME", "m_save"], ["SETTINGS", "m_settings"],
		["INVENTORY", "m_inv"]] # pad/touch reach the bag through the pause shell too
	if game.net != null and multiplayer.multiplayer_peer == null:
		rows.append(["JOIN SESSION", "m_join"])
		rows.append(["HOST SESSION", "m_host"])
	if game.net_live():
		rows.append(["CHAT", "m_chat"])
	if game.net == null or not game.net.is_client():
		rows.append(["TECH TREE", "m_tech"]) # research is host business — guests get a dead panel otherwise
	rows.append(["KINDEX", "m_dex"])
	rows.append(["STATUES", "m_statues"])
	rows.append(["GUIDE", "m_guide"])
	rows.append(["SAVE & QUIT TO TITLE", "to_title"])
	if not OS.has_feature("web"): # same freeze trap as the title quit
		rows.append(["SAVE & QUIT GAME", "quit", Color(0.85, 0.6, 0.6)])
	return rows

func draw_settings(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 190, r.y * 0.25, 380, 300)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 26)), tr("SETTINGS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Ink.GOLD)
	var y := rr.position.y + 54
	for b in [["master", "MASTER"], ["music", "MUSIC"], ["sfx", "SFX"]]:
		var v: float = game.settings[b[0]]
		draw_string(font, Vector2(rr.position.x + 24, y + 14), tr("%s  %d%%") % [tr(b[1]), int(v * 100)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.INK)
		draw_rect(Rect2(rr.position.x + 140, y + 4, 150, 14), Ink.PAPER_DARK)
		draw_rect(Rect2(rr.position.x + 140, y + 4, 150, 14), Ink.INK_SOFT, false, 1.0)
		draw_rect(Rect2(rr.position.x + 140, y + 4, 150.0 * v, 14), Ink.TEAL)
		var mr1 := Rect2(rr.position.x + 296, y, 28, 22)
		var mr2 := Rect2(rr.position.x + 330, y, 28, 22)
		click_rects.append({"rect": mr1, "act": "vol_%s_m" % b[0], "arg": null})
		click_rects.append({"rect": mr2, "act": "vol_%s_p" % b[0], "arg": null})
		draw_string(font, mr1.position + Vector2(9, 16), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.INK)
		draw_string(font, mr2.position + Vector2(8, 16), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.INK)
		y += 38
	y += 8
	var fs := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": fs, "act": "fullscreen", "arg": null})
	draw_string(font, Vector2(fs.position.x, fs.position.y + 18), tr("%s  [%s]") % [tr("FULLSCREEN"), tr("ON") if game.settings["fullscreen"] else tr("off")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN if game.settings["fullscreen"] else Ink.INK)
	y += 32
	var rd := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": rd, "act": "raids_tgl", "arg": null})
	draw_string(font, Vector2(rd.position.x, rd.position.y + 18), tr("%s  [%s]") % [tr("BASE RAIDS"), tr("ON") if game.settings["raids"] else tr("off")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN if game.settings["raids"] else Ink.INK_SOFT)
	y += 32
	var lg := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": lg, "act": "lang_tgl", "arg": null})
	draw_string(font, Vector2(lg.position.x, lg.position.y + 18), tr("%s  [%s]") % [tr("LANGUAGE"), "中文" if game.settings.get("lang", "en") == "zh" else "EN"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.INK)
	y += 32
	var tg := Rect2(rr.position.x + 24, y, 200, 26)
	click_rects.append({"rect": tg, "act": "touch_tgl", "arg": null})
	draw_string(font, Vector2(tg.position.x, tg.position.y + 18), tr("%s  [%s]") % [tr("TOUCH CONTROLS"), tr(str(game.settings.get("touch", "auto")).to_upper())],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN if game.touch_ui else Ink.INK_SOFT)
	y += 44
	var bk := Rect2(rr.position.x + 24, y, 120, 28)
	click_rects.append({"rect": bk, "act": "set_back", "arg": null})
	draw_string(font, Vector2(bk.position.x + 8, bk.position.y + 19), tr("[ %s ]") % tr("BACK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.TEAL)

func draw_build_bar(r: Vector2) -> void:
	var lst := game.buildable_list()
	var bx := 10.0
	var by := r.y - 200.0
	Ink.card(self, Rect2(bx, by, 620, 56), Ink.PAPER, 0.0, 3.0)
	# 9 slots per page; scroll/wheel pages through the whole unlock list —
	# before paging existed, unlocks past index 9 were unreachable
	var pages := maxi(1, int(ceil(lst.size() / 9.0)))
	# snap to page edges — a tail-aligned window duplicates slots across
	# "pages" and misreads the counter (audit-59)
	build_scroll = clampi((build_scroll / 9) * 9, 0, maxi(0, (pages - 1) * 9))
	var head := tr("BUILD — tap/1-9 pick, tap again to cancel")
	if pages > 1:
		head += "  (%d/%d)" % [build_scroll / 9 + 1, pages]
	var hfont := 12
	if build_sel >= 0 and build_sel < lst.size():
		var ps: Dictionary = StructureData.STRUCTURES[lst[build_sel]]
		var pcost := ""
		for c in ps.get("cost", []):
			pcost += "%d %s  " % [c[1], tr(str(ItemData.ITEMS.get(str(c[0]), {}).get("name", c[0])))]
		head = tr("BUILD  placing: %s — %s") % [tr(str(ps["name"])), pcost.strip_edges()]
		hfont = 11 # the full recipe needs the smaller face to stay on the card
		if font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hfont).x > 604.0:
			hfont = 10 # long recipes (Lumenite Shard & friends) step down again
		while font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hfont).x > 604.0 and head.length() > 8:
			head = head.left(head.length() - 2) # last-ditch crop — never spill off the card
	draw_string(font, Vector2(bx + 8, by + 16), head, HORIZONTAL_ALIGNMENT_LEFT, -1, hfont, Ink.TEAL)
	if pages > 1:
		click_rects.append({"rect": Rect2(bx + 552, by + 4, 28, 16), "act": "build_pg", "arg": -1})
		click_rects.append({"rect": Rect2(bx + 584, by + 4, 28, 16), "act": "build_pg", "arg": 1})
		draw_string(font, Vector2(bx + 560, by + 17), "◀", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Ink.INK if build_scroll > 0 else Ink.LILAC)
		draw_string(font, Vector2(bx + 592, by + 17), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Ink.INK if build_scroll + 9 < lst.size() else Ink.LILAC)
	for i in range(mini(9, lst.size() - build_scroll)):
		var idx := build_scroll + i
		var s: Dictionary = StructureData.STRUCTURES[lst[idx]]
		var afford := true
		for c in s.get("cost", []):
			if game.item_count(str(c[0])) < int(c[1]):
				afford = false
		var col := Ink.ORANGE if idx == build_sel else (Ink.INK if afford else Color(0.72, 0.45, 0.4))
		var x := bx + 8 + (i % 5) * 122
		var y := by + 32 + (i / 5) * 14
		click_rects.append({"rect": Rect2(x - 4, y - 11, 118, 14), "act": "build_pick", "arg": idx})
		var st := struct_tex(lst[idx])
		if st != null: # silhouette icon — dims vary wildly, fit a 13px box
			var ar := float(st.get_width()) / float(st.get_height())
			var iw := minf(18.0, 13.0 * ar)
			draw_texture_rect(st, Rect2(x, y - 12, iw, 13.0), false,
				Color(1, 1, 1) if afford else Color(1, 0.6, 0.55))
		draw_string(font, Vector2(x + 20, y), tr("%d %s") % [i + 1, tr(str(s["name"])).left(8)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

func draw_tech(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 120, 480, 360)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), tr("TECH  (pts: %d)") % game.tech_points,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.GOLD)
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
		var col := Ink.INK_SOFT if has else (Ink.INK if afford else Ink.LILAC)
		if t.get("parts", 0) > 0 and not has:
			col = Ink.VIOLET if afford else Color(Ink.VIOLET, 0.5) # ancient tech is purple
		var label := "T%d %s [%d]%s%s" % [t.get("tier", 1), tr(str(t.get("name", k))).left(14), t.get("cost", 0),
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
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), tr("CHEST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.GOLD)
	var st = game.chest_ref
	if st == null:
		return
	var y := rr.position.y + 52
	var rect1 := Rect2(rr.position.x + 16, y - 12, 200, 20)
	var rect2 := Rect2(rr.position.x + 230, y - 12, 190, 20)
	click_rects.append({"rect": rect1, "act": "chest_dep", "arg": null})
	click_rects.append({"rect": rect2, "act": "chest_wd", "arg": null})
	draw_string(font, rect1.position, tr("[ deposit all ]"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.TEAL)
	draw_string(font, rect2.position, tr("[ take all ]"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.TEAL)
	y += 28
	var skeys: Array = st.get("store", {}).keys()
	chest_scroll = clampi(chest_scroll, 0, maxi(0, skeys.size() - 12))
	for i2 in range(chest_scroll, skeys.size()):
		var iid: String = skeys[i2]
		draw_string(font, Vector2(rr.position.x + 16, y), tr("%s  x%d") % [tr(str(ItemData.ITEMS.get(iid, {}).get("name", iid))), st["store"][iid]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK)
		y += 18
		if y > rr.end.y - 16:
			break
	if skeys.size() > 12:
		_scroll_btns(rr, "chest_up", "chest_dn")

func draw_craft(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 240, 60, 480, 560)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), tr("CRAFT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.ORANGE)
	var y := rr.position.y + 48
	# the island repair: a worn weapon mends at the bench for half its recipe
	var rep := game.repair_quote()
	if not rep.is_empty():
		var rrect := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rrect, "act": "repair"})
		var rcost := ""
		for c in rep["cost"]:
			rcost += "%d %s, " % [c[1], tr(str(ItemData.ITEMS.get(c[0], {}).get("name", c[0])))]
		var wnm: String = tr(str(ItemData.ITEMS.get(game.player.equipment["weapon"], {}).get("name", "?")))
		draw_string(font, Vector2(rrect.position.x, y), tr("REPAIR %s [%d/%d]  <-  %s") % [wnm,
			int(game.player.weapon_wear), rep["max"], rcost.left(-2).left(46)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.TEAL if rep["afford"] else Ink.INK_SOFT)
		y += 24
	var rep_a := game.repair_quote_armor()
	if not rep_a.is_empty():
		var rrect_a := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rrect_a, "act": "repair_armor"})
		var acost := ""
		for c in rep_a["cost"]:
			acost += "%d %s, " % [c[1], tr(str(ItemData.ITEMS.get(c[0], {}).get("name", c[0])))]
		var anm: String = tr(str(ItemData.ITEMS.get(game.player.equipment["armor"], {}).get("name", "?")))
		draw_string(font, Vector2(rrect_a.position.x, y), tr("REPAIR %s [%d/%d]  <-  %s") % [anm,
			int(game.player.armor_wear), rep_a["max"], acost.left(-2).left(46)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.TEAL if rep_a["afford"] else Ink.INK_SOFT)
		y += 24
	var vis := []
	for rec in ItemData.RECIPES:
		if rec.get("station") not in [game.craft_station, "hand"]:
			continue
		# same tech list craft() consults — a guest's gated recipes live in
		# net_unlocked; filtering on the starter `unlocked` hid them (audit-46)
		var techs46: Array = game.net_unlocked if (game.net != null and game.net.is_client() \
				and not game.net_unlocked.is_empty()) else game.unlocked
		var tgate := game.recipe_tech(rec)
		if tgate != "" and tgate not in techs46:
			continue
		vis.append(rec)
	craft_scroll = clampi(craft_scroll, 0, maxi(0, vis.size() - 20))
	for ri in range(craft_scroll, vis.size()):
		var rec: Dictionary = vis[ri]
		var afford := true
		var cost := ""
		for c in rec.get("cost", []):
			cost += "%d %s, " % [c[1], tr(str(ItemData.ITEMS.get(c[0], {}).get("name", c[0])))]
			if game.item_count(c[0]) < c[1]:
				afford = false
		cost = cost.left(-2)
		var out_name: String = tr(str(ItemData.ITEMS.get(rec["out"][0], {}).get("name", rec["out"][0])))
		if y > rr.end.y - 16:
			break # don't leave click rects for rows that were never drawn
		var rect := Rect2(rr.position.x + 16, y - 12, 440, 18)
		click_rects.append({"rect": rect, "act": "craft", "arg": rec["id"]})
		draw_string(font, Vector2(rect.position.x, y), tr("%s x%d  <-  %s") % [out_name, rec["out"][1], cost.left(50)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK if afford else Ink.INK_SOFT)
		y += 20
		if y > rr.end.y - 16:
			break
	if vis.size() > 20:
		_scroll_btns(rr, "craft_up", "craft_dn")
	if not game.craft_queue.is_empty(): # the island bench queue: builds tick down live
		y += 8
		draw_string(font, Vector2(rr.position.x + 16, y), tr("QUEUE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.ORANGE)
		y += 16
		for cq in game.craft_queue:
			if y > rr.end.y - 14:
				break
			var nm: String = tr(str(ItemData.ITEMS.get(cq["out"], {}).get("name", cq["out"])))
			draw_string(font, Vector2(rr.position.x + 16, y), tr("  %s x%d  %.0fs") % [nm, cq["n"], cq["left"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GREEN)
			y += 15

func draw_inv(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 230, 60, 460, 500)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), tr("INVENTORY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.GREEN)
	# the island carry weight: the bag drags once it tops capacity
	var pl := game.player
	var over: bool = pl.carry_wt() > pl.carry_cap()
	draw_string(font, Vector2(rr.position + Vector2(330, 24)), tr("Wt %d/%d") % [int(pl.carry_wt()), int(pl.carry_cap())],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.RED if over else Ink.TEAL)
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
		var nm: String = tr(str(ItemData.ITEMS.get(k, {}).get("name", k)))
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
		draw_string(font, Vector2(cx0, y0), tr("%s x%d") % [nm.left(16), game.items[k]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD if usable else Ink.INK)
	if keys.size() > rows:
		_scroll_btns(rr, "inv_up", "inv_dn")

func draw_kinbox(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 40, 600, 540)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position + Vector2(16, 24)), tr("KINBOX"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.TEAL)
	draw_string(font, Vector2(rr.position + Vector2(112, 24)), tr("rows swap party/base"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK_SOFT)
	# the island base level: the terminal grades your base and pays slots
	var blv_txt := tr("BASE LV%d") % game.base_level
	if game.base_level < game.BASE_LEVEL_MAX:
		var bmet: bool = game.base_mission_done(game.base_level)
		blv_txt += " · " + tr(str(game.BASE_MISSION_TEXT[game.base_level])).left(20)
		draw_string(font, Vector2(rr.position.x + 16, rr.position.y + 38), blv_txt.left(42),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.GREEN if bmet else Ink.INK_SOFT)
		if bmet and (game.net == null or not game.net.is_client()):
			click_rects.append({"rect": Rect2(rr.position.x + 505, rr.position.y + 12, 80, 20),
				"act": "base_up"})
			draw_string(font, Vector2(rr.position.x + 505, rr.position.y + 26), tr("[UPGRADE]"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.GOLD)
	else:
		draw_string(font, Vector2(rr.position.x + 16, rr.position.y + 38), blv_txt + tr(" MAX"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GOLD)
	var y := rr.position.y + 54
	draw_string(font, Vector2(rr.position.x + 16, y), tr("PARTY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK)
	y += 18
	for pr in party_rows():
		var rect := Rect2(rr.position.x + 24, y - 11, 250, 17)
		draw_portrait(Vector2(rr.position.x + 4, y - 13), str(pr.get("sid", "")))
		click_rects.append({"rect": rect, "act": "party_in", "arg": pr["uid"]})
		click_rects.append({"rect": Rect2(rect.position + Vector2(254, 0), Vector2(52, 17)), "act": "deploy", "arg": pr["arg"]})
		draw_string(font, Vector2(rect.position + Vector2(254, 13)), tr("[>base]"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.GREEN)
		click_rects.append({"rect": Rect2(rect.position + Vector2(310, 0), Vector2(30, 17)), "act": "lead", "arg": pr["uid"]})
		draw_string(font, Vector2(rect.position + Vector2(312, 13)), "[▼]" if pr["out"] else "[*]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.GOLD)
		if game.net == null or not game.net.is_client(): # host-owned pals only
			click_rects.append({"rect": Rect2(rect.position + Vector2(342, 0), Vector2(34, 17)), "act": "skills", "arg": pr["arg"]})
			draw_string(font, Vector2(rect.position + Vector2(344, 13)), "[mv]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.TEAL)
		var prow: String = tr("%s%s%s %s%s Lv%d T%d %s%d/%d") % [
			"● " if pr["out"] else "○ ", str(pr["name"]).left(11),
			"☆" if pr["lucky"] else "", pr["sex"], pr["star_s"], pr["lv"], pr["talent"],
			(tr(str(pr["ailment"])) + "!  ") if pr["ailment"] != "" else "",
			pr["hp"], pr["max_hp"]]
		while prow.length() > 4 and font.get_string_size(prow, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > 246.0:
			prow = prow.left(prow.length() - 2) # button column starts at +254 — the stats stay off it
		draw_string(font, Vector2(rect.position.x, y), prow,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.RED if pr["ailment"] != "" else Ink.INK)
		y += 17
	# deployed workforce (the island: kin working the base live in the world)
	var workers := game.base_pals()
	if game.net == null or not game.net.is_client():
		workers = workers.filter(func(wp): return wp.owner_id == 0) # a guest's hands aren't yours to recall
	if not workers.is_empty():
		y += 8
		draw_string(font, Vector2(rr.position.x + 16, y), tr("BASE (%d/%d) — click to recall") % [workers.size(), game.max_base_pals()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.TEAL)
		y += 18
		var my_pid := multiplayer.get_unique_id() if game.net != null and game.net.is_client() else 0
		for wp in workers:
			var wrect := Rect2(rr.position.x + 24, y - 11, 250, 17)
			draw_portrait(Vector2(rr.position.x + 4, y - 13), wp.species_id)
			var mine: bool = game.net == null or not game.net.is_client() or wp.owner_id == my_pid
			if mine:
				click_rects.append({"rect": wrect, "act": "base_in", "arg": wp})
				# a guest recalls only their own hands — the wire enforces it too
			draw_string(font, Vector2(wrect.position.x, y), tr("%s%s %s Lv%d T%d %s%s") % [tr(str(wp.spec["name"])),
				"☆" if wp.lucky else "", wp.sex, wp.level, wp.talent,
				tr(str(StructureData.STRUCTURES.get(wp.job_site["id"], {}).get("name", wp.job_site["id"]))) if wp.job_site else tr("idle"),
				" [%s]" % tr(str(wp.ailment)) if wp.ailment != "" else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.RED if wp.ailment != "" else Ink.TEAL)
			if mine:
				click_rects.append({"rect": Rect2(wrect.position + Vector2(258, 0), Vector2(34, 17)), "act": "skills", "arg": wp})
				draw_string(font, Vector2(wrect.position.x + 260, y), "[mv]",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.TEAL)
			y += 17
	y += 10
	var brows := box_rows()
	draw_string(font, Vector2(rr.position.x + 16, y), tr("BOX (%d)") % brows.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.ORANGE)
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
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.RED if rd["fav"] else Ink.INK_SOFT)
		if butcher:
			var brect := Rect2(cx0 + colw - 30, y0 - 11, 22, 16)
			click_rects.append({"rect": brect, "act": "butcher", "arg": rd["uid"]})
			draw_string(font, Vector2(brect.position.x + 3, y0), "[x]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.RED)
		var label := "%s%s %s%s Lv%d T%d HP%d/%d%s%s %s" % [rd["name"], "☆" if rd["lucky"] else "", rd["sex"], rd["star_s"], rd["lv"], rd["talent"],
			int(maxi(0, rd["hp"])), int(rd["max_hp"]), rd["ko_t"],
			" [%s]" % tr(str(rd["ailment"])) if rd["ailment"] != "" else "",
			str(rd.get("wk", "")).left(15)]
		draw_portrait(Vector2(cx0, y0 - 12), str(rd.get("sid", "")))
		draw_string(font, Vector2(cx0 + 24, y0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.RED if rd["ko"] or rd["ailment"] != "" else Ink.INK_SOFT)
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
			out.append({"arg": int(d["uid"]), "uid": int(d["uid"]), "sid": str(d["sid"]),
				"name": tr(str(sp.get("name", str(d["sid"])))),
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
			out.append({"arg": p, "uid": p.uid, "sid": p.species_id, "name": tr(str(p.spec["name"])), "lucky": p.lucky,
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
			out.append({"arg": int(d["uid"]), "uid": int(d["uid"]), "sid": str(d["sid"]),
				"name": tr(str(sp.get("name", str(d["sid"])))), "lucky": d["lucky"], "sex": d["sex"],
				"lv": d["lv"], "talent": d["talent"], "hp": d["hp"], "max_hp": d["max_hp"],
				"ailment": d["ailment"], "fav": d["fav"], "star_s": st,
				"ko": d["hp"] <= 0, "ko_t": " [KO]" if d["hp"] <= 0 else "",
				"wk": str(d.get("wk", ""))})
	else:
		for bp in game.box:
			if bp.owner_id != 0:
				continue # a guest's stock doesn't show in the keeper's box
			out.append({"arg": bp, "uid": bp.uid, "sid": bp.species_id, "name": tr(str(bp.spec["name"])), "lucky": bp.lucky,
				"sex": bp.sex, "lv": bp.level, "talent": bp.talent, "hp": int(bp.hp),
				"max_hp": int(bp.max_hp), "ailment": bp.ailment, "fav": bp.fav,
				"star_s": star_str(bp), "ko": bp.hp <= 0,
				"ko_t": " [KO %ds]" % int(maxi(0.0, bp.revive_t - game.t)) if bp.hp <= 0 else "",
				"wk": game.work_str(bp.spec)})
	return out

func draw_shop(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 60, 600, 480)
	Ink.card(self, rr)
	draw_string(font, Vector2(rr.position.x + 16, rr.position.y + 24),
		tr("MERCHANT  (gold: %d)") % game.item_count("gold_coin"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.GOLD)
	if game.merchant == null:
		draw_string(font, rr.position + Vector2(16, 50), tr("The merchant has left."),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK_SOFT)
		return
	var y := rr.position.y + 48
	draw_string(font, Vector2(rr.position.x + 16, y), tr("BUY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.GREEN)
	draw_string(font, Vector2(rr.position.x + 316, y), tr("SELL (50%)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.ORANGE)
	y += 20
	var sy := y
	var sell_n := 0 # sell column counts only rows that actually render
	for k0 in game.items.keys():
		if ItemData.ITEMS.get(k0, {}).get("price", 0) > 0 and k0 != "gold_coin" and game.items[k0] > 0:
			sell_n += 1
	sell_n += sellable_pals().size()
	shop_scroll = clampi(shop_scroll, 0, maxi(0, maxi(game.merchant_stock.size(), sell_n) - 22))
	for i in range(shop_scroll, game.merchant_stock.size()):
		var it: Dictionary = game.merchant_stock[i]
		var nm: String
		if it.has("kin"):
			var sp: Dictionary = SpeciesData.species_of(str(it["kin"]))
			nm = tr("Lv%d %s") % [it["lv"], tr(str(sp.get("name", it["kin"])))]
		else:
			nm = tr(str(ItemData.ITEMS.get(it["id"], {}).get("name", it["id"])))
		var rect := Rect2(rr.position.x + 16, y - 12, 270, 16)
		var afford := game.item_count("gold_coin") >= int(it.get("price", 0))
		if it["n"] > 0 and afford:
			click_rects.append({"rect": rect, "act": "buy", "arg": i})
		var col := Ink.INK if (it["n"] > 0 and afford) else Ink.INK_SOFT # the till can't comp what the bag can't cover
		draw_string(font, Vector2(rect.position.x, y), tr("%s x%d  %dg") % [nm.left(16), it["n"], it["price"]],
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
		draw_string(font, Vector2(rect.position.x, y), tr("%s x%d  +%dg") % [tr(str(ItemData.ITEMS[k]["name"])).left(16),
			game.items[k], maxi(1, int(price * 0.5))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK)
		y += 17
		if y > rr.end.y - 14:
			break
	var shown := 0
	for bp in sellable_pals(): # black-market: sell spare pals for coin
		si += 1
		if si < shop_scroll:
			continue
		if y > rr.end.y - 14 or shown >= 12:
			break
		var rect := Rect2(rr.position.x + 316, y - 12, 270, 16)
		click_rects.append({"rect": rect, "act": "sell_pal", "arg": int(bp["uid"])})
		draw_portrait(Vector2(rect.position.x, y - 14), str(bp.get("sid", "")))
		draw_string(font, Vector2(rect.position.x + 24, y), tr("Lv%d %s  +%dg") % [int(bp["lv"]),
			tr(str(bp["name"])).left(14), int(bp["price"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.ORANGE)
		y += 17
		shown += 1
	if maxi(game.merchant_stock.size(), sell_n) > 22:
		_scroll_btns(rr, "shop_up", "shop_dn", rr.position.x + 289, true) # column gutter

var _dex_cache := []
var _dex_key := ""

func _dex_ids() -> Array:
	# caught first (most caught on top), then spotted, then the unknown dark —
	# recompute only when the catch book changes, not every painted frame
	var key := "%d|%d|%d" % [game.catch_counts.size(), game.dex_seen.size(),
		game.catch_counts.values().reduce(func(a, b): return int(a) + int(b), 0)]
	if key == _dex_key:
		return _dex_cache
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
		return str(tr(str(SpeciesData.species_of(a).get("name", a)))) < str(tr(str(SpeciesData.species_of(b).get("name", b)))))
	_dex_cache = ids; _dex_key = key
	return ids

func sellable_pals() -> Array: # only your OWN kin ride the sell rail — guests' stay off it
	var out: Array = []
	if game.net != null and game.net.is_client():
		for d in game.net_box: # a guest's roster is the mirrored dict, not game.box
			var sp: Dictionary = SpeciesData.species_of(str(d["sid"]))
			# mirror of pal_sell_price — keep the formula in lockstep (base 20);
			# alpha isn't on the wire row, so an alpha sticker reads under paid
			out.append({"uid": int(d["uid"]), "lv": int(d["lv"]), "sid": str(d["sid"]),
				"name": str(tr(str(sp.get("name", d["sid"])))),
				"price": 20 + int(d["lv"]) * 8 + (60 if d["lucky"] else 0) \
					+ int(d["star"]) * 50})
		return out
	for bp in game.box:
		if bp.owner_id == 0:
			out.append({"uid": bp.uid, "lv": bp.level, "sid": bp.species_id,
				"name": tr(str(bp.spec["name"])), "price": game.pal_sell_price(bp)})
	return out

func use_item(k: String) -> void:
	match k:
		"boss_sigil":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("The horn is the host's to sound"))
			elif game.summon_raid():
				game.add_item(k, -1)
		"gauntlet_sigil":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("The gauntlet answers the host, not guests"))
			elif game.start_gauntlet():
				game.add_item(k, -1)
		"kin_egg", "bred_kin_egg", "huge_kin_egg":
			if game.net != null and game.net.is_client():
				if game.net.pay("egg", {k: 1}): # the egg leaves the bag on the click
					game.net.rpc("egg_req", k)
			else:
				game.deposit_egg(k) # the clicked egg wins when held — save the bred one for its bloodline
		"fishing_rod":
			# reusable — the rod never leaves the pack; guests ask the host
			# to roll at their ghost's shore
			if game.net != null and game.net.is_client():
				game.net.rpc("fish_req")
			else:
				game.cast_line()
		"memory_wipe":
			if game.net != null and game.net.is_client():
				game.log_msg(tr("The statue only answers the island's keeper"))
			elif game.respec():
				game.add_item(k, -1)
		"fertilizer":
			# guests: the bag pays at request time — a refusal refunds it
			if game.net != null and game.net.is_client():
				if game.net.pay("fert", {"fertilizer": 1}):
					game.net.rpc("fert_req")
			else:
				game.fertilize()
		"kin_bait":
			game.throw_bait()
		"treasure_map":
			game.use_treasure_map()
		_:
			if k.begins_with("skill_fruit_"):
				if game.net != null and game.net.is_client():
					if game.net.pay("fruit", {k: 1}): # bag pays now; a refusal refunds
						game.net.rpc("fruit_req", k)
				else:
					game.teach_skill_fruit(k)
				return
			var it: Dictionary = ItemData.ITEMS.get(k, {})
			if it.get("heal", 0) > 0:
				if game.player.hp >= game.player.max_hp:
					game.log_msg(tr("HP already full"))
					return # don't burn the medicine
				game.player.hp = mini(game.player.max_hp, game.player.hp + it["heal"])
				game.add_item(k, -1)
				game.log_msg(tr("+%d HP") % it["heal"])
			elif it.get("food", 0) > 0:
				if game.player.hunger >= 100.0:
					game.log_msg(tr("Not hungry"))
					return # don't waste the food at full satiety
				game.player.hunger = minf(100.0, game.player.hunger + it["food"])
				game.add_item(k, -1)
				game.log_msg(tr("+%d food") % it["food"])
				game.sfx_play("eat")
				var bf: Dictionary = it.get("buff", {})
				if not bf.is_empty(): # the island meal bonus: one timed buff at a time
					game.player.eat_buff(bf)
					var bstr := ""
					for bk in bf:
						if bk != "t":
							bstr += ("+" if bstr == "" else ",+") + str(bk).to_upper()
					game.log_msg(tr("Meal buff: %s for %ds") % [bstr, int(bf.get("t", 300))])
			else:
				game.log_msg(tr("Can't use ") + tr(str(k)))

func _text_btns(rr: Rect2, ok_act: String) -> void:
	# on-screen confirm/cancel — the only out when there's no Esc/Enter key
	var ok := Rect2(rr.end.x + 6, rr.position.y, 40, rr.size.y)
	var cx := Rect2(ok.end.x + 6, rr.position.y, 34, rr.size.y)
	draw_rect(ok, Ink.PAPER)
	draw_rect(ok, Ink.GREEN, false, 1.5)
	draw_string(font, ok.position + Vector2(11, rr.size.y - 10), tr("OK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN)
	draw_rect(cx, Ink.PAPER)
	draw_rect(cx, Ink.RED, false, 1.5)
	draw_string(font, cx.position + Vector2(11, rr.size.y - 10), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.RED)
	click_rects.append({"rect": ok, "act": ok_act, "arg": null})
	click_rects.append({"rect": cx, "act": "text_cancel", "arg": null})

func draw_join(r: Vector2) -> void:
	var rr := Rect2(10, r.y - 58 - _vkbd_lift(), 520, 44)
	Ink.card(self, rr, Ink.PAPER, 0.0, 3.0)
	draw_string(font, rr.position + Vector2(10, 19), tr("Join IP (blank=localhost): ") + join_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.TEAL)
	_text_btns(rr, "join_go")

func draw_travel(r: Vector2) -> void:
	var nodes := game.travel_nodes()
	var rr := Rect2(r.x / 2 - 200, 80, 400, 90 + nodes.size() * 20)
	Ink.card(self, rr)
	draw_string(font, rr.position + Vector2(16, 24), tr("WAYPOINT NET"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.TEAL)
	var y := rr.position.y + 50
	var me := Vector2i(game.player.pos)
	for n in nodes:
		var k: Vector2i = n["key"]
		var nm := tr("Kinbox") if n["id"] == "kinbox" else tr("Waypoint")
		var here := (k - me).length() < 3.0
		var rect := Rect2(rr.position.x + 16, y - 12, 360, 18)
		if not here:
			click_rects.append({"rect": rect, "act": "travel", "arg": k})
		var col := Ink.INK_SOFT if here else Ink.INK
		draw_string(font, Vector2(rect.position.x, y), tr("%s%s  (%d,%d)  %dm") %
			[nm, tr("  ·here·") if here else "", k.x, k.y, int(n["dist"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		y += 20
	draw_string(font, Vector2(rr.position.x + 16, rr.end.y - 14),
		tr("click a node to blink there · esc closes"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.INK_SOFT)

func draw_dex(r: Vector2) -> void:
	var rr := Rect2(r.x / 2 - 300, 40, 600, 560)
	Ink.card(self, rr)
	var ids := _dex_ids() # the sort is O(n log n) of ~200 species — cache it
	var caught := game.catch_counts.size()
	var seen_n: int = game.dex_seen.size()
	draw_string(font, rr.position + Vector2(16, 24),
		tr("KINDEX   %d/%d caught · %d seen") % [caught, ids.size(), seen_n],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.VIOLET)
	var rows := 32
	dex_scroll = clampi(dex_scroll, 0, maxi(0, ids.size() - rows))
	var y := rr.position.y + 48
	for i in range(dex_scroll, mini(ids.size(), dex_scroll + rows)):
		var sid: String = ids[i]
		var sp: Dictionary = SpeciesData.species_of(sid)
		var cc: int = game.catch_counts.get(sid, 0)
		if cc > 0:
			var els: String = "/".join(sp.get("elements", []).map(func(e): return tr(str(e))))
			draw_portrait(Vector2(rr.position.x + 16, y - 11), sid, 18.0, 14.0)
			draw_string(font, Vector2(rr.position.x + 40, y), str(tr(str(sp.get("name", sid)))).left(18),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK)
			var hz := SpeciesGen.habitat(sid) # Kindex habitat: where to hunt it
			var hztxt := (tr(" z%d  ") % hz) if hz >= 0 \
				else (tr(" den  ") if sid in Game.LEGENDARY_DEN else tr(" egg  "))
			# non-zoned ids aren't habitat-less — dens and egg lines say where
			draw_string(font, Vector2(rr.position.x + 310, y), tr("%s%s×%d") % [els.left(8),
				hztxt, cc],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.GREEN)
			# field guide: a caught species tells you what it drops
			var dnames := []
			for dr in sp.get("drops", []):
				dnames.append(str(tr(str(ItemData.ITEMS.get(dr[0], {}).get("name", dr[0])))).left(8))
			draw_string(font, Vector2(rr.position.x + 445, y), tr(", ").join(dnames).left(11),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.INK_SOFT)
			# and which posts it can staff — the base-planning half of the entry
			draw_string(font, Vector2(rr.position.x + 530, y), game.work_str(sp).left(10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.TEAL)
		elif game.dex_seen.has(sid):
			draw_string(font, Vector2(rr.position.x + 16, y), "%s" % sp.get("glyph", "?"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK_SOFT)
			draw_string(font, Vector2(rr.position.x + 40, y), tr("%s  ·spotted·") % str(tr(str(sp.get("name", sid)))).left(18),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK_SOFT)
		else:
			draw_string(font, Vector2(rr.position.x + 16, y), tr("?  ?????"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ink.INK, 0.35))
		y += 15
	draw_string(font, Vector2(rr.position.x + 16, rr.end.y - 16),
		tr("wheel scroll · every 10 species caught pays +2 tech"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.INK_SOFT)
	if ids.size() > rows:
		_scroll_btns(rr, "dex_up", "dex_dn")

func _vkbd_lift() -> float:
	# the OS keyboard this HUD summoned eats the bottom ~40% — ride above it
	return float(DisplayServer.virtual_keyboard_get_height()) if _vkbd_open else 0.0

func draw_chat(r: Vector2) -> void:
	var rr := Rect2(12, r.y - 40 - _vkbd_lift(), 480, 28)
	Ink.card(self, rr, Ink.PAPER, 0.0, 3.0)
	draw_string(font, rr.position + Vector2(10, 19), tr("Say: ") + chat_buf + "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN)
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
		s += "[" + tr(str(pv["name"])) + "]"
	return s

const PERK_LABEL := Game.PERK_LABEL

func _eq_line() -> String:
	var wn: String = tr(str(ItemData.ITEMS.get(game.player.equipment["weapon"], {}).get("name", "Fists")))
	if game.player.weapon_wear >= 0.0:
		wn += " [%d]" % int(game.player.weapon_wear)
	var an: String = tr(str(ItemData.ITEMS.get(game.player.equipment["armor"], {}).get("name", "None")))
	var acc := ""
	for s in ["acc1", "acc2"]:
		var a: String = tr(str(ItemData.ITEMS.get(game.player.equipment[s], {}).get("name", "")))
		if a != "":
			acc += "  " + a
	return "Wpn: %s   Arm: %s%s" % [wn, an, acc]

func draw_statues(r: Vector2) -> void:
	# panel rect like every sibling — the old body treated the viewport
	# SIZE as a position and painted the whole panel off-screen (dead UI)
	var rr := Rect2(r.x / 2 - 230, 50, 460, r.y - 100)
	Ink.card(self, rr)
	draw_string(font, rr.position + Vector2(16, 24), tr("EFFIGIES"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.GREEN)
	var y := rr.position.y + 56.0
	draw_string(font, Vector2(rr.position.x + 16, y - 16), tr("Stat points: %d   Sprigmelt Effigies: %d") % [game.stat_pts, game.item_count("sprigmelt_effigy")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GREEN)
	for k in game.perks:
		var lvl: int = game.perks[k]
		var cost := 2 + lvl * 2
		var txt := "%s  Lv%d/5  (cost %d)" % [tr(str(PERK_LABEL.get(k, k))), lvl, cost] # foreign saves can inject unknown perk keys
		var rect := Rect2(rr.position.x + 16, y - 12, 360, 20)
		var col := Ink.INK if lvl < 5 else Ink.INK_SOFT
		if lvl < 5:
			click_rects.append({"rect": rect, "act": "perk", "arg": k})
		draw_string(font, Vector2(rect.position.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 24
	# soul infusion: the same effigies harden a kin you own
	y += 10
	draw_string(font, Vector2(rr.position.x + 16, y - 16), tr("SOUL INFUSION (+4%/soul)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.VIOLET)
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
		var col2 := Ink.INK_SOFT if full else Ink.INK
		draw_portrait(Vector2(rect2.position.x, y - 11), q2.species_id)
		draw_string(font, Vector2(rect2.position.x + 24, y), tr("%s Lv%d  soul+%d  (cost %d)") %
			[str(tr(str(q2.spec["name"]))).left(14), q2.level, q2.soul_boost, cost2],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col2)
		y += 20
	if infused.size() > rows2:
		_scroll_btns(rr, "stat_up", "stat_dn")

func draw_equipment_line() -> void:
	wtext(Vector2(14, 80), _eq_line(), Color(Ink.PAPER, 0.9), 12)

func draw_skills(r: Vector2) -> void:
	# the island move loadout: slot up to 3 of the kin's learned moves —
	# an empty loadout means "use everything learned" (the old default)
	var rr := Rect2(r.x / 2 - 220, 140, 440, 300)
	Ink.card(self, rr)
	var tp := game.skill_target
	if tp == null or not is_instance_valid(tp):
		draw_string(font, rr.position + Vector2(16, 24), tr("No kin selected"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.INK)
		return
	draw_portrait(rr.position + Vector2(16, 10), tp.species_id, 24.0, 19.0)
	draw_string(font, rr.position + Vector2(44, 24),
		tr("%s — slot up to 3 moves (Esc closes)") % tr(str(tp.spec["name"])),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.TEAL)
	var y := rr.position.y + 50
	for sid in tp.learned_skills():
		var sk: Dictionary = SkillData.SKILLS.get(sid, {})
		var on: bool = sid in tp.equipped
		var rect := Rect2(rr.position.x + 16, y - 12, 400, 18)
		click_rects.append({"rect": rect, "act": "skill_tgl", "arg": {"p": tp, "sid": sid}})
		draw_string(font, Vector2(rect.position.x, y), tr("%s %s  pow%d  cd%ds") %
			["[x]" if on else "[ ]", str(tr(str(sk.get("name", sid)))).left(18),
				int(sk.get("power", 0)), int(sk.get("cooldown", 2))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Ink.GOLD if on else Ink.INK_SOFT)
		y += 19
	y += 8
	draw_string(font, Vector2(rr.position.x + 16, y),
		tr("empty loadout = all learned moves fire"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ink.INK_SOFT)


func draw_guide(r: Vector2) -> void:
	# the Field Guide — a traveler's handbook in the world's own voice
	var w := 620.0
	var h := r.y - 60.0
	var rr := Rect2(Vector2(r.x - w, 10) / 2.0 + Vector2(0, 20), Vector2(w, h - 30))
	Ink.card(self, rr, Ink.PAPER)
	var lines := []
	var max_w := 560.0 # the paper's inner width — measure, don't count chars
	var gsz := 10
	for raw in GuideData.pages()[guide_page].split("\n"):
		if font.get_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, gsz).x <= max_w:
			lines.append(raw)
			continue
		var rest: String = raw
		while font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, gsz).x > max_w:
			var cut := -1
			for probe in range(mini(rest.length(), 96), 20, -1):
				if rest.substr(probe, 1) == " " and font.get_string_size(rest.left(probe), HORIZONTAL_ALIGNMENT_LEFT, -1, gsz).x <= max_w:
					cut = probe
					break
			if cut < 0: # no space fits — hard-break at the measured width
				cut = 30
				while cut < rest.length() and font.get_string_size(rest.left(cut + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, gsz).x <= max_w:
					cut += 1
			lines.append(rest.substr(0, cut))
			rest = rest.substr(cut + 1)
		lines.append(rest)
	var vis := int((rr.end.y - 44.0 - (rr.position.y + 22)) / 14) + 1 # rows the paper holds
	guide_scroll = clampi(guide_scroll, 0, maxi(0, lines.size() - vis))
	var y := rr.position.y + 22
	for i in range(guide_scroll, lines.size()):
		var ln: String = lines[i]
		var head: bool = ln.begins_with("—") or (i - guide_scroll < 2 and ln == ln.to_upper() and ln.length() > 3)
		if y > rr.end.y - 44.0: # the paper ends before the prose does — clip, never spill
			break
		draw_string(font, Vector2(rr.position.x + 22, y), ln,
			HORIZONTAL_ALIGNMENT_LEFT, -1, gsz,
			Ink.ORANGE if head else Ink.INK)
		y += 14
	if lines.size() > vis: # more prose below the fold — say so
		draw_string(font, Vector2(rr.end.x - 110, rr.position.y + 16),
			tr("%d-%d / %d") % [guide_scroll + 1, mini(lines.size(), guide_scroll + vis), lines.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ink.INK_SOFT)
		_scroll_btns(rr, "guide_up", "guide_dn")
	draw_string(font, Vector2(rr.position.x + 22, rr.end.y - 14),
		tr("Esc/n close · ←/→ turn the page · %d / %d") % [guide_page + 1, GuideData.pages().size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK_SOFT)
	# tap turners — no arrow keys on a slab
	var pv := Rect2(rr.end.x - 84, rr.end.y - 34, 34, 24)
	var nx := Rect2(rr.end.x - 42, rr.end.y - 34, 34, 24)
	for b3 in [[pv, "guide_prev", "‹"], [nx, "guide_next", "›"]]:
		draw_rect(b3[0], Ink.PAPER_DARK)
		draw_rect(b3[0], Ink.INK, false, 1.0)
		draw_string(font, b3[0].position + Vector2(11, 18), b3[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ink.INK)
		click_rects.append({"rect": b3[0], "act": b3[1], "arg": null})
