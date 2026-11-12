extends Node3D
# Settings and key rebinding.
# 1) defaults are the ones chosen by measurements on a weak GPU
# 2) a value survives a reload and back
# 3) a rebind changes only its own device class: a key must not eat the gamepad
# 4) event serialization reads back in all three forms
# 5) the settings screen builds, opens and captures a binding
# The player's file in user:// is saved and restored for the duration of the test: the
# test has no right to leave someone else's layout behind.
var _fails := 0
var _backup := ""
var _had_file := false
var _path := "user://settings.cfg"
var menu: SettingsMenu

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	_had_file = FileAccess.file_exists(_path)
	if _had_file:
		var f := FileAccess.open(_path, FileAccess.READ)
		_backup = f.get_as_text()
	await get_tree().process_frame
	_defaults()
	_persist()
	await _rebind()
	await _codec()
	await _build_menu()
	await _presets()
	await _extended()

# Presets and the fact that a manual tweak clears the "in MEDIUM" mark.
func _presets() -> void:
	check(Settings.preset == 1, "P: the СРЕДНЕЕ preset is active by default (%d)" % Settings.preset)
	Settings.apply_preset(3)
	check(Settings.shadow_preset == 3 and Settings.ssao and is_equal_approx(Settings.glow_bloom, 0.35),
		"P: КИНО enables far shadows, SSAO and bloom (%d/%s/%.2f)" % [
			Settings.shadow_preset, str(Settings.ssao), Settings.glow_bloom])
	check(Settings.preset_name() == "КИНО", "P: the preset name is readable (%s)" % Settings.preset_name())
	Settings.set_value("exposure", 1.9)
	check(Settings.preset == Settings.PRESET_CUSTOM and Settings.preset_name() == "СВОЁ",
		"P: a manual edit clears the preset mark (%d)" % Settings.preset)
	Settings.apply_preset(1)
	check(is_equal_approx(Settings.exposure, 1.0) and Settings.preset == 1,
		"P: returning to СРЕДНЕЕ fixes the slider back (%.2f)" % Settings.exposure)
	Settings.load_values()
	check(Settings.preset == 1 and is_equal_approx(Settings.glow_bloom, 0.0),
		"P: the preset and its values survive a reload (%d)" % Settings.preset)
	Settings.reset()

# Extended mode: entries must not only exist but also reach the scene.
func _extended() -> void:
	Settings.tier_extended = false
	menu.refresh()
	var hidden := _tier_rows(1, false)
	check(hidden > 10, "E: in basic mode %d extended rows are hidden" % hidden)
	Settings.tier_extended = true
	menu.refresh()
	var shown := _tier_rows(1, true)
	check(shown == hidden, "E: extended mode shows the same %d rows" % shown)
	check(is_equal_approx(Settings.ambient_energy(), Settings.ambient_base() * Settings.ambient),
		"E: ambient light energy = engine base × multiplier (%.2f)" % Settings.ambient_energy())
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	Settings.set_value("fov", 92.0)
	Settings.set_value("shake", 0.0)
	Settings.set_value("exposure", 1.4)
	Settings.set_value("tonemap", 1)
	Settings.set_value("sun_soft", 1.3)
	Settings.set_value("fog_aerial", 0.9)
	Settings.set_value("ssao_radius", 2.5)
	Settings.set_value("slowmo", 0.5)
	await get_tree().physics_frame
	check(is_equal_approx(g.camera.fov, 92.0), "E: field of view reaches the camera (%.1f)" % g.camera.fov)
	check(is_equal_approx(g._env.tonemap_exposure, 1.4), "E: exposure reaches the environment (%.2f)" % g._env.tonemap_exposure)
	check(g._env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "E: tone mapping switches (%d)" % g._env.tonemap_mode)
	check(is_equal_approx(g._sun.light_angular_distance, 1.3), "E: shadow softness reaches the sun (%.2f)" % g._sun.light_angular_distance)
	check(is_equal_approx(g._env.fog_aerial_perspective, 0.9), "E: aerial perspective applies (%.2f)" % g._env.fog_aerial_perspective)
	check(is_equal_approx(g._env.ssao_radius, 2.5), "E: SSAO radius applies (%.2f)" % g._env.ssao_radius)
	TimeScale.set_hold(true)
	check(is_equal_approx(Engine.time_scale, 0.5), "E: the slow-mo factor comes from the setting (%.2f)" % Engine.time_scale)
	TimeScale.set_hold(false)
	check(is_equal_approx(Engine.time_scale, 1.0), "E: releasing returns time to normal")
	g.queue_free()
	await get_tree().process_frame
	Settings.reset()

func _tier_rows(tier: int, visible: bool) -> int:
	var n := 0
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Control and (c as Control).has_meta("tier") and int((c as Control).get_meta("tier")) == tier:
			if (c as Control).visible == visible: n += 1
		for k in c.get_children(): stack.append(k)
	return n

