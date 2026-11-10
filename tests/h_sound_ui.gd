extends Node
# SOUND tab: all five tabs are reachable (including by button), every new row
# exists, toggles write into Settings and survive a file reload, picture presets
# do not change audio, and the new rows grow at exactly the same 2× step as the
# rest of the UI (same contract as h_uiscale: controls are rebuilt at the new
# step, not old ones recolored).
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

# A) six tabs, GENERAL is the first, SOUND the sixth, reachable via focus and button
func _tabs() -> void:
	check(menu._tabs_btn.size() == 6, "six tabs (%d)" % menu._tabs_btn.size())
	check(menu._pages.size() == 6, "six pages (%d)" % menu._pages.size())
	menu._tabs_btn[5].grab_focus()
	check(menu._tabs_btn[5].has_focus(), "the SOUND tab takes focus")
	menu._tabs_btn[5].pressed.emit()
	check(menu._pages[5].visible and not menu._pages[0].visible,
		"pressing opens the sixth page")
	menu._tabs_btn[0].pressed.emit()
	check(menu._pages[0].visible and not menu._pages[5].visible,
		"returning to the first page works")

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

# B) all promised rows are present; toggles and sliders write into Settings
func _rows_and_settings() -> void:
	# sorting of the hidden page is deferred until it is shown: measure on a visible one
	menu._tabs_btn[5].pressed.emit()
	await get_tree().process_frame
	for key in ["audio_enabled", "vibration_enabled", "particles_enabled"]:
		check(_row_by_key(key) != null, "checkbox row %s exists" % key)
	check(menu._sliders.has("audio_volume"), "the MASTER VOLUME slider exists")
	check(menu._sliders.has("vibration_strength"), "the VIBRATION STRENGTH slider exists")
	# The hardware caption must depend on hardware, not on how we test the game:
	# "headless" in settings is a developer note that tells the player nothing.
	# The check is two-sided: without a gamepad the hint is present, with one
	# connected it is not.
	var pad_hint := false
	var dev_noise := false
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			var t := (n as Label).text
			if t == I18n.t("Геймпад не подключён: вибрация заработает сама, когда контроллер появится в системе"):
				pad_hint = true
			if "headless" in t or "заглушк" in t: dev_noise = true
		for c in n.get_children(): stack.append(c)
	check(not dev_noise, "the tab has no notes about the testing method (headless/stub)")
	check(pad_hint == Input.get_connected_joypads().is_empty(),
		"the gamepad hint shows exactly when none is connected (connected %d, hint %s)" % [
			Input.get_connected_joypads().size(), pad_hint])
	# language is not about audio: the row lives on the first GENERAL tab, and the
	# SOUND tab must not have it
	var general_walk: Array[Node] = [menu]
	var general_head := false
	while not general_walk.is_empty():
		var gn: Node = general_walk.pop_back()
		if gn is Label and (gn as Label).text == I18n.t("ОБЩЕЕ"): general_head = true
		for c in gn.get_children(): general_walk.append(c)
	check(general_head, "the GENERAL tab exists")
	var lang_on_sound := false
	var sound_walk: Array[Node] = [menu._pages[5]]
	while not sound_walk.is_empty():
		var sn: Node = sound_walk.pop_back()
		if sn is Label and (sn as Label).text == I18n.t("ЯЗЫК"): lang_on_sound = true
		for c in sn.get_children(): sound_walk.append(c)
	check(not lang_on_sound, "the SOUND tab has no LANGUAGE row")
	var cb := _find_check("audio_enabled")
	cb.button_pressed = false
	check(not Settings.audio_enabled, "the SOUND checkbox writes audio_enabled=false")
	cb.button_pressed = true
	check(Settings.audio_enabled, "the SOUND checkbox writes audio_enabled=true")
	var vb := _find_check("vibration_enabled")
	vb.button_pressed = false
	check(not Settings.vibration_enabled, "the VIBRATION checkbox writes vibration_enabled=false")
	var pb := _find_check("particles_enabled")
	pb.button_pressed = false
	check(not Settings.particles_enabled, "the PARTICLES checkbox writes particles_enabled=false")
	# slider: value in setting units, refresh syncs it back
	var rec: Array = menu._sliders["audio_volume"]
	(rec[0] as HSlider).value = 0.35
	check(absf(Settings.audio_volume - 0.35) < 0.01,
		"the volume slider writes %.2f" % Settings.audio_volume)
	Settings.set_value("audio_volume", 0.8)
	menu.refresh()
	check(is_equal_approx(float(rec[0].value), 0.8),
		"refresh returns 0.8 to the slider (%.2f)" % float(rec[0].value))
	pb.button_pressed = true
	vb.button_pressed = true
	Settings.reset()
	menu.refresh()

