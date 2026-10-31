extends Node3D
# Настройки и переопределение клавиш.
# 1) дефолты — те, что выбраны по замерам на слабом GPU
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
	await _presets()
	await _extended()

# Пресеты и то, что ручной сдвиг сбрасывает отметку «в СРЕДНЕМ».
func _presets() -> void:
	check(Settings.preset == 1, "P: по умолчанию активен пресет СРЕДНЕЕ (%d)" % Settings.preset)
	Settings.apply_preset(3)
	check(Settings.shadow_preset == 3 and Settings.ssao and is_equal_approx(Settings.glow_bloom, 0.35),
		"P: КИНО включает дальние тени, SSAO и bloom (%d/%s/%.2f)" % [
			Settings.shadow_preset, str(Settings.ssao), Settings.glow_bloom])
	check(Settings.preset_name() == "КИНО", "P: имя пресета читается (%s)" % Settings.preset_name())
	Settings.set_value("exposure", 1.9)
	check(Settings.preset == Settings.PRESET_CUSTOM and Settings.preset_name() == "СВОЁ",
		"P: ручная правка снимает отметку пресета (%d)" % Settings.preset)
	Settings.apply_preset(1)
	check(is_equal_approx(Settings.exposure, 1.0) and Settings.preset == 1,
		"P: возврат в СРЕДНЕЕ чинит ползунок обратно (%.2f)" % Settings.exposure)
	Settings.load_values()
	check(Settings.preset == 1 and is_equal_approx(Settings.glow_bloom, 0.0),
		"P: пресет и его значения доживают до перезагрузки (%d)" % Settings.preset)
	Settings.reset()

# Расширенный режим: пункты обязаны не только существовать, но и доходить до сцены.
func _extended() -> void:
	Settings.tier_extended = false
	menu.refresh()
	var hidden := _tier_rows(1, false)
	check(hidden > 10, "E: в базовом режиме %d расширенных строк скрыто" % hidden)
	Settings.tier_extended = true
	menu.refresh()
	var shown := _tier_rows(1, true)
	check(shown == hidden, "E: расширенный режим показывает те же %d строк" % shown)
	check(is_equal_approx(Settings.ambient_energy(), Settings.ambient_base() * Settings.ambient),
		"E: яркость рассеянного света = база движка × множитель (%.2f)" % Settings.ambient_energy())
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	Settings.set_value("fov", 92.0)
	Settings.set_value("shake", 0.0)
	Settings.set_value("exposure", 1.4)
	Settings.set_value("tonemap", 1)
	Settings.set_value("sun_soft", 1.3)
	Settings.set_value("fog_aerial", 0.9)
	Settings.set_value("ssao_radius", 2.5)
	Settings.set_value("slowmo", 0.5)
	await get_tree().physics_frame
	check(is_equal_approx(g.camera.fov, 92.0), "E: поле зрения доходит до камеры (%.1f)" % g.camera.fov)
	check(is_equal_approx(g._env.tonemap_exposure, 1.4), "E: экспозиция доходит до окружения (%.2f)" % g._env.tonemap_exposure)
	check(g._env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "E: тонмаппинг переключается (%d)" % g._env.tonemap_mode)
	check(is_equal_approx(g._sun.light_angular_distance, 1.3), "E: мягкость теней доходит до солнца (%.2f)" % g._sun.light_angular_distance)
	check(is_equal_approx(g._env.fog_aerial_perspective, 0.9), "E: воздушная перспектива применяется (%.2f)" % g._env.fog_aerial_perspective)
	check(is_equal_approx(g._env.ssao_radius, 2.5), "E: радиус SSAO применяется (%.2f)" % g._env.ssao_radius)
	TimeScale.set_hold(true)
	check(is_equal_approx(Engine.time_scale, 0.5), "E: фактор слоу-мо берётся из настройки (%.2f)" % Engine.time_scale)
	TimeScale.set_hold(false)
	check(is_equal_approx(Engine.time_scale, 1.0), "E: отпускание возвращает время в норму")
	g.queue_free()
	await get_tree().process_frame
	Settings.reset()

