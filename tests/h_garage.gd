extends Node3D
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await frames(8)
	var garage_button: Button
	for b in menu._nav:
		if b.text == "ГАРАЖ": garage_button = b
	check(garage_button != null, "garage entry missing from main menu")
	if garage_button == null:
		get_tree().quit(1)
		return
	check(menu._nav.size() == 6, "six navigation sections")
	garage_button.grab_focus()
	check(garage_button.has_focus(), "garage entry keyboard focus")
	garage_button.pressed.emit()
	await frames(6)
	var panel: Node = menu._garage
	check(panel != null, "separate garage panel")
	check(panel.sliders.size() == 10, "all tuning and finish controls present")
	# потолок именно физический (BRAKE_MAX_G × g), а не магическое число: float32
	# хранит 16.1865 как 16.1865005…, поэтому точное сравнение с литералом проваливалось
	var brake_cap := 1.65 * 9.81
	check(panel.sliders.brake_decel.max_value <= brake_cap + 0.01, "no dead brake slider region")
	check(panel.sliders.accel_max.has_focus(), "enter garage focuses tuning")
	panel.sliders.accel_max.value = 9.0
	panel.set_paint(Color(0.1, 0.8, 0.3))
	await frames(2)
	check(not FileAccess.file_exists("user://garage_v1.json"), "live preview does not save")
	var preview: StandardMaterial3D = menu._car_model.get_node("body").get_active_material(0)
	var draft_bytes := preview.albedo_texture.get_image().get_data()
	panel.save_button.pressed.emit()
	check(FileAccess.file_exists("user://garage_v1.json"), "save button writes")
	panel.factory_button.pressed.emit()
	check(menu._profiles.draft_params().accel_max == 7, "factory button resets draft")
	panel.cancel_button.pressed.emit()
	check(menu._profiles.draft_params().accel_max == 9, "cancel button restores saved tuning")
	check(menu._car_model.get_node("body").get_active_material(0).albedo_texture.get_image().get_data() == draft_bytes, "cancel restores preview")
	var m1 := await layout(menu, panel, 1)
	menu.queue_free()
	await frames(2)
	UiTheme.force_step(2)
	get_window().size = Vector2i(3200, 1800)
	menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	menu._show_section(menu.Section.GARAGE)
	await frames(6)
	panel = menu._garage
	var m2 := await layout(menu, panel, 2)
	check(is_equal_approx(m2.x, m1.x * 2) and is_equal_approx(m2.y, m1.y * 2), "garage controls scale exactly 2x")
	check(menu._car_model.get_node("body").get_active_material(0).albedo_texture.get_image().get_data() == draft_bytes, "new menu loads saved appearance")
	menu._profiles.path = "user://missing/garage.json"
	panel.sliders.accel_max.value = 8.0
	panel.save_button.pressed.emit()
	check(not panel.status.text.is_empty() and panel.status.get_theme_color("font_color") == UiTheme.BAD, "save error visible")
	menu._profiles.path = "user://garage_v1.json"
	menu._show_section(menu.Section.PLAY)
	check(menu._profiles.draft_params().accel_max == 9, "leaving garage discards draft")
	get_tree().current_scene = null
	menu.start_game()
	await frames(8)
	var gm: GameManager = get_tree().current_scene
	check(gm != null and gm.car.params.accel_max == 9, "saved tuning reaches next game")
	check(gm.car.body._mat.albedo_texture.get_image().get_data() == draft_bytes, "menu and game paint agree")
	gm._restart_map()
	check(gm.car.params.accel_max == 9, "restart retains tuning")
	check(gm.car.body._mat.albedo_texture.get_image().get_data() == draft_bytes, "restart retains appearance")
	UiTheme.force_step(0)
	print("PARTIAL: native headless layout verified; live GPU visual verification pending")
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func layout(menu: Node, panel: Node, step: int) -> Vector2:
	await frames(6)
	var viewport := get_viewport().get_visible_rect()
	check(viewport.encloses(menu._panel.get_global_rect()), "garage panel inside viewport at %dx" % step)
	check(not menu._nav[0].get_parent().get_global_rect().intersects(menu._panel.get_global_rect()), "navigation and garage do not overlap")
	check(panel.scroll.get_v_scroll_bar().max_value > panel.scroll.size.y, "garage scrolls overflowing content")
	panel.sliders.paint_roughness.grab_focus()
	panel.scroll.ensure_control_visible(panel.sliders.paint_roughness)
	await frames(4)
	check(panel.scroll.get_global_rect().encloses(panel.sliders.paint_roughness.get_global_rect()), "last slider scrolls into view")
	for b in [panel.save_button, panel.cancel_button, panel.factory_button]:
		check(menu._panel.get_global_rect().encloses(b.get_global_rect()), "draft action inside panel")
	return Vector2(panel.sliders.accel_max.custom_minimum_size.y, panel.save_button.get_theme_font_size("font_size"))
