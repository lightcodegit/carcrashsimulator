class_name MapDB
extends RefCounted
# Карты строятся кодом из ассетов Kenney Car Kit (CC0): готовые модели зданий,
# деревьев, заборов, конусов и ящиков + процедурные коробки для пола, стен и рамп.

const A := "res://assets/city/"
const P := "res://assets/props/"
const CARS := "res://assets/cars/"
const PROP := 1.3          # единый масштаб пропов относительно моделей машин

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

static func wedge(root: Node3D, origin: Vector3, length: float, height: float, width: float, color: Color) -> StaticBody3D:
	# подъёмный клин: пологая грань растёт от origin.x к origin.x+length
	var body := StaticBody3D.new()
	var pts := PackedVector3Array([
		Vector3(0, 0, -width * 0.5), Vector3(length, 0, -width * 0.5), Vector3(length, height, -width * 0.5),
		Vector3(0, 0, width * 0.5), Vector3(length, 0, width * 0.5), Vector3(length, height, width * 0.5)])
	var tris := PackedInt32Array([0, 1, 2,  3, 5, 4,  0, 1, 5,  0, 5, 3,  0, 3, 4,  0, 4, 1,  1, 4, 5,  1, 5, 2])
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for t in range(0, tris.size(), 3):
		faces.append(pts[tris[t]]); faces.append(pts[tris[t + 1]]); faces.append(pts[tris[t + 2]])
	shape.set_faces(faces)
	var cs := CollisionShape3D.new(); cs.shape = shape; cs.position = Vector3.ZERO
	body.add_child(cs)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_mat(color))
	for f in faces:
		st.add_vertex(f)
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	body.add_child(mi)
	body.position = origin
	root.add_child(body)
	return body

static func _aabb_in(n: Node3D) -> AABB:
	var merged := AABB(); var first := true
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var g: AABB = mi.transform * mi.get_aabb()
		if first: merged = g; first = false
		else: merged = merged.merge(g)
	return merged

# Модель из ассетов. solid => отдельный StaticBody3D по мировому AABB (без масштабирования формы).
static func prop(root: Node3D, path: String, pos: Vector3, sc: float, rot_y: float, solid: bool) -> Node3D:
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("MapDB: ассет не найден " + path)
		return null
	var n: Node3D = ps.instantiate()
	n.name = path.get_file()
	var local := _aabb_in(n)
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * sc
	# сажаем низ модели на pos.y: у зданий/конусов начало координат в основании,
	# а у колёс и покрышек — в центре оси, поэтому без правки они levитируют или тонут
	n.position = Vector3(pos.x, pos.y - local.position.y * sc, pos.z)
	root.add_child(n)
	if solid:
		var w: AABB = n.transform * local
		if w.size.length() > 0.05:
			var body := StaticBody3D.new()
			body.position = w.get_center()
			var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
			sh.size = w.size; cs.shape = sh; body.add_child(cs)
			var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
			root.add_child(body)
	return n

static func street_lamp(root: Node3D, pos: Vector3, side: float) -> void:
	box(root, pos + Vector3(0, 3.0, 0), Vector3(0.22, 6.0, 0.22), Color(0.18, 0.18, 0.2))
	box_vis(root, pos + Vector3(side * 0.9, 5.9, 0), Vector3(1.8, 0.16, 0.3), Color(0.22, 0.22, 0.24))
	var head := box_vis(root, pos + Vector3(side * 1.6, 5.72, 0), Vector3(0.62, 0.18, 0.34), Color(1.0, 0.93, 0.72))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.93, 0.72)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.65)
	m.emission_energy_multiplier = 1.6
	head.material_override = m

static func build(id: String) -> Dictionary:
	match id:
		"town": return _town()
		"speedway": return _speedway()
		_: return _arena()

