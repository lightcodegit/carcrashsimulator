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

# Заводские значения снимаются до чтения файла: _init гарантированно раньше _ready,
# и это единственный честный источник «как на заводе» для кнопки сброса.
var _defaults := {}

func _init() -> void:
	_defaults = values()

func _ready() -> void:
	load_values()
	apply_window()
	changed.connect(apply_window)

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
		"tier_extended": tier_extended, "preset": preset,
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
	var w := get_window()
	if w != null:
		w.msaa_3d = msaa
		w.scaling_3d_scale = scale
		# экранный сглаживатель движок Compatibility не знает: включать его можно только
		# там, где он действительно работает, иначе настройка врёт игроку
		var aa := screen_aa and supports_screen_aa()
		w.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa else Viewport.SCREEN_SPACE_AA_DISABLED

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
	InputRouter.save_keys(cf)
	cf.save(FILE)

func load_values() -> void:
	var cf := ConfigFile.new()
	if cf.load(FILE) != OK:
		InputRouter.load_keys(cf)
		return
	var d := values()
	for key in d:
		if not cf.has_section_key(SECTION, key): continue
		var raw: Variant = cf.get_value(SECTION, key, d[key])
		var want: Variant = d[key]
		if typeof(want) == TYPE_BOOL:
			d[key] = bool(raw)
		elif NUMS.has(key) and typeof(want) == TYPE_INT:
			d[key] = clampi(int(raw), int(NUMS[key][0]), int(NUMS[key][1]))
		elif NUMS.has(key):
			d[key] = clampf(float(raw), float(NUMS[key][0]), float(NUMS[key][1]))
		else:
			d[key] = raw
	for key in d:
		set_value(key, d[key], false)
	InputRouter.load_keys(cf)
	changed.emit()

func reset() -> void:
	for key in _defaults:
		set_value(key, _defaults[key], false)
	InputRouter.reset_keys()
	changed.emit()
	save()
