extends Node3D
# Главное меню в духе BeamNG.drive: под интерфейсом живёт настоящая 3D-сцена —
# выбранная машина стоит на показном полигоне, камера медленно её облетает. Слева —
# вертикальное текстовое меню (без рамок-кнопок, янтарная полоса при наведении),
# справа — панель текущего раздела: запуск, список машин, список карт, настройки,
# выход. Выбор машины вживую подменяет модель в фоне. Физики в меню нет: модель
# статична, поэтому фон дешёв даже на слабом GPU, но выглядит как мир, а не картинка.

# Витрина VehicleDB: цифры и цвета зеркалят get_params (физика читает свою таблицу).
# Формат: имя, id, описание, макс. скорость км/ч, масса кг, разгон м/с², акцент кузова.
const CARS := [
	["СЕДАН", "sedan", "Сбалансированный седан · 160 км/ч · 1300 кг\nСредняя жёсткость кузова — честная классика краш-тестов.",
		160.0, 1300.0, 7.0, Color(0.78, 0.18, 0.16)],
	["ПИКАП", "pickup", "Тяжёлый пикап · 140 км/ч · 1900 кг\nКузов держит удар, который ломает остальных.",
		140.0, 1900.0, 6.0, Color(0.16, 0.35, 0.72)],
	["СПОРТКАР", "sport", "Хрупкий спорткар · 210 км/ч · 1050 кг\nБыстрый и низкий: мнётся глубоко и эффектно.",
		210.0, 1050.0, 11.0, Color(0.85, 0.75, 0.2)],
	["ЛИМУЗИН", "limousine", "Растянутый седан · 175 км/ч · 2100 кг\nСамый длинный и самый тяжёлый: разгон и тормоз честные, а не спортивные.",
		175.0, 2100.0, 5.6, Color(0.10, 0.11, 0.16)],
	["БЕСКОНЕЧНОСТЬ", "infinity", "Машина бесконечности · без потолка скорости · 900 кг\nРазгон вчетверо сильнее спорткара: держаться за дорогу сможет не всегда.",
		INF, 900.0, 45.0, Color(0.62, 0.28, 0.95)],
]
const MAPS := [
	["АРЕНА", "arena", "Испытательный полигон: стены, столбы, отбойники,\nлежачий полицейский, слалом и краш-блок."],
	["ГОРОДОК", "town", "Кварталы зданий, деревья, фонари, припаркованные\nмашины. Узкие улицы — боковые удары и рикошеты."],
	["ТРАССА", "speedway", "600 метров разгона и бетонная стена на финише.\nДля максимального лобового краш-теста."],
	["ГОНКА", "circuit", "Кольцо почти в километр: длинная прямая с трамплином, четыре\nповорота, трибуны, боксы и отбойники по всему периметру."],
	["БЕСКОНЕЧНОСТЬ", "endless", "Дорога без конца: плиты за спиной переставляются вперёд,\nтак что хватает только терпения, а не длины карты."],
	["ВОID", "void", "Бесконечное полотно во все стороны — ровная плоскость без стен и объектов."],
	["БОЛЬШОЙ ГОРОД", "bigcity", "Километр на километр: периметр, сетка улиц и районы —\nцентр, жилые кварталы, промзона, парк и стадион. Трамплин на бульваре."],
]

enum Section { PLAY, VEHICLES, GARAGE, MAPS, SETTINGS, EXIT }

var _profiles := GarageProfiles.new()
var _garage: GaragePanel
var _car_i := 0
var _map_i := 0
var _section := Section.PLAY

# 3D-фон
var _car_mount: Node3D
var _car_model: Node3D
var _orbit: Node3D
var _cam: Camera3D
var _orbit_angle := 0.0

# UI
var _ui: CanvasLayer
var _root: Control
var _nav: Array[Button] = []
var _panel: Control
var _settings: SettingsMenu
var _start_btn: Button
var _env: Environment
var _sun: DirectionalLight3D

