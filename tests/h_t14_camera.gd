extends Node3D
# Камера погони: шейк накладывается на чистую позицию и не накапливается,
# на скорости камера не отстаёт, после затухания возвращается точно на место.
var _fails := 0
var _frame := 0
var car: CarRig
var cam: CameraRig
var _ideal := Vector3.ZERO
var _max_dev := 0.0
var _dist_dev := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 200); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(1500, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	cam = CameraRig.new(); add_child(cam); cam.setup(car); cam.make_current()

func _ideal_chase() -> Vector3:
	var fwd := car.forward()
	var speed := car.chassis.linear_velocity.length()
	var back := 5.0 + minf(speed, 60.0) * 0.045
	var up := 1.9 + minf(speed, 60.0) * 0.010
	return car.chassis.global_position - fwd * back + Vector3(0, up, 0)

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 120:
		_ideal = _ideal_chase()
		check(cam.global_position.distance_to(_ideal) < 0.05,
			"камера сошлась на точку погони (%.3f м)" % cam.global_position.distance_to(_ideal))
	if _frame > 120 and _frame <= 240:
		# держим максимальную тряску и меряем отклонение от идеала
		cam.add_trauma(1.0)
		_max_dev = maxf(_max_dev, cam.global_position.distance_to(_ideal_chase()))
	if _frame == 241:
		check(_max_dev < 0.6, "шейк не накапливается в позицию (max отклонение %.3f м)" % _max_dev)
	if _frame > 241 and _frame <= 400:
		pass   # тряска затухает сама
	if _frame == 401:
		check(cam.global_position.distance_to(_ideal_chase()) < 0.05,
			"после затухания камера вернулась точно на место (%.3f м)" % cam.global_position.distance_to(_ideal_chase()))
		Input.action_press("throttle")
	if _frame > 500 and _frame <= 900:
		var speed := car.chassis.linear_velocity.length()
		var back := 5.0 + minf(speed, 60.0) * 0.045
		var up := 1.9 + minf(speed, 60.0) * 0.010
		var want_dist := Vector2(back, up).length()
		var d := cam.global_position.distance_to(car.chassis.global_position)
		# допуск 1.2 м: камера обновляется в _process, а замер в _physics_process — это ~1 кадр пути
		_dist_dev = maxf(_dist_dev, absf(d - want_dist))
	if _frame == 901:
		Input.action_release("throttle")
		check(car.speed_kmh() > 100.0, "машина разогналась (%.1f км/ч)" % car.speed_kmh())
		check(_dist_dev < 1.2, "на скорости камера держит дистанцию без отставания (отклонение %.2f м)" % _dist_dev)
	if _frame == 2400:
		check(car.speed_kmh() < 5.0, "машина остановилась накатом (%.1f км/ч за 25 с)" % car.speed_kmh())
		check(cam.global_position.distance_to(_ideal_chase()) < 0.05,
			"после остановки камера ровно в точке погони (%.3f м)" % cam.global_position.distance_to(_ideal_chase()))
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
