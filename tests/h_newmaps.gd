extends Node3D
# New maps. "CIRCUIT" is a closed loop: it has to converge (otherwise there is a hole or a
# step between the plates, which at 200 km/h means an impact), and under every point of the
# lane axis there must be asphalt. "ENDLESS" is about re-placing plates: the mesh and its
# collider move as a pair, otherwise the hill stays behind as an invisible collider in the
# middle of the road.

var _fails := 0
var _space: PhysicsDirectSpaceState3D

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await _circuit()
	await _endless()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _circuit() -> void:
	var m: Dictionary = MapDB.build("circuit")
	add_child(m.root)
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	var info: Dictionary = m.info
	var line: Array = info.line
	check(line.size() > 20, "the ring is built: %d axis points" % line.size())
	check(float(info.closure) < 0.05,
		"the ring closes: the ends miss each other by %.2f m" % float(info.closure))
	var where: Array[String] = []
	var gaps := 0
	var steps := 0
	var prev := 0.0
	var seen := 0
	for i in line.size():
		var a: Vector3 = line[i]
		var b: Vector3 = line[(i + 1) % line.size()]
		var span := a.distance_to(b)
		# a 1 m step: the hill's own slope (5.2 m over 60 m) gives 0.09 m per metre, while a
		# step at a plate seam would be above 0.2 — with a 4 m step a slope and a step are
		# indistinguishable
		for k in int(maxf(1.0, span)) + 1:
			var p := a.lerp(b, float(k) / maxf(span, 0.001))
			var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 4.0, p.z), Vector3(p.x, -6.0, p.z)))
			if hit.is_empty():
				gaps += 1
				continue
			var y := float(hit.position.y)
			# only the RISE: a drop at the top of the hill is exactly the ramp (the car flies),
			# while an upward step at a plate seam is what a wheel slams into
			if seen > 0 and y - prev > 0.20:
				steps += 1
				where.append("%.0f/%.0f: %.2f -> %.2f" % [p.x, p.z, prev, y])
			prev = y
			seen += 1
	check(gaps == 0, "there are no holes under the lane axis (%d rays missed)" % gaps)
	check(steps == 0, "no plate seam rises above 20 cm (%s)" % str(where))
	m.root.queue_free()
	await get_tree().physics_frame

func _endless() -> void:
	var m: Dictionary = MapDB.build("endless")
	add_child(m.root)
	await get_tree().physics_frame
	var root: Node3D = m.root
	# a hill with a collider: the mesh and the body both belong to it
	var plate: MeshInstance3D = null
	var body: StaticBody3D = null
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not String(mi.name).contains("roadRamp"): continue
		plate = mi
		for b in root.get_children():
			var sb := b as StaticBody3D
			if sb != null and sb.position.distance_squared_to(mi.position) < 0.0004: body = sb
		break
	check(plate != null and body != null, "«endless» has a hill with a collider")
	var x0 := plate.position.x
	var b0 := body.position.x
	var n0 := _plates(root)
	var moved: int = MapDB.recycle(root, x0 + 400.0, 20.0)
	check(moved > 0, "re-placement moved the plates (%d of %d)" % [moved, n0])
	check(plate.position.x > x0, "the plate moved forward (%.0f -> %.0f)" % [x0, plate.position.x])
	check(body.position.x - b0 == plate.position.x - x0,
		"its collider moved the same %.0f m as the mesh (%.0f -> %.0f)" % [
			plate.position.x - x0, b0, body.position.x])
	check(_plates(root) == n0, "the number of plates did not change (%d -> %d)" % [n0, _plates(root)])
	root.queue_free()
	await get_tree().physics_frame

func _plates(root: Node3D) -> int:
	var n := 0
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_road"): n += 1
	return n
