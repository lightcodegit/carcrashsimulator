class_name DentBody
extends Node3D
# Кузов из готовой модели + вмятины без какой-либо симуляции: удар мгновенно
# смещает вершины в радиусе R вдоль направления удара, с плавным спадом и
# валиком по краю. Геометрия меняется только в момент удара, поэтому меш можно
# держать плотным (подразбиение кузова) без стоимости в кадре.
#
# Иерархия: DentBody -> _root (масштаб + поворот морды в +X) -> model (центрирование)
#           -> body (MeshInstance3D). Вершины хранятся в пространстве меша кузова,
# все переходы наружу идут через _body_xform.

signal dented(depth_m: float, world_pos: Vector3, radius_m: float)

const SUBDIV := 2                  # 704 -> 11264 треугольника кузова
const MAX_DEPTH_RATIO := 0.30      # глубина вмятины не больше доли высоты кузова
const RIM_START := 0.70            # с какой доли радиуса начинается валик
const RIM_RATIO := 0.30            # высота валика относительно глубины
const SCUFF := Color(0.16, 0.15, 0.14)
const DIRTY_LIMIT := 4000            # вершин, до которых точечные нормали выгодны

var params: VehicleParams
var body: MeshInstance3D
var wheels: Array[MeshInstance3D] = []
var front_wheels: Array[MeshInstance3D] = []
var wheel_radius := 0.3
var dent_count := 0
var max_depth := 0.0               # метры
var total_depth := 0.0             # метры
var length := 0.0                  # габариты после приведения к params.width
var width := 0.0
var height := 0.0

var _root: Node3D
var _model: Node3D
var _mesh: ArrayMesh
var _mat: StandardMaterial3D
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()
var _colors := PackedColorArray()
var _pristine := PackedVector3Array()
var _weld_id := PackedInt32Array()   # вершина -> группа совпадающих позиций (для гладких нормалей)
var _weld_count := 0
# Инцидентность-CSR (строится один раз): вмятина двигает сотни вершин, а полный
# пересчёт нормалей по всем 11 тысячам стоил 2.4 мс на удар — больше бюджета
# физического тика. Теперь пересчитываются только группы, которых коснулся
# сдвиг; счётчики ниже это измеряют (d_dent_cost).
var _nrm := PackedVector3Array()
var _v_tri_start := PackedInt32Array()
var _v_tri_list := PackedInt32Array()
var _g_tri_start := PackedInt32Array()
var _g_tri_list := PackedInt32Array()
var _g_vert_start := PackedInt32Array()
var _g_vert_list := PackedInt32Array()
var _dirty := PackedByteArray()
var _shift := 0.0
var rebuild_count := 0
var normal_passes := 0
var _wheel_base_y: Array[float] = []
var _body_xform := Transform3D()   # вершина кузова -> локальные координаты DentBody
var _scale := 1.0

# Габариты импортированной модели в её собственных единицах и радиус колеса
# (узел в дерево не добавляется).
static func measure(scene_path: String, stretch := 1.0) -> Dictionary:
	var ps: PackedScene = load(scene_path)
	if ps == null: return {"aabb": AABB(), "wheel_r": 0.0}
	var n: Node3D = ps.instantiate()
	stretch_model(n, stretch)
	var merged := _aabb_in(n)
	var wb := _wheels_bounds(n)
	n.free()
	return {"aabb": merged, "wheel_r": wb.r, "wheel_bottom": wb.bottom}

# Радиус колеса и низ колеса — по геометрии, а не «на глаз»: расхождение оставляло луч
# подвески висеть над полом, и машина ложилась коллайдером на землю.
static func _wheels_bounds(n: Node3D) -> Dictionary:
	var r := 0.0
	var bottom := INF
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not String(c.name).to_lower().begins_with("wheel"): continue
		var g: AABB = mi.transform * mi.get_aabb()
		r = maxf(r, g.size.y * 0.5)
		bottom = minf(bottom, g.position.y)
	return {"r": r, "bottom": bottom}

