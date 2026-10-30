class_name VehicleParams
extends Resource
@export var car_id := ""
@export var model := ""                 # путь к .glb кузова (Kenney Car Kit, CC0)
@export var mass := 1300.0
@export var accel_max := 7.0
@export var vmax_kmh := 160.0
@export var brake_decel := 22.0
@export var steer_rate_deg := 38.0
@export var grip := 8.0
@export var width := 1.8                # целевая ширина: по ней DentBody считает равномерный масштаб
@export var accent_color := Color(0.8, 0.25, 0.2)
# производные от модели — заполняет DentBody.setup(), руками не задавать
@export var length := 4.4
@export var height := 1.45
@export var wheel_r := 0.36

func collider_size() -> Vector3:
	return Vector3(length * 0.94, height * 0.9, width * 0.94)
