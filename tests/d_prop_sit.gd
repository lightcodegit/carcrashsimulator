extends SceneTree
# Дата-тест: предмет должен стоять на ВЕРХНЕЙ поверхности под ним. surface_y берёт
# minf по всем прямоугольникам — если тротуарная плита (y=0.028) перекрывается с
# дорожной плитой (y≈0), предмет проваливается в плиту на разницу высот.
func _initialize() -> void:
	var fails := 0
	for id in MapDB.ids():
		MapDB._surfaces.clear()
		var m: Dictionary = MapDB.build(id)
		var root: Node3D = m.root
		var sunk := 0
		var worst := 0.0
		var total := 0
		for c in root.get_children():
			if not (c is RigidBody3D): continue
			total += 1
			var p := (c as RigidBody3D).global_position
			var chosen := MapDB.surface_y(p.x, p.z)
			var top := chosen
			for r in MapDB._surfaces:
				if (r["rect"] as AABB).has_point(Vector3(p.x, 0.0, p.z)):
					top = maxf(top, float(r["y"]))
			if top - chosen > 0.005:
				sunk += 1
				worst = maxf(worst, top - chosen)
		print("%-9s тел %d, провалившихся %d, худшее %.3f м" % [id, total, sunk, worst])
		if sunk > 0: fails += 1
		root.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
