# S113 save-roundtrip walkthrough — real input end to end:
# play -> build state -> F5 save -> mutate -> F4,F4 reload ->
# Esc->menu->SAVE & QUIT TO TITLE -> CONTINUE -> corrupt-save resilience.
# All verbs ride real injected events; markers are fixtures (state to
# persist), the verbs under test are the save/load/menu input paths.
extends SceneTree

var fails := 0
var game: Node
var hudn: Node
var main: Node
var pal_spec := "" # loaded pals get fresh uids — identity is species+mode

func _initialize() -> void:
	call_deferred("_boot")

func _gate(name: String, cond: bool, info := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not cond:
		fails += 1

func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/tmp/plg-save-%s.png" % name)
	print("shot %s" % name)

func _stamp() -> void:
	var out: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], out, true)
	print("SAVE run %s sha=%s" % [Time.get_datetime_string_from_system(),
		str(out[0]).strip_edges() if out.size() > 0 else "?"])

func _tap_key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k; ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventKey.new()
	ev2.keycode = k; ev2.pressed = false
	Input.parse_input_event(ev2)
	await process_frame

func _tap_action(act: String) -> void: # real keycode pulled from the live
	for ev in InputMap.action_get_events(act): # InputMap — a dead binding
		if ev is InputEventKey:                      # must fail the gate
			await _tap_key(ev.keycode)
			return
	_gate("action %s has a key" % act, false)

func _click(x: float, y: float) -> void:
	root.warp_mouse(Vector2i(int(x), int(y))) # the physical cursor wins
	await process_frame
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.position = Vector2(x, y)
	p.pressed = true
	Input.parse_input_event(p)
	await process_frame
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.position = Vector2(x, y)
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame

func _click_row(act_name: String) -> bool: # click a live menu/panel row
	for cr in hudn.click_rects:
		if cr["act"] == act_name:
			var c: Vector2 = cr["rect"].get_center()
			await _click(c.x, c.y)
			return true
	return false

func _restore_save() -> void: # audit-66: RAM-only backup dies with the
	# script — a crash mid-run would eat a real save. Spill to disk at
	# boot; restore from disk; a missing backup means "there was no save".
	if FileAccess.file_exists("user://savegame.plg.savbak"):
		var dst := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
		dst.store_buffer(FileAccess.get_file_as_bytes("user://savegame.plg.savbak"))
		dst.close()
		DirAccess.remove_absolute("user://savegame.plg.savbak")
	elif FileAccess.file_exists("user://savegame.plg"):
		DirAccess.remove_absolute("user://savegame.plg")
	# the game's own .bak rotation is operator state too — same contract
	if FileAccess.file_exists("user://savegame.plg.bak.savbak"):
		var db := FileAccess.open("user://savegame.plg.bak", FileAccess.WRITE)
		db.store_buffer(FileAccess.get_file_as_bytes("user://savegame.plg.bak.savbak"))
		db.close()
		DirAccess.remove_absolute("user://savegame.plg.bak.savbak")
	elif FileAccess.file_exists("user://savegame.plg.bak"):
		DirAccess.remove_absolute("user://savegame.plg.bak")

