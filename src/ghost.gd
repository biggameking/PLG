extends Node2D
class_name GhostPlayer

# Visual-only remote player: lerps toward the last synced net position.

var game: Game
var net_pos := Vector3(-1, -1, 0)
var sprite: Sprite2D
var shadow: Sprite2D

func _ready() -> void:
	shadow = Sprite2D.new()
	shadow.texture = load("res://assets/shadow.png")
	shadow.modulate = Color(0, 0, 0, 0.35)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/kin/player_f0.png")
	sprite.position.y = -40.0
	add_child(sprite)

func _process(_dt: float) -> void:
	if net_pos.x < 0:
		return
	var target := Iso.to_screen(net_pos.x, net_pos.y, net_pos.z)
	position = position.lerp(target, 0.25)
