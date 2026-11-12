class_name I18n
extends RefCounted
# Локализация интерфейса. Ключом служит сама русская строка: русский текст остаётся
# в коде читаемым и является фолбэком, а каталог хранит только английский вариант.
# Переключение живое: bind() регистрирует надпись, и set_locale() перерисовывает все
# живые узлы без пересборки экранов; освобождённые узлы из реестра выпадают сами.
#
# Строки разработчика (push_warning, print) не переводятся: их читает агент и
# журнал, а не игрок.

static var locale := "ru"

# [узел, ключ, аргументы формата]; для OptionButton — [узел, массив ключей, выбор]
static var _bindings: Array = []

const EN := {
	"%.1f м/с²": "%.1f m/s²",
	"%.2f / %.2f с · ×%.2f · %s · вмятин %d": "%.2f / %.2f s · ×%.2f · %s · dents %d",
	"%02d:%02d   %3d км/ч": "%02d:%02d   %3d km/h",
	"%3d FPS · %.1f мс": "%3d FPS · %.1f ms",
	"%d кг": "%d kg",
	"%d км/ч": "%d km/h",
	"%s за кадр": "%s per frame",
	"6.7 мс за кадр": "6.7 ms per frame",
	"13.7 мс за кадр": "13.7 ms per frame",
	"29.2 мс за кадр": "29.2 ms per frame",
	"29.4 мс за кадр": "29.4 ms per frame",
	"0.00 / 0.00 с": "0.00 / 0.00 s",
	"600 метров разгона и бетонная стена на финише.\nДля максимального лобового краш-теста.":
		"600 metres of run-up and a concrete wall at the finish.\nFor the hardest head-on crash test.",
	"B · СИНИЙ": "B · BLUE",
	"G · ЗЕЛЁНЫЙ": "G · GREEN",
	"R · КРАСНЫЙ": "R · RED",
	"SSAO/SSIL, MSAA 4×, тени 260 м": "SSAO/SSIL, MSAA 4×, shadows 260 m",
	"SSAO: РАДИУС, М": "SSAO: RADIUS, M",
	"SSAO: СИЛА": "SSAO: STRENGTH",
	"v.%s · МОДЕЛИ: KENNEY CAR KIT 3.1 · CC0": "v.%s · MODELS: KENNEY CAR KIT 3.1 · CC0",
	"АДАПТИВНАЯ": "ADAPTIVE",
	"АРЕНА": "ARENA",
	"АТМОСФЕРА": "ATMOSPHERE",
	"БАК НИТРО": "NITRO TANK",
	"БЕЗ HUD": "NO HUD",
	"БЕЗ ПОТОЛКА": "NO LIMIT",
	"БЕСКОНЕЧНОСТЬ": "ENDLESS",
	"ПУСТОТА": "VOID",
	"Бесконечное полотно во все стороны — ровная плоскость без стен и объектов.":
		"An endless canvas in every direction — a flat plane with no walls or objects.",
	"БОЛЬШОЙ ГОРОД": "BIG CITY",
	"БЫСТРЕЕ": "FASTER",
	"В ГЛАВНОЕ МЕНЮ": "MAIN MENU",
	"В РЕЖИМЕ ОЖИДАНИЯ": "IDLE",
	"ВЕРТИКАЛЬНАЯ СИНХРОНИЗАЦИЯ": "VERTICAL SYNC",
	"ВИБРАЦИЯ ГЕЙМПАДА": "GAMEPAD VIBRATION",
	"ВКЛ": "ON",
	"ВМЯТИНЫ": "DENTS",
	"ВЫЙТИ": "QUIT",
	"ВЫКЛ": "OFF",
	"ВЫСОКОЕ": "HIGH",
	"ВЫХОД": "EXIT",
	"Восстановлена сохранённая конфигурация": "Saved configuration restored",
	"Выйти из Car Crash Simulator?": "Quit Car Crash Simulator?",
	"ГАЗ": "THROTTLE",
	"ГАРАЖ · %s": "GARAGE · %s",
	"ГАРАЖ": "GARAGE",
	"ГЕЙМПАД": "GAMEPAD",
	"ГОНКА": "RACE",
	"ГОРОДОК": "TOWN",
	"ГРАФИКА": "GRAPHICS",
	"Геймпад не подключён: вибрация заработает сама, когда контроллер появится в системе":
		"No gamepad connected: vibration starts by itself once a controller appears in the system",
	"ДАЛЬНИЕ 420 М": "FAR 420 M",
	"ДЕЙСТВИЕ": "ACTION",
	"ДЕМПФИРОВАНИЕ · ОТБОЙ": "DAMPING · REBOUND",
	"ДЕМПФИРОВАНИЕ · СЖАТИЕ": "DAMPING · COMPRESSION",
	"ДЫМКА И ТУМАН": "HAZE AND FOG",
	"ДЫМКА: ВОЗДУШНАЯ ПЕРСПЕКТИВА": "HAZE: AERIAL PERSPECTIVE",
	"ДЫМКА: ПЛОТНОСТЬ ×1000": "HAZE: DENSITY ×1000",
	"Движок: %s · не поддерживается: %s": "Engine: %s · unsupported: %s",
	"Дорога без конца: плиты за спиной переставляются вперёд,\nтак что хватает только терпения, а не длины карты.":
		"A road without an end: tiles behind you are moved ahead,\nso all you need is patience, not map length.",
	"ЖЁСТКОСТЬ ПОДВЕСКИ": "SUSPENSION STIFFNESS",
	"ЖУРНАЛ УДАРОВ": "IMPACT LOG",
	"ЗАВОДСКИЕ": "FACTORY",
	"ЗАКРЫТЬ": "CLOSE",
	"ЗАПУСТИТЬ ЗАНОВО": "RESTART RUN",
	"ЗАПУСТИТЬ СИМУЛЯЦИЮ": "START SIMULATION",
	"ЗВУК ВКЛЮЧЁН": "SOUND ON",
	"ЗВУК И ВИБРАЦИЯ": "SOUND AND VIBRATION",
	"ЗВУК": "SOUND",
	"Заводские настройки в черновике · нажми СОХРАНИТЬ": "Factory settings in draft · press SAVE",
	"ИДЁТ": "RUNNING",
	"Испытательный полигон: стены, столбы, отбойники,\nлежачий полицейский, слалом и краш-блок.":
		"Test range: walls, posts, barriers,\n speed bump, slalom and crash block.",
	"КАМЕРА И ВРЕМЯ": "CAMERA AND TIME",
	"КАМЕРА": "CAMERA",
	"КАРТА": "MAP",
	"КАРТЫ": "MAPS",
	"КАЧЕСТВО КАРТИНКИ": "IMAGE QUALITY",
	"КАЧЕСТВО": "QUALITY",
	"КИНО (ACES)": "FILM (ACES)",
	"КИНО": "FILM",
	"КЛАВИАТУРА": "KEYBOARD",
	"КМ/Ч": "KM/H",
	"КОРОТКИЕ 120 М": "SHORT 120 M",
	"КУЗОВ": "BODY",
	"Кварталы зданий, деревья, фонари, припаркованные\nмашины. Узкие улицы — боковые удары и рикошеты.":
		"Blocks of buildings, trees, lamps, parked\ncars. Narrow streets — side impacts and ricochets.",
	"Километр на километр: периметр, сетка улиц и районы —\nцентр, жилые кварталы, промзона, парк и стадион. Трамплин на бульваре.":
		"A kilometre by a kilometre: perimeter, street grid and districts —\ndowntown, residential, industrial, park and stadium. Ramp on the boulevard.",
	"Клавиатура и геймпад назначаются раздельно: кнопка геймпада не съест клавишу, и наоборот. Нажмите клетку и клавишу/кнопку — назначение впишется в свой столбец.":
		"Keyboard and gamepad are bound separately: a pad button will not eat a key, and vice versa. Press a cell and a key/button — the binding lands in its own column.",
	"Клавиша уже есть у «%s» — назначена всё равно": "Key already used by “%s” — bound anyway",
	"Кольцо почти в километр: длинная прямая с трамплином, четыре\nповорота, трибуны, боксы и отбойники по всему периметру.":
		"Almost a kilometre of loop: a long straight with a ramp, four\nturns, stands, pits and barriers all around.",
	"ЛИМУЗИН": "LIMOUSINE",
	"ЛУЧШИЙ УДАР": "BEST IMPACT",
	"МАССА": "MASS",
	"МАСШТАБ КАРТИНКИ": "RENDER SCALE",
	"МАШИНА": "CAR",
	"МАШИНЫ": "CARS",
	"МЕДЛЕННЕЕ": "SLOWER",
	"МЕТАЛЛИЧНОСТЬ КУЗОВА": "BODY METALLIC",
	"МСАА": "MSAA",
	"МЯГКОСТЬ СОЛНЕЧНЫХ ТЕНЕЙ, °": "SUN SHADOW SOFTNESS, °",
	"Машина бесконечности · без потолка скорости · 900 кг\nРазгон вчетверо сильнее спорткара: держаться за дорогу сможет не всегда.":
		"Endless car · no speed cap · 900 kg\nFour times the sportscar's acceleration: it will not always hold the road.",
	"Машину и карту меняй в разделах слева · Enter — запуск": "Change car and map in the sections on the left · Enter starts",
	"НАЖМИ КЛАВИШУ…": "PRESS A KEY…",
	"НАСТРОЙКИ": "SETTINGS",
	"НАЧАТЬ": "START",
	"НЕЙТРАЛЬНЫЙ": "NEUTRAL",
	"НЕПРЯМОЙ СВЕТ (SSIL)": "INDIRECT LIGHT (SSIL)",
	"НЕТ": "NO",
	"НИЗКОЕ": "LOW",
	"НИТРО (форсаж)": "NITRO (boost)",
	"НИТРО": "NITRO",
	"Нажмите клавишу или кнопку для «%s» · ESC отменяет": "Press a key or button for “%s” · ESC cancels",
	"ОБЩАЯ ГРОМКОСТЬ": "MASTER VOLUME",
	"ОКНО И КАДР": "WINDOW AND FRAME",
	"ОСТАТЬСЯ": "STAY",
	"ОТЛАДОЧНЫЙ ОВЕРЛЕЙ (F2/F3)": "DEBUG OVERLAY (F2/F3)",
	"ОТМЕНА": "CANCEL",
	"Одна сохранённая конфигурация для каждой машины": "One saved configuration per car",
	"Окно держит редактор: полноэкранный режим и размер действуют на отдельное окно игры":
		"The editor owns the window: fullscreen and size apply to the standalone game window",
	"ПАУЗА": "PAUSE",
	"ПАУЗА/ПУСК": "PAUSE/RESUME",
	"ПИК ПЕРЕГРУЗКИ": "PEAK G-FORCE",
	"ПИКАП": "PICKUP",
	"ПОЛЕ ЗРЕНИЯ КАМЕРЫ, °": "CAMERA FIELD OF VIEW, °",
	"ПОЛНОЭКРАННЫЙ РЕЖИМ": "FULLSCREEN",
	"ПОТОЛОК КАДРОВ": "FRAME CAP",
	"ПРОДОЛЖИТЬ": "RESUME",
	"РАБОЧИЙ ТОРМОЗ · м/с²": "SERVICE BRAKE · m/s²",
	"РАЗГОН": "ACCELERATION",
	"РАССЕЯНИЕ СОЛНЕЧНОГО СВЕТА": "SUN LIGHT SCATTERING",
	"РАССЕЯННЫЙ СВЕТ ×": "AMBIENT LIGHT ×",
	"РАСШИРЕННЫЙ РЕЖИМ — ВСЯ ГРАФИКА ПО ПУНКТАМ": "ADVANCED MODE — EVERY GRAPHICS OPTION",
	"РЕПЛЕЙ УДАРА": "IMPACT REPLAY",
	"РЕПЛЕЙ": "REPLAY",
	"РЕСТАРТ": "RESTART",
	"РУЛЬ влево": "STEER left",
	"РУЛЬ вправо": "STEER right",
	"РУЧНИК": "HANDBRAKE",
	"Размер игрового поля в панели редактора задаёт её меню: Фиксированный / Пропорции / Растянуть":
		"The editor panel's game area size sets its menu: Fixed / Aspect / Stretch",
	"Растянутый седан · 175 км/ч · 2100 кг\nСамый длинный и самый тяжёлый: разгон и тормоз честные, а не спортивные.":
		"Stretched sedan · 175 km/h · 2100 kg\nThe longest and the heaviest: honest, not sporty, acceleration and brakes.",
	"СБРОС ВИДА": "RESET VIEW",
	"СБРОС": "RESET",
	"СБРОСИТЬ ВСЁ": "RESET ALL",
	"СВЕТ И ТЕНИ": "LIGHT AND SHADOWS",
	"СВЕЧЕНИЕ ЯРКОГО": "BLOOM",
	"СВЕЧЕНИЕ: BLOOM": "GLOW: BLOOM",
	"СВЕЧЕНИЕ: ЯРКОСТЬ": "GLOW: INTENSITY",
	"СВОЁ — хотя бы одно значение изменено вручную. Карточка вернёт пресет целиком.":
		"CUSTOM — at least one value changed by hand. The card restores the whole preset.",
	"СВОЁ": "CUSTOM",
	"СЕДАН": "SEDAN",
	"СИЛА ВИБРАЦИИ": "VIBRATION STRENGTH",
	"СКОРОСТЬ": "SPEED",
	"СЛЕД НА АСФАЛЬТЕ": "MARKS ON ASPHALT",
	"СЛЕД РЕЗИНЫ ЖИВЁТ, С": "TIRE MARK LIFETIME, S",
	"СЛОУ-МО": "SLOW-MO",
	"СЛОУ-МО: ФАКТОР ВРЕМЕНИ": "SLOW-MO: TIME FACTOR",
	"СМЕНА КАМЕРЫ": "CYCLE CAMERA",
	"СНИМОК": "SHOT",
	"СОХРАНИТЬ": "SAVE",
	"СПОРТКАР": "SPORTSCAR",
	"СРЕДНЕЕ": "MEDIUM",
	"СРЕДНИЕ 260 М": "MEDIUM 260 M",
	"СТОП": "STOP",
	"СЦЕПЛЕНИЕ ШИН": "TIRE GRIP",
	"СЦЕПЛЕНИЕ": "GRIP",
	"СЧЁТЧИК КАДРОВ НА ЭКРАНЕ": "ON-SCREEN FPS COUNTER",
	"Сбалансированный седан · 160 км/ч · 1300 кг\nСредняя жёсткость кузова — честная классика краш-тестов.":
		"Balanced sedan · 160 km/h · 1300 kg\nMedium body stiffness — the honest crash-test classic.",
	"Сохранено · применяется в следующем заезде и при рестарте": "Saved · applies next run and on restart",
	"ТЕЛЕМЕТРИЯ": "TELEMETRY",
	"ТЕНИ": "SHADOWS",
	"ТЕНЬ КОНТАКТА (SSAO)": "CONTACT SHADOW (SSAO)",
	"ТОНМАППИНГ": "TONEMAPPING",
	"ТОРМОЗ / задний ход": "BRAKE / reverse",
	"ТОЧКА БЕЛОГО": "WHITE POINT",
	"ТРАССА": "CIRCUIT",
	"ТРЯСКА КАМЕРЫ ×": "CAMERA SHAKE ×",
	"ТЯГА · м/с²": "THRUST · m/s²",
	"ТЯГА НИТРО · м/с²": "NITRO THRUST · m/s²",
	"Тяжёлый пикап · 140 км/ч · 1900 кг\nКузов держит удар, который ломает остальных.":
		"Heavy pickup · 140 km/h · 1900 kg\nThe body survives impacts that break the others.",
	"УДАРОВ %d · ЛУЧШИЙ %d КМ/Ч · %02d:%02d · %s / %s": "IMPACTS %d · BEST %d KM/H · %02d:%02d · %s / %s",
	"УДАРОВ: %d": "IMPACTS: %d",
	"УДАРОВ: 0": "IMPACTS: 0",
	"СТАТИСТИКА": "STATISTICS",
	"ЗАЕЗДОВ": "RUNS",
	"УДАРОВ": "IMPACTS",
	"МАКС. СКОРОСТЬ": "TOP SPEED",
	"ПРОЙДЕНО": "TRAVELED",
	"ВРЕМЯ В ЗАЕЗДАХ": "TIME IN RUNS",
	"СНИМКОВ": "SHOTS",
	"%d км": "%d km",
	"%d:%02d:%02d": "%d:%02d:%02d",
	"ГАЛЕРЕЯ": "GALLERY",
	"НЕТ СНИМКОВ": "NO SHOTS YET",
	"ОТКРЫТЬ ПАПКУ": "OPEN FOLDER",
	"УДАЛИТЬ": "DELETE",
	"ДОСТУПНОСТЬ": "ACCESSIBILITY",
	"МЕНЬШЕ ВСПЫШЕК (ИСКРЫ)": "FLASH REDUCTION (SPARKS)",
	"БОЛЬШОЙ ИНТЕРФЕЙС": "LARGER INTERFACE",
	"Ступень интерфейса применяется при построении экрана: в меню — сразу, в заезде — после возврата в меню":
		"The interface step applies when a screen is built: in the menu at once, in a run after returning to the menu",
	"УПРАВЛЕНИЕ": "CONTROLS",
	"ФИЛЬМ": "FILM",
	"ФОТОМОД · FOV %.0f° · снимков %d%s": "PHOTO MODE · FOV %.0f° · shots %d%s",
	"ФОТОМОД": "PHOTO MODE",
	"Хрупкий спорткар · 210 км/ч · 1050 кг\nБыстрый и низкий: мнётся глубоко и эффектно.":
		"Fragile sportscar · 210 km/h · 1050 kg\nFast and low: crumples deep and spectacularly.",
	"ЦВЕТ ОКРАШЕННЫХ ПАНЕЛЕЙ · RGB": "PAINTED PANEL COLOR · RGB",
	"ЧАСТИЦЫ (ДЫМ, ИСКРЫ, ПЫЛЬ)": "PARTICLES (SMOKE, SPARKS, DUST)",
	"Черновик · Сохрани для следующего заезда.\nУход из раздела отменяет несохранённые изменения.":
		"Draft · Save for the next run.\nLeaving the section discards unsaved changes.",
	"Черновик изменён · ещё не сохранён": "Draft changed · not saved yet",
	"ШАГ ▶": "STEP ▶",
	"ШЕРОХОВАТОСТЬ КУЗОВА": "BODY ROUGHNESS",
	"ЭКРАННОЕ СГЛАЖИВАНИЕ": "SCREEN-SPACE ANTI-ALIASING",
	"ЭКСПОЗИЦИЯ": "EXPOSURE",
	"ЭФФЕКТЫ": "EFFECTS",
	"без теней и пост-эффектов, 70%": "no shadows or post effects, 70%",
	"всё применяется сразу · файл настроек пишется после тишины": "everything applies at once · the settings file is written after a quiet moment",
	"удар #%d, топ %d км/ч": "impact #%d, top %d km/h",
	"рестарт: вмятин %d → %d": "restart: dents %d → %d",
	"кадр (интервал)  %.1f мс\n": "frame (interval) %.1f ms\n",
	"физика (шаг)     %.1f мс\n": "physics (step)   %.1f ms\n",
	"движок           %s\n": "engine           %s\n",
	"объектов в кадре %d\n": "objects in frame %d\n",
	"вызовов отрисовки %d\n": "draw calls       %d\n",
	"примитивов        %d\n": "primitives       %d\n",
	"видеопамять       %d МБ\n": "video memory     %d MB\n",
	"узлов %d · сирот %d\n": "nodes %d · orphans %d\n",
	"DEBUG · МАШИНА\nнет машины": "DEBUG · CAR\nno car",
	"скорость     %.0f км/ч\n": "speed        %.0f km/h\n",
	"руль         %.1f° из %.0f°\n": "steering     %.1f° of %.0f°\n",
	"занос        %.2f\n": "slip         %.2f\n",
	"боковое g    %.2f (пик %.2f)\n": "lateral g    %.2f (peak %.2f)\n",
	"педали       тормоз %.2f · ручник %.2f\n": "pedals       brake %.2f · hand %.2f\n",
	"колёса       %s (%s)\n": "wheels       %s (%s)\n",
	"на земле": "on ground",
	"в воздухе": "airborne",
	"курс         %.0f°\n": "heading      %.0f°\n",
	"DEBUG · МИР\nнет сцены": "DEBUG · WORLD\nno scene",
	"карта        %s%s\n": "map          %s%s\n",
	" (лента)": " (strip)",
	"узлов %d · тел %d · стат. %d\n": "nodes %d · bodies %d · stat %d\n",
	"мешей %d · за LOD %d\n": "meshes %d · past LOD %d\n",
	"ближ. тело   %s\n": "near body    %s\n",
	"%.1f м": "%.1f m",
	"нет": "none",
	"луч: %s\n": "ray: %s\n",
	"границы      x %.0f..%.0f z %.0f..%.0f\n": "bounds       x %.0f..%.0f z %.0f..%.0f\n",
	"спавн        %.0f, %.0f, %.0f\n": "spawn        %.0f, %.0f, %.0f\n",
	"пар физики   %d\n": "physics pairs %d\n",
	"DEBUG · ЖУРНАЛ\n": "DEBUG · LOG\n",
	"DEBUG · МАШИНА\n": "DEBUG · CAR\n",
	"DEBUG · МИР\n": "DEBUG · WORLD\n",
	"событий пока нет\n": "no events yet\n",
	"нет сцены": "no scene",
	"нет пространства": "no space",
	"чисто на %.0f м": "clear for %.0f m",
	"без тела": "no body",
	"%s · %s в %.1f м": "%s · %s at %.1f m",
	"форма?": "shape?",
	"Файл гаража из более новой версии игры": "Garage file from a newer game version",
	"Неизвестная машина": "Unknown car",
	"Не удалось записать гараж": "Could not write the garage",
	"Не удалось сохранить гараж; прежний файл сохранён": "Could not save the garage; the previous file is intact",
	"Не удалось прочитать гараж": "Could not read the garage",
	"Файл гаража слишком большой; используются заводские настройки": "Garage file is too large; factory settings are used",
	"Повреждённый файл гаража; используются заводские настройки": "Corrupted garage file; factory settings are used",
	"Неподдерживаемая версия файла гаража": "Unsupported garage file version",
	"выбор сразу подменяет машину в фоне": "picking swaps the background car immediately",
	"вылет за пределы — рестарт": "out of bounds — restart",
	"дымка и свечение, тени 120 м": "haze and glow, shadows 120 m",
	"заезд начат заново": "run restarted",
	"машина на крыше — R для рестарта": "car on its roof — R to restart",
	"мягкие тени 420 м, bloom, экспозиция 1.15": "soft shadows 420 m, bloom, exposure 1.15",
	"окно реплея пусто — разгонитесь и ударьтесь": "replay window is empty — get speed and crash",
	"рестарт": "restart",
	"сглаживание": "anti-aliasing",
	"6.7 мс": "6.7 ms",
	"13.7 мс": "13.7 ms",
	"29.2 мс": "29.2 ms",
	"29.4 мс": "29.4 ms",
	"КНОПКА %d": "BUTTON %d",
	"КУРОК L": "L TRIGGER",
	"КУРОК R": "R TRIGGER",
	"ОСЬ %d": "AXIS %d",
	"СТИК L →/←": "L STICK →/←",
	"СТИК L ↑/↓": "L STICK ↑/↓",
	"СТИК R →/←": "R STICK →/←",
	"СТИК R ↑/↓": "R STICK ↑/↓",
	"КАДР": "FRAME",
	"МИР": "WORLD",
	"ЖУРНАЛ": "LOG",
	"ОБЩЕЕ": "GENERAL",
	"ЗАГРУЗКА": "LOADING",
	"ГАДЖЕТ ОТКЛЮЧЁН": "GAMEPAD DISCONNECTED",
	"ГЕЙМПАД ПОДКЛЮЧЁН: ВИБРАЦИЯ И БИНДЫ АКТИВНЫ": "GAMEPAD CONNECTED: VIBRATION AND BINDINGS ARE LIVE",
	"СНИМОК НЕ ПОЛУЧИЛСЯ: НЕТ ЖИВОГО КАДРА": "SHOT FAILED: NO LIVE FRAME",
	"СНИМОК НЕ ПОЛУЧИЛСЯ: НЕТ ПРАВА ЗАПИСИ": "SHOT FAILED: NO WRITE ACCESS",
	"СНИМОК РЕПЛЕЯ: %s": "REPLAY SHOT: %s",
	"РЕПЛЕЙ СОХРАНЁН: %s": "REPLAY SAVED: %s",
	"РЕПЛЕЙ ПРОШЛОГО ЗАЕЗДА: кадров %d": "LAST RUN REPLAY: %d frames",
	"◀ ШАГ": "◀ STEP",
	"ЯЗЫК": "LANGUAGE",
	"Русский": "Russian",
	"English": "English",
}

