class_name VehicleParams
extends Resource
@export var car_id := ""
@export var model := ""                 # путь к .glb кузова (Kenney Car Kit, CC0)
@export var mass := 1300.0
@export var accel_max := 7.0
@export var vmax_kmh := 160.0
@export var brake_decel := 11.0     # м/с² предельного замедления: 1.0 g — то, что держат шины
@export var steer_rate_deg := 190.0   # скорость набора угла передних колёс, °/с
@export var grip := 8.0             # множитель сцепления шин (wheel_friction_slip)
@export var suspension_stiffness := 120.0
@export var damping_compression := 7.0
@export var damping_relaxation := 9.0
@export var paint_color := Color.WHITE
@export var paint_metallic := 0.15
@export var paint_roughness := 0.28
@export var width := 1.8                # целевая ширина: по ней DentBody считает равномерный масштаб
@export var accent_color := Color(0.8, 0.25, 0.2)
# Насколько растянуть кузов по длине (лимузин). 1.0 — как есть: узлы модели остаются
# на своих местах, а растяжение двигает только сам кузов и заднюю ось.
@export var body_stretch := 1.0
# Нитро — часть модели машины, а не её надпись: значения стоят прямо здесь, поэтому
# любой новый пресет получает форсаж автоматически, даже если в vehicle_db о нитро ни
# слова. Бак в 0 единиц — единственный способ его отменить.
@export var nitro_capacity := 100.0      # условные единицы бака
@export var nitro_drain := 50.0          # единиц/с: полного бака — 2 с форсажа
@export var nitro_refill := 13.0         # единиц/с: копится вчетверо медленнее, чем уходит
@export var nitro_accel := 9.0           # м/с² сверх тяги двигателя
@export var nitro_vmax := 1.45           # во сколько раз можно превысить паспортный потолок
# производные от модели — заполняет DentBody.setup(), руками не задавать
@export var length := 4.4
@export var height := 1.45
@export var wheel_r := 0.36

func collider_size() -> Vector3:
	return Vector3(length * 0.94, height * 0.9, width * 0.94)
