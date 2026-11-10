extends Node3D
# Ground contact and steps on a real VehicleBody3D suspension:
# A) on flat floor the frame does not jitter, ride height = wheel radius, the
#    collider does not dig into the ground, and the car rolls over a 0.18 m curb
#    (body clearance = 0.22 m)
# B) a 0.6 m step stops the car and does not let it pass through
# C) the car drives up the ramp instead of getting stuck
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
var _wheel_jit := 0.0
var _prev_wheel_y: Array[float] = []

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var b := BoxShape3D.new()
	b.size = Vector3(600, 2, 60); cs.shape = b
	fl.add_child(cs); add_child(fl); fl.global_position = Vector3(200, -1, 0)
	MapKit.box(self, Vector3(60, 0.10, 0), Vector3(30, 0.20, 20), Color(0.5, 0.5, 0.5))   # curb 0.20 m, like in town
	MapKit.box(self, Vector3(150, 0.3, 0), Vector3(20, 0.6, 20), Color(0.5, 0.3, 0.3))    # step 0.6 m
	MapKit.wedge(self, Vector3(220, 0.0, 0), 16, 2.4, 12, Color(0.9, 0.8, 0.2))           # ramp
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	for w in car.body.wheels: _prev_wheel_y.append(w.position.y)
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
	print("GROUND jitter=%.6f wheel_jit=%.6f flips=%d clear=%.3f ride=%.3f curb_y=%.3f ramp_y=%.2f" % [
		_jit, _wheel_jit, _flips, _min_clear, _ride_y, _climb_y, _ramp_y])
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
			if x < 40.0 and _f > 60:
				# visual wheels must not twitch: their pose comes from the physical
				# wheel node, which stands nearly still on flat floor
				for i in car.body.wheels.size():
					var wy := car.body.wheels[i].position.y
					_wheel_jit = maxf(_wheel_jit, absf(wy - _prev_wheel_y[i]))
					_prev_wheel_y[i] = wy
			if x < 40.0 and _f > 30:
				_jit_frames += 1
				var d: float = y - _prev_y
				_jit = maxf(_jit, absf(d))
				if d * _last_d < 0.0 and absf(d) > 0.0005: _flips += 1
				_last_d = d
				_ride_y = y
				# clearance between the floor and the collider bottom: negative means the box is digging into the ground
				for c in car.chassis.get_children():
					if c is CollisionShape3D:
						var sh := c.shape as BoxShape3D
						_min_clear = minf(_min_clear, y + c.position.y - sh.size.y * 0.5)
			if x > 45.0: _climb_y = maxf(_climb_y, y)
			_prev_y = y
			if x > 88.0:
				check(_jit_frames > 50, "the jitter measurement actually ran (%d frames)" % _jit_frames)
				check(_jit < 0.002, "the frame does not jitter on flat floor (%.6f m/frame)" % _jit)
				check(_flips == 0, "no sawtooth height jumps (%d sign flips)" % _flips)
				check(_min_clear > 0.02, "the collider does not dig into the floor (clearance %.3f m)" % _min_clear)
				check(_wheel_jit < 0.002, "visual wheels do not twitch (%.6f m/frame)" % _wheel_jit)
				check(absf(_ride_y - wr) < 0.05, "ride height = wheel radius (%.3f vs %.3f)" % [_ride_y, wr])
				check(_climb_y > 0.20 + wr * 0.8, "rolled over the 0.20 m curb (y=%.3f)" % _climb_y)
				_enter("B", 105.0)
		"B":
			if x > 125.0 and car.speed_kmh() < 20.0: _hold += 1
			if _hold > 30 or _pf > 600:
				# without this, «the step stopped it» would also hold for a car
				# that never reached the step
				check(x > 120.0, "the car reached the 0.6 m step (x=%.1f)" % x)
				check(x < 139.0, "the 0.6 m step stopped the car (x=%.1f)" % x)
				check(car.speed_kmh() < 20.0, "the car is pressed against it, not driving (%.1f km/h)" % car.speed_kmh())
				_enter("C", 180.0)
		"C":
			_ramp_y = maxf(_ramp_y, y)
			if y > 1.2: _hold += 1
			if _hold > 30 or _pf > 600:
				check(_ramp_y > 1.2, "drove up the ramp (max y=%.2f)" % _ramp_y)
				_finish()
	if _f > 4000:
		check(false, "timeout in phase %s: checks did not run (frame %d)" % [_phase, _f])
		_finish()
