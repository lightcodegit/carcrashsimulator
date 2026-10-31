class_name MapDB
extends RefCounted
# Карты строятся кодом из ассетов Kenney Car Kit (CC0): готовые модели зданий,
# деревьев, заборов, конусов и ящиков + процедурные коробки для пола, стен и рамп.

const A := "res://assets/city/"
const R := "res://assets/racing/"
const ROAD_Y := -0.2      # запас для сегментов без плоского полотна (у рампы полотно наклонено)
const ROAD_TOP := 0.03    # world y, на которую кладём полотно плиты
const FLOOR_Y := -0.01   # верх процедурного пола: на сантиметр НИЖЕ нуля, в котором стоят предметы
const P := "res://assets/props/"
const CARS := "res://assets/cars/"
const PROP := 1.2          # масштаб пропов: тот же, что у машины игрока (width 1.8 из 1.5)
const WALK_Y := 0.201      # верх тротуара 0.20 + миллиметр. Сбиваемые предметы — динамические:
# лишний сантиметр подъёма превращается в падение и подскок на старте
# Плоскость, на которую ставим сбиваемые предметы. Плиты приподняты над полом, и если
# ставить предмет на геометрический ноль, он оказывается внутри асфальта: solver
# выталкивает его со скоростью 0.49 м/с, и на старте конусы подпрыгивают и ложатся.
# Лучше всплыть на пару сантиметров там, где поверхность ниже (с камеры незаметно),
# чем погрузиться в неё — это физика и дрожь.
const PROP_Y := ROAD_TOP + 0.001
const GROUP_PARKED := "parked_car"

# Плоскости, на которые можно поставить предмет: (x, z) -> y. Собираются по ходу
# раскладки плит в build(), обнуляются на его старте. Без этого предмет либо внутри
# асфальта (solver его выталкивает — на старте конусы подпрыгивают), либо висящий
# над полом на толщину плиты.
static var _surfaces: Array[Dictionary] = []

# Высота, на которую нужно ставить предмет в этой точке: берётся НАИБОЛЕЕ НИЗКАЯ
# подходящая поверхность. Предмет стоит коробкой, и если центр попал на полотно, а
# углом задел бордюр, установка на бордюр оставит под ним пустоту, а втиснутый в
# бордюр ящик solver вытолкнет вниз — конус запрыгает по дороге. Низкая поверхность
# даёт крошечное пересечение с бордюром, которое машина просто переезжает.
static func surface_y(x: float, z: float) -> float:
	var got := INF
	var c := Vector3(x, 0.0, z)
	for r in _surfaces:
		if (r["rect"] as AABB).has_point(c): got = minf(got, float(r["y"]))
	return got if is_finite(got) else FLOOR_Y + 0.001

static func _mat(color: Color) -> StandardMaterial3D:
	# процедурные коробки (пол, тротуары, стены) получают то же зерно бетона, что и
	# асфальт из ассетов, иначе они выглядят бумажными на его фоне
	return Materials.concrete(color)

