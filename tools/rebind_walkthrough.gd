# REAL-INPUT acceptance for the controls/rebind panel (audit-69 M2):
# settings row click → controls panel → click the DODGE row → a real
# key event becomes the bind → settings.cfg persists it → RESET restores.
# Gates FAIL on timeout — no default-green paths.
extends SceneTree

var fails := 0
var game: Node
var hudn: Node
var main: Node

func _gate(name: String, ok: bool, detail := "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name,
		"" if detail == "" else "  " + detail])
	if not ok:
		fails += 1

func _click(x: float, y: float) -> void:
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.position = Vector2(x, y)
	p.pressed = true
	hudn._unhandled_input(p)
	await process_frame
	var r2 := InputEventMouseButton.new()
	r2.button_index = MOUSE_BUTTON_LEFT
	r2.position = Vector2(x, y)
	hudn._unhandled_input(r2)
	await process_frame

func _click_act(act: String, arg = null) -> bool:
	# click the click_rect carrying this act (+arg if given) — the same path
	# a real pointer takes, not a handler shortcut
	for cr in hudn.click_rects:
		if cr["act"] == act and (arg == null or cr["arg"] == arg):
			var c: Vector2 = cr["rect"].get_center()
			await _click(c.x, c.y)
			return true
	return false

func _tap_key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	hudn._unhandled_input(e)
	await process_frame
	var e2 := InputEventKey.new()
	e2.keycode = k
	e2.physical_keycode = k
	hudn._unhandled_input(e2)
	await process_frame

func _binds_of(act: String) -> String:
	var s := ""
	for e in InputMap.action_get_events(act):
		if e is InputEventKey:
			var k := int(e.physical_keycode)
			if k == 0:
				k = int(e.keycode)
			s += "%d " % k
	return s.strip_edges()

func _boot() -> void:
	# never eat the operator's real settings — backup, restore at the end
	var cfg_backup = FileAccess.get_file_as_bytes("user://settings.cfg") \
		if FileAccess.file_exists("user://settings.cfg") else PackedByteArray()
	change_scene_to_file("res://scenes/main.tscn")
	for i in 15:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 20:
		await process_frame
	_gate("boots to title", game.state == "title")
	game.state = "paused" # the pause shell hosts settings — open it for real
	for i in 8:
		await process_frame
	_gate("settings row found", await _click_act("m_settings"))
	for i in 8:
		await process_frame
	_gate("settings panel opens", game.panel == "settings", "panel=%s" % game.panel)

	# ---- settings -> controls -> capture a real key for DODGE
	_gate("controls row found", await _click_act("controls_open"))
	for i in 8:
		await process_frame
	_gate("controls panel opens", game.panel == "controls", "panel=%s" % game.panel)
	var dodge_keys0 := _binds_of("dodge")
	_gate("dodge row found", await _click_act("rebind", "dodge"))
	await process_frame
	_gate("capture armed", hudn.rebind_wait == "dodge", "wait=%s" % hudn.rebind_wait)
	await _tap_key(KEY_Z)
	_gate("Z becomes the dodge bind", "90" in _binds_of("dodge")
		and hudn.rebind_wait == "",
		"keys=%s want-contains 90 (was %s)" % [_binds_of("dodge"), dodge_keys0])

	# ---- clash: binding aim to the same key must refuse, not stack
	_gate("aim row found", await _click_act("rebind", "aim"))
	await process_frame
	await _tap_key(KEY_Z)
	_gate("clash refused — aim keeps its key", "81" in _binds_of("aim")
		and "90" not in _binds_of("aim"), # Q=81 stays, Z never lands
		"aim=%s dodge=%s" % [_binds_of("aim"), _binds_of("dodge")])
	await _tap_key(KEY_ESCAPE) # cancel the still-armed capture
	_gate("esc cancels capture", hudn.rebind_wait == "")

	# ---- persistence: a fresh load_settings sees the bind from disk
	game.settings["binds"] = {}
	game.load_settings()
	_gate("bind persists through cfg", "90" in _binds_of("dodge"),
		"dodge=%s" % _binds_of("dodge"))

	# ---- reset restores the project default
	game.reset_binds()
	_gate("reset restores SPACE on dodge", "32" in _binds_of("dodge"),
		"dodge=%s" % _binds_of("dodge"))
	_gate("back to settings", await _click_act("controls_back"))
	for i in 4:
		await process_frame
	_gate("back lands on settings", game.panel == "settings", "panel=%s" % game.panel)

	# restore the operator's cfg — the harness's binds/scrolls die here
	if cfg_backup.is_empty():
		DirAccess.remove_absolute("user://settings.cfg")
	else:
		var cf := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		cf.store_buffer(cfg_backup); cf.close()
	print("==== REBIND-LOOP: %d failures ====" % fails)
	quit(fails)

func _initialize() -> void:
	call_deferred("_boot")
