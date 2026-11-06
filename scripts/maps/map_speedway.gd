class_name MapSpeedway
extends RefCounted
# Трасса: прямая с трамплином, пит-лейн, трибуны и финишная стена.

static func build() -> Dictionary:
	var root := Node3D.new(); root.name = "Speedway"
	MapKit.box(root, Vector3(280, MapDefs.FLOOR_Y - 1.0, 0), Vector3(700, 2, 300), Color(0.32, 0.32, 0.34), Basis.IDENTITY, true)
	# полотно из плит Kenney Racing Kit (10 x 20), дорога вдоль +X, центр по z = 0
	MapKit.kit(root, "roadStart", Vector3(-20, 0, 6.3), 90, true, true)          # стартовая арка
	for k in 31:
		# k=1 и k=2 заняли трамплин (x=20..50) с его посадочной плитой, k=12 — полицейский
		if k != 1 and k != 2 and k != 12:
			MapKit.kit(root, "roadStraightLong", Vector3(k * 20.0, 0, 5), 90, false, true)
	# обочины-газон у старта и пит-лейна
	for k in 14:
		MapKit.kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, 16), 90, false)
		MapKit.kit(root, "grass", Vector3(-20.0 + k * 10.0, 0.02, -6), 90, false)
	# отбойники вдоль всей трассы по обе стороны
	for k in 64:
		MapKit.kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, 4.9), 0, true)
		MapKit.kit(root, "barrierWall", Vector3(-20.0 + k * 10.0, 0, -6.13), 0, true)
	MapKit.ramp(root, 20.0, 5.0, 3.0)   # трамплин: 2.6 м высоты на 30 м длины
	# пит-лейн, трибуны и обвес трассы
	for k in 4:
		MapKit.kit(root, "pitsGarage", Vector3(60.0 + k * 11.0, 0, 9.5), 0, true)
	MapKit.kit(root, "pitsOffice", Vector3(106, 0, 9.5), 0, true)
	for k in 3:
		MapKit.kit(root, "grandStand", Vector3(150.0 + k * 11.0, 0, -16.5), 180, true)
	MapKit.kit(root, "tent", Vector3(120, 0, 14), 0, true)
	MapKit.kit(root, "tentLong", Vector3(190, 0, 14), 0, true)
	for k in 5:
		MapKit.kit(root, "billboard", Vector3(240.0 + k * 60.0, 0, -13.0), 0, true)
		MapKit.kit(root, "lightRed", Vector3(260.0 + k * 60.0, 0, 8.0), 0, true)
	for k in 4:
		MapKit.kit(root, "flagCheckers", Vector3(2.0, 0, 6.6 + k * 2.2), 0, false)
		MapKit.kit(root, "fenceStraight", Vector3(300.0 + k * 10.0, 0, 9.0), 0, true)
	MapKit.kit(root, "overheadLights", Vector3(-6, 0, 6.3), 90, true)
	MapKit.kit(root, "radarEquipment", Vector3(420, 0, 10.5), 0, true)
	MapKit.kit(root, "roadBump", Vector3(240, 0, 5), 90, true, true, Vector3(1, MapDefs.BUMP_Y, 1))   # вместо плиты k=12
	for k in 10:
		MapKit.kit(root, "treeLarge", Vector3(-10.0 + k * 65.0, 0, -20.0), 0, true)
		# пилоны стоят прямо на полотне — их и предполагается сбивать. Под трамплин и
		# его посадочную плиту не ставим: полотно там наклонено, а предмету известно
		# только плоское, так что пилон тонул в горке и выпрыгивал на старте заезда
		var px := 8.0 + k * 22.0
		if px > 18.0 and px < 60.0: continue
		MapProps.loose_kit(root, "pylon", Vector3(px, 0, 3.2 * (1 if k % 2 == 0 else -1)), 0, 6.0)
	# конусы вдоль пит-лейна и стопки покрышек у боксов
	for k in 6:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(70.0 + k * 5.0, 0, 7.6), MapDefs.PROP, 0.0, 3.0)
	for k in 4:
		MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(118.0 + k * 1.8, 0, 12.0), MapDefs.PROP, 0.0, 10.0)
	MapProps.loose(root, MapDefs.P + "box.glb", Vector3(140.0, 0, 12.5), MapDefs.PROP, 1.3, 15.0)
	MapProps.loose(root, MapDefs.P + "debris-bumper.glb", Vector3(300.0, 0, -3.0), MapDefs.PROP, 0.7, 9.0)
	# финиш: бетонная стена краш-теста
	MapKit.box(root, Vector3(585, 3, 0), Vector3(1.5, 6, 30), Color(0.55, 0.2, 0.2))
	# красные отбойники перед финишной стеной сбиваются, сама стена — нет
	for k in 5:
		MapProps.loose_kit(root, "barrierRed", Vector3(578.0, 0, -2.4 + k * 1.2), 0, 25.0)   # внутри полотна: по краю опора была разная
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-10, 1.0, 0)),
		"bounds": AABB(Vector3(-120, -30, -160), Vector3(780, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true}}