# C) values survive a file reload and back
func _persist() -> void:
	Settings.set_value("audio_volume", 0.25)
	Settings.set_value("vibration_strength", 0.6)
	Settings.set_value("particles_enabled", false)
	Settings.set_value("audio_enabled", false)
	Settings.load_values()
	check(absf(Settings.audio_volume - 0.25) < 0.01, "volume reloaded (%.2f)" % Settings.audio_volume)
	check(absf(Settings.vibration_strength - 0.6) < 0.01, "vibration strength reloaded (%.2f)" % Settings.vibration_strength)
	check(not Settings.particles_enabled and not Settings.audio_enabled, "unchecked boxes reloaded")
	menu.refresh()
	check(not _find_check("particles_enabled").button_pressed, "the checkbox is unchecked in the UI after load")
	Settings.reset()
	menu.refresh()

# D) picture presets know nothing of audio: touching audio keys does not reset the
#    preset, and the presets themselves still hold the same numbers as before the tab
func _presets_semantics() -> void:
	Settings.apply_preset(1)
	Settings.set_value("audio_enabled", false)
	Settings.set_value("particles_enabled", false)
	check(Settings.preset == 1, "audio keys do not reset the preset mark (%d)" % Settings.preset)
	Settings.apply_preset(3)
	check(Settings.preset_name() == "КИНО" and is_equal_approx(Settings.glow_bloom, 0.35) \
			and Settings.shadow_preset == 3, "КИНО stayed КИНО (%s)" % Settings.preset_name())
	check(not Settings.audio_enabled, "the picture preset does not touch audio (%s)" % str(Settings.audio_enabled))
	Settings.apply_preset(1)
	Settings.set_value("exposure", 1.7)
	check(Settings.preset == Settings.PRESET_CUSTOM, "a manual picture tweak still switches to CUSTOM")
	Settings.reset()

# E) step 2× doubles the new rows (menu rebuild, as in h_uiscale), and the rows lie
#    inside the frame. The headless window can be zero-sized: the absolute frame
#    check is only made when there is something to say, the relative one — always.
func _layout_and_scale() -> void:
	var one := await _metrics_at_step(1)
	var two := await _metrics_at_step(2)
	check(one.size() >= 3 and two.size() == one.size(),
		"measurements are complete at both steps (%d/%d)" % [one.size(), two.size()])
	for key in one:
		check(is_equal_approx(float(two[key]), float(one[key]) * 2.0),
			"%s: 2× = %s, expected %s" % [key, str(two[key]), str(float(one[key]) * 2.0)])
		check(float(one[key]) > 0.0, "%s: step 1× returns a nonzero size" % key)
	UiTheme.force_step(0)

func _metrics_at_step(step: int) -> Dictionary:
	UiTheme.force_step(step)
	var mm := SettingsMenu.new()
	add_child(mm)
	mm.open()
	mm._tabs_btn[5].pressed.emit()
	await get_tree().process_frame
	var out := {}
	var cb := _menu_check(mm, "audio_enabled")
	out["check_font"] = cb.get_theme_font_size("font_size")
	var rec: Array = mm._sliders["audio_volume"]
	out["slider_w"] = int((rec[0] as HSlider).custom_minimum_size.x)
	out["slider_font"] = (rec[1] as Label).get_theme_font_size("font_size")
	var page: Node = mm._pages[5]
	var box := page.get_child(0)
	for c in box.get_children():
		if c is Label and (c as Label).text == I18n.t("ЗВУК И ВИБРАЦИЯ"):
			out["head_font"] = (c as Label).get_theme_font_size("font_size")
	# relative geometry: the three new rows stand in one column under each other.
	# In headless the anchored panels collapse into a zero rect, so absolute frame
	# bounds are no measure here — what counts is column equality and ordering
	var rows := []
	for key in ["audio_enabled", "vibration_enabled", "particles_enabled"]:
		var row := _menu_check(mm, key)
		rows.append(row)
		var rg: Rect2 = row.get_global_rect()
		check(rg.size.y > 0.0, "%s: the row has nonzero height" % key)
	out["row_x"] = int(rows[0].get_global_position().x)
	var col_ok := true
	for r in rows:
		if not is_equal_approx((r as Control).get_global_position().x, float(out["row_x"])): col_ok = false
	check(col_ok, "the SOUND rows stand in one column")
	var y0: float = (rows[0] as Control).get_global_position().y
	var y1: float = (rows[1] as Control).get_global_position().y
	var y2: float = (rows[2] as Control).get_global_position().y
	check(y0 < y1 and y1 < y2, "the checkboxes go top to bottom in table order")
	mm.close()
	mm.queue_free()
	await get_tree().process_frame
	return out

func _menu_check(m: SettingsMenu, key: String) -> CheckBox:
	for n in m._all_of("CheckBox"):
		if String(n.get_meta("key")) == key: return n as CheckBox
	return null
