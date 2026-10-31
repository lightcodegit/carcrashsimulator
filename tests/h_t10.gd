extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

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
		# луч длиннее, чем от спавна до пола: верх пола на 1 см ниже нуля (см. FLOOR_Y),
		# и коротким лучом в самый ноль мы бы его не видели
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5.0, 0)))
		if hit.is_empty():
			check(false, "%s spawn over ground" % id)
		else:
			# пол карты на 1 см ниже нуля (FLOOR_Y), а плиты лежат поверх него
			check(hit.position.y > MapDB.FLOOR_Y - 0.001 and hit.position.y < 0.20,
				"%s: под спавном пол (%.3f)" % [id, hit.position.y])
		for dx in [-2.0, 2.0]:
			for dz in [-1.0, 1.0]:
				var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.spawn.origin + Vector3(dx, 2.5, dz), m.spawn.origin + Vector3(dx, 0.05, dz)))
				check(h2.is_empty(), "%s spawn clear at %s,%s" % [id, dx, dz])
		m.root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
