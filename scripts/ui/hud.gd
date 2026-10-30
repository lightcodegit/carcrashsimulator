class_name HUD
extends CanvasLayer
# HUD в стиле технической телеметрии: тёмные панели с тонкой обводкой, моноширинные
# цифры, круговой спидометр с рисками и красной зоной, лог ударов, показания кузова.

signal menu_requested

const PANEL_BG := Color(0.045, 0.055, 0.075, 0.72)
const PANEL_LINE := Color(0.36, 0.46, 0.60, 0.55)
const DIM := Color(0.66, 0.73, 0.82)
const OK := Color(0.42, 0.88, 0.55)
const WARN := Color(0.96, 0.74, 0.24)
const BAD := Color(0.95, 0.32, 0.24)
const A0 := 135.0        # начало дуги спидометра, градусы
const SWEEP := 270.0

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
var _crash_label: Label
var _crash_until := 0
var _log_lines: Array[Label] = []
var _log: Array[String] = []
var _stat_top: Label
var _stat_count: Label
var _tip_label: Label
var _pause_panel: Control
var _pause_label: Label
var _menu_button: Button
var _esc_hint: Label
var _start_ms := 0
var _prev_kmh := 0.0
var _g := 0.0
var _peak_g := 0.0
var _tip_until := 0

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
	panel.size = Vector2(316, 176)
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
	_crash_label = _label(Vector2(0, 132), 46)
	_crash_label.size = Vector2(1600, 62)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.modulate = WARN
	_crash_label.visible = false
	root.add_child(_crash_label)
	_tip_label = _label(Vector2(0, 596), 22, DIM)
	_tip_label.size = Vector2(1600, 32)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)
	var hints := _label(Vector2(0, 862), 14, Color(0.6, 0.67, 0.76))
	hints.text = "W/S ГАЗ·ТОРМОЗ   A/D РУЛЬ   SPACE РУЧНИК   SHIFT СЛОУ-МО   C КАМЕРА   R РЕСТАРТ   ESC ПАУЗА"
	hints.size = Vector2(1600, 24)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hints)

func _build_pause(root: Control) -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	root.add_child(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_panel.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(560, 330)
	card.size = Vector2(480, 250)
	card.add_theme_stylebox_override("panel", _style(8))
	_pause_panel.add_child(card)
	_pause_label = _label(Vector2(0, 34), 44)
	_pause_label.text = "ПАУЗА"
	_pause_label.size = Vector2(480, 56)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_pause_label)
	_esc_hint = _label(Vector2(0, 96), 15, DIM)
	_esc_hint.text = "ESC — продолжить"
	_esc_hint.size = Vector2(480, 24)
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_esc_hint)
	_menu_button = Button.new()
	_menu_button.text = "В МЕНЮ"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.add_theme_font_override("font", _mono)
	_menu_button.add_theme_font_size_override("font_size", 20)
	_menu_button.position = Vector2(140, 148)
	_menu_button.size = Vector2(200, 58)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	flat.set_border_width_all(1)
	flat.border_color = PANEL_LINE
	flat.set_corner_radius_all(5)
	_menu_button.add_theme_stylebox_override("normal", flat)
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.21, 0.28, 0.98)
	hover.border_color = Color(0.55, 0.7, 0.9, 0.9)
	_menu_button.add_theme_stylebox_override("hover", hover)
	_menu_button.add_theme_stylebox_override("pressed", hover)
	_menu_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	card.add_child(_menu_button)

func bind(car: CarRig) -> void:
	_car = car
	_gauge.vmax = car.params.vmax_kmh * 1.05
	_gauge.accent = car.params.accent_color
	_row_vals[4].text = "%.2f м" % car.params.length

func show_crash(kmh: float) -> void:
	_crash_label.text = "УДАР  %d КМ/Ч" % int(kmh)
	_crash_label.visible = true
	_crash_until = Time.get_ticks_msec() + 2200
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

func _process(dt: float) -> void:
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
	if _crash_label.visible and Time.get_ticks_msec() > _crash_until:
		_crash_label.visible = false
	if _tip_label.visible and _tip_until > 0 and Time.get_ticks_msec() > _tip_until:
		_tip_label.visible = false
