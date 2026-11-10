extends Node3D
# Complaint: "behind the ramps you can glitch through them, and they are invisible from
# behind anyway." Cause found via geometry: Kenney roadRamp/roadRampLong segments are a
# shell — they have steps and sides but no bottom and no back wall (measured: 18 faces,
# 20 edges hang in the air). The frame flew into the open end and ended up INSIDE the hill
# (measured: reversing at 60 km/h the car reached x=93.7 while the hill spans x=60..120),
# and from behind the hill was fully transparent. MapKit.kit seals the collider and adds a
# visible back wall wherever the opening is larger than half a meter.
const KMPS := 3.6
const RAMP_X := 60.0        # bottom of the hill
const RAMP_LEN := 60.0      # 20 m × stretch 3.0
const HIT_TOL := 0.45       # m: how precisely the ray must hit the back-wall plane

var car: CarRig
var _ramp: MeshInstance3D
var _fails := 0
var _hits := 0
var _back_hits := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 120); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(1100, -1, 0)
	await get_tree().process_frame
	_ramp = MapKit.kit(self, "roadRampLong", Vector3(RAMP_X, 0, 0), 90, true, true, Vector3(1.0, 1.0, 3.0))
	# the body appears in the physical world only after space synchronization: without
	# these frames the rear ray does not find the hill and the check measures emptiness
	for _i in 3:
		await get_tree().physics_frame
	for c in get_children():
		if c is StaticBody3D and (c as Node3D).position == _ramp.position: _body = c as StaticBody3D
	check(_body != null, "the hill has its own collider body")
	var box: AABB = _ramp.global_transform * _ramp.get_aabb()
	check(absf(box.size.x - RAMP_LEN) < 0.6, "stretched hill: length %.1f m" % box.size.x)
	_back_rays(box)
	_drawn_back_wall(box)
	check(_back_hits == 9, "all 9 rear rays hit the hill (%d)" % _back_hits)
	await _drive_back(box)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

var _body: StaticBody3D

func _cast(from: Vector3, to: Vector3) -> Object:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return null
	_hits += 1
	return hit["collider"]

# Behind the hill — at three heights and in three lanes: a ray from a point past the end
# must hit the hill itself. With no back wall it goes inside and finds only the floor.
func _back_rays(box: AABB) -> void:
	for h in [0.6, 2.0, 4.0]:
		for lane in [-3.0, 0.0, 3.0]:
			var z: float = box.get_center().z + float(lane)
			var b := _cast(Vector3(box.end.x + 6.0, float(h), z), Vector3(box.end.x - 2.0, float(h), z))
			var hit := b == _body
			if hit: _back_hits += 1
			check(hit, "impassable from behind at height %.1f m, lane %+.1f m" % [float(h), float(lane)])

# Can the player see the back wall? Checked on drawn geometry, no pictures: the hill mesh
# must contain triangles with normal +X right at the end. Before the fix there were none —
# the hill was transparent from behind exactly where it is visible.
func _drawn_back_wall(box: AABB) -> void:
	var tris := 0
	var hi := 0.0
	var nodes: Array[Node3D] = [_ramp]
	for c in _ramp.get_children():
		if c is MeshInstance3D: nodes.append(c as Node3D)
	for n in nodes:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh == null: continue
		var xf: Transform3D = n.global_transform
		for i in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var pts := PackedVector3Array()
			if typeof(ix) == TYPE_PACKED_INT32_ARRAY and ix.size() >= 3:
				for t in range(0, ix.size(), 3):
					pts.append(v[ix[t]]); pts.append(v[ix[t + 1]]); pts.append(v[ix[t + 2]])
			else:
				pts = v
			for t in range(0, pts.size() - 2, 3):
				var a := xf * pts[t]
				var b := xf * pts[t + 1]
				var c := xf * pts[t + 2]
				var nrm := (b - a).cross(c - a)
				if nrm.length_squared() < 1e-8: continue
				if (nrm / nrm.length()).x < 0.9: continue
				var mid := (a + b + c) / 3.0
				if absf(mid.x - box.end.x) > 0.35: continue
				tris += 1
				hi = maxf(hi, maxf(a.y, maxf(b.y, c.y)) - box.position.y)
	print("drawn back wall: %d triangles, height %.1f m" % [tris, hi])
	check(tris >= 2, "the hill has a visible back wall (%d faces)" % tris)
	check(hi > 3.0, "the wall covers the end across the full height (%.1f m)" % hi)

# Functional check of the complaint: reverse into the back end. The car must bump into it
# and stay OUTSIDE the geometry (previous measurement: it reached x=93.7 inside hill 60..120).
func _drive_back(box: AABB) -> void:
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	car.respawn(Transform3D(Basis(Vector3.UP, PI), Vector3(box.end.x + 30.0, 1.0, box.get_center().z)))
	for _i in 25:
		await get_tree().physics_frame
	car.chassis.linear_velocity = Vector3(-16.0, 0.0, 0.0)
	var deepest := INF
	var inside := false
	for _i in 300:
		await get_tree().physics_frame
		var p := car.chassis.global_position
		deepest = minf(deepest, p.x)
		if p.x > box.position.x + 0.5 and p.x < box.end.x - 0.5 and p.y > box.position.y + 0.4 \
				and p.y < box.end.y - 0.2:
			inside = true
		if car.speed_kmh() < 1.0: break
	print("reverse run into the end: deepest x=%.1f with hill %.1f..%.1f, inside geometry=%s" % [
		deepest, box.position.x, box.end.x, inside])
	check(not inside, "the car does not pass through the hill's back wall (depth x=%.1f)" % deepest)
	check(deepest > box.end.x - 1.5, "the car bumped into the end instead of getting stuck (x=%.1f)" % deepest)
