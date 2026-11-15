extends Node2D
class_name Entity
# Base for anything standing on the world: tile-coords position, elevation-aware
# screen sync, 2-frame walk sprite + shadow, z-index by y-sort.

var world: World
var swims := false          # aquatic pals traverse water tiles
var pos := Vector2.ZERO          # tile coords; tile (x,y) center = x+0.5
var speed := 4.0                  # tiles/sec
var dir := 1                      # facing: 1 right, -1 left
var moving := false
var hit_flash := 0.0
var sprite: Sprite2D
var shadow_spr: Sprite2D
var tex0: Texture2D
var tex1: Texture2D
var anim_t := 0.0
var frame := 0

func setup_visuals(t0: String, t1: String, bottom_px := 64.0) -> void:
	# missing sprite => chest fallback per the load contract — never a
	# null texture on screen
	tex0 = load(t0) if ResourceLoader.exists(t0) else load("res://assets/structures/chest.png")
	tex1 = load(t1) if ResourceLoader.exists(t1) else tex0
	shadow_spr = Sprite2D.new()
	shadow_spr.texture = load("res://assets/shadow.png")
	shadow_spr.position = Vector2(0, -2)
	add_child(shadow_spr)
	sprite = Sprite2D.new()
	sprite.texture = tex0
	sprite.position = Vector2(0, -bottom_px * 0.5)
	add_child(sprite)

func elev() -> int:
	return world.elev_at(int(pos.x), int(pos.y))

func sync_screen() -> void:
	var e := elev()
	position = Iso.to_screen(pos.x, pos.y, e)

func step_toward(target: Vector2, dt: float) -> void:
	var d := target - pos
	var dist := d.length()
	if dist < 0.05:
		moving = false
		return
	var step: float = minf(dist, speed * dt)
	var nx: float = pos.x + d.x / dist * step
	var ny: float = pos.y + d.y / dist * step
	# axis-separated tile collision w/ elevation rule (water open if swims)
	var moved := false
	var bx := world.blocked_swim(int(nx), int(pos.y), pos.x, pos.y) if swims else world.blocked(int(nx), int(pos.y), pos.x, pos.y)
	if not bx:
		pos.x = nx; moved = true
	var byy := world.blocked_swim(int(pos.x), int(ny), pos.x, pos.y) if swims else world.blocked(int(pos.x), int(ny), pos.x, pos.y)
	if not byy:
		pos.y = ny; moved = true
	if not moved: # wedged on a corner: retry rotated ±45° to slide around
		for rot in [0.785, -0.785]:
			var rd := d.normalized().rotated(rot)
			var rx: float = pos.x + rd.x * step
			var ry: float = pos.y + rd.y * step
			var okx := world.blocked_swim(int(rx), int(pos.y), pos.x, pos.y) if swims else world.blocked(int(rx), int(pos.y), pos.x, pos.y)
			var okxy := world.blocked_swim(int(rx), int(ry), pos.x, pos.y) if swims else world.blocked(int(rx), int(ry), pos.x, pos.y)
			if not okx and not okxy:
				pos.x = rx; pos.y = ry; moved = true; break
	moving = true
	if d.x > 0.02:
		dir = 1
	elif d.x < -0.02:
		dir = -1

func _process(dt: float) -> void:
	anim_t += dt
	if moving and anim_t > 0.18:
		anim_t = 0
		frame = 1 - frame
		sprite.texture = tex1 if frame else tex0
	if not moving:
		frame = 0
		sprite.texture = tex0
	sprite.flip_h = dir < 0
	if hit_flash > 0:
		hit_flash -= dt
		sprite.modulate = Color(2.2, 2.2, 2.2) if int(hit_flash * 20) % 2 else Color.WHITE
	else:
		sprite.modulate = Color.WHITE
	moving = false
