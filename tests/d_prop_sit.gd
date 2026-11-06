extends SceneTree
# Два контракта расстановки предметов, на РЕАЛЬНЫХ координатах.
# ВАЖНО: в _initialize глобальные трансформации ещё не вычислены, и global_position
# у собранной, но не вставленной в дерево карты возвращает (0,0,0). Первый вариант
# проверки именно на это и наткнулся: 703 тела «стояли» в начале координат, и тест
# молча проверял surface_y(0, 0). Берём локальный position — корень карты единичный.
func _initialize() -> void:
	var fails := 0
	for id in MapDB.ids():
		MapKit.clear_surfaces()
		var m: Dictionary = MapDB.build(id)
		var root: Node3D = m.root
		var sunk := 0
		var worst := 0.0
		var total := 0
		var rings := 0
		var wrong := 0
		for c in root.get_children():
			if not (c is RigidBody3D): continue
			var body := c as RigidBody3D
			total += 1
			var p := body.position
			var chosen := MapKit.surface_y(p.x, p.z)
			var top := chosen
			for r in MapKit.surfaces():
				if (r["rect"] as AABB).has_point(Vector3(p.x, 0.0, p.z)):
					top = maxf(top, float(r["y"]))
			if top - chosen > 0.005:
				sunk += 1
				worst = maxf(worst, top - chosen)
			# скамейки кольца у фонтана стоят ровно на радиусе 24 и обязаны смотреть
			# на фонтан, а не вдоль него: local +Z после rotation.y = (sin, cos)
			for park in MapDefs.BC_PARKS:
				var dx := p.x - float(park[0])
				var dz := p.z - float(park[1])
				var d := sqrt(dx * dx + dz * dz)
				if absf(d - 24.0) > 0.02: continue
				rings += 1
				var th := body.rotation.y
				if (sin(th) * -dx + cos(th) * -dz) / maxf(d, 1e-6) < 0.9: wrong += 1
		print("%-9s тел %d, провалившихся %d, худшее %.3f м; скамеек кольца %d, не на фонтан %d" % [
			id, total, sunk, worst, rings, wrong])
		# пустой обход выглядит как «всё чисто»: тела на карте обязаны быть
		if total < 5:
			print("FAIL: %s: динамических тел %d, проверять нечего" % [id, total])
			fails += 1
		if sunk > 0 or wrong > 0: fails += 1
		# кольца скамеек есть только в Большом Городе: 4 парка по 6 скамеек
		if id == "bigcity" and rings < 24:
			print("FAIL: скамеек кольца %d, а должно быть не меньше 24" % rings)
			fails += 1
		root.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
