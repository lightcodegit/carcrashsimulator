class_name MapBigCity
extends RefCounted
# «БОЛЬШОЙ ГОРОД»: километр на километр, кольцо, сетка улиц, районы,
# парки, стадион и плотная обвеска тротуаров.

# «БОЛЬШОЙ ГОРОД» — километр на километр: периметр-кольцо, внутренняя сетка улиц
# и 16 кварталов, поделённых на районы — деловой центр, жилые кварталы, промзона,
# парк и стадион. Раскладка детерминирована (постоянный seed): игрок сравнивает
# заезды между запусками, а h_all_maps строит каждый раз один и тот же город.
# Кольцо сходится точно: четыре равных прямых по 45 плит и четыре одинаковых
# поворота — угловые смещения взаимно гасятся (тот же расчёт, что на «ГОНКЕ»).
static func build() -> Dictionary:
	var root := Node3D.new(); root.name = "BigCity"
	MapKit.box(root, Vector3(0, MapDefs.FLOOR_Y - 1.0, 0), Vector3(1160, 2, 1160), Color(0.40, 0.41, 0.43),
		Basis.IDENTITY, true)
	var rng := RandomNumberGenerator.new(); rng.seed = 20261102
	var t := MapCircuit.TrackCursor.new()
	t.root = root
	t.pos = Vector3(-450.0, 0.0, -450.0)
	t.h = 1
	for edge in 4:
		for k in 45:
			t.tile("roadStraightLong")
		t.tile("roadCornerLarger")
	# внутренняя сетка: три улицы вдоль X и три вдоль Z; плиту убираем, если её
	# отпечаток пересекается с полосой встречной улицы (ширина полосы 10, плита 20 —
	# окно ±20), а разрыв перекрываем прямоугольником асфальта в уровне плит
	for lane in [-220.0, 0.0, 220.0]:
		for k in 41:
			var x := -400.0 + k * 20.0
			if _bc_crosses(x, -220.0) or _bc_crosses(x, 0.0) or _bc_crosses(x, 220.0): continue
			# под бульварными горкой и буграми плит не должно быть: двойное полотно
			if is_equal_approx(lane, 0.0) and (is_equal_approx(x, -140.0) or is_equal_approx(x, 120.0)
					or (x >= 279.0 and x <= 321.0)): continue
			MapKit.kit(root, "roadStraightLong", Vector3(x, 0, lane + 5.0), 90, false, true)
	for lane in [-220.0, 0.0, 220.0]:
		for k in 41:
			var z := -400.0 + k * 20.0
			if _bc_crosses(z, -220.0) or _bc_crosses(z, 0.0) or _bc_crosses(z, 220.0): continue
			MapKit.kit(root, "roadStraightLong", Vector3(lane - 5.0, 0, z), 0, false, true)
	for ix in [-220.0, 0.0, 220.0]:
		for iz in [-220.0, 0.0, 220.0]:
			MapKit.box_vis(root, Vector3(ix, MapDefs.ROAD_TOP + 0.012, iz), Vector3(40, 0.02, 40), Color(0.30, 0.30, 0.33))
			MapKit.add_surface({"rect": AABB(Vector3(ix - 20.0, 0.0, iz - 20.0), Vector3(40.0, 0.0, 40.0)),
				"y": MapDefs.ROAD_TOP + 0.022})
			# бордюр плиты — барьер 0.2 м по краю полосы; на стыке с заплаткой он
			# обрывался вертикальной стенкой («поломанная разметка»). Продолжаем его
			# через заплатку с разрывом 10 м под встречную улицу: поворот остаётся
			# открыт, а линия борта читается непрерывно — в размер самого борта
			# (RAIL_*), иначе стык даёт ступеньку и по высоте, и по ширине
			var rail_c := (MapDefs.RAIL_IN + MapDefs.RAIL_OUT) * 0.5
			var rail_w := MapDefs.RAIL_OUT - MapDefs.RAIL_IN
			for s in [-1.0, 1.0]:
				MapKit.box_vis(root, Vector3(ix + s * 12.5, MapDefs.RAIL_TOP - 0.09, iz + rail_c),
					Vector3(15, 0.18, rail_w), Color(0.85, 0.85, 0.88))
				MapKit.box_vis(root, Vector3(ix + s * 12.5, MapDefs.RAIL_TOP - 0.09, iz - rail_c),
					Vector3(15, 0.18, rail_w), Color(0.85, 0.85, 0.88))
				MapKit.box_vis(root, Vector3(ix + rail_c, MapDefs.RAIL_TOP - 0.09, iz + s * 12.5),
					Vector3(rail_w, 0.18, 15), Color(0.85, 0.85, 0.88))
				MapKit.box_vis(root, Vector3(ix - rail_c, MapDefs.RAIL_TOP - 0.09, iz + s * 12.5),
					Vector3(rail_w, 0.18, 15), Color(0.85, 0.85, 0.88))
	# бульвар: арка на въезде, два «лежачих полицейских» и трамплин перед восточным
	# кварталом — на длинной прямой до кольца разгон до 200 км/ч и прыжок честные
	# арка на въезде: у roadStart ось полотна в 6.3 м от края плиты (см. _SEG), а не в 5,
	# как у обычных плит — ставим её на lane + 6.3, иначе разметка арки уходит на 1.3 м
	# вбок от линии улицы («кривые белые линии в начале карты»)
	MapKit.kit(root, "roadStart", Vector3(-420.0, 0, 6.3), 90, true, true)
	MapKit.kit(root, "roadBump", Vector3(-140.0, 0, 5.0), 90, true, true, Vector3(1.0, MapDefs.BUMP_Y, 1.0))
	MapKit.kit(root, "roadBump", Vector3(120.0, 0, 5.0), 90, true, true, Vector3(1.0, MapDefs.BUMP_Y, 1.0))
	MapKit.kit(root, "roadRampLong", Vector3(280.0, 0, 5.0), 90, true, true, Vector3(1.0, 1.0, 3.0))
	# деловой центр: четыре квартала у слияния осей — процедурные башни разной
	# высоты и цвета (Kenney-набор домов для «высоток» мал: домики даже втрое
	# больше выглядят домиками), фонари на каждом перекрёстке, щиты и припаркованные
	# машины между ними. Башня = box(): стена с честным коллайдером — в центр
	# можно влететь на 200 км/ч, и кузов сложится о неё, как о настоящий город.
	var tower_cols: Array[Color] = [Color(0.27, 0.31, 0.40), Color(0.46, 0.47, 0.50),
		Color(0.52, 0.36, 0.28), Color(0.33, 0.36, 0.38)]
	var types: Array[String] = ["building-type-a", "building-type-b", "building-type-c",
		"building-type-d", "building-type-e", "building-type-f"]
	var parked: Array[String] = [MapDefs.CARS + "sedan.glb", MapDefs.CARS + "truck.glb", MapDefs.CARS + "race.glb"]
	for cx in [-110.0, 110.0]:
		for cz in [-110.0, 110.0]:
			for gx in 3:
				for gz in 3:
					var w := 16.0 + rng.randf() * 8.0
					var d := 16.0 + rng.randf() * 8.0
					var h := 22.0 + rng.randf() * 46.0
					var px: float = cx - 60.0 + gx * 60.0 + rng.randf_range(-8.0, 8.0)
					var pz: float = cz - 60.0 + gz * 60.0 + rng.randf_range(-8.0, 8.0)
					MapKit.box(root, Vector3(px, h * 0.5, pz), Vector3(w, h, d),
						tower_cols[rng.randi() % tower_cols.size()])
			for cz2 in [-110.0, 110.0]:
				MapKit.kit(root, "lightColored", Vector3(cx + 60.0, 0, cz2 - 5.0), 0, true, false)
			MapKit.kit(root, "billboard", Vector3(cx - 70.0, 0, cz), 90, true, false)
			for n in 2:
				MapProps.prop(root, parked[rng.randi() % parked.size()], Vector3(cx - 20.0 + n * 40.0, 0,
					cz + 78.0), 1.0, PI * 0.5, true)
	# жилые кварталы: домики поменьше, заборы, деревья, сбитые конусы у въезда
	for block in [[-110.0, 335.0], [110.0, 335.0], [110.0, -335.0]]:
		var cx: float = block[0]
		var cz: float = block[1]
		for n in 10:
			var p := _bc_spot(rng, cx, cz, 84.0)
			var s := 7.0 + rng.randf() * 3.5
			var rot := float(rng.randi() % 4) * PI * 0.5
			MapProps.prop(root, MapDefs.A + types[rng.randi() % types.size()] + ".glb", p, s, rot, true)
		for n in 3:
			MapProps.prop(root, MapDefs.A + "fence-1x4.glb", Vector3(cx - 70.0 + n * 52.0, 0, cz + 80.0), 4.0, 0.0, true)
		for n in 4:
			MapProps.prop(root, MapDefs.A + ("tree-large.glb" if n % 2 == 0 else "tree-small.glb"),
				_bc_spot(rng, cx, cz, 84.0), 7.0, 0.0, true)
		for n in 2:
			MapProps.prop(root, parked[rng.randi() % parked.size()], Vector3(cx + 30.0 + n * 34.0, 0,
				cz - 84.0), 1.0, -PI * 0.5, true)
		for n in 3:
			MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(cx - 40.0 + n * 5.0, 0, cz - 60.0), MapDefs.PROP, 0.0, 3.0)
	# промзона: длинные ангары-коробки с темной крышей, склады-тенты, забор по
	# фасаду, контейнеры и покрышки на площадке, радар и вышки освещения
	for cx in [335.0, -335.0]:
		for cz in [335.0, -110.0]:
			for n in 3:
				var sx: float = cx - 60.0 + n * 60.0
				MapKit.box(root, Vector3(sx, 6.0, cz - 30.0), Vector3(44.0, 12.0, 26.0), Color(0.55, 0.56, 0.58))
				MapKit.box(root, Vector3(sx, 12.4, cz - 30.0), Vector3(40.0, 0.8, 22.0), Color(0.30, 0.31, 0.34))
			MapKit.kit(root, "tentLong", Vector3(cx - 30.0, 0, cz + 40.0), 0, true, false)
			MapKit.kit(root, "tent", Vector3(cx + 50.0, 0, cz + 40.0), 0, true, false)
			MapKit.kit(root, "pitsOffice", Vector3(cx + 70.0, 0, cz - 70.0), 90, true, false)
			MapKit.kit(root, "lightRedDouble", Vector3(cx - 80.0, 0, cz + 80.0), 0, true, false)
			for n in 5:
				MapKit.kit(root, "fenceStraight", Vector3(cx - 80.0 + n * 40.0, 0, cz - 92.0), 0, true, false)
			for n in 4:
				MapProps.loose(root, MapDefs.P + "box.glb", Vector3(cx - 60.0 + n * 40.0, 0, cz - 80.0), MapDefs.PROP,
					rng.randf() * 3.0, 15.0)
			for n in 3:
				MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(cx - 40.0 + n * 40.0, 0, cz - 66.0), MapDefs.PROP,
					0.0, 10.0)
	# парк: живой газон одним ковром (тёмные плитки kit grass на общем светлом
	# фоне читались как провалы), аллея больших деревьев, клумбы и низкие щиты
	# Парки: (-335,-110) из списка убран — этот квартал занимает промзона, и скамейки
	# круговой посадки рождались внутри ангаров (solver выталкивал их на 0.8 м вниз,
	# ловит h_restart_props). Взаём взят (335,110): до этого он не достался никому,
	# и в городе был один пустой блок.
	for block in MapDefs.BC_PARKS:
		var cx: float = block[0]
		var cz: float = block[1]
		MapKit.box_vis(root, Vector3(cx, 0.015, cz), Vector3(180, 0.03, 180), Color(0.30, 0.46, 0.28))
		for n in 10:
			MapKit.kit(root, "treeLarge", _bc_spot(rng, cx, cz, 84.0), float(rng.randi() % 4) * 90.0,
				true, false)
		for n in 4:
			MapKit.kit(root, "treeSmall", _bc_spot(rng, cx, cz, 84.0), 0, true, false)
		for n in 5:
			MapProps.prop(root, MapDefs.A + "planter.glb", _bc_spot(rng, cx, cz, 70.0), 3.2, 0.0, true)
		MapKit.kit(root, "billboardLow", Vector3(cx, 0, cz + 95.0), 0, true, false)
	# стадион: крытые трибуны каре, арка в центре и клетчатые флаги — с трамплина
	# бульвара сюда можно долететь по прямой
	for side in 4:
		for n in 4:
			var along := -60.0 + n * 40.0
			var sp := Vector3(335.0, 0, -335.0)
			match side:
				0: sp += Vector3(along, 0, -95.0)
				1: sp += Vector3(along, 0, 95.0)
				2: sp += Vector3(-95.0, 0, along)
				3: sp += Vector3(95.0, 0, along)
			MapKit.kit(root, "grandStandCovered", sp, side * 90.0, true, false)
	MapKit.kit(root, "overheadRoundColored", Vector3(335.0, 0, -325.0), 90, false, false)
	for n in 4:
		MapKit.kit(root, "flagCheckers", Vector3(285.0 + n * 34.0, 0, -240.0), 0, false, false)
	for n in 3:
		MapProps.loose_kit(root, "pylon", Vector3(300.0 + n * 24.0, 0, -420.0), 0, 6.0)
	# тротуары по периметру кварталов: гребень 0.2 м — колесо наезжает на пологую
	# грань с любой стороны, а не отстреливается от стенки; при этом край тротуара
	# всё ещё ощущается краем улицы, а не лентой асфальта в пустоте. Стадион
	# оставляем открытой площадью — его трибуны стоят впритык к линии бордюра
	for cx in [-335.0, -110.0, 110.0, 335.0]:
		for cz in [-335.0, -110.0, 110.0, 335.0]:
			if is_equal_approx(cx, 335.0) and is_equal_approx(cz, -335.0): continue
			MapKit.curb_ridge(root, Vector3(cx, 0, cz - 92.0), Vector3(0, 0, 1), 190.0)
			MapKit.curb_ridge(root, Vector3(cx, 0, cz + 92.0), Vector3(0, 0, 1), 190.0)
			MapKit.curb_ridge(root, Vector3(cx - 92.0, 0, cz), Vector3(1, 0, 0), 184.0)
			MapKit.curb_ridge(root, Vector3(cx + 92.0, 0, cz), Vector3(1, 0, 0), 184.0)
	# перекрёстки: plastic отбойники и конусы — сбить на проходе через квартал;
	# уровень y=0: под линией нет тротуара, а на уровне бордюра предмет падал бы
	# до пола и звенел на старте
	for n in 5:
		MapProps.loose_kit(root, "barrierWhite", Vector3(-220.0 + n * 110.0, 0.0, -180.0), 0, 25.0)
	for n in 4:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(100.0 + n * 4.0, 0, 208.0), MapDefs.PROP, 0.0, 3.0)
	# лесополоса за периметром: город не должен обрываться в пустоту
	for k in 24:
		var a := -470.0 + k * 40.0
		# тень пояса падает на пустой грунт за кольцом — снимаем её: 96 деревьев
		# в проходе теней стоили городу тех самых кадров, из-за которых он падал
		# ниже 50 FPS на встроенной графике
		for pt in [Vector3(a, 0, -520.0), Vector3(a, 0, 520.0),
				Vector3(-520.0, 0, a), Vector3(520.0, 0, a)]:
			var belt := MapKit.kit(root, "treeLarge", pt, 0, true, false)
			MapKit.no_shadow(belt)
			MapKit.far(belt, 420.0)
	# обвеска: тротуары, парки, дворы, промзона и обочины кольца — после районов,
	# чтобы порядок rng остался тем же, что при их расстановке
	_bc_dress(root, rng, parked)
	MapKit.drop_shadows(root)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-430.0, 1.0, 0.0)),
		"bounds": AABB(Vector3(-560.0, -30.0, -560.0), Vector3(1120.0, 70.0, 1120.0)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}

