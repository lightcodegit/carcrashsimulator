extends Node3D
# Сколько стоит картинка — измеряется живым окном, а не headless: в headless GPU нет,
# и время кадра там ничего не говорит о рендере. Печатает не только среднее, но и
# распределение длительностей кадров: «30 fps при любых настройках» — признак кванта
# вертикалки, а видно это только по гистограмме.
#
# Бюджет жёсткий: под Wayland композитор не даёт приложению отключить вертикалку
# (движок честно пишет «V-Sync mode Disabled is not available»), поэтому кадр дольше
# 16.7 мс на 60 Гц уходит ровно в 33.3 мс — это и есть те 30 fps, о которых игрок.
#
# STAGES=all,shadow,max,s90 — какие конфигурации промерить, по очереди.
const SETTLE := 45    # тиков на перестройку фреймбуфера после смены настроек
const WINDOW := 180   # кадров, по которым считаем

# Имя -> конфигурация. msaa/shadow — номера из Settings; scale — внутренний масштаб 3D:
# он режет пиксельные проходы, а геометрия остаётся, то есть самый дешёвый способ
# уложиться в 16.7 мс на слабом GPU.
const PRESETS := {
	"all":    { "msaa": 0, "shadow": 0, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": false, "scale": 1.0 },
	"shadow": { "msaa": 0, "shadow": 1, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": true, "scale": 1.0 },
	"sglow":  { "msaa": 0, "shadow": 1, "ssao": false, "ssil": false, "fog": false,
		"glow": true, "fxaa": true, "scale": 1.0 },
	"max":    { "msaa": 2, "shadow": 2, "ssao": true, "ssil": true, "fog": true,
		"glow": true, "fxaa": true, "scale": 1.0 },
	# -1 по msaa = не трогать: значение приходит из конфига до первого кадра. Нужно
	# потому, что переключение MSAA на лету не всегда пересобирает мультисемпл, и цена
	# тогда получается нулевой — поэтому комбинации считают через STAGES=env.
	"keep":   { "msaa": -1, "shadow": 0, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": false, "scale": 1.0 },
	# «как при запуске»: не меняем ничего, кроме вертикалки — это проверка, что дефолты
	# проекта действительно укладываются в 16.7 мс на слабом GPU
	"boot":   { "msaa": -1, "shadow": -1, "ssao": null, "ssil": null, "fog": null,
		"glow": null, "fxaa": null, "scale": -1.0 },
}

var _gm: GameManager
var _measuring := false
var _t0 := 0
var _ms := PackedFloat64Array()

func _ready() -> void:
	var ids := OS.get_environment("STAGES")
	if ids == "": ids = "all"
	print("PROBE driver=%s display=%s method=%s adapter=%s type=%d size=%s" % [
		RenderingServer.get_current_rendering_driver_name(),
		DisplayServer.get_name(),
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_type(),
		str(get_window().size)])
	GameContext.select("sport", "speedway")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	await get_tree().process_frame
	for id in ids.split(",", false):
		var p: Dictionary = {}
		if id == "env":
			# комбинации задаются из окружения, потому что список их длиннее, чем
			# хочется держать в коде: SHADOW/GLOW/FOG/SCALE, msaa — из конфига
			var sc := float(OS.get_environment("SCALE"))
			p = { "msaa": -1, "shadow": int(OS.get_environment("SHADOW")),
				"ssao": OS.get_environment("SSAO") == "1", "ssil": false,
				"fog": OS.get_environment("FOG") == "1",
				"glow": OS.get_environment("GLOW") == "1", "fxaa": false,
				"scale": sc if sc > 0.0 else 1.0 }
		elif PRESETS.has(id):
			p = PRESETS[id]
		else:
			push_warning("PROBE: неизвестный stage " + id)
			continue
		_apply(p)
		await _wait(SETTLE)
		_ms = PackedFloat64Array()
		_t0 = Time.get_ticks_usec()
		_measuring = true
		await _wait(WINDOW)
		_measuring = false
		var total := float(Time.get_ticks_usec() - _t0) / 1000.0 / _ms.size()
		# один интервал вертикалки или два: при 60 Гц это ровно разница между
		# «идёт 60» и «идёт 30», а среднее по кадру её не показывает
		var one := 0
		var two := 0
		var rest := 0
		for d in _ms:
			if d < 22.0: one += 1
			elif d < 45.0: two += 1
			else: rest += 1
		print("STAGE %s: %.2f мс/кадр = %.1f fps | <=22=%d 22-45=%d >45=%d" % [
			id, total, 1000.0 / total, one, two, rest])
	print("PROBE done")
	get_tree().quit(0)

func _process(dt: float) -> void:
	if _measuring: _ms.append(dt * 1000.0)

func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

# Поля Settings напрямую, а не set_value(): здесь важна только картинка, а запись
# каждой конфигурации в файл засоряла бы настройки игрока.
func _apply(p: Dictionary) -> void:
	Settings.vsync = Settings.VSync.OFF
	Settings.fps_limit = 0
	if int(p.msaa) >= 0:
		Settings.msaa = int(p.msaa)
	if int(p.shadow) >= 0:
		Settings.shadow_preset = int(p.shadow)
	if p.ssao != null: Settings.ssao = bool(p.ssao)
	if p.ssil != null: Settings.ssil = bool(p.ssil)
	if p.fog != null: Settings.fog = bool(p.fog)
	if p.glow != null: Settings.glow = bool(p.glow)
	if p.fxaa != null: Settings.screen_aa = bool(p.fxaa)
	Settings.apply_window()
	_gm._apply_render()
	# NOSKY=1: оставить небо источником света (оно запекаётся в cubemap один раз), но
	# не рисовать его каждый кадр — это полноэкранный шейдер с rayleigh/mie, и его
	# цена решает, есть ли смысл в смене движка
	if OS.get_environment("NOSKY") == "1":
		_gm._env.background_mode = Environment.BG_COLOR
		_gm._env.bg_color = Color(0.35, 0.5, 0.68)
	if float(p.scale) > 0.0:
		get_window().scaling_3d_scale = float(p.scale)
	print("CFG msaa=%d shadow=%d glow=%d fog=%d ssao=%d fxaa=%d scale=%.2f nosky=%d" % [
		Settings.msaa, Settings.shadow_preset, int(Settings.glow), int(Settings.fog),
		int(Settings.ssao), int(Settings.screen_aa), get_window().scaling_3d_scale,
		int(OS.get_environment("NOSKY") == "1")])
