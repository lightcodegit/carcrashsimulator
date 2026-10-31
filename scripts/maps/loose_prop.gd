class_name LooseProp
extends RigidBody3D
# Лёгкий предмет на трассе, который сносит машина.
#
# Solver Godot при встрече двух axis-aligned коробок бьёт почти точно через центр
# масс, поэтому без добавки предмет не кувыркается, а едет перед бампером как отвал
# бульдозера. Дозаводим его моментом импульса вокруг поперечной оси — ровно тем,
# что в реальности даёт удар бампером выше основания.

const TUMBLE := 1.5          # безразмерный множитель момента: пилон крутится ~4-5 рад/с
const MIN_HIT_MS := 3.0      # медленное касание (машина просто стоит рядом) кувырка не даёт

var height_m := 1.0

func setup_tumble() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_hit)

func _on_hit(other: Node) -> void:
	var car := other as VehicleBody3D
	if car == null: return
	var v := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	if v.length() < MIN_HIT_MS: return
	# I ≈ m·h²/3 для стержня относительно основания; ω = t/I
	apply_torque_impulse(Vector3.UP.cross(v.normalized()) * mass * height_m * height_m * TUMBLE)
