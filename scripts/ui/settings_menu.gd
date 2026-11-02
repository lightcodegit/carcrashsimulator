class_name SettingsMenu
extends Control
# Экран настроек в духе BeamNG.drive: затемнённый живой мир, слева вертикальные
# вкладки (КАЧЕСТВО / ГРАФИКА / КАМЕРА / УПРАВЛЕНИЕ), справа — содержимое секциями.
# Пресеты картинки — крупные карточки с ценой в мс; бинды — таблица
# «действие | клавиатура | геймпад», где каждый класс устройств назначается своей
# клеткой и не затирает соседний. Тот же контрол открывается из главного меню и из
# паузы. Публичный API (open/close/is_open/capturing/refresh/_begin_capture/
# _end_capture/_input/_unhandled_input, таблицы OPTIONS/CHECKS/SLIDERS/_supported)
# прежний — на него держатся GameManager, главное меню и h_settings.

signal closed

const ACTION_NAMES := {
	"throttle": "ГАЗ", "brake": "ТОРМОЗ / задний ход", "steer_left": "РУЛЬ влево",
	"steer_right": "РУЛЬ вправо", "handbrake": "РУЧНИК", "nitro": "НИТРО (форсаж)",
	"slowmo": "СЛОУ-МО",
	"cam_cycle": "СМЕНА КАМЕРЫ", "respawn": "РЕСТАРТ", "pause": "ПАУЗА",
}
const OPTIONS := [
	# [ключ, заголовок, подписи пунктов, значения, режим] — режим 0 виден всегда,
	# 1 появляется только в расширенном. "preset" живёт карточками на вкладке
	# КАЧЕСТВО и списком больше не рисуется (потому и исключён из VIDEO_SECTIONS).
	["preset", "КАЧЕСТВО КАРТИНКИ", ["НИЗКОЕ", "СРЕДНЕЕ", "ВЫСОКОЕ", "КИНО", "СВОЁ"], [0, 1, 2, 3, 4], 0],
	["vsync", "ВЕРТИКАЛЬНАЯ СИНХРОНИЗАЦИЯ", ["ВЫКЛ", "ВКЛ", "АДАПТИВНАЯ"], [0, 1, 2], 0],
	["fps_limit", "ПОТОЛОК КАДРОВ", ["БЕЗ ПОТОЛКА", "30", "60", "120"], [0, 30, 60, 120], 0],
	["scale", "МАСШТАБ КАРТИНКИ", ["70%", "85%", "100%"], [0.7, 0.85, 1.0], 0],
	["shadow_preset", "ТЕНИ", ["ВЫКЛ", "КОРОТКИЕ 120 М", "СРЕДНИЕ 260 М", "ДАЛЬНИЕ 420 М"], [0, 1, 2, 3], 0],
	["msaa", "МСАА", ["НЕТ", "2×", "4×", "8×"], [0, 1, 2, 3], 0],
	["tonemap", "ТОНМАППИНГ", ["НЕЙТРАЛЬНЫЙ", "ФИЛЬМ", "КИНО (ACES)"], [0, 1, 2], 1],
]
const CHECKS := [
	["ssao", "ТЕНЬ КОНТАКТА (SSAO)", 0],
	["ssil", "НЕПРЯМОЙ СВЕТ (SSIL)", 0],
	["fog", "ДЫМКА И ТУМАН", 0],
	["screen_aa", "ЭКРАННОЕ СГЛАЖИВАНИЕ", 0],
	["glow", "СВЕЧЕНИЕ ЯРКОГО", 0],
	["show_fps", "СЧЁТЧИК КАДРОВ НА ЭКРАНЕ", 0],
]
# [ключ, заголовок, мин, макс, шаг, формат, множитель показа, режим].
# Камера (fov/shake/slowmo) — настройки вида, а не «расширенная графика»: живут на
# своей вкладке и показаны всегда (режим 0).
const SLIDERS := [
	["skid_life", "СЛЕД РЕЗИНЫ ЖИВЁТ, С", 0.0, 120.0, 5.0, "%.0f", 1.0, 0],
	["exposure", "ЭКСПОЗИЦИЯ", 0.4, 2.5, 0.05, "%.2f", 1.0, 1],
	["tonemap_white", "ТОЧКА БЕЛОГО", 1.0, 12.0, 0.5, "%.1f", 1.0, 1],
	["glow_intensity", "СВЕЧЕНИЕ: ЯРКОСТЬ", 0.0, 1.5, 0.05, "%.2f", 1.0, 1],
	["glow_bloom", "СВЕЧЕНИЕ: BLOOM", 0.0, 1.0, 0.05, "%.2f", 1.0, 1],
	["fog_density", "ДЫМКА: ПЛОТНОСТЬ ×1000", 0.0, 20.0, 0.5, "%.1f", 1000.0, 1],
	["fog_aerial", "ДЫМКА: ВОЗДУШНАЯ ПЕРСПЕКТИВА", 0.0, 1.0, 0.05, "%.2f", 1.0, 1],
	["fog_scatter", "РАССЕЯНИЕ СОЛНЕЧНОГО СВЕТА", 0.0, 1.0, 0.05, "%.2f", 1.0, 1],
	["ssao_radius", "SSAO: РАДИУС, М", 0.2, 4.0, 0.1, "%.1f", 1.0, 1],
	["ssao_intensity", "SSAO: СИЛА", 0.0, 4.0, 0.1, "%.1f", 1.0, 1],
	["sun_soft", "МЯГКОСТЬ СОЛНЕЧНЫХ ТЕНЕЙ, °", 0.0, 2.0, 0.05, "%.2f", 1.0, 1],
	["ambient", "РАССЕЯННЫЙ СВЕТ ×", 0.2, 3.0, 0.05, "%.2f", 1.0, 1],
	["fov", "ПОЛЕ ЗРЕНИЯ КАМЕРЫ, °", 50.0, 100.0, 1.0, "%.0f", 1.0, 0],
	["shake", "ТРЯСКА КАМЕРЫ ×", 0.0, 2.0, 0.1, "%.1f", 1.0, 0],
	["slowmo", "СЛОУ-МО: ФАКТОР ВРЕМЕНИ", 0.05, 1.0, 0.05, "%.2f", 1.0, 0],
]
# Порядок секций вкладки ГРАФИКА: заголовок -> ключи строк из OPTIONS/CHECKS/SLIDERS.
const VIDEO_SECTIONS := [
	["ОКНО И КАДР", ["vsync", "fps_limit", "scale", "msaa", "screen_aa", "show_fps"]],
	["СВЕТ И ТЕНИ", ["shadow_preset", "sun_soft", "ambient", "tonemap", "exposure", "tonemap_white"]],
	["АТМОСФЕРА", ["fog", "fog_density", "fog_aerial", "fog_scatter"]],
	["ЭФФЕКТЫ", ["glow", "glow_intensity", "glow_bloom", "ssao", "ssao_radius", "ssao_intensity", "ssil"]],
	["СЛЕД НА АСФАЛЬТЕ", ["skid_life"]],
]
const CAMERA_KEYS := ["fov", "shake", "slowmo"]
# Цена кадра и состав пресетов — из замеров на Intel HD 630 (см. Settings.PRESETS).
const PRESET_CARDS := [
	["НИЗКОЕ", "6.7 мс", "без теней и пост-эффектов, 70%"],
	["СРЕДНЕЕ", "13.7 мс", "дымка и свечение, тени 120 м"],
	["ВЫСОКОЕ", "29.4 мс", "SSAO/SSIL, MSAA 4×, тени 260 м"],
	["КИНО", "29.2 мс", "мягкие тени 420 м, bloom, экспозиция 1.15"],
]