func _ready() -> void:
	# Выбор переживает выход из заезда и из игры: восстанавливаем подсветку
	# карточек по GameContext до сборки интерфейса, иначе карточки показывали
	# первые элементы списка при живом другом выборе.
	GameContext.loading_hide()
	_car_i = _index_of_id(CARS, GameContext.car_id)
	_map_i = _index_of_id(MAPS, GameContext.map_id)
	_build_world()
	_build_ui()
	# Меню обязано быть резким: Settings.scaling_3d_scale (0.7 по умолчанию) — это
	# игровой компромисс слабой GPU, а витрина с машиной мылом быть не должна.
	# Плюс фон меню живёт по тем же настройкам картинки, что и заезд: дымка,
	# свечение, тени применяются к нему на лету, а не «когда-нибудь в игре» —
	# ровно жалоба «настройки графики долго применяются»
	_on_settings_changed()
	Settings.changed.connect(_on_settings_changed)
	_show_section(Section.PLAY)
	_load_car(_car_i)
	_nav[0].grab_focus()

func _on_settings_changed() -> void:
	var w := get_window()
	if w != null: w.scaling_3d_scale = 1.0
	if _env == null: return
	_env.fog_enabled = Settings.fog
	_env.fog_density = Settings.fog_density
	_env.fog_aerial_perspective = Settings.fog_aerial
	_env.fog_sun_scatter = Settings.fog_scatter
	_env.glow_enabled = Settings.glow
	_env.glow_intensity = Settings.glow_intensity
	_env.glow_bloom = Settings.glow_bloom
	_env.ssao_enabled = Settings.ssao
	_env.ssil_enabled = Settings.ssil and Settings.supports_ssil()
	_env.tonemap_mode = int(Settings.TONEMAPS[clampi(Settings.tonemap, 0, Settings.TONEMAPS.size() - 1)][1])
	_env.tonemap_exposure = Settings.exposure
	_env.tonemap_white = Settings.tonemap_white
	_env.ambient_light_energy = Settings.ambient_energy()
	_sun.shadow_enabled = Settings.shadow_enabled()
	_sun.directional_shadow_max_distance = Settings.shadow_distance()
	_sun.light_angular_distance = Settings.sun_soft

# ---------------------------------------------------------------- живой 3D-мир
# Фон меню — настоящая карта «Городок», собранная тем же MapDB, что и в заезде:
# машины видны на улицах, где им предстоит разбиваться. Свет дневной, как в игре,
# но без теней: витрине они не нужны, а на HD 630 это половина цены кадра.
var _focus := Vector3.ZERO      # точка, вокруг которой камера кружит (спавн городка)

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.10, 0.28, 0.62)
	ps.sky_horizon_color = Color(0.62, 0.74, 0.90)
	ps.sky_curve = 0.32
	ps.ground_bottom_color = Color(0.16, 0.17, 0.19)
	ps.ground_horizon_color = ps.sky_horizon_color
	ps.use_debanding = true
	sky.sky_material = ps
	env.sky = sky
	if Settings.rendering_method() == "gl_compatibility":
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.62, 0.75)
		env.ambient_light_energy = 0.25
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.85)
	env.fog_density = 0.0018
	_env = env
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = false
	# те же байасы и сплиты, что в заезде: если игрок включил тени в настройках,
	# витрина обязана показывать их тем же качеством
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.55
	sun.directional_shadow_fade_start = 0.9
	sun.directional_shadow_blend_splits = true
	_sun = sun
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 150, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	add_child(fill)

	var m: Dictionary = MapDB.build("town")
	add_child(m.root)
	# витрина стоит посередине города на главной улице: x=0 — центр карты,
	# z=-19 — середина полосы (спавн заезда (-120,-24) лежит у края и у арки,
	# для показа не годится)
	_focus = Vector3(0.0, 0.02, -19.0)
	_clear_showcase(m.root)

	_car_mount = Node3D.new()
	_car_mount.name = "CarMount"
	_car_mount.position = _focus
	add_child(_car_mount)

	_orbit = Node3D.new()
	_orbit.position = Vector3(_focus.x, 0.0, _focus.z)
	add_child(_orbit)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.current = true
	# облёт на 10.8 м: дальше деревьев (6-8 м от полосы) и сбитого хлама — витрина
	# в кадре всегда; снос 3.8 держит машину в левой трети, панель не наезжает
	_cam.position = Vector3(3.8, 2.5, 10.8)
	_orbit.add_child(_cam)