static func _aabb_in(n: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var g: AABB = mi.transform * mi.get_aabb()
		if first: merged = g; first = false
		else: merged = merged.merge(g)
	return merged

# Лимузин — это растянутый по длине седан из того же CC0-набора: кузов длиннее, задняя
# ось уехала назад, передок остался там, где был. Колёса не масштабируются НИКОГДА:
# неравномерный масштаб сделал бы из них овалы, а они крутятся.
static func stretch_model(model: Node3D, k: float) -> void:
	if absf(k - 1.0) < 1e-3: return
	var body: MeshInstance3D = null
	var rear: Array[MeshInstance3D] = []
	for c in model.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var nm := String(c.name).to_lower()
		if nm == "body": body = mi
		elif nm.begins_with("wheel") and (nm.contains("back") or nm.contains("rear")): rear.append(mi)
	if body == null: return
	# aabb узла в его местных координатах: половина длины кузова от его центра
	var half := maxf(absf(body.get_aabb().position.z), absf(body.get_aabb().end.z))
	var grow := half * (k - 1.0)
	body.scale = Vector3(body.scale.x, body.scale.y, body.scale.z * k)
	body.position.z -= grow                 # прирост уходит в зад, нос на месте
	for w in rear:
		w.position.z -= grow * 2.0          # задняя ось держится за задок кузова

func setup(scene_path: String, p: VehicleParams) -> void:
	params = p
	var ps: PackedScene = load(scene_path)
	if ps == null:
		push_error("DentBody: модель не найдена " + scene_path)
		return
	var model: Node3D = ps.instantiate()
	stretch_model(model, p.body_stretch)
	add_child(model)
	var body_mi: MeshInstance3D = null
	for c in model.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var nm := String(c.name).to_lower()
		if nm == "body":
			body_mi = mi
		elif nm.begins_with("wheel"):
			wheels.append(mi)
			if nm.contains("front"): front_wheels.append(mi)
	var merged := _aabb_in(model)
	if merged.size.length() < 0.01:
		push_error("DentBody: пустая модель " + scene_path)
		return
	# единый равномерный масштаб: ширина модели -> params.width, иначе колёса станут овалами
	_scale = p.width / maxf(0.001, merged.size.x)
	length = merged.size.z * _scale
	width = merged.size.x * _scale
	height = merged.size.y * _scale
	var wb := _wheels_bounds(model)
	wheel_radius = float(wb.r) * _scale
	if wheel_radius < 0.01: wheel_radius = 0.3 * _scale
	_root = Node3D.new()
	_root.name = "ModelRoot"
	add_child(_root)
	_root.scale = Vector3.ONE * _scale
	_root.rotation.y = PI * 0.5      # морда модели (+Z) -> +X (вперёд по соглашению проекта)
	remove_child(model)
	_root.add_child(model)
	_model = model
	# На y=0 ставим низ колёс, а не самую нижнюю точку модели: у Kenney ниже колёс ещё
	# торчит геометрия, и подвеска из-за этого висела в 7 см над землёй.
	var ground: float = merged.position.y if not is_finite(float(wb.bottom)) else float(wb.bottom)
	model.position = Vector3(-merged.get_center().x, -ground, -merged.get_center().z)
	for w in wheels:
		_wheel_base_y.append(w.position.y)
	body = body_mi
	if body == null:
		push_warning("DentBody: в модели нет узла 'body' — вмятины невозможны")
		return
	_body_xform = _root.transform * model.transform * body.transform
	_build_deformable()

func _build_deformable() -> void:
	var src: Mesh = body.mesh
	var arr := src.surface_get_arrays(0)
	_verts = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	_idx = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	_uvs = (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate()
	if _uvs.size() != _verts.size():
		_uvs.resize(_verts.size())
	if _idx.size() == 0:
		push_warning("DentBody: кузов без индексов — вмятины отключены")
		return
	for _lvl in SUBDIV:
		_subdivide()
	_pristine = _verts.duplicate()
	_colors.resize(_verts.size())
	_colors.fill(Color.WHITE)
	_build_weld()
	_build_incidence()
	# материал автора (colormap, шероховатость) — дублируем и добавляем только vertex color
	# для ободранных вмятин: собственный metallic затемнял кузов до чёрного
	# лак и металличность поверх материала автора: без них кузов матовый и в тени
	# выглядит чёрным. vertex color нужен самому DentBody — им красится ободранная краска.
	_mat = Materials.body_paint(src.surface_get_material(0), params)
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = ArrayMesh.new()
	body.mesh = _mesh
	_rebuild()

# Одно подразбиение: каждый треугольник на 4. Середины совпадающих по позиции рёбер
# дают одинаковые точки, поэтому меш не рвётся и без сварки вершин.
func _subdivide() -> void:
	var nv := _verts.duplicate()
	var nu := _uvs.duplicate()
	var ni := PackedInt32Array()
	ni.resize(_idx.size() * 4)
	var o := 0
	for t in range(0, _idx.size(), 3):
		var a := _idx[t]; var b := _idx[t + 1]; var c := _idx[t + 2]
		var ab := nv.size(); nv.append((_verts[a] + _verts[b]) * 0.5); nu.append((_uvs[a] + _uvs[b]) * 0.5)
		var bc := nv.size(); nv.append((_verts[b] + _verts[c]) * 0.5); nu.append((_uvs[b] + _uvs[c]) * 0.5)
		var ca := nv.size(); nv.append((_verts[c] + _verts[a]) * 0.5); nu.append((_uvs[c] + _uvs[a]) * 0.5)
		ni[o] = a;  ni[o + 1] = ab; ni[o + 2] = ca
		ni[o + 3] = ab; ni[o + 4] = b;  ni[o + 5] = bc
		ni[o + 6] = ca; ni[o + 7] = bc; ni[o + 8] = c
		ni[o + 9] = ab; ni[o + 10] = bc; ni[o + 11] = ca
		o += 12
	_verts = nv
	_uvs = nu
	_idx = ni

# inward_dir — направление внутрь кузова (по ходу движения машины).
func apply_impact(world_pos: Vector3, inward_dir: Vector3, speed_kmh: float) -> void:
	apply_impact_local(_to_body_point(world_pos), _to_body_dir(inward_dir), speed_kmh, world_pos)

# То же, но в пространстве меша: реплей обязан мять кузов ровно как живой заезд,
# а мировых координат удара для этого мало — на проигрывании машина стоит в
# другой позе, и мировой вектор попал бы в другую панель.
func apply_impact_local(local_pos: Vector3, local_dir: Vector3, speed_kmh: float, world_pos := Vector3.INF) -> void:
	if body == null or not _pristine_ok(): return
	var speed := maxf(0.0, speed_kmh) / 3.6
	var radius := 0.30 + minf(speed, 60.0) * 0.014              # метры
	var depth := minf(MAX_DEPTH_RATIO * height, speed * 0.010)  # метры
	if depth <= 0.0 or radius <= 0.0: return
	var lp := local_pos
	var ld := local_dir
	var rl := radius / _scale          # всё сравнение и смещение — в единицах модели
	var dl := depth / _scale
	var cap_l := MAX_DEPTH_RATIO * height / _scale   # предел накопленной вмятины
	var moved_v := PackedInt32Array()
	# Сплошной проход по вершинам. Сетка по ячейкам не помогла и убрана: максимальный
	# радиус вмятины сопоставим с размером кузова, кандидатов выходило ~85 % меша, а
	# обход с вызовом функции на вершину стоил дороже простого цикла (замер: 5.7 мс
	# против 2.6 мс).
	for i in _verts.size():
		var d := _verts[i].distance_to(lp)
		if d > rl: continue
		var t := d / rl
		var push: float
		if t <= RIM_START:
			var f := 1.0 - t / RIM_START
			push = dl * f * f
		else:
			var r := (t - RIM_START) / (1.0 - RIM_START)
			push = -dl * RIM_RATIO * sin(r * PI)
		# Смещение НАКАПЛИВАЕТСЯ, поэтому потолок нужен именно накопленному отклонению:
		# вторая и третья вмятина в том же месте иначе уводят вершину за предельные
		# 30% высоты (кузов схлопывается внутрь), а шкала «КУЗОВ» этого не видит.
		var np: Vector3 = _verts[i] + ld * push
		var off := _pristine[i].distance_to(np)
		if off > cap_l:
			np = _pristine[i] + _pristine[i].direction_to(np) * cap_l
			off = cap_l
		_shift = maxf(_shift, off / _scale)
		_verts[i] = np
		var sc := clampf(absf(push) / maxf(1e-6, dl), 0.0, 1.0)
		_colors[i] = _colors[i].lerp(SCUFF, sc * 0.75)
		moved_v.append(i)
	if moved_v.is_empty(): return
	dent_count += 1
	# Показание — фактическое отклонение геометрии, а не номинал одного удара:
	# иначе повторные вмятины в одном месте остаются невидимы для HUD. Копим его
	# по сдвинутым вершинам: прежний max_vertex_shift() второй раз за удар
	# перебирал весь кузов.
	max_depth = maxf(max_depth, _shift)
	total_depth += depth
	# Порог измерен, не выбран на глаз (один и тот же кузов, 60 ударов подряд):
	# 1464 вершины — 2.6 мс точечно против 2.5 полным, 2296 — 3.9 против 6.9,
	# 3108 — 5.6 против 7.3. Полный проход стоит ~6.9 мс независимо от размера
	# вмятины, точечный растёт с числом затронутых вершин, и пересекаются они
	# около 4000 — то есть точечный почти всегда дешевле, а на «нос в отбойник»
	# по всей панели выгоден полный.
	if moved_v.size() <= DIRTY_LIMIT:
		_rebuild(_dirty_groups(moved_v))
	else:
		_rebuild()
	dented.emit(depth, to_global(_body_xform * lp) if world_pos == Vector3.INF else world_pos, radius)

# Снимок геометрии для плеера: реплей начинается с того кузова, который есть
# сейчас, и на выходе обязан вернуться ровно в него, даже если игрок вышел на середине.
func stash() -> Dictionary:
	return {"v": _verts.duplicate(), "c": _colors.duplicate(),
		"n": dent_count, "md": max_depth, "td": total_depth, "sh": _shift}

func unstash(s: Dictionary) -> void:
	if s.is_empty() or not _pristine_ok(): return
	_verts = (s.v as PackedVector3Array).duplicate()
	_colors = (s.c as PackedColorArray).duplicate()
	dent_count = int(s.n); max_depth = float(s.md); total_depth = float(s.td)
	# _shift — накопленный максимум за сессию; без отката при возврате геометрии
	# реплея к более раннему состоянию он оставался от поздних вмятин, и шкала
	# «КУЗОВ» по maxf(_shift, ...) перещёптывала честную глубину при скраббинге.
	_shift = float(s.get("sh", 0.0))
	_rebuild()

# Мятая точка и направление в пространстве меша — ровно то, что записывает
# реплей: пересчёт мировой точки в локальную живёт здесь, а не в recorder.
func dent_frame(world_pos: Vector3, inward_dir: Vector3) -> Array:
	return [_to_body_point(world_pos), _to_body_dir(inward_dir)]

func _to_body_point(world_pos: Vector3) -> Vector3:
	return _body_xform.affine_inverse() * to_local(world_pos)

func _to_body_dir(world_dir: Vector3) -> Vector3:
	var local: Vector3 = global_transform.basis.inverse() * world_dir
	return (_body_xform.basis.inverse() * local).normalized()

func _build_incidence() -> void:
	var tris := _idx.size() / 3
	var vcount := PackedInt32Array()
	vcount.resize(_verts.size())
	for t in tris:
		for j in 3:
			vcount[_idx[t * 3 + j]] += 1
	var vs := 0
	_v_tri_start.resize(_verts.size() + 1)
	for i in _verts.size():
		_v_tri_start[i] = vs
		vs += vcount[i]
	_v_tri_start[_verts.size()] = vs
	_v_tri_list.resize(vs)
	var fill := PackedInt32Array()
	fill.resize(_verts.size())
	for t in tris:
		for j in 3:
			var v := _idx[t * 3 + j]
			_v_tri_list[_v_tri_start[v] + fill[v]] = t
			fill[v] += 1
	# вершины группы сварки, в порядке групп: сначала счётчики, потом префиксные
	# смещения, потом раскладка — иначе все группы пишут в начало одного массива
	var gcount := PackedInt32Array()
	gcount.resize(_weld_count)
	for i in _verts.size():
		gcount[_weld_id[i]] += 1
	_g_vert_start.resize(_weld_count + 1)
	var acc := 0
	for g in _weld_count:
		_g_vert_start[g] = acc
		acc += gcount[g]
	_g_vert_start[_weld_count] = acc
	_g_vert_list.resize(_verts.size())
	var placed := PackedInt32Array()
	placed.resize(_weld_count)
	for i in _verts.size():
		var g := _weld_id[i]
		_g_vert_list[_g_vert_start[g] + placed[g]] = i
		placed[g] += 1
	# треугольники группы — пары (вершина, треугольник) БЕЗ дедупа: прежний
	# накопитель прибавлял нормаль грани к группе каждой из трёх её вершин, и
	# точечный проход обязан давать ровно то же накопление
	var gt_count := PackedInt32Array()
	gt_count.resize(_weld_count)
	for g in _weld_count:
		for k in range(_g_vert_start[g], _g_vert_start[g + 1]):
			var v := _g_vert_list[k]
			gt_count[g] += _v_tri_start[v + 1] - _v_tri_start[v]
	_g_tri_start.resize(_weld_count + 1)
	var gs := 0
	for g in _weld_count:
		_g_tri_start[g] = gs
		gs += gt_count[g]
	_g_tri_start[_weld_count] = gs
	_g_tri_list.resize(gs)
	var fillg := PackedInt32Array()
	fillg.resize(_weld_count)
	for g in _weld_count:
		for k in range(_g_vert_start[g], _g_vert_start[g + 1]):
			var v := _g_vert_list[k]
			for t in range(_v_tri_start[v], _v_tri_start[v + 1]):
				_g_tri_list[_g_tri_start[g] + fillg[g]] = _v_tri_list[t]
				fillg[g] += 1
	_dirty.resize(_weld_count)
	_nrm.resize(_verts.size())

# Группы сварки, которых коснулся сдвиг: все группы всех вершин всех
# треугольников сдвинутых вершин. Соседняя панель меняет нормаль тоже, поэтому
# одних «сдвинутых вершин» мало.
func _dirty_groups(moved_v: PackedInt32Array) -> PackedInt32Array:
	var groups := PackedInt32Array()
	for v in moved_v:
		for t in range(_v_tri_start[v], _v_tri_start[v + 1]):
			var tri := _v_tri_list[t] * 3
			for j in 3:
				var g := _weld_id[_idx[tri + j]]
				if _dirty[g] == 0:
					_dirty[g] = 1
					groups.append(g)
	for g in groups: _dirty[g] = 0
	return groups

func _face_normal(t: int) -> Vector3:
	var ia := _idx[t * 3]; var ib := _idx[t * 3 + 1]; var ic := _idx[t * 3 + 2]
	var fn := (_verts[ib] - _verts[ia]).cross(_verts[ic] - _verts[ia])
	return fn.normalized() if fn.length_squared() > 1e-16 else Vector3.ZERO

func _rebuild(dirty_groups := PackedInt32Array()) -> void:
	rebuild_count += 1
	normal_passes = 0
	if dirty_groups.is_empty():
		# полный проход: одна нормаль грани на весь меш, накопление по группам
		var sums := PackedVector3Array()
		sums.resize(_weld_count)
		sums.fill(Vector3.ZERO)
		for t in range(0, _idx.size(), 3):
			var fn := _face_normal(t / 3)
			if fn == Vector3.ZERO: continue
			sums[_weld_id[_idx[t]]] += fn
			sums[_weld_id[_idx[t + 1]]] += fn
			sums[_weld_id[_idx[t + 2]]] += fn
		for g in _weld_count:
			var v: Vector3 = sums[g]
			var n := v.normalized() if v.length_squared() > 1e-12 else Vector3.UP
			for k in range(_g_vert_start[g], _g_vert_start[g + 1]):
				_nrm[_g_vert_list[k]] = n
		normal_passes = _verts.size()
	else:
		# точечный проход идёт по парам (вершина, треугольник) — та же схема
		# накопления, что и в полном: грань с двумя вершинами одной группы
		# входит дважды здесь и там. Иначе перемотка рисовала бы швы иначе заезда.
		for g in dirty_groups:
			var sum := Vector3.ZERO
			for k in range(_g_tri_start[g], _g_tri_start[g + 1]):
				sum += _face_normal(_g_tri_list[k])
			var n := sum.normalized() if sum.length_squared() > 1e-12 else Vector3.UP
			for k in range(_g_vert_start[g], _g_vert_start[g + 1]):
				_nrm[_g_vert_list[k]] = n
			normal_passes += _g_vert_start[g + 1] - _g_vert_start[g]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _idx
	# surface_update_vertex_region в этой сборке догружает межованный блок целиком,
	# а не один массив, поэтому поверхность пересоздаётся; выигрыш дают точечный
	# пересчёт нормалей и инкрементальный реплей
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, _mat)

# Группы сварки строятся один раз по исходным позициям: смещение вмятины зависит
# только от позиции, поэтому совпадающие вершины остаются совпадающими навсегда.
func _build_weld() -> void:
	_weld_id.resize(_verts.size())
	var ids := {}
	_weld_count = 0
	for i in _verts.size():
		var v := _pristine[i]
		var k := (roundi(v.x * 2000.0) * 73856093) ^ (roundi(v.y * 2000.0) * 19349663) ^ (roundi(v.z * 2000.0) * 83492791)
		if not ids.has(k):
			ids[k] = _weld_count
			_weld_count += 1
		_weld_id[i] = ids[k]

# Гладкие нормали по сваренным позициям считаются в _rebuild(): полный проход
# нужен только после reset(), а удар пересчитывает затронутые группы.
func wheel_local_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _model == null: return out
	var xf := _root.transform * _model.transform
	for w in wheels:
		var g: AABB = xf * (w.transform * w.get_aabb())
		out.append(g.get_center())
	return out

func wheel_is_front(i: int) -> bool:
	return i < wheels.size() and front_wheels.has(wheels[i])

# Поза визуального колеса: drop — насколько колесо вышло из арки (метры),
# steer — угол поворота, roll — накопленный угол качения.
func set_wheel_pose(i: int, drop: float, steer: float, roll: float) -> void:
	if i >= wheels.size(): return
	var w := wheels[i]
	w.position.y = _wheel_base_y[i] - drop / _scale
	w.rotation = Vector3(roll, steer if front_wheels.has(w) else 0.0, 0.0)

# Точка над кузовом в локальных координатах шасси: fraction — доля длины от носа.
func hood_point(fraction: float, clearance: float) -> Vector3:
	var tx := length * (0.5 - fraction)
	var tol := length * 0.09
	var best := -INF
	for v in _pristine:
		var p := _body_xform * v
		if absf(p.x - tx) > tol: continue
		best = maxf(best, p.y)
	if best == -INF: best = height * 0.55
	return transform * Vector3(tx, best + clearance, 0.0)

func model_scale() -> float:
	return _scale

func vertex_count() -> int:
	return _verts.size()

func triangle_count() -> int:
	return _idx.size() / 3

func vertex_world(i: int) -> Vector3:
	return global_transform * (_body_xform * _verts[i])

func vertex_pristine_world(i: int) -> Vector3:
	return global_transform * (_body_xform * _pristine[i])

# Исходная геометрия живёт рядом с рабочей только когда кузов разбит на индексы.
# Без индексов сборка выходит раньше, чем _pristine заполнен, и любой обход по
# _pristine[i] ушёл бы за край массива — а reset() к тому же стёр бы всю геометрию.
func _pristine_ok() -> bool:
	return _verts.size() > 0 and _pristine.size() == _verts.size()

# Суммарное отклонение от исходной геометрии, в метрах.
func deformation() -> float:
	var s := 0.0
	if not _pristine_ok(): return s
	for i in _verts.size():
		s += _verts[i].distance_to(_pristine[i]) / _scale
	return s

func max_vertex_shift() -> float:
	var m := 0.0
	if not _pristine_ok(): return m
	for i in _verts.size():
		m = maxf(m, _verts[i].distance_to(_pristine[i]) / _scale)
	return m

func moved_vertex_count(threshold_m: float) -> int:
	var n := 0
	if not _pristine_ok(): return n
	for i in _verts.size():
		if _verts[i].distance_to(_pristine[i]) / _scale > threshold_m: n += 1
	return n

func reset() -> void:
	if not _pristine_ok(): return
	_verts = _pristine.duplicate()
	_colors.fill(Color.WHITE)
	_shift = 0.0
	dent_count = 0; max_depth = 0.0; total_depth = 0.0
	_rebuild()
