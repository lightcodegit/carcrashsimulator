extends Node
# Настройки игрока: картинка, камера, следы резины, раскладка клавиш.
#
# Файл лежит в user://, а не в репозитории: это состояние конкретного игрока, и в git
# ему делать нечего. Значения по умолчанию выбраны по замерам на самом слабом GPU,
# который нам достался (Intel HD 630), — см. SCALE_STEPS и пресет «СРЕДНЕЕ».
#
# Ключи перечислены в одном месте (values()), а диапазон и тип берутся из NUMS:
# добавить настройку — это добавить переменную, ключ и границу, а не ветку в match.

signal changed

const FILE := "user://settings.cfg"
const SECTION := "video"
const KEYS_SECTION := "keys"
# Геометрия окна — не «настройка картинки», а состояние игрока: живёт в своей секции
# того же файла, не участвует в сбросе пресета и не показывается в UI.
const WIN_SECTION := "window"

enum VSync { OFF, ON, ADAPTIVE }
enum Msaa { DISABLED = 0, X2 = 1, X4 = 2, X8 = 3 }

# тени: выкл / короткие / текущие / дальние.
const SHADOW_PRESETS := [
	["ВЫКЛ", 0, 0.0],
	["КОРОТКИЕ (120 м)", 1, 120.0],
	["СРЕДНИЕ (260 м)", 1, 260.0],
	["ДАЛЬНИЕ (420 м)", 1, 420.0],
]

# Внутренний масштаб 3D. Дефолт — 0.7, и это не лень, а арифметика: на Intel HD 630
# при 1600×900 полный кадр с тенями, свечением и дымкой стоит 21 мс, а вертикалка
# 60 Гц принимает 16.7 — не влезший кадр уходит в 33.3, то есть ровно в «30 fps».
# С 0.7 тот же набор эффектов стоит 14.8 мс. На дискретной GPU ставят 1.0.
const SCALE_STEPS := [0.7, 0.85, 1.0]
const SCALE_NAMES := ["70%", "85%", "100%"]

# Тонмаппинг: нейтральный ничего не делает, «фильм» (ACES) даёт киношное сжатие
# светов — именно он стоит по умолчанию.
const TONEMAPS := [["НЕЙТРАЛЬНЫЙ", Environment.TONE_MAPPER_LINEAR],
	["ФИЛЬМ", Environment.TONE_MAPPER_FILMIC], ["КИНО (ACES)", Environment.TONE_MAPPER_ACES]]

# Границы числовых ключей. Тип значения берётся из значения по умолчанию, поэтому
# int здесь остаётся int'ом, а float — float'ом.
const NUMS := {
	"vsync": [0, 2], "fps_limit": [0, 300], "shadow_preset": [0, 3], "msaa": [0, 3],
	"tonemap": [0, 2], "scale": [0.5, 1.0], "skid_life": [0.0, 600.0],
	"exposure": [0.4, 2.5], "tonemap_white": [1.0, 12.0],
	"glow_intensity": [0.0, 1.5], "glow_bloom": [0.0, 1.0],
	"fog_density": [0.0, 0.02], "fog_aerial": [0.0, 1.0], "fog_scatter": [0.0, 1.0],
	"ssao_radius": [0.2, 4.0], "ssao_intensity": [0.0, 4.0],
	"sun_soft": [0.0, 2.0], "ambient": [0.2, 3.0],
	"fov": [50.0, 100.0], "shake": [0.0, 2.0], "slowmo": [0.05, 1.0],
}