func _tier_rows(tier: int, visible: bool) -> int:
	var n := 0
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Control and (c as Control).has_meta("tier") and int((c as Control).get_meta("tier")) == tier:
			if (c as Control).visible == visible: n += 1
		for k in c.get_children(): stack.append(k)
	return n

func _defaults() -> void:
	# Дефолт выбран по замерам на Intel HD 630: полный кадр с тенями, свечением и
	# дымкой стоит 21 мс, а вертикалка 60 Гц принимает 16.7 — не влезший кадр уходит
	# в 33.3 мс, то есть ровно в те 30 fps, на которые жалуется игрок.
	check(Settings.msaa == Settings.Msaa.X2, "1: MSAA 2× по умолчанию (%d)" % Settings.msaa)
	check(not Settings.screen_aa, "1: экранное сглаживание выключено по умолчанию")
	check(is_equal_approx(Settings.scale, 0.7), "1: внутренний масштаб 0.7 по умолчанию (%.2f)" % Settings.scale)
	check(Settings.fog and Settings.glow, "1: дымка и свечение включены")
	check(not Settings.ssao and not Settings.ssil, "1: экранные эффекты по умолчанию выключены")
	check(Settings.shadow_preset == 1 and Settings.shadow_enabled(), "1: короткие тени по умолчанию")
	check(is_equal_approx(Settings.shadow_distance(), 120.0), "1: дистанция теней 120 м")
	check(Settings.show_fps, "1: счётчик кадров по умолчанию включён")
	check(Settings.vsync == Settings.VSync.ON, "1: вертикальная синхронизация включена")

func _persist() -> void:
	Settings.set_value("scale", 1.0)
	Settings.set_value("fog", false)
	Settings.set_value("shadow_preset", 0)
	Settings.load_values()
	check(is_equal_approx(Settings.scale, 1.0), "2: масштаб доживает до перезагрузки (%.2f)" % Settings.scale)
	check(not Settings.fog, "2: выключенная дымка читается с диска")
	check(not Settings.shadow_enabled(), "2: тени выключены с диска")
	Settings.reset()
	Settings.load_values()
	check(Settings.fog and Settings.glow and Settings.shadow_enabled(), "2: сброс возвращает значения по умолчанию")
	check(is_equal_approx(get_window().scaling_3d_scale, 0.7),
		"2: масштаб применяется к окну (%.2f)" % get_window().scaling_3d_scale)
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
	var b1 := InputEventJoypadButton.new()
	b1.button_index = 1
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	InputRouter.rebind("handbrake", k)
	var after := InputMap.action_get_events("handbrake")
	var keys := 0
	var joys := 0
	for e in after:
		if e is InputEventKey: keys += 1
		else: joys += 1
	# у ручника на геймпаде два штатных назначения (крестик и L1), а клавиатурное —
	# одно; после замены клавиши геймпад не должен ни потерять их, ни прибавить
	var want_joy := InputRouter.DEFAULTS["handbrake"].joy.size()
	check(keys == 1 and joys == want_joy,
		"3: заменена только клавиатура, геймпад цел (%d+%d, ждали 1+%d)" % [keys, joys, want_joy])
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
	# назначаем ТЕПЕРЬ ещё и кнопку: класс клавиш при этом не должен вернуться к пробелу
	InputRouter.rebind("handbrake", b1)
	var n := InputMap.action_get_events("handbrake").size()
	check(n == 2, "3: два назначения — по одному на устройство (%d)" % n)
	_key(KEY_SPACE, true)
	await get_tree().process_frame
	check(not Input.is_action_pressed("handbrake"), "3: пробел не воскрес после назначения кнопки")
	_key(KEY_SPACE, false)
	await get_tree().process_frame
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
	# количество пунктов экрана берём из тех же таблиц и тех же проверок поддержки, что
	# и сам экран: иначе тест проверял бы число, а не правило «не показывать лишнее»
	var want_opts := SettingsMenu.OPTIONS.size()
	var want_checks := 0
	for c in SettingsMenu.CHECKS:
		if SettingsMenu._supported(c[0]): want_checks += 1
	# +1 переключатель: сам режим (базовый/расширенный) тоже CheckBox, но он не
	# настройка картинки, а способ их показать
	check(opts == want_opts and checks == want_checks + 1,
		"5: картинки настроек: %d списка и %d+1 переключателя (%d/%d)" % [want_opts, want_checks, opts, checks])
	menu._begin_capture("cam_cycle")
	check(menu.capturing(), "5: режим захвата включён")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = true
	menu._input(ev)   # захват перехватывает событие до GUI
	check(not menu.capturing(), "5: захват завершился по нажатию")
	check("G" in InputRouter.describe("cam_cycle"), "5: назначение записано (%s)" % InputRouter.describe("cam_cycle"))
	# Esc во время захвата отменяет его, но не закрывает экран
	menu._begin_capture("cam_cycle")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._input(esc)
	check(not menu.capturing() and menu.is_open(), "5: Esc во время захвата отменяет захват, но не экран")
	menu._end_capture()
	# вне захвата Esc закрывает экран, и его обрабатывает уже _unhandled_input
	var esc2 := InputEventKey.new()
	esc2.physical_keycode = KEY_ESCAPE
	esc2.pressed = true
	menu._unhandled_input(esc2)
	check(not menu.is_open(), "5: Esc вне захвата закрывает экран")
	menu.close()
	_apply_in_game()
	InputRouter.reset_keys()
	Settings.reset()
	_finish()

