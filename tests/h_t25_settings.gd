extends Node3D
# Настройки и переопределение клавиш.
# 1) дефолты совпадают с тем, что проект делал до появления настроек
# 2) значение доживает до перезагрузки и обратно
# 3) rebind меняет только свой класс устройств: клавиша не съедает геймпад
# 4) сериализация событий читается обратно во всех трёх видах
# 5) экран настроек строится, открывается и перехватывает назначение
# Файл игрока в user:// на время теста сохраняется и восстанавливается: тест не имеет
# права оставлять после себя чужую раскладку.
var _fails := 0
var _backup := ""
var _had_file := false
var _path := "user://settings.cfg"
var menu: SettingsMenu

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	_had_file = FileAccess.file_exists(_path)
	if _had_file:
		var f := FileAccess.open(_path, FileAccess.READ)
		_backup = f.get_as_text()
	await get_tree().process_frame
	_defaults()
	_persist()
	await _rebind()
	await _codec()
	await _build_menu()

func _defaults() -> void:
	check(Settings.msaa == Settings.Msaa.X4, "1: MSAA 4× по умолчанию, как в project.godot (%d)" % Settings.msaa)
	check(Settings.screen_aa, "1: экранное сглаживание включено")
	check(Settings.ssao and Settings.ssil and Settings.fog and Settings.glow, "1: пост-эффекты по умолчанию включены")
	check(Settings.shadow_preset == 2 and Settings.shadow_enabled(), "1: тени 260 м по умолчанию")
	check(is_equal_approx(Settings.shadow_distance(), 260.0), "1: дистанция теней 260 м")
	check(Settings.show_fps, "1: счётчик кадров по умолчанию включён")
	check(Settings.vsync == Settings.VSync.ON, "1: вертикальная синхронизация включена")

func _persist() -> void:
	Settings.set_value("ssao", false)
	Settings.set_value("shadow_preset", 0)
	Settings.load_values()
	check(not Settings.ssao, "2: выключенная SSAO читается с диска")
	check(not Settings.shadow_enabled(), "2: тени выключены с диска")
	Settings.reset()
	Settings.load_values()
	check(Settings.ssao and Settings.shadow_enabled(), "2: сброс возвращает значения по умолчанию")
	check(Engine.max_fps == 0, "2: без потолка кадров Engine.max_fps = 0 (%d)" % Engine.max_fps)
	Settings.set_value("fps_limit", 60)
	check(Engine.max_fps == 60, "2: потолок кадров применяется сразу (%d)" % Engine.max_fps)
	Settings.set_value("fps_limit", 0)

func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _rebind() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	InputRouter.rebind("handbrake", k)
	var after := InputMap.action_get_events("handbrake")
	var keys := 0
	var joys := 0
	for e in after:
		if e is InputEventKey: keys += 1
		else: joys += 1
	# у ручника по одному событию на класс: после замены клавиши клавиатурное одно
	# и геймпадное осталось нетронутым
	check(keys == 1 and joys == 1, "3: заменена только клавиатура, геймпад цел (%d+ %d)" % [keys, joys])
	# action_press forcemently поднимает действие независимо от раскладки, поэтому
	# привязку проверяем настоящими событиями
	# состояние действий Godot применяет в конце кадра, поэтому после каждого события
	# нужен кадр ожидания: иначе проверка читает прошлое состояние
	_key(KEY_SPACE, true)
	await get_tree().process_frame
	check(not Input.is_action_pressed("handbrake"), "3: старый пробел больше не ручник")
	_key(KEY_SPACE, false)
	_key(KEY_F, true)
	await get_tree().process_frame
	check(Input.is_action_pressed("handbrake"), "3: новая клавиша — ручник")
	_key(KEY_F, false)
	await get_tree().process_frame
	check("F" in InputRouter.describe("handbrake"), "3: описание показывает новую клавишу (%s)" % InputRouter.describe("handbrake"))
	InputRouter.reset_keys()
	Settings.load_values()

func _codec() -> void:
	var b := InputEventJoypadButton.new(); b.button_index = 7
	var m := InputEventJoypadMotion.new(); m.axis = 5; m.axis_value = 0.5
	# 7 = START: заведомо не дефолтная кнопка respawn, иначе тест проходил бы сам собой
	b.button_index = 7
	InputRouter.rebind("respawn", b)
	InputRouter.rebind("slowmo", m)
	var cf := ConfigFile.new()
	InputRouter.save_keys(cf)
	InputRouter.reset_keys()
	InputRouter.load_keys(cf)
	var found_b := false
	var found_m := false
	for e in InputMap.action_get_events("respawn"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == 7: found_b = true
	for e in InputMap.action_get_events("slowmo"):
		if e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == 5 \
				and absf((e as InputEventJoypadMotion).axis_value - 0.5) < 0.01: found_m = true
	check(found_b, "4: кнопка геймпада пережила перезапись")
	check(found_m, "4: ось геймпада пережила перезапись с направлением")
	check(InputRouter.describe("slowmo").length() > 1, "4: ось описана (%s)" % InputRouter.describe("slowmo"))
	Settings.reset()

func _build_menu() -> void:   # вызывается из _ready, поэтому await здесь не нужен
	menu = SettingsMenu.new()
	add_child(menu)
	menu.open()
	check(menu.is_open(), "5: экран открывается")
	var caps := 0
	var opts := 0
	var checks := 0
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == "НАЗНАЧИТЬ": caps += 1
		if n.get_class() == "OptionButton": opts += 1
		if n.get_class() == "CheckBox": checks += 1
		for c in n.get_children(): stack.append(c)
	check(caps == InputRouter.DEFAULTS.size(), "5: по кнопке назначения на каждое действие (%d)" % caps)
	check(opts == 4 and checks == 6, "5: картинки настроек: 4 списка и 6 переключателей (%d/%d)" % [opts, checks])
	menu._begin_capture("cam_cycle")
	check(menu.capturing(), "5: режим захвата включён")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = true
	menu._unhandled_input(ev)
	check(not menu.capturing(), "5: захват завершился по нажатию")
	check("G" in InputRouter.describe("cam_cycle"), "5: назначение записано (%s)" % InputRouter.describe("cam_cycle"))
	# Esc во время захвата отменяет его, но не закрывает экран
	menu._begin_capture("cam_cycle")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	check(not menu.capturing() and menu.is_open(), "5: Esc во время захвата отменяет захват, но не экран")
	menu._end_capture()
	InputRouter.reset_keys()
	Settings.reset()
	_finish()

func _finish() -> void:
	if _had_file:
		var f := FileAccess.open(_path, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(OS.get_user_data_dir() + "/settings.cfg")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
