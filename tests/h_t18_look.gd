extends Node3D
# Доводка материалов: Kenney отдаёт плоский диффуз (roughness 1, metallic 0, без
# specular), из-за чего асфальт выглядит бумагой, а кузова в тени чернеют. Проверяем,
# что после Materials.apply_tree у дорожных поверхностей появились процедурные карты
# шероховатости и нормалей, у припаркованных машин — лак, а у процедурных коробок
# MapDB — зерно бетона.
var _fails := 0
var _road := 0
var _road_pbr := 0
var _flat := 0
var _cars := 0
var _cars_clear := 0
var _boxes := 0
var _boxes_pbr := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _scan(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := _mat_of(mi, i)
				if mat == null: continue
				if mat.resource_name == "road":
					_road += 1
					if mat.roughness_texture != null and mat.normal_enabled: _road_pbr += 1
					if mat.roughness >= 1.0 and mat.metallic == 0.0: _flat += 1
				elif mat.resource_name == "concrete":
					_boxes += 1
					if mat.roughness_texture != null and mat.normal_enabled: _boxes_pbr += 1
	for c in n.get_children():
		_scan(c)

func _mat_of(mi: MeshInstance3D, i: int) -> StandardMaterial3D:
	var over := mi.get_surface_override_material(i)
	var mat: Material = over if over != null else mi.mesh.surface_get_material(i)
	return mat as StandardMaterial3D

# Припаркованная машина — та же краска, что и у игрока: лак вместо голого диффуза.
func _scan_car(n: Node) -> void:
	var found := false
	var clear := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				found = true
				var mat := _mat_of(mi, 0)
				if mat != null and mat.clearcoat_enabled and mat.clearcoat > 0.3: clear = true
		for k in c.get_children():
			stack.append(k)
	if found:
		_cars += 1
		if clear: _cars_clear += 1

func _ready() -> void:
	await get_tree().process_frame
	for id in ["arena", "town", "speedway"]:
		_road = 0; _road_pbr = 0; _flat = 0
		_cars = 0; _cars_clear = 0
		_boxes = 0; _boxes_pbr = 0
		var m: Dictionary = MapDB.build(id)
		var root: Node3D = m.root
		add_child(root)
		_scan(root)
		for c in get_tree().get_nodes_in_group(MapDB.GROUP_PARKED):
			_scan_car(c)
		check(_road > 10, "%s: дорожные поверхности найдены (%d)" % [id, _road])
		check(_road_pbr == _road, "%s: у всего асфальта есть карты шероховатости и нормалей (%d из %d)" % [id, _road_pbr, _road])
		check(_flat == 0, "%s: не осталось плоского диффуза roughness=1 (%d)" % [id, _flat])
		check(_boxes > 0 and _boxes_pbr == _boxes, "%s: процедурные коробки с зерном бетона (%d из %d)" % [id, _boxes_pbr, _boxes])
		if id == "town":
			check(_cars >= 6, "%s: припаркованные машины найдены (%d)" % [id, _cars])
			check(_cars == _cars_clear, "%s: у всех припаркованных машин есть лак (%d из %d)" % [id, _cars_clear, _cars])
		root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
