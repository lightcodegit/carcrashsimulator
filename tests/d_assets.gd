extends SceneTree
# Ассеты Kenney Car Kit (CC0): структура машин, наличие кузова и колёс,
# опора на землю, валидность городских моделей и пропов.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _list(dir: String) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null: return out
	for f in da.get_files():
		if f.ends_with(".glb"): out.append(dir + "/" + f)
	return out

func _initialize() -> void:
	for id in VehicleDB.ids():
		var p = VehicleDB.get_params(id)
		# отсутствие параметров — это провал, а не повод промолчать: молча пропущенная
		# машина выглядела как зелёный тест
		check(p != null, "%s: параметры найдены" % id)
		if p == null: continue
		var ps: PackedScene = load(p.model)
		check(ps != null, "%s scene loads" % id)
		if ps == null: continue
		var n: Node3D = ps.instantiate()
		var bodies := 0; var wheels := 0; var front := 0
		var min_y := INF
		var uv_ok := true
		for c in n.get_children():
			var mi := c as MeshInstance3D
			if mi == null: continue
			var nm := String(c.name).to_lower()
			if nm == "body":
				bodies += 1
				var arr := mi.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				check(verts.size() > 200, "%s body has geometry (%d вершин)" % [id, verts.size()])
				check(idx.size() > 0 and idx.size() % 3 == 0, "%s body is indexed (%d)" % [id, idx.size()])
				check(uv.size() == verts.size(), "%s body has UVs (%d/%d)" % [id, uv.size(), verts.size()])
				if uv.size() != verts.size(): uv_ok = false
			elif nm.begins_with("wheel"):
				wheels += 1
				if nm.contains("front"): front += 1
			var g: AABB = mi.transform * mi.get_aabb()
			min_y = minf(min_y, g.position.y)
		check(bodies == 1, "%s has exactly one 'body' node (%d)" % [id, bodies])
		check(wheels == 4, "%s has 4 wheels (%d)" % [id, wheels])
		check(front == 2, "%s has 2 front wheels (%d)" % [id, front])
		check(absf(min_y) < 0.02, "%s rests on y=0 (%.3f)" % [id, min_y])
		check(uv_ok, "%s UVs usable for dents" % id)
		n.free()
	var city := _list("res://assets/city")
	var props := _list("res://assets/props")
	check(city.size() >= 8, "city assets present (%d)" % city.size())
	check(props.size() >= 3, "prop assets present (%d)" % props.size())
	for path in city + props:
		var a: AABB = DentBody.measure(path).aabb
		check(a.size.length() > 0.1, "%s has a sane AABB (%s)" % [path.get_file(), str(a.size)])
		check(a.position.y > -0.35, "%s sits on the ground plane (%.2f)" % [path.get_file(), a.position.y])
	check(FileAccess.file_exists("res://assets/LICENSE-kenney-car-kit.txt"), "CC0 license file shipped")
	check(FileAccess.file_exists("res://assets/racing/LICENSE-kenney-racing-kit.txt"),
		"racing kit CC0 license file shipped")
	# The repo goes public with this file as the only grant for the code: an empty
	# or truncated LICENSE still "exists", so the marker text is what is checked.
	check(FileAccess.file_exists("res://LICENSE"), "code license shipped")
	var lic := FileAccess.get_file_as_string("res://LICENSE")
	check(lic.contains("MIT License") and lic.contains("Permission is hereby granted"),
		"LICENSE is the MIT text, not a stub (%d bytes)" % lic.length())
	check(lic.contains("Copyright (c)"), "LICENSE carries a copyright line")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
