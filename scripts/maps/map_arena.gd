class_name MapArena
extends RefCounted
# Арена: замкнутый полигон с испытательной петлёй, боксами и краш-блоком.

static func build() -> Dictionary:
	var root := Node3D.new(); root.name = "Arena"
	MapKit.box(root, Vector3(0, MapDefs.FLOOR_Y - 1.0, 0), Vector3(200, 2, 200), Color(0.55, 0.55, 0.57), Basis.IDENTITY, true)
	var wc := Color(0.35, 0.35, 0.38)
	MapKit.box(root, Vector3(0, 4, -100), Vector3(200, 8, 1), wc)
	MapKit.box(root, Vector3(0, 4, 100), Vector3(200, 8, 1), wc)
	MapKit.box(root, Vector3(-100, 4, 0), Vector3(1, 8, 200), wc)
	MapKit.box(root, Vector3(100, 4, 0), Vector3(1, 8, 200), wc)
	# испытательная петля: outbound по z = 0, разворот, return по z = -20
	for k in 5:
		MapKit.kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, 5), 90, false, true)
	MapKit.kit(root, "roadHalfCircle", Vector3(60, 0, 5), 90, false, true)
	for k in 5:
		if k != 1:   # плиту x=-20..0 занял лежачий полицейский
			MapKit.kit(root, "roadStraightLong", Vector3(-40.0 + k * 20.0, 0, -15), 90, false, true)
	# Трамплина на арене больше нет: он стоит в 70 м от стены, а с 2.6-метровой горки
	# машина летит дальше (замеры: 140 км/ч — 70 м полёта, 210 км/ч — 190 м). Прыжок
	# кончался ударом о стену или вылетом за карту, и игрок видел это как «удар на рампе».
	# Лежачий полицейский остаётся: с него приземление внутри полигона на любой скорости
	# (замер: 210 км/ч — 2.4 м подъёма, 70 тиков полёта, ноль ударов).
	MapKit.kit(root, "roadBump", Vector3(-20, 0, -15), 90, true, true, Vector3(1, MapDefs.BUMP_Y, 1))
	for k in 8:
		MapKit.kit(root, "grass", Vector3(-40.0 + k * 10.0, 0.02, 16), 90, false)
		MapKit.kit(root, "grass", Vector3(-40.0 + k * 10.0, 0.02, -26), 90, false)
	# отбойники по внешнему и внутреннему краю петли
	for k in 10:
		MapKit.kit(root, "barrierWhite", Vector3(-40.0 + k * 10.0, 0, 4.9), 0, true)
		MapKit.kit(root, "barrierWhite", Vector3(-40.0 + k * 10.0, 0, -26.1), 0, true)
	for k in 4:
		MapKit.kit(root, "barrierRed", Vector3(44.0 + k * 2.5, 0, 4.9), 0, true)
	# боксы, трибуны и обвес полигона
	MapKit.kit(root, "pitsGarage", Vector3(-60, 0, 9.5), 0, true)
	MapKit.kit(root, "pitsOffice", Vector3(-60, 0, 21.0), 0, true)
	MapKit.kit(root, "tent", Vector3(-72, 0, 10), 0, true)
	for k in 2:
		MapKit.kit(root, "grandStand", Vector3(-20.0 + k * 11.0, 0, -34.0), 0, true)
	MapKit.kit(root, "overheadLights", Vector3(-6, 0, 6.3), 90, true)
	for k in 3:
		MapKit.kit(root, "lightRed", Vector3(-30.0 + k * 30.0, 0, 8.5), 0, true)
		MapKit.kit(root, "flagCheckers", Vector3(-24.0 + k * 30.0, 0, 6.6), 0, false)
	MapKit.kit(root, "billboard", Vector3(70, 0, -34.0), 0, true)
	MapKit.kit(root, "radarEquipment", Vector3(78, 0, 12.0), 0, true)
	# слалом из пилонов и краш-блок в конце прямой; пилоны сбиваются
	for k in 5:
		MapProps.loose_kit(root, "pylon", Vector3(-14.0 + k * 6.0, 0, 2.6 * (1 if k % 2 == 0 else -1)), 0, 6.0)
	# краш-блок — в конце обратной прямой: на исходящей он стоял ровно под коридором
	# взлёта, и прыжок через горку кончался ударом о него
	MapKit.box(root, Vector3(82, 1, -20), Vector3(3, 2, 3), Color(0.6, 0.2, 0.2))
	# сносимый хлам: конусы у краш-блока, покрышки и ящик у боксов, обломки на обратной прямой.
	# Конусы стояли на исходящей прямой между горкой и стеной — то есть ровно в коридоре
	# приземления; убраны к блоку, который переехал на обратную прямую.
	for k in 4:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(79.0 + k * 3.0, 0, -23.0 + 1.5 * float(k)), MapDefs.PROP, 0.0, 3.0)
	for k in 3:
		MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(-70.0 + k * 2.0, 0, 6.5), MapDefs.PROP, 0.0, 10.0)
	MapProps.loose(root, MapDefs.P + "box.glb", Vector3(-50.0, 0, 7.5), MapDefs.PROP, 0.6, 15.0)
	MapProps.loose(root, MapDefs.P + "debris-bumper.glb", Vector3(10.0, 0, -18.0), MapDefs.PROP, 0.3, 9.0)
	MapProps.loose(root, MapDefs.P + "debris-plate-a.glb", Vector3(34.0, 0, -18.5), MapDefs.PROP, 1.1, 12.0)
	for k in 4:
		MapKit.kit(root, "treeLarge", Vector3(-80.0 + k * 50.0, 0, 40.0), 0, true)
		MapKit.kit(root, "treeSmall", Vector3(-60.0 + k * 50.0, 0, -50.0), 0, true)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)),
		"bounds": AABB(Vector3(-110, -30, -110), Vector3(220, 70, 220)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}