func _defaults() -> void:
	# We check the factory values of the CODE, not the player's file: on Windows user://
	# is not isolated by HOME, and someone else's settings.cfg turned these checks into a
	# lottery. The "file → values" path is covered by _persist below.
	Settings.reset()
	# The default was chosen by measurements on Intel HD 630: a full frame with shadows,
	# glow and haze costs 21 ms, while a 60 Hz vertical accepts 16.7 — a frame that does
	# not fit lands in 33.3 ms, exactly the 30 fps the player complains about.
	check(Settings.msaa == Settings.Msaa.X2, "1: MSAA 2× by default (%d)" % Settings.msaa)
	check(not Settings.screen_aa, "1: screen anti-aliasing is off by default")
	check(is_equal_approx(Settings.scale, 0.7), "1: internal scale 0.7 by default (%.2f)" % Settings.scale)
	check(Settings.fog and Settings.glow, "1: fog and glow are enabled")
	check(not Settings.ssao and not Settings.ssil, "1: screen effects are off by default")
	check(Settings.shadow_preset == 1 and Settings.shadow_enabled(), "1: short shadows by default")
	check(is_equal_approx(Settings.shadow_distance(), 120.0), "1: shadow distance 120 m")
	check(Settings.show_fps, "1: the frame counter is on by default")
	check(Settings.vsync == Settings.VSync.ON, "1: vertical sync is enabled")

func _persist() -> void:
	Settings.set_value("scale", 1.0)
	Settings.set_value("fog", false)
	Settings.set_value("shadow_preset", 0)
	Settings.load_values()
	check(is_equal_approx(Settings.scale, 1.0), "2: the scale survives a reload (%.2f)" % Settings.scale)
	check(not Settings.fog, "2: disabled fog is read from disk")
	check(not Settings.shadow_enabled(), "2: shadows are off from disk")
	Settings.reset()
	Settings.load_values()
	check(Settings.fog and Settings.glow and Settings.shadow_enabled(), "2: reset restores the defaults")
	check(is_equal_approx(get_window().scaling_3d_scale, 0.7),
		"2: the scale applies to the window (%.2f)" % get_window().scaling_3d_scale)
	check(Engine.max_fps == 60, "2: the frame cap is 60 by default (%d)" % Engine.max_fps)
	Settings.set_value("fps_limit", 0)
	check(Engine.max_fps == 0, "2: with no frame cap Engine.max_fps = 0 (%d)" % Engine.max_fps)
	Settings.set_value("fps_limit", 60)
	check(Engine.max_fps == 60, "2: the frame cap applies immediately (%d)" % Engine.max_fps)

func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _rebind() -> void:
	var b1 := InputEventJoypadButton.new()
	b1.button_index = 1
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	InputRouter.rebind("handbrake", k)
	var after := InputMap.action_get_events("handbrake")
	var keys := 0
	var joys := 0
	for e in after:
		if e is InputEventKey: keys += 1
		else: joys += 1
	# the handbrake has two stock gamepad bindings (cross and L1) and one keyboard one;
	# after replacing the key the gamepad must neither lose nor gain any
	var want_joy := InputRouter.DEFAULTS["handbrake"].joy.size()
	check(keys == 1 and joys == want_joy,
		"3: only the keyboard was replaced, the gamepad is intact (%d+%d, expected 1+%d)" % [keys, joys, want_joy])
	# action_press forcibly raises the action regardless of the layout, so we verify the
	# binding with real events
	# Godot applies action states at the end of the frame, so each event needs a frame of
	# waiting: otherwise the check reads the previous state
	_key(KEY_SPACE, true)
	await get_tree().process_frame
	check(not Input.is_action_pressed("handbrake"), "3: the old Space is no longer the handbrake")
	_key(KEY_SPACE, false)
	_key(KEY_F, true)
	await get_tree().process_frame
	check(Input.is_action_pressed("handbrake"), "3: the new key is the handbrake")
	_key(KEY_F, false)
	await get_tree().process_frame
	check("F" in InputRouter.describe("handbrake"), "3: the description shows the new key (%s)" % InputRouter.describe("handbrake"))
	# bind a BUTTON NOW as well: the key class must not revert to Space because of it
	InputRouter.rebind("handbrake", b1)
	var n := InputMap.action_get_events("handbrake").size()
	check(n == 2, "3: two bindings — one per device (%d)" % n)
	_key(KEY_SPACE, true)
	await get_tree().process_frame
	check(not Input.is_action_pressed("handbrake"), "3: Space did not resurrect after binding the button")
	_key(KEY_SPACE, false)
	await get_tree().process_frame
	InputRouter.reset_keys()
	Settings.load_values()

