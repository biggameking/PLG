class_name Ink
# Field-file visual grammar: warm navy ink on cream paper.
# All HUD chrome goes through card()/tag() so the print look stays
# consistent — hard offset shadow, ink border, no blur, no gradients.

const INK := Color(0.11, 0.10, 0.18)        # #1c1a2e — ink, never pure black
const INK_SOFT := Color(0.11, 0.10, 0.18, 0.55)
const PAPER := Color(0.96, 0.93, 0.85)      # #f4ecd8
const PAPER_DARK := Color(0.90, 0.86, 0.75) # shaded paper / hover
const EDGE := Color(0.16, 0.15, 0.24)       # border tone
const ORANGE := Color(1.0, 0.42, 0.07)      # signal: action
const RED := Color(0.91, 0.26, 0.23)        # signal: danger
const TEAL := Color(0.25, 0.61, 0.60)       # signal: info / selection
const GOLD := Color(0.85, 0.64, 0.25)       # reward / key cap
const GREEN := Color(0.35, 0.64, 0.30)      # health
const MOSS := Color(0.44, 0.60, 0.37)
const VIOLET := Color(0.36, 0.29, 0.54)     # shadow violet #5b4a8a
const LILAC := Color(0.55, 0.48, 0.72)      # #8c7bb8 soft shadow

static var _dots: Texture2D

## Full paper card: hard offset ink shadow, cream fill, 2px ink border,
## faint off-register inner line (print wobble). `tilt` in radians for
## hero panels only — small chips stay square so text stays readable.
static func card(ci: CanvasItem, rr: Rect2, fill := PAPER, tilt := 0.0, shadow := 4.0) -> void:
	if tilt != 0.0:
		var c := rr.get_center()
		ci.draw_set_transform(c, tilt, Vector2.ONE)
		_flat_card(ci, Rect2(-rr.size * 0.5, rr.size), fill, shadow)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_flat_card(ci, rr, fill, shadow)

static func _flat_card(ci: CanvasItem, rr: Rect2, fill: Color, shadow: float) -> void:
	ci.draw_rect(Rect2(rr.position + Vector2(shadow, shadow + 1), rr.size), Color(INK, 0.82))
	ci.draw_rect(rr, fill)
	ci.draw_rect(rr, INK, false, 2.0)
	ci.draw_rect(rr.grow(-1.5), Color(INK, 0.14), false, 1.0)

## Small world-anchored label — same paper, lighter shadow, no inner line.
static func tag(ci: CanvasItem, rr: Rect2, alpha := 1.0, fill := PAPER) -> void:
	var f := fill
	f.a *= alpha
	ci.draw_rect(Rect2(rr.position + Vector2(2, 3), rr.size), Color(INK, 0.75 * alpha))
	ci.draw_rect(rr, f)
	ci.draw_rect(rr, Color(INK, alpha), false, 1.5)

## Halftone dot field over a rect — one draw call, texture tiles.
static func dots(ci: CanvasItem, rr: Rect2, alpha := 0.35) -> void:
	if _dots == null:
		_dots = load("res://assets/ui/halftone.png")
	if _dots:
		ci.draw_texture_rect(_dots, rr, true, Color(1, 1, 1, alpha))
