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
	var vp := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var b: Button = gm.hud.pause_button("В ГЛАВНОЕ МЕНЮ")
	check(b != null, "кнопка «В ГЛАВНОЕ МЕНЮ» найдена")
	check(b != null and b.visible, "menu button shown while paused")
	var br := b.get_global_rect()
	check(br.position.x >= 0 and br.position.y >= 0 and br.position.x + br.size.x <= vp.x and br.position.y + br.size.y <= vp.y,
		"menu button inside viewport (%s of %s)" % [str(br), str(vp)])
	check(_topmost_at(gm.hud, br.get_center()) == b, "menu button not covered by another control")

	# 4b) полное меню паузы: четыре кнопки, фокус на первой, управление с геймпада и
	# клавиатуры, «заново» сбрасывает статистику и снимает паузу
	for name in ["ПРОДОЛЖИТЬ", "НАСТРОЙКИ", "ЗАПУСТИТЬ ЗАНОВО", "В ГЛАВНОЕ МЕНЮ"]:
		var pb: Button = gm.hud.pause_button(name)
		check(pb != null and pb.visible, "пауза: кнопка %s на месте" % name)
		check(pb != null and pb.focus_mode == Control.FOCUS_ALL, "пауза: %s доступна с геймпада" % name)
		if pb != null:
			var r := pb.get_global_rect()
			check(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= vp.x and r.end.y <= vp.y,
				"пауза: %s внутри окна (%s)" % [name, str(r)])
			# перекрытость считаем для точки чуть внутри левой границы: центр всех кнопок
			# накрывается затемнением оверлея, а хиттест идёт по самому вложенному контролу
			check(_topmost_at(gm.hud, r.position + Vector2(6, r.size.y * 0.5)) == pb,
				"пауза: %s не перекрыта другой панелью" % name)
	check(gm.hud.pause_button("ПРОДОЛЖИТЬ").has_focus(), "пауза: фокус на первой кнопке")
	# «заново» должна обнулить журнал ударов и снять паузу
	gm._crashes = 3
	gm.hud.pause_button("ЗАПУСТИТЬ ЗАНОВО").emit_signal("pressed")
	await get_tree().process_frame
	check(gm._crashes == 0, "пауза: «заново» сбросила журнал")
	check(not gm._paused and not get_tree().paused, "пауза: «заново» снимает паузу")
	check(gm.car.body.dent_count == 0, "пауза: «заново» починила кузов")
	# «продолжить» не трогает машину: вмятина, полученная до паузы, должна остаться
	gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
	gm._set_paused(true)
	await get_tree().process_frame
	gm.hud.pause_button("ПРОДОЛЖИТЬ").emit_signal("pressed")
	await get_tree().process_frame
	check(not gm._paused and not get_tree().paused, "пауза: «продолжить» снимает паузу")
	check(gm.car.body.dent_count > 0, "пауза: «продолжить» не перезапускает машину")

	# 4c) высокий прыжок не считается вылетом за пределы: верхней границы у карты нет,
	# машина должна продолжать лететь, а не телепортироваться на спавн
	gm.car.respawn(gm._spawn)
	gm.car.chassis.global_position = gm._spawn.origin + Vector3(0, 100, 0)
	gm.car.chassis.linear_velocity = Vector3(20, 0, 0)
	for f in 6:
		await get_tree().physics_frame
	check(gm.car.chassis.global_position.y > 60.0,
		"прыжок выше верхней границы карты не вызывает рестарт (y=%.1f)" % gm.car.chassis.global_position.y)

	# 4d) новые элементы HUD: шкала деформации реагирует на вмятину, счётчик кадров
	# печатает число, а строка с раскладкой клавиш с экрана убрана совсем
	gm._respawn_now()
	for f in 10:
		await get_tree().physics_frame
	# точку удара берём от ТЕКУЩЕГО положения: nose считался до прыжка на 100 м
	var nose2 := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
	gm.car.body.apply_impact(nose2, Vector3(1, 0, 0), 150.0)
	for f in 3:
		await get_tree().process_frame
	check(gm.hud._deform_fill.size.x > 1.0,
		"шкала кузова заполняется вмятиной (%.1f px)" % gm.hud._deform_fill.size.x)
	check(gm.hud._deform_fill.size.x <= gm.hud._deform_bg.size.x, "шкала не вылезает за панель")
	for f in 100:
		await get_tree().process_frame
	var fps_text: String = gm.hud._fps_label.text
	check("FPS" in fps_text and fps_text.strip_edges().split(" ")[0].is_valid_int(),
		"счётчик кадров печатает число (%s)" % fps_text)
	# Индикатор сцепления сверяем с тем же значением, которое отдаёт CarRig: вписать
	# slip из теста нельзя — _drive пересчитывает его каждый тик физики.
	await get_tree().process_frame
	var want := (1.0 - gm.car.slip) * (gm.hud._slip_bg.size.x - 2.0)
	check(absf(gm.hud._slip_fill.size.x - maxf(want, 0.0)) < 1.5,
		"полоса сцепления соответствует скольжению (bar=%.1f want=%.1f, slip=%.2f)" % [
			gm.hud._slip_fill.size.x, want, gm.car.slip])
	var shown := ""
	for c in gm.hud.get_children():
		shown += _texts(c)
	check("РУЧНИК" not in shown and "СЛОУ-МО" not in shown and "РЕСТАРТ" not in shown,
		"с HUD убрана строка с раскладкой клавиш")
	gm.hud.set_fps_visible(false)
	check(not gm.hud._fps_label.visible, "настройка скрывает счётчик кадров")
	gm.hud.set_fps_visible(true)

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

# Только видимые контролы: экран настроек живёт внутри HUD и сам содержит слова
# «РУЧНИК», «СЛОУ-МО», «РЕСТАРТ» — в свёрнутом состоянии он ничего не доказывает.
func _texts(n: Node) -> String:
	var out := ""
	if n is Control and not (n as Control).visible: return out
	if n is Label: out += (n as Label).text
	for c in n.get_children():
		out += _texts(c)
	return out

# Самый вложенный Control с mouse_filter != IGNORE, накрывающий точку. Обходим
# ГЛУБИНОЙ, а не шириной: затемнение оверлея накрывает всю карту и тоже ловит мышь,
# но кнопка вложен в него и получит клик именно она.
func _topmost_at(root: Node, p: Vector2) -> Control:
	for c in root.get_children():
		if not (c is Control) or not c.visible: continue
		var deeper := _topmost_at(c, p)
		if deeper != null: return deeper
	if root is Control and (root as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		if (root as Control).get_global_rect().has_point(p): return root as Control
	return null
