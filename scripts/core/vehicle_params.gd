class_name VehicleParams
extends Resource
@export var car_id := ""
@export var mass := 1300.0
@export var accel_max := 7.0
@export var vmax_kmh := 160.0
@export var brake_decel := 22.0
@export var steer_rate_deg := 38.0
@export var grip := 8.0
@export var length := 4.4
@export var width := 1.8
@export var height := 1.45
@export var gc := 0.32
@export var body_h := 0.70
@export var roof_h := 0.43
@export var cab_x0 := -1.0
@export var cab_x1 := 0.9
@export var sections := 20
@export var ring_points := 16
@export var k_struct := 1.0
@export var k_anchor := 1.2
@export var break_strain := 0.22
@export var shell_color := Color.RED
@export var hood_scale := 0.85   # высота носа относительно борта
@export var trunk_scale := 0.9   # высота кормы
@export var wheel_r := 0.36
func collider_size() -> Vector3:
	return Vector3(length * 0.92, height - 0.12, width * 0.9)
