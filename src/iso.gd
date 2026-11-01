class_name Iso
# Isometric projection: tile grid (x,y) + elevation (0..3) → screen px.
# 64x32 diamond, 16px rise per elevation level.

const TW := 64.0
const TH := 32.0
const ELEV_STEP := 16.0

static func to_screen(x: float, y: float, elev: int = 0) -> Vector2:
	return Vector2((x - y) * TW * 0.5, (x + y) * TH * 0.5 - elev * ELEV_STEP)

# screen px → fractional tile coords (ignores elevation)
static func from_screen(sx: float, sy: float, elev: int = 0) -> Vector2:
	var fy := (sy + elev * ELEV_STEP) / (TH * 0.5)
	var fx := sx / (TW * 0.5)
	return Vector2((fy + fx) * 0.5, (fy - fx) * 0.5)
