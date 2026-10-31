extends Node3D
# Ручник с геймпада проверяется на ЖИВОЙ сцене, а не на голом CarRig: h_t20_devices
# доказал, что тормоза на колёсах одинаковые с клавиатуры и с курка, но жалоба игрока
# осталась. Значит кнопка A делает что-то ещё, кроме как поднимает действие «ручник», —
# и поймать это можно только вместе с HUD, меню паузы и фокусом контролов.
# K) клавиатурный пробел, J) настоящая кнопка геймпада через полный путь событий.
const WINDOW := 60
var _fails := 0
var gm: GameManager
var _dev := "key"
var _f := 0
var _v0 := 0.0
var _pos_before := Vector3.ZERO
var _curve: Array[float] = []
var _curves := {}
var _events := {}
var _pad := false
var _pad_hb: InputEventJoypadButton
var _pad_gas: InputEventJoypadMotion
var _key_gas: InputEventKey
var _key_hb: InputEventKey

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	_pad = not Input.get_connected_joypads().is_empty()
	for e in InputMap.action_get_events("throttle"):
		if e is InputEventKey: _key_gas = e
		elif e is InputEventJoypadMotion: _pad_gas = e
	for e in InputMap.action_get_events("handbrake"):
		if e is InputEventKey: _key_hb = e
		elif e is InputEventJoypadButton: _pad_hb = e
	# Замер кривой идёт по городку: на арене и трассе теперь честные горки и бугры
	# (раньше они были декорацией), и тормозящая машина успевала на них наехать — тест
	# мерил бы рельеф, а не ручник. Ровный асфальт городка для этого и выбран.
	GameContext.select("sedan", "town")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().process_frame
	# ловим не состояние, а сам факт: что именно успело произойти за нажатие
	gm.hud.menu_requested.connect(func(): _note("menu"))
	gm.hud.resume_requested.connect(func(): _note("resume"))
	gm.hud.restart_requested.connect(func(): _note("restart"))
	gm.hud.settings_requested.connect(func(): _note("settings"))
	if _pad: await _focus_trap()
	_start("key")

func _note(what: String) -> void:
	_events[what] = int(_events.get(what, 0)) + 1

# Живое событие идёт двумя дорожками сразу: Input обновляет состояние действий
# (его читает CarRig), а viewport раздаёт его контролам (его читает GUI: кнопки паузы,
# ui_accept). push_input сам по себе состояние действий НЕ поднимает — поэтому харнес
# на голом CarRig этого и не видел.
func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	get_viewport().push_input(ev)

func _key(e: InputEvent, down: bool) -> void:
	if e == null: return
	var ev := InputEventKey.new()
	ev.physical_keycode = (e as InputEventKey).physical_keycode
	ev.pressed = down
	_send(ev)

func _pad_btn(down: bool) -> void:
	if _pad_hb == null or not _pad: return
	var e := InputEventJoypadButton.new()
	e.button_index = _pad_hb.button_index
	e.device = 0
	e.pressed = down
	_send(e)

func _pad_axis(down: bool) -> void:
	if _pad_gas == null or not _pad: return
	var e := InputEventJoypadMotion.new()
	e.axis = _pad_gas.axis
	e.axis_value = signf(_pad_gas.axis_value) if down else 0.0
	e.device = 0
	_send(e)

func _gas(down: bool) -> void:
	if _dev == "joy": _pad_axis(down)
	else: _key(_key_gas, down)

func _hb(down: bool) -> void:
	if _dev == "joy": _pad_btn(down)
	else: _key(_key_hb, down)

func _start(dev: String) -> void:
	_dev = dev
	_f = 0
	_curve.clear()
	_events = {}
	_v0 = 0.0
	gm._respawn_now()
	_gas(true)

# Ловушка фокуса: кнопка меню паузы остаётся сфокусированной, когда карточка уже
# скрыта, а кнопка A на геймпаде — это ещё и ui_accept. Значит «ручник» может
# оказаться нажатием невидимой кнопки, и машина мгновенно встанет — рестарт или
# выход в меню. Проверяем именно это: фокус ставим руками, нажимаем ручник.
func _focus_trap() -> void:
	var b := gm.hud.pause_button("ЗАПУСТИТЬ ЗАНОВО")
	check(b != null, "у меню паузы есть кнопка рестарта")
	if b == null: return
	gm._set_paused(true)
	await get_tree().process_frame
	b.grab_focus()
	gm._set_paused(false)
	await get_tree().process_frame
	_events = {}
	_pad_btn(true)
	await get_tree().process_frame
	_pad_btn(false)
	await get_tree().process_frame
	check(_events.is_empty(),
		"скрытая кнопка не съедает ручник геймпада (%s)" % str(_events.keys()))
	check(not gm._paused, "ручник не ставит игру на паузу через скрытую кнопку")

func _physics_process(_dt: float) -> void:
	_f += 1
	# курок живёт до следующего события, а вот кнопка приходит один раз: чтобы действие
	# оставалось нажатым, событие нужно слать каждый тик — как это делает удержание
	if _dev == "joy": _gas(true)
	if _f == 150:
		_v0 = gm.car.speed_kmh()
		_pos_before = gm.car.chassis.global_position
		_hb(true)
	if _f > 150:
		_curve.append(gm.car.speed_kmh())
	if _f == 151 + WINDOW:
		_finish()

func _finish() -> void:
	var moved := gm.car.chassis.global_position.distance_to(_pos_before)
	check(_events.is_empty(), "%s: ручник не трогает интерфейс (%s)" % [_dev, str(_events.keys())])
	check(not get_tree().paused, "%s: ручник не ставит игру на паузу" % _dev)
	check(moved > 1.0, "%s: машина продолжает ехать, а не телепортируется (%.1f м)" % [_dev, moved])
	check(_curve.size() >= WINDOW, "%s: кривая снята целиком (%d)" % [_dev, _curve.size()])
	check(_curve[WINDOW - 1] > _v0 * 0.6,
		"%s: ручник не обнуляет скорость мгновенно (%.1f -> %.1f)" % [_dev, _v0, _curve[WINDOW - 1]])
	check(_curve[WINDOW - 1] < _v0 - 5.0,
		"%s: ручник всё же тормозит (%.1f -> %.1f)" % [_dev, _v0, _curve[WINDOW - 1]])
	_curves[_dev] = _curve.duplicate()
	_hb(false)
	_gas(false)
	if _dev == "key" and _pad:
		_start("joy")
	else:
		if _pad:
			var k: Array = _curves["key"]
			var j: Array = _curves["joy"]
			var worst := 0.0
			for i in WINDOW: worst = maxf(worst, absf(k[i] - j[i]))
			check(worst < 8.0, "живой геймпад и клавиатура тормозятся похоже (расхождение %.1f км/ч)" % worst)
		else:
			print("NOTE: геймпад не подключён — проверялась только клавиатура")
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
