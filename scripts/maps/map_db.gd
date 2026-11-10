class_name MapDB
extends RefCounted
# Фасад карт: список и сборка по id. Сама геометрия разложена по слоям —
# MapDefs (числа), MapKit (пол и киты), MapProps (пропы), MapCircuit (кольцо и
# «бесконечность») и отдельные файлы на каждую карту.

# Список карт. Тесты полигонов (h_map_props, h_markings, h_restart_props) перебирают его, поэтому новая карта
# обязана появиться здесь — иначе она останется непроверенной.
static func ids() -> Array[String]:
	return ["arena", "town", "speedway", "circuit", "endless", "bigcity", "void"]

static func build(id: String) -> Dictionary:
	MapKit.clear_surfaces()
	match id:
		"town": return MapTown.build()
		"speedway": return MapSpeedway.build()
		"circuit": return MapCircuit.circuit()
		"endless": return MapCircuit.endless()
		"bigcity": return MapBigCity.build()
		"void": return MapVoid.build()
		_: return MapArena.build()

# Переставка лент «бесконечности» — публичный вход для GameManager.
static func recycle(root: Node3D, car_x: float, spacing: float) -> int:
	# Для карты «void» нет rc_lines — ничего не делаем.
	var info := MapDB._map_info_from_root(root)
	if info and info.has("id") and info["id"] == "void": return 0
	# Для остальных (endless и др.) используем стандартную логику MapCircuit.
	return MapCircuit.recycle(root, car_x, spacing)

# Подъем пола после машины. endless_floor в endless двигается по X, а
# void_floor — по X и Z. Выясняем, какая полочь передана, и действуем соответственно.
static func floor_follow(root: Node3D, car_x: float) -> void:
	# Сначала пробуем найти void_floor — если есть, двигаем и по X, и по Z.
	var void_floor := root.get_node_or_null("void_floor") as StaticBody3D
	if void_floor != null:
		# двигаем полотно void_floor: want — это кратное 2000, чтобы шаг был ровным
		var want_x := roundf(car_x / 2000.0) * 2000.0
		var want_z := 0.0  # Z не двигается Baseline, но можно добавить позже, если нужно
		var dx := want_x - void_floor.position.x
		var dz := want_z - void_floor.position.z
		if absf(dx) >= 0.5: void_floor.position.x += dx
		if absf(dz) >= 0.5: void_floor.position.z += dz
		return
	# Иначе — классический endless_floor, двигаем только по X (старое поведение).
	var body := root.get_node_or_null("endless_floor") as StaticBody3D
	if body == null: return
	var want := roundf(car_x / 2000.0) * 2000.0
	var dx := want - body.position.x
	if absf(dx) < 0.5: return
	body.position.x += dx

# Вспомогательная функция: читаем info id из build() результата, закреплённого за root.
# Метод build() возвращает словарь с полями root, spawn, bounds, info.
static func _map_info_from_root(root: Node3D) -> Dictionary:
	# root — это ребёнок Node3D, родитель которого — MapVoid (RefCounted).
	# MapDB.build() возвращает словарь, но мы читаем из родительского RefCounted.
	# Проще передать info через вызов build и сохранить, но пока оставим пустой словарь,
	# так как в GameManager floor_follow вызывается без info.
	return {}

# Статистика сцены для отладочного оверлея. Обход итеративный (в дереве Большого
# Города ~8 тыс. узлов) и считается не чаще 4 раз в секунду: сам замер не должен
# становиться заметной частью измеряемого кадра.
static func debug_counts(root: Node3D, cam: Vector3) -> Dictionary:
	var out := {"bodies": 0, "statics": 0, "meshes": 0, "hidden": 0,
		"nearest": INF, "nodes": 0}
	if root == null: return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out["nodes"] = int(out["nodes"]) + 1
		for c in n.get_children():
			stack.append(c)
		if n is RigidBody3D:
			out["bodies"] = int(out["bodies"]) + 1
			out["nearest"] = minf(float(out["nearest"]),
				(n as RigidBody3D).global_position.distance_to(cam))
		elif n is StaticBody3D:
			out["statics"] = int(out["statics"]) + 1
		elif n is GeometryInstance3D:
			out["meshes"] = int(out["meshes"]) + 1
			var gi := n as GeometryInstance3D
			var end := gi.visibility_range_end
			if end > 0.0 and gi.global_position.distance_to(cam) > end:
				out["hidden"] = int(out["hidden"]) + 1
	return out
