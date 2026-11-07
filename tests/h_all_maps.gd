extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	# Все карты, а не четыре из шести: circuit и endless иначе не получают ни
	# посадки, ни света, ни материалов ни у одного теста. Машины — короткая и
	# длиннобазная, чтобы база и свесы проверялись на каждой карте без тройного
	# времени прогона.
	for map_id in MapDB.ids():
		for car_id in ["sedan", "limousine"]:
			GameContext.select(car_id, map_id)
			var gm: GameManager = load("res://scenes/game.tscn").instantiate()
			add_child(gm)
			for f in 30:
				await get_tree().physics_frame
			check(gm.car != null and gm.car.chassis != null, "%s/%s car built" % [map_id, car_id])
			check(gm.hud != null and gm.camera != null, "%s/%s hud+camera" % [map_id, car_id])
			var nose := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
			gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
			check(gm.car.body.dent_count > 0, "%s/%s dent applied" % [map_id, car_id])
			check(gm.car.body.deformation() > 0.05, "%s/%s body deformed (%.2f м)" % [map_id, car_id, gm.car.body.deformation()])
			gm._respawn_now()
			check(gm.car.body.dent_count == 0 and gm.car.body.deformation() < 1e-6, "%s/%s respawn restored body" % [map_id, car_id])
			# Кузовная краска: блеск дают лак и низкая шероховатость, а не metallic —
			# он гасит диффуз, и машина в тени чернеет.
			var mat: StandardMaterial3D = gm.car.body._mat
			check(mat.metallic <= 0.25, "%s/%s металличность низкая (%.2f)" % [map_id, car_id, mat.metallic])
			check(mat.roughness < 0.5, "%s/%s краска глянцевая (roughness %.2f)" % [map_id, car_id, mat.roughness])
			check(mat.clearcoat_enabled and mat.clearcoat > 0.3,
				"%s/%s лак включён (%.2f)" % [map_id, car_id, mat.clearcoat])
			check(mat.albedo_texture != null, "%s/%s текстура colormap на месте" % [map_id, car_id])
			check(mat.vertex_color_use_as_albedo, "%s/%s vertex color для потёртостей включён" % [map_id, car_id])
			var suns := 0
			var amb := false
			var long_shadow := false
			var env: Environment = null
			for c in gm.get_children():
				if c is DirectionalLight3D:
					suns += 1
					long_shadow = long_shadow or (c as DirectionalLight3D).directional_shadow_max_distance >= 100.0
				if c is WorldEnvironment: env = (c as WorldEnvironment).environment
			if env != null:
				# на Compatibility небо тёмное, и свет от него дают ровным цветом — см. GameManager
				amb = env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY \
					or (env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
						and env.ambient_light_energy > 0.1 and env.ambient_light_color.v > 0.4)
			check(suns >= 2, "%s/%s солнце плюс заполняющий свет (%d)" % [map_id, car_id, suns])
			check(amb, "%s/%s рассеянный свет от неба" % [map_id, car_id])
			check(long_shadow, "%s/%s тени хватает за машину с запасом" % [map_id, car_id])
			# окружение: физическое небо, дымка и экранный непрямой свет — иначе кузова
			# в тени домов остаются чёрными, а дальние карты обрываются
			# Небо — процедурный градиент: физическое на этом движке даёт «молоко»
			# (замер: синий минус красный 0.046 против 0.121). Проверяется сам факт
			# gradient-неба с синим зенитом, а не конкретный класс материала.
			var sm := (env.sky.sky_material if env != null and env.sky != null else null) as ProceduralSkyMaterial
			check(sm != null and sm.sky_top_color.b > sm.sky_top_color.r + 0.3,
				"%s/%s небо — градиент с синим зенитом" % [map_id, car_id])
			check(env != null and env.fog_enabled and env.fog_density > 0.0,
				"%s/%s дымка включена" % [map_id, car_id])
			# SSIL живёт только на Forward+: на Compatibility движок его не знает, и
			# требовать его было бы требованием несуществующей настройки
			check(env != null and env.ssil_enabled == (Settings.ssil and Settings.supports_ssil()),
				"%s/%s экранный непрямой свет следует настройке и движку" % [map_id, car_id])
			check(env != null and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
				"%s/%s отражения от неба" % [map_id, car_id])
			if map_id == "bigcity" and car_id == "sedan":
				_check_surface_index()
			gm.queue_free()
			await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Индекс поверхностей против полного перебора: сравнение и по значению, и по
# цене в одном процессе — так проверка не зависит от скорости машины, на которой
# бежит. До сетки surface_y и был перебором, поэтому соотношение было 1.0.
func _check_surface_index() -> void:
	var surfaces := MapKit.surfaces()
	check(surfaces.size() > 200, "на городе есть что индексировать (%d поверхностей)" % surfaces.size())
	if surfaces.size() <= 1: return
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 20261107
	var pts: Array[Vector2] = []
	for i in 4000:
		# точку берём внутри случайного прямоугольника: иначе половина запросов
		# уходила бы в промах и не трогала индекс вовсе
		var rect: AABB = surfaces[rnd.randi() % surfaces.size()]["rect"]
		pts.append(Vector2(rnd.randf_range(rect.position.x, rect.end.x),
			rnd.randf_range(rect.position.z, rect.end.z)))
	for i in 200:
		pts.append(Vector2(9000.0 + float(i), 9000.0))
	var brute := func(p: Vector2) -> float:
		var g := INF
		for r in surfaces:
			if (r["rect"] as AABB).has_point(Vector3(p.x, 0.0, p.y)): g = minf(g, float(r["y"]))
		return g if is_finite(g) else MapDefs.FLOOR_Y + 0.001
	var same := 0
	for p in pts:
		if is_equal_approx(brute.call(p), MapKit.surface_y(p.x, p.y)): same += 1
	check(same == pts.size(),
		"сетка отдаёт ровно те же высоты, что перебор (%d из %d)" % [same, pts.size()])
	var tb := Time.get_ticks_usec()
	for p in pts: brute.call(p)
	tb = Time.get_ticks_usec() - tb
	var tg := Time.get_ticks_usec()
	for p in pts: MapKit.surface_y(p.x, p.y)
	tg = Time.get_ticks_usec() - tg
	check(tg * 3 < tb,
		"индекс быстрее перебора втрое на тех же точках (%d мкс против %d)" % [tg, tb])
	print("NOTE: surface_y %d запросов: перебор %d мкс, сетка %d мкс, ускорение %.1f×" %
		[pts.size(), tb, tg, float(tb) / maxf(float(tg), 1.0)])