# Витрина не должна прятаться за декором: сносим сбитый хлам в 15 м от машины
# (отбойник ровно на её полосе да конусы) и деревья, чей ствол попадает в кольцо
# облёта. Городок для заезда при этом не меняется — расчистка только в меню.
func _clear_showcase(root: Node3D) -> void:
	for c in root.get_children():
		var n3 := c as Node3D
		if n3 == null: continue
		var d := n3.global_position.distance_to(_focus)
		if c is LooseProp and d < 15.0:
			root.remove_child(c)
			c.queue_free()
		elif String(c.name).begins_with("tree") and d < 11.5:
			root.remove_child(c)
			c.queue_free()

func _process(dt: float) -> void:
	# медленный кинематографичный облёт: курс вокруг машины + лёгкое «дыхание» высоты.
	# цель взгляда сдвинута ВПРАВО на 2.6 м: look_at ставит цель в центр экрана,
	# поэтому именно сдвиг цели (а не позиции) укладывает машину в левую треть,
	# где её правый борт не уходит под панель раздела
	_orbit_angle += dt * 0.12
	_orbit.rotation.y = _orbit_angle
	if _cam != null:
		_cam.position.y = 2.5 + sin(_orbit_angle * 1.3) * 0.18
		var eye := _cam.global_position
		var aim := _focus + Vector3(0.0, 0.7, 0.0)
		var dir := (aim - eye).normalized()
		var right := dir.cross(Vector3.UP).normalized()
		_cam.look_at(aim + right * 2.6, Vector3.UP)

# Индекс карточки по id из GameContext: выбор переживает выход из заезда и
# из игры; незнакомый id (старая версия файла настроек) откатывается на первый.
func _index_of_id(items: Array, id: String) -> int:
	for i in items.size():
		if String(items[i][1]) == id: return i
	return 0

func _load_car(i: int) -> void:
	_car_i = clampi(i, 0, CARS.size() - 1)
	if _car_model != null and is_instance_valid(_car_model):
		_car_mount.remove_child(_car_model)
		_car_model.queue_free()
		_car_model = null
	var id: String = CARS[_car_i][1]
	_profiles.select_vehicle(id)
	var p := _profiles.effective_params(id)
	if p == null: return
	var ps: PackedScene = load(p.model)
	if ps == null: return
	var node: Node3D = ps.instantiate()
	if node == null: return
	DentBody.stretch_model(node, p.body_stretch)
	var a: AABB = DentBody.measure(p.model, p.body_stretch).aabb
	var s := 4.6 / maxf(0.001, a.size.z)     # нормируем длину машины в мировые метры
	Materials.apply_tree(node, "car")
	Materials.apply_vehicle(node, p)
	node.scale = Vector3.ONE * s
	node.position = Vector3(-a.get_center().x * s, -a.position.y * s, -a.get_center().z * s)
	_car_mount.add_child(node)
	_car_model = node

