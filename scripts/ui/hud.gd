class_name HUD
extends CanvasLayer
# HUD в стиле технической телеметрии: тёмные панели с тонкой обводкой, моноширинные
# цифры, круговой спидометр с рисками и красной зоной, лог ударов, показания кузова.

signal menu_requested
signal resume_requested
signal restart_requested
signal settings_requested

const PANEL_BG := Color(0.045, 0.055, 0.075, 0.72)
const PANEL_LINE := Color(0.36, 0.46, 0.60, 0.55)
const DIM := Color(0.66, 0.73, 0.82)
const OK := Color(0.42, 0.88, 0.55)
const WARN := Color(0.96, 0.74, 0.24)
const BAD := Color(0.95, 0.32, 0.24)
const ACCENT := Color(0.45, 0.8, 0.95)
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
				draw_string(font, c + d * r * 0.68 - Vector2(14, -5), lbl, HORIZONTAL_ALIGNMENT_CENTER, 28, 13, Color(1, 1, 1, 0.55))
		var tt := clampf(speed / maxf(1.0, vmax), 0.0, 1.0)
		var col := OK.lerp(WARN, clampf(tt * 1.5, 0.0, 1.0)).lerp(BAD, clampf((tt - 0.72) / 0.28, 0.0, 1.0))
		if tt > 0.002:
			draw_arc(c, r, deg_to_rad(A0), deg_to_rad(A0 + SWEEP * tt), 96, col, 7.0)
		var na := deg_to_rad(A0 + SWEEP * tt)
		draw_line(c, c + Vector2(cos(na), sin(na)) * r * 0.80, Color(0.95, 0.96, 1.0, 0.9), 2.5)
		draw_circle(c, r * 0.055, accent)
		draw_arc(c, r * 0.14, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.0)

var _car: CarRig
var _mono: SystemFont
var _gauge: Gauge
var _speed_label: Label
var _kmh_label: Label
var _rows: Array[Label] = []
var _row_vals: Array[Label] = []
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
var _deform_full := 0.25
var _deform_area := Rect2(14, 192, 288, 8)
var _slip_area := Rect2(14, 218, 288, 8)
var _pause_panel: Control
var _pause_label: Label
var _run_stats: Label
var _buttons: Array[Button] = []
var _esc_hint: Label
var _start_ms := 0
var _prev_kmh := 0.0
var _g := 0.0
var _peak_g := 0.0
var _tip_until := 0
var _fps_avg := 60.0
var _fps_next := 0

func _mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Nimbus Mono PS", "Courier New", "monospace"])
	return f

func _ready() -> void:
	layer = 10
	_mono = _mono_font()
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

func _style(sb_corner := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_LINE
	sb.set_corner_radius_all(sb_corner)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	return sb

func _label(pos: Vector2, size_px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _row(panel: Control, y: float, title: String) -> Label:
	var t := _label(Vector2(14, y), 13, DIM)
	t.text = title
	panel.add_child(t)
	var v := _label(Vector2(0, y), 15)
	v.size = Vector2(panel.size.x - 28, 20)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(v)
	_rows.append(t); _row_vals.append(v)
	return v

func _build_speedo(root: Control) -> void:
	_gauge = Gauge.new()
	_gauge.font = _mono
	_gauge.position = Vector2(34, 606)
	_gauge.size = Vector2(250, 250)
	root.add_child(_gauge)
	_speed_label = _label(Vector2(34, 690), 52)
	_speed_label.size = Vector2(250, 62)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_speed_label)
	_kmh_label = _label(Vector2(34, 752), 14, DIM)
	_kmh_label.text = "КМ/Ч"
	_kmh_label.size = Vector2(250, 20)
	_kmh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_kmh_label)

