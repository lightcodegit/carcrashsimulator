class_name HUD
extends CanvasLayer
# HUD в стиле технической телеметрии: тёмные панели с тонкой обводкой, круговой
# спидометр с рисками и красной зоной, лог ударов, показания кузова. Шрифт — тот же,
# что в главном меню (UiTheme.sans_font), веса как в меню: заголовки 700, значения 700,
# подписи 500–600, циферблат 800.

signal menu_requested
signal resume_requested
signal restart_requested
signal settings_requested

const PANEL_BG := Color(0.045, 0.055, 0.075, 0.72)
const PANEL_LINE := UiTheme.LINE
const DIM := UiTheme.DIM
const OK := Color(0.42, 0.88, 0.55)
const WARN := Color(0.96, 0.74, 0.24)
const BAD := Color(0.95, 0.32, 0.24)
const ACCENT := UiTheme.AMBER
const A0 := 135.0        # начало дуги спидометра, градусы
const SWEEP := 270.0
# Предел шкалы кузова — не константа, а физический потолок вмятины этого кузова
# (MAX_DEPTH_RATIO · высота): с фиксированным 0.25 м шкала упиралась в 100% на
# первом же серьёзном ударе и переставала что-либо показывать.
const SLIP_FULL := 0.45      # доля бокового увода, при которой шин уже нет

class Gauge extends Control:
	var speed := 0.0
	var vmax := 220.0
	var font: Font
	var accent := Color(0.45, 0.8, 0.95)
	var nitro := 1.0             # доля бака форсажа
	var nitro_hot := false       # горит ли прямо сейчас

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c, r * 1.10, Color(0.03, 0.04, 0.06, 0.78))
		draw_arc(c, r * 1.08, 0, TAU, 96, Color(1, 1, 1, 0.10), 1.0)
		draw_arc(c, r, deg_to_rad(A0), deg_to_rad(A0 + SWEEP), 96, Color(1, 1, 1, 0.09), 7.0)
		draw_arc(c, r, deg_to_rad(A0 + SWEEP * 0.86), deg_to_rad(A0 + SWEEP), 32, Color(0.9, 0.25, 0.2, 0.42), 7.0)
		for k in 21:
			var t := float(k) / 20.0
			var a := deg_to_rad(A0 + SWEEP * t)
			var d := Vector2(cos(a), sin(a))
			var major := k % 5 == 0
			var inner := r * (0.86 if major else 0.92)
			draw_line(c + d * inner, c + d * r * 0.985, Color(1, 1, 1, 0.5 if major else 0.2), 2.0 if major else 1.0)
			if major and font != null:
				var lbl := str(int(round(vmax * t / 10.0) * 10))
				draw_string(font, c + d * r * 0.66 - Vector2(14, -5), lbl,
					HORIZONTAL_ALIGNMENT_CENTER, 28, 12, Color(1, 1, 1, 0.45))
		var tt := clampf(speed / maxf(1.0, vmax), 0.0, 1.0)
		# дуга в фирменном янтаре и «прогорает» к красному только у отсечки:
		# зелёно-жёлтый градиент остался от прежнего HUD и спорил с меню
		var col := ACCENT.lerp(BAD, clampf((tt - 0.78) / 0.22, 0.0, 1.0))
		if tt > 0.002:
			draw_arc(c, r, deg_to_rad(A0), deg_to_rad(A0 + SWEEP * tt), 96, col, 7.0)
			# метка текущего значения — точка на дуге. Стрелку через центр убрали: она
			# переходила через цифры, которые теперь стоят в нижней пустоте шкалы
			var na := deg_to_rad(A0 + SWEEP * tt)
			draw_circle(c + Vector2(cos(na), sin(na)) * r, 4.5, Color(1, 1, 1, 0.9))
		# Кольцо форсажа внутри шкалы: полное — бак полон, убывает на глазах, оранжевое —
		# газ подан и нитро горит. Отдельный виджет вешать некуда: спидометр уже занял
		# угол, а ресурс обязан быть виден без догадок.
		var a0 := deg_to_rad(A0)
		var nr := r * 0.78
		draw_arc(c, nr, a0, a0 + deg_to_rad(SWEEP), 96, Color(1, 1, 1, 0.10), 4.0)
		if nitro > 0.002:
			var ncol := Color(1.0, 0.55, 0.16, 0.95) if nitro_hot else accent
			draw_arc(c, nr, a0, a0 + deg_to_rad(SWEEP * clampf(nitro, 0.0, 1.0)), 96, ncol, 4.0)
		if font != null:
			# цифра скорости — внутри циферблата, в нижней пустоте дуги (шкала начинается на
			# 135° и кончается на 45°, снизу она разомкнута). Отдельная Label под циферблатом
			# ложилась ровно на стрелку и на сам круг.
			draw_string(font, c + Vector2(-70, r * 0.22), "%d" % int(speed),
				HORIZONTAL_ALIGNMENT_CENTER, 140, 44, Color(1, 1, 1, 0.95))
			draw_string(font, c + Vector2(-70, r * 0.22 + 46), "КМ/Ч",
				HORIZONTAL_ALIGNMENT_CENTER, 140, 12, DIM)
			draw_string(font, c + Vector2(-70, r * 1.14), "НИТРО",
				HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(1, 1, 1, 0.35))

