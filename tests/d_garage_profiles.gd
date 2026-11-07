extends SceneTree
var fails := 0
const PATH := "user://garage_v1.json"

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func put(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/core/garage_profiles.gd"):
		check(false, "garage profile service missing")
		quit(1)
		return
	var service = load("res://scripts/core/garage_profiles.gd")
	var store = service.new()
	for id in VehicleDB.ids():
		var stock := VehicleDB.get_params(id)
		var effective: VehicleParams = store.effective_params(id)
		for prop in stock.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				check(stock.get(prop.name) == effective.get(prop.name), id + " absent profile preserves " + prop.name)
	check(not FileAccess.file_exists(PATH), "reads never write")
	store.select_vehicle("sedan")
	store.set_value("accel_max", 9.0)
	store.set_value("paint_color", [0.1, 0.8, 0.3])
	check(store.draft_params().accel_max == 9.0, "draft applies live")
	check(store.effective_params("sedan").accel_max == 7.0, "unsaved draft not effective")
	check(not FileAccess.file_exists(PATH), "editing never writes")
	store.cancel()
	check(store.draft_params().accel_max == 7.0, "cancel restores stock")
	store.set_value("accel_max", 9.0)
	store.set_value("paint_color", [0.1, 0.8, 0.3])
	check(store.save() == OK, "save succeeds")
	var saved_text := FileAccess.get_file_as_string(PATH)
	var reload = service.new()
	check(reload.effective_params("sedan").accel_max == 9.0, "fresh store reloads disk")
	check(reload.effective_params("pickup").accel_max == 6.0, "per-car isolation")
	check(VehicleDB.get_params("sedan").accel_max == 7.0, "stock factory stays pure")
	store.factory_reset()
	check(store.draft_params().accel_max == 7.0, "factory changes draft")
	check(FileAccess.get_file_as_string(PATH) == saved_text, "factory never writes")
	store.cancel()
	check(store.draft_params().accel_max == 9.0, "cancel factory restores saved")
	store.select_vehicle("pickup")
	store.set_value("accel_max", 8.0)
	check(store.save() == OK, "second car save")
	check(service.new().effective_params("sedan").accel_max == 9.0, "saving second car retains first")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check(document.version == 1 and document.vehicles.size() == 2, "versioned one record per vehicle")
	check(not FileAccess.file_exists(PATH + ".tmp"), "atomic save consumes temporary file")
	store.select_vehicle("sedan")
	store.factory_reset()
	check(store.save() == OK and service.new().effective_params("sedan").accel_max == 7.0, "factory saved explicitly")
	for bad in ["{broken", "[]", '{"version":2,"vehicles":{"sedan":{"accel_max":9}}}', '{"version":1,"vehicles":[]}', '{"version":1,"vehicles":{"sedan":null}}']:
		put(bad)
		check(service.new().effective_params("sedan").accel_max == 7.0, "malformed/unsupported file falls back")
	put('{"version":1,"vehicles":{"unknown":{"accel_max":9},"sedan":{"accel_max":"9","mass":1,"grip":1e99,"nitro_accel":true,"paint_color":[1,0],"suspension_stiffness":-99}}}')
	var hostile = service.new()
	var p: VehicleParams = hostile.effective_params("sedan")
	check(p.accel_max == 7 and p.mass == 1300 and p.nitro_accel == 9, "wrong types and unknown fields ignored")
	check(p.grip == 14 and p.suspension_stiffness == 60, "finite bounds clamped")
	hostile.select_vehicle("sedan")
	for value in [NAN, INF, -INF, "nan", null, {}, true]:
		hostile.set_value("accel_max", value)
		check(hostile.draft_params().accel_max == 7, "non numeric/nonfinite input rejected")
	hostile.set_value("paint_color", [NAN, 0, 1])
	check(hostile.draft_params().paint_color == VehicleDB.get_params("sedan").paint_color, "nonfinite color rejected")
	hostile.set_value("paint_color", [-1, 2, 0.5])
	check(hostile.draft_params().paint_color == Color(0, 1, 0.5), "color channels bounded")
	check(not hostile.select_vehicle("../../unknown"), "unknown id rejected")
	var blocked = service.new("user://missing/garage.json")
	blocked.select_vehicle("sedan")
	blocked.set_value("accel_max", 9.0)
	check(blocked.save() != OK and not blocked.last_error.is_empty(), "write error exposed")
	check(blocked.effective_params("sedan").accel_max == 7, "failed save never changes saved state")
	DirAccess.make_dir_absolute(PATH + ".tmp")
	var before := FileAccess.get_file_as_string(PATH)
	hostile.set_value("accel_max", 9.0)
	check(hostile.save() != OK, "blocked temporary file fails")
	check(FileAccess.get_file_as_string(PATH) == before, "failed save preserves old file")
	DirAccess.remove_absolute(PATH + ".tmp")
	# файл без версии — ручная правка или формат до версионирования: профили в нём
	# те же самые, и запирать из-за этого сохранение нельзя
	put('{"vehicles":{"sedan":{"accel_max":9.0}}}')
	var unversioned = service.new()
	check(unversioned.effective_params("sedan").accel_max == 9.0,
		"файл без version принят как свой")
	unversioned.select_vehicle("sedan")
	unversioned.set_value("accel_max", 8.0)
	check(unversioned.save() == OK, "и после такого файла сохранение работает")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check(doc is Dictionary and (doc as Dictionary).get("version") == 1,
		"записанный файл снова с версией")
	put('{"version":1.0,"vehicles":{"sedan":{"accel_max":9.0}}}')
	check(service.new().effective_params("sedan").accel_max == 9.0,
		"version, записанная как 1.0, читается")
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
