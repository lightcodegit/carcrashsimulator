extends Node3D
# Crash scenario: a sedan accelerates into a concrete wall. Checks impact registration,
# stopping, dents appearing and persisting, wall solidity and the cost of an impact.
var _fails := 0
var _frame := 0
var car: CarRig
var _impacts: Array[float] = []
var _impact_ms := 0.0
var _def_at_crash := 0.0
const WALL_X := 60.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 30); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(WALL_X, 4, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	car.impact.connect(func(s: float, _p: Vector3, _n: Vector3) -> void: _impacts.append(s))

func _physics_process(_dt: float) -> void:
	# the car is built in _ready via await: on a live renderer that lands later
	# than the needed frame, so count frames from its appearance, not scene start
	if car == null: return
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame == 750:
		Input.action_release("throttle")
		var b := car.body
		check(_impacts.size() > 0, "impact registered (%s)" % str(_impacts))
		check(_impacts.size() > 0 and _impacts[0] > 40.0 and _impacts[0] < 170.0,
			"impact speed plausible (%s)" % str(_impacts))
		check(car.speed_kmh() < 8.0, "the car came to a stop (%.1f km/h)" % car.speed_kmh())
		check(car.chassis.global_position.x < WALL_X, "chassis did not enter the wall (%.2f)" % car.chassis.global_position.x)
		check(b.dent_count > 0, "dents appeared (%d)" % b.dent_count)
		_def_at_crash = b.deformation()
		check(_def_at_crash > 0.5, "body visibly deformed (%.2f m)" % _def_at_crash)
		check(b.max_depth > 0.05 and b.max_depth < b.height * 0.45,
			"dent depth within body bounds (%.3f m at height %.2f)" % [b.max_depth, b.height])
		var thru := 0; var below := 0; var bad := 0
		for i in b.vertex_count():
			var w := b.vertex_world(i)
			if not w.is_finite(): bad += 1
			if w.x > WALL_X + 0.6: thru += 1
			if w.y < -0.05: below += 1
		check(bad == 0, "all vertices finite (%d)" % bad)
		check(thru == 0, "body did not pass through the wall (%d)" % thru)
		check(below == 0, "body did not sink under the floor (%d)" % below)
		pass
	if _frame == 1250:
		var b := car.body
		check(absf(b.deformation() - _def_at_crash) < 1e-6,
			"dents do not heal (%.4f -> %.4f)" % [_def_at_crash, b.deformation()])
		check(car.speed_kmh() < 4.0, "the car is stationary (%.1f km/h)" % car.speed_kmh())
		# The cost of an impact is measured by rebuilding the body mesh. Timing it with an
		# inter-frame clock is unreliable: under background load it false-fired (61–83 ms on a
		# "max frame" while the real rebuild takes a few milliseconds). Take the median of three
		# hits, and at the very end — so an extra dent does not disturb the "dents do not heal" check.
		var costs: Array[float] = []
		for i in 3:
			var t0 := Time.get_ticks_usec()
			b.apply_impact(car.chassis.global_position + Vector3(0, 0.25, 0.6 + i * 0.35), Vector3(0, 0, 1), 120.0)
			costs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		costs.sort()
		_impact_ms = costs[1]
		check(_impact_ms < 40.0, "body rebuild after impact (%.2f ms, all %s)" % [_impact_ms, str(costs)])
		print("CRASH impacts=%s dents=%d depth=%.3f m deform=%.2f m impact=%.2f ms" % [
			str(_impacts), b.dent_count, b.max_depth, b.deformation(), _impact_ms])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
