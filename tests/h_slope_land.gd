extends Node3D
# Complaint: "when the car lands on a ramp or its edge during a fall, speed drops". The
# previous checks (h_ramp_run, h_landing) measured landing on FLAT floor and rolling over
# the hill on wheels, while this case is the body falling onto the hill's slanted face or
# onto the lip of its crest. Measured before the fix: landing on the 4.4° slope at 80 km/h
# — 30 g, 1079 km/h/s and minus 79 km/h over 12 ticks: the nose goes under the crest's top
# face and the belly jams into the hill's end.
#
# The hill is a real road asset (roadRamp and roadRampLong, stretched ×3 like on the maps),
# not a wedge built in test code. We take the lane through the CENTER of the plate:
# roadRamp's geometry is offset from the origin, and at z=0 the car stands on the plate's
# edge with half its wheels in the air — in such a run the support rays do not see the
# surface and the check measures emptiness.
#
# We hold the car at the required HEIGHT ABOVE THE FACE (set Position every tick), then
# release it: otherwise the takeoff point depends on speed and at 200 km/h the car flies
# past the hill — the check would start measuring a landing beyond the ramp instead of
# onto it.

const KMPS := 3.6
const WINDOW := 4          # ticks used to measure deceleration — same as the impact detector
const LAND_TICKS := 30     # 0.5 s after the touch: window within which the loss is still the landing's doing
const PEAK_MAX := 120.0    # km/h/s: impact threshold (210) with the same margin as in h_ramp_run
const LOSS_MAX := 25.0     # km/h within the window
const ADVANCE_MIN := 5.0   # m of forward travel within the window: stopped at the hill means it jammed into it
const SINK_MIN := 1.0        # m: the run counts such a descent as a real fall
const HEIGHTS := [3.0, 6.0]
const SPEEDS := [60.0, 110.0, 200.0]
const RAMPS := ["roadRamp", "roadRampLong"]
# Not every run lands on the hill: at 200 km/h the car flies off the crest past it, and
# that is the ramp's normal behavior, not an error. So the thresholds are aggregate —
# they are also the proof that the check measures a landing onto the hill itself, not emptiness.
const ON_RAMP_MIN := 3
const HARD_MIN := 8

var car: CarRig
var _fails := 0
var _cases := 0
var _on_ramp := 0
var _hard := 0
var _worst_peak := 0.0
var _worst_loss := 0.0
var _impacts := 0

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
	car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)
	for name in RAMPS:
		# hill plate with the same stretching as on the maps: ramp(..., 3.0) and roadRampLong ×3
		var m := MapKit.kit(self, name, Vector3(60, 0, 0), 90, true, true, Vector3(1.0, 1.0, 3.0))
		MapKit.kit(self, "roadStraight", Vector3(180, 0, 0), 90, false, true)
		# the hill body appears in the physical world only after space synchronization
		for _i in 3:
			await get_tree().physics_frame
		await _sweep(name, m)
		for c in get_children():
			if c != fb and c != car: c.free()
	check(_cases >= HEIGHTS.size() * SPEEDS.size() * RAMPS.size() * 2,
		"the test is not vacuous: %d landings measured" % _cases)
	check(_on_ramp >= ON_RAMP_MIN,
		"the cars land EXACTLY on the hill: %d landings out of %d" % [_on_ramp, _cases])
	check(_hard >= HARD_MIN,
		"these are falls, not slides: %d descents ≥ %.1f m out of %d" % [_hard, SINK_MIN, _cases])
	print("landings %d, on the hill %d, with descent ≥ %.1f m %d" % [_cases, _on_ramp, SINK_MIN, _hard])
	print("worst landing: peak %.0f km/h/s, loss within window %.1f km/h (thresholds %.0f and %.1f)" % [
		_worst_peak, _worst_loss, PEAK_MAX, LOSS_MAX])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Enumeration: middle of the slope and the crest's lip, two heights, three speeds.
func _sweep(name: String, m: MeshInstance3D) -> void:
	var box: AABB = m.global_transform * m.get_aabb()
	var lane := (box.position.z + box.end.z) * 0.5
	var half: float = car._box_half.z
	for h in HEIGHTS:
		for v in SPEEDS:
			var mid := box.position.x + box.size.x * 0.55
			await _land(name, "склон", mid, float(h), float(v), lane, box)
			await _land(name, "кромка", box.end.x - half, float(h), float(v), lane, box)

