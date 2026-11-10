extends Node3D
# Flow regressions: pause/resume, respawn without a phantom impact,
# fire fading after respawn, returning to the menu from the pause overlay.
var _fails := 0
var gm: GameManager
var _impacts := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 20:
		await get_tree().physics_frame
	# loading screen: the built scene must turn it off (otherwise it hangs over
	# the game forever — the flip side of a live loading screen)
	check(not GameContext.loading_visible(), "loading screen hidden once the run scene is ready")
	gm.car.impact.connect(func(_s, _p, _n): _impacts += 1)

	# 1) phantom impact on respawn: the peak speed must reset
	gm.car._recent_speed = 120.0
	gm._respawn_now()
	for f in 20:
		await get_tree().physics_frame
	check(_impacts == 0, "no phantom impact right after respawn (%d)" % _impacts)

	# 2) a dent appears and respawn clears it completely
	var nose := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	check(gm.car.body.dent_count == 1, "dent applied")
	check(gm.car.body.deformation() > 0.05, "body deformed (%.2f m)" % gm.car.body.deformation())
	gm._respawn_now()
	check(gm.car.body.dent_count == 0, "dent count cleared after respawn")
	check(gm.car.body.deformation() < 1e-6, "body restored after respawn (%.6f)" % gm.car.body.deformation())

	# 3) Esc pauses, R while paused restarts the run and unpauses, Esc exits.
	# R on pause used to silently do nothing: players complained that "R does not
	# restart, it only resets speed" — now the same key works in both states.
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check(gm._paused and get_tree().paused, "esc pauses")
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	gm.car.chassis.global_position = Vector3(60.0, 1.0, 0.0)
	_key(KEY_R)
	await get_tree().process_frame
	check(not gm._paused and not get_tree().paused,
		"R while paused unpauses (_paused=%s, tree=%s)" % [str(gm._paused), str(get_tree().paused)])
	check(gm.car.body.dent_count == 0, "R while paused restarts the run (dents %d)" % gm.car.body.dent_count)
	check(absf(gm.car.chassis.global_position.x - gm._spawn.origin.x) < 1.0,
		"R while paused returns the car to spawn (x=%.1f)" % gm.car.chassis.global_position.x)
	check(gm.hud._tip_label.visible, "the restart is visible to the player: a label is on screen")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check(gm._paused and get_tree().paused, "esc pauses again")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not gm._paused and not get_tree().paused, "esc resumes")
	_key(KEY_R)
	await get_tree().physics_frame
	check(gm.car.body.dent_count == 0, "respawn works while running")

	# 4) the «В ГЛАВНОЕ МЕНЮ» button in the pause overlay: visible, inside the window, not covered
	gm._set_paused(true)
	await get_tree().process_frame
	# The live window rect, not the size from project.godot: with canvas_items+expand
	# the logical area is derived from the actual aspect and never equals the base.
	var vp := get_viewport().get_visible_rect().size
	var b: Button = gm.hud.pause_button("В ГЛАВНОЕ МЕНЮ")
	check(b != null, "the «В ГЛАВНОЕ МЕНЮ» button was found")
	check(b != null and b.visible, "menu button shown while paused")
	var br := b.get_global_rect()
	check(br.position.x >= 0 and br.position.y >= 0 and br.position.x + br.size.x <= vp.x and br.position.y + br.size.y <= vp.y,
		"menu button inside viewport (%s of %s)" % [str(br), str(vp)])
	check(_topmost_at(gm.hud, br.get_center()) == b, "menu button not covered by another control")

	# 4b) the full pause menu: four buttons, focus on the first, gamepad and keyboard
	# navigation, «заново» resets statistics and unpauses
	for name in ["ПРОДОЛЖИТЬ", "НАСТРОЙКИ", "ЗАПУСТИТЬ ЗАНОВО", "В ГЛАВНОЕ МЕНЮ"]:
		var pb: Button = gm.hud.pause_button(name)
		check(pb != null and pb.visible, "pause: button %s is present" % name)
		check(pb != null and pb.focus_mode == Control.FOCUS_ALL, "pause: %s is reachable from the gamepad" % name)
		if pb != null:
			var r := pb.get_global_rect()
			check(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= vp.x and r.end.y <= vp.y,
				"pause: %s inside the window (%s)" % [name, str(r)])
			# compute overlap for a point just inside the left edge: the overlay dim covers
			# all button centres, and hit-testing goes by the innermost control
			check(_topmost_at(gm.hud, r.position + Vector2(6, r.size.y * 0.5)) == pb,
				"pause: %s not covered by another panel" % name)
	check(gm.hud.pause_button("ПРОДОЛЖИТЬ").has_focus(), "pause: focus is on the first button")
	# the "not covered" check itself would be vacuous if the helper always returned
	# a button: a point inside the card but off the buttons must return the card
	var card_rect: Rect2 = gm.hud.pause_button("ПРОДОЛЖИТЬ").get_parent().get_global_rect()
	var card_point: Vector2 = card_rect.position + Vector2(24, 24)
	var on_card := _topmost_at(gm.hud, card_point)
	check(on_card != null and on_card is Panel, "pause: outside the buttons the card is on top, not the dim (%s)" % [
		"null" if on_card == null else on_card.get_class()])
	# the pause overlay must not label buttons with keys: the «ПРОДОЛЖИТЬ» button is
	# itself the way to continue, and an «ESC — …» line duplicated it in words
	var overlay := ""
	for c in gm.hud.get_children():
		overlay += _texts(c)
	check("ESC" not in overlay, "the pause menu shows no key-binding labels (%s)" % overlay.left(120))
	# «заново» must clear the impact log and unpause
	gm._crashes = 3
	gm.hud.log_impact(120.0)
	check(gm.hud._log_lines[0].text != "", "the log showed the impact as a line")
	gm.hud.pause_button("ЗАПУСТИТЬ ЗАНОВО").emit_signal("pressed")
	await get_tree().process_frame
	check(gm._crashes == 0, "pause: «заново» reset the log")
	var rows := ""
	for l in gm.hud._log_lines:
		rows += l.text
	check(rows == "", "pause: «заново» cleared the log lines (%s)" % rows.left(40))
	check(not gm._paused and not get_tree().paused, "pause: «заново» unpauses")
	check(gm.car.body.dent_count == 0, "pause: «заново» repaired the body")
	# «продолжить» must not touch the car: a dent taken before the pause must remain
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	gm._set_paused(true)
	await get_tree().process_frame
	gm.hud.pause_button("ПРОДОЛЖИТЬ").emit_signal("pressed")
	await get_tree().process_frame
	check(not gm._paused and not get_tree().paused, "pause: «продолжить» unpauses")
	check(gm.car.body.dent_count > 0, "pause: «продолжить» does not restart the car")

	# 4c) a high jump must not count as leaving the map: the map has no upper bound,
	# the car must keep falling, not teleport to spawn
	gm.car.respawn(gm._spawn)
	gm.car.chassis.global_position = gm._spawn.origin + Vector3(0, 100, 0)
	gm.car.chassis.linear_velocity = Vector3(20, 0, 0)
	for f in 6:
		await get_tree().physics_frame
	check(gm.car.chassis.global_position.y > 60.0,
		"a jump above the map's top does not trigger a restart (y=%.1f)" % gm.car.chassis.global_position.y)

	# 4d) new HUD elements: the deformation bar reacts to a dent, the frame counter
	# prints a number, and the key-layout line is gone from the screen entirely
	gm._respawn_now()
	for f in 10:
		await get_tree().physics_frame
	# take the impact point from the CURRENT position: nose was computed before the 100 m jump
	var nose2 := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
	gm.car.body.apply_impact(nose2, Vector3(1, 0, 0), 150.0)
	for f in 3:
		await get_tree().process_frame
	check(gm.hud._deform_fill.size.x > 1.0,
		"the body bar fills with the dent (%.1f px)" % gm.hud._deform_fill.size.x)
	check(gm.hud._deform_fill.size.x <= gm.hud._deform_bg.size.x, "the bar does not spill past the panel")
	for f in 100:
		await get_tree().process_frame
	var fps_text: String = gm.hud._fps_label.text
	check("FPS" in fps_text and fps_text.strip_edges().split(" ")[0].is_valid_int(),
		"the frame counter prints a number (%s)" % fps_text)
	# Compare the grip indicator against the very value CarRig exposes: the test cannot
	# hardcode slip — _drive recomputes it every physics tick.
	await get_tree().process_frame
	var want := (1.0 - gm.car.slip) * (gm.hud._slip_bg.size.x - 2.0)
	check(absf(gm.hud._slip_fill.size.x - maxf(want, 0.0)) < 1.5,
		"the grip bar matches the slip (bar=%.1f want=%.1f, slip=%.2f)" % [
			gm.hud._slip_fill.size.x, want, gm.car.slip])
	var shown := ""
	for c in gm.hud.get_children():
		shown += _texts(c)
	check("РУЧНИК" not in shown and "СЛОУ-МО" not in shown and "РЕСТАРТ" not in shown,
		"the key-layout line is removed from the HUD")
	gm.hud.set_fps_visible(false)
	check(not gm.hud._fps_label.visible, "the setting hides the frame counter")
	gm.hud.set_fps_visible(true)

	# 5) return to menu: the harness scene detaches, otherwise it gets torn down with the checks
	get_tree().current_scene = null
	b.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not get_tree().paused, "tree unpaused on menu return")
	check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn",
		"menu button returns to main menu (%s)" % str(get_tree().current_scene.scene_file_path if get_tree().current_scene else null))
	# The main menu no longer prints the key layout under its buttons either: players asked
	# to remove keybinding labels from overlays, not move them from the HUD to here
	var menu_texts := _texts(get_tree().current_scene)
	check("ГАЗ:" not in menu_texts and "РУЧНИК:" not in menu_texts,
		"the menu has no key-layout line (%s)" % menu_texts.left(120))

	# 6) input must not burn the car while paused: steering inherits ALWAYS from the
	# manager, and held throttle+nitro on pause used to drain the tank while the car stood
	Input.action_press("throttle")
	Input.action_press("nitro")
	gm.car.nitro = gm.car.params.nitro_capacity
	gm._set_paused(true)
	for f in 120:
		await get_tree().physics_frame
	Input.action_release("throttle")
	Input.action_release("nitro")
	gm._set_paused(false)
	for f in 10:
		await get_tree().physics_frame
	check(gm.car.nitro >= gm.car.params.nitro_capacity - 0.5,
		"nitro does not drain while paused (%.1f of %.1f)" % [gm.car.nitro, gm.car.params.nitro_capacity])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Only visible controls: the settings screen lives inside the HUD and itself contains
# the words «РУЧНИК», «СЛОУ-МО», «РЕСТАРТ» — while collapsed it proves nothing.
func _texts(n: Node) -> String:
	var out := ""
	if n is Control and not (n as Control).visible: return out
	if n is Label: out += (n as Label).text
	for c in n.get_children():
		out += _texts(c)
	return out

# The innermost Control with mouse_filter != IGNORE covering the point. Walk by
# DEPTH, not width: the overlay dim covers the whole map and catches the mouse too,
# but the button is nested in it and is the one that gets the click.
func _topmost_at(root: Node, p: Vector2) -> Control:
	var found: Control = null
	for c in root.get_children():
		if not (c is Control): continue
		var ctl := c as Control
		# not visible on the node itself — is it visible in the tree: the hidden settings
		# screen's overlay lives in the HUD permanently, and its fullscreen dim would
		# otherwise count as "covering" everything
		if not ctl.is_visible_in_tree(): continue
		if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.get_global_rect().has_point(p):
			found = ctl
		# nesting and child order decide, not an early return: the click goes to the
		# topmost-painted control, i.e. the last matching one
		var deeper := _topmost_at(ctl, p)
		if deeper != null: found = deeper
	return found
