extends Node3D
# Поворот на большой скорости (жалоба «машины на большой скорости не поворачивают
# нормально»). Угол передних колёс ограничен допустимым боковым ускорением, и прежний
# потолок 1.07 g без нижнего порога на 180 км/ч оставлял полградуса: руль крутится,
# машина едет прямо. Здесь меряется то, что чувствует игрок: как быстро меняется курс,
# сколько машина уводит в сторону, доворачивает ли она после отпускания руля (иначе
# поворот — это занос) и не съедает ли само поворот скорость.
const SPEEDS := [80.0, 140.0, 200.0, 260.0]
const CARS := ["sport", "sedan"]
const HOLD := 60             # тиков полного руля (1 с)
const COAST := 60            # тиков после отпускания
const YAW_MIN := 15.0        # °/с: минимум, который был бы недостижим при старом потолке
const RESIDUAL_MAX := 15.0   # °: на сколько курс уползает после отпускания руля
const SPEED_KEEP := 0.8      # долю скорости обязан сохранить
const SIDE_MIN := 6.0        # м: боковой снос за секунду

var _fails := 0
var car: CarRig
var _queue: Array[String] = []
var _t := 0
var _yaw0 := 0.0
var _z0 := 0.0
var _v0 := 0.0
var _yaw_hold := 0.0
var _max_side := 0.0
var _tag := ""
var _car_id := ""

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(3000, 2, 3000); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	for c in CARS:
		for v in SPEEDS:
			_queue.append("%s|%f" % [c, v])
	_run()

func _run() -> void:
	if _queue.is_empty():
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
		return
	var line: String = _queue.pop_front()
	var parts := line.split("|")
	var id: String = parts[0]
	var kmh := float(parts[1])
	_tag = "%s @%d" % [id, int(kmh)]
	if id != _car_id:
		# CarRig.build добавляет узлы, а не пересобирает их: вторая машина в одном риге
		# оставила бы в дереве оба шасси
		if car != null and is_instance_valid(car): car.free()
		car = CarRig.new(); add_child(car)
		car.build(VehicleDB.get_params(id), get_world_3d())
		_car_id = id
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for _i in 20:
		await get_tree().physics_frame
	car.chassis.linear_velocity = Vector3(kmh / 3.6, 0.0, 0.0)
	_v0 = car.speed_kmh()
	_yaw0 = car.heading
	_z0 = car.chassis.global_position.z
	_t = 0
	_max_side = 0.0
	_yaw_hold = 0.0
	Input.action_press("throttle")
	Input.action_press("steer_left")
	_step()

func _step() -> void:
	await get_tree().physics_frame
	_t += 1
	var v := car.chassis.linear_velocity
	var fwd := car.forward()
	var side := v - fwd * v.dot(fwd)
	side.y = 0.0
	_max_side = maxf(_max_side, side.length())
	if _t == HOLD:
		_yaw_hold = rad_to_deg(angle_difference(car.heading, _yaw0))
		Input.action_release("steer_left")
	if _t < HOLD + COAST:
		_step()
		return
	Input.action_release("throttle")
	var yaw_rate := absf(_yaw_hold)                 # ° за секунду держания руля
	var residual := absf(rad_to_deg(angle_difference(car.heading, _yaw0)) - _yaw_hold)
	var kept := car.speed_kmh() / maxf(_v0, 1.0)
	var drift := absf(car.chassis.global_position.z - _z0)
	print("%-14s курс %+6.1f° за 1 с, после руля %+5.1f°, снос %5.1f м, увод %.1f м/с, на выходе %.0f км/ч (%.0f%%)" % [
		_tag, _yaw_hold, residual, drift, _max_side, car.speed_kmh(), kept * 100.0])
	check(yaw_rate >= YAW_MIN,
		"%s: полный руль на 1 с поворачивает машину минимум на %.0f° (поворот %.1f°)" % [_tag, YAW_MIN, yaw_rate])
	check(drift >= SIDE_MIN, "%s: машина уехала в сторону на %.1f м, а не ехала прямо" % [_tag, drift])
	check(residual <= RESIDUAL_MAX,
		"%s: после отпускания руля курс доворачивает на %.1f° — это занос, а не поворот" % [_tag, residual])
	check(kept >= SPEED_KEEP, "%s: поворот не должен съедать скорость (%.0f%% от %.0f км/ч)" % [
		_tag, kept * 100.0, _v0])
	_run()
