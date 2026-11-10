extends Node3D
# Asset wheels and impassability: the wheel axis is across the car, wheels rest on
# the ground, the front wheels steer, and the frame and body do not pass through a thin wall.
var _fails := 0
var _frame := 0
var car: CarRig
var wall_x := 6.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(60, 2, 60); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	# thin wall: face at x = 6.0
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.2, 4, 8); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(6.1, 2, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-14.0, 1.0, 0)))

func _physics_process(_dt: float) -> void:
	# The car appears in _ready via await: on a real renderer that is later than
	# frame 6 than in headless. Count from its appearance, or the test measures emptiness.
	if car == null: return
	_frame += 1
	if _frame == 6:
		var b := car.body
		check(b.wheels.size() == 4, "four wheels (%d)" % b.wheels.size())
		check(b.front_wheels.size() == 2, "two front wheels (%d)" % b.front_wheels.size())
		for w in b.wheels:
			# the asset wheel is an ArrayMesh: check via the world AABB.
			# The car looks toward +X, so the wheel axis is world Z (thin), and the diameter along X and Y.
			var wa: AABB = w.global_transform * w.get_aabb()
			check(wa.size.z < wa.size.y * 0.75, "the wheel axis is across the car (tire %.2f thinner than diameter %.2f)" % [wa.size.z, wa.size.y])
			check(absf(wa.size.y * 0.5 - b.wheel_radius) < 0.03, "the wheel radius matches params (%.3f vs %.3f)" % [wa.size.y * 0.5, b.wheel_radius])
			check(absf(wa.size.x * 0.5 - b.wheel_radius) < 0.03, "the wheel is round in the longitudinal plane (%.3f)" % (wa.size.x * 0.5))
		Input.action_press("steer_left")
	if _frame == 30:
		# the VehicleBody3D suspension settles over several ticks, so height is not measured immediately
		for w in car.body.wheels:
			var wa: AABB = w.global_transform * w.get_aabb()
			check(absf(wa.position.y) < 0.03, "the wheel touches the floor (bottom at %.3f)" % wa.position.y)
		var f0 := car.body.front_wheels[0].rotation.y
		var back := car.body.wheels[0]
		for w in car.body.wheels:
			if not car.body.front_wheels.has(w): back = w
		check(absf(f0) > 0.05, "the front wheel turned (%.3f rad)" % f0)
		check(absf(back.rotation.y) < 0.01, "the rear wheel does not turn (%.3f)" % back.rotation.y)
		Input.action_release("steer_left")
		Input.action_press("throttle")
	if _frame == 240:
		Input.action_release("throttle")
		check(car.chassis.global_position.x < wall_x, "the frame did not pass through the wall (%.2f)" % car.chassis.global_position.x)
		check(car.speed_kmh() < 12.0, "the car stopped against the wall (%.1f km/h)" % car.speed_kmh())
		check(car.body.dent_count > 0, "the wall impact dented the body (%d)" % car.body.dent_count)
		var below := 0; var thru := 0; var bad := 0
		for i in car.body.vertex_count():
			var w := car.body.vertex_world(i)
			if not w.is_finite(): bad += 1
			if w.y < -0.05: below += 1
			if w.x > wall_x + 0.15: thru += 1
		check(bad == 0, "all vertices are finite (%d)" % bad)
		check(below == 0, "the body did not sink below the floor (%d)" % below)
		check(thru == 0, "the body did not pass through the wall (%d)" % thru)
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
