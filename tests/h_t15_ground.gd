extends Node3D
# Опора и ступени на настоящей подвеске VehicleBody3D:
# A) на плоском полу рама не дрожит, посадка = радиусу колеса, коллайдер не пашет землю,
#    и бордюр 0.18 м машина переезжает (просвет кузова = 0.22 м)
# B) ступень 0.6 м останавливает машину и не пускает её сквозь себя
# C) на рампу машина заезжает, а не упирается
var _fails := 0
var _f := 0
var _pf := 0
var car: CarRig
var _phase := "A"
var _prev_y := 0.0
var _last_d := 0.0
var _jit := 0.0
var _flips := 0
var _jit_frames := 0
var _min_clear := 9.9
var _ride_y := 0.0
var _climb_y := 0.0
var _ramp_y := 0.0
var _hold := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var b := BoxShape3D.new()
	b.size = Vector3(600, 2, 60); cs.shape = b
	fl.add_child(cs); add_child(fl); fl.global_position = Vector3(200, -1, 0)
	MapDB.box(self, Vector3(60, 0.09, 0), Vector3(30, 0.18, 20), Color(0.5, 0.5, 0.5))   # бордюр 0.18 м
	MapDB.box(self, Vector3(150, 0.3, 0), Vector3(20, 0.6, 20), Color(0.5, 0.3, 0.3))    # ступень 0.6 м
	MapDB.wedge(self, Vector3(220, 0.0, 0), 16, 2.4, 12, Color(0.9, 0.8, 0.2))           # рампа
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	_enter("A", -20.0)

func _enter(phase: String, x: float) -> void:
	_phase = phase
	_pf = 0
	_prev_y = 0.0
	_last_d = 0.0
	_climb_y = 0.0
	_ramp_y = 0.0
	_hold = 0
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(x, 1.0, 0)))
	Input.action_press("throttle")

func _finish() -> void:
	print("GROUND jitter=%.6f flips=%d clear=%.3f ride=%.3f curb_y=%.3f ramp_y=%.2f" % [
		_jit, _flips, _min_clear, _ride_y, _climb_y, _ramp_y])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_f += 1
	_pf += 1
	var y := car.chassis.global_position.y
	var x := car.chassis.global_position.x
	var wr := car.body.wheel_radius
	match _phase:
		"A":
			if x < 40.0 and _f > 30:
				_jit_frames += 1
				var d: float = y - _prev_y
				_jit = maxf(_jit, absf(d))
				if d * _last_d < 0.0 and absf(d) > 0.0005: _flips += 1
				_last_d = d
				_ride_y = y
				# просвет между полом и низом коллайдера: ушёл в минус — коробка пашет землю
				for c in car.chassis.get_children():
					if c is CollisionShape3D:
						var sh := c.shape as BoxShape3D
						_min_clear = minf(_min_clear, y + c.position.y - sh.size.y * 0.5)
			if x > 45.0: _climb_y = maxf(_climb_y, y)
			_prev_y = y
			if x > 88.0:
				check(_jit_frames > 50, "замер дрожи состоялся (%d кадров)" % _jit_frames)
				check(_jit < 0.002, "рама не дрожит на плоском полу (%.6f м/кадр)" % _jit)
				check(_flips == 0, "нет пилообразных скачков высоты (%d смен знака)" % _flips)
				check(_min_clear > 0.02, "коллайдер не пашет пол (просвет %.3f м)" % _min_clear)
				check(absf(_ride_y - wr) < 0.05, "посадка = радиусу колеса (%.3f против %.3f)" % [_ride_y, wr])
				check(_climb_y > 0.18 + wr * 0.8, "переехала бордюр 0.18 м (y=%.3f)" % _climb_y)
				_enter("B", 105.0)
		"B":
			if x > 125.0 and car.speed_kmh() < 20.0: _hold += 1
			if _hold > 30 or _pf > 600:
				check(x < 139.0, "ступень 0.6 м остановила машину (x=%.1f)" % x)
				check(car.speed_kmh() < 20.0, "машина упёрлась, а не едет (%.1f км/ч)" % car.speed_kmh())
				_enter("C", 180.0)
		"C":
			_ramp_y = maxf(_ramp_y, y)
			if y > 1.2: _hold += 1
			if _hold > 30 or _pf > 600:
				check(_ramp_y > 1.2, "заехала на рампу (max y=%.2f)" % _ramp_y)
				_finish()
	if _f > 4000:
		print("TIMEOUT in phase %s" % _phase)
		_finish()
