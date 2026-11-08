extends SceneTree
func _init() -> void:
	var m: Dictionary = MapDB.build("endless")
	var root: Node3D = m.root
	root.name = "MapRoot"
	get_root().add_child(root)
	await process_frame
	await physics_frame
	var space := get_root().world_3d.direct_space_state
	var from: Vector3 = (m.spawn as Transform3D).origin + Vector3(0, 2.0, 0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5.0, 0)))
	if hit.is_empty(): print("RAY: empty"); quit(); return
	var col: Object = hit["collider"]
	print("RAY hit y=%.3f collider=%s pos=%s" % [hit["position"].y, col.get_class(), (col as Node3D).global_position])
	var p: Node = col
	while p != null and p.get_parent() != null and p.get_parent() != get_root(): p = p.get_parent()
	print("RAY top node: ", p.name, " (", p.get_class(), ")")
	quit()