static func _arena() -> Dictionary:
	var root := Node3D.new(); root.name = "Arena"
	box(root, Vector3(0, -1.0, 0), Vector3(200, 2, 200), Color(0.55, 0.55, 0.57))
	var wc := Color(0.35, 0.35, 0.38)
	box(root, Vector3(0, 4, -100), Vector3(200, 8, 1), wc)
	box(root, Vector3(0, 4, 100), Vector3(200, 8, 1), wc)
	box(root, Vector3(-100, 4, 0), Vector3(1, 8, 200), wc)
	box(root, Vector3(100, 4, 0), Vector3(1, 8, 200), wc)
	# разметка испытательного полигона
	for k in 20:
		box_vis(root, Vector3(-90 + k * 9.5, 0.02, 0), Vector3(5.0, 0.02, 0.4), Color(0.85, 0.85, 0.88))
	box_vis(root, Vector3(30, 0.02, 0), Vector3(0.4, 0.02, 60), Color(0.9, 0.75, 0.2))
	# столбы, отбойники, краш-блок
	box(root, Vector3(60, 4, -10), Vector3(0.8, 8, 0.8), Color(0.75, 0.7, 0.2))
	box(root, Vector3(60, 4, 10), Vector3(0.8, 8, 0.8), Color(0.75, 0.7, 0.2))
	for i in 3:
		box(root, Vector3(20 + i * 8, 0.7, -25), Vector3(0.4, 1.4, 8), Color(0.9, 0.3, 0.2))
	box(root, Vector3(82, 1, 0), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))
	box(root, Vector3(0, 4, 99.0), Vector3(60, 8, 1), Color(0.3, 0.3, 0.33))
	wedge(root, Vector3(38, 0.0, 25), 14, 3.2, 8, Color(0.95, 0.8, 0.2))
	# конусы вдоль полосы разгона и ящики на площадке
	for k in 12:
		prop(root, P + "cone.glb", Vector3(6 + k * 7.0, 0.0, 8.0), PROP, 0.0, false)
		prop(root, P + "cone.glb", Vector3(6 + k * 7.0, 0.0, -8.0), PROP, 0.0, false)
	for k in 4:
		prop(root, P + "box.glb", Vector3(70.0 + k * 1.3, 0.0, 20.0 + k * 0.4), PROP, 0.4 * k, true)
	prop(root, P + "debris-tire.glb", Vector3(88, 0.0, -18), PROP * 1.2, 0.0, true)
	prop(root, P + "debris-tire.glb", Vector3(90, 0.0, -16), PROP * 1.2, 0.7, true)
	prop(root, P + "debris-bumper.glb", Vector3(76, 0.0, -22), PROP, 0.9, true)
	prop(root, CARS + "sedan.glb", Vector3(-40, 0.0, 30), 1.0, PI * 0.5, true)   # припаркованная мишень
	prop(root, CARS + "race.glb", Vector3(-40, 0.0, 38), 1.0, PI * 0.5, true)
	for k in 6:
		street_lamp(root, Vector3(-60 + k * 24.0, 0, -60), 1.0)
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)),
		"bounds": AABB(Vector3(-110, -30, -110), Vector3(220, 70, 220)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}

static func _town() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	box(root, Vector3(0, -1.0, 0), Vector3(300, 2, 300), Color(0.42, 0.42, 0.45))
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	# улицы: главная вдоль z = -24, поперечная вдоль x = 0
	box_vis(root, Vector3(0, 0.02, -24), Vector3(300, 0.03, 14), Color(0.16, 0.16, 0.18))
	box_vis(root, Vector3(0, 0.02, 36), Vector3(300, 0.03, 12), Color(0.16, 0.16, 0.18))
	box_vis(root, Vector3(0, 0.03, -24), Vector3(300, 0.02, 0.35), Color(0.85, 0.82, 0.4))
	for k in 24:
		box_vis(root, Vector3(-140 + k * 12.0, 0.03, 36), Vector3(6.0, 0.02, 0.3), Color(0.85, 0.82, 0.4))
	# тротуары
	for z in [-32.5, -15.5, 29.0, 43.0]:
		box(root, Vector3(0, 0.1, z), Vector3(300, 0.2, 3.0), Color(0.5, 0.5, 0.52))
	# кварталы: здания из ассетов, равномерный масштаб, разная высота
	var types: Array[String] = ["building-type-a", "building-type-b", "building-type-c",
		"building-type-d", "building-type-e", "building-type-f"]
	var bz := [-78.0, -52.0, 8.0, 62.0, 92.0]
	var bx := [-108.0, -76.0, -44.0, 24.0, 56.0, 88.0, 116.0]
	for x in bx:
		for z in bz:
			if absf(x) < 14.0: continue                       # перекрёсток
			var t: String = types[rng.randi() % types.size()]
			var s := 9.0 + rng.randf() * 7.0
			var rot := float(rng.randi() % 4) * PI * 0.5
			prop(root, A + t + ".glb", Vector3(x + rng.randf_range(-3.0, 3.0), 0.0, z + rng.randf_range(-3.0, 3.0)), s, rot, true)
	# деревья, клумбы и заборы вдоль улиц
	for k in 22:
		var x := -140.0 + k * 13.5
		prop(root, A + ("tree-large.glb" if k % 2 == 0 else "tree-small.glb"), Vector3(x, 0.0, -13.0), 7.5, 0.0, true)
		prop(root, A + "tree-large.glb", Vector3(x + 6.0, 0.0, 45.5), 7.0, 0.0, true)
	for k in 8:
		prop(root, A + "planter.glb", Vector3(-100.0 + k * 28.0, 0.0, -18.5), 3.2, 0.0, true)
	for k in 10:
		prop(root, A + "fence-1x4.glb", Vector3(-120.0 + k * 26.0, 0.0, 52.0), 4.0, 0.0, true)
	# фонари и припаркованные машины
	for k in 9:
		street_lamp(root, Vector3(-120.0 + k * 30.0, 0, -33.5), 1.0)
		street_lamp(root, Vector3(-105.0 + k * 30.0, 0, 30.0), -1.0)
	var parked: Array[String] = [CARS + "sedan.glb", CARS + "truck.glb", CARS + "race.glb"]
	for k in 6:
		prop(root, parked[k % parked.size()], Vector3(-90.0 + k * 26.0, 0.0, -20.0), 1.0, PI * 0.5, true)
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-120, 1.0, -24)),
		"bounds": AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}

