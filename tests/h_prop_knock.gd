extends Node3D
# Knockdown props: light ones (cone, pylon) fly off on impact and barely slow the car,
# the heavy plastic barrier slows it noticeably. Separately we verify all three maps
# really contain dynamic bodies.
var _fails := 0
var _f := 0
var _pf := 0
var car: CarRig
var _prop: RigidBody3D
var _start := Vector3.ZERO
var _kind := ""
var _queue: Array[String] = ["cone", "pylon", "barrier", "bin", "planter", "bench", "sign", "hydrant"]
var _v_before := 0.0
var _got_v := false
var _got_loss := false
var _v_after := 0.0
var _max_y := 0.0
var _impacts := 0
var _settling := false
var _settle_at := 0
var _kind_at := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var b := BoxShape3D.new()
	b.size = Vector3(600, 2, 60); cs.shape = b
		# floor friction — same as map roads (zero): otherwise the test measures behavior
		# in an environment the game does not have, and a prop that never stops would look fine
	var fpm := PhysicsMaterial.new(); fpm.friction = 0.0
	fl.physics_material_override = fpm
	fl.add_child(cs); add_child(fl); fl.global_position = Vector3(200, -1.0 - 0.01 + 1.0, 0)  # floor top = FLOOR_Y
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)
	for id in MapDB.ids():
		var m: Dictionary = MapDB.build(id)
		var root_map: Node3D = m.root
		var n := 0
		for c in root_map.get_children():
			if c is RigidBody3D: n += 1
		if id != "void":
			check(n >= 5, "%s: map has something to knock down (%d dynamic bodies)" % [id, n])
		else:
			check(n == 0, "void: no dynamic bodies (%d)" % n)
		root_map.free()
	_next()

func _next() -> void:
	if _queue.is_empty():
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
		return
	_kind = _queue.pop_front()
	_kind_at = _f
	if _prop != null and is_instance_valid(_prop): _prop.queue_free()
	match _kind:
		"cone": _prop = MapProps.loose(self, "res://assets/props/cone.glb", Vector3.ZERO, MapDefs.PROP, 0.0, 3.0)
		"pylon": _prop = MapProps.loose_kit(self, "pylon", Vector3.ZERO, 0, 6.0)
		"bin": _prop = MapProps.knock_bin(self, 0.0, 0.0, 0.0)
		"planter": _prop = MapProps.knock_planter(self, 0.0, 0.0, 0.0)
		"bench": _prop = MapProps.knock_bench(self, 0.0, 0.0, 0.0)
		"sign": _prop = MapProps.knock_sign(self, 0.0, 0.0, 0.0)
		"hydrant": _prop = MapProps.knock_hydrant(self, 0.0, 0.0, 0.0)
		_: _prop = MapProps.loose_kit(self, "barrierWhite", Vector3.ZERO, 0, 25.0)
	_start = _prop.global_position
	_pf = 0
	_v_before = 0.0
	_got_v = false
	_got_loss = false
	_v_after = 0.0
	_max_y = 0.0
	_impacts = 0
	_settling = false
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-70, 1.0, 0)))
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or _prop == null: return
	_f += 1
	_pf += 1
	# release the throttle before impact: otherwise the car keeps pushing the prop and
	# accelerating, so the speed loss cannot be measured
	if car.chassis.global_position.x > -10.0: Input.action_release("throttle")
	if not _got_v and car.chassis.global_position.x > -4.0:
		_v_before = car.speed_kmh()
		_got_v = true
	_max_y = maxf(_max_y, _prop.global_position.y)
	var x := car.chassis.global_position.x
	if not _got_loss and x > 5.0:
		_v_after = car.speed_kmh()
		_got_loss = true
	if (x > 16.0 or _pf > 700) and not _settling:
		var moved := (_prop.global_position - _start).length()
		var e := _prop.global_basis.get_euler()
		var tilt := absf(e.x) + absf(e.z)
		var loss := 100.0 * (1.0 - _v_after / maxf(1.0, _v_before))
		print("%-8s v=%.0f->%.0f shift=%.2f m (%.1f,%.1f,%.1f) v_prop=%.1f height=%.2f tilt=%.2f loss=%.1f%% impacts=%d" % [
			_kind, _v_before, _v_after, moved, _prop.global_position.x, _prop.global_position.y,
			_prop.global_position.z, _prop.linear_velocity.length(), _max_y, tilt, loss, _impacts])
		check(moved > 3.0, "%s flew off on impact (shift %.2f m)" % [_kind, moved])
		check(_max_y < 4.0, "%s did not fly into the stratosphere (height %.2f m)" % [_kind, _max_y])
		if _kind == "barrier" or _kind == "planter" or _kind == "bench":
			# low and wide: the bumper hits near the center of mass, so the prop slides
			# instead of tumbling — same behavior as the barrier
			# heavy and wide: on a zero-friction road it slides rather than tumbles
			# (that is exactly why the floors have no friction — the car must not lose
			# speed from touching), but it slows the car noticeably and crawls far away
			check(loss > 4.0, "heavy %s slows the car (%.1f%%)" % [_kind, loss])
			check(moved > 8.0, "%s crawls far away (%.2f m)" % [_kind, moved])
		else:
			check(tilt > 0.3 or _max_y > 0.3, "%s is tossed or tipped (tilt %.2f, height %.2f)" % [_kind, tilt, _max_y])
			check(loss < 12.0, "light prop barely slows the car (%.1f%%)" % loss)
			check(_impacts == 0, "%s does not count as an impact (%d)" % [_kind, _impacts])
			check(car.body.dent_count == 0, "%s does not dent the body (%d)" % [_kind, car.body.dent_count])
		# 7 seconds for the prop to stop on its own. We haul the car away: it rolls
		# on inertia faster than the prop and caught up with it — the measurement would
		# show not decay but another bumper push.
		car.respawn(Transform3D(Basis.IDENTITY, Vector3(-140, 1.0, 0)))
		_settling = true
		_settle_at = _f + 420
	var rest := 0.0
	var spin := 0.0
	if _settling and _f >= _settle_at:
		rest = _prop.linear_velocity.length()
		spin = _prop.angular_velocity.length()
		print("%-8s settled: v=%.2f m/s ω=%.2f rad/s" % [_kind, rest, spin])
		check(rest < 0.6, "%s stops after the impact (%.2f m/s after 7 s)" % [_kind, rest])
		check(spin < 1.5, "%s stops spinning (%.2f rad/s)" % [_kind, spin])
		car.body.reset()
		_next()
	# Budget per prop, not per whole run: a shared 6000-frame limit silently cut
	# the last check — the test printed ALL PASS without ever reaching it.
	if _f - _kind_at > 1800 or _f > 40000:
		check(false, "%s never reached its checks (%d frames)" % [_kind, _f - _kind_at])
		print("TIMEOUT on " + _kind)
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(1)
