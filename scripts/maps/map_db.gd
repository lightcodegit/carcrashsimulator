class_name MapDB
extends RefCounted
# Карты строятся кодом из ассетов Kenney Car Kit (CC0): готовые модели зданий,
# деревьев, заборов, конусов и ящиков + процедурные коробки для пола, стен и рамп.

const A := "res://assets/city/"
const R := "res://assets/racing/"
# Верх процедурного пола — он же физическая земля: по нему едут машина и предметы,
# потому что у плоских плит коллайдера нет (свой коллайдер дал бы уступ в 4 см на
# каждом стыке, и на 150 км/ч колесо цепляет его: после прыжка машину бросало вбок,
# а скорость падала со 150 до 0 км/ч за 1.3 с). Пол на 1 см ниже нуля, в котором
# стоят декоративные покрытия (трава 0.02), — иначе они под полом и не видны.
const FLOOR_Y := -0.01
# world y полотна: 2 мм над физической землёй — ровно настолько, чтобы не мерцало
# и не было заметно глазу. Своего коллайдера у плиты нет (см. выше).
const ROAD_TOP := FLOOR_Y + 0.002
const ROAD_Y := -0.2      # запас для сегментов без плоского полотна (у рампы полотно наклонено)
# Высота «лежачего полицейского». Низ коллайдера рамы — CarRig.CLEARANCE плюс 2 см
# зазора, то есть 0.24 м: всё, что выше, для машины уже стена. При масштабе 0.35 (верх
# 0.30 м) на 280 км/ч кузов упирался в гребень и складывался — тот самый «удар на
# рампе»; с 0.22 м верх в 0.19 м остаётся под коллайдером, и горка проезжается.
const BUMP_Y := 0.22
const P := "res://assets/props/"
const CARS := "res://assets/cars/"
const PROP := 1.2          # масштаб пропов: тот же, что у машины игрока (width 1.8 из 1.5)
# Верх тротуара 0.20 + миллиметр. Сбиваемые предметы динамические: лишний сантиметр
# подъёма превращается в падение и подскок на старте заезда.
const WALK_Y := 0.201
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

# SEGMENTY Kenney — это оболочки: у рампы есть ступени и два боковых торца, а дна и
# задней стенки НЕТ (замер по геометрии roadRamp: 18 граней, 20 рёбер висят в воздухе).
# Машина, оказавшаяся сзади трамплина, входила в открытый торец и пропадала внутри
# (жалоба «сзади трамплинов можно пройти сквозь них, и вообще они невидимые сзади»), а
# жёсткая посадка на дальний край проваливалась сквозь грань. kit() добавляет недостающие
# плоскости: дно — всегда, торцы — там, где сегмент на них обрывается.
static func _needs_closure(name: String) -> bool:
	return name.begins_with("roadRamp") or name == "roadBump" or name == "ramp"

static func _closure(m: Mesh) -> Array[Dictionary]:
	var ab := m.get_aabb()
	var x0 := ab.position.x
	var x1 := ab.end.x
	var y0 := ab.position.y
	var z0 := ab.position.z
	var z1 := ab.end.z
	var verts := _mesh_vertices(m)
	var have := _face_planes(m)
	# дно уводим на 2 см НИЖЕ подола: совпадая с его плоскостью, оно начинает мерцать
	# вместе с разметкой (тот же класс ошибки, что чинила h_t21)
	var ybot := y0 - 0.02
	var out: Array[Dictionary] = []
	_add_quad(out, have, Vector3(x0, ybot, z0), Vector3(x1, ybot, z0), Vector3(x1, ybot, z1),
		Vector3(x0, ybot, z1), Vector3(0.0, -1.0, 0.0), "grass", false)
	# высоты торцов — по вершинам самого сегмента: у рампы задний торец обрывается на 2.7 м,
	# у бугра оба сходят на нет и стенка не нужна
	for side in [[z0, _height_at(verts, z0), Vector3(0.0, 0.0, -1.0)],
			[z1, _height_at(verts, z1), Vector3(0.0, 0.0, 1.0)]]:
		var z := float(side[0])
		var top := float(side[1])
		if top - y0 < 0.05: continue
		# стенку начинаем от подола сегмента, а не от дна: дно уводим ниже, и видимая
		# грань с такой кромкой уже торчала бы под асфальтом (h_t10 считает это провисанием)
		_add_quad(out, have, Vector3(x0, y0, z), Vector3(x1, y0, z),
			Vector3(x1, top, z), Vector3(x0, top, z), side[2] as Vector3, "grey",
			top - y0 > 0.5)
	return out