static func _supported(key: String) -> bool:
	match key:
		"ssil": return Settings.supports_ssil()
		"screen_aa": return Settings.supports_screen_aa()
	return true

var _tabs_btn: Array[Button] = []
var _pages: Array[Control] = []
var _sliders := {}            # key -> [HSlider, Label, множитель, формат]
var _bind_btns := {}          # action -> [кнопка клавиатуры, кнопка геймпада]
var _preset_cards: Array[Button] = []
var _custom_note: Label
var _capture_label: Label
var _capturing := ""
var _is_open := false
var _save_at := 0             # мс, когда пора писать ползунки на диск

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	# почти непрозрачно: живой мир угадывается фоном, но подписи меню за оверлеем
	# не должны складываться в двойной текст с вкладками
	dim.color = Color(0.02, 0.025, 0.035, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_build_nav()
	var host := Control.new()
	host.name = "Content"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.offset_left = UiTheme.CONTENT_X; host.offset_right = -48
	host.offset_top = 64; host.offset_bottom = -64
	add_child(host)
	var builders := ["_quality_page", "_video_page", "_camera_page", "_controls_page"]
	for i in builders.size():
		var sc := ScrollContainer.new()
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.visible = i == 0
		host.add_child(sc)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		sc.add_child(box)
		_pages.append(sc)
		call(builders[i], box)
	_capture_label = UiTheme.label("", 15, UiTheme.AMBER, 500, true)
	_capture_label.position = Vector2(400, 862)
	add_child(_capture_label)

func _build_nav() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(UiTheme.MARGIN, 84)
	box.custom_minimum_size = Vector2(UiTheme.NAV_W, 0)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var names := ["КАЧЕСТВО", "ГРАФИКА", "КАМЕРА", "УПРАВЛЕНИЕ"]
	for i in names.size():
		var b := UiTheme.nav_item(names[i])
		b.custom_minimum_size = Vector2(UiTheme.NAV_W, 0)
		var idx := i
		b.pressed.connect(_show_tab.bind(idx))
		box.add_child(b)
		_tabs_btn.append(b)
	var bottom := VBoxContainer.new()
	bottom.position = Vector2(UiTheme.MARGIN, 700)
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)
	var reset := UiTheme.ghost_button("СБРОСИТЬ ВСЁ")
	reset.custom_minimum_size = Vector2(280, 44)
	reset.pressed.connect(func() -> void:
		Settings.reset()
		refresh())
	bottom.add_child(reset)
	var closeb := UiTheme.ghost_button("ЗАКРЫТЬ")
	closeb.custom_minimum_size = Vector2(280, 44)
	closeb.pressed.connect(func() -> void: closed.emit())
	bottom.add_child(closeb)

