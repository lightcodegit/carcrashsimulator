extends Control
# Меню BeamNG-образного вида: живой 3D-фон под CanvasLayer, левая навигация из
# пяти текстовых пунктов, правая панель меняет раздел. Проверяем структуру,
# переключение разделов, выбор машины/карты и переход в игру.
var _fails := 0
var _f := 0
var mm: Node3D

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _design_size() -> Vector2:
	# при headless окне логический вьюпорт не совпадает с дизайн-1600×900, мерить
	# надо по фактическому видимому прямоугольнику
	return get_viewport().get_visible_rect().size

func _labels(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Control and not (c as Control).visible: continue
		if c is Label: out.append(c)
		_labels(c, out)

func _buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Control and not (c as Control).visible: continue
		if c is Button and not (c is OptionButton): out.append(c)
		_buttons(c, out)

func _ui_root() -> Control:
	# узлы, созданные кодом, носят автоимена (@CanvasLayer@N) — ищем по классу
	for c in mm.get_children():
		if c is CanvasLayer:
			return (c as CanvasLayer).get_node("Root") as Control
	return null

func _ready() -> void:
	# headless-окно — 64×64 (с 2D-масштабированием движок подставлял вместо него
	# квадрат 1600×1600, и тесты мерили не то, что видит игрок). Сетку задаём явно.
	get_window().size = Vector2i(1600, 900)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)

func _process(_d: float) -> void:
	_f += 1
	if _f != 8: return
	var vp := _design_size()
	var ui := _ui_root()
	check(ui.size == get_viewport().get_visible_rect().size,
		"слой меню растянут на вьюпорт (%s vs %s)" % [str(ui.size), str(get_viewport().get_visible_rect().size)])
	var labels: Array = []; _labels(mm, labels)
	var has_crash := false
	var has_sim := false
	for l in labels:
		if l.text == "CAR CRASH": has_crash = true
		if l.text == "SIMULATOR": has_sim = true
		var r: Rect2 = l.get_global_rect()
		check(r.position.x >= -1 and r.position.y >= -1 and r.position.x + r.size.x <= vp.x + 1 and r.position.y + r.size.y <= vp.y + 1,
			"label %s inside viewport (%s)" % [l.text.substr(0, 18), str(r)])
	check(has_crash and has_sim, "логотип из двух строк (CAR CRASH + SIMULATOR)")
	# живой фон: камера и машина в сцене
	check(mm.get_node_or_null("Camera3D") != null or mm._cam != null, "в фоне есть камера")
	check(mm._car_model != null and is_instance_valid(mm._car_model), "в фоне стоит модель машины")
	# навигация: ровно пять пунктов с нужными подписями
	var btns: Array = []; _buttons(mm, btns)
	var nav_texts: Array[String] = []
	for b in btns:
		if ["НАЧАТЬ", "МАШИНЫ", "КАРТЫ", "НАСТРОЙКИ", "ВЫХОД"].has(b.text): nav_texts.append(b.text)
	check(nav_texts.size() == 5, "пять пунктов навигации (%s)" % str(nav_texts))
	# выбор по умолчанию — первая машина и первая карта
	check(mm._car_i == 0 and mm._map_i == 0, "по умолчанию выбраны первые (%d/%d)" % [mm._car_i, mm._map_i])
	# раздел МАШИНЫ: карточка на каждую машину из списка меню
	for b in btns:
		if b.text == "МАШИНЫ": b.emit_signal("pressed")
	var btns2: Array = []; _buttons(mm, btns2)
	var consts: Dictionary = (mm.get_script() as GDScript).get_script_constant_map()
	var ncars: int = (consts["CARS"] as Array).size()
	var cards := 0
	for b in btns2:
		if b.has_meta("car_i"): cards += 1
	check(cards == ncars, "в разделе МАШИНЫ карточка на каждую (%d из %d)" % [cards, ncars])
	# раздел КАРТЫ: карточка на каждую карту
	for b in btns2:
		if b.text == "КАРТЫ": b.emit_signal("pressed")
	var btns3: Array = []; _buttons(mm, btns3)
	var nmaps: int = (consts["MAPS"] as Array).size()
	var mcards := 0
	for b in btns3:
		if b.has_meta("map_i"): mcards += 1
	check(mcards == nmaps, "в разделе КАРТЫ карточка на каждую (%d из %d)" % [mcards, nmaps])
	# выбор доживает до GameContext только по запуску: сам клик — только состояние
	mm.select_car(1)
	mm.select_map(2)
	check(mm._car_i == 1 and mm._map_i == 2, "выбор меняется (car %d map %d)" % [mm._car_i, mm._map_i])
	check(mm._car_model != null and is_instance_valid(mm._car_model),
		"смена машины подменяет модель в живом фоне")
	# раздел НАЧАТЬ: большая кнопка запуска
	for b in btns3:
		if b.text == "НАЧАТЬ": b.emit_signal("pressed")
	var btns4: Array = []; _buttons(mm, btns4)
	var startb: Button = null
	for b in btns4:
		if b.text == "ЗАПУСТИТЬ СИМУЛЯЦИЮ": startb = b
	check(startb != null, "в разделе НАЧАТЬ есть кнопка запуска")
	var br: Rect2 = startb.get_global_rect()
	check(br.position.x > 0 and br.position.y > 0 and br.position.x + br.size.x < vp.x and br.position.y + br.size.y < vp.y,
		"кнопка запуска внутри кадра (%s)" % str(br))
	# переход: сцена-харнес не должна быть current_scene, иначе её снесёт смена сцены
	get_tree().current_scene = null
	startb.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameContext.car_id == "pickup" and GameContext.map_id == "speedway",
		"выбор доехал до GameContext (%s/%s)" % [GameContext.car_id, GameContext.map_id])
	var gm: Node = get_tree().current_scene
	check(gm is GameManager, "запуск открывает игровую сцену (%s)" % str(gm))
	check(gm is GameManager and gm.car != null and gm.hud != null and gm.camera != null, "game scene wired")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
