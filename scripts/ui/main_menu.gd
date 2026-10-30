extends Control

const CARS := [["Седан", "sedan"], ["Пикап", "pickup"], ["Спорткар", "sport"]]
const MAPS := [["Арена", "arena"], ["Городок", "town"], ["Трасса", "speedway"]]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5; col.anchor_right = 0.5
	col.offset_left = -220; col.offset_right = 220
	col.offset_top = 120; col.offset_bottom = 620
	col.add_theme_constant_override("separation", 18)
	add_child(col)
	var t := Label.new()
	t.text = "CAR CRASH SIMULATOR"
	t.add_theme_font_size_override("font_size", 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := Label.new()
	sub.text = "краш-песочница · 3 машины · 3 карты"
	sub.add_theme_font_size_override("font_size", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.75, 0.8)
	col.add_child(sub)
	var car_opt := OptionButton.new()
	for c in CARS: car_opt.add_item(c[0])
	var map_opt := OptionButton.new()
	for m in MAPS: map_opt.add_item(m[0])
	col.add_child(car_opt); col.add_child(map_opt)
	var start := Button.new(); start.text = "Старт"
	start.custom_minimum_size = Vector2(0, 46)
	start.pressed.connect(func() -> void:
		GameContext.select(CARS[car_opt.selected][1], MAPS[map_opt.selected][1])
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	col.add_child(start)
	var hint := Label.new()
	hint.text = "WASD/стрелки · Space ручник · Shift слоу-мо · C камера · R рестарт"
	hint.add_theme_font_size_override("font_size", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.6, 0.65, 0.7)
	col.add_child(hint)
