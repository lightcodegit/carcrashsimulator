class_name GameManager
extends Node3D

var car: CarRig
var hud: HUD
var camera: CameraRig
var effects: EffectsDirector
var skid: SkidMarks
var settings: SettingsMenu
var audio: AudioDriver
var vibration: VibrationFeed
var replay: ReplayRecorder
var replay_player: ReplayPlayer
var photo: PhotoMode
var _env: Environment
var _sun: DirectionalLight3D
var _spawn := Transform3D.IDENTITY
var _map_root: Node3D
var _endless := false
var _bounds := AABB(Vector3(-160, -30, -160), Vector3(320, 70, 320))
var _top_crash := 0.0
var _crashes := 0
var _paused := false
var _flip := 0.0
var _start_ms := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Esc и «в меню» должны работать и на паузе
	GameContext.loading_hide()   # сцена собрана: загрузочный экран больше не нужен
	TimeScale.set_hold(false)     # слоу-мо не должно переезжать в новый заезд
	_setup_env()
	var m: Dictionary = MapDB.build(GameContext.map_id)
	_spawn = m.spawn
	_bounds = m.bounds
	_map_root = m.root
	_endless = bool(m.info.get("endless", false))
	add_child(m.root)
	car = CarRig.new()
	add_child(car)
	var profiles := GarageProfiles.new()
	var params: VehicleParams = profiles.effective_params(GameContext.car_id)
	if params == null:
		# id мог прийти из сохранённого контекста старой версии игры: без машины
		# сцена была бы чёрным экраном, поэтому берём первую из списка и ругаемся
		push_error("GameManager: машина '%s' не найдена, ставим первую" % GameContext.car_id)
		params = VehicleDB.get_params(VehicleDB.ids()[0])
	car.build(params, get_world_3d())
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
	# звук и вибрация — следующие после effects: им нужна уже подключённая машина,
	# а сбитым предметам — уже готовый приёмник пыли от effects
	audio = AudioDriver.new()
	audio.name = "AudioDriver"
	add_child(audio)
	audio.attach(car)
	vibration = VibrationFeed.new()
	vibration.name = "VibrationFeed"
	add_child(vibration)
	vibration.attach(car)
	# пыль от сбитого предмета: callback в LooseProp, а не опрос — предмет знает
	# о ударе сам ровно в тот тик, когда его кувыркают
	for n in get_tree().get_nodes_in_group(LooseProp.GROUP):
		if n is LooseProp: (n as LooseProp).on_hit_fx = effects.on_prop_hit
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
	# Оверлей подключается последним: ему нужны и машина, и камера, и уже собранный
	# HUD, иначе первая перерисовка читала бы null.
	hud.attach_debug(self)
	hud.settings_requested.connect(_open_settings)
	# реплей — после HUD: плееру нужны и панель полос, и уже подключённая машина.
	#Recorder пишет кольцо кадров, player его проигрывает на замороженном мире.
	replay = ReplayRecorder.new()
	add_child(replay)
	replay.attach(car, self)
	replay_player = ReplayPlayer.new()
	add_child(replay_player)
	replay_player.setup(replay, car, self)
	# recorder обязан замолчать на собственном проигрывании: иначе повтор писал бы
	# сам себя и окно съезжало бы вперёд
	replay.player = replay_player
	hud.replay_requested.connect(_open_replay)
	hud.replay_exit_requested.connect(_exit_replay)
	hud.replay_step_requested.connect(func(d: int) -> void: replay_player.scrub(d))
	hud.replay_play_requested.connect(func() -> void: replay_player.toggle_play())
	hud.replay_rate_requested.connect(func(d: int) -> void: replay_player.bump_rate(d))
	replay_player.cursor_changed.connect(_on_replay_cursor)
	replay_player.stopped.connect(_on_replay_stopped)
	photo = PhotoMode.new()
	add_child(photo)
	photo.setup(car, self)
	photo.hud_hidden.connect(func(v: bool) -> void: hud.set_panels_hidden(v))
	# путь и номер кадра — по сигналу записи, а не «подождали кадр»: подпись
	# обязана показывать то, что легло на диск, и только когда легло
	photo.shot_saved.connect(func(_p: String, _i: int) -> void: _photo_label())
	photo.fov_changed.connect(func(_v: float) -> void: _photo_label())
	hud.photo_requested.connect(_open_photo)
	hud.photo_exit_requested.connect(_exit_photo)
	hud.photo_shot_requested.connect(_photo_shot)
	hud.photo_hide_requested.connect(_photo_hide)
	hud.photo_reset_requested.connect(_photo_reset)
	car.impact.connect(_on_impact)
	_start_ms = Time.get_ticks_msec()
	_release_inputs()
	_apply_render()
	# главное меню держит 3D-масштаб окна в 1.0 (витрина обязана быть резкой) —
	# на заезд возвращаем игровую настройку
	Settings.apply_window()

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
# Единственное место, где картинка доходит до живой сцены: всё, что игрок может
# покрутить в НАСТРОЙКАХ, обязано применяться отсюда, а не только записываться в файл.
func _apply_render() -> void:
	if _env == null or hud == null: return
	_env.ssao_enabled = Settings.ssao
	_env.ssil_enabled = Settings.ssil and Settings.supports_ssil()
	_env.fog_enabled = Settings.fog
	_env.glow_enabled = Settings.glow
	_sun.shadow_enabled = Settings.shadow_enabled()
	_sun.directional_shadow_max_distance = Settings.shadow_distance()
	_env.tonemap_mode = int(Settings.TONEMAPS[clampi(Settings.tonemap, 0, Settings.TONEMAPS.size() - 1)][1])
	_env.tonemap_exposure = Settings.exposure
	_env.tonemap_white = Settings.tonemap_white
	_env.glow_intensity = Settings.glow_intensity
	_env.glow_bloom = Settings.glow_bloom
	_env.fog_density = Settings.fog_density
	_env.fog_aerial_perspective = Settings.fog_aerial
	_env.fog_sun_scatter = Settings.fog_scatter
	_env.ssao_radius = Settings.ssao_radius
	_env.ssao_intensity = Settings.ssao_intensity
	_env.ambient_light_energy = Settings.ambient_energy()
	# угловой размер солнца — ширина полутени на краю собственной тени: нулевой даёт
	# бритвенную границу, около 1.2 — мягкую, как у настоящего диска на небе
	_sun.light_angular_distance = Settings.sun_soft
	if camera != null:
		camera.fov = Settings.fov
		camera.apply_settings()
	hud.set_fps_visible(Settings.show_fps)
	_apply_audio()

