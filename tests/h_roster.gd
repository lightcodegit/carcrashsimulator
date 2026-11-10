extends Node3D
# A driving test over ALL cars. A new body must drive right away: it may be stretched
# (limousine), have no spec top speed (endless) or different wheel geometry — and that
# is exactly when seating (suspension ray hanging above the floor), model scale, or the
# body node where dents are pressed usually break. The check iterates VehicleDB.ids(),
# so adding a car automatically adds it to this test.

const HOLD := 180            # throttle ticks (3 s)

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
	check(car.body != null and car.body.body != null, "%s: the body has a 'body' node — dents will work" % id)
	check(car.wheel_count() == 4, "%s: four wheels (%d)" % [id, car.wheel_count()])
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for _i in 20:
		await get_tree().physics_frame
	var rest_y := car.chassis.global_position.y
	check(rest_y > p.wheel_r * 0.7 and rest_y < p.wheel_r * 1.9,
		"%s: the car sits on its wheels, neither hanging nor lying on the body (y=%.2f, radius %.2f)" % [
			id, rest_y, p.wheel_r])
	Input.action_press("throttle")
	for _i in HOLD:
		await get_tree().physics_frame
	Input.action_release("throttle")
	var v := car.speed_kmh()
	# Expect not "60 km/h for everyone" but 70% of the ideal constant-acceleration run:
	# the torque curve and air drag eat a third, and a slow car's target must be lower
	# than a fast one's — otherwise the test would be a check of "the fastest passes".
	var ideal := 3.6 * p.accel_max * (HOLD / 60.0)
	var target := minf(ideal * 0.7, p.vmax_kmh * 0.9)
	print("%-10s in 3 s: %.0f km/h (target %.0f), path %.0f m, body y=%.2f, roll %.0f°" % [
		id, v, target, car.chassis.global_position.x, car.chassis.global_position.y,
		rad_to_deg(asin(clampf(car.chassis.global_basis.x.y, -1.0, 1.0)))])
	check(v >= target, "%s: accelerates at least to %.0f km/h (accel %.1f m/s²)" % [id, target, p.accel_max])
	# a third of the path at constant acceleration — margin for the torque curve and drag
	var way_min := 0.35 * 0.5 * (ideal / 3.6) * (HOLD / 60.0)
	check(car.chassis.global_position.x > way_min,
		"%s: drove %.0f m instead of standing still (expected more than %.0f m)" % [
			id, car.chassis.global_position.x, way_min])
	check(car.chassis.global_position.y < 2.0, "%s: did not fly off the ground (y=%.2f)" % [
		id, car.chassis.global_position.y])
	check(absf(car.chassis.global_basis.x.y) < 0.35, "%s: drives on wheels, not on its side" % id)
	# steering: a short input must turn the car (even a long one)
	var yaw0 := car.heading
	Input.action_press("throttle")
	Input.action_press("steer_left")
	for _i in 45:
		await get_tree().physics_frame
	Input.action_release("steer_left")
	Input.action_release("throttle")
	var dyaw := rad_to_deg(angle_difference(car.heading, yaw0))
	check(absf(dyaw) > 6.0, "%s: obeys the steering (%.1f° in 0.75 s)" % [id, dyaw])
