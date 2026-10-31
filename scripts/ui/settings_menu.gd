class_name SettingsMenu
extends Control
# Экран настроек: картинка и раскладка клавиш. Один и тот же контрол открывается из
# главного меню и из меню паузы, поэтому сам себя ставит поверх всего, перехватывает
# мышь и клавиатуру и умеет возвращать значения контролам после сброса.

signal closed

const PANEL_BG := Color(0.045, 0.055, 0.075, 0.94)
const PANEL_LINE := Color(0.36, 0.46, 0.60, 0.55)
const DIM := Color(0.66, 0.73, 0.82)
const ACCENT := Color(0.45, 0.8, 0.95)
const NOTE := Color(0.55, 0.62, 0.72)
const ACTION_NAMES := {
	"throttle": "ГАЗ", "brake": "ТОРМОЗ / задний ход", "steer_left": "РУЛЬ влево",
	"steer_right": "РУЛЬ вправо", "handbrake": "РУЧНИК", "slowmo": "СЛОУ-МО",
	"cam_cycle": "СМЕНА КАМЕРЫ", "respawn": "РЕСТАРТ", "pause": "ПАУЗА",
}
const OPTIONS := [
	# [ключ, заголовок, подписи пунктов, значения, режим] — режим 0 виден всегда,
	# 1 появляется только в расширенном
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
# [ключ, заголовок, мин, макс, шаг, формат, множитель показа, режим]
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
	["fov", "ПОЛЕ ЗРЕНИЯ КАМЕРЫ, °", 50.0, 100.0, 1.0, "%.0f", 1.0, 1],
	["shake", "ТРЯСКА КАМЕРЫ ×", 0.0, 2.0, 0.1, "%.1f", 1.0, 1],
	["slowmo", "СЛОУ-МО: ФАКТОР ВРЕМЕНИ", 0.05, 1.0, 0.05, "%.2f", 1.0, 1],
]

static func _supported(key: String) -> bool:
	match key:
		"ssil": return Settings.supports_ssil()
		"screen_aa": return Settings.supports_screen_aa()
	return true