# Всё немое доводится до звука и до частиц отсюда: та же точка Settings.changed.
func _apply_audio() -> void:
	if audio != null:
		audio.apply_settings()
	if effects != null:
		effects.set_enabled(bool(Settings.particles_enabled) and not _paused)

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
	# все числа, которые игрок может покрутить, живут в _apply_render — иначе у
	# настройки было бы два источника правды и второе всегда побеждало при открытии меню
	env.glow_enabled = true
	env.ssao_enabled = true
	# экранный непрямой свет вытаскивает из черноты то, что не освещено солнцем напрямую:
	# припаркованные машины в тени домов были главным источником жалобы на темноту.
	# На Compatibility его нет — движок сам предупреждает, если включить, поэтому
	# просим только там, где он существует.
	env.ssil_enabled = Settings.supports_ssil()
	env.ssil_intensity = 1.25
	env.ssil_radius = 6.0
	# дымка даёт глубину и прячет границу прорисовки на 620-метровой трассе
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.85)   # оттенок дымки — не настройка, а часть образа
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
	# Байасы дефолта (0.1 / 2.0) рассчитаны на Forward+ с атласом 4096; в Compatibility
	# атлас 2048 на четыре сплита, и на поясе 30–60 м нормальный байас уезжает на
	# метры: тень отрывалась от основания борта и машины («тени ломаются, когда
	# подъезжаешь»). Зажатые байасы держат контакт, сплиты сдвинуты так, чтобы пояс
	# 25–70 м — куда падает край тени 60-метровой башни — попал в среднюю зону, а не
	# в хвостовую.
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.55
	sun.directional_shadow_fade_start = 0.9
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
	if _endless:
		# плиты переставляем каждый физический кадр: дешёвая проверка концев лент
		# ничего не стоит, а телепорты размазываются по кадрам вместо пакета
		# раз в полсекунды — лента не успевает отстать от машины
		MapDB.recycle(_map_root, car.chassis.global_position.x, 20.0)
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
	# В фотомоде свои клавиши: Esc — выход, F5 прячет интерфейс (ловит PhotoMode),
	# а действия заезда на него не должны влиять вовсе.
	if photo != null and photo.active:
		if event.is_action_pressed("pause"):
			# Экран без HUD прячет всё, включая кнопку возврата; F5 при этом может
			# быть занята биндом игрока. Первый Esc возвращает интерфейс, второй —
			# выходит из фотомода: тупика «спрятал и не вернуть» больше нет.
			if photo.hud_off: photo.hide_hud(false)
			else: _exit_photo()
		elif event.is_action_pressed("respawn"): _exit_photo()
		return
	# На реплее мир стоит, и клавиши заезда на нём не работают вовсе: Esc и R
	# значит «выйти», а не «пауза» и «рестарт по середине повтора».
	if replay_player != null and replay_player.active:
		if event.is_action_pressed("pause"): _exit_replay()
		elif event.is_action_pressed("respawn"):
			_exit_replay()
			_respawn_now()
			hud.show_tip("рестарт")
		return
	if event.is_action_pressed("pause"):
		_set_paused(not _paused)
	# R обязан работать и на паузе: игрок жмёт его, чтобы начать заезд заново, а не
	# чтобы выбираться из меню. Прежняя ветка «elif _paused: return» съедала именно
	# его, и со стороны это выглядело как «R не рестартит, а только сбрасывает скорость».
	elif event.is_action_pressed("respawn"):
		if _paused: _set_paused(false)
		_respawn_now()
		hud.show_tip("рестарт")
	elif _paused:
		return
	elif event.is_action_pressed("cam_cycle"):
		camera.cycle_mode()

