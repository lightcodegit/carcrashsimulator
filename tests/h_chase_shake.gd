extends Node3D
# Chase camera: shake is added on top of the clean position and never accumulates,
# at speed the camera does not fall behind, and after decay it returns exactly home.
var _fails := 0
var _frame := 0
var car: CarRig
var cam: CameraRig
var _ideal := Vector3.ZERO
var _max_dev := 0.0
var _dist_dev := 0.0
var _dist_n := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 200); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(1500, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	cam = CameraRig.new(); add_child(cam); cam.setup(car); cam.make_current()
	# The tree parent runs before its children, but we must read the camera
	# AFTER it updated itself this frame, otherwise we measure our own
	# one-frame skip (0.7 m at 150 km/h) instead of a chase miss.
	process_priority = 10

func _ideal_chase() -> Vector3:
	# Compute the ideal from the RENDERED position and rendered heading: chase
	# follows exactly those (see CarRig.render_transform()). Against the tick
	# machine the ideal would differ by one physics tick of travel — a metre at
	# 150 km/h — and would check the ticks, not the camera.
	var gt: Transform3D = car.render_transform()
	var fwd: Vector3 = gt.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6: fwd = fwd.normalized()
	var speed := car.chassis.linear_velocity.length()
	var back := 5.0 + minf(speed, 60.0) * 0.045
	var up := 1.9 + minf(speed, 60.0) * 0.010
	return gt.origin - fwd * back + Vector3(0, up, 0)

# Chase jitter. Measured live and against the car's RENDERED position: physics runs
# at 60 Hz, frames are drawn faster, and if the camera used the tick position it would
# miss by a metre or two of travel every frame — "lags, catches up, flickers". In
# headless no frames are drawn and there is no interpolation between ticks, so the check is skipped.
func _process(_dt: float) -> void:
	if DisplayServer.get_name() == "headless": return
	# Measure only at speed: the chase miss is proportional to one physics tick of
	# travel; at 30 km/h it is six times smaller than at 180, and at low speed the
	# check simply would not have noticed the old bug.
	if car == null or car.chassis == null or car.speed_kmh() < 100.0: return
	var gt: Transform3D = car.render_transform()
	var gap := (gt.origin - cam.global_position).dot(gt.basis.z)
	_smooth = gap if _jit.is_empty() else lerpf(_smooth, gap, 0.2)
	if _jit.size() < 600: _jit.append(absf(gap - _smooth))
	# Measure the chase distance in the same frame where the camera computes it: from
	# _physics_process the rendered car looks a tick older, and at 150 km/h that is a
	# metre of distance the camera itself never had — the check would measure ticks,
	# not the chase.
	var fwd: Vector3 = gt.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6: fwd = fwd.normalized()
	var sp := car.chassis.linear_velocity.length()
	var want_dist := Vector2(5.0 + minf(sp, 60.0) * 0.045, 1.9 + minf(sp, 60.0) * 0.010).length()
	_dist_dev = maxf(_dist_dev, absf(cam.global_position.distance_to(gt.origin) - want_dist))
	_dist_n += 1

var _jit: Array[float] = []
var _smooth := 0.0

func _physics_process(_dt: float) -> void:
	# the car is built in _ready via await: on a live renderer that lands later
	# than the needed frame, so count frames from its appearance, not scene start
	if car == null: return
	_frame += 1
	if _frame == 120:
		_ideal = _ideal_chase()
		check(cam.global_position.distance_to(_ideal) < 0.05,
			"camera converged on the chase point (%.3f m)" % cam.global_position.distance_to(_ideal))
	if _frame > 120 and _frame <= 240:
		# hold maximum shake and measure deviation from the ideal
		cam.add_trauma(1.0)
		_max_dev = maxf(_max_dev, cam.global_position.distance_to(_ideal_chase()))
	if _frame == 241:
		check(_max_dev < 0.6, "shake does not accumulate into position (max deviation %.3f m)" % _max_dev)
	if _frame > 241 and _frame <= 400:
		pass   # shake decays on its own
	if _frame == 401:
		check(cam.global_position.distance_to(_ideal_chase()) < 0.05,
			"after decay the camera returned exactly home (%.3f m)" % cam.global_position.distance_to(_ideal_chase()))
		Input.action_press("throttle")
	if _frame == 1500:
		Input.action_release("throttle")
		check(car.speed_kmh() > 100.0, "the car reached speed (%.1f km/h)" % car.speed_kmh())
		if _dist_n == 0:
			# in headless no frames are drawn and _process returns before the
			# measurements: silently comparing zero against the threshold would be "green" without a check
			print("PARTIAL: chase distance not measured (no live frames)")
		else:
			check(_dist_dev < 0.2, "at speed the camera holds its distance without lag (deviation %.2f m)" % _dist_dev)
	if _frame == 3000:
		check(car.speed_kmh() < 5.0, "the car coasted to a stop (%.1f km/h after 25 s)" % car.speed_kmh())
		if _jit.is_empty():
			print("PARTIAL: no frames were drawn (headless or window not visible) — jitter not measured")
		else:
			var mx := 0.0
			var mean := 0.0
			for g in _jit:
				mx = maxf(mx, g)
				mean += g
			mean /= float(_jit.size())
			check(mean < 0.02, "camera follows the rendered car without jitter (mean %.3f m)" % mean)
			# do not bound the maximum: during acceleration the camera by design pulls
			# further back (back grows with speed); that is not jitter — jitter is the mean deviation
			print("frames %d: mean jitter %.3f m, max %.3f m" % [_jit.size(), mean, mx])
		check(cam.global_position.distance_to(_ideal_chase()) < 0.05,
			"after stopping the camera sits exactly at the chase point (%.3f m)" % cam.global_position.distance_to(_ideal_chase()))
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
