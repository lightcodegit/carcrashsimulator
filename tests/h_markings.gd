extends Node3D
# Разметка не должна делить плоскость ни с чем. Плита Kenney — корыто из трёх уровней
# (в местных координатах: трава y=0.0, асфальт y=0.1, белые полосы y=0.2), поэтому
# важны именно мировые высоты:
# 1) полотно приподнято над полом карты, но не выше тротуарного бордюра;
# 2) белая полоса ощутимо выше своего асфальта (10 см — настоящий поребрик);
# 3) ни одна горизонтальная грань ассетов не совпадает с плоскостью пола в пределах
#    2 мм — ровно это и давало мерцание, когда плиту топили на половину высоты.
const SEG := "road"          # дорожными считаем только сегменты road*
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

static func _tris(mesh: Mesh, surface: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	if idx.is_empty():
		for q in range(0, verts.size() - 2, 3):
			out.append(verts[q]); out.append(verts[q + 1]); out.append(verts[q + 2])
	else:
		for k in range(0, idx.size() - 2, 3):
			out.append(verts[idx[k]]); out.append(verts[idx[k + 1]]); out.append(verts[idx[k + 2]])
	return out

# Мировые высоты верхних горизонтальных граней поверхности с именем name_key.
static func _horiz(mesh: Mesh, tr: Transform3D, name_key: String) -> Array[float]:
	var ys: Array[float] = []
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat == null or mat.resource_name != name_key: continue
		var f := _tris(mesh, s)
		for q in range(0, f.size() - 2, 3):
			var a := tr * f[q]
			var b := tr * f[q + 1]
			var d := tr * f[q + 2]
			var n := (b - a).cross(d - a) + (d - a).cross(b - d) + (b - d).cross(a - b)
			if absf(n.y) > 0.9 * n.length(): ys.append(maxf(a.y, maxf(b.y, d.y)))
	return ys

# Минимальная мировая высота полотна сегмента — то же правило, по которому MapDB его
# и ставит. По горизонтальным граням нельзя: у рампы единственная горизонтальная грань
# полотна — это верхняя площадка на 2.6 м, а въезд наклонён.
static func _road_min(p: MeshInstance3D) -> float:
	var got := INF
	for s in p.mesh.get_surface_count():
		var mat := p.mesh.surface_get_material(s)
		if mat == null or mat.resource_name != "road": continue
		var v: PackedVector3Array = p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for q in v: got = minf(got, (p.global_transform * q).y)
	return got

static func _kits(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null and String(mesh.resource_path).begins_with("res://assets/racing/"):
			out.append(mi)
	for c in n.get_children():
		_kits(c, out)

# Мировая координата оси полотна плиты вдоль её поперечной оси. У roadStart она
# не в центре плиты (6.3 против 5.0 у обычных), и прямая постановка без поправки
# уводит белую линию арки на 1.3 м вбок — жалоба «кривые линии в начале Большого
# Города». Сравниваем арку с соседней плитой: ось обязана совпадать.
static func _lateral_center(p: MeshInstance3D) -> float:
	var cx := 0.0
	var n := 0
	for s in p.mesh.get_surface_count():
		var mat := p.mesh.surface_get_material(s)
		if mat == null or mat.resource_name != "road": continue
		for v in (p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			cx += v.x
			n += 1
	if n == 0: return INF
	var w: Vector3 = p.global_transform * Vector3(cx / float(n), 0.1, 10.0)
	return w.dot(p.global_transform.basis.x.normalized())

func _ready() -> void:
	await get_tree().process_frame
	for id in MapDB.ids():
		var m: Dictionary = MapDB.build(id)
		var root: Node3D = m.root
		add_child(root)
		await get_tree().physics_frame
		var kits: Array = []
		_kits(root, kits)
		# пол карты — главный источник мерцания: ни одна грань ассета не должна ложиться
		# ровно в его плоскость
		var on_floor := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			for s in ["road", "grey", "grass"]:
				for y in _horiz(p.mesh, p.global_transform, s):
					if absf(y - MapDB.FLOOR_Y) < 0.0005: on_floor += 1
		check(on_floor == 0, "%s: ни одна грань ассета не легла в плоскость пола (%d)" % [id, on_floor])
		var plates := 0
		var lifted := 0
		var proud := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			if not String(p.mesh.resource_path.get_file().get_basename()).begins_with(SEG): continue
			var lo := _road_min(p)
			if not is_finite(lo): continue
			plates += 1
			# Полотно лежит на 1–10 мм ВЫШЕ физической земли: меньше — грани совпадают и
			# мерцают, больше — колёса визуально проваливаются в дорогу.
			if lo > MapDB.FLOOR_Y + 0.0005 and lo < MapDB.FLOOR_Y + 0.010: lifted += 1
			for g in _horiz(p.mesh, p.global_transform, "grey"):
				if g - lo > 0.05 and g - lo < 0.30: proud += 1
		check(plates > 5, "%s: дорожных сегментов %d" % [id, plates])
		check(lifted == plates, "%s: полотно всех плит приподнято над полом (%d из %d)" % [id, lifted, plates])
		check(proud > 10, "%s: белая разметка выше своего асфальта (%d граней)" % [id, proud])
		var arches := 0
		for mi in kits:
			var p := mi as MeshInstance3D
			if String(p.mesh.resource_path.get_file().get_basename()) != "roadStart": continue
			var best: MeshInstance3D = null
			var bd := INF
			for mi2 in kits:
				var q := mi2 as MeshInstance3D
				if String(q.mesh.resource_path.get_file().get_basename()) != "roadStraightLong": continue
				# сравнивать можно только плиты с той же поперечной осью: у кольца рядом
				# плиты повёрнуты, и их «поперечная координата» считается в другом
				# направлении
				if absf(p.global_transform.basis.x.dot(q.global_transform.basis.x)) < 0.99: continue
				var d: float = p.global_position.distance_to(q.global_position)
				if d < bd: bd = d; best = q
			if best == null: continue
			var la := _lateral_center(p)
			var lb := _lateral_center(best)
			if not is_finite(la) or not is_finite(lb): continue
			if absf(la - lb) > 0.15:
				arches += 1
				print("  %s: арка на %.2f, соседняя плита на %.2f (сдвиг %.2f м)" % [
					id, la, lb, la - lb])
		check(arches == 0, "%s: арки старта стоят по оси улицы (%d со сдвигом)" % [id, arches])
		root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