# Пресеты картинки. Их цена измерена на Intel HD 630 при 1600×900, холодным стартом
# (MSAA на лету буфер не пересобирает, горячий замер врёт): НИЗКОЕ 6.7 мс, СРЕДНЕЕ
# 13.7, ВЫСОКОЕ 29.4, КИНО 29.2. Бюджет вертикалки 60 Гц — 16.7 мс, то есть на этой
# машине в 60 fps влезают первые два; «ВЫСОКОЕ» и «КИНО» собраны для дискретной GPU.
# «КИНО» — это мягкие тени 420 м, воздушная перспектива на полную, bloom и экспозиция
# 1.15: картинка, ради которой и включают все пост-проходы.
const PRESETS := [
	["НИЗКОЕ", { "msaa": 0, "shadow_preset": 0, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "screen_aa": false, "scale": 0.7, "exposure": 1.0, "tonemap_white": 4.0,
		"glow_intensity": 0.45, "glow_bloom": 0.0, "fog_density": 0.0016, "fog_aerial": 0.5,
		"fog_scatter": 0.25, "ssao_radius": 1.2, "ssao_intensity": 1.4, "sun_soft": 0.55,
		"ambient": 1.0, "tonemap": 2 }],
	["СРЕДНЕЕ", { "msaa": 1, "shadow_preset": 1, "ssao": false, "ssil": false, "fog": true,
		"glow": true, "screen_aa": false, "scale": 0.7, "exposure": 1.0, "tonemap_white": 4.0,
		"glow_intensity": 0.45, "glow_bloom": 0.0, "fog_density": 0.0016, "fog_aerial": 0.5,
		"fog_scatter": 0.25, "ssao_radius": 1.2, "ssao_intensity": 1.4, "sun_soft": 0.55,
		"ambient": 1.0, "tonemap": 2 }],
	["ВЫСОКОЕ", { "msaa": 2, "shadow_preset": 2, "ssao": true, "ssil": true, "fog": true,
		"glow": true, "screen_aa": true, "scale": 1.0, "exposure": 1.0, "tonemap_white": 4.0,
		"glow_intensity": 0.45, "glow_bloom": 0.0, "fog_density": 0.0016, "fog_aerial": 0.5,
		"fog_scatter": 0.25, "ssao_radius": 1.2, "ssao_intensity": 1.4, "sun_soft": 0.55,
		"ambient": 1.0, "tonemap": 2 }],
	["КИНО", { "msaa": 2, "shadow_preset": 3, "ssao": true, "ssil": true, "fog": true,
		"glow": true, "screen_aa": true, "scale": 1.0, "exposure": 1.15, "tonemap_white": 6.0,
		"glow_intensity": 0.7, "glow_bloom": 0.35, "fog_density": 0.0022, "fog_aerial": 1.0,
		"fog_scatter": 0.55, "ssao_radius": 1.6, "ssao_intensity": 1.8, "sun_soft": 1.2,
		"ambient": 1.15, "tonemap": 2 }],
]
const PRESET_CUSTOM := 4          # «СВОЁ»: игрок тронул хоть один пункт вручную

var vsync: int = VSync.ON
var fps_limit := 0
var shadow_preset := 1
var ssao := false
var ssil := false
var fog := true
var glow := true
var msaa: int = Msaa.X2           # 2X: на Compatibility это единственное сглаживание
var screen_aa := false
var scale := 0.7
var show_fps := true
var skid_life := 30.0             # 0 — полосы не исчезают, а только перезаписываются
# расширенные пункты картинки
var tonemap: int = 2
var exposure := 1.0
var tonemap_white := 4.0
var glow_intensity := 0.45
var glow_bloom := 0.0
var fog_density := 0.0016
var fog_aerial := 0.5
var fog_scatter := 0.25
var ssao_radius := 1.2
var ssao_intensity := 1.4
var sun_soft := 0.55              # угловой размер солнца: мягкость границы тени
var ambient := 1.0                # множитель рассеянного света поверх базового
# камера и время
var fov := 75.0
var shake := 1.0
var slowmo := 0.3
# как выглядит сам экран настроек
var tier_extended := false
var preset := 1
# окно: полноэкранный режим — настройка, размер/позиция — запоминаемое состояние
var fullscreen := false
var _win_rect := Rect2i(0, 0, 1600, 900)
var _win_max := false
var _win_save_at := 0

# Заводские значения снимаются до чтения файла: _init гарантированно раньше _ready,
# и это единственный честный источник «как на заводе» для кнопки сброса.
var _defaults := {}