static func box(root: Node3D, pos: Vector3, size: Vector3, color: Color, rot: Basis = Basis.IDENTITY, no_shadow := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos; body.basis = rot
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; body.add_child(cs)
	var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
	var vis := box_vis(body, Vector3.ZERO, size, color)
	# пол бросает тень сам на себя: невидимая работа, а на слабом GPU — самая дорогая
	if no_shadow: vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var faces := PackedVector3Array()
	for t in range(0, tris.size(), 3):
		faces.append(pts[tris[t]]); faces.append(pts[tris[t + 1]]); faces.append(pts[tris[t + 2]])
	# клин выпуклый: convex-призма даёт ровное касание, а concave-трёхсетка цепляла машину
	# внутренними рёбрами и раскручивала её в воздухе на 50°
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
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

static func _mesh_faces(m: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if ix.size() >= 3:
			for t in range(0, ix.size(), 3):
				faces.append(v[ix[t]]); faces.append(v[ix[t + 1]]); faces.append(v[ix[t + 2]])
		else:
			for q in v: faces.append(q)
	return faces

static var _road_offsets := {}

# Смещение сегмента по высоте: выравниваем по его же ПОЛОТНУ, а не по верхушке меша.
#
# Плита Kenney — это корыто из трёх уровней: трава y=0.0, асфальт y=0.1, белые бордюрные
# полосы y=0.2 (замерено по геометрии roadStraightLong). Прежнее «топим на половину
# высоты» клало асфальт на y=-0.1, то есть ПОД невидимый пол карты (у того верх ровно
# y=0), и тогда сам асфальт был не виден, а белая полоса попадала точно в плоскость пола
# — отсюда и мерцание разметки, на которое жаловался игрок. Полотно поднимаем на 3 см над
# полом: этого хватает глубине буфера формата, и полосы остаются на 10 см выше асфальта,
# как настоящий поребрик.
static func _road_offset(m: Mesh) -> float:
	var key := m.resource_path
	if _road_offsets.has(key): return _road_offsets[key]
	var got := INF
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		if mat == null or mat.resource_name != "road": continue
		var v: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			# минимум по вершинам: у плоской плиты он равен её высоте, у рампы — низу въезда
			got = minf(got, p.y)
	var off := ROAD_TOP - (got if is_finite(got) else -ROAD_Y)
	_road_offsets[key] = off
	return off

# Сегмент Kenney Racing Kit. road => плита ставится по её ПОЛОТНУ (см. _road_offset).
# solid => статичный trimesh-коллайдер по геометрии сегмента (рампы и отбойники честные).
static func kit(root: Node3D, name: String, pos: Vector3, rot_y_deg: float, solid: bool, road := false) -> MeshInstance3D:
	var m: Mesh = load(R + name + ".obj")
	if m == null:
		push_warning("MapDB: сегмент трассы не найден " + name)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	# имя с координатами: одинаковые имена среди соседей Godot молча переименовывает в @MeshInstance3D@N
	mi.name = "kit_%s_%.0f_%.0f" % [name, pos.x, pos.z]
	mi.position = pos + Vector3(0, _road_offset(m) if road else 0.0, 0)
	mi.rotation.y = deg_to_rad(rot_y_deg)
	# Плоская плита (≤25 см по высоте) лежит на полу и теней на себя не бросает: тень
	# плиты падает ровно на тот же пол. Отключать ей тень — чистый выигрыш без
	# изменения картинки. Трамплин и лежачий полицейский остаются с тенями: они
	# высокие, и тень у их подножия видна.
	if road and m.get_aabb().size.y <= 0.25:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# после add_child: global_transform узла, которого ещё нет в дереве, не определён
	if road:
		_record_surfaces(mi, m)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var slab := _plate_slab(mi, m)
		if slab.is_empty():
			# полотно наклонено (рампа, лежачий полицейский): нужна честная трёхсетка
			body.position = mi.position
			body.rotation.y = mi.rotation.y
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(_mesh_faces(m))
			# без этого лучи проходят сквозь trimesh (обратные грани отсекаются), хотя
			# solver тело останавливает: клармп рамы и опора переставали видеть препятствие
			shape.backface_collision = true
			cs.shape = shape
		else:
			# Коробка по полотну вместо трёхсетки плиты. Во-первых, дешевле: на трассе
			# это снимает ~15 000 граней. Во-вторых, raised белые полосы — только
			# геометрия, а не столкновение: иначе предмет, вставленный в бордюр, solver
			# выталкивает вниз, и конусы на старте заезда подпрыгивают. Так было и
			# раньше: плиты вообще не имели коллайдера, и всё ехало по процедурному полу.
			body.position = slab["center"]
			var box := BoxShape3D.new()
			box.size = slab["size"]
			cs.shape = box
		body.add_child(cs)
		var pm := PhysicsMaterial.new(); pm.friction = 0.0
		body.physics_material_override = pm
		root.add_child(body)
	return mi

# Мировая «плита полотна»: прямоугольник горизонтальных граней поверхности road и её
# высота. Пустой словарь — полотно не плоское (рампа, лежачий полицейский).
static func _plate_slab(mi: MeshInstance3D, m: Mesh) -> Dictionary:
	var faces := _flat_faces(m, "road")
	if faces.is_empty(): return {}
	var ys := {}
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	var flat := true
	var ref := INF
	for f in faces:
		var w: Vector3 = mi.transform * f[0]
		if not is_finite(ref): ref = w.y
		elif absf(w.y - ref) > 0.002: flat = false
		for p in f:
			var q: Vector3 = mi.transform * p
			lo = Vector3(minf(lo.x, q.x), 0.0, minf(lo.z, q.z))
			hi = Vector3(maxf(hi.x, q.x), 0.0, maxf(hi.z, q.z))
	if not flat: return {}
	var bottom: float = (mi.transform * m.get_aabb().position).y
	var size := Vector3(hi.x - lo.x, ref - bottom, hi.z - lo.z)
	if size.x < 0.05 or size.y < 0.02 or size.z < 0.05: return {}
	return {"center": Vector3((lo.x + hi.x) * 0.5, bottom + size.y * 0.5, (lo.z + hi.z) * 0.5), "size": size}

# Плитаoccupies прямоугольник по всему своему отпечатку на высоте полотна. Только это и
# есть настоящая поверхность: приподнятые белые полосы коллайдера не имеют (см.
# _plate_slab), поэтому ставить предмет «на бордюр» означало бы ронять его на пол.
static func _record_surfaces(mi: MeshInstance3D, m: Mesh) -> void:
	var slab := _plate_slab(mi, m)
	if slab.is_empty(): return
	var r: Vector3 = slab["center"]
	var sz: Vector3 = slab["size"]
	var rect := AABB(Vector3(r.x - sz.x * 0.5, 0.0, r.z - sz.z * 0.5), Vector3(sz.x, 0.0, sz.z))
	_surfaces.append({"rect": rect, "y": r.y + sz.y * 0.5})

# Треугольники поверхности name_key, у которых нормаль почти вертикальна.
static func _flat_faces(m: Mesh, name_key: String) -> Array:
	var out: Array = []
	for surf in m.get_surface_count():
		var mat := m.surface_get_material(surf)
		if mat == null or mat.resource_name != name_key: continue
		var arrays := m.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tris: Array = []
		if idx.is_empty():
			var i := 0
			while i + 2 < verts.size():
				tris.append([verts[i], verts[i + 1], verts[i + 2]])
				i += 3
		else:
			for k in range(0, idx.size() - 2, 3):
				tris.append([verts[idx[k]], verts[idx[k + 1]], verts[idx[k + 2]]])
		for t in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var n := (b - a).cross(c - a)
			if absf(n.y) > 0.9 * n.length(): out.append(t)
	return out

# Трамплин занимает 10 м из 20-метровой плиты, поэтому плиту под ним не ставят:
# иначе две копии белой разметки лежат в одной плоскости и мерцают. Остаток длины
# добираем короткой плитой roadStraight.
static func ramp(root: Node3D, x: float, z: float) -> void:
	kit(root, "roadRamp", Vector3(x, 0, z), 90, true, true)
	kit(root, "roadStraight", Vector3(x + 10.0, 0, z), 90, true, true)

# Имя с координатами: "." и ":" Godot в именах узлов молча заменяет, а одинаковые имена
# среди соседей переименовывает в @Node3D@N, поэтому без координат пропы ненаходимы.
static func _prop_name(path: String, pos: Vector3) -> String:
	return "%s_%d_%d" % [path.get_file().get_basename().replace("-", "_"), int(pos.x), int(pos.z)]

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
	n.name = _prop_name(path, pos)
	var local := _aabb_in(n)
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * sc
	# сажаем низ модели на pos.y: у зданий/конусов начало координат в основании,
	# а у колёс и покрышек — в центре оси, поэтому без правки они levитируют или тонут
	n.position = Vector3(pos.x, pos.y - local.position.y * sc, pos.z)
	if path.begins_with(CARS):
		Materials.apply_tree(n, "car")
		n.add_to_group(GROUP_PARKED)
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

# Лёгкий предмет, который можно снести: визуал живёт внутри RigidBody3D, коллайдер —
# коробка по его габариту. Массу задаём явно: от неё зависит и разлёт предмета, и то,
# насколько машина замедлится. Здания, отбойники трассы, фонари и деревья остаются
# статичными — их сносом не снести, а физика на них тратиться не должна.
static func loose(root: Node3D, path: String, pos: Vector3, sc: float, rot_y: float, mass_kg: float) -> Node3D:
	pos.y = _sit(pos.y, pos.x, pos.z)
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("MapDB: ассет не найден " + path)
		return null
	var n: Node3D = ps.instantiate()
	n.name = _prop_name(path, pos)
	var local := _aabb_in(n)
	n.scale = Vector3.ONE * sc
	# центр по X/Z и низ на y = 0 тела: у конусов основание в нуле, у покрышек — центр оси
	n.position = Vector3(-local.get_center().x * sc, -local.position.y * sc, -local.get_center().z * sc)
	return _wrap_loose(root, n, local, pos, rot_y, mass_kg)

# То же самое для сегмента Kenney Racing Kit (пилоны, пластиковые отбойники).
static func loose_kit(root: Node3D, name: String, pos: Vector3, rot_y_deg: float, mass_kg: float) -> Node3D:
	pos.y = _sit(pos.y, pos.x, pos.z)
	var m: Mesh = load(R + name + ".obj")
	if m == null:
		push_warning("MapDB: сегмент не найден " + name)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "loose_" + name
	var local := m.get_aabb()
	mi.position = Vector3(-local.get_center().x, -local.position.y, -local.get_center().z)
	return _wrap_loose(root, mi, local, pos, deg_to_rad(rot_y_deg), mass_kg)

# «Ноль» в раскладке карт означает «стою на поверхности под этой точкой», а не «в
# плоскости y=0». Высоту, которую вызывающий выбрал сам (тротуар — WALK_Y), не трогаем.
static func _sit(y: float, x: float, z: float) -> float:
	return y if y > 0.005 else surface_y(x, z)

static func _wrap_loose(root: Node3D, visual: Node3D, local: AABB, pos: Vector3, rot_y: float, mass_kg: float) -> RigidBody3D:
	var body := LooseProp.new()
	body.mass = mass_kg
	body.continuous_cd = true     # иначе на 200 км/ч конус пролетает сквозь машину
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0             # на скользком предмет уезжает, не успев перевернуться
	pm.bounce = clampf(6.0 / mass_kg, 0.08, 0.20)    # лёгкое отскакивает сильнее, тяжёлое почти не прыгает
	body.physics_material_override = pm
	body.rotation.y = rot_y
	body.position = pos
	body.add_child(visual)
	var w: AABB = visual.transform * local
	if w.size.length() > 0.05:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = w.size
		cs.shape = sh
		cs.position = w.get_center()
		body.add_child(cs)
		body.height_m = w.size.y
	body.setup_tumble()
	root.add_child(body)
	return body

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
	_surfaces.clear()
	match id:
		"town": return _town()
		"speedway": return _speedway()
		_: return _arena()

static func _arena() -> Dictionary:
	var root := Node3D.new(); root.name = "Arena"
	box(root, Vector3(0, FLOOR_Y - 1.0, 0), Vector3(200, 2, 200), Color(0.55, 0.55, 0.57), Basis.IDENTITY, true)
	var wc := Color(0.35, 0.35, 0.38)
	box(root, Vector3(0, 4, -100), Vector3(200, 8, 1), wc)
	box(root, Vector3(0, 4, 100), Vector3(200, 8, 1), wc)
	box(root, Vector3(-100, 4, 0), Vector3(1, 8, 200), wc)
	box(root, Vector3(100, 4, 0), Vector3(1, 8, 200), wc)
	# испытательная петля: outbound по z = 0, разворот, return по z = -20
	for k in 5:
		if k != 3:   # плиту x=20..40 занял трамплин
			kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, 5), 90, true, true)
	kit(root, "roadHalfCircle", Vector3(60, 0, 5), 90, true, true)
	for k in 5:
		if k != 1:   # плиту x=-20..0 занял лежачий полицейский
			kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, -15), 90, true, true)
	ramp(root, 20.0, 5.0)
	kit(root, "roadBump", Vector3(-20, 0, -15), 90, true, true)
	for k in 8:
		kit(root, "grass", Vector3(-40.0 + k * 10.0, 0.02, 16), 90, false)
		kit(root, "grass", Vector3(-40.0 + k * 10.0, 0.02, -26), 90, false)
	# отбойники по внешнему и внутреннему краю петли
	for k in 10:
		kit(root, "barrierWhite", Vector3(-40.0 + k * 10.0, 0, 4.9), 0, true)
		kit(root, "barrierWhite", Vector3(-40.0 + k * 10.0, 0, -26.1), 0, true)
	for k in 4:
		kit(root, "barrierRed", Vector3(44.0 + k * 2.5, 0, 4.9), 0, true)
	# боксы, трибуны и обвес полигона
	kit(root, "pitsGarage", Vector3(-60, 0, 9.5), 0, true)
	kit(root, "pitsOffice", Vector3(-60, 0, 21.0), 0, true)
	kit(root, "tent", Vector3(-72, 0, 10), 0, true)
	for k in 2:
		kit(root, "grandStand", Vector3(-20.0 + k * 11.0, 0, -34.0), 0, true)
	kit(root, "overheadLights", Vector3(-6, 0, 6.3), 90, true)
	for k in 3:
		kit(root, "lightRed", Vector3(-30.0 + k * 30.0, 0, 8.5), 0, true)
		kit(root, "flagCheckers", Vector3(-24.0 + k * 30.0, 0, 6.6), 0, false)
	kit(root, "billboard", Vector3(70, 0, -34.0), 0, true)
	kit(root, "radarEquipment", Vector3(78, 0, 12.0), 0, true)
	# слалом из пилонов и краш-блок в конце прямой; пилоны сбиваются
	for k in 5:
		loose_kit(root, "pylon", Vector3(-14.0 + k * 6.0, 0, 2.6 * (1 if k % 2 == 0 else -1)), 0, 6.0)
	box(root, Vector3(82, 1, 0), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))
	# сносимый хлам: конусы у краш-блока, покрышки и ящик у боксов, обломки на обратной прямой
	for k in 4:
		loose(root, P + "cone.glb", Vector3(66.0 + k * 3.0, 0, -3.0 + 1.5 * float(k)), PROP, 0.0, 3.0)
	for k in 3:
		loose(root, P + "debris-tire.glb", Vector3(-70.0 + k * 2.0, 0, 6.5), PROP, 0.0, 10.0)
	loose(root, P + "box.glb", Vector3(-50.0, 0, 7.5), PROP, 0.6, 15.0)
	loose(root, P + "debris-bumper.glb", Vector3(10.0, 0, -18.0), PROP, 0.3, 9.0)
	loose(root, P + "debris-plate-a.glb", Vector3(34.0, 0, -18.5), PROP, 1.1, 12.0)
	for k in 4:
		kit(root, "treeLarge", Vector3(-80.0 + k * 50.0, 0, 40.0), 0, true)
		kit(root, "treeSmall", Vector3(-60.0 + k * 50.0, 0, -50.0), 0, true)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)),
		"bounds": AABB(Vector3(-110, -30, -110), Vector3(220, 70, 220)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}

