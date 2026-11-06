extends Node3D
# Ручник не должен зависеть от того, чем в него попали: с клавиатуры и с геймпада машина
# тормозится одинаково, блокировка остаётся на задней оси (передняя добирает лишь долю
# тормоза и продолжает рулить), и сила торможения меряется в g — жалоба «ручник почти не
# тормозит» это про величину, а не про факт срабатывания: потеря 5 км/ч из 60 это 0.14 g,
# и прежняя проверка её не видела.
# K) разгон и ручник событиями с клавиатуры
# J) то же самое настоящими событиями геймпада (курок + кнопка)
# Прогон: с зажатым газом (занос), с отпущенным (торможение как таковое) и служебный
# тормоз как линейка — ручник обязан тормозить короче педали, а не длиннее её.
const WINDOW := 60
const RUNS := ["key:gas", "key:coast", "key:foot", "joy:gas", "joy:coast"]
var car: CarRig
var _run_i := 0
var _dev := "key"
var _mode := "gas"
var _f := 0
var _v0 := 0.0
var _curve: Array[float] = []
var _curves := {}
var _gs := {}
var _pads := true
var _brake_ok := true
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

# События берутся из ТЕКУЩЕЙ раскладки, а не из hardcoded клавиш: тесты крутятся на
# машине игрока, где у него могут быть свои биндинги, и проверка «пробел — это ручник»
# ловит не поведение, а чужие настройки.
static func _first_of(action: String, cls: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if cls == "key" and e is InputEventKey: return e
		if cls == "pad" and (e is InputEventJoypadButton or e is InputEventJoypadMotion): return e
	return null

var _key_gas: InputEventKey
var _key_hb: InputEventKey
var _key_brk: InputEventKey
var _pad_gas: InputEventJoypadMotion
var _pad_hb: InputEventJoypadButton

func _key(e: InputEventKey, down: bool) -> void:
	if e == null: return
	var ev := e as InputEventKey
	var out := InputEventKey.new()
	out.physical_keycode = ev.physical_keycode
	out.pressed = down
	Input.parse_input_event(out)

func _pad_btn(down: bool) -> void:
	if _pad_hb == null: return
	var e := InputEventJoypadButton.new()
	e.button_index = _pad_hb.button_index
	e.device = 0
	e.pressed = down
	Input.parse_input_event(e)

# у InputEventJoypadMotion нет pressed: состояние передаётся самим axis_value, и курок
# «удерживается» только если значение приходит при каждом опросе. Значение берётся
# ПОЛНЫМ ходом (1.0 в знак привязки), а не порогом 0.5 из раскладки: иначе сравнение
# с клавиатурой некорректно — на клавиатуре газ = 1.0.
func _pad_axis(down: bool) -> void:
	if _pad_gas == null: return
	var e := InputEventJoypadMotion.new()
	e.axis = _pad_gas.axis
	e.axis_value = (signf(_pad_gas.axis_value) if down else 0.0)
	e.device = 0
	Input.parse_input_event(e)

func _gas(down: bool) -> void:
	if _dev == "joy":
		_pad_axis(down)
	else:
		_key(_key_gas, down)

func _brk(down: bool) -> void:
	_key(_key_brk, down)

func _hb(down: bool) -> void:
	if _dev == "joy":
		_pad_btn(down)
	else:
		_key(_key_hb, down)

func _start(run: String) -> void:
	var parts: PackedStringArray = run.split(":")
	_dev = parts[0]
	_mode = parts[1]
	_f = 0
	_v0 = 0.0
	_brake_ok = true
	_curve.clear()
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	_hb(false)
	_brk(false)
	_gas(true)

func _ready() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	_key_gas = _first_of("throttle", "key") as InputEventKey
	_key_hb = _first_of("handbrake", "key") as InputEventKey
	_key_brk = _first_of("brake", "key") as InputEventKey
	_pad_gas = _first_of("throttle", "pad") as InputEventJoypadMotion
	_pad_hb = _first_of("handbrake", "pad") as InputEventJoypadButton
	check(_key_gas != null and _key_hb != null, "у газа и ручника есть клавиатурное событие")
	if Input.get_connected_joypads().is_empty():
		print("PARTIAL: геймпад не подключён — сравнение устройств пропускается, проверяется только клавиатура")
		_pads = false
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	_start(RUNS[0])

func _check_axles() -> void:
	# Задняя ось заблокирована и без тяги; передняя на газу тянет (заносом можно рулить),
	# накатом катится свободно, но в любом случае заторможена НЕ сильнее задней. Если brake
	# дать через chassis.brake, Godot разовьёт его на все четыре колеса разом, и блокировка
	# четырёх колёс ставит машину в точку — ровно прежняя жалоба на геймпад.
	var rear_max := 0.0
	for w in car._wheels:
		if not w.use_as_steering: rear_max = maxf(rear_max, w.brake)
	for w in car._wheels:
		var front := w.use_as_steering
		if front and w.brake >= rear_max: _brake_ok = false
		if front and _mode == "gas" and w.engine_force <= 0.0: _brake_ok = false
		if not front and (w.brake <= 0.0 or w.engine_force != 0.0): _brake_ok = false

func _physics_process(_dt: float) -> void:
	_f += 1
	# и курок, и удерживаемая клавиша приходят в игру событием каждый тик: Godot
	# применяет состояние действий только в конце кадра
	if _dev == "joy" and _mode == "gas": _gas(true)
	if _f == 150:
		_v0 = car.speed_kmh()
		if _mode == "foot": _brk(true)
		else: _hb(true)
		if _mode != "gas": _gas(false)
	if _f > 150:
		_curve.append(car.speed_kmh())
		# CarRig — ребёнок харнеса, поэтому его _physics_process идёт после нашего:
		# состояние колёс за тик становится видно только на следующем
		if _f == 155: _check_axles()
	if _f == 151 + WINDOW:
		var run: String = RUNS[_run_i]
		_curves[run] = _curve.duplicate()
		if _mode != "foot": check(_brake_ok, "%s: на ручнике блокируется только задняя ось" % run)
		var g := (_v0 - _curve[WINDOW - 1]) / 3.6 / 9.81
		# «Мгновенная остановка» с геймпада — это не про потерю за секунду, а про короткий
		# тап курка: мерим, сколько машина успела потерять за 0.2 с и каким был пиковый
		# замедляющий тик. Прежний порог «осталось больше 60% скорости за 1 с» глушил и
		# нормальное торможение в 0.8 g, и жалобу тоже — он не отличал одно от другого.
		var tap := _v0 - _curve[11]
		var peak := 0.0
		for i in range(1, WINDOW):
			peak = maxf(peak, (_curve[i - 1] - _curve[i]) * 60.0 / 3.6 / 9.81)
		var what := "педаль" if _mode == "foot" else "ручник"
		print("%s: %s на %.0f км/ч теряет %.1f км/ч за 1 с = %.2f g, тап за 0.2 с %.1f км/ч (%.0f%%), пик %.2f g" % [
			run, what, _v0, _v0 - _curve[WINDOW - 1], g, tap, tap / _v0 * 100.0, peak])
		_gs[run] = g
		if _mode == "foot":
			# окно поднято вместе с BRAKE_MAX_G (1.25→1.65 g): замер педали на 57 км/ч
			# теперь 1.23 g с пиком 1.39; верх 1.5 по-прежнему ловит «удар о невидимую
			# стену», из-за которого окно и придумали (прежний прогон давал 2.7 g)
			check(g < 1.5, "%s: педаль в покрышечном пределе (%.2f g)" % [run, g])
		elif _mode == "gas":
			check(g > 0.55, "%s: ручник тормозит даже с зажатым газом (%.2f g)" % [run, g])
			check(g < 1.1, "%s: ручник на газу не удар о невидимую стену (%.2f g)" % [run, g])
		else:
			check(g > 0.7, "%s: без газа ручник тормозит как педаль (%.2f g)" % [run, g])
			check(g < 1.15, "%s: ручник накатом остаётся торможением, а не остановкой (%.2f g)" % [run, g])
		check(tap < _v0 * 0.25, "%s: короткое касание ручника не обнуляет скорость (%.1f -> %.1f)" % [run, _v0, _v0 - tap])
		check(peak < 1.5, "%s: ни один тик не тормозит сильнее предела сцепления (%.2f g)" % [run, peak])
		check(_curve[WINDOW - 1] > 0.0, "%s: машина остаётся в движении (%.1f км/ч)" % [run, _curve[WINDOW - 1]])
		_hb(false)
		_brk(false)
		_gas(false)
		_run_i += 1
		while _run_i < RUNS.size() and not _pads and RUNS[_run_i].begins_with("joy"):
			_run_i += 1
		if _run_i < RUNS.size():
			_start(RUNS[_run_i])
			return
		if _gs.has("key:foot"):
			check(_gs["key:foot"] > _gs.get("key:coast", 0.0),
				"педаль тормозит не короче ручника (%.2f g против %.2f g)" % [_gs["key:foot"], _gs.get("key:coast", 0.0)])
		if _pads:
			for mode in ["gas", "coast"]:
				var k: Array = _curves["key:" + mode]
				var j: Array = _curves["joy:" + mode]
				var worst := 0.0
				for i in WINDOW:
					worst = maxf(worst, absf(k[i] - j[i]))
				check(worst < 2.0, "геймпад и клавиатура тормозятся одинаково (%s, расхождение %.2f км/ч)" % [mode, worst])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
