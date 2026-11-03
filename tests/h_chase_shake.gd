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
var _dist_n := 0

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
	# Родитель по дереву обрабатывается раньше детей, а нам нужно смотреть на камеру
	# ПОСЛЕ того, как она сама себя обновила в этом кадре, иначе меряем собственный
	# пропуск в один кадр (0.7 м на 150 км/ч) вместо промаха погони.
	process_priority = 10

func _ideal_chase() -> Vector3:
	# Идеал считаем по РИСУЕМОМУ положению и рисуемому курсу: именно за ними стоит
	# погоня (см. CarRig.render_transform()). По тиковой машине идеал отличался бы на
	# путь за один тик физики — метр на 150 км/ч — и проверял бы не камеру, а такты.
	var gt: Transform3D = car.render_transform()
	var fwd: Vector3 = gt.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6: fwd = fwd.normalized()
	var speed := car.chassis.linear_velocity.length()
	var back := 5.0 + minf(speed, 60.0) * 0.045
	var up := 1.9 + minf(speed, 60.0) * 0.010
	return gt.origin - fwd * back + Vector3(0, up, 0)

# Дрожание погони. Меряется живьём и по РИСУЕМОМУ положению машины: физика считает
# 60 Гц, кадр строится чаще, и если камера берёт тиковую позицию, она каждый кадр
# промахивается на метр-два пути — «отстаёт, догоняет, мелькает». В headless кадр не
# рисуется и интерполяции между тиками нет, поэтому там проверка пропускается.
func _process(_dt: float) -> void:
	if DisplayServer.get_name() == "headless": return
	# Меряем только на скорости: промах погони пропорционален пути за один тик физики,
	# на 30 км/ч он в шесть раз меньше, чем на 180, и на малой скорости проверка бы
	# просто не заметила прежнюю ошибку.
	if car == null or car.chassis == null or car.speed_kmh() < 100.0: return
	var gt: Transform3D = car.render_transform()
	var gap := (gt.origin - cam.global_position).dot(gt.basis.z)
	_smooth = gap if _jit.is_empty() else lerpf(_smooth, gap, 0.2)
	if _jit.size() < 600: _jit.append(absf(gap - _smooth))
	# Дистанцию погони меряем в том же кадре, где камера её считает: из _physics_process
	# рисуемая машина выглядит на тик старше, и на 150 км/ч это метр дистанции, которого
	# в самой камере нет — проверка меряла бы такты, а не погоню.
	var fwd: Vector3 = gt.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6: fwd = fwd.normalized()
	var sp := car.chassis.linear_velocity.length()
	var want_dist := Vector2(5.0 + minf(sp, 60.0) * 0.045, 1.9 + minf(sp, 60.0) * 0.010).length()
	_dist_dev = maxf(_dist_dev, absf(cam.global_position.distance_to(gt.origin) - want_dist))
	_dist_n += 1

var _jit: Array[float] = []
var _smooth := 0.0

func _physics_process(_dt: float) -> void:
	# машина собирается в _ready через await: на реальном рендере это позже
	# нужного кадра, и отсчёт ведём от её появления, а не от запуска сцены
	if car == null: return
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
	if _frame == 1500:
		Input.action_release("throttle")
		check(car.speed_kmh() > 100.0, "машина разогналась (%.1f км/ч)" % car.speed_kmh())
		if _dist_n == 0:
			# в headless кадров не рисуется и _process выходит раньше замеров:
			# молча сравнить нуль с порогом значило бы «зелено» без проверки
			print("NOTE: дистанция погони не мерилась (нет живых кадров)")
		else:
			check(_dist_dev < 0.2, "на скорости камера держит дистанцию без отставания (отклонение %.2f м)" % _dist_dev)
	if _frame == 3000:
		check(car.speed_kmh() < 5.0, "машина остановилась накатом (%.1f км/ч за 25 с)" % car.speed_kmh())
		if _jit.is_empty():
			print("NOTE: кадров не рисовалось (headless или окно не видно) — дрожание не мерилось")
		else:
			var mx := 0.0
			var mean := 0.0
			for g in _jit:
				mx = maxf(mx, g)
				mean += g
			mean /= float(_jit.size())
			check(mean < 0.02, "камера идёт за рисуемой машиной без дрожания (среднее %.3f м)" % mean)
			# максимум не нормируем: на разгоне камера по замыслу отъезжает дальше
			# (back растёт со скоростью), это не дрожание; дрожание — среднее отклонение
			print("кадров %d: среднее дрожание %.3f м, максимум %.3f м" % [_jit.size(), mean, mx])
		check(cam.global_position.distance_to(_ideal_chase()) < 0.05,
			"после остановки камера ровно в точке погони (%.3f м)" % cam.global_position.distance_to(_ideal_chase()))
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
