extends Node3D
var fails := 0
var car: CarRig

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func release() -> void:
	for action in ["throttle", "brake", "nitro", "steer_left"]: Input.action_release(action)

func _ready() -> void:
	if not ResourceLoader.exists("res://scripts/core/garage_profiles.gd"):
		check(false, "runtime garage tuning missing")
		get_tree().quit(1)
		return
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position.y = -1
	var store = load("res://scripts/core/garage_profiles.gd").new()
	store.select_vehicle("sedan")
	var speeds: Array[float] = []
	var stops: Array[float] = []
	for tuned in [false, true]:
		store.factory_reset()
		if tuned:
			for key in {"accel_max":10.5, "brake_decel":8.0, "grip":12.0, "suspension_stiffness":60.0, "damping_compression":4.0, "damping_relaxation":5.0, "nitro_accel":18.0, "nitro_capacity":200.0}:
				store.set_value(key, {"accel_max":10.5, "brake_decel":8.0, "grip":12.0, "suspension_stiffness":60.0, "damping_compression":4.0, "damping_relaxation":5.0, "nitro_accel":18.0, "nitro_capacity":200.0}[key])
		car = CarRig.new()
		add_child(car)
		car.build(store.draft_params(), get_world_3d())
		car.respawn(Transform3D.IDENTITY)
		await frames(90)
		check(absf(car.chassis.position.y - car.body.wheel_radius) < 0.035, "tuned suspension settles at stock ride height")
		if tuned:
			for wheel in car._wheels:
				check(wheel.suspension_stiffness == 60 and wheel.damping_compression == 4 and wheel.damping_relaxation == 5, "suspension tuning reaches all wheels")
				check(is_equal_approx(wheel.wheel_friction_slip, 5.1), "grip reaches runtime slip")
				check(wheel.wheel_rest_length > 0.07, "softer springs update dependent rest length")
			check(car.nitro == 200, "tuned tank full at spawn")
		Input.action_press("throttle")
		await frames(120)
		speeds.append(car.speed_kmh())
		release()
		car.respawn(Transform3D.IDENTITY)
		await frames(60)
		car.chassis.linear_velocity = Vector3(20, 0, 0)
		Input.action_press("brake")
		await frames(60)
		stops.append(car.speed_kmh())
		if tuned:
			check(absf(car._wheels[0].brake - 1300.0 * 8.0 / 240.0) < 0.01, "service brake reaches wheel impulse")
		release()
		car.respawn(Transform3D.IDENTITY)
		await frames(60)
		car.set_physics_process(false)
		car.chassis.linear_velocity = Vector3.ZERO
		Input.action_press("throttle")
		Input.action_press("nitro")
		car._drive(1.0 / 60.0)
		var expected := 1300.0 * (28.5 if tuned else 16.0) / 4.0
		check(absf(car._wheels[0].engine_force - expected) < 0.1, "traction plus nitro force reaches wheels")
		car.set_physics_process(true)
		await frames(150)
		check(car.nitro > 70 if tuned else car.nitro < 1, "capacity changes boost duration")
		release()
		car.queue_free()
		await get_tree().process_frame
	check(speeds[1] > speeds[0] * 1.25, "traction tuning increases measured acceleration: %s" % str(speeds))
	check(stops[1] > stops[0] + 10, "lower brake setting increases stopping distance: %s" % str(stops))
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
