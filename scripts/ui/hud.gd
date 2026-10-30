class_name HUD
extends CanvasLayer

class Gauge extends Control:
	var speed := 0.0
	var vmax := 220.0
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r * 1.04, Color(0.05, 0.06, 0.08, 0.55))
		draw_arc(c, r, deg_to_rad(135), deg_to_rad(405), 72, Color(1, 1, 1, 0.18), r * 0.14)
		var t := clampf(speed / vmax, 0.0, 1.0)
		var a1 := deg_to_rad(135.0 + 270.0 * t)
		var col := Color(0.45, 0.9, 0.5).lerp(Color(1.0, 0.35, 0.18), t)
		if t > 0.001:
			draw_arc(c, r, deg_to_rad(135), a1, 56, col, r * 0.14)
		for k in 9:
			var ta := deg_to_rad(135.0 + 270.0 * k / 8.0)
			var d := Vector2(cos(ta), sin(ta))
			draw_line(c + d * r * 0.80, c + d * r * 0.90, Color(1, 1, 1, 0.5), 2.0)
		draw_line(c, c + Vector2(cos(a1), sin(a1)) * r * 0.72, Color(1, 0.92, 0.8), 3.0)

var _car: CarRig
var _damage: DamageModel
var _gauge: Gauge
var _speed_label: Label
var _kmh_label: Label
var _crash_label: Label
var _crash_until := 0
var _bars: Array[ProgressBar] = []
var _totaled_label: Label
var _tip_label: Label
var _tip_until := 0
var _pause_label: Label
var _stat_top: Label
var _stat_count: Label

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_gauge = Gauge.new()
	_gauge.position = Vector2(28, 630)
	_gauge.size = Vector2(230, 230)
	root.add_child(_gauge)
	_speed_label = _label(Vector2(28, 705), 44)
	_speed_label.size = Vector2(230, 60)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_speed_label)
	_kmh_label = _label(Vector2(28, 757), 16)
	_kmh_label.text = "км/ч"
	_kmh_label.size = Vector2(230, 24)
	_kmh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kmh_label.modulate = Color(0.75, 0.8, 0.85)
	root.add_child(_kmh_label)
	var panel := Panel.new()
	panel.position = Vector2(28, 28)
	panel.size = Vector2(250, 170)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.55)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var names := ["REAR", "L", "R", "ROOF", "F"]
	for i in 5:
		var l := _label(Vector2(14, 12 + i * 30), 13)
		l.text = names[i]
		l.size = Vector2(44, 26)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(l)
		var b := ProgressBar.new()
		b.min_value = 0; b.max_value = 100
		b.position = Vector2(64, 16 + i * 30)
		b.size = Vector2(165, 16)
		b.value = 100
		b.show_percentage = false
		panel.add_child(b)
		_bars.append(b)
	_stat_top = _label(Vector2(1270, 28), 20)
	_stat_top.text = "ЛУЧШИЙ УДАР: —"
	_stat_top.size = Vector2(300, 30)
	_stat_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_stat_top)
	_stat_count = _label(Vector2(1270, 58), 16)
	_stat_count.text = "УДАРОВ: 0"
	_stat_count.size = Vector2(300, 24)
	_stat_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stat_count.modulate = Color(0.75, 0.8, 0.85)
	root.add_child(_stat_count)
	_crash_label = _label(Vector2(0, 140), 40)
	_crash_label.size = Vector2(1600, 60)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.modulate = Color(1, 0.85, 0.2)
	_crash_label.visible = false
	root.add_child(_crash_label)
	_totaled_label = _label(Vector2(0, 220), 46)
	_totaled_label.size = Vector2(1600, 60)
	_totaled_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_totaled_label.text = "TOTALLED"
	_totaled_label.modulate = Color(1, 0.25, 0.2)
	_totaled_label.visible = false
	root.add_child(_totaled_label)
	_tip_label = _label(Vector2(0, 610), 26)
	_tip_label.size = Vector2(1600, 40)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)
	var hints := _label(Vector2(0, 856), 17)
	hints.text = "W/S газ/тормоз · A/D руль · Space ручник · Shift слоу-мо · C камера · R рестарт · Esc меню"
	hints.size = Vector2(1600, 30)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.modulate = Color(0.75, 0.8, 0.85, 0.9)
	root.add_child(hints)
	_pause_label = _label(Vector2(0, 400), 52)
	_pause_label.text = "ПАУЗА · Esc — продолжить"
	_pause_label.size = Vector2(1600, 70)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.visible = false
	root.add_child(_pause_label)

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l

func bind(car: CarRig, damage: DamageModel) -> void:
	_car = car; _damage = damage
	_gauge.vmax = car.params.vmax_kmh * 1.1
	damage.totaled_changed.connect(func(t: bool): _totaled_label.visible = t)

func show_crash(kmh: float) -> void:
	_crash_label.text = "УДАР %d км/ч" % int(kmh)
	_crash_label.visible = true
	_crash_until = Time.get_ticks_msec() + 2500

func set_crash_stats(crashes: int, top: float) -> void:
	_stat_count.text = "УДАРОВ: %d" % crashes
	_stat_top.text = ("ЛУЧШИЙ УДАР: %d км/ч" % int(top)) if top > 0 else "ЛУЧШИЙ УДАР: —"

func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_label.visible = text != ""
	_tip_until = Time.get_ticks_msec() + 2500

func set_paused(v: bool) -> void:
	_pause_label.visible = v

func _process(_dt: float) -> void:
	if _car == null: return
	var kmh := _car.speed_kmh()
	_speed_label.text = "%d" % int(kmh)
	_gauge.speed = kmh
	_gauge.queue_redraw()
	if _crash_label.visible and Time.get_ticks_msec() > _crash_until:
		_crash_label.visible = false
	if _tip_label.visible and _tip_until > 0 and Time.get_ticks_msec() > _tip_until:
		_tip_label.visible = false
	if _damage != null:
		var hpz := _damage.hp_array()
		for i in 5:
			_bars[i].value = hpz[i]
			_bars[i].modulate = Color(0.3, 0.9, 0.4) if hpz[i] > 55 else (Color(0.95, 0.7, 0.2) if hpz[i] > 25 else Color(0.9, 0.25, 0.2))
