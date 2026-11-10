extends Node
# UI step contract. A fractional scale factor makes the engine render blurry (see
# h_pixelscale), so growth is done in whole steps and own layout numbers.
# Therefore at step 2× EVERYTHING — fonts, icons, margins, column and panel
# widths — must grow exactly twofold. A single missed literal is what this test catches.

var _fails := 0
const EXPECTED := 14

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _metrics(step: int) -> Dictionary:
	UiTheme.force_step(step)
	var m := {}
	m["label20"] = UiTheme.label("ЩУК", 20, Color.WHITE).get_theme_font_size("font_size")
	m["check_tex"] = UiTheme.check_tex(true).get_width()
	m["knob_tex"] = UiTheme.knob_tex().get_width()
	m["nav_font"] = UiTheme.nav_item("МАШИНЫ").get_theme_font_size("font_size")
	m["nav_big"] = UiTheme.nav_item("НАЧАТЬ", true).get_theme_font_size("font_size")
	m["action_font"] = UiTheme.action_button("ВЫЙТИ", 20).get_theme_font_size("font_size")
	m["check_font"] = _check_font()
	m["panel_margin"] = UiTheme.panel_style(10).content_margin_left
	m["card_radius"] = UiTheme.card_style(true).corner_radius_top_left
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	mm._show_section(0)
	m["nav_w"] = mm._nav[0].custom_minimum_size.x
	var marks: Array = mm.find_children("*", "TextureRect", true, false)
	# the logo is the widest texture in the menu; taking marks[0] is not allowed:
	# traversal order depends on the tree and a zero-size node used to come up
	var mark_w := 0.0
	for tr in marks:
		mark_w = maxf(mark_w, (tr as Control).custom_minimum_size.x)
	check(mark_w > 0.0, "a texture with nonzero width was found in the menu")
	m["logo_mark"] = mark_w
	m["panel_w"] = mm._panel.offset_right - mm._panel.offset_left
	m["start_w"] = mm._start_btn.custom_minimum_size.x
	m["start_h"] = mm._start_btn.custom_minimum_size.y
	mm.queue_free()
	remove_child(mm)
	return m

func _check_font() -> int:
	var c := CheckBox.new()
	UiTheme.style_check(c)
	var f := c.get_theme_font_size("font_size")
	c.free()
	return f

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(1600, 900)
	# the auto step must be computed from the screen, not the window: a 4K player
	# starts in a 1600×900 window and would never see the second step from window size
	var want := 2 if DisplayServer.screen_get_size().y >= 1700 else 1
	check(UiTheme.step() == want,
		"auto step from screen %s wants %d, got %d" % [
			str(DisplayServer.screen_get_size()), want, UiTheme.step()])
	var one := _metrics(1)
	var two := _metrics(2)
	# completeness: without it a skipped measurement silently shortens the list and «everything passes»
	check(one.size() == EXPECTED, "step 1× returned %d measurements, expected %d" % [one.size(), EXPECTED])
	check(two.size() == EXPECTED, "step 2× returned %d measurements, expected %d" % [two.size(), EXPECTED])
	check(one.keys() == two.keys(), "measurement sets match: %s vs %s" % [str(one.keys()), str(two.keys())])
	check(UiTheme.step() == 2, "the step switches (now %d)" % UiTheme.step())
	for key in one:
		var a: float = float(one[key])
		var b: float = float(two[key])
		check(is_equal_approx(b, a * 2.0), "%s: 2× = %s, expected %s" % [key, str(b), str(a * 2.0)])
	# step 1× must remain the original design: no measurement changed on its own
	for key in one:
		check(float(one[key]) > 0.0, "%s: step 1× returns a nonzero design size" % key)
	UiTheme.force_step(0)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