func _preview_garage(params: VehicleParams) -> void:
	# Меняем только материал экземпляра: модель и общий кэш остаются нетронутыми.
	if is_instance_valid(_car_model):
		Materials.apply_vehicle(_car_model, params)

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "MenuUI"
	_ui.layer = 10
	add_child(_ui)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_root)

	# скрим левее колонки: городок светлый, и белые буквы навигации на фасадах
	# терялись — слева мягкая тёмная вуаль, как виньетка в BeamNG
	var scrim := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.015, 0.02, 0.03, 0.78), Color(0.015, 0.02, 0.03, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 8
	scrim.texture = gt
	# левая вуаль тянется на всю логическую высоту: при вертикальном аспекте окна
	# она кончилась бы посередине экрана
	scrim.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scrim.offset_right = UiTheme.fx(470.0)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	_build_logo(_root)
	_build_nav(_root)
	_build_panel(_root)
	_build_footer(_root)

	_settings = SettingsMenu.new()
	_settings.name = "SettingsMenu"
	_ui.add_child(_settings)
	# закрыл настройки — возвращаемся на «НАЧАТЬ»; сам раздел SETTINGS ничего не рисует,
	# он только открывает оверлей (иначе closed → open → closed — вечный круг)
	_settings.closed.connect(func() -> void:
		_settings.close()
		_show_section(Section.PLAY))

func _build_logo(host: Control) -> void:
	# логотип: процедурная эмблема (краш-звезда с машиной) + вордмарк из двух
	# строк — белая «CAR CRASH», янтарный «SIMULATOR», как BEAMNG + .DRIVE
	var row := HBoxContainer.new()
	row.position = Vector2(UiTheme.fx(UiTheme.MARGIN - 8), UiTheme.fx(40))
	row.add_theme_constant_override("separation", UiTheme.px(18))
	host.add_child(row)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/logo_emblem.svg")
	mark.custom_minimum_size = Vector2(UiTheme.px(96), UiTheme.px(96))
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.px(-10))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	# наклонный экстрасмелый: две строки собраны в один блок, вторая — со сдвигом,
	# как у спортивных брендов; обводка держит буквы на любом фоне городка
	var l1 := UiTheme.label("CAR CRASH", 46, Color.WHITE, 800)
	l1.add_theme_font_override("font", UiTheme.sans_font(800, true))
	l1.add_theme_constant_override("outline_size", UiTheme.px(8))
	l1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	col.add_child(l1)
	var l2 := UiTheme.label("SIMULATOR", 40, UiTheme.AMBER, 800)
	l2.add_theme_font_override("font", UiTheme.sans_font(800, true))
	l2.add_theme_constant_override("outline_size", UiTheme.px(8))
	l2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	l2.add_theme_constant_override("margin_left", UiTheme.px(60))
	col.add_child(l2)

func _build_nav(host: Control) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(UiTheme.fx(UiTheme.MARGIN), UiTheme.fx(250))
	box.custom_minimum_size = Vector2(UiTheme.fx(UiTheme.NAV_W), 0)
	box.add_theme_constant_override("separation", UiTheme.px(6))
	host.add_child(box)
	var items := ["НАЧАТЬ", "МАШИНЫ", "ГАРАЖ", "КАРТЫ", "НАСТРОЙКИ", "ВЫХОД"]
	for idx in items.size():
		var b := UiTheme.nav_item(items[idx], idx == 0)
		b.custom_minimum_size = Vector2(UiTheme.fx(UiTheme.NAV_W), 0)
		var sec: int = idx
		b.pressed.connect(func() -> void: _show_section(sec))
		box.add_child(b)
		_nav.append(b)
	UiTheme.nav_mark_active(_nav[0], true)

func _build_panel(host: Control) -> void:
	# панель раздела — тёмная полупрозрачная карточка поверх живого мира; высота
	# подгоняется под контент (_fit_panel), чтобы под короткими разделами не висело
	# пустое чёрное поле. Приклеена к правому краю фиксированной шириной: на
	# ультрашироких окнах процентная привязка растянула бы карточку на полэкрана
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(10))
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = UiTheme.fx(-700); _panel.offset_right = UiTheme.fx(-56)
	_panel.offset_top = UiTheme.fx(150); _panel.offset_bottom = UiTheme.fx(560)
	host.add_child(_panel)
	var holder := Control.new()
	holder.name = "PanelContent"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.offset_left = UiTheme.fx(26); holder.offset_right = UiTheme.fx(-26)
	holder.offset_top = UiTheme.fx(22); holder.offset_bottom = UiTheme.fx(-22)
	_panel.add_child(holder)

