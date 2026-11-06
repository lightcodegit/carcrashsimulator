extends Node
# Вкладка ЗВУК: пять вкладок достижимы (в т.ч. кнопкой), каждая новая строка
# существует, тумблеры пишут в Settings и доживают до перезагрузки файла,
# картинка-пресеты от звука не меняются, а новые ряды растут ступенью 2× ровно
# как остальной интерфейс (тот же контракт, что у h_uiscale: пересборка контролов
# на новой ступени, а не перекраска старых).
var _fails := 0
var menu: SettingsMenu

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.reset()
	menu = SettingsMenu.new()
	add_child(menu)
	menu.open()
	_tabs()
	await _rows_and_settings()
	_persist()
	_presets_semantics()
	await _layout_and_scale()
	menu.close()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# A) пять вкладок, ЗВУК — пятая, достижима фокусом и нажатием кнопки
func _tabs() -> void:
	check(menu._tabs_btn.size() == 5, "вкладок пять (%d)" % menu._tabs_btn.size())
	check(menu._pages.size() == 5, "страниц пять (%d)" % menu._pages.size())
	menu._tabs_btn[4].grab_focus()
	check(menu._tabs_btn[4].has_focus(), "вкладка ЗВУК берёт фокус")
	menu._tabs_btn[4].pressed.emit()
	check(menu._pages[4].visible and not menu._pages[0].visible,
		"нажатие открывает пятую страницу")
	menu._tabs_btn[0].pressed.emit()
	check(menu._pages[0].visible and not menu._pages[4].visible,
		"возврат на первую страницу работает")

func _find_check(key: String) -> CheckBox:
	for n in menu._all_of("CheckBox"):
		if String(n.get_meta("key")) == key: return n as CheckBox
	return null

func _row_by_key(key: String) -> Control:
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if (n.get_class() == "OptionButton" or n.get_class() == "CheckBox") \
				and String((n as Control).get_meta("key")) == key:
			return n as Control
		for c in n.get_children(): stack.append(c)
	return null

# B) все обещанные строки на месте; тумблеры и ползунки пишут в Settings
func _rows_and_settings() -> void:
	for key in ["audio_enabled", "vibration_enabled", "particles_enabled"]:
		check(_row_by_key(key) != null, "строка-галка %s существует" % key)
	check(menu._sliders.has("audio_volume"), "ползунок ОБЩАЯ ГРОМКОСТЬ существует")
	check(menu._sliders.has("vibration_strength"), "ползунок СИЛА ВИБРАЦИИ существует")
	# Подпись про железо обязана зависеть от железа, а не от того, как мы тестируем
	# игру: «headless» в настройках — это заметка для разработчика, игроку она
	# ничего не говорит. Проверка двусторонняя: без геймпада подсказка есть, с
	# подключённым — её нет.
	var pad_hint := false
	var dev_noise := false
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			var t := (n as Label).text
			if "Геймпад" in t: pad_hint = true
			if "headless" in t or "заглушк" in t: dev_noise = true
		for c in n.get_children(): stack.append(c)
	check(not dev_noise, "на вкладке нет заметок про метод тестирования (headless/заглушка)")
	check(pad_hint == Input.get_connected_joypads().is_empty(),
		"подсказка про геймпад показывается ровно когда его нет (подключено %d, подсказка %s)" % [
			Input.get_connected_joypads().size(), pad_hint])
	var cb := _find_check("audio_enabled")
	cb.button_pressed = false
	check(not Settings.audio_enabled, "галка ЗВУК пишет audio_enabled=false")
	cb.button_pressed = true
	check(Settings.audio_enabled, "галка ЗВУК пишет audio_enabled=true")
	var vb := _find_check("vibration_enabled")
	vb.button_pressed = false
	check(not Settings.vibration_enabled, "галка ВИБРАЦИЯ пишет vibration_enabled=false")
	var pb := _find_check("particles_enabled")
	pb.button_pressed = false
	check(not Settings.particles_enabled, "галка ЧАСТИЦЫ пишет particles_enabled=false")
	# ползунок: значение в единицах настройки, refresh синхронизирует обратно
	var rec: Array = menu._sliders["audio_volume"]
	(rec[0] as HSlider).value = 0.35
	check(absf(Settings.audio_volume - 0.35) < 0.01,
		"ползунок громкости пишет %.2f" % Settings.audio_volume)
	Settings.set_value("audio_volume", 0.8)
	menu.refresh()
	check(is_equal_approx(float(rec[0].value), 0.8),
		"refresh возвращает ползунку 0.8 (%.2f)" % float(rec[0].value))
	pb.button_pressed = true
	vb.button_pressed = true
	Settings.reset()
	menu.refresh()

