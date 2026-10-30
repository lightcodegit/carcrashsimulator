class_name MapDB
extends RefCounted

static func _mat(color: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = rough
	return m

static func box(root: Node3D, pos: Vector3, size: Vector3, color: Color, rot: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos; body.basis = rot
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; body.add_child(cs)
	var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
	box_vis(body, Vector3.ZERO, size, color)
	root.add_child(body)
	return body

static func box_vis(root: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new()
	bm.size = size; bm.material = _mat(color); mi.mesh = bm
	mi.position = pos
	root.add_child(mi)
	return mi

static func build(id: String) -> Dictionary:
	match id:
		"town": return _town()
		"speedway": return _speedway()
		_: return _arena()

static func _arena() -> Dictionary:
	var root := Node3D.new(); root.name = "Arena"
	box(root, Vector3(0, -0.25, 0), Vector3(200, 0.5, 200), Color(0.55, 0.55, 0.57))
	var wc := Color(0.35, 0.35, 0.38)
	box(root, Vector3(0, 4, -100), Vector3(200, 8, 1), wc)
	box(root, Vector3(0, 4, 100), Vector3(200, 8, 1), wc)
	box(root, Vector3(-100, 4, 0), Vector3(1, 8, 200), wc)
	box(root, Vector3(100, 4, 0), Vector3(1, 8, 200), wc)
	box(root, Vector3(60, 4, -10), Vector3(0.8, 8, 0.8), Color(0.75, 0.7, 0.2))
	box(root, Vector3(60, 4, 10), Vector3(0.8, 8, 0.8), Color(0.75, 0.7, 0.2))
	for i in 3:
		box(root, Vector3(20 + i * 8, 0.7, -25), Vector3(0.4, 1.4, 8), Color(0.9, 0.3, 0.2))
	box(root, Vector3(45, 1.35, 25), Vector3(14, 0.5, 8), Color(0.95, 0.8, 0.2), Basis(Vector3(0, 0, 1), -deg_to_rad(22)))
	box(root, Vector3(82, 1, 0), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))
	box(root, Vector3(0, 4, 99.0), Vector3(60, 8, 1), Color(0.3, 0.3, 0.33))
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}

static func _town() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	box(root, Vector3(0, -0.25, 0), Vector3(300, 0.5, 300), Color(0.42, 0.42, 0.45))
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	for bx in 3:
		for bz in 3:
			var h := 8.0 + rng.randf() * 14.0
			box(root, Vector3(-48 + bx * 48, h * 0.5, -48 + bz * 48), Vector3(26, h, 26), Color(0.5, 0.52, 0.56))
	for x in range(-120, 130, 40):
		box(root, Vector3(x, 3, -33), Vector3(0.5, 6, 0.5), Color(0.2, 0.2, 0.22))
	for k in 4:
		box(root, Vector3(-30 + k * 45, 0.75, -15.0), Vector3(4.2, 1.5, 1.9), Color(0.2, 0.35, 0.55))
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-120, 1.0, -24)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}

static func _speedway() -> Dictionary:
	var root := Node3D.new(); root.name = "Speedway"
	box(root, Vector3(0, -0.25, 0), Vector3(700, 0.5, 300), Color(0.32, 0.32, 0.34))
	box_vis(root, Vector3(280, 0.02, 0), Vector3(620, 0.03, 12), Color(0.15, 0.15, 0.17))
	for side in [-1, 1]:
		box(root, Vector3(280, 0.5, side * 7.0), Vector3(620, 1.0, 0.4), Color(0.8, 0.8, 0.85))
	box(root, Vector3(585, 3, 0), Vector3(1.5, 6, 30), Color(0.55, 0.2, 0.2))
	box(root, Vector3(40, 1.0, 0), Vector3(10, 0.5, 10), Color(0.95, 0.8, 0.2), Basis(Vector3(0, 0, 1), -deg_to_rad(18)))
	for k in 6:
		box(root, Vector3(-20 + k * 120, 1.2, -8.5), Vector3(0.6, 2.4, 0.6), Color(0.7, 0.7, 0.2))
		box(root, Vector3(-20 + k * 120, 1.2, 8.5), Vector3(0.6, 2.4, 0.6), Color(0.7, 0.7, 0.2))
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-10, 1.0, 0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}