static func _town() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	box(root, Vector3(0, FLOOR_Y - 1.0, 0), Vector3(300, 2, 300), Color(0.42, 0.42, 0.45), Basis.IDENTITY, true)
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	# улицы из плит Racing Kit: главная вдоль z = -24 и вторая вдоль z = 36
	for k in 14:
		# первую плиту заняла стартовая арка: её разметка легла бы ровно на разметку плиты
		if k > 0: kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, -19), 90, true, true)
		kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, 41), 90, true, true)
	kit(root, "roadStart", Vector3(-140, 0, -17.7), 90, true, true)   # арка на въезде в город
	for k in 24:
		box_vis(root, Vector3(-140 + k * 12.0, 0.03, -24), Vector3(6.0, 0.02, 0.3), Color(0.85, 0.82, 0.4))
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
	# фонари из набора трассы и припаркованные машины
	for k in 9:
		kit(root, "lightColored", Vector3(-120.0 + k * 30.0, 0, -33.5), 0, true)
		kit(root, "lightColored", Vector3(-105.0 + k * 30.0, 0, 30.0), 180, true)
	for k in 5:
		kit(root, "billboard", Vector3(-100.0 + k * 50.0, 0, -36.0), 0, true)
		kit(root, "fenceStraight", Vector3(-110.0 + k * 40.0, 0, 27.0), 0, true)
	# пластиковые отбойники и пилоны сбиваются: первые тяжёлые и тормозят машину, вторые нет
	for k in 6:
		loose_kit(root, "barrierWhite", Vector3(-90.0 + k * 30.0, WALK_Y, -15.5), 0, 25.0)
		loose_kit(root, "pylon", Vector3(-80.0 + k * 30.0, 0, 20.0), 0, 6.0)
	# хлам на улицах: конусы у перекрёстка, покрышки и ящики во дворе, мусор на тротуаре
	for k in 5:
		loose(root, P + "cone.glb", Vector3(-8.0 + k * 4.0, 0, -22.0 + 1.2 * float(k % 3)), PROP, 0.0, 3.0)
	for k in 3:
		loose(root, P + "debris-tire.glb", Vector3(40.0 + k * 2.0, WALK_Y, 29.0), PROP, 0.0, 10.0)
	loose(root, P + "box.glb", Vector3(-40.0, WALK_Y, -32.5), PROP, 0.8, 15.0)
	loose(root, P + "box.glb", Vector3(96.0, 0, 43.0), PROP, 2.2, 15.0)
	loose(root, P + "debris-plate-a.glb", Vector3(20.0, 0, 34.0), PROP, 0.4, 12.0)
	loose(root, P + "debris-bumper.glb", Vector3(-60.0, WALK_Y, -15.5), PROP, 1.7, 9.0)
	var parked: Array[String] = [CARS + "sedan.glb", CARS + "truck.glb", CARS + "race.glb"]
	for k in 6:
		prop(root, parked[k % parked.size()], Vector3(-90.0 + k * 26.0, 0.0, -20.0), 1.0, PI * 0.5, true)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-120, 1.0, -24)),
		"bounds": AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}

