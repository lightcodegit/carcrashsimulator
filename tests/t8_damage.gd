extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	var dm := DamageModel.new()
	var p: VehicleParams = VehicleDB.get_params("sedan")
	var spec: ShellSpec = ShellBuilder.build(p)
	dm.bind_spec(spec)
	check(dm.hp(Zones.FRONT) == 100.0, "F0 full hp")
	dm.report_breaks(Zones.FRONT, int(spec.zone_spring_totals[Zones.FRONT] * 0.35))
	check(dm.hp(Zones.FRONT) < 1.0, "F1 capacity maps to 0")
	dm.reset()
	check(dm.hp(Zones.FRONT) == 100.0, "F1b reset")
	dm.report_breaks(Zones.FRONT, int(spec.zone_spring_totals[Zones.FRONT] * 0.1))
	check(dm.hp(Zones.FRONT) > 65.0 and dm.hp(Zones.FRONT) < 80.0, "F2 10%% break ≈ 71 hp (%.1f)" % dm.hp(Zones.FRONT))
	dm.report_breaks(Zones.ROOF, int(spec.zone_spring_totals[Zones.ROOF] * 0.4))
	check(dm.worst_zone() == Zones.ROOF, "F3 worst zone")
	check(dm.is_totaled(), "F4 totaled when any zone hits zero")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
