class_name HUD
extends CanvasLayer

var _car: CarRig
var _damage: DamageModel
var _speed_label: Label
var _crash_label: Label
var _crash_until := 0
var _bars: Array[ProgressBar] = []
var _totaled_label: Label
var _tip_label: Label
var _pause_label: Label

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_speed_label = _label(Vector2(30, 30), 42)
	root.add_child(_speed_label)
	_crash_label = _label(Vector2(0, 120), 34)
	_crash_label.size = Vector2(1600, 50)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.modulate = Color(1, 0.85, 0.2)
	_crash_label.visible = false
	root.add_child(_crash_label)
	_totaled_label = _label(Vector2(0, 200), 40)
	_totaled_label.size = Vector2(1600, 60)
	_totaled_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_totaled_label.text = "TOTALLED"
	_totaled_label.modulate = Color(1, 0.25, 0.2)
	_totaled_label.visible = false
	root.add_child(_totaled_label)
	var hints := _label(Vector2(30, 820), 18)
	hints.text = "W/S газ/тормоз · A/D руль · Space ручник · Shift слоу-мо · C камера · R рестарт · Esc меню"
	root.add_child(hints)
	_tip_label = _label(Vector2(0, 700), 26)
	_tip_label.size = Vector2(1600, 40)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.visible = false
	root.add_child(_tip_label)
	_pause_label = _label(Vector2(600, 400), 48)
	_pause_label.text = "ПАУЗА (Esc)"
	_pause_label.visible = false
	root.add_child(_pause_label)
	var names := ["REAR", "L", "R", "ROOF", "F"]
	for i in 5:
		var b := ProgressBar.new()
		b.min_value = 0; b.max_value = 100
		b.custom_minimum_size = Vector2(150, 14)
		b.position = Vector2(30, 130 + i * 22)
		b.value = 100
		b.show_percentage = false
		var l := _label(Vector2(185, 126 + i * 22), 14)
		l.text = names[i]
		root.add_child(l); root.add_child(b)
		_bars.append(b)

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l

func bind(car: CarRig, damage: DamageModel) -> void:
	_car = car; _damage = damage
	damage.totaled_changed.connect(func(t: bool): _totaled_label.visible = t)

func show_crash(kmh: float) -> void:
	_crash_label.text = "CRASH @ %d км/ч" % int(kmh)
	_crash_label.visible = true
	_crash_until = Time.get_ticks_msec() + 2500

func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_label.visible = true

func set_paused(v: bool) -> void:
	_pause_label.visible = v

func _process(_dt: float) -> void:
	if _car == null: return
	_speed_label.text = "%d км/ч" % int(_car.speed_kmh())
	if _crash_label.visible and Time.get_ticks_msec() > _crash_until:
		_crash_label.visible = false
	if _damage != null:
		var hpz := _damage.hp_array()
		for i in 5:
			_bars[i].value = hpz[i]
			_bars[i].modulate = Color(0.3, 0.9, 0.4) if hpz[i] > 55 else (Color(0.95, 0.7, 0.2) if hpz[i] > 25 else Color(0.9, 0.25, 0.2))
