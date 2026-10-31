extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

# Дорожные плиты не должны лежать друг на друге: две копии белой разметки в одной
# плоскости мерцают (z-fighting). Трамплин и лежачий полицейский занимают свою плиту.
# Статичные декорации и припаркованные машины не должны ни проваливаться под
# поверхность, которую рисует карта, ни висеть над ней: и то, и другое видно на
# уровне глаз, а провал в 3 см я уже успел дважды занести, меняя высоту земли.
func _seated(root: Node3D) -> Array:
	var bad: Array[String] = []
	var checked := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if not (c_is_prop(n)): continue
		var box := _world_aabb(n as Node3D)
		if box.size.length() < 0.05: continue
		checked += 1
		var p := n as Node3D
		var surf := MapDB.surface_y(p.global_position.x, p.global_position.z)
		if box.position.y < surf - 0.006 or box.position.y > surf + 0.04:
			bad.append("%s: низ %.3f при поверхности %.3f" % [String(n.name), box.position.y, surf])
	return [bad, checked]

func c_is_prop(n: Node) -> bool:
	if n is Node3D and (n as Node3D).is_in_group(MapDB.GROUP_PARKED): return true
	var nm := String(n.name)
	if not (nm.begins_with("city_") or nm.begins_with("kit_") or nm.begins_with("props_")): return false
	# дорожные плиты — не предметы, а «ванны» с юбкой вниз на 10 см: их низ под
	# поверхностью по замыслу. Ищем по пути меша, а не по имени: имена Godot правит
	# молча, и различить kit_roadStart и kit_grassStart по имени нельзя.
	if _is_road_plate(n): return false
	return true

func _is_road_plate(n: Node) -> bool:
	if not (n is MeshInstance3D): return false
	var mi := n as MeshInstance3D
	if mi.mesh == null: return false
	return mi.mesh.resource_path.get_file().get_basename().begins_with("road")

func _world_aabb(n: Node3D) -> AABB:
	var m := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var g: AABB = mi.global_transform * mi.get_aabb()
			if first: m = g; first = false
			else: m = m.merge(g)
		for k in c.get_children(): stack.append(k)
	return m

func _road_overlaps(root: Node3D) -> Array[String]:
	var boxes: Array[AABB] = []
	var names: Array[String] = []
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null: continue
		if not mi.mesh.resource_path.get_file().begins_with("road"): continue
		boxes.append(mi.global_transform * mi.mesh.get_aabb())
		names.append(mi.mesh.resource_path.get_file() + "@" + str(mi.global_position.x))
	var bad: Array[String] = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a := boxes[i].intersection(boxes[j])
			if a.size.x * a.size.z > 0.05:
				bad.append(names[i] + " × " + names[j])
	return bad

func _ready() -> void:
	await get_tree().process_frame
	for id in ["arena", "town", "speedway"]:
		var m: Dictionary = MapDB.build(id)
		var root_map: Node3D = m.root
		var spawn: Transform3D = m.spawn
		var info: Dictionary = m.info
		add_child(root_map)
		check(info.colliders > 10, "%s has colliders (%d)" % [id, m.info.colliders])
		check(info.has_ramp or id == "town", "%s ramp expectation" % id)
		var ov := _road_overlaps(root_map)
		check(ov.is_empty(), "%s: дорожные плиты не наложены друг на друга (%s)" % [id, str(ov)])
		await get_tree().physics_frame
		var seat: Array = _seated(root_map)
		var sunk: Array = seat[0]
		check(seat[1] > 8, "%s: проверено посадкой %d объектов (иначе проверка пустая)" % [id, seat[1]])
		check(sunk.is_empty(), "%s: декорации стоят на поверхности (%s)" % [id, str(sunk.slice(0, 4))])
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		var from := spawn.origin + Vector3(0, 2.0, 0)
		# луч длиннее, чем от спавна до пола: верх пола на 1 см ниже нуля (см. FLOOR_Y),
		# и коротким лучом в самый ноль мы бы его не видели
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5.0, 0)))
		if hit.is_empty():
			check(false, "%s spawn over ground" % id)
		else:
			# пол карты на 1 см ниже нуля (FLOOR_Y), а плиты лежат поверх него
			check(hit.position.y > MapDB.FLOOR_Y - 0.001 and hit.position.y < 0.20,
				"%s: под спавном пол (%.3f)" % [id, hit.position.y])
		for dx in [-2.0, 2.0]:
			for dz in [-1.0, 1.0]:
				var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(m.spawn.origin + Vector3(dx, 2.5, dz), m.spawn.origin + Vector3(dx, 0.05, dz)))
				check(h2.is_empty(), "%s spawn clear at %s,%s" % [id, dx, dz])
		# Рельеф обязан быть твёрдым: и горка, и бугор. Без коллайдера по ним ехал
		# невидимый пол — машина не прыгала, а сбитый предмет проваливался внутрь
		# бугра и зависал в геометрии (жалоба «объекты проходят сквозь бугры»).
		# Ищем именно вершину: луч в угол плиты ничего не доказывает.
		for c in root_map.get_children():
			var mi := c as MeshInstance3D
			if mi == null: continue
			var n := String(mi.name)
			if not (n.contains("roadRamp") or n.contains("roadBump")): continue
			var box := _world_aabb(mi)
			var top := MapDB.FLOOR_Y + 0.2
			var best := -1e9
			for fx in [0.25, 0.5, 0.75]:
				for fz in [0.25, 0.5, 0.75]:
					var p := Vector3(box.position.x + box.size.x * fx, box.end.y + 1.0,
						box.position.z + box.size.z * fz)
					var relief := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -8.0, 0)))
					if not relief.is_empty(): best = maxf(best, relief.position.y)
			check(best > top, "%s: %s твёрдый на своей высоте (лучше всего %.2f м, ждали > %.2f)" % [
				id, n, best, top])
		m.root.queue_free()
		await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
