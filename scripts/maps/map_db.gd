class_name MapDB
extends RefCounted
# Фасад карт: список и сборка по id. Сама геометрия разложена по слоям —
# MapDefs (числа), MapKit (пол и киты), MapProps (пропы), MapCircuit (кольцо и
# «бесконечность») и отдельные файлы на каждую карту.

# Список карт. Тесты полигонов (h_map_props, h_markings, h_restart_props) перебирают его, поэтому новая карта
# обязана появиться здесь — иначе она останется непроверенной.
static func ids() -> Array[String]:
	return ["arena", "town", "speedway", "circuit", "endless", "bigcity"]

static func build(id: String) -> Dictionary:
	MapKit.clear_surfaces()
	match id:
		"town": return MapTown.build()
		"speedway": return MapSpeedway.build()
		"circuit": return MapCircuit.circuit()
		"endless": return MapCircuit.endless()
		"bigcity": return MapBigCity.build()
		_: return MapArena.build()

# Переставка лент «бесконечности» — публичный вход для GameManager.
static func recycle(root: Node3D, car_x: float, spacing: float) -> int:
	return MapCircuit.recycle(root, car_x, spacing)

static func floor_follow(root: Node3D, car_x: float) -> void:
	MapCircuit.floor_follow(root, car_x)

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
