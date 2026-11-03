extends Node3D
# h_wrap: регресс-тесты на три починенных системы — перестановка бесконечной
# ленты, стойкость загрузки клавиш к чужим ключам в конфиге и валидация id.
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _physics_process(_dt: float) -> void:
	_wrap()
	_keys()
	_context()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---- лента «бесконечности»: без нахлёста, коллайдеры при плитах, барьеры едут,
# телепорт назад возвращает дорогу под машину
func _wrap() -> void:
	var m: Dictionary = MapDB.build("endless")
	var root: Node3D = m.root
	add_child(root)
	var plates: Array[Node3D] = []
	var solids: Array[Node3D] = []
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		if String(mi.name).begins_with("kit_road"):
			plates.append(mi)
			if String(mi.name).contains("roadBump") or String(mi.name).contains("roadRampLong"):
				solids.append(mi)
	var bar0 := INF
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_barrierWall"):
			bar0 = minf(bar0, mi.position.x)
	var car_x := -20.0
	while car_x < 6000.0:
		car_x += 50.0
		MapDB.recycle(root, car_x, 20.0)
	var seen := {}
	var dupes := 0
	for mi in plates:
		var k := "%.0f|%.0f" % [mi.position.x, mi.position.z]
		if seen.has(k): dupes += 1
		seen[k] = true
	# пустой список дал бы «0 внахлёст» и «0 сирот» — то есть зелёный тест без проверки
	check(plates.size() > 0, "плит собрано для сравнения %d" % plates.size())
	check(solids.size() > 0, "твёрдых плит собрано %d" % solids.size())
	check(dupes == 0, "после трёх с лишним оборотов ленты нет плит внахлёст (dupes=%d)" % dupes)
	var orphan := 0
	for mi in solids:
		var body := root.get_node_or_null(NodePath("col_" + mi.name))
		if body == null or absf(body.position.x - mi.position.x) > 0.01: orphan += 1
	check(orphan == 0, "у каждой твёрдой плиты её коллайдер рядом (orphans=%d из %d)" % [orphan, solids.size()])
	var bar1 := INF
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_barrierWall"):
			bar1 = minf(bar1, mi.position.x)
	check(bar1 > bar0, "отбойники переставляются вместе с лентой (мин x %.0f -> %.0f)" % [bar0, bar1])
	# телепорт назад: дорога обязана вернуться под стартовую точку. В живом заезде
	# recycle зовётся каждый физический кадр, здесь те же пять вызовов подряд
	for _i in 5: MapDB.recycle(root, -20.0, 20.0)
	var covered := false
	for mi in plates:
		if mi.position.x <= -20.0 and mi.position.x + MapDB._advance_of(mi) >= -20.0:
			covered = true
	check(covered, "после возврата машины на старт полотно легло под спавн (x=-20)")
	root.queue_free()

# ---- [keys] с чужим ключом: загрузка не обрывается, валидные бинды доходят
func _keys() -> void:
	var cf := ConfigFile.new()
	cf.set_value("keys", "throttle", "k84")
	cf.set_value("keys", "ghost_from_future", "k57")
	cf.set_value("keys", "respawn", "k82")
	InputRouter.load_keys(cf)
	var got := false
	for e in InputMap.action_get_events("throttle"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_T: got = true
	check(got, "перебинд throttle на T загрузился, несмотря на чужой ключ в файле")
	var back := false
	for e in InputMap.action_get_events("respawn"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_R: back = true
	check(back, "бинды после чужого ключа не потерялись (respawn=R)")
	InputRouter.reset_keys()

# ---- GameContext: мусорный id не доживает до сборки заезда
func _context() -> void:
	GameContext.select("bogus_car", "bogus_map")
	check(GameContext.car_id != "bogus_car" and GameContext.map_id != "bogus_map",
		"мусорные id отклонены (%s / %s)" % [GameContext.car_id, GameContext.map_id])
	var p := VehicleDB.get_params(GameContext.car_id)
	check(p != null, "после отклонения машину можно собрать (params != null)")