static func _mesh_vertices(m: Mesh) -> PackedVector3Array:
	var all := PackedVector3Array()
	for i in m.get_surface_count():
		for p in (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			all.append(p)
	return all

static func _height_at(verts: PackedVector3Array, z: float) -> float:
	var top := -INF
	for p in verts:
		if absf(p.z - z) < 0.06: top = maxf(top, p.y)
	return top if is_finite(top) else 0.0

# Плоскости уже имеющихся граней: не рисовать вторую совпадающую стенку — это ещё
# и мерцание на том же самом месте.
static func _face_planes(m: Mesh) -> Array[Dictionary]:
	var planes: Array[Dictionary] = []
	var faces := _mesh_faces(m)
	for t in range(0, faces.size() - 2, 3):
		var a := faces[t]; var b := faces[t + 1]; var c := faces[t + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-8: continue
		planes.append({"n": n.normalized(), "c": (a + b + c) / 3.0})
	return planes

static func _add_quad(out: Array[Dictionary], have: Array[Dictionary], a: Vector3, b: Vector3,
		c: Vector3, d: Vector3, want: Vector3, mat_name: String, show: bool) -> void:
	var tri := PackedVector3Array()
	# порядок вершин подбираем по направлению нормали: грань обязана смотреть наружу
	if (b - a).cross(c - a).dot(want) >= 0.0:
		tri.append_array([a, b, c, a, c, d])
	else:
		tri.append_array([a, c, b, a, d, c])
	var mid := (a + c) * 0.5
	for p in have:
		if absf((p["n"] as Vector3).dot(want)) > 0.99 and (p["c"] as Vector3).distance_to(mid) < 1.0:
			return
	var nrm := PackedVector3Array()
	for t in range(0, tri.size() - 2, 3):
		var f := (tri[t + 1] - tri[t]).cross(tri[t + 2] - tri[t]).normalized()
		for k in 3: nrm.append(f)
	out.append({"tri": tri, "n": nrm, "mat": mat_name, "show": show})

static func _scaled_faces(faces: PackedVector3Array, sc: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in faces: out.append(Vector3(p.x * sc.x, p.y * sc.y, p.z * sc.z))
	return out

static func _uv_at(m: Mesh, p: Vector3) -> Vector2:
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var u: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		if u.size() != v.size(): continue
		for k in v.size():
			pts.append(v[k]); uvs.append(u[k])
	var best := 0
	var bd := INF
	for k in pts.size():
		var d := pts[k].distance_squared_to(p)
		if d < bd: bd = d; best = k
	return uvs[best] if bd < INF else Vector2.ZERO

static func _mat_by_name(m: Mesh, mat_name: String) -> Material:
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		if mat != null and mat.resource_name == mat_name: return mat
	var first := m.surface_get_material(0)
	return first if first != null else StandardMaterial3D.new()

# Задняя стенка горки — отдельным узлом-оболочкой в локальных координатах сегмента, а не
# новым мешем у самого сегмента: три теста и сама MapDB узнают плиту по resource_path её
# меша (h_t10, h_t21), и подмена меша на собранный в коде потеряла бы эту идентичность.
# Дно сюда не идёт: его не видно никогда.
static func _closure_mesh(m: Mesh, close: Array[Dictionary]) -> ArrayMesh:
	var tri := PackedVector3Array()
	var nrm := PackedVector3Array()
	var mat: Material = null
	for e in close:
		if not bool(e["show"]): continue
		if mat == null: mat = _mat_by_name(m, String(e["mat"]))
		tri.append_array(e["tri"] as PackedVector3Array)
		nrm.append_array(e["n"] as PackedVector3Array)
	if tri.size() < 3: return null
	var uv := PackedVector2Array()
	for p in tri: uv.append(_uv_at(m, p))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = tri
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	var cm := ArrayMesh.new()
	cm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	cm.surface_set_material(0, mat)
	return cm

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
# sc — множитель геометрии сегмента. Нужен потому, что у Kenney «лежачий
# полицейский» в 10 раз выше настоящего: как горка он безобиден, а как твёрдое
# препятствие на пути машины превращается в стену (замер: на 164 км/ч скорость падала
# до 13, а исход заезда менялся от сдвига в четыре тика). Масштаб по Y делает из него
# честный бугор. Коллайдер получает ТО ЖЕ запечённое в грани масштабирование: у тела
# масштаба нет, и без этого машина летала бы по воздуху над видимой горкой.
static func kit(root: Node3D, name: String, pos: Vector3, rot_y_deg: float, solid: bool, road := false,
		sc := Vector3.ONE) -> MeshInstance3D:
	var m: Mesh = load(R + name + ".obj")
	if m == null:
		push_warning("MapDB: сегмент трассы не найден " + name)
		return null
	# Замыкаем только те сегменты, по которым едут: рампы и бугры. Пропы и плиты — свои
	# оболочки, им это не нужно, а лишняя грань у дерева сбила бы проверку «декорации стоят
	# на поверхности» (h_t10) своим нижним краем
	var close: Array[Dictionary] = []
	if solid and _needs_closure(name): close = _closure(m)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var drawn := false
	for e in close:
		if bool(e["show"]): drawn = true
	# Лишняя поверхность нужна только там, где открытая грань действительно видна: задняя
	# стенка рампы в полметра и выше. Плоским плитам и отбойникам хватает замкнутого
	# коллайдера — вызовов отрисовки это не добавляет
	if drawn:
		var shell := MeshInstance3D.new()
		shell.name = "shell"
		shell.mesh = _closure_mesh(m, close)
		mi.add_child(shell)
	# имя с координатами: одинаковые имена среди соседей Godot молча переименовывает в @MeshInstance3D@N
	mi.name = "kit_%s_%.0f_%.0f" % [name, pos.x, pos.z]
	mi.scale = sc
	mi.position = pos + Vector3(0, (_road_offset(m) if road else 0.0) * sc.y, 0)
	mi.rotation.y = deg_to_rad(rot_y_deg)
	# Плоская плита (≤25 см по высоте) лежит на полу и теней на себя не бросает: тень
	# плиты падает ровно на тот же пол. Отключать ей тень — чистый выигрыш без
	# изменения картинки. Трамплин и лежачий полицейский остаются с тенями: они
	# высокие, и тень у их подножия видна.
	if road and m.get_aabb().size.y * sc.y <= 0.25:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# после add_child: global_transform узла, которого ещё нет в дереве, не определён
	if road:
		_record_surfaces(mi, m)
	if solid:
		# Коллайдер нужен только наклонным сегментах (рампа, лежачий полицейский):
		# у плоской плиты полотно совпадает с физической землёй, и свой коллайдер дал
		# бы уступ в 4 см на каждой границе — на 150 км/ч колесо цепляет его и машину
		# бросает вперёдь (замерено: 150 → 0 км/ч за 1.3 с после прыжка).
		var body := StaticBody3D.new()
		body.position = mi.position
		body.rotation.y = mi.rotation.y
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		var faces := _mesh_faces(m)
		for e in close:
			faces.append_array(e["tri"] as PackedVector3Array)
		shape.set_faces(_scaled_faces(faces, sc))
		# без этого лучи проходят сквозь trimesh (обратные грани отсекаются), хотя
		# solver тело останавливает: клармп рамы и опора переставали видеть препятствие
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		var pm := PhysicsMaterial.new(); pm.friction = 0.0
		body.physics_material_override = pm
		root.add_child(body)
	return mi

# Мировая «плита полотна»: прямоугольник горизонтальных граней поверхности road и её
# высота. Пустой словарь — полотно не плоское (рампа, лежачий полицейский). Нужно это
# только для посадки предметов: полотно плиты — тот визуальный уровень, над которым
# предмет не должен ни проваливаться, ни висеть.
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

# Плита занимает прямоугольник по всему своему отпечатку на высоте полотна. Только это и
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

# Трамплин занимает плиту целиком (10 м, а растянутый — две), поэтому плиту под ним не
# ставят: иначе две копии белой разметки лежат в одной плоскости и мерцают. Остаток
# длины добираем короткой плитой roadStraight.
#
# И горка, и бугор обязаны быть твёрдыми: без коллайдера машина едет по невидимому полу
# на уровне земли (замер: на трассе при горке в 2.7 м кузов поднимается лишь до 0.38 м),
# а сбитый предмет проваливается сквозь геометрию и зависает внутри бугра — ровно то, на
# что жалуются как «объекты проходят сквозь бугры». Trimesh по граням самой модели, а не
# коробка: коробка поставила бы ступеньку, о которую машина теряла скорость.
static func ramp(root: Node3D, x: float, z: float, stretch := 1.0) -> void:
	# stretch тянет горку вдоль направления движения (мировая ось X — это местная Z
	# сегмента после поворота на 90°) при той же высоте. Крутая горка в 15° на 60 Гц
	# физике не проезжается: за тик полотно поднимается на 0.31 м, а ход подвески 0.20 м,
	# колёса не успевают, и нос кузова упирается в наклонную грань. Замер по трамплину
	# 2.6 м: до 235 км/ч машина летит, на 250 уже останавливается в нуле и складывается —
	# то же самое на любых скоростях выше. Растянутая втрое горка даёт 0.10 м за тик.
	kit(root, "roadRamp", Vector3(x, 0, z), 90, true, true, Vector3(1.0, 1.0, stretch))
	kit(root, "roadStraight", Vector3(x + 10.0 * stretch, 0, z), 90, false, true)

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
	pos.y = _sit(pos.y, pos.x, pos.z)
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
	# Дороги и пол заведомо с нулевым трением: машина не должна терять скорость от
	# любого касания (отдельная просьба игрока), а Bullet перемножает трение пары —
	# 1.0 предмета о 0.0 пола даёт те же нули. Без гашения сбитый конус уезжал и не
	# останавливался никогда. Режим REPLACE, потому что в проекте default_linear_damp
	# стоит в 0, а ADD прибавлял бы ноль к значению материала, а не к нашему.
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 1.6
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 2.4
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

# Список карт. Тесты полигонов (h_t10, h_t21, h_t24) перебирают его, поэтому новая карта
# обязана появиться здесь — иначе она останется непроверенной.
static func ids() -> Array[String]:
	return ["arena", "town", "speedway", "circuit", "endless"]

static func build(id: String) -> Dictionary:
	_surfaces.clear()
	match id:
		"town": return _town()
		"speedway": return _speedway()
		"circuit": return _circuit()
		"endless": return _endless()
		_: return _arena()


# ------------------------------------------------------------ замкнутое кольцо «ГОНКА»
# Трасса собирается Курсором по тайлам Kenney, а не расстановкой на глаз: у каждого
# тайла полоса идёт по местной +Z, поэтому якорь (куда встанет узел, куда денется полоса
# и как повернёт курсор) измерен по геометрии модели. Правые повороты чередуются
# 25/15/25/15 — при таком чередовании прямоугольник сходится при любых длинах
# противоположных прямых (условие замыкания: L1-L3 = R2+R3-R1-R4, L2-L4 = R3+R4-R1-R2),
# так что между плитами нет ни ступеньки, ни щели.
const TILE_ANCHOR := {
	"roadStraightLong": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadStartPositions": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadRampLong": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadStraight": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 10.0), "turn": 0, "len": 10.0},
	# у арки полоса шире тайла: её асфальт по местной X лежит 2.54..10.06, центр 6.3
	"roadStart": {"in": Vector2(6.3, 0.0), "out": Vector2(6.3, 20.0), "turn": 0, "len": 20.0},
	# бугор — 20 м по ходу, гребень 0.9 м: на трассе он сжат так же, как на других картах
	"roadBump": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadCornerLarge": {"in": Vector2(5.0, 0.0), "out": Vector2(20.0, 15.0), "turn": 1, "len": 15.0},
	"roadCornerLarger": {"in": Vector2(5.0, 0.0), "out": Vector2(30.0, 25.0), "turn": 1, "len": 25.0},
}
# Курс в осях (x, z): куда едет машина. 0 = −Z, 1 = +X, 2 = +Z, 3 = −X.
const TRAV := {0: Vector2(0.0, -1.0), 1: Vector2(1.0, 0.0), 2: Vector2(0.0, 1.0), 3: Vector2(-1.0, 0.0)}
# Куда смотрит местная +X тайла (поперёк полосы) при том же курсе: у поворота входной
# край лежит по местной X, и без этого якоря стык с прямой расходился бы на полтайла.
const SIDE := {0: Vector2(-1.0, 0.0), 1: Vector2(0.0, -1.0), 2: Vector2(1.0, 0.0), 3: Vector2(0.0, 1.0)}
# Поворот узла, дающий этот курс: местная +Z должна смотреть на курс, отсюда 180-90h.
const ROT := {0: 180.0, 1: 90.0, 2: 0.0, 3: -90.0}

# AABB узла, который ещё не в дереве: global_transform вне дерева возвращает единичный,
# а отпечаток трассы нужен прямо во время сборки.
static func _track_debug() -> bool:
	return OS.get_environment("TRACKDEBUG") != ""

static func _placed_aabb(mi: MeshInstance3D) -> AABB:
	var a: AABB = mi.get_aabb()
	var sc: Vector3 = mi.scale
	return Transform3D(Basis(Vector3.UP, mi.rotation.y), mi.position) * AABB(a.position * sc, a.size * sc)

class TrackCursor:
	var root: Node3D
	var pos := Vector3.ZERO
	var h := 1
	var box := AABB()
	var line: Array[Vector3] = []      # ось полосы по точкам — по ней проверяется замыкание
	var spawn := Transform3D.IDENTITY
	var _tiles := 0

	func tile(name: String, solid := false, sc := Vector3.ONE) -> MeshInstance3D:
		var d: Dictionary = TILE_ANCHOR[name]
		var tr: Vector2 = TRAV[h]
		var sd: Vector2 = SIDE[h]
		var pin: Vector2 = d["in"]
		var outp: Vector2 = d["out"]
		var rot: float = ROT[h]
		# точка полосы -> мир: местная X идёт по SIDE, местная Z — по TRAV. Множитель
		# тайла обязан попасть и в шаг курсора: растянутая втрое рамка занимает 60 м, и
		# без этого кольцо не сходится (замер: расходился ровно на 90 м).
		var dx := (outp.x - pin.x) * sc.x
		var dz := (outp.y - pin.y) * sc.z
		var off := Vector3(sd.x * dx + tr.x * dz, 0.0, sd.y * dx + tr.y * dz)
		var node := pos - Vector3(sd.x * pin.x * sc.x + tr.x * pin.y * sc.z, 0.0,
			sd.y * pin.x * sc.x + tr.y * pin.y * sc.z)
		var mi: MeshInstance3D = MapDB.kit(root, name, node, rot, solid, true, sc)
		line.append(Vector3(pos.x, 0.0, pos.z))
		if MapDB._track_debug():
			print("  %s: узел (%.1f, %.1f) rot %.0f -> полоса (%.1f, %.1f), курс %d" % [
				name, node.x, node.z, rot, pos.x, pos.z, h])
		if mi != null:
			var g: AABB = MapDB._placed_aabb(mi)
			box = g if _tiles == 0 else box.merge(g)
			_tiles += 1
		pos += off
		if int(d["turn"]) == 1:
			h = (h + 1) % 4
		return mi

	func place(name: String, side_off: float, along: float, rot_extra: int, solid: bool) -> void:
		var tr: Vector2 = TRAV[h]
		var sd: Vector2 = SIDE[h]
		var node := pos + Vector3(tr.x * along + sd.x * side_off, 0.0, tr.y * along + sd.y * side_off)
		MapDB.kit(root, name, node, ROT[(h + rot_extra + 8) % 4], solid, false)

const SEGMENTS := 90             # 1800 м плит «бесконечности» в строю; переставляем по 20 м

static func _endless() -> Dictionary:
	# «БЕСКОНЕЧНОСТЬ» — дорога, которая не кончается: лента плит лежит на одном большом
	# полотнище, а по мере того, как машина уходит вперёд, MapDB.recycle() переносит
	# самые задние плиты и отбойники за спину в начало хвоста. Полотно не двигается,
	# ездок не чувствует шва, и трасса теоретически длиннее, чем сядет терпения.
	var root := Node3D.new(); root.name = "Endless"
	box(root, Vector3(0, FLOOR_Y - 1.0, 0), Vector3(40000.0, 2.0, 240.0),
		Color(0.34, 0.37, 0.33), Basis.IDENTITY, true)
	var t := TrackCursor.new()
	t.root = root
	t.pos = Vector3(-40.0, 0.0, 0.0)
	t.h = 1
	for k in SEGMENTS:
		var name := "roadStraightLong"
		match k % 9:
			3: name = "roadRampLong"
			6: name = "roadBump"
			7: name = "roadStartPositions"
		var sc := Vector3.ONE
		var solid := false
		if name == "roadRampLong":
			sc = Vector3(1.0, 1.0, 3.0)
			solid = true
		elif name == "roadBump":
			sc = Vector3(1.0, BUMP_Y, 1.0)
			solid = true
		t.tile(name, solid, sc)
	# отбойники вдоль всей ленты: они тоже уезжают вперёд вместе с плитами
	for side in [1, -1]:
		for k in int(SEGMENTS * 2.0):
			# узел плиты на «бесконечности» стоит на z = +5 (полоса по оси z = 0), поэтому
			# отбойники в тех же смещениях, что и на трассе: иначе один из них лежит на
			# асфальте и цепляется боком
			kit(root, "barrierWall", Vector3(-40.0 + k * 10.0, 0, 4.9 if side > 0 else -6.13),
				0, true, false)
	# стартовое кольцо прожекторов и щит — чтобы первый взгляд был на трассу, а не в пустоту
	for k in 4:
		kit(root, "lightRed", Vector3(-30.0 + k * 40.0, 0, 6.5), 0, true, false)
		kit(root, "billboard", Vector3(10.0 + k * 60.0, 0, -17.0), 0, true, false)
	# сносимый хлам у обочин: предметам известно только плоское полотно, поэтому они
	# стоят на месте, а лента плит уходит вперёд — на «бесконечности» их сбивают один раз
	for k in 6:
		loose(root, P + "cone.glb", Vector3(20.0 + k * 3.0, 0, 6.9), PROP, 0.0, 3.0)
	for k in 4:
		loose(root, P + "debris-tire.glb", Vector3(120.0 + k * 3.0, 0, -6.9), PROP, 0.0, 10.0)
	loose(root, P + "box.glb", Vector3(200.0, 0, 7.2), PROP, 1.1, 15.0)
	loose(root, P + "debris-bumper.glb", Vector3(260.0, 0, -7.2), PROP, 0.8, 9.0)
	drop_shadows(root)
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-20.0, 1.0, 0.0)),
		"bounds": AABB(Vector3(-200, -60, -120), Vector3(40000, 120, 240)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true, "endless": true}}

