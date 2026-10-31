class_name GameManager
extends Node3D

var car: CarRig
var hud: HUD
var camera: CameraRig
var effects: EffectsDirector
var skid: SkidMarks
var settings: SettingsMenu
var _env: Environment
var _sun: DirectionalLight3D
var _spawn := Transform3D.IDENTITY
var _bounds := AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320))
var _top_crash := 0.0
var _crashes := 0
var _paused := false
var _flip := 0.0
var _start_ms := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Esc и «в меню» должны работать и на паузе
	TimeScale.set_hold(false)     # слоу-мо не должно переезжать в новый заезд
	_setup_env()
	var m: Dictionary = MapDB.build(GameContext.map_id)
	_spawn = m.spawn
	_bounds = m.bounds
	add_child(m.root)
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params(GameContext.car_id), get_world_3d())
	car.respawn(_spawn)
	# после car в дереве: свой _physics_process получает уже посчитанное за этот тик скольжение
	skid = SkidMarks.new()
	skid.name = "SkidMarks"
	add_child(skid)
	skid.setup(car)
	settings = SettingsMenu.new()
	settings.name = "SettingsMenu"
	add_child(settings)   # настройки живут на слое HUD, чтобы не оказаться под интерфейсом
	effects = EffectsDirector.new()
	add_child(effects)
	effects.attach(car)
	camera = CameraRig.new()
	add_child(camera)
	camera.setup(car)
	camera.make_current()
	hud = HUD.new()
	add_child(hud)
	# настройки переселяются на слой HUD: как ребёнок Node3D они остались бы на слое 0
	# и утонули бы под интерфейсом
	settings.reparent(hud)
	settings.closed.connect(_close_settings)
	Settings.changed.connect(_apply_render)
	hud.bind(car)
	hud.menu_requested.connect(_to_menu)
	hud.resume_requested.connect(func() -> void: _set_paused(false))
	hud.restart_requested.connect(_restart_map)
	hud.settings_requested.connect(_open_settings)
	car.impact.connect(_on_impact)
	_start_ms = Time.get_ticks_msec()
	_release_inputs()
	_apply_render()

# Состояние действий переживает смену сцены: уход в меню с зажатым W возвращал в игру
# уже с нажатым газом и ручником, и машина начинала движение сама. Отжимаем всё ПОСЛЕ
# сбора HUD: экран настроек перехватывает нажатия только пока открыт, а на этапе
# _ready он ещё скрыт, и его контролы успевали съесть Esc как ui_cancel.
# Это release по уже известным именам из InputMap — новых состояний не заводим.
func _release_inputs() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)

# Настройки картинки применяются к конкретной сцене, потому что Environment и солнце
# принадлежат заезду, а не автозагрузке. Вызывается при сборке сцены и на каждый
# Settings.changed — экран настроек открыт и из меню, и из паузы.
func _apply_render() -> void:
	if _env == null or hud == null: return
	_env.ssao_enabled = Settings.ssao
	_env.ssil_enabled = Settings.ssil and Settings.supports_ssil()
	_env.fog_enabled = Settings.fog
	_env.glow_enabled = Settings.glow
	_sun.shadow_enabled = Settings.shadow_enabled()
	_sun.directional_shadow_max_distance = Settings.shadow_distance()
	hud.set_fps_visible(Settings.show_fps)

func _open_settings() -> void:
	# Карточку паузы прячем: её кнопки живые (focus_mode=ALL), и под затемнением
	# настроек навигация с геймпада уходила бы на невидимые контролы
	hud.set_paused(false)
	settings.open()

