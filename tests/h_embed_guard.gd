extends Node

# Контракт встроенного запуска: пока окном владеет редактор, игра не имеет права
# ни навязывать ему геометрию, ни запоминать его прямоугольник. Второй пункт —
# та же дыра, что раньше давала «серое окно»: снятый с панели редактора размер
# уезжает в cfg и на следующем отдельном старте становится размером окна игрока.
# Запускать ОБЯЗАТЕЛЬНО с --wid <хендл окна-хоста> (см. tests/p_embed_host.tscn).

const SEEDED := Rect2i(100, 120, 1280, 720)

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): чужое окно без живого окна не бывает")
		print("ALL PASS")
		get_tree().quit(0)
		return
	if not Engine.is_embedded_in_editor():
		print("FAIL: тест запущен без --wid: окном владеет игра, проверять нечего")
		print("FAILS 1")
		get_tree().quit(1)
		return
	_seed(SEEDED)
	Settings.load_values()
	check(Settings._win_rect == SEEDED, "после загрузки помним сеяный прямоугольник (%s)" % str(Settings._win_rect))

	# Ждём дольше дебаунса записи (500 мс): за это время _capture_window на сломанном
	# коде успевает снять геометрию с панели и поставить save() в очередь.
	await get_tree().create_timer(1.2).timeout
	check(Settings._win_rect == SEEDED,
		"геометрия редактора не просочилась в память (%s вместо %s)" % [str(Settings._win_rect), str(SEEDED)])
	var on_disk := _read_window()
	check(on_disk == SEEDED,
		"cfg не перезаписан чужим окном (%s вместо %s)" % [str(on_disk), str(SEEDED)])
	# Проверка самого guard'а идёт последней: на сломанном коде сначала обязаны
	# громко упасть поведения, а не только вызов несуществующей функции.
	check(not Settings.owns_window(), "окно редакторское — guard обязан его узнавать")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _seed(r: Rect2i) -> void:
	Settings.save()
	var cf := ConfigFile.new()
	if cf.load(Settings.FILE) != OK:
		check(false, "cfg прочитан для досева [window]")
		return
	cf.set_value(Settings.WIN_SECTION, "x", r.position.x)
	cf.set_value(Settings.WIN_SECTION, "y", r.position.y)
	cf.set_value(Settings.WIN_SECTION, "w", r.size.x)
	cf.set_value(Settings.WIN_SECTION, "h", r.size.y)
	cf.set_value(Settings.WIN_SECTION, "max", false)
	if cf.save(Settings.FILE) != OK:
		check(false, "cfg записан с сеяной геометрией")

func _read_window() -> Rect2i:
	var cf := ConfigFile.new()
	if cf.load(Settings.FILE) != OK:
		return Rect2i(-1, -1, -1, -1)
	return Rect2i(int(cf.get_value(Settings.WIN_SECTION, "x", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "y", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "w", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "h", -1)))