static func _speedway() -> Dictionary:
	var root := Node3D.new(); root.name = "Speedway"
	box(root, Vector3(280, FLOOR_Y - 1.0, 0), Vector3(700, 2, 300), Color(0.32, 0.32, 0.34), Basis.IDENTITY, true)
	# полотно из плит Kenney Racing Kit (10 x 20), дорога вдоль +X, центр по z = 0
	kit(root, "roadStart", Vector3(-20, 0, 6.3), 90, true, true)          # стартовая арка
	for k in 31:
		if k != 1 and k != 12:   # эти плиты заняли трамплин и лежачий полицейский
			kit(root, "roadStraightLong", Vector3(k * 20.0, 0, 5), 90, true, true)
	# обочины-газон у старта и пит-лейна
	for k in 14:
		kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, 16), 90, false)
		kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, -6), 90, false)
	# отбойники вдоль всей трассы по обе стороны
	for k in 64:
		kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, 4.9), 0, true)
		kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, -6.13), 0, true)
	ramp(root, 20.0, 5.0)   # трамплин: поднимается вдоль +X на 2.7 м
	# пит-лейн, трибуны и обвес трассы
	for k in 4:
		kit(root, "pitsGarage", Vector3(60.0 + k * 11.0, 0, 9.5), 0, true)
	kit(root, "pitsOffice", Vector3(106, 0, 9.5), 0, true)
	for k in 3:
		kit(root, "grandStand", Vector3(150.0 + k * 11.0, 0, -16.5), 180, true)
	kit(root, "tent", Vector3(120, 0, 14), 0, true)
	kit(root, "tentLong", Vector3(190, 0, 14), 0, true)
	for k in 5:
		kit(root, "billboard", Vector3(240.0 + k * 60.0, 0, -13.0), 0, true)
		kit(root, "lightRed", Vector3(260.0 + k * 60.0, 0, 8.0), 0, true)
	for k in 4:
		kit(root, "flagCheckers", Vector3(2.0, 0, 6.6 + k * 2.2), 0, false)
		kit(root, "fenceStraight", Vector3(300.0 + k * 10.0, 0, 9.0), 0, true)
	kit(root, "overheadLights", Vector3(-6, 0, 6.3), 90, true)
	kit(root, "radarEquipment", Vector3(420, 0, 10.5), 0, true)
	kit(root, "roadBump", Vector3(240, 0, 5), 90, true, true)   # вместо плиты k=12
	for k in 10:
		kit(root, "treeLarge", Vector3(-10.0 + k * 65.0, 0, -20.0), 0, true)
		# пилоны стоят прямо на полотне — их и предполагается сбивать
		loose_kit(root, "pylon", Vector3(-14.0 + k * 22.0, 0, 3.2 * (1 if k % 2 == 0 else -1)), 0, 6.0)
	# конусы вдоль пит-лейна и стопки покрышек у боксов
	for k in 6:
		loose(root, P + "cone.glb", Vector3(70.0 + k * 5.0, 0, 7.6), PROP, 0.0, 3.0)
	for k in 4:
		loose(root, P + "debris-tire.glb", Vector3(118.0 + k * 1.8, 0, 12.0), PROP, 0.0, 10.0)
	loose(root, P + "box.glb", Vector3(140.0, 0, 12.5), PROP, 1.3, 15.0)
	loose(root, P + "debris-bumper.glb", Vector3(300.0, 0, -3.0), PROP, 0.7, 9.0)
	# финиш: бетонная стена краш-теста
	box(root, Vector3(585, 3, 0), Vector3(1.5, 6, 30), Color(0.55, 0.2, 0.2))
	# красные отбойники перед финишной стеной сбиваются, сама стена — нет
	for k in 5:
		loose_kit(root, "barrierRed", Vector3(578.0, 0, -2.4 + k * 1.2), 0, 25.0)   # внутри полотна: по краю опора была разная
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-10, 1.0, 0)),
		"bounds": AABB(Vector3(-120, -30, -160), Vector3(780, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}