func _close_settings() -> void:
	settings.close()
	if _paused: hud.set_paused(true)     # фокус возвращается на кнопки паузы

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Небо — процедурный градиент, а не физическое. Физическое (Рэлей, диск солнца) на
	# этом движке оказалось не «правильным», а блёклым: замер игровым видом по восьми
	# полосам верхних 40% кадра дал разницу синего с красным 0.046, то есть молоко,
	# а вверх за горизонтом и вовсе темнее 0.01. Ручки PhysicalSkyMaterial (turbidity,
	# rayleigh_coefficient, mie) картинку не двигают вовсе. Градиент с явным синим зенитом
	# даёт 0.121 — втрое синее, и на обоих движках одинаково, а кубическая радианс-карта
	# неба по-прежнему питает отражения в кузовах.
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.10, 0.28, 0.62)        # зенит: густой синий ясный день
	ps.sky_horizon_color = Color(0.62, 0.74, 0.90)    # у горизонта — светлеет, как и должен
	ps.sky_curve = 0.32                               # где именно заканчивается горизонт
	ps.ground_bottom_color = Color(0.16, 0.17, 0.19)  # «земля» неба: тёмный асфальт, не трава
	ps.ground_horizon_color = ps.sky_horizon_color
	ps.sun_angle_max = 30.0
	ps.sun_curve = 0.55
	ps.use_debanding = true
	sky.sky_material = ps
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.sky = sky
	# небо как источник рассеянного света и отражений: иначе кузова в тени почти чёрные.
	# На Compatibility физическое небо рисуется примерно втрое темнее, чем на Forward+,
	# и свет, взятый с него, несёт ту же потерю: замер живым кадром — 20%
	# пикселей машины темнее 0.05 против 1% на Vulkan, при этом ambient_light_energy и
	# energy_multiplier неба на Compatibility не двигают ничего. Поэтому там рассеянный
	# свет берётся ровным цветом, подобранным по тому же замеру (2% чёрных, яркость 0.38).
	if Settings.rendering_method() == "gl_compatibility":
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.62, 0.75)
		env.ambient_light_energy = 0.25
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	# экранный непрямой свет вытаскивает из черноты то, что не освещено солнцем напрямую:
	# припаркованные машины в тени домов были главным источником жалобы на темноту.
	# На Compatibility его нет — движок сам предупреждает, если включить, поэтому
	# просим только там, где он существует.
	env.ssil_enabled = Settings.supports_ssil()
	env.ssil_intensity = 1.25
	env.ssil_radius = 6.0
	# дымка даёт глубину и прячет границу прорисовки на 620-метровой трассе
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.85)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.25
	we.environment = env
	add_child(we)
	_env = env
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_angular_distance = 0.55     # мягкая граница тени, а не бритвенная
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	_sun = sun
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 150, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	add_child(fill)

# Никакого баннера «УДАР» и автоматического слоу-мо: игра не должна останавливаться.
# Удар уходит только в компактный журнал телеметрии и в лёгкий шейк камеры.
func _on_impact(speed_kmh: float, _point: Vector3, _normal: Vector3) -> void:
	_crashes += 1
	_top_crash = maxf(_top_crash, speed_kmh)
	hud.log_impact(speed_kmh)
	hud.set_crash_stats(_crashes, _top_crash)
	camera.add_trauma(clampf(speed_kmh / 160.0, 0.12, 0.55))

func _physics_process(dt: float) -> void:
	if _paused: return
	TimeScale.set_hold(Input.is_action_pressed("slowmo"))
	var pos := car.chassis.global_position
	# Верхнюю границу не проверяем: над картой ничего не держит, и прыгнуть высоко —
	# это фича песочницы, а не вылет. Проверка только по горизонтали (y = 0 заведомо
	# внутри AABB), плюс провал под пол.
	if pos.y < -60.0 or not _bounds.has_point(Vector3(pos.x, 0.0, pos.z)):
		_respawn_now()
		hud.show_tip("вылет за пределы — рестарт")
		return
	# на настоящей подвеске машина может остаться на крыше и уже не поедет: подсказываем выход
	_flip = 0.0 if car.chassis.global_basis.y.y > -0.2 else _flip + dt
	if _flip > 1.0: hud.show_tip("машина на крыше — R для рестарта")

func _unhandled_input(event: InputEvent) -> void:
	# пока открыт экран настроек, его события нам не нужны: там своя обработка,
	# включая Esc для закрытия
	if settings != null and settings.is_open(): return
	if event.is_action_pressed("pause"):
		_set_paused(not _paused)
	elif _paused:
		return
	elif event.is_action_pressed("respawn"):
		_respawn_now()
	elif event.is_action_pressed("cam_cycle"):
		camera.cycle_mode()

func _respawn_now() -> void:
	_flip = 0.0
	for n in get_tree().get_nodes_in_group(LooseProp.GROUP):
		if is_instance_valid(n): n.restore()
	car.respawn(_spawn)
	skid.respawn()
	hud.show_tip("")
	TimeScale.set_hold(false)

func _set_paused(v: bool) -> void:
	_paused = v
	if v: TimeScale.set_hold(false)
	get_tree().paused = v
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if v else Node.PROCESS_MODE_INHERIT
	if v: hud.set_run_stats(run_summary())
	hud.set_paused(v)

# Сводка заезда в меню паузы: игрок уходит из игры на секунду и хочет увидеть, чем
# именно кончился заход, а не вспоминать это по памяти.
func run_summary() -> String:
	var secs := int((Time.get_ticks_msec() - _start_ms) / 1000)
	return "УДАРОВ %d · ЛУЧШИЙ %d КМ/Ч · %02d:%02d · %s / %s" % [
		_crashes, int(_top_crash), secs / 60, secs % 60,
		GameContext.car_id.to_upper(), GameContext.map_id.to_upper()]

# Тот же спавн на той же карте, без пересборки сцены: дёргать change_scene ради
# «начать заново» — значит на полсекунды потерять картинку ради того же результата.
func _restart_map() -> void:
	_crashes = 0
	_top_crash = 0.0
	_respawn_now()
	hud.set_crash_stats(0, 0.0)
	_set_paused(false)

func _to_menu() -> void:
	get_tree().paused = false
	_paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