func _build_footer(host: Control) -> void:
	# Версия читается из настроек проекта, поэтому бамп в project.godot сам
	# обновляет надпись — подпись ассетов при этом остаётся требованием CC0.
	var version: String = ProjectSettings.get_setting("application/config/version")
	var v := UiTheme.label("v.%s · МОДЕЛИ: KENNEY CAR KIT 3.1 · CC0", 13, UiTheme.FAINT,
		500, true, [version])
	# нижний левый угол якорем: на вытянутых по высоте окнах подвал не должен
	# оставаться на уровне 856 px посередине экрана
	v.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	v.offset_left = UiTheme.fx(UiTheme.MARGIN); v.offset_top = UiTheme.fx(-44); v.offset_bottom = UiTheme.fx(-24)
	host.add_child(v)

# ---- переключение разделов -------------------------------------------------
func _show_section(sec: int) -> void:
	if _section == Section.GARAGE and sec != Section.GARAGE:
		_profiles.cancel()
		_preview_garage(_profiles.draft_params())
	_section = sec
	for n in _nav.size():
		UiTheme.nav_mark_active(_nav[n], n == sec)
	if sec == Section.SETTINGS:
		# меню под оверлеем настроек гаснем полностью: полупрозрачный фон
		# превращал подписи навигации в двойной текст поверх вкладок
		_root.visible = false
		_settings.open()
		return
	_root.visible = true
	_settings.close()
	# снимаем с родителя сразу: queue_free откладывает удаление на кадр, и за этот
	# кадр в дереве живут две панели — тесты и поиск по имени видели призраков
	var holder := _panel.get_node("PanelContent")
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	_cur_sc = null
	_garage = null
	match sec:
		Section.PLAY: _panel_play()
		Section.VEHICLES: _panel_vehicles()
		Section.GARAGE: _panel_garage()
		Section.MAPS: _panel_maps()
		Section.EXIT: _panel_exit()
	_fit_panel()

func _panel_play() -> void:
	var s := _scroller()
	var title := UiTheme.label("НАЧАТЬ", 34, Color.WHITE, 800)
	s.add_child(title)
	s.add_child(_sep())
	_kv(s, "МАШИНА", String(CARS[_car_i][0]))
	var cdesc := UiTheme.label_line(String(CARS[_car_i][2]), 0, 14, UiTheme.DIM)
	cdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cdesc.custom_minimum_size = Vector2(UiTheme.fx(560), 0)
	s.add_child(cdesc)
	_kv(s, "КАРТА", String(MAPS[_map_i][0]))
	var mdesc := UiTheme.label_flat(String(MAPS[_map_i][2]), 14, UiTheme.DIM)
	mdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mdesc.custom_minimum_size = Vector2(UiTheme.fx(560), 0)
	s.add_child(mdesc)
	s.add_child(_spacer(10))
	_start_btn = UiTheme.action_button("ЗАПУСТИТЬ СИМУЛЯЦИЮ", 24)
	_start_btn.custom_minimum_size = Vector2(UiTheme.fx(560), UiTheme.fx(64))
	_start_btn.pressed.connect(start_game)
	s.add_child(_start_btn)
	s.add_child(_spacer(6))
	var hint := UiTheme.label("Машину и карту меняй в разделах слева · Enter — запуск", 13, UiTheme.FAINT)
	s.add_child(hint)