static func _speedway() -> Dictionary:
	var root := Node3D.new(); root.name = "Speedway"
	box(root, Vector3(280, -1.0, 0), Vector3(700, 2, 300), Color(0.32, 0.32, 0.34))
	box_vis(root, Vector3(280, 0.02, 0), Vector3(620, 0.03, 14), Color(0.14, 0.14, 0.16))
	for k in 50:
		box_vis(root, Vector3(-20 + k * 12.0, 0.03, 0), Vector3(6.0, 0.02, 0.3), Color(0.9, 0.9, 0.92))
	for side in [-1, 1]:
		box(root, Vector3(280, 0.5, side * 8.0), Vector3(620, 1.0, 0.4), Color(0.8, 0.8, 0.85))
		# отбойники с чередованием цвета
		for k in 40:
			var c := Color(0.85, 0.2, 0.18) if k % 2 == 0 else Color(0.9, 0.9, 0.92)
			box_vis(root, Vector3(-10 + k * 15.0, 0.75, side * 8.0), Vector3(15.0, 0.5, 0.42), c)
	box(root, Vector3(585, 3, 0), Vector3(1.5, 6, 30), Color(0.55, 0.2, 0.2))
	for k in 8:
		box_vis(root, Vector3(584.1, 0.6 + k * 0.7, -14 + k * 4.0), Vector3(0.2, 0.7, 4.0), Color(0.9, 0.9, 0.92) if k % 2 == 0 else Color(0.85, 0.2, 0.18))
	wedge(root, Vector3(30, 0.0, 0), 12, 2.2, 10, Color(0.95, 0.8, 0.2))
	# конусы на старте, покрышки и обломки у стены, деревья за трассой
	for k in 8:
		prop(root, P + "cone.glb", Vector3(-6 + k * 3.0, 0.0, 6.5 - k * 0.4), PROP, 0.0, false)
	for k in 5:
		prop(root, P + "debris-tire.glb", Vector3(560.0 + (k % 3) * 0.9, 0.0, -12.0 + k * 1.1), PROP * 1.2, 0.5 * k, true)
	prop(root, P + "debris-bumper.glb", Vector3(548, 0.0, 10), PROP, 0.6, true)
	prop(root, P + "debris-plate-a.glb", Vector3(552, 0.0, 12), PROP, 1.1, false)
	for k in 14:
		prop(root, A + "tree-large.glb", Vector3(-20 + k * 45.0, 0.0, -18.0), 8.0, 0.0, true)
		prop(root, A + ("tree-large.glb" if k % 2 == 0 else "tree-small.glb"), Vector3(-20 + k * 45.0, 0.0, 18.0), 8.0, 0.0, true)
	for k in 6:
		prop(root, P + "box.glb", Vector3(-20 + k * 120.0, 0.0, -11.0), PROP, 0.3, true)
		prop(root, P + "box.glb", Vector3(-20 + k * 120.0, 0.0, 11.0), PROP, 0.8, true)
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-10, 1.0, 0)),
		"bounds": AABB(Vector3(-120, -30, -160), Vector3(780, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}