# Настройки обязаны долетать до живой сцены, а не только до файла: иначе экран
# настроек — декорация.
func _apply_in_game() -> void:
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	check(g._env.fog_enabled and g._env.glow_enabled, "по умолчанию дымка и свечение включены")
	check(not g._env.ssao_enabled and not g._env.ssil_enabled, "по умолчанию экранные эффекты выключены")
	check(g._sun.shadow_enabled and is_equal_approx(g._sun.directional_shadow_max_distance, 120.0),
		"по умолчанию тени 120 м")
	check(is_equal_approx(g._env.sky.sky_material.energy_multiplier, 1.0),
		"небо не компенсируется наживую: при включённых дымке и свечении Compatibility и Forward+ " +
		"рисуют его одинаково (замеры в h_t27_light)")
	Settings.set_value("ssao", true)
	Settings.set_value("glow", true)
	await get_tree().physics_frame
	check(g._env.ssao_enabled, "SSAO включается на лету")
	Settings.set_value("ssao", false)
	Settings.set_value("fog", false)
	Settings.set_value("glow", false)
	Settings.set_value("shadow_preset", 0)
	await get_tree().physics_frame
	check(not g._env.ssao_enabled and not g._env.ssil_enabled and not g._env.fog_enabled and not g._env.glow_enabled,
		"пост-эффекты выключаются на лету")
	check(not g._sun.shadow_enabled, "тени выключаются на лету")
	Settings.set_value("shadow_preset", 3)
	await get_tree().physics_frame
	check(g._sun.shadow_enabled and is_equal_approx(g._sun.directional_shadow_max_distance, 420.0),
		"дистанция теней меняется (%.0f)" % g._sun.directional_shadow_max_distance)
	Settings.set_value("scale", 1.0)
	await get_tree().physics_frame
	check(is_equal_approx(g.get_window().scaling_3d_scale, 1.0),
		"масштаб доходит до окна (%.2f)" % g.get_window().scaling_3d_scale)
	check(g.hud._fps_label.visible, "счётчик кадров виден по умолчанию")
	Settings.set_value("show_fps", false)
	await get_tree().physics_frame
	check(not g.hud._fps_label.visible, "счётчик кадров скрывается настройкой")
	g.queue_free()
	Settings.reset()
	await get_tree().process_frame

func _finish() -> void:
	if _had_file:
		var f := FileAccess.open(_path, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(OS.get_user_data_dir() + "/settings.cfg")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
