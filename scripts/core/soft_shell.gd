class_name SoftShell
extends Node3D

signal spring_burst(zone: int)
signal plastic_event(zone: int, world_pos: Vector3, energy: float)

const SUBSTEPS := 2
const RELAX := 3
const DAMP := 0.985
const MAX_PT_SPEED := 14.0
const YIELD := 0.05
const YIELD_C := 0.08
const SLEEP_FRAMES := 90
const GRAVITY := Vector3(0, -9.8, 0)

var spec: ShellSpec
var params: VehicleParams
var chassis: Node3D
var velocity_getter := Callable()          # -> Vector3 линейная скорость шасси
var space_state: PhysicsDirectSpaceState3D  # задаёт CarRig/тест; null => коллизий с миром нет

var _pos: Array[Vector3] = []
var _prev: Array[Vector3] = []
var _rest_local: Array[Vector3] = []
var _dyn: Array[bool] = []
var _still: Array[int] = []
var _slow: Array[int] = []
var _age: Array[int] = []
var _adj: Array = []                       # Array[PackedInt32Array] spring indices per point
var _stress := PackedInt32Array()
var _spring_on := PackedByteArray()
var _spring_rest := PackedFloat64Array()
var broken_by_zone: Array[int] = [0, 0, 0, 0, 0]
var wake_count_at_impact := 0
var _dyn_count := 0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _zone_hp: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0]
var _active: PackedInt32Array = PackedInt32Array()
var _active_dirty := false
var _sim_ms_sum := 0.0
var _sim_frames := 0

func setup(s: ShellSpec, ch: Node3D, p: VehicleParams) -> void:
	spec = s; chassis = ch; params = p
	_pos.resize(s.points.size()); _prev.resize(s.points.size())
	_rest_local.assign(s.points)
	_dyn.resize(s.points.size()); _still.resize(s.points.size()); _slow.resize(s.points.size()); _age.resize(s.points.size())
	_adj.clear()
	for i in s.points.size():
		_adj.append(PackedInt32Array()); _dyn[i] = false; _still[i] = 0; _slow[i] = 0; _age[i] = 0
	_spring_on.resize(s.springs.size()); _spring_on.fill(1)
	_stress.resize(s.springs.size()); _stress.fill(0)
	_spring_rest.resize(s.springs.size())
	for k in s.springs.size():
		_spring_rest[k] = s.springs[k].rest
		_adj[s.springs[k].a].append(k)
		if s.springs[k].b >= 0: _adj[s.springs[k].b].append(k)
	broken_by_zone = [0, 0, 0, 0, 0]; _dyn_count = 0
	_mesh = MeshInstance3D.new(); add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.metallic = 0.15; _mat.roughness = 0.5
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _mat
	_rebuild_mesh()

func _physics_process(dt: float) -> void:
	sim_step(dt)

func sim_step(dt: float) -> float:
	var t0 := Time.get_ticks_usec()
	if _dyn_count > 0 and chassis != null:
		if _active_dirty: _rebuild_active()
		var h := dt / float(SUBSTEPS)
		for _s in SUBSTEPS:
			_integrate(h)
			_plasticity_and_break()   # меряем strain ДО релаксации: PBD-коррекция вычитает её полностью
			for _it in RELAX: _relax()
			_collide_world(h)
		_nan_guard()
		_sleep_check()
	_rebuild_mesh()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_sim_ms_sum += ms; _sim_frames += 1
	return ms

func get_sim_ms_avg() -> float:
	return _sim_ms_sum / maxf(1.0, float(_sim_frames))

func _nan_guard() -> void:
	for i in spec.points.size():
		if _dyn[i] and not _pos[i].is_finite():
			push_warning("SoftShell NaN: resetting dynamic points")
			for k in spec.points.size():
				if _dyn[k]:
					_pos[k] = _chassis_xform() * _rest_local[k]
					_prev[k] = _pos[k]
			return

func _chassis_xform() -> Transform3D:
	if chassis.is_inside_tree(): return chassis.global_transform
	return chassis.transform

func _pt(i: int) -> Vector3:
	if _dyn[i]: return _pos[i]
	return _chassis_xform() * _rest_local[i]

func _wake(i: int, base_vel: Vector3) -> void:
	if _dyn[i]: return
	_dyn[i] = true; _dyn_count += 1; _still[i] = 0; _slow[i] = 0; _age[i] = 0; _active_dirty = true
	_pos[i] = _chassis_xform() * _rest_local[i]
	_prev[i] = _pos[i] - base_vel / 60.0 / float(SUBSTEPS)

func _point_vel_at(_r_local: Vector3) -> Vector3:
	if not velocity_getter.is_valid(): return Vector3.ZERO
	return velocity_getter.call()

