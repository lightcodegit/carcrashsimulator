extends SceneTree
# Mods are player-supplied data, so the loader is a security boundary as much as
# a feature: every hostile shape below must be rejected or clamped and reported,
# never reach the simulation as a NaN, a negative mass or an arbitrary resource.
#
# The test writes into the isolated user:// the runner provides, then calls
# ModDB.reload() explicitly: the static loader is lazy and one-shot.

var fails := 0
const DIR := "user://mods"

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func mkdirs(folder: String) -> void:
	var root := DirAccess.open("user://")
	if root == null: return
	if not root.dir_exists("mods"): root.make_dir("mods")
	var mods := DirAccess.open(DIR)
	if mods == null: return
	if not mods.dir_exists(folder): mods.make_dir(folder)

func put(folder: String, text: String) -> void:
	mkdirs(folder)
	var f := FileAccess.open("%s/%s/mod.json" % [DIR, folder], FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()

func has_error(fragment: String) -> bool:
	for e in ModDB.errors():
		if String(e).contains(fragment): return true
	return false

func _initialize() -> void:
	# An empty user://mods is not an error: a fresh install ships no mods.
	ModDB.reload()
	check(ModDB.mods().is_empty(), "an empty mods folder loads nothing")
	check(ModDB.errors().is_empty(), "an empty mods folder reports nothing")
	check(ModDB.mods_total_cars() == 0, "an empty mods folder has no cars")

	# A valid pack: one car based on the sedan with physics and color overrides.
	put("01_tuner", JSON.stringify({
		"name": "Tuner Pack", "version": "1.2", "author": "QA",
		"cars": [{
			"id": "tuned_sedan", "name": "Tuned Sedan",
			"description": "A test car.", "base": "sedan",
			"color": [0.2, 0.9, 0.4],
			"params": {"mass": 1550, "accel_max": 9.5, "vmax_kmh": 230,
				"brake_decel": 14, "grip": 9.5, "nitro_capacity": 120,
				"nitro_accel": 8},
		}],
	}))
	ModDB.reload()
	check(ModDB.errors().is_empty(), "a valid pack reports no errors (%s)" % str(ModDB.errors()))
	check(ModDB.mods().size() == 1, "the valid pack is loaded")
	check(ModDB.mods()[0]["name"] == "Tuner Pack", "the pack keeps its name")
	check(VehicleDB.ids().has("tuned_sedan"), "the mod car joins VehicleDB.ids()")
	var p := VehicleDB.get_params("tuned_sedan")
	check(p != null, "the mod car has parameters")
	if p != null:
		check(p.car_id == "tuned_sedan", "the mod id becomes car_id")
		check(p.mass == 1550.0, "mass override applies (%.0f)" % p.mass)
		check(p.accel_max == 9.5, "accel override applies (%.1f)" % p.accel_max)
		check(p.vmax_kmh == 230.0, "top speed override applies (%.0f)" % p.vmax_kmh)
		check(p.nitro_accel == 8.0 and p.nitro_capacity == 120.0, "nitro overrides apply")
		check(p.model == VehicleDB.get_params("sedan").model, "the base model is inherited")
		check(p.length > 2.0 and p.wheel_r > 0.2, "dimensions are derived from the model")
		check(p.accent_color.is_equal_approx(Color(0.2, 0.9, 0.4)), "the pack color applies")
		check(p.paint_color == VehicleDB.get_params("sedan").paint_color,
			"the stock body paint is inherited")
		# Two calls must not share one mutable resource.
		p.mass = 1.0
		check(VehicleDB.get_params("tuned_sedan").mass == 1550.0,
			"every call returns a fresh parameter set")
	var pack: Dictionary = ModDB.mods()[0]
	pack["name"] = "hacked"
	check(ModDB.mods()[0]["name"] == "Tuner Pack", "mods() returns a snapshot")
	check(String(ModDB.car("tuned_sedan").get("base", "")) == "sedan", "the menu can read the base")
	check(VehicleDB.get_params("sedan").mass == 1300.0, "the built-in sedan stays stock")

	# Width and stretch feed the collider, so their overrides must move the
	# derived length and wheel radius with them.
	put("02_wide", JSON.stringify({
		"name": "Wide", "cars": [{"id": "wide_sedan", "name": "Wide Sedan",
			"base": "sedan", "params": {"width": 2.2, "body_stretch": 1.2}}],
	}))
	ModDB.reload()
	var wide := VehicleDB.get_params("wide_sedan")
	var stock := VehicleDB.get_params("sedan")
	check(wide != null, "the wide car loads")
	if wide != null and stock != null:
		check(wide.width == 2.2, "width override applies")
		check(wide.length > stock.length * 1.25,
			"a wider, stretched body is longer (%.2f vs %.2f)" % [wide.length, stock.length])
		check(wide.wheel_r > stock.wheel_r * 1.15,
			"the wheels are scaled with the body (%.2f vs %.2f)" % [wide.wheel_r, stock.wheel_r])
		check(wide.height > stock.height, "the body is taller at a larger scale")

	# Out-of-range numbers are clamped, not trusted. Typed strings and unknown
	# keys are ignored, so they cannot reach VehicleParams.set().
	put("03_limits", JSON.stringify({
		"cars": [{"id": "clamped", "name": "Clamped", "base": "sedan", "params": {
			"mass": 999999, "accel_max": -5, "vmax_kmh": 99999, "brake_decel": 0,
			"steer_rate_deg": 1, "grip": 99, "suspension_stiffness": -5,
			"damping_compression": 0, "damping_relaxation": -1,
			"nitro_capacity": -1, "nitro_drain": 999, "nitro_refill": 999,
			"nitro_accel": -10, "nitro_vmax": 0.1,
			"model": "res://evil.glb", "paint_color": [1, 0, 0, 0],
		}}],
	}))
	ModDB.reload()
	var c := VehicleDB.get_params("clamped")
	check(c != null, "the clamped car still loads")
	if c != null:
		check(c.mass == 4000.0, "mass clamps to the maximum (%.0f)" % c.mass)
		check(c.accel_max == 1.0, "negative acceleration clamps up")
		check(c.vmax_kmh == 1000.0, "top speed clamps to 1000 km/h")
		check(c.brake_decel == 4.0, "braking clamps to the minimum")
		check(c.steer_rate_deg == 120.0, "steering rate clamps up")
		check(c.grip == 20.0, "grip clamps to the maximum")
		check(c.suspension_stiffness == 40.0, "suspension clamps up")
		check(c.damping_compression == 2.0 and c.damping_relaxation == 2.0, "damping clamps up")
		check(c.nitro_capacity == 0.0 and c.nitro_accel == 0.0, "nitro clamps at zero")
		check(c.nitro_drain == 200.0 and c.nitro_refill == 100.0, "nitro rates clamp to the maximum")
		check(c.nitro_vmax == 1.0, "nitro speed factor clamps up")
		check(c.model == VehicleDB.get_params("sedan").model, "an unknown model key is ignored")
		check(c.paint_color == VehicleDB.get_params("sedan").paint_color,
			"an injected paint_color key is ignored")
	check(has_error("ignores unknown parameter 'model'"), "unknown keys are reported")
	check(has_error("ignores unknown parameter 'paint_color'"), "injected keys are reported")

	put("04_types", JSON.stringify({
		"cars": [{"id": "typed", "name": "Typed", "base": "pickup", "params": {
			"mass": "1500", "grip": true, "vmax_kmh": null, "accel_max": 7.5}}],
	}))
	ModDB.reload()
	var t := VehicleDB.get_params("typed")
	check(t != null, "a pack with wrong value types still yields the car")
	if t != null:
		check(t.mass == 1900.0 and t.grip == 6.0 and t.vmax_kmh == 140.0,
			"non-numeric values leave the base numbers")
		check(t.accel_max == 7.5, "the numeric sibling still applies")
	check(has_error("parameter 'mass' is not a number"), "a string number is reported")

	# Every rejected shape below must leave a reason in the MODS panel and must
	# not leak a car id into the game.
	put("05_bad_json", "{not json")
	put("06_not_object", "[]")
	put("07_no_cars", '{"name":"Empty"}')
	put("08_unknown_base", '{"cars":[{"id":"ghost_base","name":"Ghost","base":"ufo"}]}')
	put("09_builtin_id", '{"cars":[{"id":"sedan","name":"Copy","base":"sedan"}]}')
	put("10_path_id", '{"cars":[{"id":"../evil","name":"Evil","base":"sedan"}]}')
	put("11_upper_id", '{"cars":[{"id":"Upper_Case","name":"Upper","base":"sedan"}]}')
	put("12_short_id", '{"cars":[{"id":"a","name":"Short","base":"sedan"}]}')
	put("13_no_name", '{"cars":[{"id":"no_name_car","name":"","base":"sedan"}]}')
	put("14_bad_color", '{"cars":[{"id":"bad_color","name":"Bad Color","base":"sedan","color":[1,2]}]}')
	mkdirs("15_missing_file")
	put("16_too_large", '{"pad":"' + "x".repeat(ModDB.MAX_FILE_BYTES + 10) + '"}')
	put("17_dup_a", '{"cars":[{"id":"dup_car","name":"First","base":"sedan","params":{"mass":1111}}]}')
	put("18_dup_b", '{"cars":[{"id":"dup_car","name":"Second","base":"pickup","params":{"mass":2222}}]}')
	# Nine cars in one pack: the loader keeps the first eight.
	var many: Array = []
	for i in 9:
		many.append({"id": "many_%d" % i, "name": "Many %d" % i, "base": "sedan"})
	put("19_too_many", JSON.stringify({"cars": many}))
	ModDB.reload()
	var ids := VehicleDB.ids()
	for bad in ["sedan", "ghost_base", "../evil", "Upper_Case", "a", "no_name_car"]:
		check(not ModDB.car_ids().has(bad), "rejected id is absent from the mod catalog: " + bad)
	check(ModDB.car_ids().has("bad_color"), "a bad color does not reject the car")
	check(ModDB.car_ids().has("dup_car"), "the first duplicate id is kept")
	check(VehicleDB.get_params("dup_car").mass == 1111.0, "the first duplicate wins")
	check(ModDB.car_ids().has("many_7") and not ModDB.car_ids().has("many_8"),
		"a pack keeps at most %d cars" % ModDB.MAX_CARS_PER_MOD)
	check(VehicleDB.get_params("tuned_sedan") != null, "one broken folder does not stop the others")
	check(has_error("05_bad_json") and has_error("not a valid JSON object"),
		"broken JSON is reported with its folder")
	check(has_error("06_not_object"), "a JSON array is rejected")
	check(has_error("07_no_cars"), "a pack without cars is rejected")
	check(has_error("unknown base 'ufo'"), "an unknown base is reported")
	check(has_error("already a built-in car"), "a built-in id collision is reported")
	check(has_error("10_path_id"), "a path-like id is rejected")
	check(has_error("11_upper_id"), "uppercase ids are rejected")
	check(has_error("12_short_id"), "a one-letter id is rejected")
	check(has_error("no name"), "an empty name is rejected")
	check(has_error("color must be [r, g, b]"), "a short color is reported")
	check(has_error("15_missing_file") and has_error("mod.json is missing"),
		"a folder without mod.json is reported")
	check(has_error("16_too_large") and has_error("larger than"), "an oversized file is rejected")
	check(has_error("already used by another mod"), "a cross-pack duplicate is reported")
	check(has_error("too many cars"), "the per-pack car cap is reported")

	# Reload is an explicit rescan: removing the valid folder removes its car.
	var pack_dir := DirAccess.open("%s/01_tuner" % DIR)
	if pack_dir != null:
		pack_dir.remove("mod.json")
	DirAccess.remove_absolute("%s/01_tuner" % DIR)
	ModDB.reload()
	check(not VehicleDB.ids().has("tuned_sedan"), "reload drops a removed pack")
	check(VehicleDB.get_params("tuned_sedan") == null, "a removed car is no longer buildable")

	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