# Переставка плит «бесконечности»: то, что осталось за спиной, уезжает в хвост ленты.
# Плита и её коллайдер переносятся парой — у kit() тело стоит ровно в той же точке, что
# и меш, и если двигать только меш, горка уедет вперёд, а невидимый коллайдер останется
# позади (ровно тот класс bugs, из-за которого предметы проваливались сквозь бугры).
static func recycle(root: Node3D, car_x: float, spacing: float) -> int:
	var bodies := {}
	for c in root.get_children():
		var sb := c as StaticBody3D
		if sb != null:
			bodies["%.1f|%.1f" % [sb.position.x, sb.position.z]] = sb
	var plates: Array[Node3D] = []
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_road"): plates.append(mi)
	if plates.is_empty(): return 0
	var step := float(plates.size()) * spacing
	var moved := 0
	for mi in plates:
		if mi.position.x + spacing >= car_x - 120.0: continue
		mi.position.x += step
		var key := "%.1f|%.1f" % [mi.position.x - step, mi.position.z]
		var body: StaticBody3D = bodies.get(key)
		if body != null:
			body.position.x += step
		moved += 1
	return moved

static func _circuit() -> Dictionary:
	var root := Node3D.new(); root.name = "Circuit"
	var t := TrackCursor.new()
	t.root = root
	t.pos = Vector3(-140.0, 0.0, -60.0)
	t.h = 1
	# Нижняя прямая — 280 м: арка, места старта, разгон и длинный трамплин с посадочной
	# плитой. Трамплин взят растянутым (×3): 5.2 м высоты на 60 м — это 5°, и прыжок
	# остаётся прыжком даже на 300 км/ч, а не ударом носом в грань (замер на арена-рампе:
	# 15° машина начинала складываться с 250 км/ч).
	t.tile("roadStart")
	for k in 3:
		t.tile("roadStraightLong")
	t.tile("roadStartPositions")
	for k in 3:
		t.tile("roadStraightLong")
	t.tile("roadRampLong", true, Vector3(1.0, 1.0, 3.0))
	t.tile("roadStraight", false, Vector3(1.0, 1.0, 6.0))
	# Развороты чередуются 25/15/25/15 и противоположные прямые равны (280 и 280,
	# 120 и 120) — при таком чередовании кольцо сходится точно, без ступеньки на стыке.
	t.tile("roadCornerLarger")
	for k in 6:
		t.tile("roadStraightLong")
	t.tile("roadCornerLarge")
	# старт — за аркой на нижней прямой, курсом вдоль неё
	t.spawn = Transform3D(Basis(Vector3.UP, 0.0), Vector3(-118.0, 1.0, -60.0))
	for k in 13:
		t.tile("roadStraightLong")
	t.tile("roadBump", true, Vector3(1.0, BUMP_Y, 1.0))
	t.tile("roadCornerLarger")
	for k in 6:
		t.tile("roadStraightLong")
	t.tile("roadCornerLarge")
	var f: AABB = t.box
	# зрительский пояс: внешние отбойники по периметру асфальта, внутренние — по краю
	# инфилда, трибуны и боксы на прямой, мачты, тенты, флаги и деревья за пределами.
	# прямоугольник ОСЕЙ четырёх прямых (не отпечаток тайлов: углы выступают за полосу на
	# радиус разворота). Внутренний пояс отставляется от оси на 8 м — на 3 м за кромку
	# асфальта, иначе отбойник лежит на полосе и машина бьётся о него на горке.
	_decorate(root, f, AABB(Vector3(-125.0, 0.0, -60.0), Vector3(290.0, 0.0, 110.0)))
	if OS.get_environment("TRACKDEBUG") != "":
		var a0: Vector3 = t.line[0]
		var a1: Vector3 = t.pos
		print("незамыкание: (%.2f, %.2f) при курсе %d (старт был курс 1)" % [
			a1.x - a0.x, a1.z - a0.z, t.h])
		print("кольцо: отпечаток x=%.1f..%.1f z=%.1f..%.1f y=%.2f..%.2f тайлов %d" % [
			f.position.x, f.end.x, f.position.z, f.end.z, f.position.y, f.end.y, t._tiles])
	var floor_y := -0.4
	box(root, Vector3((f.position.x + f.end.x) * 0.5, floor_y, (f.position.z + f.end.z) * 0.5),
		Vector3(f.size.x + 90.0, 0.8, f.size.z + 90.0), Color(0.42, 0.46, 0.4), Basis.IDENTITY, true)
	return {"root": root, "spawn": t.spawn,
		"bounds": AABB(f.position - Vector3(40, 40, 40), f.size + Vector3(80, 100, 80)),
		# closure — незамыкание в метрах, line — ось полосы: по ним h_t32 проверяет кольцо
		"info": {"colliders": root.get_child_count(), "has_ramp": true,
			"closure": t.pos.distance_to(t.line[0]), "line": t.line}}