# Карточка выбора: имя + описание живут внутри одной кнопки — список читается
# цельно, а не «подпись где-то под кнопкой», как было в черновике. Строка строки
# машины длиннее строки карты (см. CARS): у машин добавляется цветовой слом кузова
# справа — три полосы характеристик, чтобы сравнивать машины глазами, а не по тексту.
func _pick_card(items: Array, i: int, sel: bool, meta_key: String, cb: Callable) -> Button:
	var row: Array = items[i]
	var card := Button.new()
	card.flat = false
	card.text = ""
	card.focus_mode = Control.FOCUS_ALL
	card.add_theme_stylebox_override("normal", UiTheme.card_style(sel))
	card.add_theme_stylebox_override("hover", UiTheme.card_style(true))
	card.add_theme_stylebox_override("pressed", UiTheme.card_style(true))
	card.add_theme_stylebox_override("focus", UiTheme.card_style(true))
	var spec := row.size() > 3
	card.custom_minimum_size = Vector2(UiTheme.fx(560), UiTheme.fx(92 if spec else 72))
	# высота задана явно: вложенный VBox не участвует в минимальном размере
	# кнопки (Button меряет только свой text), без этого карточки схлопывались в строку
	card.set_meta(meta_key, i)
	card.pressed.connect(cb)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(host)
	if spec:
		var accent: Color = row[6]
		var slom := ColorRect.new()
		slom.color = Color(accent.r, accent.g, accent.b, 0.92)
		slom.position = Vector2(UiTheme.fx(16), UiTheme.fx(16)); slom.size = Vector2(UiTheme.fx(5), UiTheme.fx(56))
		slom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(slom)
		# левый блок — VBox: свободный Label вне контейнера не сжимается до
		# заданной ширины (минимальный размер текста распуляет его), и описание
		# machines залезало на полосы характеристик; контейнер width задаёт насильно
		var lbox := VBoxContainer.new()
		lbox.position = Vector2(UiTheme.fx(32), UiTheme.fx(12)); lbox.size = Vector2(UiTheme.fx(296), UiTheme.fx(70))
		lbox.add_theme_constant_override("separation", UiTheme.px(4))
		lbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(lbox)
		var nm := UiTheme.label(String(row[0]), 21, UiTheme.AMBER_HI if sel else Color.WHITE, 700)
		lbox.add_child(nm)
		var fl := UiTheme.label_line(String(row[2]), 1, 13, UiTheme.DIM, 500)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.max_lines_visible = 2
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbox.add_child(fl)
		var vmax: float = row[3]
		if is_finite(vmax):
			_stat(host, 344, 10, "СКОРОСТЬ", "%d км/ч", clampf(vmax / 220.0, 0.0, 1.0), [int(vmax)])
		else:
			_stat(host, 344, 10, "СКОРОСТЬ", "∞", clampf(1.0, 0.0, 1.0))
		_stat(host, 344, 38, "МАССА", "%d кг", clampf(row[4] / 2200.0, 0.0, 1.0), [int(row[4])])
		_stat(host, 344, 66, "РАЗГОН", "%.1f м/с²", clampf(row[5] / 45.0, 0.0, 1.0), [float(row[5])])
	else:
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = UiTheme.fx(16); col.offset_right = UiTheme.fx(-16)
		col.offset_top = UiTheme.fx(10); col.offset_bottom = UiTheme.fx(-10)
		col.add_theme_constant_override("separation", UiTheme.px(2))
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(col)
		var nm2 := UiTheme.label(String(row[0]), 21, UiTheme.AMBER_HI if sel else Color.WHITE, 700)
		col.add_child(nm2)
		var sub := UiTheme.label_line(String(row[2]), 0, 13, UiTheme.DIM, 500)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(sub)
	return card

# Одна строка паспорта машины: подпись, значение и полоса относительно шкалы
# (за максимум принят лучший показатель ростера, поэтому полосы сравнимы).
func _stat(host: Control, x: float, y: float, title: String, val: String, t: float, args: Array = []) -> void:
	# все координаты строки паспорта — дизайн-px; ступень применяем один раз здесь
	var sx := UiTheme.fx(x)
	var sy := UiTheme.fx(y)
	var lab := UiTheme.label(title, 11, UiTheme.FAINT, 600)
	lab.position = Vector2(sx, sy)
	host.add_child(lab)
	var v := UiTheme.label(val, 11, Color.WHITE, 700, false, args)
	v.position = Vector2(sx + UiTheme.fx(106), sy)
	v.size = Vector2(UiTheme.fx(66), UiTheme.fx(16))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	host.add_child(v)
	var bg := ColorRect.new()
	bg.color = UiTheme.LINE
	bg.position = Vector2(sx, sy + UiTheme.fx(17)); bg.size = Vector2(UiTheme.fx(172), UiTheme.fx(4))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	var fill := ColorRect.new()
	fill.color = UiTheme.AMBER
	fill.position = Vector2(sx, sy + UiTheme.fx(17)); fill.size = Vector2(UiTheme.fx(172.0 * t), UiTheme.fx(4))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(fill)

