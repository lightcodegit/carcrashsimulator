extends Node
# Braking: the "pedal + handbrake" combo must be stronger than either pedal alone
# (earlier, with the handbrake held the service brake was dropped, and together
# they braked WORSE than the pedal alone), and a stopped car with S held must
# first stay put, and only then start reversing.
var _fails := 0
var gm: GameManager
var _f := 0
var _phase := "roll1"
var _d := 0.0
var _d0 := 0.0
var _last := Vector3.ZERO
var _d_brake := 0.0
var _v_hold := 0.0
var _v_rev := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameContext.select("sedan", "bigcity")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	gm.car.chassis.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(0.0)),
		Vector3(0, 1.2, -140))
	await get_tree().physics_frame
	_last = gm.car.chassis.global_position
	Input.action_press("throttle")

func _stop_all() -> void:
	for a in ["throttle", "brake", "handbrake"]:
		Input.action_release(a)

func _physics_process(delta: float) -> void:
	_f += 1
	var car := gm.car
	var p := car.chassis.global_position
	_d += (p - _last).length()
	_last = p
	var v := car.speed_kmh()
	if _f > 3000:
		check(false, "run timeout in phase %s" % _phase)
		_finish()
		return
	match _phase:
		"roll1":
			if v >= 120.0:
				_stop_all()
				_phase = "brake"
				_d0 = _d
				Input.action_press("brake")
		"brake":
			if v <= 3.0:
				_d_brake = _d - _d0
				_stop_all()
				_phase = "roll2"
				Input.action_press("throttle")
		"roll2":
			if v >= 120.0:
				_stop_all()
				_phase = "bh"
				_d0 = _d
				Input.action_press("brake")
				Input.action_press("handbrake")
		"bh":
			if v <= 3.0:
				var d_bh := _d - _d0
				print("distances: pedal %.1f m, pedal+handbrake %.1f m" % [_d_brake, d_bh])
				check(d_bh < _d_brake * 0.9,
					"the combo is stronger than the pedal alone (%.1f vs %.1f m)" % [d_bh, _d_brake])
				_stop_all()
				_phase = "hold"
				_d0 = _f
		"hold":
			# with S held at a full stop: for the first 0.3 s the car must not creep back,
			# by 1.2 s reversing must have engaged
			if _f == int(_d0 + 18): _v_hold = car.chassis.linear_velocity.dot(gm.car.forward())
			if _f == int(_d0 + 72):
				_v_rev = car.chassis.linear_velocity.dot(gm.car.forward())
				check(_v_hold > -0.5, "right after stopping S holds instead of pushing back (%.2f m/s)" % _v_hold)
				check(_v_rev < -0.5, "after the hold S engages reverse (%.2f m/s)" % _v_rev)
				_finish()
			Input.action_press("brake")

func _finish() -> void:
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