var _mono: SystemFont
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _keys := {}          # action -> Label, показывающий текущую раскладку
var _sliders := {}         # key -> [HSlider, Label, множитель показа, формат]
var _capturing := ""
var _capture_label: Label
var _is_open := false
var _save_at := 0          # мс, когда пора писать ползунки на диск

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_mono = _font()
	add_child(_dim())
	var card := Panel.new()
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -470; card.offset_right = 470
	card.offset_top = -330; card.offset_bottom = 330
	card.add_theme_stylebox_override("panel", _style(8))
	add_child(card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 28; box.offset_right = -28; box.offset_top = 22; box.offset_bottom = -22
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_label("НАСТРОЙКИ", 34))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var video := _build_video()
	var controls := _build_controls()
	_pages = [video, controls]
	# расширенный режим — это строк двадцать, поэтому страницы живут в прокрутке:
	# без неё последние пункты оказались бы за нижним краем панели, и до них нельзя
	# было бы добраться ни мышью, ни с геймпада
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for i in _pages.size():
		var t := _button(["КАРТИНКА", "УПРАВЛЕНИЕ"][i])
		t.custom_minimum_size = Vector2(210, 40)
		tabs.add_child(t)
		t.pressed.connect(_show_page.bind(_pages[i]))
		_tabs.append(t)
	box.add_child(_note("Тени стоят дороже всего: на слабой видеокарте начните с них. " +
		"Ничего из этого не меняет модели и материалы — только стоимость кадра."))
	for pg in _pages: scroll.add_child(pg)
	box.add_child(scroll)
	_capture_label = _label("", 14, ACCENT)
	box.add_child(_capture_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	var reset := _button("СБРОСИТЬ ВСЁ")
	reset.custom_minimum_size = Vector2(220, 46)
	reset.pressed.connect(func() -> void:
		Settings.reset()
		refresh())
	bottom.add_child(reset)
	var close := _button("ЗАКРЫТЬ")
	close.custom_minimum_size = Vector2(220, 46)
	close.pressed.connect(func() -> void: closed.emit())
	bottom.add_child(close)
	refresh()
	_show_page(video)

func open() -> void:
	visible = true
	_is_open = true
	refresh()
	if not _tabs.is_empty(): _tabs[0].grab_focus()

# Закрыть и сообщить. Флаг снимаем до сигнала, чтобы `is_open()` был честным для
# любого обработчика: владельцы экрана (главное меню, пауза) тоже зовут close(),
# но повторный вызов безопасен.
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

func _show_page(page: Control) -> void:
	for p in _pages: p.visible = p == page

func _build_video() -> Control:
	var host := VBoxContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 6)
	if not Settings.supports_screen_aa() or not Settings.supports_ssil():
		# без этой строки игрок искал бы глазами выключенные у движка пункты
		var miss: Array[String] = []
		if not Settings.supports_screen_aa(): miss.append("сглаживание")
		if not Settings.supports_ssil(): miss.append("SSIL")
		host.add_child(_note("Движок: %s · не поддерживается: %s" % [
			Settings.rendering_method(), ", ".join(miss)]))
	var mode := CheckBox.new()
	mode.text = "РАСШИРЕННЫЙ РЕЖИМ — ВСЯ ГРАФИКА ПО ПУНКТАМ"
	mode.focus_mode = Control.FOCUS_ALL
	mode.add_theme_font_override("font", _mono)
	mode.add_theme_font_size_override("font_size", 15)
	mode.add_theme_color_override("font_color", ACCENT)
	mode.set_meta("key", "tier_extended")
	mode.toggled.connect(func(on: bool) -> void:
		Settings.set_value("tier_extended", on)
		_apply_tier())
	host.add_child(mode)
	for o in OPTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_wide_label(o[1], 470))
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(300, 34)
		for l in o[2]: opt.add_item(l)
		opt.set_meta("key", o[0])
		opt.set_meta("values", o[3])
		opt.set_meta("tier", int(o[4]))
		var key: String = o[0]
		var vals: Array = o[3]
		# пресет — не ещё одна настройка, а применение сразу нескольких: он обязан
		# перевести все ползунки, а не просто запомнить номер
		if key == "preset":
			opt.item_selected.connect(func(i: int) -> void:
				if i >= Settings.PRESET_CUSTOM:
					Settings.set_value("preset", Settings.PRESET_CUSTOM)
				else:
					Settings.apply_preset(i)
				refresh())
		else:
			opt.item_selected.connect(func(i: int) -> void: Settings.set_value(key, vals[i]))
		row.add_child(opt)
		host.add_child(row)
	for c in CHECKS:
		if not _supported(c[0]): continue
		var cb := CheckBox.new()
		cb.text = c[1]
		cb.focus_mode = Control.FOCUS_ALL
		cb.add_theme_font_override("font", _mono)
		cb.add_theme_font_size_override("font_size", 15)
		cb.add_theme_color_override("font_color", DIM)
		cb.set_meta("key", c[0])
		cb.set_meta("tier", int(c[2]))
		var k: String = c[0]
		cb.toggled.connect(func(on: bool) -> void: Settings.set_value(k, on))
		host.add_child(cb)
	for sl in SLIDERS:
		host.add_child(_slider_row(sl))
	return host

# Один ряд: заголовок, ползунок, число. Значение летит в Settings на каждом шаге
# (так картинка меняется на глазах), а на диск — только когда ползунок отпустили:
# иначе перетаскивание записывало бы файл тридцать раз в секунду.
func _slider_row(sl: Array) -> Control:
	var key: String = sl[0]
	var mul: float = float(sl[6])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_meta("tier", int(sl[7]))
	row.add_child(_wide_label(sl[1], 330))
	var s := HSlider.new()
	s.min_value = float(sl[2]) * mul
	s.max_value = float(sl[3]) * mul
	s.step = float(sl[4]) * mul
	s.custom_minimum_size = Vector2(320, 34)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var val := _label("", 15, DIM)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	_sliders[key] = [s, val, mul, String(sl[5])]
	s.value_changed.connect(func(_v: float) -> void: _slide(key))
	return row