func _build_telemetry(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(28, 28)
	panel.size = Vector2(316, 232)
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	var title := _label(Vector2(14, 10), 13, DIM)
	title.text = "ТЕЛЕМЕТРИЯ"
	panel.add_child(title)

	_row(panel, 38, "ПЕРЕГРУЗКА")
	_row(panel, 64, "ПИК ПЕРЕГРУЗКИ")
	_row(panel, 90, "ВМЯТИНЫ")
	_row(panel, 116, "МАКС. ГЛУБИНА")
	_row(panel, 142, "ГАБАРИТ ДЛИНЫ")
	var cap := _label(Vector2(14, 170), 13, DIM)
	cap.text = "КУЗОВ"
	panel.add_child(cap)
	var cap2 := _label(Vector2(14, 196), 13, DIM)
	cap2.text = "СЦЕПЛЕНИЕ"
	panel.add_child(cap2)
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
	panel.position = Vector2(1252, 28)
	panel.size = Vector2(320, 176)
	panel.add_theme_stylebox_override("panel", _style())
	root.add_child(panel)
	var title := _label(Vector2(14, 10), 13, DIM)
	title.text = "ЖУРНАЛ УДАРОВ"
	panel.add_child(title)
	_stat_top = _label(Vector2(14, 34), 20)
	_stat_top.text = "— км/ч"
	_stat_top.size = Vector2(292, 26)
	_stat_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_stat_top)
	var cap := _label(Vector2(14, 38), 12, DIM)
	cap.text = "ЛУЧШИЙ"
	panel.add_child(cap)
	_stat_count = _label(Vector2(14, 60), 13, DIM)
	_stat_count.text = "УДАРОВ: 0"
	panel.add_child(_stat_count)
	for i in 4:
		var l := _label(Vector2(14, 92 + i * 20), 14, Color(0.82, 0.86, 0.92))
		l.text = ""
		l.size = Vector2(292, 18)
		panel.add_child(l)
		_log_lines.append(l)

func _build_banners(root: Control) -> void:
	# никакого баннера «УДАР» поверх экрана: только подсказка и журнал в панели
	_tip_label = _label(Vector2(0, 596), 22, DIM)
	_tip_label.size = Vector2(1600, 32)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)

# Счётчик кадров в правом нижнем углу: там раньше была строка с раскладкой клавиш,
# которую игрок попросил убрать — подсказки о кнопках теперь живут в меню паузы.
func _build_fps(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(1312, 846)
	panel.size = Vector2(260, 40)
	panel.add_theme_stylebox_override("panel", _style(4))
	root.add_child(panel)
	_fps_label = _label(Vector2(14, 8), 16)
	_fps_label.size = Vector2(232, 24)
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
	var card := Panel.new()
	card.position = Vector2(520, 236)
	card.size = Vector2(560, 428)
	card.add_theme_stylebox_override("panel", _style(8))
	_pause_panel.add_child(card)
	_pause_label = _label(Vector2(0, 28), 42)
	_pause_label.text = "ПАУЗА"
	_pause_label.size = Vector2(560, 52)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_pause_label)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	rule.position = Vector2(150, 92)
	rule.size = Vector2(260, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)
	_run_stats = _label(Vector2(0, 104), 15, DIM)
	_run_stats.text = "В РЕЖИМЕ ОЖИДАНИЯ"
	_run_stats.size = Vector2(560, 24)
	_run_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_run_stats)
	var rows := [
		["ПРОДОЛЖИТЬ", _resume_cb],
		["НАСТРОЙКИ", _settings_cb],
		["ЗАПУСТИТЬ ЗАНОВО", _restart_cb],
		["В ГЛАВНОЕ МЕНЮ", _menu_cb],
	]
	for i in rows.size():
		var b := _button(rows[i][0] as String)
		b.position = Vector2(150, 146 + i * 66)
		b.size = Vector2(260, 54)
		(b.pressed as Signal).connect(rows[i][1] as Callable)
		card.add_child(b)
		_buttons.append(b)
	_esc_hint = _label(Vector2(0, 404), 13, Color(0.5, 0.56, 0.65))
	_esc_hint.text = "ESC — продолжить"
	_esc_hint.size = Vector2(560, 20)
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_esc_hint)

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	# FOCUS_ALL: без фокуса кнопка недоступна с геймпада и со стрелок, а меню паузы
	# именно этим и управляется
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _mono)
	b.add_theme_font_size_override("font_size", 19)
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	norm.set_border_width_all(1)
	norm.border_color = PANEL_LINE
	norm.set_corner_radius_all(5)
	norm.content_margin_left = 12; norm.content_margin_right = 12
	b.add_theme_stylebox_override("normal", norm)
	b.add_theme_stylebox_override("hover", _lit(norm, 0.16, 0.21, 0.28))
	var sel := _lit(norm, 0.17, 0.25, 0.34)
	sel.border_color = ACCENT
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", sel)
	return b

