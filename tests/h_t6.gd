extends Node3D
var _fails := 0
var _frame := 0
var car: CarRig

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(1400, 1, 60); cs.shape = box
	var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
	body.add_child(cs); add_child(body); body.global_position = Vector3(600, -0.5, 0)
	ObstacleField.add(Vector3(600, -0.5, 0), Vector3(700, 0.5, 30))
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame in [487, 500, 540, 551, 560]: print("probe "+str(_frame)+" thr="+str(Input.get_action_strength("throttle"))+" brk="+str(Input.get_action_strength("brake"))+" str="+str(Input.get_action_strength("steer_left"))+" v="+str(car.speed_kmh()))

	# фаза 1: разгон 8 с (асимптотика аркадной тяги)
	if _frame == 5: Input.action_press("throttle")
	if _frame == 485:
		check(car.speed_kmh() > 0.7 * 160 and car.speed_kmh() < 1.1 * 160,
			"reach ~vmax (%.1f km/h)" % car.speed_kmh())
		check(absf(car.chassis.global_position.z) < 3.0, "straight-line drift small")
		Input.action_release("throttle"); Input.action_press("brake")
	if _frame == 546:
		Input.action_release("brake")
		check(car.speed_kmh() < 90.0, "braked below 90 (%.1f)" % car.speed_kmh())
	# фаза 2: рулёжка на средней скорости
	if _frame == 550: Input.action_press("steer_left")
	if _frame == 590:
		check(car.heading > deg_to_rad(12.0), "steered left (%.0f deg)" % rad_to_deg(car.heading))
		Input.action_release("steer_left")
	if _frame == 595: Input.action_press("throttle")
	# фаза 3: ручник-дрифт
	if _frame == 605: Input.action_press("handbrake"); Input.action_press("steer_right")
	if _frame == 665:
		var vel := car.chassis.linear_velocity
		var fwd := Vector3(cos(car.heading), 0, -sin(car.heading))
		var lat := vel - fwd * vel.dot(fwd)
		check(lat.length() > 2.0, "handbrake induces lateral slip (%.1f)" % lat.length())
		check(car.chassis.global_position.is_finite(), "no NaN trajectory")
	if _frame == 680:
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