func apply_impact(world_pos: Vector3, dir: Vector3, speed_ms: float) -> void:
	var R := 0.7 + minf(speed_ms, 40.0) * 0.008
	var crush_vel := minf(12.0, speed_ms * 0.4)
	var crush_off := minf(0.25, speed_ms * 0.012)   # глубина первичного прогиба растёт со скоростью
	var v_ch := _point_vel_at(Vector3.ZERO)
	var R2 := R * R
	wake_count_at_impact = 0
	for i in spec.points.size():
		var wp := _pt(i)
		if wp.distance_squared_to(world_pos) > R2: continue
		wake_count_at_impact += 1
		if not _dyn[i]:
			_wake(i, v_ch - dir * crush_vel)
			_pos[i] -= dir * crush_off
		else:
			_prev[i] += dir * crush_vel / 60.0 / float(SUBSTEPS)
			_pos[i] -= dir * crush_off * 0.5
	var n := int(crush_vel * 4.0) + 1
	for k in mini(n, 6):
		plastic_event.emit(zone_at(world_pos), world_pos, speed_ms * 0.02)

func zone_at(world_pos: Vector3) -> int:
	var local := _chassis_xform().affine_inverse() * world_pos
	var half_l := params.length * 0.5
	if local.x > half_l * 0.7: return Zones.FRONT
	if local.x < -half_l * 0.7: return Zones.REAR
	return Zones.ROOF if local.y > params.gc + params.body_h + spec.y_off else (Zones.RIGHT if local.z > 0 else Zones.LEFT)

func _integrate(h: float) -> void:
	var h2 := h * h
	for i in spec.points.size():
		if not _dyn[i]: continue
		var v := (_pos[i] - _prev[i]) * DAMP
		if v.length() > MAX_PT_SPEED * h: v = v.normalized() * MAX_PT_SPEED * h
		_prev[i] = _pos[i]
		_pos[i] += v + GRAVITY * h2

func _anchor_target(k: int) -> Vector3:
	var sp: Spring = spec.springs[k]
	return _chassis_xform() * spec.chassis_nodes[sp.anchor]

func _endpoint(k: int, which: int) -> int:
	var sp: Spring = spec.springs[k]
	return sp.a if which == 0 else sp.b

func _rebuild_active() -> void:
	_active = PackedInt32Array()
	for k in spec.springs.size():
		if _spring_on[k] == 0: continue
		var sp: Spring = spec.springs[k]
		if _dyn[sp.a] or (sp.b >= 0 and _dyn[sp.b]): _active.append(k)
	_active_dirty = false

func _relax() -> void:
	for _ai in _active.size():
		var k: int = _active[_ai]
		if _spring_on[k] == 0: continue
		var sp: Spring = spec.springs[k]
		var pa := _pt(sp.a)
		var pb: Vector3
		if sp.type == Spring.ANCHOR: pb = _anchor_target(k)
		else: pb = _pt(sp.b)
		var delta := pb - pa
		var len := delta.length()
		if len < 1e-6: continue
		var rest := _spring_rest[k]
		var kk: float
		match sp.type:
			Spring.STRUCT: kk = 0.9 * params.k_struct
			Spring.SHEAR: kk = 0.6 * params.k_struct
			Spring.BEND: kk = 0.35
			_: kk = minf(1.0, 0.95 * params.k_anchor)
		var corr := delta * (1.0 - rest / len) * kk
		if corr.length() > 0.12: corr = corr.normalized() * 0.12  # кламп: один шаг не даёт взрыва
		if sp.type == Spring.ANCHOR:
			if _dyn[sp.a]: _pos[sp.a] += corr
		elif _dyn[sp.a] and _dyn[sp.b]:
			_pos[sp.a] += corr * 0.5; _pos[sp.b] -= corr * 0.5
		elif _dyn[sp.a]: _pos[sp.a] += corr
		elif _dyn[sp.b]: _pos[sp.b] -= corr

func _break_strain_for(ty: int) -> float:
	match ty:
		Spring.ANCHOR: return params.break_strain * 1.8
		Spring.SHEAR: return params.break_strain * 1.15
		Spring.BEND: return params.break_strain
		_: return params.break_strain

func _plasticity_and_break() -> void:
	for _ai in _active.size():
		var k: int = _active[_ai]
		if _spring_on[k] == 0: continue
		var sp: Spring = spec.springs[k]
		var pa := _pt(sp.a)
		var pb: Vector3 = _anchor_target(k) if sp.type == Spring.ANCHOR else _pt(sp.b)
		var len := pa.distance_to(pb)
		var rest := _spring_rest[k]
		var strain := (len - rest) / maxf(rest, 1e-6)
		if strain > _break_strain_for(sp.type):
			_stress[k] += 1
			if _stress[k] < 8:
				continue  # мгновенный перегрос не рвёт: нужно ~8 substep подряд (демпфирует отскок-каскады)
			_spring_on[k] = 0
			broken_by_zone[sp.zone] += 1
			spring_burst.emit(sp.zone)
			_stress[k] = 0
			if sp.type == Spring.ANCHOR:
				if not _dyn[sp.a]: _wake(sp.a, _point_vel_at(Vector3.ZERO))
			else:
				if not _dyn[sp.a]: _wake(sp.a, _point_vel_at(Vector3.ZERO))
				if not _dyn[sp.b]: _wake(sp.b, _point_vel_at(Vector3.ZERO))
			continue
		if strain > YIELD or strain < -YIELD_C:
			_spring_rest[k] = lerpf(rest, len, 0.85)   # пластичность: вмятина остаётся
			if randi() % 8 == 0:
				plastic_event.emit(sp.zone, (pa + pb) * 0.5, absf(strain))


