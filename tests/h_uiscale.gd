extends Node
# Контракт ступеней интерфейса. Дробный коэффициент движок отдаёт мылом (см.
# h_pixelscale), поэтому рост сделан целыми ступенями и own числами раскладки.
# Значит, на ступени 2× ВСЁ — шрифты, иконки, отступы, ширина колонок и панелей —
# обязано вырасти ровно вдвое. Один пропущенный литерал тест и поймает.

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
	# логотип — самая широкая текстурка меню; брать marks[0] нельзя: порядок
	# обхода зависит от дерева и попадался нулевой по размеру узел
	var mark_w := 0.0
	for tr in marks:
		mark_w = maxf(mark_w, (tr as Control).custom_minimum_size.x)
	check(mark_w > 0.0, "в меню найдена текстурка с ненулевой шириной")
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
	# автоступень обязана считаться по экрану, а не по окну: игрок с 4K стартует
	# в окне 1600×900 и по размеру окна никогда бы не увидел вторую ступень
	var want := 2 if DisplayServer.screen_get_size().y >= 1700 else 1
	check(UiTheme.step() == want,
		"автоступень по экрану %s даёт %d, получилась %d" % [
			str(DisplayServer.screen_get_size()), want, UiTheme.step()])
	var one := _metrics(1)
	var two := _metrics(2)
	# полнота: без этого пропущенный замер молча сокращает список и «всё проходит»
	check(one.size() == EXPECTED, "ступень 1× отдала %d замеров, ожидалось %d" % [one.size(), EXPECTED])
	check(two.size() == EXPECTED, "ступень 2× отдала %d замеров, ожидалось %d" % [two.size(), EXPECTED])
	check(one.keys() == two.keys(), "наборы замеров совпадают: %s против %s" % [str(one.keys()), str(two.keys())])
	check(UiTheme.step() == 2, "ступень переключается (сейчас %d)" % UiTheme.step())
	for key in one:
		var a: float = float(one[key])
		var b: float = float(two[key])
		check(is_equal_approx(b, a * 2.0), "%s: 2× = %s, ожидалось %s" % [key, str(b), str(a * 2.0)])
	# ступень 1× обязана остаться прежним дизайном: ни один замер не изменился сам
	for key in one:
		check(float(one[key]) > 0.0, "%s: ступень 1× отдаёт ненулевой дизайн-размер" % key)
	UiTheme.force_step(0)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
