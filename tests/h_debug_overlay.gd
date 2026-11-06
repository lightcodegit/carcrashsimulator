extends Node
# Отладочный оверлей: включён → панель существует; каждая из четырёх секций
# печатает непустой текст без nan/inf; F2 и F3 работают через настоящий InputMap
# (синтезированное событие), а настройка доживает до файла и обратно.
var _fails := 0
var gm: GameManager
var hud: HUD
var overlay: Control

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(1600, 900)
	Settings.debug_mode = true
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	hud = gm.hud
	overlay = _find_overlay(hud)
	check(overlay != null, "оверлей собран вместе с HUD")
	if overlay == null:
		print("FAILS %d" % _fails); get_tree().quit(1); return
	check(hud._gameplay.has(overlay), "оверлей учтён в списке геймплейных панелей")

	# Раскладка: оверлей обязан влезать в экран и не наезжать на остальные панели.
	# Проверяем здесь, а не в h_hud_layout: у того свой бюджет надписей и закрытой
	# площади, и влезать в него чужой панелью значит портить его контракт.
	var rect := overlay.get_global_rect()
	var view := get_viewport().get_visible_rect()
	check(rect.position.x >= 0 and rect.position.y >= 0
		and rect.end.x <= view.size.x and rect.end.y <= view.size.y,
		"оверлей внутри экрана (%s в %s)" % [str(rect), str(view.size)])
	var hits := 0
	for p in hud._gameplay:
		if p == overlay: continue
		if rect.intersects(p.get_global_rect()): hits += 1
	check(hits == 0, "оверлей не наезжает на панели HUD (%d)" % hits)

	# контракт данных: оверлей читает снимки, а не приватные поля
	var snap: Dictionary = gm.car.debug_snapshot()
	for key in ["speed_kmh", "steer_deg", "steer_max_deg", "slip", "grounded",
		"pedal", "hand", "heading_deg", "contacts", "skid"]:
		check(snap.has(key), "снимок машины отдаёт ключ %s" % key)
	check(is_finite(float(snap.speed_kmh)) and is_finite(float(snap.steer_deg)),
		"числа снимка конечны")
	var scene: Dictionary = gm.debug_scene()
	for key in ["map_root", "bounds", "spawn", "endless", "map_id", "crashes"]:
		check(scene.has(key), "снимок сцены отдаёт ключ %s" % key)
	var counts := MapDB.debug_counts(scene.map_root, gm.camera.global_position)
	check(int(counts.nodes) > 100, "обход дерева нашёл узлы (%d)" % int(counts.nodes))
	check(int(counts.bodies) > 0, "на карте есть динамические тела (%d)" % int(counts.bodies))

	# секции: F3 листает, текст обязан быть живым
	for i in 30:
		await get_tree().process_frame
	# Счётчики кадра существуют только при живом рендере: в headless движок не
	# считает вызовы отрисовки, и «ноль» там — не поломка, а отсутствие GPU.
	if DisplayServer.get_name() != "headless":
		var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		check(calls > 0, "под живым рендером вызовы отрисовки nonzero (%d)" % calls)
	else:
		print("PARTIAL: вызовы отрисовки под headless не меряются")
	var seen := {}
	for i in 4:
		var text := String(overlay._label.text)
		check(text.length() > 24, "секция %d печатает текст (%d симв.)" % [i, text.length()])
		check(text.begins_with("DEBUG · "), "секция %d подписана (%s)" % [i, text.left(16)])
		check("nan" not in text.to_lower() and "inf" not in text.to_lower(),
			"в секции %d нет nan/inf" % i)
		# Моноширинный 14px даёт ~8.4 px на символ, поле подписи — 348 px. Длиннее —
		# и текст режется по краю панели, что ровно то, что поймал первый скриншот.
		var widest := 0
		for line in text.split("\n"):
			widest = maxi(widest, String(line).length())
		check(widest <= 41, "ни одна строка секции %d не обрезается (самая длинная %d)" % [i, widest])
		print("секция %d: %s" % [i, text.replace("\n", " · ").strip_edges().left(150)])
		seen[text.left(12)] = true
		_press("debug_section")
		await get_tree().process_frame
	check(seen.size() == 4, "четыре секции дают четыре разных заголовка (%d)" % seen.size())

	# выключение: панель уходит из дерева, а список панелей перестаёт её учитывать.
	# has() на освобождённом объекте в TypedArray запрещён движком, поэтому сверяем
	# длину списка до и после, а не ищем в нём уже несуществующий узел.
	var panels_before := hud._gameplay.size()
	_press("debug_toggle")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not Settings.debug_mode, "F2 выключил режим (настройка flipped)")
	check(_find_overlay(hud) == null, "после выключения оверлея нет в дереве")
	check(hud._gameplay.size() == panels_before - 1,
		"панель убрана из списка геймплейных (%d → %d)" % [panels_before, hud._gameplay.size()])
	_press("debug_toggle")
	await get_tree().process_frame
	check(Settings.debug_mode and _find_overlay(hud) != null, "F2 включил режим обратно")

	# На паузе оверлей обязан жить: именно на паузе удобнее читать цифры. HUD
	# переводится в ALWAYS, оверлей наследует его — проверяем, а не предполагаем.
	gm._set_paused(true)
	await get_tree().process_frame
	var ov := _find_overlay(hud)
	var before := String(ov._label.text)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	ov.call("_unhandled_input", ev)
	await get_tree().process_frame
	check(String(ov._label.text) != before, "F3 работает на паузе")
	gm._set_paused(false)
	await get_tree().process_frame

	# настройка проходит путь файл → загрузка
	Settings.debug_mode = false
	Settings.save()
	var cf := ConfigFile.new()
	check(cf.load("user://settings.cfg") == OK, "cfg перечитывается")
	var raw: Variant = cf.get_value("video", "debug_mode", null)
	check(raw == false, "в файл записано false (%s)" % str(raw))
	Settings.debug_mode = true
	Settings.save()
	Settings.debug_mode = false
	Settings.load_values()
	check(Settings.debug_mode, "true доживает до следующей загрузки")

	Settings.debug_mode = false
	Settings.save()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _find_overlay(h: HUD) -> Control:
	for c in h.get_children():
		if c is CanvasLayer: continue
		var root := c as Control
		if root == null: continue
		for k in root.get_children():
			if k.get_script() != null and String(k.get_script().resource_path).ends_with("debug_overlay.gd"):
				return k
	return null

# Синтезированное событие проходит через InputMap: так проверка заодно подтверждает,
# что действия debug_toggle и debug_section зарегистрированы на F2 и F3.
func _press(action: String) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F2 if action == "debug_toggle" else KEY_F3
	ev.pressed = true
	var handled := false
	for node in [hud, overlay]:
		if node == null or not is_instance_valid(node): continue
		node.call("_unhandled_input", ev)
		handled = true
	check(handled, "обработчик %s вызван" % action)
