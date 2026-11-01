extends Control
# Minimal HUD: HP/XP bar, sphere tier, party chips, message log, help text.

var game: Game
var font := ThemeDB.fallback_font
var show_help := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		show_help = not show_help
	if event.is_action_pressed("party_toggle"):
		var next_base := party_shift()
		if next_base >= 0:
			var p: Pal = game.party_pal()
			if p:
				p.mode = "base" if p.mode == "partner" else "partner"
				game.log_msg("%s -> %s" % [p.spec["name"], p.mode])

func party_shift() -> int:
	return 0

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not game or not game.player:
		return
	var pl := game.player
	var r := get_viewport().get_visible_rect()
	# top-left: HP bar
	draw_rect(Rect2(12, 10, 224, 18), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(14, 12, int(220 * clampf(pl.hp / pl.max_hp, 0, 1)), 14), Color("#4caf50"))
	draw_string(font, Vector2(16, 25), "HP %d/%d  Lv%d" % [int(pl.hp), int(pl.max_hp), pl.level],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# spheres
	var tiers := game.sphere_tiers()
	var sx := 12
	for id in ["pal_sphere", "mega_sphere", "giga_sphere", "ultra_sphere", "legendary_sphere"]:
		var n := game.item_count(id)
		if n <= 0:
			continue
		var sel := tiers.find(id) == pl.sphere_sel
		draw_rect(Rect2(sx, 34, 70, 20), Color(0, 0, 0, 0.55))
		if sel:
			draw_rect(Rect2(sx, 34, 70, 20), Color("#4dd0e1"), false, 1.5)
		draw_string(font, Vector2(sx + 4, 49), "%s x%d" % [ItemData.ITEMS[id]["name"].left(7), n],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		sx += 74
	# aim hint
	if pl.aiming:
		draw_string(font, Vector2(12, 76), "AIM — click a pal to throw (Q cancel)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#4dd0e1"))
	# time
	draw_rect(Rect2(r.size.x - 130, 10, 118, 20), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(r.size.x - 122, 25), "Day %d  %02d:00" % [game.day, int(game.tod)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8f0f2"))
	# message log bottom-left
	var my := r.size.y - 24
	for i in range(game.messages.size()):
		var m: String = game.messages[game.messages.size() - 1 - i]
		draw_string(font, Vector2(14, my - i * 18), m,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	# party chips top-right under time
	var py := 38
	for uid in game.party:
		var p := game.find_pal(uid)
		if not p:
			continue
		draw_rect(Rect2(r.size.x - 150, py, 138, 16), Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(r.size.x - 144, py + 13), "%s Lv%d %s" %
			[p.spec["name"], p.level, "●" if p.mode == "partner" else "○"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8f0d0"))
		py += 18
	if show_help:
		var lines := [
			"MOVE  wasd/arrows    SPRINT  shift    DODGE  space",
			"MELEE/CHOP  left-click   AIM  q   THROW  lmb   BALL  tab",
			"PARTNER->BASE toggle  f    HELP  h",
			"HP<40% or status + sneak-behind = better catch odds.",
		]
		draw_rect(Rect2(10, r.size.y - 120, 560, 72), Color(0, 0, 0, 0.7))
		for i in range(lines.size()):
			draw_string(font, Vector2(20, r.size.y - 100 + i * 17), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dfe8ea"))
