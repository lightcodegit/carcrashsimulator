extends Control

const CARS := [
	["Седан", "sedan", "Сбалансированный седан · 160 км/ч · 1300 кг\nСредняя прочность — честная классика краш-тестов."],
	["Пикап", "pickup", "Тяжёлый пикап · 140 км/ч · 1900 кг\nКузов крепче всех: держит удар, который убивает других."],
	["Спорткар", "sport", "Хрупкий спорткар · 210 км/ч · 1050 кг\nБыстрый и нежный: сминается эффектно и домино."],
]
const MAPS := [
	["Арена", "arena", "Испытательный полигон: бетонные стены, столбы,\nотбойники, рампа 22° и краш-блоки на трассе."],
	["Городок", "town", "Кварталы зданий, фонари, припаркованные машины.\nУзкие улицы — боковые удары и рикошеты."],
	["Трасса", "speedway", "600 метров разгона и бетонная стена на финише.\nДля максимального лобового краш-теста."],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.10, 0.12, 0.16), Color(0.04, 0.05, 0.07)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.25); gt.fill_to = Vector2(0.5, 1.2)
	gt.width = 64; gt.height = 64
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grad)
	var title := Label.new()
	title.text = "CAR CRASH SIMULATOR"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 70)
	title.size = Vector2(1600, 90)
	add_child(title)
	var sub := Label.new()
	sub.text = "краш-песочница · мягкая деформация кузова · 3 машины · 3 карты"
	sub.add_theme_font_size_override("font_size", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.6, 0.7, 0.8)
	sub.position = Vector2(0, 160)
	sub.size = Vector2(1600, 30)
	add_child(sub)
	var car_card := _make_card("МАШИНА", CARS, 240)
	var map_card := _make_card("КАРТА", MAPS, 860)
	add_child(car_card["panel"]); add_child(map_card["panel"])
	var start := Button.new()
	start.text = "В ПУТЬ"
	start.add_theme_font_size_override("font_size", 26)
	start.custom_minimum_size = Vector2(320, 64)
	start.position = Vector2(640, 700)
	start.pressed.connect(func() -> void:
		GameContext.select(CARS[car_card["opt"].selected][1], MAPS[map_card["opt"].selected][1])
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	add_child(start)
	var hint := Label.new()
	hint.text = "WASD/стрелки · Space ручник · Shift слоу-мо · C камера · R рестарт · Esc меню · геймпад поддерживается"
	hint.add_theme_font_size_override("font_size", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.55, 0.62, 0.7)
	hint.position = Vector2(0, 800)
	hint.size = Vector2(1600, 30)
	add_child(hint)

func _make_card(title_text: String, items: Array, x: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = Vector2(x, 230)
	panel.size = Vector2(500, 250)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.25, 0.3, 0.4, 0.6)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 18; sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 16)
	t.modulate = Color(0.55, 0.65, 0.75)
	col.add_child(t)
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 22)
	opt.custom_minimum_size = Vector2(0, 48)
	for it in items: opt.add_item(it[0])
	col.add_child(opt)
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 17)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(456, 120)
	desc.bbcode_enabled = true
	desc.modulate = Color(0.8, 0.85, 0.9)
	col.add_child(desc)
	var refresh := func(idx: int) -> void:
		var parts: Array = (items[idx][2] as String).split("\n")
		desc.text = parts[0]
		if parts.size() > 1:
			desc.text += "\n[dim]\n" + parts[1] + "[/dim]"
	opt.item_selected.connect(refresh)
	refresh.call(0)
	return {"panel": panel, "opt": opt}
