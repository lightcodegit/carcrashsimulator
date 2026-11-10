class_name MapVoid
extends RefCounted
# «ПУСТОТА»: бесконечное полотно во все стороны — ровная плоскость без стен,
# разметки и объектов. Пол следует за машиной по X и Z, поэтому края нет.

const FLOOR_SIZE := 40000.0

static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "Void"
	var floor_body := MapKit.box(root, Vector3(0, MapDefs.FLOOR_Y - 1.0, 0),
		Vector3(FLOOR_SIZE, 2.0, FLOOR_SIZE), Color(0.30, 0.31, 0.33),
		Basis.IDENTITY, true)
	floor_body.name = "void_floor"
	MapKit.drop_shadows(root)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)),
		"bounds": AABB(Vector3(-200000.0, -80.0, -200000.0), Vector3(400000.0, 160.0, 400000.0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false, "endless": true}}