func _collide_world(_h: float) -> void:
	if space_state == null: return
	for i in spec.points.size():
		if not _dyn[i]: continue
		_age[i] += 1
			# 1) свип prev -> pos против мира
		if _pos[i] != _prev[i]:
			var q := PhysicsRayQueryParameters3D.create(_prev[i], _pos[i])
			q.collide_with_bodies = true; q.collide_with_areas = false
			var hit := space_state.intersect_ray(q)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				_pos[i] = hit.position + n * 0.01
				var v := _pos[i] - _prev[i]
				var vn := n * v.dot(n)
				_prev[i] = _pos[i] - (v - vn * 1.2) * 0.85   # погасить нормаль, оставить касательную
				continue
		# 1b) аналитический барьер непроходимости (реестр AABB-тел карты)
		var ejected := ObstacleField.project_out(_pos[i])
		if ejected != _pos[i]:
			_pos[i] = ejected
			_prev[i] = ejected
			continue
		# 2) зонд вниз (точка уже внутри/под поверхностью после push-out)
		var q2 := PhysicsRayQueryParameters3D.create(_pos[i] + Vector3(0, 0.05, 0), _pos[i] - Vector3(0, 0.2, 0))
		q2.collide_with_bodies = true
		var hit2 := space_state.intersect_ray(q2)
		if not hit2.is_empty() and hit2.normal.y > 0.3:
			_pos[i].y = hit2.position.y + 0.01
			var v2 := _pos[i] - _prev[i]
			_prev[i] = _pos[i] - Vector3(v2.x * 0.9, -maxf(0.0, -v2.y) * 0.2, v2.z * 0.9)

func _sleep_check() -> void:
	for i in spec.points.size():
		if not _dyn[i]: continue
		var v := (_pos[i] - _prev[i]) * 60.0 * float(SUBSTEPS)
		if v.length() < 0.35:  # выше гравитационного приращения и микродрожжака релаксации
			_still[i] += 1
		else:
			_still[i] = 0
		_slow[i] = 0 if v.length() > 0.8 else _slow[i] + 1
		if _still[i] >= SLEEP_FRAMES or _slow[i] >= 240 or _age[i] >= 360:  # 4 с дрейфа / 6 с в dynamic -> сон
			var e := ObstacleField.project_out(_pos[i])
			_pos[i] = e; _prev[i] = e
			var orig: Vector3 = _chassis_xform() * spec.points[i]
			if _pos[i].distance_squared_to(orig) > params.length * params.length:
				_pos[i] = orig  # не запекать мусорные позиции (шипы)
			_rest_local[i] = _chassis_xform().affine_inverse() * _pos[i]
			_dyn[i] = false; _dyn_count -= 1

func _rebuild_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := params.shell_color * 0.85
	for t in spec.triangles.size() / 3:
		for vv in 3:
			var i: int = spec.triangles[t * 3 + vv]
			st.set_color(base.lerp(Color(0.16, 0.14, 0.13), 1.0 - _zone_hp[spec.zones[i]] / 100.0))
			st.add_vertex(_pt(i))
	st.generate_normals()
	st.index()
	_mesh.mesh = st.commit()

func debug_dyn() -> void:
	for i in spec.points.size():
		if _dyn[i]:
			var v := (_pos[i] - _prev[i]) * 120.0
			print("DYN pt "+str(i)+" v="+str(v.length())+" zone="+str(spec.zones[i])+" pos="+str(_pos[i]))

func point_count() -> int: return spec.points.size()
func point_world(i: int) -> Vector3: return _pt(i)
func dyn_count() -> int: return _dyn_count
func get_broken_total() -> int:
	var s := 0
	for z in broken_by_zone: s += z
	return s

func reset() -> void:
	for i in spec.points.size():
		_dyn[i] = false; _still[i] = 0; _slow[i] = 0; _rest_local[i] = spec.points[i]
	_dyn_count = 0
	_spring_on.fill(1)
	for k in spec.springs.size(): _spring_rest[k] = spec.springs[k].rest
	_stress.fill(0)
	broken_by_zone = [0, 0, 0, 0, 0]
	_zone_hp = [100.0, 100.0, 100.0, 100.0, 100.0]
	_rebuild_mesh()

func set_zone_hp(hp: Array[float]) -> void:
	_zone_hp = hp