# В этом билде у HSlider нет сигнала «отпустил» (только value_changed), поэтому диск
# пишется не на каждый пиксель перетаскивания, а по тишине: картинка меняется сразу,
# а на диск уходит одно сохранение после того, как ползунок перестали двигать.
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
func _build_controls() -> Control:
	var host := VBoxContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 6)
	host.add_child(_note("Действие можно назначить на клавишу, кнопку или ось геймпада. " +
		"Клавиатура и геймпад хранятся раздельно: назначив ручник на кнопку, пробел не потеряется."))
	for action in ACTION_NAMES:
		host.add_child(_key_row(action))
	return host

func _key_row(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_wide_label(ACTION_NAMES[action], 250))
	var val := _label(InputRouter.describe(action), 16)
	val.custom_minimum_size = Vector2(300, 0)
	_keys[action] = val
	row.add_child(val)
	var b := _button("НАЗНАЧИТЬ")
	b.custom_minimum_size = Vector2(160, 32)
	b.pressed.connect(_begin_capture.bind(action))
	row.add_child(b)
	var clr := _button("СБРОС")
	clr.custom_minimum_size = Vector2(110, 32)
	clr.pressed.connect(func() -> void:
		InputRouter.clear_binding(action)
		refresh())
	row.add_child(clr)
	return row

func _begin_capture(action: String) -> void:
	_capturing = action
	_capture_label.text = "Нажмите клавишу или кнопку для «%s» · ESC отменяет" % ACTION_NAMES[action]

func _end_capture() -> void:
	_capturing = ""
	_capture_label.text = ""
	refresh()

# Пока ждём назначение, событие перехватываем ДО обработки GUI: кнопка «НАЗНАЧИТЬ»
# остаётся в фокусе, а Enter и Space — это ещё и ui_accept, поэтому через
# _unhandled_input назначенный пробел нажимал бы кнопку снова, и захват никогда бы
# не закончился.
func _input(event: InputEvent) -> void:
	if _capturing == "": return
	if not event.is_pressed() or _is_echo(event): return
	_take(event)
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# Esc вне захвата закрывает сам экран: иначе из настроек, открытых из паузы, нельзя
	# выйти клавиатурой, а кнопка «ЗАКРЫТЬ» — единственный выход мыши под затемнением
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

# Перечитывает Settings и InputRouter: нужно и после сброса, и после смены языка
# раскладки, и при каждом открытии экрана.
func refresh() -> void:
	for n in _all_of("OptionButton"):
		var key := String(n.get_meta("key"))
		var vals: Array = n.get_meta("values")
		# сравнение вещественное: масштаб картинки — это 0.7/0.85/1.0, и int()
		# схлопнул бы первые два в один и тот же пункт
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
	_apply_tier()
	for action in _keys:
		(_keys[action] as Label).text = InputRouter.describe(action)

# Показывает только те строки, которые относятся к выбранному режиму. Делает это по
# meta, а не пересобирая страницу: пересборка унесла бы фокус с кнопки, на которой
# игрок стоит.
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

func _wide_label(text: String, w: float) -> Label:
	var l := _label(text, 15, DIM)
	l.custom_minimum_size = Vector2(w, 0)
	return l

func _note(text: String) -> Label:
	var l := _label(text, 13, NOTE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(840, 34)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _mono)
	b.add_theme_font_size_override("font_size", 16)
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	norm.set_border_width_all(1)
	norm.border_color = PANEL_LINE
	norm.set_corner_radius_all(5)
	norm.content_margin_left = 14; norm.content_margin_right = 14
	b.add_theme_stylebox_override("normal", norm)
	var sel := norm.duplicate() as StyleBoxFlat
	sel.bg_color = Color(0.17, 0.25, 0.34, 0.98)
	sel.border_color = ACCENT
	b.add_theme_stylebox_override("hover", sel)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", sel)
	return b

func _dim() -> Control:
	var d := ColorRect.new()
	d.color = Color(0.02, 0.03, 0.05, 0.78)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d

func _style(corner := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_LINE
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	return sb

func _font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Nimbus Mono PS", "Courier New", "monospace"])
	return f

func _label(text: String, size_px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l