func _panel_vehicles() -> void:
	var s := _scroller()
	s.add_child(UiTheme.label("МАШИНЫ", 30, Color.WHITE, 800))
	s.add_child(UiTheme.label("выбор сразу подменяет машину в фоне", 13, UiTheme.FAINT))
	s.add_child(_sep())
	for i in CARS.size():
		s.add_child(_pick_card(CARS, i, i == _car_i, "car_i", select_car.bind(i)))

func _panel_garage() -> void:
	_garage = GaragePanel.new()
	_panel.get_node("PanelContent").add_child(_garage)
	_garage.preview_changed.connect(_preview_garage)
	_garage.setup(_profiles, I18n.t(String(CARS[_car_i][0])))

func _panel_maps() -> void:
	var s := _scroller()
	s.add_child(UiTheme.label("КАРТЫ", 30, Color.WHITE, 800))
	s.add_child(_sep())
	for i in MAPS.size():
		s.add_child(_pick_card(MAPS, i, i == _map_i, "map_i", select_map.bind(i)))

func _panel_exit() -> void:
	var s := _scroller()
	s.add_child(UiTheme.label("ВЫХОД", 30, Color.WHITE, 800))
	s.add_child(_sep())
	s.add_child(UiTheme.label("Выйти из Car Crash Simulator?", 18, UiTheme.DIM))
	s.add_child(_spacer(14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.px(14))
	s.add_child(row)
	var yes := UiTheme.action_button("ВЫЙТИ", 20)
	yes.custom_minimum_size = Vector2(UiTheme.fx(200), UiTheme.fx(56))
	yes.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(yes)
	var no := UiTheme.ghost_button("ОСТАТЬСЯ", 18)
	no.custom_minimum_size = Vector2(UiTheme.fx(160), UiTheme.fx(56))
	no.pressed.connect(func() -> void: _show_section(Section.PLAY))
	row.add_child(no)

# ---- хуки для логики и тестов ---------------------------------------------
func select_car(i: int) -> void:
	_load_car(i)
	if _section in [Section.PLAY, Section.VEHICLES, Section.GARAGE]:
		_show_section(_section)

func select_map(i: int) -> void:
	_map_i = clampi(i, 0, MAPS.size() - 1)
	if _section == Section.PLAY or _section == Section.MAPS:
		_show_section(_section)

func start_game() -> void:
	GameContext.select(String(CARS[_car_i][1]), String(MAPS[_map_i][1]))
	get_tree().paused = false
	GameContext.loading_show()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# ---- мелкие строительные помощники -----------------------------------------
var _cur_sc: ScrollContainer = null

func _scroller() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.get_node("PanelContent").add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiTheme.px(8))
	sc.add_child(box)
	_cur_sc = sc
	return box

# Панель высотой ровно по контенту (пол: 220, потолок 640 — дальше скролл).
func _fit_panel() -> void:
	if _section == Section.GARAGE:
		# Прокручиваются настройки, но действия с черновиком всегда видны.
		_panel.offset_bottom = _panel.offset_top + UiTheme.fx(640)
		return
	if _cur_sc == null: return
	var box := _cur_sc.get_child(0) as VBoxContainer
	if box == null: return
	var need := box.get_combined_minimum_size().y + UiTheme.fx(44.0)
	_panel.offset_bottom = _panel.offset_top + clampf(need, UiTheme.fx(220.0), UiTheme.fx(640.0))

func _kv(parent: Node, k: String, v: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.px(12))
	parent.add_child(row)
	var kl := UiTheme.label(k, 13, UiTheme.FAINT, 700, true)
	kl.custom_minimum_size = Vector2(UiTheme.fx(120), 0)
	row.add_child(kl)
	row.add_child(UiTheme.label(v, 20, Color.WHITE, 700))

func _sep() -> Control:
	var r := ColorRect.new()
	r.color = UiTheme.LINE
	r.custom_minimum_size = Vector2(0, UiTheme.fx(1))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, UiTheme.fx(h))
	return c
