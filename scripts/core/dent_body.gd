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
var _mesh: ArrayMesh
var _mat: StandardMaterial3D
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()
var _colors := PackedColorArray()
var _pristine := PackedVector3Array()
var _weld_id := PackedInt32Array()   # вершина -> группа совпадающих позиций (для гладких нормалей)
var _weld_count := 0
var _wheel_base_y: Array[float] = []
var _body_xform := Transform3D()   # вершина кузова -> локальные координаты DentBody
var _scale := 1.0

# AABB импортированной модели в её собственных единицах (узел в дерево не добавляется).
static func measure(scene_path: String) -> AABB:
	var ps: PackedScene = load(scene_path)
	if ps == null: return AABB()
	var n: Node3D = ps.instantiate()
	var merged := _aabb_in(n)
	n.free()
	return merged

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

func setup(scene_path: String, p: VehicleParams) -> void:
	params = p
	var ps: PackedScene = load(scene_path)
	if ps == null:
		push_error("DentBody: модель не найдена " + scene_path)
		return
	var model: Node3D = ps.instantiate()
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
	wheel_radius = 0.3 * _scale
	_root = Node3D.new()
	_root.name = "ModelRoot"
	add_child(_root)
	_root.scale = Vector3.ONE * _scale
	_root.rotation.y = PI * 0.5      # морда модели (+Z) -> +X (вперёд по соглашению проекта)
	remove_child(model)
	_root.add_child(model)
	model.position = Vector3(-merged.get_center().x, -merged.position.y, -merged.get_center().z)
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
	# материал автора (колormap, шероховатость) — дублируем и добавляем только vertex color
	# для ободранных вмятин: собственный metallic затемнял кузов до чёрного
	var base_mat: Material = src.surface_get_material(0)
	if base_mat is StandardMaterial3D:
		_mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		_mat = StandardMaterial3D.new()
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
	if body == null or _verts.size() == 0: return
	var speed := maxf(0.0, speed_kmh) / 3.6
	var radius := 0.30 + minf(speed, 60.0) * 0.014              # метры
	var depth := minf(MAX_DEPTH_RATIO * height, speed * 0.010)  # метры
	if depth <= 0.0 or radius <= 0.0: return
	var lp := _to_body_point(world_pos)
	var ld := _to_body_dir(inward_dir)
	var rl := radius / _scale          # всё сравнение и смещение — в единицах модели
	var dl := depth / _scale
	var moved := 0
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
		_verts[i] += ld * push
		var sc := clampf(absf(push) / maxf(1e-6, dl), 0.0, 1.0)
		_colors[i] = _colors[i].lerp(SCUFF, sc * 0.75)
		moved += 1
	if moved == 0: return
	dent_count += 1
	max_depth = maxf(max_depth, depth)
	total_depth += depth
	_rebuild()
	dented.emit(depth, world_pos, radius)

func _to_body_point(world_pos: Vector3) -> Vector3:
	return _body_xform.affine_inverse() * to_local(world_pos)

func _to_body_dir(world_dir: Vector3) -> Vector3:
	var local: Vector3 = global_transform.basis.inverse() * world_dir
	return (_body_xform.basis.inverse() * local).normalized()

func _rebuild() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _smooth_normals()
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _idx
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

# Гладкие нормали по сваренным позициям: исходный меш плоскостной, а вмятина
# читается только при плавном шейдинге.
func _smooth_normals() -> PackedVector3Array:
	var nrm := PackedVector3Array()
	nrm.resize(_verts.size())
	var acc := PackedVector3Array()
	acc.resize(_weld_count)
	acc.fill(Vector3.ZERO)
	for t in range(0, _idx.size(), 3):
		var ia := _idx[t]; var ib := _idx[t + 1]; var ic := _idx[t + 2]
		var fn := (_verts[ib] - _verts[ia]).cross(_verts[ic] - _verts[ia])
		if fn.length_squared() < 1e-16: continue
		fn = fn.normalized()
		acc[_weld_id[ia]] += fn
		acc[_weld_id[ib]] += fn
		acc[_weld_id[ic]] += fn
	for i in _verts.size():
		var v := acc[_weld_id[i]]
		nrm[i] = v.normalized() if v.length_squared() > 1e-12 else Vector3.UP
	return nrm

# Подвес, рулёжка и качение колёс ассета: exts — провис в метрах, steer — радианы, roll — накопленный угол.
func pose_wheels(exts: Array[float], steer: float, roll: float) -> void:
	for i in wheels.size():
		var w := wheels[i]
		var ext: float = exts[i] if i < exts.size() else 0.0
		w.position.y = _wheel_base_y[i] - ext / _scale
		var st := steer if front_wheels.has(w) else 0.0
		w.rotation = Vector3(roll, st, 0.0)

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
	return position + Vector3(tx, best + clearance, 0.0)

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

# Суммарное отклонение от исходной геометрии, в метрах.
func deformation() -> float:
	var s := 0.0
	for i in _verts.size():
		s += _verts[i].distance_to(_pristine[i]) / _scale
	return s

func max_vertex_shift() -> float:
	var m := 0.0
	for i in _verts.size():
		m = maxf(m, _verts[i].distance_to(_pristine[i]) / _scale)
	return m

func moved_vertex_count(threshold_m: float) -> int:
	var n := 0
	for i in _verts.size():
		if _verts[i].distance_to(_pristine[i]) / _scale > threshold_m: n += 1
	return n

func reset() -> void:
	if _verts.size() == 0: return
	_verts = _pristine.duplicate()
	_colors.fill(Color.WHITE)
	dent_count = 0; max_depth = 0.0; total_depth = 0.0
	_rebuild()
