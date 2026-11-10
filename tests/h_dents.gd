extends Node3D
# Dents without springs: locality, monotonicity in speed, accumulation,
# geometry finiteness, exact reset, frame budget.
var _fails := 0
var car: CarRig
var _frame := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 2, 120)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	await get_tree().physics_frame

func _nose() -> Vector3:
	return _nose_of(car)

func _nose_of(c: CarRig) -> Vector3:
	return c.chassis.global_position + Vector3(c.params.length * 0.5 - 0.05, 0.0, 0.0)

func _physics_process(_dt: float) -> void:
	# The car is built in _ready via await: on a live renderer that lands four frames
	# later than in headless. Count from the car's appearance, not from scene start.
	if car == null: return
	_frame += 1
	if _frame != 4: return
	var b := car.body
	check(b.vertex_count() > 3000, "the body is subdivided (%d vertices)" % b.vertex_count())
	check(b.triangle_count() > 3000, "the body is subdivided (%d triangles)" % b.triangle_count())
	check(b.wheels.size() == 4 and b.front_wheels.size() == 2, "wheels found (%d/%d)" % [b.wheels.size(), b.front_wheels.size()])
	check(car.params.length > 2.5 and car.params.length < 4.0, "dimensions come from the model (%.2f m)" % car.params.length)

	# A) geometry untouched before impact
	check(b.dent_count == 0 and b.deformation() < 1e-6, "A1 idle body pristine")

	# B) nose impact: the dent exists, is finite, is local
	var p := _nose()
	var t0 := Time.get_ticks_usec()
	b.apply_impact(p, Vector3(1, 0, 0), 60.0)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(b.dent_count == 1, "B1 dent registered (%d)" % b.dent_count)
	var def60 := b.deformation()
	check(def60 > 0.05, "B2 geometry deformed (%.3f m)" % def60)
	check(ms < 25.0, "B3 dent budget (%.2f ms)" % ms)
	var finite := true
	var under := 0
	for i in b.vertex_count():
		var w := b.vertex_world(i)
		if not w.is_finite(): finite = false
		if w.y < -0.05: under += 1
	check(finite, "B4 all vertices finite")
	check(under == 0, "B5 nothing pushed under the floor (%d)" % under)
	check(b.max_depth > 0.01 and b.max_depth < 0.6, "B6 depth plausible (%.3f m)" % b.max_depth)
	# locality: beyond the impact radius vertices do not move at all
	var moved_far := 0
	var moved_near := 0
	for i in b.vertex_count():
		var shift := b.vertex_world(i).distance_to(b.vertex_pristine_world(i))
		if shift < 1e-5: continue
		if b.vertex_pristine_world(i).distance_to(p) > 1.6: moved_far += 1
		else: moved_near += 1
	check(moved_far == 0, "B7 the dent is local (%d vertices moved beyond 1.6 m)" % moved_far)
	check(moved_near > 20, "B8 the impact zone moved (%d vertices)" % moved_near)
	check(b.moved_vertex_count(0.01) > 20, "B9 moved-vertex counter (%d)" % b.moved_vertex_count(0.01))

	# C) monotonicity in speed: the second car stands apart (otherwise the solver
	# ejects it from the first collider and the impact lands off the body)
	var car2 := CarRig.new()
	add_child(car2)
	car2.build(VehicleDB.get_params("sedan"), get_world_3d())
	car2.respawn(Transform3D(Basis.IDENTITY, Vector3(24.0, 1.0, 0)))
	await get_tree().physics_frame
	car2.body.apply_impact(_nose_of(car2), Vector3(1, 0, 0), 150.0)
	check(car2.body.max_depth > b.max_depth, "C1 faster hit dents deeper (%.3f > %.3f)" % [car2.body.max_depth, b.max_depth])
	check(car2.body.deformation() > def60, "C2 faster hit deforms more (%.3f > %.3f)" % [car2.body.deformation(), def60])
	car2.queue_free()

	# D) repeated impacts accumulate
	var before := b.deformation()
	b.apply_impact(p + Vector3(-0.3, 0.1, 0.2), Vector3(1, 0, 0), 60.0)
	check(b.dent_count == 2, "D1 second dent counted (%d)" % b.dent_count)
	check(b.deformation() > before, "D2 deformation accumulates (%.3f > %.3f)" % [b.deformation(), before])

	# D3–D5) a series into ONE spot: the cap by body height must hold for the
	# accumulated displacement, and the «КУЗОВ» gauge must show the total dent, not the
	# nominal of a single impact (before the fix max_depth came from the last impact's depth)
	var single := b.max_depth
	var spot := p + Vector3(-0.05, 0.0, 0.0)
	for k in 6:
		b.apply_impact(spot, Vector3(1, 0, 0), 60.0)
	var cap := DentBody.MAX_DEPTH_RATIO * b.height
	var nominal := minf(cap, (60.0 / 3.6) * 0.010)   # depth of a single 60 km/h impact
	check(b.max_vertex_shift() <= cap + 1e-3,
		"D3 the accumulated dent stays under the cap (%.3f vs %.3f)" % [b.max_vertex_shift(), cap])
	check(b.max_depth >= single,
		"D4 the gauge sees accumulation, not one impact (%.3f ≥ %.3f)" % [b.max_depth, single])
	# the influence radius is measured from the surface point, so a series into one spot
	# converges below the cap; what matters is that it is deeper than one impact and that the gauge sees it
	check(b.max_vertex_shift() > nominal + 0.02,
		"D5 the impact series is deeper than a single hit (%.3f vs %.3f)" % [b.max_vertex_shift(), nominal])
	check(b.max_depth > nominal + 0.02,
		"D6 the «КУЗОВ» reading grew along with the geometry (%.3f vs %.3f)" % [b.max_depth, nominal])

	# E) reset restores the original geometry
	b.reset()
	check(b.dent_count == 0, "E1 dent count cleared")
	check(b.deformation() < 1e-6, "E2 geometry restored (%.6f)" % b.deformation())
	check(b.max_vertex_shift() < 1e-6, "E3 no vertex left displaced")

	# F) a weak impact does not punch through the body or push vertices out of bounds
	b.apply_impact(_nose(), Vector3(1, 0, 0), 200.0)
	check(b.max_vertex_shift() < car.params.length * 0.5, "F1 shift bounded (%.2f m)" % b.max_vertex_shift())
	print("DENT verts=%d tris=%d impact=%.2f ms depth=%.3f m moved=%d" % [
		b.vertex_count(), b.triangle_count(), ms, b.max_depth, b.moved_vertex_count(0.01)])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
