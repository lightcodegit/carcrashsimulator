extends Node3D
# Steering at high speed (the complaint «cars don't steer properly at high speed»).
# The front wheel angle is capped by the allowed lateral acceleration, and the old
# 1.07 g ceiling without a lower bound at 180 km/h left half a degree: the wheel
# turns, the car goes straight. What is measured here is what the player feels: how
# fast the heading changes, how far the car pulls aside, whether it straightens
# after the wheel is released (otherwise a turn is just a skid) and whether the
# turn itself eats speed.
const SPEEDS := [80.0, 140.0, 200.0, 260.0]
const CARS := ["sport", "sedan", "limousine"]
const HOLD := 60             # ticks of full steering (1 s)
const COAST := 60            # ticks after release
const YAW_MIN := 15.0        # °/s: a minimum that was unreachable under the old ceiling
const T03_MIN := 6.0         # °: heading after 0.3 s — what the player expects from «it steers»
const CORRIDOR_MAX := 90.0   # m of road at a 30° turn at 200 km/h
const RESIDUAL_MAX := 15.0   # °: how much the heading creeps after the wheel is released
const SPEED_KEEP := 0.8      # the speed fraction that must be kept
const SIDE_MIN := 6.0        # m: lateral drift within a second

var _fails := 0
var car: CarRig
var _queue: Array[String] = []
var _t := 0
var _yaw0 := 0.0
var _z0 := 0.0
var _v0 := 0.0
var _yaw_hold := 0.0
var _yaw_03 := 0.0
var _corridor := 0.0
var _max_side := 0.0
var _x0 := 0.0
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
		# CarRig.build adds nodes instead of rebuilding them: a second car in the
		# same rig would leave both chassis in the tree
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
	if _t == 18:
		_yaw_03 = absf(rad_to_deg(angle_difference(car.heading, _yaw0)))
	if _corridor == 0.0 and absf(rad_to_deg(angle_difference(car.heading, _yaw0))) >= 30.0:
		_corridor = absf(car.chassis.global_position.x - _x0)
	if _t == HOLD:
		_yaw_hold = rad_to_deg(angle_difference(car.heading, _yaw0))
		Input.action_release("steer_left")
	if _t < HOLD + COAST:
		_step()
		return
	Input.action_release("throttle")
	var yaw_rate := absf(_yaw_hold)                 # ° per second of holding the wheel
	var residual := absf(rad_to_deg(angle_difference(car.heading, _yaw0)) - _yaw_hold)
	var kept := car.speed_kmh() / maxf(_v0, 1.0)
	var drift := absf(car.chassis.global_position.z - _z0)
	print("%-14s heading %+6.1f° in 1 s, %+5.1f° after release, drift %5.1f m, slide %.1f m/s, exit %.0f km/h (%.0f%%)" % [
		_tag, _yaw_hold, residual, drift, _max_side, car.speed_kmh(), kept * 100.0])
	check(yaw_rate >= YAW_MIN,
		"%s: full steering for 1 s turns the car by at least %.0f° (turn %.1f°)" % [_tag, YAW_MIN, yaw_rate])
	check(drift >= SIDE_MIN, "%s: the car pulled aside by %.1f m instead of going straight" % [_tag, drift])
	check(residual <= RESIDUAL_MAX,
		"%s: the heading keeps turning %.1f° after release — that is a skid, not a turn" % [_tag, residual])
	check(kept >= SPEED_KEEP, "%s: the turn must not eat speed (%.0f%% of %.0f km/h)" % [
		_tag, kept * 100.0, _v0])
	_run()
