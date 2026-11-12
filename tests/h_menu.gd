extends Control
# A BeamNG-style menu: a live 3D background under the CanvasLayer, a left navigation of
# six text items, and a right panel that switches sections. We check the structure,
# section switching, the car/map selection and the transition into the game.
var _fails := 0
var _f := 0
var mm: Node3D

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _design_size() -> Vector2:
	# under a headless window the logical viewport does not match the design 1600×900, so
	# measurement must use the actual visible rectangle
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
	# nodes created by code carry auto names (@CanvasLayer@N) — so we match by class
	for c in mm.get_children():
		if c is CanvasLayer:
			return (c as CanvasLayer).get_node("Root") as Control
	return null

func _ready() -> void:
	# the headless window is 64×64 (with 2D scaling the engine used to substitute a
	# 1600×1600 square for it, and the tests measured something else than the player sees).
	# The grid size is set explicitly.
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
		"the menu layer stretches over the viewport (%s vs %s)" % [str(ui.size), str(get_viewport().get_visible_rect().size)])
	var labels: Array = []; _labels(mm, labels)
	var has_crash := false
	var has_sim := false
	for l in labels:
		if l.text == "CAR CRASH": has_crash = true
		if l.text == "SIMULATOR": has_sim = true
		var r: Rect2 = l.get_global_rect()
		check(r.position.x >= -1 and r.position.y >= -1 and r.position.x + r.size.x <= vp.x + 1 and r.position.y + r.size.y <= vp.y + 1,
			"label %s inside viewport (%s)" % [l.text.substr(0, 18), str(r)])
	check(has_crash and has_sim, "the logo is two lines (CAR CRASH + SIMULATOR)")
	# live background: a camera and a car in the scene
	check(mm.get_node_or_null("Camera3D") != null or mm._cam != null, "the background has a camera")
	check(mm._car_model != null and is_instance_valid(mm._car_model), "a car model stands in the background")
	# Every section exactly once and in navigation order, including the new garage.
	var btns: Array = []; _buttons(mm, btns)
	var nav_texts: Array[String] = []
	for b in mm._nav:
		nav_texts.append(b.text)
		check(btns.has(b), "navigation item is visible: " + b.text)
	var nav_expected: Array[String] = []
	for k in ["НАЧАТЬ", "МАШИНЫ", "ГАРАЖ", "КАРТЫ", "ГАЛЕРЕЯ", "СТАТИСТИКА", "НАСТРОЙКИ", "ВЫХОД"]:
		nav_expected.append(I18n.t(k))
	check(nav_texts == nav_expected, "navigation content and order (%s)" % str(nav_texts))
	# the default selection is the first car and the first map
	check(mm._car_i == 0 and mm._map_i == 0, "the first entries are selected by default (%d/%d)" % [mm._car_i, mm._map_i])
	# the CARS section: one card per car in the menu list
	for b in btns:
		if b.text == I18n.t("МАШИНЫ"): b.emit_signal("pressed")
	var btns2: Array = []; _buttons(mm, btns2)
	var consts: Dictionary = (mm.get_script() as GDScript).get_script_constant_map()
	var ncars: int = (consts["CARS"] as Array).size()
	var cards := 0
	for b in btns2:
		if b.has_meta("car_i"): cards += 1
	check(cards == ncars, "the CARS section has one card per car (%d of %d)" % [cards, ncars])
	# the MAPS section: one card per map
	for b in btns2:
		if b.text == I18n.t("КАРТЫ"): b.emit_signal("pressed")
	var btns3: Array = []; _buttons(mm, btns3)
	var nmaps: int = (consts["MAPS"] as Array).size()
	var mcards := 0
	for b in btns3:
		if b.has_meta("map_i"): mcards += 1
	check(mcards == nmaps, "the MAPS section has one card per map (%d of %d)" % [mcards, nmaps])
	# the selection only reaches GameContext when starting: a click alone only sets state
	mm.select_car(1)
	mm.select_map(2)
	check(mm._car_i == 1 and mm._map_i == 2, "the selection changes (car %d map %d)" % [mm._car_i, mm._map_i])
	check(mm._car_model != null and is_instance_valid(mm._car_model),
		"switching the car swaps the model in the live background")
	# the START section: the big launch button
	for b in btns3:
		if b.text == I18n.t("НАЧАТЬ"): b.emit_signal("pressed")
	var btns4: Array = []; _buttons(mm, btns4)
	var startb: Button = null
	for b in btns4:
		if b.text == I18n.t("ЗАПУСТИТЬ СИМУЛЯЦИЮ"): startb = b
	check(startb != null, "the START section has a launch button")
	var br: Rect2 = startb.get_global_rect()
	check(br.position.x > 0 and br.position.y > 0 and br.position.x + br.size.x < vp.x and br.position.y + br.size.y < vp.y,
		"the launch button is inside the frame (%s)" % str(br))
	# the transition: the harness scene must not be current_scene, otherwise a scene change tears it down
	get_tree().current_scene = null
	startb.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameContext.car_id == "pickup" and GameContext.map_id == "speedway",
		"the selection reached GameContext (%s/%s)" % [GameContext.car_id, GameContext.map_id])
	var gm: Node = get_tree().current_scene
	check(gm is GameManager, "starting opens the game scene (%s)" % str(gm))
	check(gm is GameManager and gm.car != null and gm.hud != null and gm.camera != null, "game scene wired")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