static func t(key: String) -> String:
	if locale == "en":
		return EN.get(key, key)
	return key

static func fmt(key: String, args: Array) -> String:
	return t(key) % args

# Надпись с живым переключением: текст ставится сразу и переставляется при смене
# языка. Аргументы формата запоминаются, чтобы при переключении пересчитать строку.
static func bind(node: Node, key: String, args: Array = []) -> void:
	_apply(node, key, args)
	# Реестр чистится лениво: слабые ссылки мёртвых узлов копятся на каждой
	# пересборке разделов меню (а это десятки надписей за раз) и выкалываются
	# только на смене языка — длинная сессия в меню текла памятью.
	if _bindings.size() >= 256 and _bindings.size() % 64 == 0:
		var live: Array = []
		for b in _bindings:
			if b[0].get_ref() != null: live.append(b)
		_bindings = live
	_bindings.append([weakref(node), key, args])

# Производные длинного ключа: каталог хранит описание целиком (с переводом
# строки), а экран режет его на строки или склеивает в одну. Реестр хранит
# спецификацию, и set_locale пересчитывает производную надпись от перевода.
static func bind_line(node: Node, key: String, line: int) -> void:
	node.set("text", _line_of(key, line))
	_bindings.append([weakref(node), key, { "line": line }])

static func bind_flat(node: Node, key: String) -> void:
	node.set("text", _flat(key))
	_bindings.append([weakref(node), key, { "flat": true }])