# Мелкий пояс (отбойники, газоны, мачты, щиты, тенты) теней не бросает: на новых картах
# таких узлов сотни, и каждый стоил места в проходе теней — живьём кадр на кольце вышел
# 35 мс против 10 мс на трассе. Тень от отбойника высотой 0.7 м на картинке не видна.
const NO_SHADOW_PREFIX := ["barrier", "grass", "light", "billboard", "tent", "fence",
	"flag", "rail", "pylon", "road"]

static func drop_shadows(root: Node3D) -> void:
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: continue
		var stem := String(mi.name).trim_prefix("kit_")
		for pre in NO_SHADOW_PREFIX:
			if stem.begins_with(pre):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break

# Обвес кольца. Координаты — по отпечатку трассы: внешний пояс в 6 м от асфальта,
# внутренний — вдоль инфилда, всё остальное за пределами полосы, чтобы не стоять под
# колёсами (на арена-рампе именно отбойники в коридоре приземления давали «удар на рампе»).
static func _decorate(root: Node3D, f: AABB, infill: AABB) -> void:
	var out_x0 := f.position.x - 6.0
	var out_x1 := f.end.x + 6.0
	var out_z0 := f.position.z - 6.0
	var out_z1 := f.end.z + 6.0
	for k in int((out_x1 - out_x0) / 10.0) + 1:
		kit(root, "barrierWall", Vector3(out_x0 + k * 10.0, 0, out_z0), 0, true, false)
		kit(root, "barrierWall", Vector3(out_x0 + k * 10.0, 0, out_z1), 0, true, false)
	for k in int((out_z1 - out_z0) / 10.0) + 1:
		kit(root, "barrierWall", Vector3(out_x0, 0, out_z0 + k * 10.0), 90, true, false)
		kit(root, "barrierWall", Vector3(out_x1, 0, out_z0 + k * 10.0), 90, true, false)
	# инфилд: внутренний ряд отбойников и слалом из пилонов — между ними можно
	# остановиться и осмотреть кузов, на полосу они не выходят
	var in_x0 := infill.position.x + 8.0
	var in_x1 := infill.end.x - 8.0
	var in_z0 := infill.position.z + 8.0
	var in_z1 := infill.end.z - 8.0
	for k in int((in_x1 - in_x0) / 10.0) + 1:
		kit(root, "barrierWhite", Vector3(in_x0 + k * 10.0, 0, in_z0), 0, true, false)
		kit(root, "barrierWhite", Vector3(in_x0 + k * 10.0, 0, in_z1), 0, true, false)
	for k in 8:
		loose_kit(root, "pylon", Vector3(in_x0 + 10.0 + k * 12.0, 0, (in_z0 + in_z1) * 0.5
			+ 6.0 * (1.0 if k % 2 == 0 else -1.0)), 0, 6.0)
	# трибуны, боксы и щиты за нижней прямой
	for k in 3:
		kit(root, "grandStandCovered", Vector3(-90.0 + k * 26.0, 0, out_z0 - 8.0), 0, true, false)
	kit(root, "pitsOffice", Vector3(30.0, 0, out_z0 - 8.0), 0, true, false)
	for k in 4:
		kit(root, "billboard", Vector3(out_x0 + 20.0 + k * 40.0, 0, out_z1 + 8.0), 0, true, false)
	# мачты освещения вдоль обеих прямых и радара у финиша
	for k in 6:
		kit(root, "lightRedDouble", Vector3(-120.0 + k * 50.0, 0, out_z0 - 3.0), 0, true, false)
		kit(root, "lightRed", Vector3(-120.0 + k * 50.0, 0, out_z1 + 3.0), 180, true, false)
	kit(root, "radarEquipment", Vector3(out_x0 + 8.0, 0, in_z0 + 8.0), 0, true, false)
	# арка над стартом — без коллайдера, как roadStart на трассе: под ней проезжают,
	# и луч тесту она перекрывает полосу
	kit(root, "overheadRound", Vector3(-132.0, 0, -55.0), 90, false, false)
	for k in 4:
		kit(root, "tentLong", Vector3(in_x0 + 6.0 + k * 26.0, 0, in_z1 - 6.0), 0, true, false)
	# деревья и газон за внешним поясом: силуэт полигона, а не препятствие
	for k in 12:
		var gx := out_x0 - 14.0 + k * 28.0
		kit(root, "grass", Vector3(gx, 0.02, out_z0 - 14.0), 90, false, false)
		kit(root, "treeLarge", Vector3(gx + 8.0, 0, out_z1 + 16.0), 0, true, false)
	for k in 5:
		loose(root, P + "cone.glb", Vector3(-60.0 + k * 4.0, 0, in_z0 + 4.0), PROP, 0.0, 3.0)
	for k in 3:
		loose(root, P + "debris-tire.glb", Vector3(60.0 + k * 3.0, 0, in_z1 - 4.0), PROP, 0.0, 10.0)
	Materials.apply_tree(root, "prop")

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
		kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, 5), 90, false, true)
	kit(root, "roadHalfCircle", Vector3(60, 0, 5), 90, false, true)
	for k in 5:
		if k != 1:   # плиту x=-20..0 занял лежачий полицейский
			kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, -15), 90, false, true)
	# Трамплина на арене больше нет: он стоит в 70 м от стены, а с 2.6-метровой горки
	# машина летит дальше (замеры: 140 км/ч — 70 м полёта, 210 км/ч — 190 м). Прыжок
	# кончался ударом о стену или вылетом за карту, и игрок видел это как «удар на рампе».
	# Лежачий полицейский остаётся: с него приземление внутри полигона на любой скорости
	# (замер: 210 км/ч — 2.4 м подъёма, 70 тиков полёта, ноль ударов).
	kit(root, "roadBump", Vector3(-20, 0, -15), 90, true, true, Vector3(1, BUMP_Y, 1))
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
	# краш-блок — в конце обратной прямой: на исходящей он стоял ровно под коридором
	# взлёта, и прыжок через горку кончался ударом о него
	box(root, Vector3(82, 1, -20), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))
	# сносимый хлам: конусы у краш-блока, покрышки и ящик у боксов, обломки на обратной прямой.
	# Конусы стояли на исходящей прямой между горкой и стеной — то есть ровно в коридоре
	# приземления; убраны к блоку, который переехал на обратную прямую.
	for k in 4:
		loose(root, P + "cone.glb", Vector3(79.0 + k * 3.0, 0, -23.0 + 1.5 * float(k)), PROP, 0.0, 3.0)
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
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}

