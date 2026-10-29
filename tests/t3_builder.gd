extends SceneTree
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)
func _initialize() -> void:
	var SB := preload("res://scripts/core/shell_builder.gd")
	for id in ["sedan", "pickup", "sport"]:
		var p: VehicleParams = VehicleDB.get_params(id)
		var spec: ShellSpec = SB.build(p)
		var n_pts: int = p.sections * p.ring_points + 2
		check(spec.points.size() == n_pts, "%s point count %d == %d" % [id, spec.points.size(), n_pts])
		check(spec.points.size() >= 288 and spec.points.size() <= 420, "%s in budget" % id)
		check(spec.springs.size() > 1200, "%s spring count %d" % [id, spec.springs.size()])
		var ok_idx := true; var ok_rest := true; var n_anchor := 0
		for s in spec.springs:
			if s.type == 3:
				if s.anchor < 0 or s.anchor >= spec.chassis_nodes.size(): ok_idx = false
				var d_a: float = spec.points[s.a].distance_to(spec.chassis_nodes[s.anchor])
				if s.rest <= 0.001 or absf(s.rest - d_a) > 0.001: ok_rest = false
				n_anchor += 1
			else:
				if s.a < 0 or s.b < 0 or s.a >= n_pts or s.b >= n_pts: ok_idx = false
				if s.rest <= 0.001 or absf(s.rest - spec.points[s.a].distance_to(spec.points[s.b])) > 0.001: ok_rest = false
		check(ok_idx, "%s spring indices valid" % id)
		check(ok_rest, "%s rest lengths match geometry" % id)
		check(n_anchor >= n_pts * 0.2 and n_anchor <= n_pts, "%s anchor coverage %d" % [id, n_anchor])
		check(spec.triangles.size() % 3 == 0 and spec.triangles.size() > n_pts * 3, "%s triangulated %d" % [id, spec.triangles.size()])
		var finite := true
		for pt in spec.points:
			if not pt.is_finite(): finite = false
		check(finite, "%s points finite" % id)
		for z in range(5): check(spec.zone_spring_totals[z] > 0, "%s zone %d has springs (%d)" % [id, z, spec.zone_spring_totals[z]])
		check(spec.chassis_nodes.size() == 10, "%s chassis nodes" % id)
		check(spec.zones[0] == 0, "%s tail point is REAR zone" % id)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
