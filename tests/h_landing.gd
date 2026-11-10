extends Node3D
# Report: "when the car lands really hard, it loses a huge amount of speed".
# The cause was found by measurement: suspension travel is not enough for a hard landing,
# the frame settles onto its collider, and from then on it is that collider braking the
# car, not the tyres. The check fails if the bump stop (BUMP_DAMP in CarRig) is removed:
# see the comparison in the README.
const KMPS := 3.6
const DROPS := [5.5, 8.0, 12.0]
const SPEEDS := [200.0, 280.0]
# thresholds from the measurement WITH the bump stop (the degradation without it is in brackets):
const PEAK_MAX := 85.0     # km/h per second (106 without the stop)
const LOSS_MAX := 6.0      # km/h over the first 5 landing ticks (7.2 without the stop)
const WINDOW := 4

var car: CarRig
var _fails := 0
var _cases := 0
var _worst_peak := 0.0
var _worst_loss := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fb := StaticBody3D.new()
	fb.name = "пол"
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 120); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(1100, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	for h in DROPS:
		for v in SPEEDS:
			await _drop(float(h), float(v))
	check(_cases >= DROPS.size() * SPEEDS.size(),
		"the test is not empty: landings measured %d" % _cases)
	print("worst landing: peak %.0f km/h/s, loss over 5 ticks %.2f km/h (thresholds %.0f and %.1f)" % [
		_worst_peak, _worst_loss, PEAK_MAX, LOSS_MAX])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _drop(h: float, kmh: float) -> void:
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(20.0, 1.0, 0)))
	for _i in 6:
		await get_tree().physics_frame
	# respawn itself puts the car at its ride height, so the drop height is set directly
	var p0 := car.chassis.global_position
	car.chassis.global_position = Vector3(p0.x, p0.y + h, p0.z)
	car.chassis.reset_physics_interpolation()
	car.chassis.linear_velocity = Vector3(kmh / KMPS, 0.0, 0.0)
	var air := false
	var lt := 0
	var v0 := 0.0
	var vy0 := 0.0
	var peak := 0.0
	var loss5 := 0.0
	var hist: Array[Vector3] = []
	for _i in 240:
		await get_tree().physics_frame
		var v: Vector3 = car.chassis.linear_velocity
		if not air:
			if not car._grounded: air = true
			continue
		if car._grounded:
			v0 = car.speed_kmh()
			vy0 = v.y
			hist = [v]
			lt = 0
			break
	if not air or v0 == 0.0:
		print("PARTIAL: drop %.1f m @%.0f: the flight or the touch-down was not caught" % [h, kmh])
		return
	for _i in 120:
		await get_tree().physics_frame
		lt += 1
		hist.append(car.chassis.linear_velocity)
		while hist.size() > WINDOW + 1: hist.pop_front()
		if hist.size() == WINDOW + 1:
			peak = maxf(peak, (hist[0].length() - hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0))
		if lt == 5: loss5 = v0 - car.speed_kmh()
	_cases += 1
	_worst_peak = maxf(_worst_peak, peak)
	_worst_loss = maxf(_worst_loss, loss5)
	print("drop %.1f m @%.0f km/h: touch-down at vy=%.1f, peak %.0f km/h/s (%.1f g), loss over 5 ticks %.2f km/h" % [
		h, kmh, vy0, peak, peak / 3.6 / 9.81, loss5])
	check(peak < PEAK_MAX, "the landing from %.1f m @%.0f brakes within grip (%.0f km/h/s)" % [h, kmh, peak])
	check(loss5 < LOSS_MAX, "the landing from %.1f m @%.0f does not eat speed over the first ticks (%.2f km/h)" % [h, kmh, loss5])