# Height of the hill's slanted face at x: the plate rises from ground to crest linearly.
func _rise(box: AABB, x: float) -> float:
	var t := clampf((x - box.position.x) / maxf(box.size.x, 0.001), 0.0, 1.0)
	return box.position.y + t * (box.end.y - box.position.y)

func _land(name: String, where: String, x: float, h: float, kmh: float,
		lane: float, box: AABB) -> void:
	var tag := "%s/%s %.1f m @%.0f" % [name, where, h, kmh]
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(20.0, 1.0, lane)))
	for _i in 25:
		await get_tree().physics_frame
	# The hold is computed by the body CENTER: for roadRamp the top face at the plate's
	# start lies at ground level, and "bottom h above the face" would mean a 10 cm drop.
	for _i in 12:
		car.chassis.global_position = Vector3(x, _rise(box, x) + h, lane)
		car.chassis.linear_velocity = Vector3.ZERO
		car.chassis.angular_velocity = Vector3.ZERO
		car.chassis.reset_physics_interpolation()
		await get_tree().physics_frame
	var y0 := car.chassis.global_position.y
	car.chassis.linear_velocity = Vector3(kmh / KMPS, 0.0, 0.0)
	var air := 0
	var flew := false
	var touch := false
	var fticks := 0
	var lt := 0
	var x0 := x
	var v0 := 0.0
	var vy0 := 0.0
	var sink := 0.0
	var peak := 0.0
	var impacts0 := _impacts
	var hist: Array[Vector3] = []
	# phase 1: the flight must be sustained (3 ticks in a row without ground) — proof that
	# the car actually fell, not slid down the slope
	for _i in 120:
		await get_tree().physics_frame
		air = 0 if car._grounded else air + 1
		if air >= 3:
			flew = true
			break
	# phase 2: the touch while moving downward — at the hill's lip wheels lose ground on
	# the climb too, and at launch, while the complaint is about landing
	for _i in 240:
		if not flew or touch: break
		await get_tree().physics_frame
		fticks += 1
		var v: Vector3 = car.chassis.linear_velocity
		if car._grounded and v.y < 0.0:
			touch = true
			v0 = car.speed_kmh()
			vy0 = v.y
			x0 = car.chassis.global_position.x
			sink = y0 - car.chassis.global_position.y
			impacts0 = _impacts
			hist = [v]
	if not flew:
		print("PARTIAL: %s: no flight — the car never left the ground" % tag)
		return
	if not touch:
		print("PARTIAL: %s: no landing (air %d ticks, speed %.0f km/h)" % [
			tag, fticks, car.speed_kmh()])
		return
	# phase 3: the landing window
	for _i in LAND_TICKS + 8:
		if lt >= LAND_TICKS: break
		await get_tree().physics_frame
		var v2: Vector3 = car.chassis.linear_velocity
		lt += 1
		hist.append(v2)
		while hist.size() > WINDOW + 1: hist.pop_front()
		if hist.size() == WINDOW + 1:
			peak = maxf(peak, (hist[0].length() - hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0))
	var loss := v0 - car.speed_kmh()
	var after := car.chassis.global_position.x - x0
	var hit := _impacts - impacts0
	var on_ramp := x0 >= box.position.x and x0 <= box.end.x
	_cases += 1
	if on_ramp: _on_ramp += 1
	_worst_peak = maxf(_worst_peak, peak)
	_worst_loss = maxf(_worst_loss, loss)
	print("%-26s flight %2d tick, descent %.2f m, vy=%.1f, x=%.1f %s: loss %5.1f km/h, peak %4.0f km/h/s (%.1f g), %5.1f m within the window, impacts %d" % [
		tag, fticks, sink, vy0, x0, "ON THE HILL" if on_ramp else "past the hill", loss, peak,
		peak / 3.6 / 9.81, after, hit])
	if sink >= SINK_MIN: _hard += 1
	check(loss < LOSS_MAX, "%s: landing on %s does not eat speed (%.1f km/h in 0.5 s)" % [
		tag, where, loss])
	check(peak < PEAK_MAX, "%s: landing on %s is below the impact threshold with margin (%.0f km/h/s)" % [
		tag, where, peak])
	check(hit == 0, "%s: landing on %s registers no impact (%d)" % [tag, where, hit])
	check(after > ADVANCE_MIN, "%s: the car drove away from %s instead of jamming into it (%.1f m)" % [
		tag, where, after])