static func _town() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	box(root, Vector3(0, FLOOR_Y - 1.0, 0), Vector3(300, 2, 300), Color(0.42, 0.42, 0.45), Basis.IDENTITY, true)
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	# улицы из плит Racing Kit: главная вдоль z = -24 и вторая вдоль z = 36
	for k in 14:
		# первую плиту заняла стартовая арка: её разметка легла бы ровно на разметку плиты
		if k > 0: kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, -19), 90, false, true)
		kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, 41), 90, false, true)
	kit(root, "roadStart", Vector3(-140, 0, -17.7), 90, false, true)   # арка на въезде в город
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
	kit(root, "roadStart", Vector3(-20, 0, 6.3), 90, false, true)          # стартовая арка
	for k in 31:
		# k=1 и k=2 заняли трамплин (x=20..50) с его посадочной плитой, k=12 — полицейский
		if k != 1 and k != 2 and k != 12:
			kit(root, "roadStraightLong", Vector3(k * 20.0, 0, 5), 90, false, true)
	# обочины-газон у старта и пит-лейна
	for k in 14:
		kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, 16), 90, false)
		kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, -6), 90, false)
	# отбойники вдоль всей трассы по обе стороны
	for k in 64:
		kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, 4.9), 0, true)
		kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, -6.13), 0, true)
	ramp(root, 20.0, 5.0, 3.0)   # трамплин: 2.6 м высоты на 30 м длины
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
	kit(root, "roadBump", Vector3(240, 0, 5), 90, true, true, Vector3(1, BUMP_Y, 1))   # вместо плиты k=12
	for k in 10:
		kit(root, "treeLarge", Vector3(-10.0 + k * 65.0, 0, -20.0), 0, true)
		# пилоны стоят прямо на полотне — их и предполагается сбивать. Под трамплин и
		# его посадочную плиту не ставим: полотно там наклонено, а предмету известно
		# только плоское, так что пилон тонул в горке и выпрыгивал на старте заезда
		var px := -14.0 + k * 22.0
		if px > 18.0 and px < 60.0: continue
		loose_kit(root, "pylon", Vector3(px, 0, 3.2 * (1 if k % 2 == 0 else -1)), 0, 6.0)
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