# Свободная точка квартала: кольцо 84..88 м от центра — не встать ни на улицу,
# ни на бордюр тротуара (92 м).
static func _bc_spot(rng: RandomNumberGenerator, cx: float, cz: float, min_r: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := min_r + rng.randf() * (88.0 - min_r)
	return Vector3(cx + cos(a) * r, 0.0, cz + sin(a) * r)

# Плита, начатая в node_x (полоса 20 м вдоль оси), пересекает полосу встречной
# улицы шириной 10 м с осью lane: [lane−5, lane+5] ∩ [node_x, node_x+20] ≠ ∅.
static func _bc_crosses(node_x: float, lane: float) -> bool:
	return node_x < lane + 5.0 and node_x > lane - 25.0

# Попадает ли точка в заплатку перекрёстка: заплатка визуальная, её верх на 2.4 см
# выше физической земли, и предмет, поставленный «на поверхность» в её границах,
# на самом деле стоит на полу и выглядит утонувшим.
static func _bc_on_patch(x: float, z: float) -> bool:
	for ix in [-220.0, 0.0, 220.0]:
		for iz in [-220.0, 0.0, 220.0]:
			if absf(x - ix) < 21.0 and absf(z - iz) < 21.0: return true
	return false

# Ставим ли предмет у этой полосы улицы: нет — на перекрёстке, в проёме встречной
# улицы и под бульварными горками/буграми.
static func _bc_spot_free(along: float, lane: float, boulevard: bool) -> bool:
	for c in [-220.0, 0.0, 220.0]:
		if absf(along - c) < 24.0: return false
	if boulevard:
		for r in [[-150.0, -120.0], [110.0, 140.0], [270.0, 350.0], [-430.0, -400.0]]:
			if along > float(r[0]) and along < float(r[1]): return false
	return true

# Плотная обвеска города. Детерминирована тем же rng, что и районы: порядок вызовов
# зафиксирован, поэтому одна и та же карта собирается одинаково от запуска к запуску.
static func _bc_dress(root: Node3D, rng: RandomNumberGenerator, parked: Array[String]) -> void:
	# тротуарные плиты: полоса 7.6 м по обе стороны каждой улицы, сегментами — под
	# перекрёстками её нет, иначе светлый борт шёл бы поперёк асфальта заплатки.
	# Плита — только видимость, в списке поверхностей её нет (как у газона парка): предметы
	# ставятся ДО обвески и сели по полу, а зарегистрированный сверху слой в 2.8 см
	# заставил бы h_restart_props считать их утонувшими — 218 штук на ровном месте.
	# Тень плите не нужна: она лежит на таком же полу.
	for lane in [-220.0, 0.0, 220.0]:
		for side in [-1.0, 1.0]:
			var c: float = lane + side * 9.4
			for k in 46:
				var along := -460.0 + k * 20.0
				if not _bc_spot_free(along + 10.0, lane as float, false): continue
				var a := MapKit.box_vis(root, Vector3(along + 10.0, 0.014, c),
					Vector3(20, 0.028, 7.6), MapDefs.SIDEWALK_COL)
				a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var b := MapKit.box_vis(root, Vector3(c, 0.014, along + 10.0),
					Vector3(7.6, 0.028, 20), MapDefs.SIDEWALK_COL)
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# тротуары: фонарь, урна, кашпо или молодое дерево каждые ~9 м с обеих сторон
	for lane in [-220.0, 0.0, 220.0]:
		for k in 68:
			var along := -440.0 + k * 13.0
			for side in [-6.6, 6.6]:
				if not _bc_spot_free(along, lane, is_equal_approx(lane, 0.0)): continue
				var px: float = along
				var pz: float = lane + side
				var roll := rng.randi() % 10
				var node: Node = null
				if roll < 2:
					node = MapKit.kit(root, "lightColored" if roll == 0 else "lightRed",
						Vector3(px, 0, pz), 0, true, false)
				elif roll < 4:
					node = MapProps.knock_bin(root, px, pz, 0.0)
				elif roll == 4:
					node = MapProps.knock_planter(root, px, pz, 0.0)
				elif roll == 5:
					node = MapProps.knock_sign(root, px, pz, 0.0)
				elif roll == 6:
					node = MapProps.knock_hydrant(root, px, pz, 0.0)
				elif roll == 7:
					# сбиваемое на тротуаре: конус и пилон летят от бампера, и город
					# начинает реагировать на машину, а не стоять декорацией
					node = MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(px, 0, pz), MapDefs.PROP, 0.0, 3.0)
				elif roll == 8:
					node = MapProps.loose_kit(root, "pylon", Vector3(px, 0, pz), 0, 6.0)
				else:
					node = MapProps.prop(root, MapDefs.A + "tree-small.glb", Vector3(px, 0, pz), 5.5,
						rng.randf() * TAU, true)
					MapKit.no_shadow(node)
				if node != null: MapKit.far(node, 240.0)
	# улицы вдоль Z: та же обвеска, повёрнутая на 90°
	for lane in [-220.0, 0.0, 220.0]:
		for k in 68:
			var along := -440.0 + k * 13.0
			for side in [-6.6, 6.6]:
				if not _bc_spot_free(along, lane, false): continue
				var px: float = lane + side
				var pz: float = along
				var roll := rng.randi() % 10
				var node: Node = null
				if roll < 2:
					node = MapKit.kit(root, "lightRed" if roll == 0 else "lightColored",
						Vector3(px, 0, pz), 90, true, false)
				elif roll < 4:
					node = MapProps.knock_bin(root, px, pz, 90.0)
				elif roll == 4:
					node = MapProps.knock_planter(root, px, pz, 90.0)
				elif roll == 5:
					node = MapProps.knock_sign(root, px, pz, 90.0)
				elif roll == 6:
					node = MapProps.knock_hydrant(root, px, pz, 90.0)
				elif roll == 7:
					node = MapProps.loose(root, MapDefs.P + "debris-plate-a.glb", Vector3(px, 0, pz), MapDefs.PROP,
						rng.randf() * 3.0, 9.0)
				elif roll == 8:
					node = MapProps.loose_kit(root, "pylon", Vector3(px, 0, pz), 90, 6.0)
				else:
					node = MapProps.prop(root, MapDefs.A + "tree-small.glb", Vector3(px, 0, pz), 5.5,
						rng.randf() * TAU, true)
					MapKit.no_shadow(node)
				if node != null: MapKit.far(node, 240.0)
	# парки: скамейки и столы у фонтана, кашпо вдоль газона, рощи по углам
	var parks: Array = MapDefs.BC_PARKS
	for i in parks.size():
		var cx: float = parks[i][0]
		var cz: float = parks[i][1]
		if i == 0: MapProps.fountain(root, cx, cz)
		for k in 6:
			var a := k * TAU / 6.0 + 0.3
			var bx: float = cx + cos(a) * 24.0
			var bz: float = cz + sin(a) * 24.0
			MapProps.knock_bench(root, bx, bz, -rad_to_deg(a) - 90.0)
		for k in 3:
			MapProps.picnic(root, cx - 40.0 + k * 40.0, cz + 52.0, 0.0)
		for k in 14:
			var t := MapProps.prop(root, MapDefs.A + ("tree-large.glb" if k % 3 == 0 else "tree-small.glb"),
				_bc_spot(rng, cx, cz, 40.0), 6.5 + rng.randf() * 3.0, rng.randf() * TAU, true)
			MapKit.far(t, 320.0)
		for k in 8:
			var ps := _bc_spot(rng, cx, cz, 30.0)
			MapKit.far(MapProps.knock_planter(root, ps.x, ps.z, rng.randf() * 360.0), 240.0)
	# деловой центр: площадь под башнями и карманы между ними. Без покрытия квартал
	# выглядел бетонным полем (кадр проверки это показывал), поэтому плита площади,
	# а в девяти карманах решётки — скамейка, кашпо и припаркованная машина.
	for cx in [-110.0, 110.0]:
		for cz in [-110.0, 110.0]:
			var plaza := MapKit.box_vis(root, Vector3(cx, 0.012, cz),
				Vector3(184, 0.024, 184), MapDefs.PLAZA_COL)
			plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for gx in 3:
				for gz in 3:
					var mx: float = cx - 30.0 + gx * 60.0
					var mz: float = cz - 30.0 + gz * 60.0
					if _bc_on_patch(mx, mz) or _bc_on_patch(mx + 4.0, mz): continue
					MapProps.bench(root, mx, mz, 90.0 * ((gx + gz) % 4))
					MapKit.far(MapProps.knock_planter(root, mx + 4.0, mz, 0.0), 240.0)
					if (gx + gz) % 2 == 0:
						MapKit.far(MapProps.prop(root, parked[rng.randi() % parked.size()],
							Vector3(mx - 5.0, 0, mz + 6.0), 1.0,
							PI * 0.5 * ((gx + gz) % 4), true), 260.0)
			for k in 4:
				var a := k * TAU / 4.0 + PI / 4.0
				var bx: float = cx + cos(a) * 78.0
				var bz: float = cz + sin(a) * 78.0
				MapProps.bench(root, bx, bz, -rad_to_deg(a) - 90.0)
				MapProps.planter(root, Vector3(bx + 3.0, 0, bz), 0.0)
			MapKit.kit(root, "flagCheckers", Vector3(cx - 84.0, 0, cz - 84.0), 0, false, false)
			MapKit.kit(root, "billboardLow", Vector3(cx + 84.0, 0, cz - 84.0), 90, true, false)
	# жилые дворы: урны, баки-ящики, конусы, ещё деревья и заборы
	for block in [[-110.0, 335.0], [110.0, 335.0], [110.0, -335.0]]:
		var cx2: float = block[0]
		var cz2: float = block[1]
		for k in 6:
			MapProps.bin(root, cx2 - 70.0 + k * 28.0, cz2 - 74.0)
		for k in 4:
			MapProps.loose(root, MapDefs.P + "box.glb", Vector3(cx2 - 50.0 + k * 34.0, 0, cz2 + 66.0),
				MapDefs.PROP, rng.randf() * 3.0, 14.0)
		for k in 6:
			MapKit.far(MapProps.prop(root, MapDefs.A + "tree-large.glb", _bc_spot(rng, cx2, cz2, 40.0),
				7.0 + rng.randf() * 2.5, rng.randf() * TAU, true), 320.0)
		for k in 5:
			MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(cx2 - 60.0 + k * 30.0, 0, cz2 - 20.0),
				MapDefs.PROP, 0.0, 3.0)
	# промзона: палатки, рельс, двойные мачты, барьеры вдоль фасада
	for cx in [335.0, -335.0]:
		for cz in [335.0, -110.0]:
			MapKit.kit(root, "tentClosedLong", Vector3(cx + 20.0, 0, cz + 70.0), 0, true, false)
			MapKit.kit(root, "rail", Vector3(cx - 20.0, 0, cz + 76.0), 90, true, false)
			MapKit.kit(root, "lightRedDouble", Vector3(cx + 76.0, 0, cz + 20.0), 0, true, false)
			for k in 4:
				MapKit.kit(root, "barrierWall", Vector3(cx - 70.0 + k * 40.0, 0, cz - 78.0), 0,
					true, false)
			for k in 5:
				MapProps.loose(root, MapDefs.P + "debris-tire.glb",
					Vector3(cx + 40.0 + k * 12.0, 0, cz - 60.0), MapDefs.PROP, rng.randf() * 3.0, 10.0)
	# обочины кольца: флаги по углам, деревья и трава снаружи, барьеры внутри
	for k in 12:
		var a := -440.0 + k * 80.0
		for side in [-470.0, 470.0]:
			MapKit.far(MapProps.prop(root, MapDefs.A + "tree-large.glb", Vector3(a, 0, side), 7.5,
				rng.randf() * TAU, true), 300.0)
			MapKit.far(MapProps.prop(root, MapDefs.A + "tree-large.glb", Vector3(side, 0, a), 7.5,
				rng.randf() * TAU, true), 300.0)
	for k in 16:
		var a := -400.0 + k * 55.0
		MapProps.loose_kit(root, "pylon", Vector3(a, 0, -432.0), 0, 6.0)
		MapProps.loose_kit(root, "pylon", Vector3(-432.0, 0, a), 90, 6.0)
	for n in 8:
		MapKit.kit(root, "flagGreen" if n % 2 == 0 else "flagRed",
			Vector3(-455.0 + n * 130.0, 0, -455.0), 0, false, false)
		MapKit.kit(root, "flagTankco", Vector3(455.0, 0, -455.0 + n * 130.0), 90, false, false)
