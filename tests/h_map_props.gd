extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

# Road plates must not lie on top of each other: two copies of the white marking in one
# plane flicker (z-fighting). The ramp and the speed bump each take their own plate.
# Static decorations and parked cars must neither sink below the surface the map draws
# nor hang above it: both are visible at eye level, and I already managed to reintroduce
# a 3 cm sink twice while changing the ground height.
func _seated(root: Node3D) -> Array:
	var bad: Array[String] = []
	var checked := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if not (c_is_prop(n)): continue
		var box := _world_aabb(n as Node3D)
		if box.size.length() < 0.05: continue
		checked += 1
		var p := n as Node3D
		var surf := MapKit.surface_y(p.global_position.x, p.global_position.z)
		if box.position.y < surf - 0.006 or box.position.y > surf + 0.04:
			bad.append("%s: bottom %.3f against surface %.3f" % [String(n.name), box.position.y, surf])
	return [bad, checked]

func c_is_prop(n: Node) -> bool:
	if n is Node3D and (n as Node3D).is_in_group(MapDefs.GROUP_PARKED): return true
	var nm := String(n.name)
	if not (nm.begins_with("city_") or nm.begins_with("kit_") or nm.begins_with("props_")): return false
	# road plates are not props but "tubs" with a skirt going 10 cm down: their bottom is
	# below the surface by design. We match by mesh path, not by name: Godot rewrites names
	# silently, and kit_roadStart cannot be told from kit_grassStart by name.
	if _is_road_plate(n): return false
	return true

func _is_road_plate(n: Node) -> bool:
	if not (n is MeshInstance3D): return false
	var mi := n as MeshInstance3D
	if mi.mesh == null: return false
	return mi.mesh.resource_path.get_file().get_basename().begins_with("road")

func _world_aabb(n: Node3D) -> AABB:
	var m := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var g: AABB = mi.global_transform * mi.get_aabb()
			if first: m = g; first = false
			else: m = m.merge(g)
		for k in c.get_children(): stack.append(k)
	return m

func _road_overlaps(root: Node3D) -> Array[String]:
	var boxes: Array[AABB] = []
	var names: Array[String] = []
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null: continue
		if not mi.mesh.resource_path.get_file().begins_with("road"): continue
		boxes.append(mi.global_transform * mi.mesh.get_aabb())
		names.append(mi.mesh.resource_path.get_file() + "@" + str(mi.global_position.x))
	var bad: Array[String] = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			# Corner and curved tiles are squares with empty sectors inside: their AABB
			# also covers the inner corner of the turn, so a "corner × straight" overlap
			# proves nothing. Real road overlap is caught by h_markings, which compares
			# the flat faces of the marking rather than the bounding boxes.
			if _curved(names[i]) or _curved(names[j]): continue
			var a := boxes[i].intersection(boxes[j])
			if a.size.x * a.size.z > 0.05:
				bad.append(names[i] + " × " + names[j])
	return bad

func _curved(name: String) -> bool:
	for k in ["Corner", "HalfCircle", "Curved", "Skew", "Split"]:
		if name.contains(k): return true
	return false

func _ready() -> void:
	await get_tree().process_frame
	for id in MapDB.ids():   # a new map goes through the same audit automatically
		var m: Dictionary = MapDB.build(id)
		var root_map: Node3D = m.root
		var spawn: Transform3D = m.spawn
		var info: Dictionary = m.info
		add_child(root_map)
		check(info.colliders > 10, "%s has colliders (%d)" % [id, m.info.colliders])
		# A ramp with a long flight only where there is room to fly: on the closed
		# circuit and in the town the jump used to end in a wall (measurements in h_ramp_run).
		var flies := id != "arena" and id != "town"
		check(info.has_ramp == flies, "%s: hill present as expected (%s)" % [id, str(info.has_ramp)])
		var ov := _road_overlaps(root_map)
		check(ov.is_empty(), "%s: road plates do not lie on top of each other (%s)" % [id, str(ov)])
		await get_tree().physics_frame
		var seat: Array = _seated(root_map)
		var sunk: Array = seat[0]
		check(seat[1] > 8, "%s: seating checked for %d objects (otherwise the check is empty)" % [id, seat[1]])
		check(sunk.is_empty(), "%s: decorations stand on the surface (%s)" % [id, str(sunk.slice(0, 4))])
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var from := spawn.origin + Vector3(0, 2.0, 0)
		# the ray is longer than the spawn-to-floor distance: the floor top sits 1 cm below
		# zero (see FLOOR_Y), so a short ray down to exactly zero would not see it
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5.0, 0)))
		if hit.is_empty():
			check(false, "%s spawn over ground" % id)
		else:
			# the map floor sits 1 cm below zero (FLOOR_Y), and the plates lie on top of it
			check(hit.position.y > MapDefs.FLOOR_Y - 0.001 and hit.position.y < 0.20,
				"%s: there is a floor under the spawn (%.3f)" % [id, hit.position.y])
		for dx in [-2.0, 2.0]:
			for dz in [-1.0, 1.0]:
				var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.spawn.origin + Vector3(dx, 2.5, dz), m.spawn.origin + Vector3(dx, 0.05, dz)))
				check(h2.is_empty(), "%s spawn clear at %s,%s" % [id, dx, dz])
		# The relief must be solid: both the hill and the bump. Without a collider an
		# invisible floor ran through them — the car did not jump, and a knocked-over prop
		# sank inside the bump and hung in the geometry (the report "objects pass through
		# bumps"). We look for the crest exactly: a ray into a plate corner proves nothing.
		for c in root_map.get_children():
			var mi := c as MeshInstance3D
			if mi == null: continue
			var n := String(mi.name)
			if not (n.contains("roadRamp") or n.contains("roadBump")): continue
			var box := _world_aabb(mi)
			# Window 0.12..0.24 m: the hill must be higher than the flat road surface (0.002)
			# but lower than the bottom of the frame collider (CarRig.CLEARANCE + 2 cm),
			# otherwise for the car it is a wall, not a hill — at 280 km/h the body grounded on the crest (h_ramp_run).
			var top := MapDefs.FLOOR_Y + 0.12
			var best := -1e9
			for fx in [0.25, 0.5, 0.75]:
				for fz in [0.25, 0.5, 0.75]:
					var p := Vector3(box.position.x + box.size.x * fx, box.end.y + 1.0,
						box.position.z + box.size.z * fz)
					var relief := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -8.0, 0)))
					if not relief.is_empty(): best = maxf(best, relief.position.y)
			check(best > top, "%s: %s is solid at its own height (best hit %.2f m, expected > %.2f)" % [
				id, n, best, top])
		m.root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