static func _lit(sb: StyleBoxFlat, r: float, g: float, bl: float) -> StyleBoxFlat:
	var s := sb.duplicate() as StyleBoxFlat
	s.bg_color = Color(r, g, bl, 0.98)
	s.border_color = Color(0.55, 0.7, 0.9, 0.9)
	return s

func bind(car: CarRig) -> void:
	_car = car
	_gauge.vmax = car.params.vmax_kmh * 1.05
	_gauge.accent = car.params.accent_color
	_deform_full = DentBody.MAX_DEPTH_RATIO * car.params.height
	_row_vals[4].text = "%.2f м" % car.params.length

func log_impact(kmh: float) -> void:
	_peak_g = 0.0
	var secs := (Time.get_ticks_msec() - _start_ms) / 1000
	_log.push_front("%02d:%02d   %3d км/ч" % [secs / 60, secs % 60, int(kmh)])
	if _log.size() > 4: _log.resize(4)
	for i in _log_lines.size():
		_log_lines[i].text = _log[i] if i < _log.size() else ""

func set_crash_stats(crashes: int, top: float) -> void:
	_stat_count.text = "УДАРОВ: %d" % crashes
	_stat_top.text = ("%d" % int(top)) if top > 0 else "—"

func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_label.visible = text != ""
	_tip_until = Time.get_ticks_msec() + 2500

func set_paused(v: bool) -> void:
	_pause_panel.visible = v
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
		_fps_label.get_parent().visible = v

func _process(dt: float) -> void:
	if _fps_label != null and _fps_label.visible:
		# сглаживаем по кадрам, а не по времени: рваная цифра 40/60/44 читается как сбой
		_fps_avg = lerpf(_fps_avg, 1.0 / maxf(dt, 1e-5), 0.06)
		var now := Time.get_ticks_msec()
		if now >= _fps_next:
			_fps_next = now + 250
			_fps_label.text = "%3d FPS · %.1f мс" % [int(round(_fps_avg)), 1000.0 / maxf(_fps_avg, 0.001)]
			_fps_label.modulate = OK if _fps_avg > 50.0 else (WARN if _fps_avg > 30.0 else BAD)
	if _car == null or _car.chassis == null: return
	var kmh := _car.speed_kmh()
	_speed_label.text = "%d" % int(kmh)
	_gauge.speed = kmh
	_gauge.queue_redraw()
	if dt > 0.0:
		var inst := (kmh - _prev_kmh) / 3.6 / dt / 9.81
		_g = lerpf(_g, clampf(inst, -3.0, 6.0), 0.25)
	_prev_kmh = kmh
	_peak_g = maxf(_peak_g, absf(_g))
	_row_vals[0].text = "%+.2f g" % _g
	_row_vals[0].modulate = BAD if absf(_g) > 1.5 else Color.WHITE
	_row_vals[1].text = "%.2f g" % _peak_g
	if _car.body != null:
		_row_vals[2].text = str(_car.body.dent_count)
		_row_vals[3].text = "%.3f м" % _car.body.max_depth
		var d: float = _car.body.max_depth
		if absf(d - _deform) > 1e-4:
			_deform = d
			var t: float = clampf(d / _deform_full, 0.0, 1.0)
			_deform_fill.size.x = maxf(0.0, (_deform_bg.size.x - 2.0) * t)
			_deform_fill.color = OK.lerp(WARN, clampf(t * 2.0, 0.0, 1.0)).lerp(BAD, clampf((t - 0.6) / 0.4, 0.0, 1.0))
	# Индикатор сцепления: полоса показывает, сколько шины ещё держат, и краснеет
	# раньше, чем занос становится виден по следам резины.
	var grip := 1.0 - _car.slip
	_slip_fill.size.x = maxf(0.0, (_slip_bg.size.x - 2.0) * grip)
	_slip_fill.color = BAD.lerp(WARN, clampf(grip * 2.0, 0.0, 1.0)).lerp(OK, clampf((grip - 0.5) * 2.0, 0.0, 1.0))
	if _tip_label.visible and _tip_until > 0 and Time.get_ticks_msec() > _tip_until:
		_tip_label.visible = false