var _car: CarRig
var _gauge: Gauge
var _rows: Array[Label] = []
var _v_peak: Label           # пик перегрузки за заезд
var _v_dents: Label          # сколько вмятин на кузове
var _v_deform: Label         # доля предельной вмятины, %
var _v_grip: Label           # сколько шины ещё держат, %
var _log_lines: Array[Label] = []
var _log: Array[String] = []
var _stat_top: Label
var _stat_count: Label
var _tip_label: Label
var _fps_label: Label
var _deform_bg: ColorRect
var _deform_fill: ColorRect
var _slip_bg: ColorRect
var _slip_fill: ColorRect
var _deform := 0.0
# Геймплейные панели гаснем на паузе: сводка уже есть в колонке паузы, а поверх
# них наводить мышь нечему — экран паузы должен быть чистым, как в BeamNG
var _gameplay: Array[Control] = []
var _fps_panel: Control = null
var _paused_ui := false
var _deform_full := 0.25
# Порядок строк telemetry-панели: заголовок, линейка акцента, две строки показаний,
# потом две подписанные шкалы. Все отступы кратны 6 px — панель читается колонкой.
var _deform_area := Rect2(14, 112, 272, 6)
var _slip_area := Rect2(14, 152, 272, 6)
var _pause_panel: Control
var _pause_label: Label
var _run_stats: Label
var _buttons: Array[Button] = []
var _start_ms := 0
var _prev_kmh := 0.0
var _g := 0.0
var _peak_g := 0.0
var _tip_until := 0
# Окно кадра считается по реальным тикам ОС: Process-delta масштабируется
# Engine.time_scale, и в слоу-мо EMA по 1/dt показывал троекратно завышенный FPS.
var _fps_avg := 60.0
var _fps_frames := 0
var _fps_win_ms := -1     # −1 = «окно ещё не открыто»: 0 был бы легальным тиком на старте

func _ready() -> void:
	layer = 10
	_start_ms = Time.get_ticks_msec()
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_speedo(root)
	_build_telemetry(root)
	_build_crash_log(root)
	_build_fps(root)
	_build_banners(root)
	_build_pause(root)

func _style(sb_corner := 10) -> StyleBoxFlat:
	# тот же язык, что у панелей меню: скругление 10, мягкая тень, тонкая обводка —
	# HUD и меню должны читаться одним интерфейсом
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_LINE
	sb.set_corner_radius_all(sb_corner)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	return sb

func _label(pos: Vector2, size_px: int, color: Color = Color.WHITE, weight := 500) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", UiTheme.sans_font(weight))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _row(panel: Control, y: float, title: String) -> Label:
	var t := _label(Vector2(14, y), 12, DIM, 600)
	t.text = title
	panel.add_child(t)
	var v := _label(Vector2(0, y - 2), 16, Color.WHITE, 700)
	v.size = Vector2(panel.size.x - 28, 22)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(v)
	_rows.append(t)
	return v

# Подпись шкалы слева и её процент справа, над самой полосой.
func _caption(panel: Control, y: float, title: String) -> Label:
	var v := _label(Vector2(0, y - 2), 12, DIM, 600)
	v.size = Vector2(panel.size.x - 28, 18)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(v)
	var t := _label(Vector2(14, y), 12, DIM, 600)
	t.text = title
	panel.add_child(t)
	return v

