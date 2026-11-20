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
	_seed_mod()
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)

# A mod pack on disk before the menu builds its catalog: the car must reach the
# VEHICLES cards, the MODS panel and VehicleDB without special cases.
func _seed_mod() -> void:
	var root := DirAccess.open("user://")
	if root != null and not root.dir_exists("mods"): root.make_dir("mods")
	var dir := DirAccess.open("user://mods")
	if dir != null and not dir.dir_exists("testpack"): dir.make_dir("testpack")
	var f := FileAccess.open("user://mods/testpack/mod.json", FileAccess.WRITE)
	if f == null: return
	f.store_string('{"name":"Test Pack","version":"1","author":"QA","cars":[{"id":"test_car",'
		+ '"name":"TEST CAR","description":"A modded sedan.","base":"sedan",'
		+ '"color":[0.2,0.8,0.4],"params":{"mass":1200,"vmax_kmh":240,"accel_max":12}}]}')
	f.close()
	ModDB.reload()

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
	for k in ["НАЧАТЬ", "МАШИНЫ", "ГАРАЖ", "КАРТЫ", "ГАЛЕРЕЯ", "СТАТИСТИКА", "МОДЫ", "НАСТРОЙКИ", "ВЫХОД"]:
		nav_expected.append(I18n.t(k))
	check(nav_texts == nav_expected, "navigation content and order (%s)" % str(nav_texts))
	# the default selection is the first car and the first map
	check(mm._car_i == 0 and mm._map_i == 0, "the first entries are selected by default (%d/%d)" % [mm._car_i, mm._map_i])
	# the CARS section: one card per car in the menu list
	for b in btns:
		if b.text == I18n.t("МАШИНЫ"): b.emit_signal("pressed")
	var btns2: Array = []; _buttons(mm, btns2)
	var consts: Dictionary = (mm.get_script() as GDScript).get_script_constant_map()
	var ncars: int = mm.CARS.size()
	check(ncars == (consts["BASE_CARS"] as Array).size() + 1,
		"the catalog is the shipped roster plus one mod car (%d)" % ncars)
	check(mm.CARS.any(func(row: Array) -> bool: return String(row[1]) == "test_car"),
		"the mod car is in the menu catalog")
	var mod_params := VehicleDB.get_params("test_car")
	check(mod_params != null and is_equal_approx(mod_params.vmax_kmh, 240.0),
		"the mod car reaches VehicleDB with its overrides")
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
	# The STATS section: lifetime totals plus per-map/per-car record tables.
	# Seeded here because an empty profile would only prove that the headers fit.
	Stats.maps = {
		"arena": {"runs": 3, "crashes": 2, "best_impact": 150.0, "top_speed": 200.0,
			"distance": 1000.0, "seconds": 30.0, "best_lap": 65.5},
		"speedway": {"runs": 1, "crashes": 1, "best_impact": 90.0, "top_speed": 180.0,
			"distance": 600.0, "seconds": 20.0, "best_lap": 0.0},
	}
	Stats.cars = {
		"sedan": {"runs": 4, "crashes": 3, "best_impact": 155.0, "top_speed": 210.0,
			"distance": 1600.0, "seconds": 50.0, "best_lap": 62.25},
	}
	mm._show_section(5)   # Section.STATS
	var map_grid: GridContainer = mm._panel.find_child("MapRecords", true, false) as GridContainer
	var car_grid: GridContainer = mm._panel.find_child("CarRecords", true, false) as GridContainer
	check(map_grid != null and map_grid.columns == 6, "the stats section has a six-column map table")
	check(car_grid != null and car_grid.columns == 6, "the stats section has a six-column car table")
	check(map_grid != null and map_grid.get_child_count() == 6 * 3,
		"the map table has a header and two record rows (%s)" % [str(map_grid.get_child_count()) if map_grid else "null"])
	check(car_grid != null and car_grid.get_child_count() == 6 * 2,
		"the car table has a header and one record row (%s)" % [str(car_grid.get_child_count()) if car_grid else "null"])
	var stat_texts: Array[String] = []
	for grid in [map_grid, car_grid]:
		if grid == null: continue
		for c in grid.get_children():
			if c is Label: stat_texts.append((c as Label).text)
	check(I18n.t("ЗАЕЗДОВ") in stat_texts and I18n.t("УДАРОВ") in stat_texts,
		"record tables carry the runs/impacts headers")
	check(I18n.t("АРЕНА") in stat_texts and I18n.t("СЕДАН") in stat_texts,
		"record rows use the map and car display names")
	check("1:05.50" in stat_texts and "1:02.25" in stat_texts,
		"best laps are formatted as times (%s)" % str(stat_texts))
	check(I18n.fmt("%d км/ч", [150]) in stat_texts,
		"best impact is shown with units (%s)" % str(stat_texts))
	check("—" in stat_texts, "a map with no lap yet shows a dash, not 0:00.00")
	# The MODS section reports the installed pack and offers a rescan. The pack
	# itself was seeded before the menu was built (see _seed_mod).
	mm._show_section(6)   # Section.MODS
	var mod_labels: Array = []; _labels(mm._panel, mod_labels)
	var mod_texts: Array[String] = []
	for l in mod_labels: mod_texts.append((l as Label).text)
	check(mod_texts.any(func(t: String) -> bool: return t.begins_with("Test Pack")),
		"the mods panel names the pack (%s)" % str(mod_texts))
	check("· TEST CAR (sedan)" in mod_texts, "the mods panel lists the car and its base")
	check(ModDB.errors().is_empty(), "the valid test pack reports no mod errors")
	var mod_btns: Array = []; _buttons(mm, mod_btns)
	var reload_btn: Button = null
	for b in mod_btns:
		if b.text == I18n.t("ПЕРЕЗАГРУЗИТЬ"): reload_btn = b
	check(reload_btn != null, "the mods panel has a reload button")
	if reload_btn != null:
		reload_btn.emit_signal("pressed")
		check(mm.CARS.size() == ncars, "a rescan keeps the mod car in the catalog")
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
	# The section panel never outgrows the window: in the editor's embedded
	# panel (745x253 in the report) the panel used to be cut by the window edge
	# with no scroll. The live min_size clamps the request to 800x450, and
	# _fit_panel caps the panel to the window height; both are measured here.
	get_window().size = Vector2i(745, 253)
	UiTheme.force_step(1)
	mm._show_section(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var pr: Rect2 = Rect2(mm._panel.position, mm._panel.size)
	check(pr.end.y <= get_window().size.y,
		"the section panel stays inside a tiny window (%s vs %s)" % [str(pr), str(get_window().size)])
	check(pr.end.x <= get_window().size.x, "the section panel stays inside in width (%s)" % str(pr))
	get_window().size = Vector2i(1600, 900)
	UiTheme.force_step(0)
	# the rebuild above freed the old launch button (_show_section tears the
	# panel down and builds a fresh one) — re-capture before pressing
	var btns5: Array = []; _buttons(mm, btns5)
	for b in btns5:
		if b.text == I18n.t("ЗАПУСТИТЬ СИМУЛЯЦИЮ"): startb = b
	check(is_instance_valid(startb), "the launch button survived the section rebuild")
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