func _init() -> void:
	_defaults = values()

func _ready() -> void:
	load_values()
	restore_window_geometry()
	apply_window()
	changed.connect(apply_window)

# Минимальная геометрия, которую вообще стоит помнить и возвращать. Ниже — это уже
# не окно, а осколок: Windows не даёт рамке сжаться, а Godot сжимает клиентскую
# область, и интерфейс пропадает (серое окно с полоской).
const WIN_MIN := Vector2i(320, 240)
const WIN_DEFAULT := Vector2i(1600, 900)

static func _win_ok(r: Rect2i) -> bool:
	return r.size.x >= WIN_MIN.x and r.size.y >= WIN_MIN.y

# Восстановление — ровно один раз на старте: если дёргать размер из apply_window,
# он воевал бы с каждым пользовательским ресайзом.
func restore_window_geometry() -> void:
	if fullscreen: return
	var scr := DisplayServer.screen_get_size()
	var r := _win_rect
	if not _win_ok(r):
		# Ноль мог остаться в файле от прошлой версии. Если и живое окно сжалось
		# в ноль, игроку показывается серое поле с тонкой полоской интерфейса:
		# поднимаем заводской размер, иначе чинить нечего.
		var live := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		if not _win_ok(live): DisplayServer.window_set_size(WIN_DEFAULT)
		return
	if _win_max:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(r.size)
	# сохранённая позиция могла остаться от отключённого монитора: возвращаем на экран
	var pos := r.position
	pos.x = clampi(pos.x, -r.size.x + 160, scr.x - 160)
	pos.y = clampi(pos.y, 0, scr.y - 160)
	DisplayServer.window_set_position(pos)

# Запоминаем только оконный режим: в maximized/fullscreen размер — это весь экран,
# и запись затёрла бы настоящую геометрию. У Window нет сигнала о перемещении,
# поэтому прямоугольник опрашивается в _process — сравнение двух Rect2i копеечное.
func _capture_window() -> void:
	# В headless окно — фикция нулевого размера, и каждый тестовый прогон записывал
	# в настоящие настройки игрока w=0 h=0. Развёрнутое окно отдаёт тот же ноль.
	if DisplayServer.get_name() == "headless": return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN: return
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED: return
	_win_max = mode == DisplayServer.WINDOW_MODE_MAXIMIZED
	if _win_max: return
	var r := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	if not _win_ok(r): return
	if r == _win_rect: return
	_win_rect = r
	_win_save_at = Time.get_ticks_msec() + 500

func values() -> Dictionary:
	return {
		"vsync": vsync, "fps_limit": fps_limit, "shadow_preset": shadow_preset,
		"ssao": ssao, "ssil": ssil, "fog": fog, "glow": glow,
		"msaa": msaa, "screen_aa": screen_aa, "scale": scale, "show_fps": show_fps,
		"skid_life": skid_life, "tonemap": tonemap, "exposure": exposure,
		"tonemap_white": tonemap_white, "glow_intensity": glow_intensity, "glow_bloom": glow_bloom,
		"fog_density": fog_density, "fog_aerial": fog_aerial, "fog_scatter": fog_scatter,
		"ssao_radius": ssao_radius, "ssao_intensity": ssao_intensity, "sun_soft": sun_soft,
		"ambient": ambient, "fov": fov, "shake": shake, "slowmo": slowmo,
		"tier_extended": tier_extended, "preset": preset, "fullscreen": fullscreen,
	}

func set_value(key: String, v: Variant, persist := true) -> void:
	var all := values()
	if not all.has(key): return
	var want: Variant = all[key]
	var val: Variant = v
	if typeof(want) == TYPE_BOOL:
		val = bool(v)
	elif NUMS.has(key):
		if typeof(want) == TYPE_INT:
			val = clampi(int(v), int(NUMS[key][0]), int(NUMS[key][1]))
		else:
			val = clampf(float(v), float(NUMS[key][0]), float(NUMS[key][1]))
	set(key, val)
	if key != "preset" and key != "tier_extended":
		_mark_custom(key, val)
	if persist:
		save()
		changed.emit()

