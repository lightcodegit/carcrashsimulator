extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _make_shell(chassis: Node3D) -> SoftShell:
	var p: VehicleParams = VehicleDB.get_params("sedan")
	var spec: ShellSpec = ShellBuilder.build(p)
	var shell := SoftShell.new()
	shell.setup(spec, chassis, p)
	return shell

func _initialize() -> void:
	var chassis := Node3D.new()
	root.add_child(chassis)
	var sh := _make_shell(chassis)
	check(sh.dyn_count() == 0, "A1 idle dynamic zero")
	for f in 120: sh.sim_step(1.0 / 60.0)
	check(sh.get_broken_total() == 0, "A2 idle nothing breaks")
	check(sh.get_sim_ms_avg() < 8.0, "A3 sim step under 8ms (%.2f)" % sh.get_sim_ms_avg())

	# B) удар в нос на 20 m/s: wake, пластичность, разрыв, монотонность по энергии
	sh.spring_burst.connect(func(_z): pass)
	sh.apply_impact(Vector3(2.35, 0.0, 0), Vector3(-1, 0, 0), 25.0)
	check(sh.dyn_count() > 20, "B1 impact wakes points (%d)" % sh.dyn_count())
	for f in 240: sh.sim_step(1.0 / 60.0)
	var finite := true
	for i in sh.point_count():
		if not sh.point_world(i).is_finite(): finite = false
	check(finite, "B2 no NaN after impact")
	check(sh.broken_by_zone[Zones.FRONT] >= 8, "B3 front springs burst (%d)" % sh.broken_by_zone[Zones.FRONT])
	check(sh.broken_by_zone[Zones.ROOF] * 2 <= sh.broken_by_zone[Zones.FRONT], "B4 damage localized to front")
	var sh2 := _make_shell(chassis)
	sh2.apply_impact(Vector3(2.35, 0.0, 0), Vector3(-1, 0, 0), 45.0)
	for f in 240: sh2.sim_step(1.0 / 60.0)
	check(sh2.wake_count_at_impact > sh.wake_count_at_impact, "B5 stronger impact wakes larger region (%d > %d)" % [sh2.wake_count_at_impact, sh.wake_count_at_impact])
	check(sh2.broken_by_zone[Zones.FRONT] >= 8, "B5b strong impact still shreds front (%d)" % sh2.broken_by_zone[Zones.FRONT])

	# C) reset
	sh.reset()
	check(sh.get_broken_total() == 0 and sh.dyn_count() == 0, "C1 reset clears damage")

	# D) саг без пола: анкеры держат клетку
	var sh3 := _make_shell(chassis)
	sh3.apply_impact(Vector3(0, 0.0, 0), Vector3(0, 1, 0), 5.0)
	for f in 600: sh3.sim_step(1.0 / 60.0)
	var min_y := INF
	for i in sh3.point_count(): min_y = minf(min_y, sh3.point_world(i).y)
	check(min_y > -0.74, "D1 cage hangs above sag limit (min_y=%.2f)" % min_y)

	# E) движущееся шасси: FOLLOW-точки дублируют трансформ (local: вне дерева global недоступен)
	chassis.position = Vector3(10, 2, 0)
	var ep := sh.point_world(0)
	check(ep.distance_to(chassis.transform * sh.spec.points[0]) < 0.001, "E1 FOLLOW tracks chassis (%s vs %s)" % [str(ep), str(chassis.transform * sh.spec.points[0])])

	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
