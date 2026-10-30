extends Node3D
# Флоу-регрессии: пауза/выход из паузы, респавн без фантомного удара,
# затухание огня после респавна, возврат в меню из оверлея паузы.
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
	await get_tree().process_frame
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 20:
		await get_tree().physics_frame
	gm.car.impact.connect(func(_s, _p, _n): _impacts += 1)

	# 1) фантомный удар при респавне: скорость пика должна сбрасываться
	gm.car._recent_speed = 120.0
	gm._respawn_now()
	for f in 20:
		await get_tree().physics_frame
	check(_impacts == 0, "no phantom impact right after respawn (%d)" % _impacts)

	# 2) вмятина появляется и полностью сбрасывается респавном
	var nose := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	check(gm.car.body.dent_count == 1, "dent applied")
	check(gm.car.body.deformation() > 0.05, "body deformed (%.2f м)" % gm.car.body.deformation())
	gm._respawn_now()
	check(gm.car.body.dent_count == 0, "dent count cleared after respawn")
	check(gm.car.body.deformation() < 1e-6, "body restored after respawn (%.6f)" % gm.car.body.deformation())

	# 3) Esc — пауза, R на паузе игнорируется, Esc — выход
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check(gm._paused and get_tree().paused, "esc pauses")
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	_key(KEY_R)
	await get_tree().process_frame
	check(gm.car.body.dent_count > 0, "respawn ignored while paused")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not gm._paused and not get_tree().paused, "esc resumes")
	_key(KEY_R)
	await get_tree().physics_frame
	check(gm.car.body.dent_count == 0, "respawn works while running")

	# 4) кнопка «В МЕНЮ» в оверлее паузы: видима, в пределах окна, ничем не перекрыта
	gm._set_paused(true)
	await get_tree().process_frame
	var b: Button = gm.hud._menu_button
	check(b.visible, "menu button shown while paused")
	var vp := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var br := b.get_global_rect()
	check(br.position.x >= 0 and br.position.y >= 0 and br.position.x + br.size.x <= vp.x and br.position.y + br.size.y <= vp.y,
		"menu button inside viewport (%s of %s)" % [str(br), str(vp)])
	check(_topmost_at(gm.hud, br.get_center()) == b, "menu button not covered by another control")

	# 5) возврат в меню: сцена-харнес отцепляется, иначе её снесёт вместе с проверками
	get_tree().current_scene = null
	b.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not get_tree().paused, "tree unpaused on menu return")
	check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn",
		"menu button returns to main menu (%s)" % str(get_tree().current_scene.scene_file_path if get_tree().current_scene else null))
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Последний по порядку отрисовки Control с mouse_filter != IGNORE, накрывающий точку:
# GUI-хиттест Godot идёт в обратном порядке, значит именно он получит клик.
func _topmost_at(root: Node, p: Vector2) -> Control:
	var found: Control = null
	for c in root.get_children():
		if c is Control and c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if c.get_global_rect().has_point(p): found = c
		var deeper := _topmost_at(c, p)
		if deeper != null: found = deeper
	return found
