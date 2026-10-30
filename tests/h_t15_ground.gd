extends Node3D
# Опора и ступени: рама не дрожит на плоском полу (иначе колёса дёргаются вместе с ней),
# машина заезжает на бордюр/площадку до STEP_UP и упирается в более высокую ступень.
var _fails := 0
var _f := 0
var car: CarRig
var _prev_y := 0.0
var _jit := 0.0
var _flips := 0
var _last_d := 0.0
var _jit_frames := 0
var _climb_y := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var b := BoxShape3D.new()
	b.size = Vector3(400, 2, 60); cs.shape = b
	fl.add_child(cs); add_child(fl); fl.global_position = Vector3(150, -1, 0)
	MapDB.box(self, Vector3(60, 0.2, 0), Vector3(30, 0.4, 20), Color(0.5, 0.5, 0.5))    # площадка 0.4 м
	MapDB.box(self, Vector3(140, 0.45, 0), Vector3(20, 0.9, 20), Color(0.5, 0.3, 0.3))  # ступень 0.9 м
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	_prev_y = car.chassis.global_position.y
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_f += 1
	var y := car.chassis.global_position.y
	var x := car.chassis.global_position.x
	var d: float = y - _prev_y
	if x < 40.0 and _f > 30:
		_jit_frames += 1
		_jit = maxf(_jit, absf(d))
		if d * _last_d < 0.0 and absf(d) > 0.0005: _flips += 1
	if x > 45.0: _climb_y = maxf(_climb_y, y)
	_last_d = d
	_prev_y = y
	if _f == 900:
		Input.action_release("throttle")
		var ride: float = car.params.collider_size().y * 0.5
		check(_jit_frames > 50, "замер дрожи состоялся (%d кадров)" % _jit_frames)
		check(_jit < 0.002, "рама не дрожит на плоском полу (%.6f м/кадр)" % _jit)
		check(_flips == 0, "нет пилообразных скачков высоты (%d смен знака)" % _flips)
		check(_climb_y > 0.4 + ride * 0.9, "заехала на площадку 0.4 м (y=%.3f, нужно >%.3f)" % [_climb_y, 0.4 + ride * 0.9])
		check(x < 131.0, "упёрлась в ступень 0.9 м (x=%.1f)" % x)
		check(car.body.dent_count > 0, "ступень выше STEP_UP помяла кузов (%d)" % car.body.dent_count)
		print("GROUND jitter=%.6f flips=%d climb_y=%.3f x=%.1f dents=%d" % [_jit, _flips, _climb_y, x, car.body.dent_count])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