func _codec() -> void:
	var b := InputEventJoypadButton.new(); b.button_index = 7
	var m := InputEventJoypadMotion.new(); m.axis = 5; m.axis_value = 0.5
	# 7 = START: definitely not the default respawn button, otherwise the test would pass on its own
	b.button_index = 7
	InputRouter.rebind("respawn", b)
	InputRouter.rebind("slowmo", m)
	var cf := ConfigFile.new()
	InputRouter.save_keys(cf)
	InputRouter.reset_keys()
	InputRouter.load_keys(cf)
	var found_b := false
	var found_m := false
	for e in InputMap.action_get_events("respawn"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == 7: found_b = true
	for e in InputMap.action_get_events("slowmo"):
		if e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == 5 \
				and absf((e as InputEventJoypadMotion).axis_value - 0.5) < 0.01: found_m = true
	check(found_b, "4: the gamepad button survived the rewrite")
	check(found_m, "4: the gamepad axis survived the rewrite with its direction")
	check(InputRouter.describe("slowmo").length() > 1, "4: the axis is described (%s)" % InputRouter.describe("slowmo"))
	var kmod := InputEventKey.new()
	kmod.physical_keycode = KEY_F
	kmod.ctrl_pressed = true
	kmod.shift_pressed = true
	var ktok := InputRouter._encode(kmod)
	var back: InputEventKey = InputRouter._decode(ktok)
	check(back != null and back.ctrl_pressed and back.shift_pressed and not back.alt_pressed \
			and back.physical_keycode == KEY_F,
			"4: modifiers survived the write to file (%s)" % ktok)
	var bare: InputEventKey = InputRouter._decode("k%d" % KEY_F)
	check(bare != null and not bare.ctrl_pressed and not bare.shift_pressed,
			"4: the old token without modifiers reads as before")
	InputRouter.reset_keys()
	Settings.reset()

func _build_menu() -> void:   # called from _ready, so await is not needed here
	menu = SettingsMenu.new()
	add_child(menu)
	menu.open()
	check(menu.is_open(), "5: the screen opens")
	var caps := 0
	var opts := 0
	var checks := 0
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).has_meta("bind_action"): caps += 1
		if n.get_class() == "OptionButton": opts += 1
		if n.get_class() == "CheckBox": checks += 1
		for c in n.get_children(): stack.append(c)
	check(caps == InputRouter.DEFAULTS.size() * 2,
		"5: two binding cells per action — keyboard and gamepad (%d)" % caps)
	# the number of screen entries is taken from the same tables and the same support
	# checks as the screen itself: otherwise the test would check a number instead of the
	# rule "do not show what is unsupported". preset is excluded from the list: it is
	# cards on the QUALITY tab.
	var want_opts := SettingsMenu.OPTIONS.size() - 1
	var want_checks := 0
	for c in SettingsMenu.CHECKS:
		if SettingsMenu._supported(c[0]): want_checks += 1
	# +1 toggle: the mode itself (basic/extended) is also a CheckBox, but it is not an
	# image setting, it is a way to show them
	check(opts == want_opts + 1 and checks == want_checks + 1,
		"5: parameters, including language, and %d+1 toggles (%d/%d)" % [want_checks, opts, checks])
	Settings.set_value("language", "en")
	var translated := false
	for label in menu._all_of("Label"):
		if label.text == "SETTINGS": translated = true
	check(I18n.locale == "en" and translated,
		"5: English translates the menu labels immediately")
	Settings.load_values()
	check(Settings.language == "en", "5: the chosen language is saved")
	Settings.set_value("language", "ru")
	check(I18n.locale == "ru", "5: Russian can be chosen back")
	menu._begin_capture("cam_cycle")
	check(menu.capturing(), "5: capture mode is on")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = true
	menu._input(ev)   # capture intercepts the event before the GUI
	check(not menu.capturing(), "5: capture finished on the press")
	check("G" in InputRouter.describe("cam_cycle"), "5: the binding was recorded (%s)" % InputRouter.describe("cam_cycle"))
	# A modifier is part of the binding: earlier the capture dropped Ctrl, "Ctrl+G"
	# became a plain G and silently started conflicting with it.
	menu._begin_capture("cam_cycle")
	var evc := InputEventKey.new()
	evc.physical_keycode = KEY_G
	evc.ctrl_pressed = true
	evc.pressed = true
	menu._input(evc)
	var held := false
	for e in InputMap.action_get_events("cam_cycle"):
		if e is InputEventKey and (e as InputEventKey).ctrl_pressed \
				and (e as InputEventKey).physical_keycode == KEY_G:
			held = true
	check(held, "5: the capture kept Ctrl on the key (%s)" % str(InputMap.action_get_events("cam_cycle")))
	check("CTRL" in InputRouter.describe("cam_cycle"),
		"5: the screen shows the modifier (%s)" % InputRouter.describe("cam_cycle"))
	var plain := InputEventKey.new()
	plain.physical_keycode = KEY_G
	var with := InputEventKey.new()
	with.physical_keycode = KEY_G
	with.ctrl_pressed = true
	check(not InputRouter._same_event(plain, with),
		"5: Ctrl+G and G are different keys, one binding does not displace the other")
	# Esc during capture cancels it but does not close the screen
	menu._begin_capture("cam_cycle")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._input(esc)
	check(not menu.capturing() and menu.is_open(), "5: Esc during capture cancels the capture but not the screen")
	menu._end_capture()
	# An assignment that conflicts with a factory binding (W is throttle) ends
	# the capture: the assignment already happened, and the cell must not stay
	# in "PRESS A KEY…" while the next press silently rebinds it again.
	menu._begin_capture("brake")
	var clash := InputEventKey.new()
	clash.physical_keycode = KEY_W
	clash.pressed = true
	menu._input(clash)
	check(not menu.capturing(), "5: a conflicting assignment ends the capture")
	check("W" in InputRouter.describe("brake"), "5: the conflicting binding was recorded (%s)" % InputRouter.describe("brake"))
	check(not InputRouter.describe("brake").contains("CTRL"), "5: only W was taken")
	InputRouter.clear_binding("brake")
	# A key event with no code (some media keys emit one) cannot be represented
	# in the config: k0 is rejected by the decoder, so the binding would die on
	# restart. The capture refuses it and keeps waiting for a real key.
	menu._begin_capture("respawn")
	var phantom := InputEventKey.new()
	phantom.pressed = true
	menu._input(phantom)
	var ghost := false
	for e in InputRouter._custom.get("respawn", []):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == 0: ghost = true
	check(not ghost, "a codeless key leaves no phantom binding (%s)" % str(InputRouter._custom.get("respawn", [])))
	check(menu.capturing(), "the capture keeps waiting for a representable key")
	menu._end_capture()
	# outside capture Esc closes the screen, handled by _unhandled_input already
	var esc2 := InputEventKey.new()
	esc2.physical_keycode = KEY_ESCAPE
	esc2.pressed = true
	menu._unhandled_input(esc2)
	check(not menu.is_open(), "5: Esc outside capture closes the screen")
	menu.close()
	# without await the call returns at its first internal await, and all live-scene
	# checks would stay off-screen while the test printed ALL PASS
	await _apply_in_game()
	InputRouter.reset_keys()
	Settings.reset()
	_finish()