# Пресет перестаёт быть пресетом в тот момент, когда значение в нём разошлось.
# Сравниваем только тот ключ, который тронули: иначе любое касание сбрасывало бы
# отметку и игрок терял указатель «я в СРЕДНЕМ».
func _mark_custom(key: String, val: Variant) -> void:
	if preset >= PRESET_CUSTOM: return
	if not PRESETS[preset][1].has(key): return
	if PRESETS[preset][1][key] != val:
		set("preset", PRESET_CUSTOM)

func apply_preset(i: int) -> void:
	if i < 0 or i >= PRESETS.size(): return
	set("preset", i)
	for k in PRESETS[i][1]:
		set_value(k, PRESETS[i][1][k], false)
	save()
	changed.emit()

func preset_name() -> String:
	return "СВОЁ" if preset >= PRESET_CUSTOM else String(PRESETS[preset][0])

# Применяет всё, что живёт не в Environment конкретной сцены: вертикальная синхронизация,
# потолок кадров, сглаживание и внутренний масштаб окна. Освещение и пост-эффекты
# применяются из GameManager, потому что Environment принадлежит сцене, а не автозагрузке.
func apply_window() -> void:
	match vsync:
		VSync.OFF: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSync.ADAPTIVE: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = maxi(fps_limit, 0)
	if fullscreen:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		# выход из полноэкранного возвращает на запомненную геометрию, а не на 1600×900
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_MAXIMIZED if _win_max else DisplayServer.WINDOW_MODE_WINDOWED)
		if not _win_max and _win_ok(_win_rect):
			DisplayServer.window_set_size(_win_rect.size)
			DisplayServer.window_set_position(_win_rect.position)
	var w := get_window()
	if w != null:
		w.msaa_3d = msaa
		w.scaling_3d_scale = scale
		# экранный сглаживатель движок Compatibility не знает: включать его можно только
		# там, где он действительно работает, иначе настройка врёт игроку
		var aa := screen_aa and supports_screen_aa()
		w.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa else Viewport.SCREEN_SPACE_AA_DISABLED

# Дебаунс геометрии: ресайз перетаскиванием генерирует событие на каждый пиксель,
# писать cfg на каждом — дисковый IO ради состояния окна.
func _process(_dt: float) -> void:
	_capture_window()
	if _win_save_at == 0 or Time.get_ticks_msec() < _win_save_at: return
	_win_save_at = 0
	save()

static func rendering_method() -> String:
	return RenderingServer.get_current_rendering_method()

static func supports_screen_aa() -> bool:
	return rendering_method() != "gl_compatibility"

static func supports_ssil() -> bool:
	return rendering_method() == "forward_plus"

# Базовая яркость рассеянного света зависит от движка: на Compatibility физически
# неоткуда взяться свету с неба (замер: 20% пикселей кузова темнее 0.05), поэтому там
# он целый ровный цвет с энергией 0.25. Множитель ambient крутится вокруг этой базы.
func ambient_base() -> float:
	return 0.25 if rendering_method() == "gl_compatibility" else 1.0

func ambient_energy() -> float:
	return ambient_base() * ambient

func shadow_enabled() -> bool:
	return int(SHADOW_PRESETS[shadow_preset_clamped()][1]) == 1

func shadow_distance() -> float:
	return float(SHADOW_PRESETS[shadow_preset_clamped()][2])

func shadow_preset_clamped() -> int:
	return clampi(shadow_preset, 0, SHADOW_PRESETS.size() - 1)