func _show_tab(i: int) -> void:
	for n in _pages.size(): _pages[n].visible = n == i
	# активная вкладка: янтарная полоса + подпись держатся постоянно, а не только
	# на наведении — иначе «открытая вкладка» неотличима от просто курсора рядом
	for t in _tabs_btn.size():
		UiTheme.nav_mark_active(_tabs_btn[t], t == i)

func open() -> void:
	visible = true
	_is_open = true
	refresh()
	if not _tabs_btn.is_empty(): _tabs_btn[0].grab_focus()

# Закрыть и сообщить. Флаг снимаем до сигнала, чтобы is_open() был честным для
# любого обработчика: владельцы экрана (главное меню, пауза) тоже зовут close(),
# повторный вызов безопасен.
func close() -> void:
	if _save_at != 0:
		_save_at = 0
		Settings.save()           # закрыть меню можно и не дождавшись тишины
	_capturing = ""
	_is_open = false
	visible = false

func is_open() -> bool:
	return _is_open

func capturing() -> bool:
	return _capturing != ""

# ---- вкладка КАЧЕСТВО: пресеты карточками -----------------------------------
func _quality_page(box: VBoxContainer) -> void:
	box.add_child(UiTheme.label("КАЧЕСТВО КАРТИНКИ", 30, Color.WHITE, 800))
	box.add_child(_sep())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	for i in PRESET_CARDS.size():
		var c := Button.new()
		c.text = "%s\n%s за кадр\n%s" % [PRESET_CARDS[i][0], PRESET_CARDS[i][1], PRESET_CARDS[i][2]]
		c.focus_mode = Control.FOCUS_ALL
		c.custom_minimum_size = Vector2(500, 108)
		c.add_theme_font_override("font", UiTheme.sans_font())
		c.add_theme_font_size_override("font_size", 17)
		c.add_theme_color_override("font_color", UiTheme.TEXT)
		c.add_theme_color_override("font_hover_color", Color.WHITE)
		c.add_theme_color_override("font_focus_color", Color.WHITE)
		c.add_theme_stylebox_override("normal", UiTheme.card_style(false))
		c.add_theme_stylebox_override("hover", UiTheme.card_style(true))
		c.add_theme_stylebox_override("pressed", UiTheme.card_style(true))
		c.add_theme_stylebox_override("focus", UiTheme.card_style(true))
		var idx := i
		c.pressed.connect(func() -> void:
			Settings.apply_preset(idx)
			refresh())
		grid.add_child(c)
		_preset_cards.append(c)
	_custom_note = UiTheme.label("", 15, UiTheme.AMBER)
	box.add_child(_custom_note)

