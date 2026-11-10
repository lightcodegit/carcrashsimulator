extends Node
# The car and map choice survives exiting to the menu and out of the game: select writes
# last_car/last_map into settings.cfg, the menu raises card highlighting via
# GameContext, and the loading screen is dimmed when the scene is ready and does not
# loom over the game.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)

	# 1) select persists the choice and validates garbage
	GameContext.select("pickup", "bigcity")
	check(GameContext.car_id == "pickup" and GameContext.map_id == "bigcity",
		"select applies valid ids (%s/%s)" % [GameContext.car_id, GameContext.map_id])
	check(Settings.last_car == "pickup" and Settings.last_map == "bigcity",
		"selection persisted to settings (%s/%s)" % [Settings.last_car, Settings.last_map])
	GameContext.select("nonexistent_car", "nonexistent_map")
	check(GameContext.car_id == "pickup" and GameContext.map_id == "bigcity",
		"garbage ids do not stick (%s/%s)" % [GameContext.car_id, GameContext.map_id])
	var cf := ConfigFile.new()
	check(cf.load("user://settings.cfg") == OK, "settings.cfg readable")
	check(String(cf.get_value("video", "last_car", "")) == "pickup",
		"last_car written to disk (%s)" % str(cf.get_value("video", "last_car", "")))

	# 2) the menu raises the choice from GameContext: cards do not reset to the first ones
	GameContext.select("sport", "speedway")
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	for i in 3: await get_tree().process_frame
	check(mm._car_i == 2 and mm._map_i == 2,
		"menu restores the current selection (%d/%d)" % [mm._car_i, mm._map_i])
	mm.queue_free()
	await get_tree().process_frame

	# 3) loading screen: shows on request, dims when ready
	check(not GameContext.loading_visible(), "loading screen hidden by default")
	GameContext.loading_show()
	check(GameContext.loading_visible(), "loading screen shows on request")
	GameContext._loading_until_ms = 0   # the test does not wait out the minimum hold
	GameContext.loading_hide()
	await get_tree().process_frame
	check(not GameContext.loading_visible(), "loading screen hides once the scene is ready")

	if _fails == 0: print("ALL PASS")
	else: print("FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
