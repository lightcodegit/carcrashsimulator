extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

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