func save() -> void:
	var cf := ConfigFile.new()
	var d := values()
	for key in d:
		cf.set_value(SECTION, key, d[key])
	# В файл попадает только осмысленная геометрия. Ноль, однажды записанный (свёрнутое
	# окно отдаёт 0×0), потом разворачивается в «серое окно с полоской»: рамка у Windows
	# минимальная, а клиентская область — нет.
	if not _win_ok(_win_rect):
		var live := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		_win_rect = live if _win_ok(live) else Rect2i(Vector2i.ZERO, WIN_DEFAULT)
	cf.set_value(WIN_SECTION, "x", _win_rect.position.x)
	cf.set_value(WIN_SECTION, "y", _win_rect.position.y)
	cf.set_value(WIN_SECTION, "w", _win_rect.size.x)
	cf.set_value(WIN_SECTION, "h", _win_rect.size.y)
	cf.set_value(WIN_SECTION, "max", _win_max)
	InputRouter.save_keys(cf)
	cf.save(FILE)

# Значение из файла мог написать человек руками или испортить прошлая версия игры:
# Array у bool-ключа, Dictionary у числового. Прямой bool(raw)/int(raw) на таких
# значениях — это ошибка времени выполнения, после которой load_values обрывается
# посередине, и ВСЕ остальные настройки молча остаются дефолтными (проверено на
# враждебном settings.cfg). Поэтому приведение с проверкой типа и запасным значением.
static func _as_bool(raw: Variant, fallback: bool) -> bool:
	if raw is bool: return raw
	if raw is int or raw is float: return int(raw) != 0
	if raw is String:
		var t := (raw as String).to_lower()
		return t == "1" or t == "true" or t == "yes" or t == "on"
	return fallback

static func _as_num(raw: Variant, fallback: float) -> float:
	if raw is int or raw is float: return float(raw)
	if raw is String and (raw as String).is_valid_float(): return (raw as String).to_float()
	return fallback

func load_values() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(FILE)
	if err != OK:
		# Полусгоревший файл (дисок кончился посреди save) иначе молча стирается
		# первым же следующим save: сохраняем копию, чтобы пользователь мог вернуть
		# свои бинды и настройки руками
		if err == ERR_PARSE_ERROR and FileAccess.file_exists(FILE):
			DirAccess.copy_absolute(FILE.replace(".cfg", ""), FILE + ".bad")
		InputRouter.load_keys(cf)
		return
	var d := values()
	for key in d:
		if not cf.has_section_key(SECTION, key): continue
		var raw: Variant = cf.get_value(SECTION, key, d[key])
		var want: Variant = d[key]
		if typeof(want) == TYPE_BOOL:
			d[key] = _as_bool(raw, bool(want))
		elif NUMS.has(key) and typeof(want) == TYPE_INT:
			d[key] = clampi(int(_as_num(raw, float(want))), int(NUMS[key][0]), int(NUMS[key][1]))
		elif NUMS.has(key):
			d[key] = clampf(_as_num(raw, float(want)), float(NUMS[key][0]), float(NUMS[key][1]))
		elif key == "preset":
			# единственный числовой ключ вне NUMS: без границы preset=-1 читался
			# как последний пресет списка, а preset=1000 — как «СВОЁ»
			d[key] = clampi(int(_as_num(raw, float(want))), 0, int(PRESET_CUSTOM))
		elif raw is String or raw is int or raw is float or raw is bool:
			d[key] = raw
	for key in d:
		set_value(key, d[key], false)
	if cf.has_section(WIN_SECTION):
		var x := int(_as_num(cf.get_value(WIN_SECTION, "x", _win_rect.position.x), 0.0))
		var y := int(_as_num(cf.get_value(WIN_SECTION, "y", _win_rect.position.y), 0.0))
		var w := int(_as_num(cf.get_value(WIN_SECTION, "w", _win_rect.size.x), 0.0))
		var h := int(_as_num(cf.get_value(WIN_SECTION, "h", _win_rect.size.y), 0.0))
		if _win_ok(Rect2i(x, y, w, h)):
			_win_rect = Rect2i(x, y, w, h)
		_win_max = _as_bool(cf.get_value(WIN_SECTION, "max", false), false)
	InputRouter.load_keys(cf)
	changed.emit()

func reset() -> void:
	for key in _defaults:
		set_value(key, _defaults[key], false)
	InputRouter.reset_keys()
	changed.emit()
	save()
