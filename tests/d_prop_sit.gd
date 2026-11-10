extends SceneTree
# Two prop-placement contracts, on REAL coordinates.
# IMPORTANT: in _initialize global transforms are not computed yet, and for a map
# built but not inserted into the tree global_position returns (0,0,0). The first
# version of this check tripped on exactly that: 703 bodies "stood" at the origin,
# and the test silently checked surface_y(0, 0). Use local position — the map root
# has an identity transform.
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
			# fountain-ring benches sit exactly at radius 24 and must face the
			# fountain, not along it: local +Z after rotation.y = (sin, cos)
			for park in MapDefs.BC_PARKS:
				var dx := p.x - float(park[0])
				var dz := p.z - float(park[1])
				var d := sqrt(dx * dx + dz * dz)
				if absf(d - 24.0) > 0.02: continue
				rings += 1
				var th := body.rotation.y
				if (sin(th) * -dx + cos(th) * -dz) / maxf(d, 1e-6) < 0.9: wrong += 1
		print("%-9s bodies %d, sunk %d, worst %.3f m; ring benches %d, not facing fountain %d" % [
			id, total, sunk, worst, rings, wrong])
		# an empty walk looks like "all clean": a map must have bodies
		if total < 5:
			print("FAIL: %s: %d dynamic bodies, nothing to check" % [id, total])
			fails += 1
		if sunk > 0 or wrong > 0: fails += 1
		# bench rings exist only in Big City: 4 parks × 6 benches
		if id == "bigcity" and rings < 24:
			print("FAIL: ring benches %d, expected at least 24" % rings)
			fails += 1
		root.free()
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