# Тонкая янтарная линейка под заголовком панели: тот же акцент, что в меню и
# навигации, — HUD обязан читаться частью одного интерфейса, а не отдельной темой.
func _rule(panel: Control, _accent: Color) -> void:
	var r := ColorRect.new()
	r.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	r.position = Vector2(14, 30)
	r.size = Vector2(panel.size.x - 28, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(r)

func _build_speedo(root: Control) -> void:
	_gauge = Gauge.new()
	_gauge.font = UiTheme.sans_font(800)
	_gauge.position = Vector2(28, 620)
	_gauge.size = Vector2(232, 232)
	root.add_child(_gauge)
	_gameplay.append(_gauge)

func _build_telemetry(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(24, 24)
	panel.size = Vector2(300, 164)
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	_gameplay.append(panel)
	var title := _label(Vector2(14, 8), 12, ACCENT, 700)
	title.text = "ТЕЛЕМЕТРИЯ"
	panel.add_child(title)
	_rule(panel, ACCENT)
	# Из панели убрано то, что не меняется в заезде или дублирует другое показание:
	# габарит длины (величина машины, читается один раз), максимальная глубина вмятины
	# — то же самое рассказывает шкала «кузов» — и текущая перегрузка: мигает на кочках,
	# а для аварии есть журнал ударов и пик.
	_v_peak = _row(panel, 42, "ПИК ПЕРЕГРУЗКИ")
	_v_dents = _row(panel, 68, "ВМЯТИНЫ")
	var cap := _caption(panel, 94, "КУЗОВ")
	var cap2 := _caption(panel, 134, "СЦЕПЛЕНИЕ")
	_v_deform = cap
	_v_grip = cap2
	# Шкала деформации кузова: доля глубины самой большой вмятины от предельной.
	# Показание «суммарного отклонения вершин» для этого не годится — там сотни метров
	# на сильный краш, и степень разрушения по нему не читается.
	# Два ColorRect вместо отрисовки: свой обработчик draw падает на null canvas_item,
	# когда панель уже выгружается вместе со сценой.
	_deform_fill = ColorRect.new()
	_deform_fill.color = OK
	_deform_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deform_fill.position = _deform_area.position
	_deform_fill.size = Vector2(0, _deform_area.size.y)
	panel.add_child(_deform_fill)
	_deform_bg = ColorRect.new()
	_deform_bg.color = Color(1, 1, 1, 0.09)
	_deform_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deform_bg.position = _deform_area.position - Vector2(1, 1)
	_deform_bg.size = _deform_area.size + Vector2(2, 2)
	panel.add_child(_deform_bg)
	panel.move_child(_deform_fill, panel.get_child_count() - 1)
	_slip_fill = ColorRect.new()
	_slip_fill.color = OK
	_slip_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slip_fill.position = _slip_area.position
	_slip_fill.size = Vector2(_slip_area.size.x, _slip_area.size.y)
	panel.add_child(_slip_fill)
	_slip_bg = ColorRect.new()
	_slip_bg.color = Color(1, 1, 1, 0.09)
	_slip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slip_bg.position = _slip_area.position - Vector2(1, 1)
	_slip_bg.size = _slip_area.size + Vector2(2, 2)
	panel.add_child(_slip_bg)
	panel.move_child(_slip_fill, panel.get_child_count() - 1)

func _build_crash_log(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(1276, 24)
	panel.size = Vector2(300, 160)
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	_gameplay.append(panel)
	var title := _label(Vector2(14, 8), 12, ACCENT, 700)
	title.text = "ЖУРНАЛ УДАРОВ"
	panel.add_child(title)
	_rule(panel, ACCENT)
	var cap := _label(Vector2(14, 42), 12, DIM, 600)
	cap.text = "ЛУЧШИЙ УДАР"
	panel.add_child(cap)
	_stat_top = _label(Vector2(0, 38), 20, Color.WHITE, 700)
	_stat_top.text = "—"
	_stat_top.size = Vector2(272, 26)
	_stat_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_stat_top)
	_stat_count = _label(Vector2(14, 68), 12, DIM, 600)
	_stat_count.text = "УДАРОВ: 0"
	panel.add_child(_stat_count)
	for i in 4:
		var l := _label(Vector2(14, 88 + i * 17), 13, Color(0.82, 0.86, 0.92))
		l.text = ""
		l.size = Vector2(272, 18)
		panel.add_child(l)
		_log_lines.append(l)

func _build_banners(root: Control) -> void:
	# никакого баннера «УДАР» поверх экрана: только подсказка и журнал в панели
	_tip_label = _label(Vector2(0, 596), 22, ACCENT, 600)
	_tip_label.size = Vector2(1600, 32)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)
	_gameplay.append(_tip_label)

# Счётчик кадров в правом нижнем углу: там раньше была строка с раскладкой клавиш,
# которую игрок попросил убрать — подсказки о кнопках теперь живут в меню паузы.
func _build_fps(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(1360, 852)
	panel.size = Vector2(216, 32)
	panel.add_theme_stylebox_override("panel", _style(8))
	root.add_child(panel)
	_fps_panel = panel
	_gameplay.append(panel)
	_fps_label = _label(Vector2(8, 6), 14, Color.WHITE, 600)
	_fps_label.size = Vector2(200, 20)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.text = "— FPS"
	panel.add_child(_fps_label)

func _build_pause(root: Control) -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	root.add_child(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# затемнение обязано съедать клики: иначе кнопка «В МЕНЮ» под overlay всё ещё
	# получает мышь, пока игра на паузе
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel.add_child(dim)
	# BeamNG-образная пауза: не карточка по центру поверх мира, а левая колонка —
	# мир за спиной остаётся видимым, список действий читается как главное меню
	var card := Panel.new()
	card.position = Vector2(48, 120)
	card.size = Vector2(380, 480)   # ровно под четыре строку меню: пустого хвоста быть не должно
	card.add_theme_stylebox_override("panel", _style(8))
	_pause_panel.add_child(card)
	_pause_label = _label(Vector2(24, 24), 40, Color.WHITE, 800)
	_pause_label.text = "ПАУЗА"
	_pause_label.size = Vector2(332, 52)
	card.add_child(_pause_label)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	rule.position = Vector2(24, 88)
	rule.size = Vector2(200, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)
	_run_stats = _label(Vector2(24, 102), 14, DIM)
	_run_stats.text = "В РЕЖИМЕ ОЖИДАНИЯ"
	_run_stats.size = Vector2(332, 60)
	_run_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_run_stats)
	var rows := [
		["ПРОДОЛЖИТЬ", _resume_cb],
		["НАСТРОЙКИ", _settings_cb],
		["ЗАПУСТИТЬ ЗАНОВО", _restart_cb],
		["В ГЛАВНОЕ МЕНЮ", _menu_cb],
	]
	for i in rows.size():
		var b := _button(rows[i][0] as String)
		b.position = Vector2(24, 196 + i * 64)
		b.size = Vector2(332, 56)
		(b.pressed as Signal).connect(rows[i][1] as Callable)
		card.add_child(b)
		_buttons.append(b)

func _button(text: String) -> Button:
	# плоская строка как в навигации меню: янтарная полоса слева на фокусе/наведении
	var b := UiTheme.nav_item(text)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	return b

func bind(car: CarRig) -> void:
	_car = car
	# Шкала спидометра обязана быть конечной: у машины без потолка скорости
	# стрелка всё равно должна иметь куда доезжать.
	_gauge.vmax = (car.params.vmax_kmh * 1.05) if is_finite(car.params.vmax_kmh) else 600.0
	_gauge.accent = car.params.accent_color
	_deform_full = DentBody.MAX_DEPTH_RATIO * car.params.height

func log_impact(kmh: float) -> void:
	var secs := (Time.get_ticks_msec() - _start_ms) / 1000
	_log.push_front("%02d:%02d   %3d км/ч" % [secs / 60, secs % 60, int(kmh)])
	if _log.size() > 4: _log.resize(4)
	for i in _log_lines.size():
		_log_lines[i].text = _log[i] if i < _log.size() else ""

# Пик держим за всю попытку (подпись «ПИК ПЕРЕГРУЗКИ»): сбрасываем его только на
# новом заезде, а не на каждом ударе, иначе шкала показывала бы максимум между
# двумя авариями, а не худший перегрузок заезда.
func reset_run() -> void:
	_peak_g = 0.0
	_g = 0.0
	_prev_kmh = 0.0
	_start_ms = Time.get_ticks_msec()

func set_crash_stats(crashes: int, top: float) -> void:
	_stat_count.text = "УДАРОВ: %d" % crashes
	_stat_top.text = ("%d км/ч" % int(top)) if top > 0 else "—"
	_stat_top.add_theme_color_override("font_color", ACCENT if top > 0 else Color.WHITE)

func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_label.visible = text != ""
	_tip_until = Time.get_ticks_msec() + 2500

func set_paused(v: bool) -> void:
	_pause_panel.visible = v
	_paused_ui = v
	for c in _gameplay:
		c.visible = not v
	if v and not _buttons.is_empty():
		_buttons[0].grab_focus()

func set_run_stats(text: String) -> void:
	_run_stats.text = text

# Кнопки меню паузы наружу нужны тестам и внешним экранам: искать их по тексту,
# а не по индексу, — иначе любой порядок кнопок ломает чужой код.
func pause_button(label: String) -> Button:
	for b in _buttons:
		if b.text == label: return b
	return null

func _resume_cb() -> void: resume_requested.emit()
func _settings_cb() -> void: settings_requested.emit()
func _restart_cb() -> void: restart_requested.emit()
func _menu_cb() -> void: menu_requested.emit()

# Счётчик кадров включается настройкой: на слабом GPU сам факт отрисовки панели —
# лишняя работа, которую игрок вправе отключить.
func set_fps_visible(v: bool) -> void:
	if _fps_label != null:
		_fps_label.visible = v
		# на паузе панель счётчика остаётся спрятанной, пока настройка не применена вне паузы
		if _fps_panel != null: _fps_panel.visible = v and not _paused_ui

func _process(dt: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_frames += 1
		var now := Time.get_ticks_msec()
		if _fps_win_ms < 0: _fps_win_ms = now
		var span := now - _fps_win_ms
		# окно в реальных мс, счёт кадров в нём: dt из _process домножен на
		# Engine.time_scale, и в слоу-мо прежний EMA завышал кадры втрое.
		# Закрытие по 30 кадрам — страховка для режимов, где 250 мс реального
		# времени не настаивают и к моменту чтения счётчик молчал бы «— FPS»
		if span >= 250 or _fps_frames >= 30:
			_fps_avg = _fps_frames * 1000.0 / maxf(float(span), 1.0)
			_fps_frames = 0
			_fps_win_ms = now
			_fps_label.text = "%3d FPS · %.1f мс" % [int(round(_fps_avg)), 1000.0 / maxf(_fps_avg, 0.001)]
			_fps_label.modulate = OK if _fps_avg > 50.0 else (WARN if _fps_avg > 30.0 else BAD)
	if _car == null or _car.chassis == null: return
	var kmh := _car.speed_kmh()
	_gauge.speed = kmh
	_gauge.nitro = _car.nitro_fraction()
	_gauge.nitro_hot = _car.nitro_active
	_gauge.queue_redraw()
	if dt > 0.0:
		var inst := (kmh - _prev_kmh) / 3.6 / dt / 9.81
		_g = lerpf(_g, clampf(inst, -3.0, 6.0), 0.25)
	_prev_kmh = kmh
	# Текущую перегрузку на панель не выносим: она дёргается на каждой кочке, а игрок
	# читает по ней только одно — была ли авария. Для аварии есть пик и журнал.
	_peak_g = maxf(_peak_g, absf(_g))
	_v_peak.text = "%.2f g" % _peak_g
	_v_peak.modulate = BAD if _peak_g > 3.0 else Color.WHITE
	if _car.body != null:
		_v_dents.text = str(_car.body.dent_count)
		var d: float = _car.body.max_depth
		var t: float = clampf(d / _deform_full, 0.0, 1.0)
		_v_deform.text = "%d%%" % int(round(t * 100.0))
		if absf(d - _deform) > 1e-4:
			_deform = d
			_deform_fill.size.x = maxf(0.0, (_deform_bg.size.x - 2.0) * t)
			_deform_fill.color = OK.lerp(WARN, clampf(t * 2.0, 0.0, 1.0)).lerp(BAD, clampf((t - 0.6) / 0.4, 0.0, 1.0))
	# Индикатор сцепления: полоса показывает, сколько шины ещё держат, и краснеет
	# раньше, чем занос становится виден по следам резины.
	var grip := 1.0 - _car.slip
	_v_grip.text = "%d%%" % int(round(clampf(grip, 0.0, 1.0) * 100.0))
	_slip_fill.size.x = maxf(0.0, (_slip_bg.size.x - 2.0) * grip)
	_slip_fill.color = BAD.lerp(WARN, clampf(grip * 2.0, 0.0, 1.0)).lerp(OK, clampf((grip - 0.5) * 2.0, 0.0, 1.0))
	if _tip_label.visible and _tip_until > 0 and Time.get_ticks_msec() > _tip_until:
		_tip_label.visible = false
