extends Node3D
# Виброфид проверяется внедрёнными callable: импульс ровно один на удар,
# амплитуда растёт со скоростью и режется настройкой, непрерывный занос даёт
# rumble, остановка гасит его одним нулём, выключенная настройка не порождает
# ни одного вызова, устройство берётся из InputRouter.pad_index().
# Железо здесь проверить нельзя — реальный путь Input.* помечен PARTIAL.
var _fails := 0
var car: CarRig
var feed: VibrationFeed
var _rumbles: Array = []
var _impulses: Array = []
var _f := 0
var _phase := "accel"
var _stop_snapshot := 0
var _amp100 := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	Settings.reset()
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	feed = VibrationFeed.new(); add_child(feed)
	feed.rumble_fn = func(low: float, high: float, dev: int) -> void: _rumbles.append([low, high, dev])
	feed.impulse_fn = func(low: float, high: float, ms: int, dev: int) -> void: _impulses.append([low, high, ms, dev])
	feed.attach(car)
	# дефолтный путь без железа: pad_index -1, реальные вызовы Input.* не
	# делаются, исключений нет — сам удар при этом посчитан
	var raw := VibrationFeed.new()
	add_child(raw)
	raw.attach(car)
	car.impact.emit(80.0, Vector3.ZERO, Vector3.RIGHT)
	check(raw.impulse_calls == 1, "дефолтный путь без железа считает импульс (%d)" % raw.impulse_calls)
	raw.queue_free()
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	_f += 1
	match _phase:
		"accel":
			if _f == 120:
				_impacts()
		"drift":
			if _f == 220:
				_after_slip()
		"stopped":
			if _f == 245:
				_disabled()
		"disabled":
			if _f == 285:
				_finish()
		_:
			pass

func _one_impulse(speed: float) -> Array:
	_impulses.clear()
	car.impact.emit(speed, Vector3.ZERO, Vector3.RIGHT)
	if _impulses.size() != 1:
		check(false, "удар %.0f дал не один импульс (%d)" % [speed, _impulses.size()])
		return [0.0, 0.0, 0, -1]
	return _impulses[0]

func _impacts() -> void:
	var a := _one_impulse(100.0)
	_amp100 = float(a[0])
	check(_amp100 > 0.0 and _amp100 <= 1.0, "амплитуда в диапазоне (%.3f)" % _amp100)
	check(int(a[2]) > 0, "длительность положительная (%d)" % int(a[2]))
	var b := _one_impulse(190.0)
	check(float(b[0]) > _amp100, "быстрый удар вибрирует сильнее (%.3f > %.3f)" % [float(b[0]), _amp100])
	Settings.set_value("vibration_strength", 0.5)
	var c := _one_impulse(100.0)
	check(absf(float(c[0]) - _amp100 * 0.5) <= 0.01,
		"сила 0.5 режет амплитуду вдвое (%.3f против %.3f)" % [float(c[0]), _amp100 * 0.5])
	Settings.set_value("vibration_strength", 1.0)
	# устройство по умолчанию — из InputRouter.pad_index(): назначение на
	# конкретный геймпад переключает номер, которому шлётся вибрация
	var jb := InputEventJoypadButton.new()
	jb.button_index = 12
	jb.device = 2
	InputRouter.rebind("nitro", jb)
	check(InputRouter.pad_index() == 2, "pad_index помнит назначенный девайс (%d)" % InputRouter.pad_index())
	var d := _one_impulse(60.0)
	check(int(d[3]) == 2, "импульс ушёл девайсу 2 из InputRouter (%s)" % str(d))
	InputRouter.clear_binding("nitro")
	# занос: ручник + руль, rumble обязан появиться сам (не по нашей команде)
	Input.action_press("handbrake")
	Input.action_press("steer_right")
	_rumbles.clear()
	_phase = "drift"

func _after_slip() -> void:
	var any := false
	for r in _rumbles:
		if float(r[0]) > 0.1: any = true
	check(any and _rumbles.size() >= 2,
		"непрерывный занос даёт ненулевой rumble многократно (%d)" % _rumbles.size())
	# остановка (пауза/рестарт идут этим же путём): ровно один нулевой вызов,
	# и после неё — тишина, хотя машина всё ещё крутится на ручнике
	_rumbles.clear()
	feed.set_active(false)
	check(_rumbles.size() == 1 and float(_rumbles[0][0]) == 0.0 and float(_rumbles[0][1]) == 0.0,
		"остановка прислала один нулевой rumble (%s)" % str(_rumbles))
	_stop_snapshot = _rumbles.size() + _impulses.size()
	_phase = "stopped"

func _disabled() -> void:
	check(_rumbles.size() + _impulses.size() <= _stop_snapshot,
		"после остановки новых вызовов нет (%d против %d)" % [
			_rumbles.size() + _impulses.size(), _stop_snapshot])
	feed.set_active(true)
	Settings.set_value("vibration_enabled", false)
	var n := _rumbles.size() + _impulses.size()
	car.impact.emit(150.0, Vector3.ZERO, Vector3.RIGHT)
	_phase = "disabled"
	_dis_n = n

var _dis_n := 0

func _finish() -> void:
	check(_rumbles.size() + _impulses.size() == _dis_n,
		"выключенная вибрация не порождает ни одного вызова (+%d)" % [
			_rumbles.size() + _impulses.size() - _dis_n])
	Input.action_release("throttle")
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	car.slip = 0.0
	if Input.get_connected_joypads().is_empty():
		print("PARTIAL: живого геймпада нет — реальный путь Input.start_joy_vibration проверен только внедрёнными заглушками")
	Settings.reset()
	InputRouter.reset_keys()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
