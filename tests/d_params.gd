extends SceneTree
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _initialize() -> void:
	var ids := VehicleDB.ids()      # take the list from the DB: a new body joins the check itself
	var by_id := {}
	for id in ids:
		var p = VehicleDB.get_params(id)
		check(p != null, "%s exists" % id)
		if p == null: continue
		by_id[id] = p
		check(p.mass > 500 and p.vmax_kmh > 100, "%s sane stats" % id)
		check(p.model != "" and ResourceLoader.exists(p.model), "%s model asset exists (%s)" % [id, p.model])
		# dimensions derive from the model: they must be plausible meters
		check(p.length > 2.0 and p.length < 6.0, "%s derived length (%.2f m)" % [id, p.length])
		check(p.width > 1.2 and p.width < 2.6, "%s width (%.2f m)" % [id, p.width])
		check(p.height > 0.6 and p.height < 2.4, "%s derived height (%.2f m)" % [id, p.height])
		check(p.wheel_r > 0.2 and p.wheel_r < 0.8, "%s wheel radius (%.2f m)" % [id, p.wheel_r])
		check(p.length > p.width and p.length > p.height, "%s length is the long axis" % id)
		var cs: Vector3 = p.collider_size()
		check(cs.x > 0 and cs.y > 0 and cs.z > 0, "%s collider positive" % id)
		check(cs.y < p.height and cs.x < p.length and cs.z < p.width, "%s collider inside body (%s)" % [id, str(cs)])
		# "brakes stronger than the motor" made sense while the motors were in the
		# tire-sized range. For a car with no speed ceiling it would be untrue: braking
		# hits the grip limit, and demanding 4.5 g from it is meaningless.
		var grip_limit := CarRig.BRAKE_MAX_G * CarRig.GRAVITY
		check(p.brake_decel >= minf(p.accel_max, grip_limit),
			"%s brakes no weaker than the tires allow (%.1f vs %.1f)" % [id, p.brake_decel, minf(p.accel_max, grip_limit)])
		check(p.steer_rate_deg > 10.0 and p.grip > 1.0, "%s handling sane" % id)
	check(VehicleDB.get_params("unknown") == null, "unknown id returns null")
	check(by_id["sport"].vmax_kmh > by_id["sedan"].vmax_kmh, "sport is the fastest of ordinary cars")
	# "Infinity car" is the only one without a spec-sheet ceiling: the torque curve
	# in car_rig.gd is built as 1 - (v/vmax)^1.6, and with INF it never drops.
	check(not is_finite(by_id["infinity"].vmax_kmh), "infinity has no speed ceiling")
	check(by_id["infinity"].accel_max > by_id["sport"].accel_max, "infinity accelerates hardest")
	check(is_finite(by_id["infinity"].brake_decel), "infinity still stops like a car")
	check(by_id["sport"].accel_max > by_id["sedan"].accel_max, "sport accelerates harder")
	check(by_id["pickup"].width > by_id["sedan"].width, "pickup is the widest")
	check(by_id["sport"].height < by_id["sedan"].height, "sport is the lowest")

	# The limousine is the longest and the heaviest: that is its whole point, otherwise
	# a "stretched body" would be just a picture.
	var longest := ""
	var heaviest := ""
	for id in ids:
		if longest == "" or by_id[id].length > by_id[longest].length: longest = id
		if heaviest == "" or by_id[id].mass > by_id[heaviest].mass: heaviest = id
	check(longest == "limousine", "limousine is the longest car (%.2f m)" % by_id["limousine"].length)
	check(heaviest == "limousine", "limousine is the heaviest car (%.0f kg)" % by_id["limousine"].mass)
	check(by_id["limousine"].length > by_id["sedan"].length * 1.15,
		"limousine is at least 15%% longer than the sedan (%.2f vs %.2f m)" % [
			by_id["limousine"].length, by_id["sedan"].length])
	check(by_id["limousine"].accel_max < by_id["sedan"].accel_max,
		"limousine accelerates worse than the sedan (%.1f vs %.1f)" % [
			by_id["limousine"].accel_max, by_id["sedan"].accel_max])
	check(by_id["limousine"].nitro_accel > 0.0, "limousine has nitro too")

	# Body stretching must not touch the wheels: they are round and spin, and a
	# non-uniform scale would turn them into ovals.
	var ps: PackedScene = load("res://assets/cars/sedan.glb")
	var m: Node3D = ps.instantiate()
	DentBody.stretch_model(m, 1.45)
	var body_mi: MeshInstance3D = m.get_node("body")
	var round_ok := true
	var rear_z := 0.0
	for c in m.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var nm := String(mi.name).to_lower()
		if not nm.begins_with("wheel"): continue
		var a: AABB = mi.get_aabb()
		# the wheel spins in the Y/Z plane: its diameter must stay equal, while X is
		# the tire width — by definition not equal to the diameter
		if absf(a.size.y - a.size.z) > 0.001: round_ok = false
		if nm.contains("back"): rear_z = minf(rear_z, mi.position.z)
	check(body_mi.scale.z > 1.4, "limousine: body stretched along length (×%.2f)" % body_mi.scale.z)
	check(round_ok, "limousine: wheels stayed round")
	check(rear_z < -1.0, "limousine: rear axle moved back (z=%.2f)" % rear_z)
	m.free()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