# Settings must reach the live scene, not just the file: otherwise the settings
# screen is a decoration.
func _apply_in_game() -> void:
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	check(g._env.fog_enabled and g._env.glow_enabled, "fog and glow are on by default")
	check(not g._env.ssao_enabled and not g._env.ssil_enabled, "screen effects are off by default")
	check(g._sun.shadow_enabled and is_equal_approx(g._sun.directional_shadow_max_distance, 120.0),
		"120 m shadows by default")
	check(is_equal_approx(g._env.sky.sky_material.energy_multiplier, 1.0),
		"the sky is not compensated live: with fog and glow on, Compatibility and Forward+ " +
		"render it identically (measurements in h_picture)")
	Settings.set_value("ssao", true)
	Settings.set_value("glow", true)
	await get_tree().physics_frame
	check(g._env.ssao_enabled, "SSAO turns on the fly")
	Settings.set_value("ssao", false)
	Settings.set_value("fog", false)
	Settings.set_value("glow", false)
	Settings.set_value("shadow_preset", 0)
	await get_tree().physics_frame
	check(not g._env.ssao_enabled and not g._env.ssil_enabled and not g._env.fog_enabled and not g._env.glow_enabled,
		"post-effects turn off the fly")
	check(not g._sun.shadow_enabled, "shadows turn off the fly")
	Settings.set_value("shadow_preset", 3)
	await get_tree().physics_frame
	check(g._sun.shadow_enabled and is_equal_approx(g._sun.directional_shadow_max_distance, 420.0),
		"the shadow distance changes (%.0f)" % g._sun.directional_shadow_max_distance)
	Settings.set_value("scale", 1.0)
	await get_tree().physics_frame
	check(is_equal_approx(g.get_window().scaling_3d_scale, 1.0),
		"the scale reaches the window (%.2f)" % g.get_window().scaling_3d_scale)
	check(g.hud._fps_label.visible, "the frame counter is visible by default")
	Settings.set_value("show_fps", false)
	await get_tree().physics_frame
	check(not g.hud._fps_label.visible, "the frame counter is hidden by the setting")
	g.queue_free()
	Settings.reset()
	await get_tree().process_frame

func _finish() -> void:
	if _had_file:
		var f := FileAccess.open(_path, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	else:
		DirAccess.remove_absolute("user://settings.cfg")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
