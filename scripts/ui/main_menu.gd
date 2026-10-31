extends Control
# Главное меню в телеметрическом стиле: тёмные панели с тонкой обводкой, моноширинный
# шрифт, живой 3D-превью выбранной машины и её спецификация.

const CARS := [
	["СЕДАН", "sedan", "Сбалансированный седан · 160 км/ч · 1300 кг\nСредняя жёсткость кузова — честная классика краш-тестов."],
	["ПИКАП", "pickup", "Тяжёлый пикап · 140 км/ч · 1900 кг\nКузов держит удар, который ломает остальных."],
	["СПОРТКАР", "sport", "Хрупкий спорткар · 210 км/ч · 1050 кг\nБыстрый и низкий: мнётся глубоко и эффектно."],
]
const MAPS := [
	["АРЕНА", "arena", "Испытательный полигон: стены, столбы, отбойники,\nрампа 13°, конусы и краш-блок."],
	["ГОРОДОК", "town", "Кварталы зданий, деревья, фонари, припаркованные\nмашины. Узкие улицы — боковые удары и рикошеты."],
	["ТРАССА", "speedway", "600 метров разгона и бетонная стена на финише.\nДля максимального лобового краш-теста."],
]
const PANEL_BG := Color(0.045, 0.055, 0.075, 0.80)
const PANEL_LINE := Color(0.36, 0.46, 0.60, 0.55)
const DIM := Color(0.66, 0.73, 0.82)
const ACCENT := Color(0.45, 0.8, 0.95)

var _mono: SystemFont
var _pivot: Node3D
var _car_node: Node3D
var _spec: Label
var _car_opts: OptionButton
var _map_opts: OptionButton
var _preview_name: Label

func _mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Nimbus Mono PS", "Courier New", "monospace"])
	return f

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mono = _mono_font()
	add_child(_background())
	add_child(_header())
	_build_selectors()
	_build_preview()
	_build_footer()
	_car_opts.grab_focus()

func _style(corner := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_LINE
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	return sb

func _label(pos: Vector2, size_px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _background() -> Control:
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.085, 0.10, 0.135), Color(0.022, 0.028, 0.04)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.62, 0.28)
	gt.fill_to = Vector2(0.62, 1.35)
	gt.width = 128; gt.height = 128
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid := Control.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(func() -> void:
		for x in range(0, 1601, 80):
			grid.draw_line(Vector2(x, 0), Vector2(x, 900), Color(1, 1, 1, 0.022), 1.0)
		for y in range(0, 901, 80):
			grid.draw_line(Vector2(0, y), Vector2(1600, y), Color(1, 1, 1, 0.022), 1.0))
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(grad)
	host.add_child(grid)
	return host

func _header() -> Control:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label(Vector2(90, 52), 54)
	t.text = "CAR CRASH SIMULATOR"
	host.add_child(t)
	var s := _label(Vector2(92, 122), 15, DIM)
	s.text = "ПЕСОЧНИЦА АВТОКАТАСТРОФ · ВМЯТИНЫ БЕЗ ПРУЖИН · 3 МАШИНЫ · 3 КАРТЫ"
	host.add_child(s)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	rule.position = Vector2(92, 158)
	rule.size = Vector2(620, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(rule)
	return host

func _build_selectors() -> void:
	var car_panel := _card("МАШИНА", Vector2(90, 196), Vector2(620, 176))
	_car_opts = _selector(CARS, Vector2(20, 48), car_panel.size.x - 40)
	car_panel.add_child(_car_opts)
	var car_desc := _desc(car_panel.size.x - 40)
	car_panel.add_child(car_desc)
	_wire(_car_opts, CARS, car_desc, true)
	var map_panel := _card("КАРТА", Vector2(90, 392), Vector2(620, 176))
	_map_opts = _selector(MAPS, Vector2(20, 48), map_panel.size.x - 40)
	map_panel.add_child(_map_opts)
	var map_desc := _desc(map_panel.size.x - 40)
	map_panel.add_child(map_desc)
	_wire(_map_opts, MAPS, map_desc, false)

func _card(title_text: String, pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = sz
	panel.add_theme_stylebox_override("panel", _style())
	add_child(panel)
	var t := _label(Vector2(18, 14), 13, DIM)
	t.text = title_text
	panel.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	rule.position = Vector2(18, 38)
	rule.size = Vector2(sz.x - 36, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rule)
	return panel

func _selector(items: Array, pos: Vector2, w: float) -> OptionButton:
	var opt := OptionButton.new()
	opt.position = pos
	opt.size = Vector2(w, 46)
	opt.add_theme_font_override("font", _mono)
	opt.add_theme_font_size_override("font_size", 20)
	for it in items:
		opt.add_item(it[0])
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.09, 0.11, 0.15, 0.95)
	norm.set_border_width_all(1)
	norm.border_color = PANEL_LINE
	norm.set_corner_radius_all(4)
	norm.content_margin_left = 14
	opt.add_theme_stylebox_override("normal", norm)
	opt.add_theme_stylebox_override("hover", norm)
	var pressed := norm.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.19, 0.26, 0.98)
	pressed.border_color = ACCENT
	opt.add_theme_stylebox_override("pressed", pressed)
	opt.add_theme_stylebox_override("focus", pressed)
	return opt

func _desc(w: float) -> RichTextLabel:
	var d := RichTextLabel.new()
	d.position = Vector2(20, 104)
	d.size = Vector2(w, 60)
	d.add_theme_font_override("normal_font", _mono)
	d.add_theme_font_size_override("normal_font_size", 14)
	d.add_theme_color_override("default_color", Color(0.80, 0.85, 0.92))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.fit_content = true
	d.bbcode_enabled = true
	d.scroll_active = false
	return d

