extends Node
# Настройки игрока: картинка, счётчик кадров и раскладка клавиш.
#
# Файл лежит в user://, а не в репозитории: это состояние конкретного игрока, и в git
# ему делать нечего. Значения по умолчанию совпадают с тем, что проект имел до
# появления настроек, — первый запуск выглядит ровно как раньше.

signal changed

const FILE := "user://settings.cfg"
const SECTION := "video"
const KEYS_SECTION := "keys"

enum VSync { OFF, ON, ADAPTIVE }
enum Msaa { DISABLED = 0, X2 = 1, X4 = 2, X8 = 3 }

# тени: выкл / короткие / текущие / дальние. Это единственная настройка, которая
# заметно помогает слабой видеокарте и при этом не меняет ни модели, ни материалы.
const SHADOW_PRESETS := [
	["ВЫКЛ", 0, 0.0],
	["КОРОТКИЕ (120 м)", 1, 120.0],
	["СРЕДНИЕ (260 м)", 1, 260.0],
	["ДАЛЬНИЕ (420 м)", 1, 420.0],
]

var vsync: int = VSync.ON
var fps_limit := 0
var shadow_preset := 2
var ssao := true
var ssil := true
var fog := true
var glow := true
var msaa: int = Msaa.X4          # как в project.godot до появления настроек
var screen_aa := true
var show_fps := true

func _ready() -> void:
	load_values()
	apply_window()
	changed.connect(apply_window)

func values() -> Dictionary:
	return {
		"vsync": vsync, "fps_limit": fps_limit, "shadow_preset": shadow_preset,
		"ssao": ssao, "ssil": ssil, "fog": fog, "glow": glow,
		"msaa": msaa, "screen_aa": screen_aa, "show_fps": show_fps,
	}

func set_value(key: String, v: Variant) -> void:
	match key:
		"vsync": vsync = v
		"fps_limit": fps_limit = int(v)
		"shadow_preset": shadow_preset = int(v)
		"ssao": ssao = bool(v)
		"ssil": ssil = bool(v)
		"fog": fog = bool(v)
		"glow": glow = bool(v)
		"msaa": msaa = int(v)
		"screen_aa": screen_aa = bool(v)
		"show_fps": show_fps = bool(v)
		_: return
	save()
	changed.emit()

# Применяет всё, что живёт не в Environment конкретной сцены: вертикальная синхронизация,
# потолок кадров и сглаживание окна. Освещение и пост-эффекты применяются из GameManager,
# потому что Environment принадлежит сцене, а не автозагрузке.
func apply_window() -> void:
	match vsync:
		VSync.OFF: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSync.ADAPTIVE: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = maxi(fps_limit, 0)
	var w := get_window()
	if w != null:
		w.msaa_3d = msaa
		w.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if screen_aa else Viewport.SCREEN_SPACE_AA_DISABLED

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
	if cf.load(FILE) != OK: return
	var d := values()
	for key in d:
		if cf.has_section_key(SECTION, key):
			d[key] = cf.get_value(SECTION, key, d[key])
	vsync = int(d.vsync)
	fps_limit = int(d.fps_limit)
	shadow_preset = int(d.shadow_preset)
	ssao = bool(d.ssao)
	ssil = bool(d.ssil)
	fog = bool(d.fog)
	glow = bool(d.glow)
	msaa = int(d.msaa)
	screen_aa = bool(d.screen_aa)
	show_fps = bool(d.show_fps)
	InputRouter.load_keys(cf)

func reset() -> void:
	vsync = VSync.ON
	fps_limit = 0
	shadow_preset = 2
	ssao = true
	ssil = true
	fog = true
	glow = true
	msaa = Msaa.X4
	screen_aa = true
	show_fps = true
	InputRouter.reset_keys()
	save()
	changed.emit()
