extends Node3D
# Cost of a dent and of scrubbing. We measure not milliseconds (they jitter) but the
# number of mesh rebuilds: that is what the code actually controls. The old player
# rebuilt the body from scratch on every step forward, so a step's price grew linearly
# with the impact count: 64 dents = 284 ms for a single hop.
var fails := 0
var car: CarRig

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func _ready() -> void:
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D.IDENTITY)
	var body: DentBody = car.body
	var lp := Vector3(0.4, 0.2, 0.9)
	var ld := Vector3(-1, 0, 0)

	# 1) one impact = one rebuild
	body.reset()
	body.rebuild_count = 0
	for i in 8:
		body.apply_impact_local(lp + Vector3(0.0, 0.0, float(i) * 0.07), ld, 120.0)
	check(body.rebuild_count == 8,
		"eight impacts rebuilt the mesh eight times (actual %d)" % body.rebuild_count)

	# 2) normals are recomputed over dirty groups, not over all vertices
	body.reset()
	body.rebuild_count = 0
	body.normal_passes = 0
	body.apply_impact_local(lp, ld, 120.0)
	check(body.normal_passes > 0 and body.normal_passes < body._verts.size() / 2,
		"an impact recomputed normals of some vertices, not the whole body (%d of %d)" % [
			body.normal_passes, body._verts.size()])

	# 3) player: one step forward costs one rebuild, not the sum of all previous ones
	var rec := ReplayRecorder.new()
	add_child(rec)
	rec.attach(car, null)
	var pl := ReplayPlayer.new()
	add_child(pl)
	pl.setup(rec, car, null)
	rec.player = pl
	for i in 24:
		rec.sim_t += 0.05
		rec.dents.append({"t": rec.sim_t, "lp": lp + Vector3(0.0, 0.0, float(i) * 0.02),
			"ld": ld, "kmh": 120.0})
		body.apply_impact_local(lp + Vector3(0.0, 0.0, float(i) * 0.02), ld, 120.0)
	rec.frames.append({"t": 0.0, "p": PackedFloat32Array([0, 0.5, 0]),
		"b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]), "kmh": 0.0, "slip": 0.0,
		"nitro": 1.0, "hot": 0.0, "w": _four_wheels(),
		"pr": PackedFloat32Array()})
	rec.frames.append({"t": 1.0, "p": PackedFloat32Array([10, 0.5, 0]),
		"b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]), "kmh": 60.0, "slip": 0.0,
		"nitro": 1.0, "hot": 0.0, "w": _four_wheels(),
		"pr": PackedFloat32Array()})
	body.reset()
	check(pl.begin_at(0.0), "the player opened the window")
	pl.playing = false
	body.rebuild_count = 0
	for i in 6:
		pl.scrub(4)          # six steps of 4 frames = the cursor crosses ~6 events
	var forward := body.rebuild_count
	# six steps of 4 frames cross ~24 events: the price = the number of events
	# crossed, not the sum of previous ones (the old code paid 4+8+12+16+20+24 = 64)
	check(forward <= 30,
		"six forward steps rebuilt the mesh %d times instead of the 1+2+..+N sum" % forward)

	# 4) scrubbing back must restore exactly the same number of dents
	var want := body.dent_count
	pl.seek(0.0)
	check(body.dent_count == 0, "scrubbing to the window start cleared the dents (%d)" % body.dent_count)
	pl.seek(1.0)
	check(body.dent_count == want, "the backward scrub restored the dents (%d vs %d)" % [
		body.dent_count, want])

	# 5) the incremental normal pass must match the full one
	body.reset()
	for i in 12:
		body.apply_impact_local(lp + Vector3(0.35, 0.2, -1.0 + float(i) * 0.12), ld, 150.0)
	body._rebuild()
	var full: PackedVector3Array = body._nrm.duplicate()
	body.reset()
	for i in 12:
		body.apply_impact_local(lp + Vector3(0.35, 0.2, -1.0 + float(i) * 0.12), ld, 150.0)
	var worst := 0.0
	for i in body._verts.size():
		worst = maxf(worst, full[i].distance_to(body._nrm[i]))
	check(worst < 1e-4,
		"incremental normals match the full ones: worst diff %.6f" % worst)

	# 6) the ring holds a long session: the event limit must not clip old dents
	var big := ReplayRecorder.new()
	add_child(big)
	big.attach(car, null)
	# the player's path, not an array append: the limit lives in the impact receiver
	for i in ReplayRecorder.MAX_DENTS + 10:
		big.sim_t = float(i)
		big._on_impact(120.0, car.chassis.global_position + Vector3(0.5, 0.2, 0.0), Vector3.BACK)
	check(big.dents.size() == ReplayRecorder.MAX_DENTS,
		"the impact ring is capped at %d (actual %d)" % [ReplayRecorder.MAX_DENTS, big.dents.size()])
	check(ReplayRecorder.MAX_DENTS >= 200,
		"the limit covers a long session without losing old dents (%d)" % ReplayRecorder.MAX_DENTS)
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _four_wheels() -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(16)
	return w