func _respawn_now() -> void:
	_flip = 0.0
	# рестарт во время повтора или фотомода возможен (R работает на паузе), а
	# живой мир после респауна другой: проигрывание обязано закрыться до того,
	# как мы очистим кольцо, — иначе машина осталась бы с replaying=true поверх
	# собственной физики
	if replay_player != null and replay_player.active: _exit_replay()
	if photo != null and photo.active: _exit_photo()
	# окно реплея — это ОДИН заход: рестарт телепортирует машину, и повтор через
	# телепорт показывал бы не аварию, а прыжок
	if replay != null: replay.clear()
	for n in get_tree().get_nodes_in_group(LooseProp.GROUP):
		if is_instance_valid(n): n.restore()
	car.respawn(_spawn)
	skid.respawn()
	if audio != null: audio.reset_state()
	if vibration != null: vibration.stop()
	if effects != null: effects.reset_transient()
	TimeScale.set_hold(false)

# ── реплей удара ────────────────────────────────────────────────────────────
# Мир ставится на ту же паузу, что и меню: физика не считает ни шага, а плеер
# только перекладывает записанные кадры. Поэтому «повтор» — не пересимуляция.
func _open_replay() -> void:
	_set_paused(true)
	if replay_player.begin_default():
		hud.set_paused(false)          # карточку паузы прячем, но _paused остаётся: мир стоит
		hud.set_replay_ui(true)
		_release_inputs()
		_on_replay_cursor(replay_player.cursor, replay.window_end())
	else:
		hud.show_tip("окно реплея пусто — разгонитесь и ударьтесь")
		_set_paused(false)

func _exit_replay() -> void:
	if replay_player == null or not replay_player.active: return
	replay_player.end()
	hud.set_replay_ui(false)
	_set_paused(false)

func _on_replay_cursor(t: float, total: float) -> void:
	if hud == null: return
	var dents := 0
	for d in replay.dents:
		if float(d.t) <= t + 1e-6: dents += 1
	hud.set_replay_info(t - replay.window_start(), total - replay.window_start(),
		replay_player.rate(), replay_player.playing, dents)

# Выход из реплея возвращает живое состояние, поэтому HUD обязан перечесть
# вмятины и пик по настоящему кузову, а не по проигранному.
func _on_replay_stopped() -> void:
	if hud != null: hud.set_replay_info(0.0, 0.0, 1.0, false, 0)

# Единственный признак для всех, кто должен молчать на паузе и на повторе:
# recorder пишет только когда мир жив. И пауза, и повтор, и фотомод держат
# get_tree().paused, поэтому достаточно одного _paused.
func is_frozen() -> bool:
	return _paused

