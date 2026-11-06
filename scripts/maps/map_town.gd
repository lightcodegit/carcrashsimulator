class_name MapTown
extends RefCounted
# Городок: две улицы, кварталы домов, тротуары и сбиваемый хлам.

static func build() -> Dictionary:
	var root := Node3D.new(); root.name = "Town"
	MapKit.box(root, Vector3(0, MapDefs.FLOOR_Y - 1.0, 0), Vector3(300, 2, 300), Color(0.42, 0.42, 0.45), Basis.IDENTITY, true)
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	# улицы из плит Racing Kit: главная вдоль z = -24 и вторая вдоль z = 36
	for k in 14:
		# первую плиту заняла стартовая арка: её разметка легла бы ровно на разметку плиты
		if k > 0: MapKit.kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, -19), 90, false, true)
		MapKit.kit(root, "roadStraightLong", Vector3(-140.0 + k * 20.0, 0, 41), 90, false, true)
	MapKit.kit(root, "roadStart", Vector3(-140, 0, -17.7), 90, true, true)   # арка на въезде в город
	for k in 24:
		MapKit.box_vis(root, Vector3(-140 + k * 12.0, 0.03, -24), Vector3(6.0, 0.02, 0.3), Color(0.85, 0.82, 0.4))
		MapKit.box_vis(root, Vector3(-140 + k * 12.0, 0.03, 36), Vector3(6.0, 0.02, 0.3), Color(0.85, 0.82, 0.4))
	# тротуары
	for z in [-32.5, -15.5, 29.0, 43.0]:
		MapKit.box(root, Vector3(0, 0.1, z), Vector3(300, 0.2, 3.0), Color(0.5, 0.5, 0.52))
	# кварталы: здания из ассетов, равномерный масштаб, разная высота
	var types: Array[String] = ["building-type-a", "building-type-b", "building-type-c",
		"building-type-d", "building-type-e", "building-type-f"]
	var bz := [-78.0, -52.0, 8.0, 62.0, 92.0]
	var bx := [-108.0, -76.0, -44.0, 24.0, 56.0, 88.0, 116.0]
	for x in bx:
		for z in bz:
			if absf(x) < 14.0: continue                       # перекрёсток
			var t: String = types[rng.randi() % types.size()]
			var s := 9.0 + rng.randf() * 7.0
			var rot := float(rng.randi() % 4) * PI * 0.5
			MapProps.prop(root, MapDefs.A + t + ".glb", Vector3(x + rng.randf_range(-3.0, 3.0), 0.0, z + rng.randf_range(-3.0, 3.0)), s, rot, true)
	# деревья, клумбы и заборы вдоль улиц
	for k in 22:
		var x := -140.0 + k * 13.5
		MapProps.prop(root, MapDefs.A + ("tree-large.glb" if k % 2 == 0 else "tree-small.glb"), Vector3(x, 0.0, -13.0), 7.5, 0.0, true)
		MapProps.prop(root, MapDefs.A + "tree-large.glb", Vector3(x + 6.0, 0.0, 45.5), 7.0, 0.0, true)
	for k in 8:
		MapProps.prop(root, MapDefs.A + "planter.glb", Vector3(-100.0 + k * 28.0, 0.0, -18.5), 3.2, 0.0, true)
	for k in 10:
		MapProps.prop(root, MapDefs.A + "fence-1x4.glb", Vector3(-120.0 + k * 26.0, 0.0, 52.0), 4.0, 0.0, true)
	# фонари из набора трассы и припаркованные машины
	for k in 9:
		MapKit.kit(root, "lightColored", Vector3(-120.0 + k * 30.0, 0, -33.5), 0, true)
		MapKit.kit(root, "lightColored", Vector3(-105.0 + k * 30.0, 0, 30.0), 180, true)
	for k in 5:
		MapKit.kit(root, "billboard", Vector3(-100.0 + k * 50.0, 0, -36.0), 0, true)
		MapKit.kit(root, "fenceStraight", Vector3(-110.0 + k * 40.0, 0, 27.0), 0, true)
	# пластиковые отбойники и пилоны сбиваются: первые тяжёлые и тормозят машину, вторые нет
	for k in 6:
		MapProps.loose_kit(root, "barrierWhite", Vector3(-90.0 + k * 30.0, MapDefs.WALK_Y, -15.5), 0, 25.0)
		MapProps.loose_kit(root, "pylon", Vector3(-80.0 + k * 30.0, 0, 20.0), 0, 6.0)
	# хлам на улицах: конусы у перекрёстка, покрышки и ящики во дворе, мусор на тротуаре
	for k in 5:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(-8.0 + k * 4.0, 0, -22.0 + 1.2 * float(k % 3)), MapDefs.PROP, 0.0, 3.0)
	for k in 3:
		MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(40.0 + k * 2.0, MapDefs.WALK_Y, 29.0), MapDefs.PROP, 0.0, 10.0)
	MapProps.loose(root, MapDefs.P + "box.glb", Vector3(-40.0, MapDefs.WALK_Y, -32.5), MapDefs.PROP, 0.8, 15.0)
	MapProps.loose(root, MapDefs.P + "box.glb", Vector3(96.0, 0, 43.0), MapDefs.PROP, 2.2, 15.0)
	MapProps.loose(root, MapDefs.P + "debris-plate-a.glb", Vector3(20.0, 0, 34.0), MapDefs.PROP, 0.4, 12.0)
	MapProps.loose(root, MapDefs.P + "debris-bumper.glb", Vector3(-60.0, MapDefs.WALK_Y, -15.5), MapDefs.PROP, 1.7, 9.0)
	var parked: Array[String] = [MapDefs.CARS + "sedan.glb", MapDefs.CARS + "truck.glb", MapDefs.CARS + "race.glb"]
	for k in 6:
		MapProps.prop(root, parked[k % parked.size()], Vector3(-90.0 + k * 26.0, 0.0, -20.0), 1.0, PI * 0.5, true)
	Materials.apply_tree(root, "prop")
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-120, 1.0, -24)),
		"bounds": AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320)),
		"info": {"colliders": root.get_child_count(), "has_ramp": false}}