# C) значения доживают до перезагрузки файла и обратно
func _persist() -> void:
	Settings.set_value("audio_volume", 0.25)
	Settings.set_value("vibration_strength", 0.6)
	Settings.set_value("particles_enabled", false)
	Settings.set_value("audio_enabled", false)
	Settings.load_values()
	check(absf(Settings.audio_volume - 0.25) < 0.01, "громкость перечитана (%.2f)" % Settings.audio_volume)
	check(absf(Settings.vibration_strength - 0.6) < 0.01, "сила вибрации перечитана (%.2f)" % Settings.vibration_strength)
	check(not Settings.particles_enabled and not Settings.audio_enabled, "выключенные галки перечитаны")
	menu.refresh()
	check(not _find_check("particles_enabled").button_pressed, "галка после загрузки снята в UI")
	Settings.reset()
	menu.refresh()

# D) пресеты картинки не ведают звука: трогание звуковых ключей пресет не сбрасывает,
#    а сами пресеты остались теми же числами, что и до вкладки
func _presets_semantics() -> void:
	Settings.apply_preset(1)
	Settings.set_value("audio_enabled", false)
	Settings.set_value("particles_enabled", false)
	check(Settings.preset == 1, "звуковые ключи не сбрасывают отметку пресета (%d)" % Settings.preset)
	Settings.apply_preset(3)
	check(Settings.preset_name() == "КИНО" and is_equal_approx(Settings.glow_bloom, 0.35) \
			and Settings.shadow_preset == 3, "КИНО остался КИНО (%s)" % Settings.preset_name())
	check(not Settings.audio_enabled, "пресет картинки не трогает звук (%s)" % str(Settings.audio_enabled))
	Settings.apply_preset(1)
	Settings.set_value("exposure", 1.7)
	check(Settings.preset == Settings.PRESET_CUSTOM, "ручная правка картинки по-прежнему делает СВОЁ")
	Settings.reset()

# E) ступень 2× удваивает новые ряды (пересборка меню, как в h_uiscale), и
#    ряды лежат внутри кадра. Headless-окно бывает нулевым: абсолютная проверка
#    кадра делается только когда есть о чём говорить, относительная — всегда.
func _layout_and_scale() -> void:
	var one := await _metrics_at_step(1)
	var two := await _metrics_at_step(2)
	check(one.size() >= 3 and two.size() == one.size(),
		"замеры полны на обеих ступенях (%d/%d)" % [one.size(), two.size()])
	for key in one:
		check(is_equal_approx(float(two[key]), float(one[key]) * 2.0),
			"%s: 2× = %s, ожидалось %s" % [key, str(two[key]), str(float(one[key]) * 2.0)])
		check(float(one[key]) > 0.0, "%s: ступень 1× отдаёт ненулевой размер" % key)
	UiTheme.force_step(0)

func _metrics_at_step(step: int) -> Dictionary:
	UiTheme.force_step(step)
	var mm := SettingsMenu.new()
	add_child(mm)
	mm.open()
	mm._tabs_btn[4].pressed.emit()
	await get_tree().process_frame
	var out := {}
	var cb := _menu_check(mm, "audio_enabled")
	out["check_font"] = cb.get_theme_font_size("font_size")
	var rec: Array = mm._sliders["audio_volume"]
	out["slider_w"] = int((rec[0] as HSlider).custom_minimum_size.x)
	out["slider_font"] = (rec[1] as Label).get_theme_font_size("font_size")
	var page: Node = mm._pages[4]
	var box := page.get_child(0)
	for c in box.get_children():
		if c is Label and (c as Label).text == "ЗВУК И ВИБРАЦИЯ":
			out["head_font"] = (c as Label).get_theme_font_size("font_size")
	# относительная геометрия: три новых ряда стоят в одной колонке друг под
	# другом. В headless якорные панели схлопнуты в нулевой rect, поэтому
	# абсолютные границы кадра здесь не мерило — мерило равенство колонки и рост
	var rows := []
	for key in ["audio_enabled", "vibration_enabled", "particles_enabled"]:
		var row := _menu_check(mm, key)
		rows.append(row)
		var rg: Rect2 = row.get_global_rect()
		check(rg.size.y > 0.0, "%s: ряд имеет ненулевую высоту" % key)
	out["row_x"] = int(rows[0].get_global_position().x)
	var col_ok := true
	for r in rows:
		if not is_equal_approx((r as Control).get_global_position().x, float(out["row_x"])): col_ok = false
	check(col_ok, "ряды ЗВУК стоят в одну колонку")
	var y0: float = (rows[0] as Control).get_global_position().y
	var y1: float = (rows[1] as Control).get_global_position().y
	var y2: float = (rows[2] as Control).get_global_position().y
	check(y0 < y1 and y1 < y2, "галки идут сверху вниз по порядку таблицы")
	mm.close()
	mm.queue_free()
	await get_tree().process_frame
	return out

func _menu_check(m: SettingsMenu, key: String) -> CheckBox:
	for n in m._all_of("CheckBox"):
		if String(n.get_meta("key")) == key: return n as CheckBox
	return null