func _wire(opt: OptionButton, items: Array, desc: RichTextLabel, is_car: bool) -> void:
	var refresh := func(idx: int) -> void:
		var parts: Array = (items[idx][2] as String).split("\n")
		desc.text = parts[0]
		if parts.size() > 1:
			desc.text += "\n[color=#7d8a9c]" + parts[1] + "[/color]"
	opt.item_selected.connect(func(i: int) -> void:
		refresh.call(i)
		if is_car: _load_car(CARS[i][1])
	)
	refresh.call(0)

func _build_preview() -> void:
	var panel := Panel.new()
	panel.position = Vector2(760, 196)
	panel.size = Vector2(750, 512)
	panel.add_theme_stylebox_override("panel", _style(6))
	add_child(panel)
	var t := _label(Vector2(18, 14), 13, DIM)
	t.text = "ПРЕВЬЮ МОДЕЛИ"
	panel.add_child(t)
	_preview_name = _label(Vector2(0, 13), 15, ACCENT)
	_preview_name.size = Vector2(panel.size.x - 20, 20)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_preview_name)
	var sv := SubViewport.new()
	sv.size = Vector2i(714, 356)
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_4X
	panel.add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	sv.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, -32, 0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 150, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.72, 0.82, 1.0)
	sv.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 3.2, -3.6)
	rim.omni_range = 9.0
	rim.light_color = ACCENT
	rim.light_energy = 0.55
	sv.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.08, 0.10)
	fm.roughness = 0.35
	fm.metallic = 0.4
	pm.material = fm
	floor_mi.mesh = pm
	sv.add_child(floor_mi)
	_pivot = Node3D.new()
	sv.add_child(_pivot)
	var cam := Camera3D.new()
	cam.fov = 38.0
	# look_at_from_position: обычный look_at требует узел уже в дереве
	cam.look_at_from_position(Vector3(4.6, 2.35, 5.4), Vector3(0, 0.72, 0), Vector3.UP)
	sv.add_child(cam)
	var rect := TextureRect.new()
	rect.texture = sv.get_texture()
	rect.position = Vector2(18, 44)
	rect.size = Vector2(714, 356)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rect)
	_spec = _label(Vector2(18, 412), 14, Color(0.84, 0.88, 0.94))
	_spec.size = Vector2(714, 88)
	panel.add_child(_spec)
	_load_car(CARS[0][1])

func _load_car(id: String) -> void:
	var p: VehicleParams = VehicleDB.get_params(id)
	if p == null: return
	if _car_node != null and is_instance_valid(_car_node):
		_pivot.remove_child(_car_node)
		_car_node.queue_free()
	var ps: PackedScene = load(p.model)
	if ps == null: return
	_car_node = ps.instantiate()
	_pivot.add_child(_car_node)
	var a: AABB = DentBody.measure(p.model).aabb
	var s := 2.6 / maxf(0.001, a.size.z)          # нормируем длину модели в превью
	Materials.apply_tree(_car_node, "car")
	_car_node.scale = Vector3.ONE * s
	_car_node.position = Vector3(-a.get_center().x * s, -a.position.y * s, -a.get_center().z * s)
	_preview_name.text = id.to_upper()
	_spec.text = "МАССА %d кг     МАКС %d км/ч     РАЗГОН %.1f м/с²\nДЛИНА %.2f м     ШИРИНА %.2f м     ВЫСОТА %.2f м\nТОРМОЗ %.1f м/с²     РУЛЬ %.0f °/с     СЦЕПЛЕНИЕ %.1f" % [
		int(p.mass), int(p.vmax_kmh), p.accel_max, p.length, p.width, p.height,
		p.brake_decel, p.steer_rate_deg, p.grip]

func _build_footer() -> void:
	var start := Button.new()
	start.text = "ЗАПУСК СИМУЛЯЦИИ"
	start.add_theme_font_override("font", _mono)
	start.add_theme_font_size_override("font_size", 24)
	start.position = Vector2(90, 610)
	start.size = Vector2(620, 76)
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.10, 0.17, 0.24, 0.96)
	norm.set_border_width_all(1)
	norm.border_color = ACCENT
	norm.set_corner_radius_all(5)
	start.add_theme_stylebox_override("normal", norm)
	var hover := norm.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.28, 0.38, 1.0)
	start.add_theme_stylebox_override("hover", hover)
	start.add_theme_stylebox_override("pressed", hover)
	start.add_theme_stylebox_override("focus", hover)
	start.pressed.connect(_start)
	add_child(start)
	var hint := _label(Vector2(90, 706), 14, DIM)
	hint.text = "WASD/СТРЕЛКИ · SPACE РУЧНИК · SHIFT СЛОУ-МО · C КАМЕРА · R РЕСТАРТ · ESC ПАУЗА · ГЕЙМПАД"
	hint.size = Vector2(620, 24)
	add_child(hint)
	var ver := _label(Vector2(760, 730), 13, Color(0.45, 0.52, 0.62))
	ver.text = "МОДЕЛИ: KENNEY CAR KIT 3.1 · CC0"
	ver.size = Vector2(750, 22)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)

func _start() -> void:
	GameContext.select(CARS[_car_opts.selected][1], MAPS[_map_opts.selected][1])
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _process(dt: float) -> void:
	if _pivot != null:
		_pivot.rotation.y += dt * 0.45