# ---- вкладка ГРАФИКА: секции строк ------------------------------------------
func _video_page(box: VBoxContainer) -> void:
	if not Settings.supports_screen_aa() or not Settings.supports_ssil():
		var miss: Array[String] = []
		if not Settings.supports_screen_aa(): miss.append("сглаживание")
		if not Settings.supports_ssil(): miss.append("SSIL")
		box.add_child(UiTheme.label("Движок: %s · не поддерживается: %s" % [
			Settings.rendering_method(), ", ".join(miss)], 14, UiTheme.DIM))
	var mode := CheckBox.new()
	mode.text = "РАСШИРЕННЫЙ РЕЖИМ — ВСЯ ГРАФИКА ПО ПУНКТАМ"
	mode.focus_mode = Control.FOCUS_ALL
	mode.set_meta("key", "tier_extended")
	mode.set_meta("tier", 0)
	UiTheme.style_check(mode)
	mode.add_theme_color_override("font_color", UiTheme.AMBER)
	mode.toggled.connect(func(on: bool) -> void:
		Settings.set_value("tier_extended", on)
		_apply_tier())
	box.add_child(mode)
	for sec in VIDEO_SECTIONS:
		box.add_child(_spacer(14))
		box.add_child(_section_head(String(sec[0])))
		box.add_child(_sep())
		for key in sec[1]:
			box.add_child(_row_for(String(key)))

func _camera_page(box: VBoxContainer) -> void:
	box.add_child(UiTheme.label("КАМЕРА И ВРЕМЯ", 30, Color.WHITE, 800))
	box.add_child(_sep())
	for key in CAMERA_KEYS:
		box.add_child(_row_for(String(key)))

func _row_for(key: String) -> Control:
	for o in OPTIONS:
		if String(o[0]) == key: return _option_row(o)
	for c in CHECKS:
		if String(c[0]) == key:
			if not _supported(key):
				var skip := Control.new()
				skip.visible = false
				return skip
			return _check_row(c)
	for s in SLIDERS:
		if String(s[0]) == key: return _slider_row(s)
	var empty := Control.new()
	empty.visible = false
	return empty

func _option_row(o: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_meta("tier", int(o[4]))
	var lab := UiTheme.label(String(o[1]), 16, UiTheme.TEXT, 500)
	lab.custom_minimum_size = Vector2(400, 0)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(320, 36)
	opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for l in o[2]: opt.add_item(l)
	opt.set_meta("key", String(o[0]))
	opt.set_meta("values", o[3])
	UiTheme.style_option(opt)
	var key: String = o[0]
	var vals: Array = o[3]
	opt.item_selected.connect(func(i: int) -> void: Settings.set_value(key, vals[i]))
	row.add_child(opt)
	return row

func _check_row(c: Array) -> Control:
	var wrap := MarginContainer.new()
	wrap.set_meta("tier", int(c[2]))
	var cb := CheckBox.new()
	cb.text = String(c[1])
	cb.focus_mode = Control.FOCUS_ALL
	cb.set_meta("key", String(c[0]))
	UiTheme.style_check(cb)
	var k: String = c[0]
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(k, on))
	wrap.add_child(cb)
	return wrap