static func _line_of(key: String, line: int) -> String:
	var parts := t(key).split("\n")
	return parts[clampi(line, 0, parts.size() - 1)]

static func _flat(key: String) -> String:
	return t(key).replace("\n", " ")

static func bind_options(ob: OptionButton, keys: Array) -> void:
	var sel := ob.selected
	_fill_options(ob, keys)
	ob.select(sel)
	_bindings.append([weakref(ob), keys, sel, true])

static func _fill_options(ob: OptionButton, keys: Array) -> void:
	ob.clear()
	for k in keys:
		ob.add_item(t(String(k)))

static func _apply(node: Node, key: String, args: Array) -> void:
	var s := t(key)
	if not args.is_empty():
		s = s % args
	node.set("text", s)

static func set_locale(l: String) -> void:
	locale = l
	var live: Array = []
	for b in _bindings:
		var node: Node = b[0].get_ref()
		if not is_instance_valid(node):
			continue
		if b.size() == 4:
			var ob := node as OptionButton
			var sel: int = ob.selected
			_fill_options(ob, b[1])
			ob.select(sel)
			b[2] = sel
		else:
			var spec: Variant = b[2]
			if spec is Dictionary and spec.has("line"):
				node.set("text", _line_of(b[1], int(spec["line"])))
			elif spec is Dictionary and spec.has("flat"):
				node.set("text", _flat(b[1]))
			else:
				_apply(node, b[1], spec)
		live.append(b)
	_bindings = live