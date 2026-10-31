extends Node3D
# Ездовой тест ПО ВСЕМ машинам. Новый кузов обязан ехать сразу: он может быть растянут
# (лимузин), без паспортного потолка (бесконечность) или с другой геометрией колёс — и
# именно тогда чаще всего ломается посадка (луч подвески висит над полом), масштаб
# модели или узел кузова, на котором мнутся вмятины. Проверка перебирает VehicleDB.ids(),
# поэтому добавить машину — значит автоматически добавить её в этот тест.

const HOLD := 180            # тиков газа (3 с)

var _fails := 0
var car: CarRig
var _floor: StaticBody3D

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	_floor = StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(3000, 2, 3000); cs.shape = box
	_floor.add_child(cs); add_child(_floor); _floor.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	for id in VehicleDB.ids():
		await _drive(id)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _drive(id: String) -> void:
	if car != null and is_instance_valid(car): car.free()
	car = CarRig.new()
	add_child(car)
	var p := VehicleDB.get_params(id)
	car.build(p, get_world_3d())
	await get_tree().physics_frame
	check(car.body != null and car.body.body != null, "%s: у кузова есть узел 'body' — вмятины будут" % id)
	check(car.wheel_count() == 4, "%s: четыре колеса (%d)" % [id, car.wheel_count()])
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for _i in 20:
		await get_tree().physics_frame
	var rest_y := car.chassis.global_position.y
	check(rest_y > p.wheel_r * 0.7 and rest_y < p.wheel_r * 1.9,
		"%s: машина сидит на колёсах, а не висит и не легла на кузов (y=%.2f, радиус %.2f)" % [
			id, rest_y, p.wheel_r])
	Input.action_press("throttle")
	for _i in HOLD:
		await get_tree().physics_frame
	Input.action_release("throttle")
	var v := car.speed_kmh()
	# Ожидаем не «60 км/ч у всех», а 70% от идеального разгона при постоянном ускорении:
	# кривая тяги и сопротивление воздуха съедают треть, и у медленной машины цель должна
	# быть ниже, чем у быстрой, — иначе тест был бы проверкой «самая быстрая проходит».
	var ideal := 3.6 * p.accel_max * (HOLD / 60.0)
	var target := minf(ideal * 0.7, p.vmax_kmh * 0.9)
	print("%-10s за 3 с: %.0f км/ч (цель %.0f), путь %.0f м, кузов y=%.2f, крен %.0f°" % [
		id, v, target, car.chassis.global_position.x, car.chassis.global_position.y,
		rad_to_deg(asin(clampf(car.chassis.global_basis.x.y, -1.0, 1.0)))])
	check(v >= target, "%s: разгоняется хотя бы до %.0f км/ч (разгон %.1f м/с²)" % [id, target, p.accel_max])
	# треть пути при постоянном ускорении — запас на кривую тяги и воздух
	var way_min := 0.35 * 0.5 * (ideal / 3.6) * (HOLD / 60.0)
	check(car.chassis.global_position.x > way_min,
		"%s: проехала %.0f м, а не стояла на месте (ждали больше %.0f м)" % [
			id, car.chassis.global_position.x, way_min])
	check(car.chassis.global_position.y < 2.0, "%s: не улетела с земли (y=%.2f)" % [
		id, car.chassis.global_position.y])
	check(absf(car.chassis.global_basis.x.y) < 0.35, "%s: едет на колёсах, не на боку" % id)
	# руль: короткое движение должно повернуть (и у длинной машины тоже)
	var yaw0 := car.heading
	Input.action_press("throttle")
	Input.action_press("steer_left")
	for _i in 45:
		await get_tree().physics_frame
	Input.action_release("steer_left")
	Input.action_release("throttle")
	var dyaw := rad_to_deg(angle_difference(car.heading, yaw0))
	check(absf(dyaw) > 6.0, "%s: слушается руля (%.1f° за 0.75 с)" % [id, dyaw])
