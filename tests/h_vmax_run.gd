extends Node3D
var _fails := 0
var _frame := 0
var car: CarRig
var _max_lat := 0.0
var _max_slip_deg := 0.0
var _max_yaw := 0.0
var _v_brake := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(2400, 2, 900); cs.shape = box
	var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
	body.add_child(cs); add_child(body); body.global_position = Vector3(900, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))

func _physics_process(_dt: float) -> void:
	# машина собирается в _ready через await: на реальном рендере это позже
	# нужного кадра, и отсчёт ведём от её появления, а не от запуска сцены
	if car == null: return
	_frame += 1

	# фаза 1: разгон 8 с (асимптотика тяги к vmax)
	if _frame == 5: Input.action_press("throttle")
	if _frame == 485:
		check(car.speed_kmh() > 0.7 * 160 and car.speed_kmh() < 1.1 * 160,
			"reach ~vmax (%.1f km/h)" % car.speed_kmh())
		check(absf(car.chassis.global_position.z) < 3.0, "straight-line drift small")
		_v_brake = car.speed_kmh()
		Input.action_release("throttle"); Input.action_press("brake")
	if _frame == 546:
		Input.action_release("brake")
		# за секунду полного торможения шины держат ~1.2 g = ~43 км/ч. Прежняя проверка
		# («ниже 90») пропускала и 2.7 g: машина вставала в одну точку, и игрок читал
		# это как «мгновенно сбрасывает скорость». Теперь диапазон и есть требование.
		var lost := _v_brake - car.speed_kmh()
		check(lost > 30.0 and lost < 62.0,
			"торможение в покрышечном пределе: -%.0f км/ч за 1 с (%.1f g)" % [lost, lost / 3.6 / 9.81])
	# фаза 2: рулёжка на средней скорости
	if _frame == 550: Input.action_press("steer_left")
	if _frame == 590:
		check(car.heading > deg_to_rad(12.0), "steered left (%.0f deg)" % rad_to_deg(car.heading))
		Input.action_release("steer_left")
	if _frame == 595: Input.action_press("throttle")
	# фаза 3: ручник-дрифт. Разгоняемся и только потом дёргаем ручник без газа — так
	# занос делают в жизни. Пик скольжения ищем по всему окну: в момент замера машина
	# может уже довернуться, и мгновенная боковая скорость окажется почти нулевой.
	if _frame == 780:
		check(car.speed_kmh() > 70.0, "разогнались перед ручником (%.1f км/ч)" % car.speed_kmh())
		Input.action_release("throttle")
		Input.action_press("handbrake"); Input.action_press("steer_right")
	if _frame > 780 and _frame <= 840:
		var vel := car.chassis.linear_velocity
		var fwd := Vector3(cos(car.heading), 0, -sin(car.heading))
		var lat := (vel - fwd * vel.dot(fwd)).length()
		_max_lat = maxf(_max_lat, lat)
		if vel.length() > 2.0:
			_max_slip_deg = maxf(_max_slip_deg, rad_to_deg(acos(clampf(vel.normalized().dot(fwd), -1.0, 1.0))))
		_max_yaw = maxf(_max_yaw, absf(car.chassis.angular_velocity.y))
	if _frame == 840:
		check(_max_lat > 2.0, "ручник срывает машину в скольжение (пик %.1f м/с)" % _max_lat)
		check(_max_slip_deg > 10.0, "ручник даёт угол заноса (пик %.1f°)" % _max_slip_deg)
		check(_max_yaw > 0.8, "ручник доворачивает нос (пик %.2f рад/с)" % _max_yaw)
		check(car.chassis.global_position.is_finite(), "no NaN trajectory")
	if _frame == 860:
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
