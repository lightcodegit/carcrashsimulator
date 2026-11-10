class_name MapKit
extends RefCounted
# Примитивы сцены: процедурные коробки и клинья, сегменты Kenney Racing Kit,
# замыкание открытых торцов, учёт поверхностей для посадки предметов и
# вспомогательные обходы дерева (дальность, тени).

# Плоскости, на которые можно поставить предмет: (x, z) -> y. Собираются по ходу
# раскладки плит в build(), обнуляются на его старте. Без этого предмет либо внутри
# асфальта (solver его выталкивает — на старте конусы подпрыгивают), либо висящий
# над полом на толщину плиты.
static var _surfaces: Array[Dictionary] = []

# Индекс поверхностей. surface_y вызывается на каждый расставляемый предмет, и
# полный обход 399 плит на сборке города стоил 662 мс — hitch, который игрок
# видит как подвисание при заезде на карту. Запись кладётся во ВСЕ ячейки,
# которые пересекает её прямоугольник, поэтому точка внутри прямоугольника
# обязательно лежит в своей ячейке и ответ совпадает с перебором бит в бит.
const GRID_CELL := 48.0
# Прямоугольник шире этого числа ячеек уходит в общий список: иначе одна
# плита-пол заполнила бы сетку тысячами ссылок и сборка стала бы дороже запроса.
const GRID_SPAN_MAX := 16
static var _grid: Dictionary = {}
static var _grid_wide: Array[Dictionary] = []
static var _grid_count := -1

static func clear_surfaces() -> void:
	_surfaces.clear()
	_grid.clear()
	_grid_wide.clear()
	_grid_count = -1

static func surfaces() -> Array[Dictionary]:
	return _surfaces

static func add_surface(entry: Dictionary) -> void:
	_surfaces.append(entry)

static func _build_grid() -> void:
	_grid.clear()
	_grid_wide.clear()
	for r in _surfaces:
		var rect: AABB = r["rect"]
		var from := Vector2i(int(floor(rect.position.x / GRID_CELL)), int(floor(rect.position.z / GRID_CELL)))
		var to := Vector2i(int(floor((rect.position.x + rect.size.x) / GRID_CELL)),
			int(floor((rect.position.z + rect.size.z) / GRID_CELL)))
		if (to.x - from.x + 1) * (to.y - from.y + 1) > GRID_SPAN_MAX:
			_grid_wide.append(r)
			continue
		for gx in range(from.x, to.x + 1):
			for gz in range(from.y, to.y + 1):
				var k := Vector2i(gx, gz)
				if not _grid.has(k):
					# Array, а не PackedInt32Array: упакованный массив — значение,
					# и append через каст молча писал бы в копию
					_grid[k] = []
				(_grid[k] as Array).append(r)
	_grid_count = _surfaces.size()

# Высота, на которую нужно ставить предмет в этой точке: берётся НАИБОЛЕЕ НИЗКАЯ
# подходящая поверхность. Предмет стоит коробкой, и если центр попал на полотно, а
# углом задел бордюр, установка на бордюр оставит под ним пустоту, а втиснутый в
# бордюр ящик solver вытолкнет вниз — конус запрыгает по дороге. Низкая поверхность
# даёт крошечное пересечение с бордюром, которое машина просто переезжает.
static func surface_y(x: float, z: float) -> float:
	if _grid_count != _surfaces.size(): _build_grid()
	var got := INF
	var c := Vector3(x, 0.0, z)
	var bucket: Array = _grid.get(Vector2i(int(floor(x / GRID_CELL)), int(floor(z / GRID_CELL))), [])
	for r in bucket:
		if (r["rect"] as AABB).has_point(c): got = minf(got, float(r["y"]))
	for r in _grid_wide:
		if (r["rect"] as AABB).has_point(c): got = minf(got, float(r["y"]))
	return got if is_finite(got) else MapDefs.FLOOR_Y + 0.001

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

