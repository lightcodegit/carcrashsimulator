extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _collect_props(n: Node, out: Array) -> void:
	if n is Node3D and String(n.name).ends_with(".glb"):
		out.append(n)
	for c in n.get_children():
		_collect_props(c, out)

func _local_aabb(n: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var g: AABB = mi.transform * mi.get_aabb()
		if first: merged = g; first = false
		else: merged = merged.merge(g)
	return merged

# Дорожные плиты не должны лежать друг на друге: две копии белой разметки в одной
# плоскости мерцают (z-fighting). Трамплин и лежачий полицейский занимают свою плиту.
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
			var a := boxes[i].intersection(boxes[j])
			if a.size.x * a.size.z > 0.05:
				bad.append(names[i] + " × " + names[j])
	return bad

func _ready() -> void:
	await get_tree().process_frame
	for id in ["arena", "town", "speedway"]:
		var m: Dictionary = MapDB.build(id)
		var root_map: Node3D = m.root
		var spawn: Transform3D = m.spawn
		var info: Dictionary = m.info
		add_child(root_map)
		check(info.colliders > 10, "%s has colliders (%d)" % [id, m.info.colliders])
		check(info.has_ramp or id == "town", "%s ramp expectation" % id)
		var ov := _road_overlaps(root_map)
		check(ov.is_empty(), "%s: дорожные плиты не наложены друг на друга (%s)" % [id, str(ov)])
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var from := spawn.origin + Vector3(0, 2.0, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -3.0, 0)))
		check(not hit.is_empty(), "%s spawn over ground" % id)
		check(absf(hit.position.y - 0.0) < 0.06, "%s floor top y≈0 (%.2f)" % [id, hit.position.y])
		for dx in [-2.0, 2.0]:
			for dz in [-1.0, 1.0]:
				var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.spawn.origin + Vector3(dx, 2.5, dz), m.spawn.origin + Vector3(dx, 0.05, dz)))
				check(h2.is_empty(), "%s spawn clear at %s,%s" % [id, dx, dz])
		m.root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