# Один ряд: заголовок, ползунок, число. Значение летит в Settings на каждом шаге
# (картинка меняется на глазах), а на диск — одно сохранение после тишины.
func _slider_row(sl: Array) -> Control:
	var key: String = sl[0]
	var mul: float = float(sl[6])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_meta("tier", int(sl[7]))
	var lab := UiTheme.label(String(sl[1]), 16, UiTheme.TEXT, 500)
	lab.custom_minimum_size = Vector2(400, 0)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	var s := HSlider.new()
	s.min_value = float(sl[2]) * mul
	s.max_value = float(sl[3]) * mul
	s.step = float(sl[4]) * mul
	s.custom_minimum_size = Vector2(420, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	UiTheme.style_slider(s)
	row.add_child(s)
	var val := UiTheme.label("", 15, UiTheme.DIM, 500, true)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	_sliders[key] = [s, val, mul, String(sl[5])]
	s.value_changed.connect(func(_v: float) -> void: _slide(key))
	return row

# HSlider в этом билде не имеет сигнала «отпустил», поэтому на диск уходит одно
# сохранение после того, как ползунок перестали двигать, а не на каждый пиксель.
func _slide(key: String) -> void:
	var rec: Array = _sliders[key]
	Settings.set_value(key, float(rec[0].value) / float(rec[2]), false)
	Settings.changed.emit()
	rec[1].text = String(rec[3]) % float(rec[0].value)
	_save_at = Time.get_ticks_msec() + 400

func _process(_dt: float) -> void:
	if _save_at == 0 or Time.get_ticks_msec() < _save_at: return
	_save_at = 0
	Settings.save()
	Settings.apply_window()

# ---- вкладка УПРАВЛЕНИЕ: таблица биндов -------------------------------------
func _controls_page(box: VBoxContainer) -> void:
	box.add_child(UiTheme.label("УПРАВЛЕНИЕ", 30, Color.WHITE, 800))
	box.add_child(_sep())
	box.add_child(UiTheme.label(
		"Клавиатура и геймпад назначаются раздельно: кнопка геймпада не съест клавишу, " +
		"и наоборот. Нажмите клетку и клавишу/кнопку — назначение впишется в свой столбец.",
		14, UiTheme.DIM))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	for t in [["ДЕЙСТВИЕ", 300.0], ["КЛАВИАТУРА", 280.0], ["ГЕЙМПАД", 280.0]]:
		var hl := UiTheme.label(String(t[0]), 13, UiTheme.FAINT, 700, true)
		hl.custom_minimum_size = Vector2(float(t[1]), 0)
		if String(t[0]) == "ДЕЙСТВИЕ": hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
	# хедер шире на ширину «СБРОС» в строках — столбцы совпадают
	var head_pad := Control.new()
	head_pad.custom_minimum_size = Vector2(90, 0)
	head.add_child(head_pad)
	box.add_child(head)
	# Список берём из раскладки, а не из подписей: новое действие обязано появиться
	# в экране само, иначе его нельзя переназначить.
	for action in InputRouter.DEFAULTS:
		box.add_child(_key_row(String(action)))

func _key_row(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab := UiTheme.label(String(ACTION_NAMES.get(action, action.to_upper())), 16, UiTheme.TEXT, 600)
	lab.custom_minimum_size = Vector2(300, 0)
	# колонка действия съедает всё лишнее: тогда клетки и «СБРОС» стоят
	# на одном месте во всех строках таблицы
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	var pair: Array = []
	for _i in 2:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(280, 40)
		b.add_theme_font_override("font", UiTheme.mono_font())
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", UiTheme.card_style(false))
		b.add_theme_stylebox_override("hover", UiTheme.card_style(true))
		b.add_theme_stylebox_override("pressed", UiTheme.card_style(true))
		b.add_theme_stylebox_override("focus", UiTheme.card_style(true))
		b.set_meta("bind_action", action)
		b.pressed.connect(_begin_capture.bind(action))
		row.add_child(b)
		pair.append(b)
	_bind_btns[action] = pair
	var clr := UiTheme.ghost_button("СБРОС", 13)
	clr.custom_minimum_size = Vector2(90, 40)
	clr.pressed.connect(func() -> void:
		InputRouter.clear_binding(action)
		refresh())
	row.add_child(clr)
	return row

# Имя бинда только своего класса устройств: клавиша — в столбец клавиатуры,
# кнопка/ось — в столбец геймпада.
func _class_name(action: String, want_key: bool) -> String:
	var parts: Array[String] = []
	for e in InputMap.action_get_events(action):
		if bool(e is InputEventKey) != want_key: continue
		var t := InputRouter.event_name(e)
		if t != "" and not (t in parts): parts.append(t)
	return " · ".join(parts) if not parts.is_empty() else "—"

# ---- захват назначения ------------------------------------------------------
func _begin_capture(action: String) -> void:
	_capturing = action
	_capture_label.text = "Нажмите клавишу или кнопку для «%s» · ESC отменяет" % \
		String(ACTION_NAMES.get(action, action.to_upper()))

func _end_capture() -> void:
	_capturing = ""
	_capture_label.text = ""
	refresh()

# Пока ждём назначение, событие перехватываем ДО обработки GUI: кнопка остаётся в
# фокусе, а Enter и Space — это ещё и ui_accept, иначе назначенный пробел нажимал
# бы кнопку снова и захват никогда бы не закончился.
func _input(event: InputEvent) -> void:
	if _capturing == "": return
	if not event.is_pressed() or _is_echo(event): return
	_take(event)
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# Esc вне захвата закрывает сам экран: иначе из настроек, открытых из паузы,
	# нельзя выйти клавиатурой
	if _capturing != "" or not _is_open: return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_dismiss()
		get_viewport().set_input_as_handled()

func _dismiss() -> void:
	close()
	closed.emit()

# Одно нажатие — одно назначение. Клавиша и устройство пишутся «как есть», без
# лишних полей: иначе событие не совпадёт с самим собой при сравнении.
func _take(event: InputEvent) -> void:
	var mapped: InputEvent = null
	if event is InputEventKey:
		var code: int = (event as InputEventKey).physical_keycode
		if code == KEY_ESCAPE:
			_end_capture()
			return
		var k := InputEventKey.new()
		k.physical_keycode = code
		mapped = k
	elif event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = (event as InputEventJoypadButton).button_index
		b.device = (event as InputEventJoypadButton).device
		mapped = b
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		var m := InputEventJoypadMotion.new()
		m.axis = (event as InputEventJoypadMotion).axis
		m.axis_value = (event as InputEventJoypadMotion).axis_value
		m.device = (event as InputEventJoypadMotion).device
		mapped = m
	if mapped == null: return
	InputRouter.rebind(_capturing, mapped)
	_end_capture()

static func _is_echo(e: InputEvent) -> bool:
	return e is InputEventKey and (e as InputEventKey).echo

# ---- перечитать всё из Settings/InputRouter ---------------------------------
func refresh() -> void:
	for n in _all_of("OptionButton"):
		var key := String(n.get_meta("key"))
		var vals: Array = n.get_meta("values")
		var cur := float(Settings.get(key))
		for i in vals.size():
			if is_equal_approx(cur, float(vals[i])): n.select(i)
	for n in _all_of("CheckBox"):
		var k := String(n.get_meta("key"))
		if k != "": n.button_pressed = bool(Settings.get(k))
	for key in _sliders:
		var rec: Array = _sliders[key]
		rec[0].value = float(Settings.get(key)) * float(rec[2])
		rec[1].text = String(rec[3]) % rec[0].value
	for action in _bind_btns:
		var pair: Array = _bind_btns[action]
		(pair[0] as Button).text = _class_name(String(action), true)
		(pair[1] as Button).text = _class_name(String(action), false)
	for i in _preset_cards.size():
		_preset_cards[i].add_theme_stylebox_override("normal", UiTheme.card_style(Settings.preset == i))
	_custom_note.text = "" if Settings.preset < Settings.PRESET_CUSTOM else \
		"СВОЁ — хотя бы одно значение изменено вручную. Карточка вернёт пресет целиком."
	_apply_tier()

# Расширенные строки скрыты, пока режим базовый. Прячем по meta, а не пересобираем:
# пересборка унесла бы фокус с контрола, на котором игрок стоит.
func _apply_tier() -> void:
	var ext := bool(Settings.tier_extended)
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).has_meta("tier"):
			(n as Control).visible = ext or int((n as Control).get_meta("tier")) == 0
		for k in n.get_children(): stack.append(k)

func _all_of(cls: String) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_class() == cls: out.append(n as Control)
		for c in n.get_children(): stack.append(c)
	return out

func _section_head(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tick := ColorRect.new()
	tick.color = UiTheme.AMBER
	tick.custom_minimum_size = Vector2(3, 16)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	row.add_child(UiTheme.label(text, 15, UiTheme.AMBER, 700))
	return row

func _sep() -> Control:
	var r := ColorRect.new()
	r.color = UiTheme.LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
