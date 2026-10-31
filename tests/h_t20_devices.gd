extends Node3D
# Ручник не должен зависеть от того, чем в него попали: с клавиатуры и с геймпада
# машина тормозится одинаково, и блокируется только задняя ось.
# K) разгон и ручник событиями с клавиатуры
# J) то же самое настоящими событиями геймпада (курок + кнопка A)
# Дальше кривые скорости сравниваются между собой, а состояние колёс — с ожиданиями.
const WINDOW := 60
var car: CarRig
var _dev := "key"
var _f := 0
var _v0 := 0.0
var _curve: Array[float] = []
var _curves := {}
var _brake_ok := true
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _pad_btn(i: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = i
	e.device = 0
	e.pressed = down
	Input.parse_input_event(e)

func _pad_axis(a: int, v: float) -> void:
	# у InputEventJoypadMotion нет pressed: состояние передаётся самим axis_value,
	# и курок «удерживается» только если значение приходит при каждом опросе
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = 0
	Input.parse_input_event(e)

func _gas(down: bool) -> void:
	if _dev == "joy":
		_pad_axis(5, 1.0 if down else 0.0)
	else:
		_key(KEY_W, down)

func _hb(down: bool) -> void:
	if _dev == "joy":
		_pad_btn(0, down)
	else:
		_key(KEY_SPACE, down)

func _start(dev: String) -> void:
	_dev = dev
	_f = 0
	_v0 = 0.0
	_curve.clear()
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	_gas(true)

func _ready() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	check(not Input.get_connected_joypads().is_empty(), "нет подключённого геймпада — проверка бессмысленна")
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	_start("key")

func _check_axles() -> void:
	# на ручнике с зажатым газом: задняя ось заблокирована и без тяги, передняя свободна
	# и тянет. Если brake дать через chassis.brake, Godot разовьёт его на все четыре колеса.
	for w in car._wheels:
		var front := w.use_as_steering
		if front and (w.brake > 0.0 or w.engine_force <= 0.0): _brake_ok = false
		if not front and (w.brake <= 0.0 or w.engine_force != 0.0): _brake_ok = false

func _physics_process(_dt: float) -> void:
	_f += 1
	if _dev == "joy": _gas(true)          # курок надо удерживать событием каждый тик
	if _f == 150:
		_v0 = car.speed_kmh()
		_hb(true)
	if _f > 150:
		_curve.append(car.speed_kmh())
		# CarRig — ребёнок харнеса, поэтому его _physics_process идёт после нашего:
		# состояние колёс за тик становится видно только на следующем
		if _f == 155:
			_check_axles()
	if _f == 151 + WINDOW:
		_curves[_dev] = _curve.duplicate()
		check(_brake_ok, "%s: на ручнике блокируется только задняя ось" % _dev)
		check(_curve[WINDOW - 1] > _v0 * 0.6, "%s: ручник не останавливает машину мгновенно (%.1f -> %.1f)" % [_dev, _v0, _curve[WINDOW - 1]])
		check(_curve[WINDOW - 1] < _v0 - 5.0, "%s: ручник всё же тормозит (%.1f -> %.1f)" % [_dev, _v0, _curve[WINDOW - 1]])
		_hb(false)
		_gas(false)
		if _dev == "key":
			_start("joy")
		else:
			var k: Array = _curves["key"]
			var j: Array = _curves["joy"]
			var worst := 0.0
			for i in WINDOW:
				worst = maxf(worst, absf(k[i] - j[i]))
			check(worst < 2.0, "геймпад и клавиатура тормозятся одинаково (расхождение %.2f км/ч)" % worst)
			print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
			get_tree().quit(0 if _fails == 0 else 1)