func _boot() -> void:
	_stamp()
	if FileAccess.file_exists("user://savegame.plg"): # never eat a real save
		var f0 := FileAccess.open("user://savegame.plg.savbak", FileAccess.WRITE)
		f0.store_buffer(FileAccess.get_file_as_bytes("user://savegame.plg"))
		f0.close()
	if FileAccess.file_exists("user://savegame.plg.bak"): # …nor its backup
		var fb := FileAccess.open("user://savegame.plg.bak.savbak", FileAccess.WRITE)
		fb.store_buffer(FileAccess.get_file_as_bytes("user://savegame.plg.bak"))
		fb.close()
	change_scene_to_file("res://scenes/main.tscn") # a real current_scene —
	for i in 12:                                  # reload_current_scene must
		await process_frame                     # work for to_title's leg
	main = current_scene
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 30:
		await process_frame
	_gate("boots to title", game.state == "title")
	for i in 3:
		if game.state == "play":
			break
		await _click_row("new_game")
	for i in 10:
		await process_frame
	_gate("NEW GAME enters play", game.state == "play")

	# ---- markers: state the save must carry — fixtures, verbs untested
	game.add_item("wood", 37)
	game.add_item("lumenite", 3)
	game.tod = 14.5
	var pal: Kin = game.gen_pal("sprigmelt", 5, game.player.pos)
	game.pals.append(pal) # gen_pal is a factory — registration is the caller's
	pal.mode = "partner" # a rostered kin rides the save too
	game.party.append(pal.uid)
	pal_spec = pal.species_id
	var save_pos := Vector2(114, 110)
	if game.world.blocked(114, 110):
		save_pos = Vector2(int(game.player.pos.x), int(game.player.pos.y))
	game.player.pos = save_pos
	for i in 4:
		await process_frame
	var wood_s: int = game.item_count("wood")
	var tod_s: float = game.tod
	var day_s: int = game.day
	var party_s: int = game.party.size()

	# ---- F1: real key -> save (audit-66: file_exists is vacuous when a
	# save already exists — assert the bytes actually changed)
	var md5_0 := FileAccess.get_md5("user://savegame.plg") \
		if FileAccess.file_exists("user://savegame.plg") else ""
	await _tap_action("save")
	for i in 6:
		await process_frame
	_gate("F1 writes the save", FileAccess.file_exists("user://savegame.plg")
		and FileAccess.get_md5("user://savegame.plg") != md5_0,
		"md5=%s" % FileAccess.get_md5("user://savegame.plg"))

	# ---- mutate everything the save owns
	game.items["wood"] = 0
	game.items["lumenite"] = 0
	game.tod = 22.0
	game.day = 99
	game.player.pos = save_pos + Vector2(6, 6)
	for qu in game.party.duplicate():
		game.party.erase(qu) # roster mutation — the save must put it back
	pal.mode = "wild"
	for i in 6:
		await process_frame
	_gate("state mutated", game.item_count("wood") == 0 and game.day == 99,
		"wood=%d day=%d" % [game.item_count("wood"), game.day])

	# ---- F4,F4: armed-confirm then real reload
	await _tap_action("load_save")
	# audit-66: messages is a 6-entry ring — an append-index baseline scans
	# nothing once it's full. Assert the real arm field AND the tail line.
	var armed: bool = game.load_arm > game.t
	var arm_msg := false
	for mi in range(maxi(0, game.messages.size() - 3), game.messages.size()):
		if "F4" in str(game.messages[mi]):
			arm_msg = true
	_gate("first F4 only arms", armed and arm_msg and game.day == 99,
		"day=%d arm=%.1f msg=%s" % [game.day, game.load_arm - game.t, arm_msg])
	await _tap_action("load_save")
	for i in 20:
		await process_frame
	_gate("F4,F4 restores the save", game.day == day_s
		and game.item_count("wood") == wood_s and absf(game.tod - tod_s) < 0.5,
		"day=%d wood=%d tod=%.1f" % [game.day, game.item_count("wood"), game.tod])
	_gate("position round-trips", game.player.pos.distance_to(save_pos) < 1.5,
		"pos=%s want~%s" % [str(game.player.pos), str(save_pos)])
	# audit-66: loaded pals get FRESH uids (party_idx maps positionally) —
	# identity survives as species+mode+party membership, not the old uid
	var pal_back: Kin = game.find_pal(game.party[0]) if game.party.size() > 0 else null
	_gate("roster round-trips", game.party.size() == party_s
		and pal_back != null and pal_back.mode == "partner"
		and pal_back.species_id == pal_spec,
		"party=%d want %d pal=%s" % [game.party.size(), party_s,
			"%s/%s" % [pal_back.species_id, pal_back.mode] if pal_back != null else "missing"])
	await _shot("reloaded")

	# ---- Esc -> SAVE & QUIT TO TITLE -> CONTINUE
	await _tap_key(KEY_ESCAPE)
	for i in 6:
		await process_frame
	_gate("Esc pauses", game.state == "paused")
	_gate("title row found", await _click_row("to_title"))
	for i in 30:
		await process_frame
	# reload_current_scene rebuilt everything — old refs point at freed nodes
	main = current_scene
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 10:
		await process_frame
	_gate("quit to title", game.state == "title")
	game.tod = 99.0 # title-state poke — CONTINUE must read the file, not RAM
	_gate("CONTINUE row found", await _click_row("continue"))
	for i in 25:
		await process_frame
	_gate("CONTINUE resumes the save", game.state == "play"
		and game.day == day_s and game.item_count("wood") == wood_s
		and absf(game.tod - tod_s) < 0.5, # the 99.0 poke proves file, not RAM
		"state=%s day=%d wood=%d tod=%.1f" % [game.state, game.day,
			game.item_count("wood"), game.tod])
	await _shot("continued")

	# ---- corrupt saves: a torn main must recover via .bak (audit-69 H1);
	# only BOTH files dead may fail closed
	game.to_title() # NB to_title() saves first — corrupt AFTER it lands
	for i in 30:
		await process_frame
	main = current_scene # scene reloaded — re-resolve like the first leg
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 10:
		await process_frame
	var f := FileAccess.open("user://savegame.plg", FileAccess.WRITE)
	if f:
		f.store_string("KINBOUND-CORRUPTED-BLOB")
		f.close()
	game.day = 55 # canary (audit-66): a post-validation reject that left the
	_gate("CONTINUE on torn main", await _click_row("continue")) # world
	for i in 25:                                                # half-rebuilt
		await process_frame                                     # would still
	_gate("torn main recovers via .bak", game.state == "play"   # pass on
		and game.day != 55, "state=%s day=%d" % [game.state, game.day])
	# now burn BOTH files — nothing left to recover from
	game.to_title() # a good save + a good .bak land again
	for i in 30:
		await process_frame
	main = current_scene
	game = main.get_node("Game")
	hudn = main.get_node("UILayer/HUD")
	for i in 10:
		await process_frame
	for p2 in ["user://savegame.plg", "user://savegame.plg.bak"]:
		var f2 := FileAccess.open(p2, FileAccess.WRITE)
		if f2:
			f2.store_string("KINBOUND-CORRUPTED-BLOB")
			f2.close()
	game.day = 55
	_gate("CONTINUE on both-dead saves", await _click_row("continue"))
	for i in 25:
		await process_frame
	_gate("both-dead saves fail closed", game.state == "title"
		and game.day == 55, "state=%s day=%d" % [game.state, game.day])

	_restore_save()
	print("==== SAVE-LOOP: %d failures ====" % fails)
	quit(fails)
