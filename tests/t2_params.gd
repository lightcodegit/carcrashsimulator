extends SceneTree
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _initialize() -> void:
	var ids := ["sedan", "pickup", "sport", "infinity"]
	var by_id := {}
	for id in ids:
		var p = VehicleDB.get_params(id)
		check(p != null, "%s exists" % id)
		if p == null: continue
		by_id[id] = p
		check(p.mass > 500 and p.vmax_kmh > 100, "%s sane stats" % id)
		check(p.model != "" and ResourceLoader.exists(p.model), "%s model asset exists (%s)" % [id, p.model])
		# габариты производные от модели: должны быть правдоподобными метрами
		check(p.length > 2.0 and p.length < 6.0, "%s derived length (%.2f м)" % [id, p.length])
		check(p.width > 1.2 and p.width < 2.6, "%s width (%.2f м)" % [id, p.width])
		check(p.height > 0.6 and p.height < 2.4, "%s derived height (%.2f м)" % [id, p.height])
		check(p.wheel_r > 0.2 and p.wheel_r < 0.8, "%s wheel radius (%.2f м)" % [id, p.wheel_r])
		check(p.length > p.width and p.length > p.height, "%s length is the long axis" % id)
		var cs: Vector3 = p.collider_size()
		check(cs.x > 0 and cs.y > 0 and cs.z > 0, "%s collider positive" % id)
		check(cs.y < p.height and cs.x < p.length and cs.z < p.width, "%s collider inside body (%s)" % [id, str(cs)])
		# «тормоз сильнее мотора» имело смысл, пока моторы были в покрышечном
		# диапазоне. Машине без потолка скорости оно было бы неправдой: тормоз упирается
		# в предел сцепления, и требовать от него 4.5 г бессмысленно.
		var grip_limit := CarRig.BRAKE_MAX_G * CarRig.GRAVITY
		check(p.brake_decel >= minf(p.accel_max, grip_limit),
			"%s тормозит не слабее, чем позволяют шины (%.1f против %.1f)" % [id, p.brake_decel, minf(p.accel_max, grip_limit)])
		check(p.steer_rate_deg > 10.0 and p.grip > 1.0, "%s handling sane" % id)
	check(VehicleDB.get_params("unknown") == null, "unknown id returns null")
	check(by_id["sport"].vmax_kmh > by_id["sedan"].vmax_kmh, "sport is the fastest of ordinary cars")
	# «Машина бесконечности» — единственная без паспортного потолка: кривая тяги
	# car_rig.gd строится как 1 - (v/vmax)^1.6, и при INF она не падает никогда.
	check(not is_finite(by_id["infinity"].vmax_kmh), "infinity has no speed ceiling")
	check(by_id["infinity"].accel_max > by_id["sport"].accel_max, "infinity accelerates hardest")
	check(is_finite(by_id["infinity"].brake_decel), "infinity still stops like a car")
	check(by_id["sport"].accel_max > by_id["sedan"].accel_max, "sport accelerates harder")
	check(by_id["pickup"].mass > by_id["sedan"].mass, "pickup is the heaviest")
	check(by_id["pickup"].width > by_id["sedan"].width, "pickup is the widest")
	check(by_id["sport"].height < by_id["sedan"].height, "sport is the lowest")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