static func box_vis(root: Node3D, pos: Vector3, size: Vector3, color: Color,
		rot: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new()
	bm.size = size; bm.material = _mat(color); mi.mesh = bm
	mi.position = pos; mi.basis = rot
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

# Гребень бордюра: два клина сходятся вершинами на линии center (подъём 0.2 м по 0.6 м
# с каждой стороны). Колесо наезжает на пологую грань с любой стороны; прежняя стенка
# box 0.2 м — вертикальная грань, для колеса на 108 км/ч это сплошной удар (страхует
# h_curbs).
static func curb_ridge(root: Node3D, center: Vector3, axis: Vector3, length: float) -> void:
	var a := rad_to_deg(atan2(-axis.z, axis.x))
	for s in [-1.0, 1.0]:
		var b := wedge(root, center + axis * (0.6 * s), 0.6, 0.2, length, Color(0.5, 0.5, 0.52))
		b.rotation_degrees.y = a if s < 0.0 else a + 180.0

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

# Коллайдер дорожных сегментов — только полотно (материал road). Юбки (grass) и боковые
# поребрики (grey: у бугра они торчат над землёй до 1.0 м, у горки идут вдоль всего
# склона) делают из края горки или бугра невидимую стену — колесо, соскользнувшее к
# краю, отбивается от неё. Полотно остаётся наезжаемым, а дно и задние стенки добавляет
# _closure — сквозь горку по-прежнему нельзя (страхует h_ramp_solid, борт — h_curbs).
static func _collider_faces(m: Mesh, name: String) -> PackedVector3Array:
	# Арка старта — не полотно, а рамка: её стойки обязаны быть твёрдыми, иначе сквозь
	# них проезжают (жалоба «сквозь арку можно проехать»). Из коллайдера убраны
	# горизонтальные грани у земли — с ними арка блокирует ХУЖЕ: колесо запрыгивает на
	# сопланарный пол и проходит стойку насквозь (замер: удар 0 км/ч, x=−395.9), без них
	# стойка держит (удар 99 км/ч, остановка у x=−412). Полотно под аркой даёт плита.
	# Ряд пилонов сдвинут из-под пролёта ворот: там рамка толкала пилон на 0.33 м, и он
	# проседал на 6 мм (ловит h_restart_props).
	if name == "roadStart":
		var all := _mesh_faces(m)
		var walls := PackedVector3Array()
		for t in range(0, all.size() - 2, 3):
			var a := all[t]; var b := all[t + 1]; var c := all[t + 2]
			var n := (b - a).cross(c - a)
			if absf(n.y) > 0.9 * n.length() and (a.y + b.y + c.y) / 3.0 < 0.35: continue
			walls.append(a); walls.append(b); walls.append(c)
		return walls
	if not name.begins_with("road"): return _mesh_faces(m)
	var faces := PackedVector3Array()
	for surf in m.get_surface_count():
		var mat := m.surface_get_material(surf)
		if mat == null or mat.resource_name != "road": continue
		var arr := m.surface_get_arrays(surf)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if ix.size() >= 3:
			for t in range(0, ix.size(), 3):
				faces.append(v[ix[t]]); faces.append(v[ix[t + 1]]); faces.append(v[ix[t + 2]])
		else:
			for q in v: faces.append(q)
	# У рамп и бугров боковины и ступени — тоже физика: в коллайдер идут только
	# грани материала «road», и сквозь видимую горку проезжали сбоку (жалоба
	# игрока). Берём крутые грани меша: вертикальные стенки и ступени профиля;
	# дно и пологие грани не трогаем — их уже замыкает оболочка, а наезжаемость
	# низких кромок (h_curbs) сохраняется.
	if _needs_closure(name):
		var all := _mesh_faces(m)
		for t in range(0, all.size() - 2, 3):
			var a := all[t]; var b := all[t + 1]; var c := all[t + 2]
			var n := (b - a).cross(c - a)
			if n.length() < 0.0001: continue
			if absf(n.y) > 0.5 * n.length(): continue
			faces.append(a); faces.append(b); faces.append(c)
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
	# вместе с разметкой (тот же класс ошибки, что чинила h_markings)
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
		# грань с такой кромкой уже торчала бы под асфальтом (h_map_props считает это провисанием)
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
# новым мешем у самого сегмента: три теста и сам MapKit узнают плиту по resource_path её
# меша (h_map_props, h_markings), и подмена меша на собранный в коде потеряла бы эту идентичность.
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
	var off := MapDefs.ROAD_TOP - (got if is_finite(got) else -MapDefs.ROAD_Y)
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
	var m: Mesh = load(MapDefs.R + name + ".obj")
	if m == null:
		push_warning("MapDB: сегмент трассы не найден " + name)
		return null
	# Замыкаем только те сегменты, по которым едут: рампы и бугры. Пропы и плиты — свои
	# оболочки, им это не нужно, а лишняя грань у дерева сбила бы проверку «декорации стоят
	# на поверхности» (h_map_props) своим нижним краем
	var close: Array[Dictionary] = []
	if solid and _needs_closure(name): close = _closure(m)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if name.begins_with("billboard"):
		_blank_billboard_panel(mi)
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
		# Стенка видна и с тыла: односторонняя грань с обратной стороны отсекается,
		# и горка выглядела прозрачной, хотя коллайдер стоял (жалоба игрока). Дубли
		# материала с отключённым клиппингом хватает: треугольников не прибавляется,
		# и проверка h_ramp_solid по их числу не ломается.
		var sm: Material = shell.mesh.surface_get_material(0)
		if sm is BaseMaterial3D:
			var sm2: BaseMaterial3D = (sm as BaseMaterial3D).duplicate()
			sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
			shell.material_override = sm2
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
		# Коллайдер нужен наклонным сегментам (рампа, лежачий полицейский): у плоской
		# плиты полотно совпадает с физической землёй, и свой коллайдер дал бы уступ
		# в 4 см на каждой границе — на 150 км/ч колесо цепляет его, и машину бросает
		# вперёд (замерено: 150 → 0 км/ч за 1.3 с после прыжка).
		var body := StaticBody3D.new()
		# имя-пара к мешу: recycle переставляет тело по имени, а не поиском по
		# «той же точке» — совпадающие координаты соседей схлопывались в один ключ
		body.name = "col_" + mi.name
		body.position = mi.position
		body.rotation.y = mi.rotation.y
		var cs := CollisionShape3D.new()
		var tri := ConcavePolygonShape3D.new()
		var faces := _collider_faces(m, name)
		for e in close:
			faces.append_array(e["tri"] as PackedVector3Array)
		tri.set_faces(_scaled_faces(faces, sc))
		# без этого лучи проходят сквозь trimesh (обратные грани отсекаются), хотя
		# solver тело останавливает: клармп рамы и опора переставали видеть препятствие
		tri.backface_collision = true
		cs.shape = tri
		body.add_child(cs)
		var pm := PhysicsMaterial.new(); pm.friction = 0.0
		body.physics_material_override = pm
		root.add_child(body)
	return mi

# Панель билборда — поверхность "tankco" из Kenney, рекламный плакат. По просьбе
# игрока щит должен быть чистым белым и пустым, поэтому переопределяем именно её
# белым материалом. Override ставится здесь, до Materials.apply_tree(..., "prop")
# в конце сборки карты: apply_tree пропускает поверхности с уже заданным override
# (materials.gd:174), так что белое не перетирается додведенным танко. Каркас
# (grey/bark) и опоры не трогаем — белим только сам щит.
static var _billboard_blank: StandardMaterial3D
static func _blank_billboard_panel(mi: MeshInstance3D) -> void:
	if _billboard_blank == null:
		_billboard_blank = StandardMaterial3D.new()
		_billboard_blank.resource_name = "billboard_blank"
		_billboard_blank.albedo_color = Color(0.90, 0.90, 0.91)
		_billboard_blank.roughness = 0.6
		_billboard_blank.metallic = 0.0
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		if src != null and src.resource_name == "tankco":
			mi.set_surface_override_material(i, _billboard_blank)

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

# Отсечь предмет по дальности: на Compatibility это дешёвый CPU-коллинг, а туман
# сцены скрывает точку исчезновения, так что картинка не меняется, а отрисовок
# становится меньше. Для тротуарной мелочи и молодых деревьев в плотном городе
# это и есть цена между «много деталей» и честными кадрами в секунду.

static func far(n: Node, dist: float) -> void:
	# prop()/loose()/kit() возвращают null на отсутствующем ассете, а вызов идёт
	# прямо сюда — без проверки сборка карты падает на пустом месте
	if n == null: return
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		gi.visibility_range_end = dist
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in n.get_children():
		far(c, dist)

# Выключить тени у узла с потомками (мелочь вроде кашпо: тень видна только вблизи,
# а каждый caster удваивается в проходе теней).
static func no_shadow(n: Node) -> void:
	if n == null: return
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		no_shadow(c)
