extends Node3D
# Обращение машины после переработки удара:
# A) заезд на рампу и приземление НЕ считаются ударом и не гасят скорость
# B) удар в стену регистрируется и мнёт кузов
# C) касание борта о стену на ходу не теряет скорость и не даёт удара
# D) боковой удар в стену останавливает машину и мнёт борт
# E) ручник тормозит и срывает машину в занос
var _fails := 0
var _frame := 0
var car: CarRig
var _impacts := 0
var _max_y := 0.0
var _ramp_impacts := -1
var _phase := "A"
var _phase_frame := 0
var _brush_speed := 0.0
var _hb_speed := 0.0
var _done := {}
var _hold := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func once(key: String, cond: bool, msg: String) -> void:
	if _done.has(key): return
	_done[key] = true
	check(cond, msg)

func _enter(phase: String, spawn: Transform3D) -> void:
	_phase = phase
	_phase_frame = 0
	_impacts = 0
	_hold = 0
	car.respawn(spawn)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(240, 2, 120); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(40, -1, 0)
	MapDB.wedge(self, Vector3(20, 0.0, 0), 14, 3.2, 10, Color(0.9, 0.8, 0.2))   # рампа x = 20..34
	var wall := StaticBody3D.new()                                             # стена впереди, x = 90
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 40); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(90, 4, 0)
	var side := StaticBody3D.new()                                             # длинная боковая стена по z = 6.3
	var scs := CollisionShape3D.new(); var sbox := BoxShape3D.new()
	sbox.size = Vector3(120, 4, 0.6); scs.shape = sbox
	side.add_child(scs); add_child(side); side.global_position = Vector3(40, 2, 6.3)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_frame += 1
	_phase_frame += 1
	var p := car.chassis.global_position
	_max_y = maxf(_max_y, p.y)
	match _phase:
		"A":
			if _ramp_impacts < 0 and p.x > 45.0:
				_ramp_impacts = _impacts
				once("A1", _ramp_impacts == 0, "A1 заезд на рампу и прыжок не дают удара (%d)" % _ramp_impacts)
				once("A2", _max_y > 1.5, "A2 машина поднялась по рампе (max y=%.2f)" % _max_y)
				once("A3", car.body.dent_count == 0, "A3 рампа не мнёт кузов (%d)" % car.body.dent_count)
			if p.x > 87.0 and car.speed_kmh() < 20.0: _hold += 1
			if _phase_frame > 1200 or _hold > 6:
				Input.action_release("throttle")
				once("B1", _impacts > 0, "B1 удар в стену зарегистрирован (%d)" % _impacts)
				once("B2", car.body.dent_count > 0, "B2 стена помяла кузов (%d)" % car.body.dent_count)
				once("B3", p.x < 90.0, "B3 рама не вошла в стену (%.2f)" % p.x)
				_enter("C", Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 4.9)))
				Input.action_press("throttle")
		"C":
			if _brush_speed == 0.0 and car.speed_kmh() > 70.0:
				_brush_speed = car.speed_kmh()
			if _brush_speed > 0.0 and p.x > 55.0:
				once("C1", absf(p.z - 4.9) < 1.2, "C1 машина идёт вдоль стены (z=%.2f)" % p.z)
				once("C2", _impacts == 0, "C2 скользящее касание не удар (%d)" % _impacts)
				once("C3", car.speed_kmh() > _brush_speed * 0.85,
					"C3 касание не съедает скорость (%.1f из %.1f км/ч)" % [car.speed_kmh(), _brush_speed])
				once("C4", car.body.dent_count == 0, "C4 касание не мнёт кузов (%d)" % car.body.dent_count)
				Input.action_release("throttle")
				_enter("D", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 1.0, -6)))
				Input.action_press("throttle")
		"D":
			if _phase_frame > 200:
				once("D1", p.z < 6.3, "D1 боковой клармп держит раму (z=%.2f)" % p.z)
				once("D2", _impacts > 0, "D2 боковой удар зарегистрирован (%d)" % _impacts)
				once("D3", car.body.dent_count > 0, "D3 борт помят (%d)" % car.body.dent_count)
				once("D4", car.speed_kmh() < 25.0, "D4 машина остановилась (%.1f км/ч)" % car.speed_kmh())
				Input.action_release("throttle")
				_enter("E", Transform3D(Basis.IDENTITY, Vector3(-40, 1.0, -12)))
				Input.action_press("throttle")
		"E":
			if _hb_speed == 0.0 and car.speed_kmh() > 75.0:
				_hb_speed = car.speed_kmh()
				# газ НЕ отпускаем: это ровно тот случай из жалоб — W и Space вместе.
				# Godot считает brake только при engine_force == 0, поэтому CarRig
				# обязан сам снимать тягу на ручнике.
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_phase_frame = 0
			elif _hb_speed > 0.0 and _phase_frame == 60:
				var vel := car.chassis.linear_velocity
				var fwd := Vector3(cos(car.heading), 0, -sin(car.heading))
				var lat := (vel - fwd * vel.dot(fwd)).length() * 3.6
				# ручник — тормоз для заноса, а не экстренный: блокируется только задняя
				# ось (через chassis.brake Godot блокировал все четыре колеса, и на
				# геймпаде это читалось как мгновенная остановка), поэтому торможение
				# умеренное, но заметное, и машина обязана остаться в движении
				check(car.speed_kmh() < _hb_speed - 8.0,
					"E1 ручник тормозит (%.1f -> %.1f км/ч)" % [_hb_speed, car.speed_kmh()])
				check(car.speed_kmh() > _hb_speed * 0.35,
					"E1b ручник не останавливает мгновенно (%.1f -> %.1f км/ч)" % [_hb_speed, car.speed_kmh()])
				check(lat > 3.0, "E2 ручник срывает в занос (боковая %.1f км/ч)" % lat)
				check(car.heading > deg_to_rad(8.0), "E3 ручник доворачивает нос (%.0f°)" % rad_to_deg(car.heading))
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)
	if _frame > 3000:
		print("TIMEOUT in phase %s at frame %d" % [_phase, _frame])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
