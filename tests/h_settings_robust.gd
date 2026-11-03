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
	await _corrupt_cfg()
	await _oversized_cfg()
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
		"exposure = \"nan\"\nshadow_preset = Vector2(1,1)\n[window]\nw = 0\nh = 0\nmax = [true]\n" +
		"[keys]\nthrottle = {}\nbrake = 42\nnitro = [65, 66]\npause = \"k0\"\n")
	Settings.load_values()
	check(Settings.preset == 0, "preset вне диапазона прижат к границе (%d)" % Settings.preset)
	check(Settings.preset_name() != "", "имя пресета читается (%s)" % Settings.preset_name())
	check(Settings.fov >= 60.0 and Settings.fov <= 120.0,
		"fov после мусора в пределах разумного (%.1f)" % Settings.fov)
	check(Settings.scale >= 0.5 and Settings.scale <= 1.0,
		"scale после мусора в пределах разумного (%.2f)" % Settings.scale)
	# NaN в файле отравил бы каждый последующий boot: строка «nan» не считается
	# числом, а clampf и так выкидывает не-конечное значение за границы.
	check(is_finite(Settings.exposure), "exposure остался конечным (%.2f)" % Settings.exposure)
	check(typeof(Settings.fog) == TYPE_BOOL, "bool-ключ остался bool (%s)" % typeof(Settings.fog))
	# бинды из битых строк не читаются, но и не теряются: действие остаётся по умолчанию
	var th := InputMap.action_get_events("throttle")
	check(th.size() > 0, "throttle остался с биндом после {} в файле (%d)" % th.size())
	var br := InputMap.action_get_events("brake")
	check(br.size() > 0, "brake остался с биндом после числа в файле (%d)" % br.size())
	# «pause = k0»: физический код 0 не нажимается. Если принять такой бинд, действие
	# останется без события, а пауза в заезде открывается только клавишей.
	var pz := InputMap.action_get_events("pause")
	check(pz.size() > 0, "pause не остался без бинда после k0 (%d)" % pz.size())
	var pz_ok := false
	for e in pz:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
			pz_ok = true
	check(pz_ok, "pause вернулся к ESC после k0")
	check(not Settings._win_ok(Rect2i(0, 0, 2000000000, 2000000000)),
		"абсурдный размер окна не проходит проверку")
	# Геометрия возврата окна на экран. Проверка синтетическая, а не через
	# DisplayServer: в headless экран читается как 0×0, и живой вызов ничего бы не
	# доказал, зато поймал бы собственную ошибку клампа.
	var one := Rect2i(0, 0, 1920, 1080)
	var win := Vector2i(1600, 900)
	check(Settings._clamp_pos(Vector2i(120, 80), win, one) == Vector2i(120, 80),
		"видимая позиция не двигается")
	var back := Settings._clamp_pos(Vector2i(-90000, -90000), win, one)
	check(back.x == -1440 and back.y == 0,
		"улетевшее влево-вверх окно возвращается с 160 px на экране (%s)" % str(back))
	var fwd := Settings._clamp_pos(Vector2i(5000, 5000), win, one)
	check(fwd.x == 1760 and fwd.y == 920,
		"улетевшее вправо-вниз окно возвращается (%s)" % str(fwd))
	# Второй монитор слева: отрицательные координаты — нормальное место, переносить
	# окно на основной экран при каждом старте нельзя.
	var left := Rect2i(-1920, 0, 3840, 1080)
	check(Settings._clamp_pos(Vector2i(-1900, 10), win, left) == Vector2i(-1900, 10),
		"окно на левом мониторе остаётся на левом мониторе")
	# Геометрия окна: ноль в файле — не размер, а мусор. Хуже того, в headless сам
	# движок отдаёт окно 0×0, и опрос окна в тестовом прогоне затирал настоящие
	# настройки игрока (в user://settings.cfg появлялось w=0 h=0).
	check(Settings._win_ok(Settings._win_rect),
		"нулевой размер из файла не попал в геометрию (%s)" % str(Settings._win_rect.size))
	# Принуждаем испорченную геометрию и требуем, чтобы save() её залатал: именно
	# такой ноль превращает окно в серое поле с тонкой полоской интерфейса.
	Settings._win_rect = Rect2i(0, 0, 0, 0)
	Settings.save()
	var cf := ConfigFile.new()
	check(cf.load(PATH_CFG) == OK, "файл настроек перечитывается после save")
	var saved_w := int(cf.get_value("window", "w", 0))
	var saved_h := int(cf.get_value("window", "h", 0))
	check(saved_w >= Settings.WIN_MIN.x and saved_h >= Settings.WIN_MIN.y,
		"в файл записан осмысленный размер окна (%dx%d)" % [saved_w, saved_h])
	Settings.reset()

func _corrupt_cfg() -> void:
	# Синтаксически битый файл (нераскрытый массив) — единственный случай, где игра
	# обязана сохранить копию: без неё следующий save молча стирает бинды и настройки.
	var bad := "user://settings.cfg.bad"
	if FileAccess.file_exists(bad): DirAccess.remove_absolute(bad)
	_write("[video]\nfog = [1, 2\n")
	Settings.load_values()
	check(FileAccess.file_exists(bad), "битый settings.cfg сохранён копией в .bad")
	if FileAccess.file_exists(bad): DirAccess.remove_absolute(bad)

func _oversized_cfg() -> void:
	# Парсер ConfigFile однопоточный: файл размером с лог остановил бы старт. Такой
	# файл — мусор, и читать его нельзя: копия в .bad и жизнь на текущих значениях.
	var junk := "[video]\n"
	while junk.length() < Settings.CFG_MAX_BYTES + 4096:
		junk += "filler_%d = 1\n" % junk.length()
	_write(junk)
	Settings.set_value("fov", 99.0, false)
	Settings.load_values()
	check(is_equal_approx(Settings.fov, 99.0),
		"переразмеренный файл не перечитывается (%.1f)" % Settings.fov)
	check(FileAccess.file_exists("user://settings.cfg.bad"), "переразмеренный файл отложен в .bad")
	if FileAccess.file_exists("user://settings.cfg.bad"):
		DirAccess.remove_absolute("user://settings.cfg.bad")
	# атомарная запись: временный файл не должен пережить save
	Settings.save()
	check(not FileAccess.file_exists("user://settings.cfg.part"),
		"после save не остался черновик .part")

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