# ── фотомод ─────────────────────────────────────────────────────────────────
func _open_photo() -> void:
	_set_paused(true)
	if photo.begin():
		hud.set_paused(false)
		hud.set_photo_ui(true)
		_release_inputs()
		# Машина замирает целиком: она наследует ALWAYS у менеджера, и её физика
		# просыпалась на паузе — клавиши камеры (W/A/S/D) дёргали руль и газ
		# замороженного мира (жалоба: «в фотомоде можно двигать колёсами»). А
		# фотомоду от машины нужно только застывшее позой.
		car.process_mode = Node.PROCESS_MODE_DISABLED
		_photo_label()
	else:
		_set_paused(false)

func _exit_photo() -> void:
	if photo == null or not photo.active: return
	photo.end()
	hud.set_photo_ui(false)
	hud.set_panels_hidden(false)
	car.process_mode = Node.PROCESS_MODE_INHERIT
	_set_paused(false)

func _photo_shot() -> void:
	# подпись обновляется по сигналу shot_saved, а не «через кадр»: кадр пишется
	# ровно тогда, когда движок успел его взять, и ждать второй тик смысла нет
	photo.shoot()

func _photo_hide() -> void:
	photo.hide_hud(not photo.hud_off)

func _photo_reset() -> void:
	photo.reset_view()
	_photo_label()

func _photo_label() -> void:
	if hud == null or photo == null: return
	var p := photo.last_path()
	hud.set_photo_info(I18n.fmt("ФОТОМОД · FOV %.0f° · снимков %d%s", [
		photo.fov, photo.shots, "" if p == "" else " · " + p.replace("user://", "")]))

func _set_paused(v: bool) -> void:
	_paused = v
	if v: TimeScale.set_hold(false)
	get_tree().paused = v
	hud.process_mode = Node.PROCESS_MODE_ALWAYS if v else Node.PROCESS_MODE_INHERIT
	if v: hud.set_run_stats(run_summary())
	hud.set_paused(v)
	# GameManager живёт в PROCESS_MODE_ALWAYS и дети наследуют этот режим:
	# пауза сама по себе их не глушит, поэтому звук, вибрация и частицы
	# выключаются явным вызовом, а снятие с паузы возвращает настройки
	if v:
		if audio != null: audio.suspend()
		if vibration != null: vibration.set_active(false)
		if effects != null: effects.set_enabled(false)
	else:
		if audio != null: audio.resume()
		if vibration != null: vibration.set_active(true)
		if effects != null: effects.set_enabled(bool(Settings.particles_enabled))

# Сводка заезда в меню паузы: игрок уходит из игры на секунду и хочет увидеть, чем
# именно кончился заход, а не вспоминать это по памяти.
func run_summary() -> String:
	var secs := int((Time.get_ticks_msec() - _start_ms) / 1000)
	# fmt здесь, а не в HUD: составленная строка — уже не ключ каталога.
	return I18n.fmt("УДАРОВ %d · ЛУЧШИЙ %d КМ/Ч · %02d:%02d · %s / %s", [
		_crashes, int(_top_crash), secs / 60, secs % 60,
		GameContext.car_id.to_upper(), GameContext.map_id.to_upper()])

func debug_scene() -> Dictionary:
	# То же правило, что и для шасси: оверлей читает состояние сцены через один
	# интерфейс, а не через приватные поля менеджера.
	return {
		"map_root": _map_root,
		"bounds": _bounds,
		"spawn": _spawn.origin,
		"endless": _endless,
		"map_id": GameContext.map_id,
		"crashes": _crashes,
		"top_crash": _top_crash,
	}

# Тот же спавн на той же карте, без пересборки сцены: дёргать change_scene ради
# «начать заново» — значит на полсекунды потерять картинку ради того же результата.
func _restart_map() -> void:
	_crashes = 0
	_top_crash = 0.0
	_start_ms = Time.get_ticks_msec()
	hud.reset_run()        # пик перегрузки и timestamps журнала — с чистого заезда
	_respawn_now()
	hud.set_crash_stats(0, 0.0)
	hud.show_tip("заезд начат заново")
	_set_paused(false)

func _to_menu() -> void:
	get_tree().paused = false
	_paused = false
	GameContext.loading_show()
	# на выходе из заезда молчат все внешние устройства; _exit_tree дублирует
	# это на случай смены сцены минуя «в меню»
	if audio != null: audio.stop_all()
	if vibration != null: vibration.set_active(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
