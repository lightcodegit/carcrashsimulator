extends Node
# Настройки переживают враждебный файл, конфликтные бинды не дублируются, а
# рестарт не наследует состояние педалей. Родительский кейс: одна правка
# settings.cfg руками обрывала загрузку посередине, и все настройки молча
# слетали (проверено на bool(Array) и String(dict)).
const PATH_CFG := "user://settings.cfg"
var _backup := ""
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(PATH_CFG):
		var f := FileAccess.open(PATH_CFG, FileAccess.READ)
		_backup = f.get_as_text()
	await _hostile_cfg()
	await _rebind_collision()
	await _respawn_state()
	if _backup != "":
		var w := FileAccess.open(PATH_CFG, FileAccess.WRITE)
		w.store_string(_backup)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _write(text: String) -> void:
	var f := FileAccess.open(PATH_CFG, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _hostile_cfg() -> void:
	_write("[video]\nfog = [1, 2, 3]\nfov = {}\nscale = \"abc\"\npreset = -1\n" +
		"shadow_preset = Vector2(1,1)\n[window]\nw = 0\nh = 0\nmax = [true]\n" +
		"[keys]\nthrottle = {}\nbrake = 42\nnitro = [65, 66]\n")
	Settings.load_values()
	check(Settings.preset == 0, "preset вне диапазона прижат к границе (%d)" % Settings.preset)
	check(Settings.preset_name() != "", "имя пресета читается (%s)" % Settings.preset_name())
	check(Settings.fov >= 60.0 and Settings.fov <= 120.0,
		"fov после мусора в пределах разумного (%.1f)" % Settings.fov)
	check(Settings.scale >= 0.5 and Settings.scale <= 1.0,
		"scale после мусора в пределах разумного (%.2f)" % Settings.scale)
	check(typeof(Settings.fog) == TYPE_BOOL, "bool-ключ остался bool (%s)" % typeof(Settings.fog))
	# бинды из битых строк не читаются, но и не теряются: действие остаётся по умолчанию
	var th := InputMap.action_get_events("throttle")
	check(th.size() > 0, "throttle остался с биндом после {} в файле (%d)" % th.size())
	var br := InputMap.action_get_events("brake")
	check(br.size() > 0, "brake остался с биндом после числа в файле (%d)" % br.size())
	Settings.reset()

func _rebind_collision() -> void:
	# конфликт двух НАЗНАЧЕННЫХ игроком биндов: второй забирает клавишу у первого
	var k1 := InputEventKey.new(); k1.physical_keycode = KEY_G
	var k2 := InputEventKey.new(); k2.physical_keycode = KEY_G
	InputRouter.rebind("throttle", k1)
	InputRouter.rebind("brake", k2)
	var has_g := func(action: String) -> bool:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_G:
				return true
		return false
	check(has_g.call("brake"), "G назначена тормозу")
	check(not has_g.call("throttle"),
		"G снята с газа: два игроцких назначения не делят одну клавишу")
	# дефолтный конфликт остаётся возможным (модель замещения класса не выражает
	# «клавиш нет вовсе»), поэтому проверяем лишь, что прежнее поведение целое:
	# новое назначение принято, класс клавиш замещён одним событием
	var w := InputEventKey.new(); w.physical_keycode = KEY_H
	InputRouter.rebind("handbrake", w)
	var hk := 0
	for e in InputMap.action_get_events("handbrake"):
		if e is InputEventKey:
			hk += 1
			check((e as InputEventKey).physical_keycode == KEY_H,
				"у ручника осталась только назначенная клавиша")
	check(hk == 1, "назначение поверх дефолта заместило класс клавиш (%d)" % hk)
	InputRouter.clear_binding("throttle")
	InputRouter.clear_binding("brake")
	InputRouter.clear_binding("handbrake")

func _respawn_state() -> void:
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 10:
		await get_tree().physics_frame
	var car := g.car
	car.chassis.linear_velocity = Vector3.ZERO
	Input.action_press("brake")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("brake")
	check(car._rev_lag > 0.0, "на затормозившей машине лаг заднего хода накоплен (%.2f)" % car._rev_lag)
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	check(is_equal_approx(car._rev_lag, 0.0) and is_equal_approx(car._hand_pedal, 0.0),
		"рестарт обнулил лаг и давление ручника (%.2f / %.2f)" % [car._rev_lag, car._hand_pedal])
	g.queue_free()
	for i in 6:
		await get_tree().physics_frame
