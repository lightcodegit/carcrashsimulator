extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	for id in ["sedan", "pickup", "sport"]:
		var p = VehicleDB.get_params(id)
		check(p != null, "%s exists" % id)
		check(p.mass > 500 and p.vmax_kmh > 100, "%s sane stats" % id)
		check(absf(p.body_h + p.roof_h + p.gc - p.height) < 0.01, "%s height consistent" % id)
		check(p.cab_x1 > p.cab_x0, "%s cabin ordered" % id)
		check(p.sections >= 16 and p.ring_points == 16, "%s cage resolution" % id)
		check(p.break_strain > 0.1 and p.break_strain < 0.5, "%s strain range" % id)
	check(VehicleDB.get_params("sedan").break_strain < VehicleDB.get_params("pickup").break_strain, "sedan crumples easier than pickup")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
