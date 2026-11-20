extends SceneTree
# Lifetime statistics: accumulation, persistence across loads, and hostile file
# handling. Run: godot --headless --path . --script res://tests/d_stats.gd
var fails := 0
const PATH := "user://stats_v1.json"

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func put(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _initialize() -> void:
	var script = load("res://scripts/autoload/Stats.gd")
	DirAccess.remove_absolute(PATH)
	var s1 = script.new()
	s1.add_run()
	s1.add_run()
	s1.add_impact(112.5)
	s1.add_impact(90.0)            # weaker: best stays
	s1.add_impact(-5.0)            # negative is not a speed
	s1.add_speed(213.0)
	s1.add_speed(150.0)
	s1.add_distance(1500.0)
	s1.add_distance(-50.0)         # negative distance does not subtract
	s1.add_time(90.0)
	s1.add_shot()
	check(s1.runs == 2, "runs accumulate (%d)" % s1.runs)
	check(s1.crashes == 3, "every impact counts (%d)" % s1.crashes)
	check(is_equal_approx(s1.best_impact, 112.5), "best impact keeps the maximum (%.1f)" % s1.best_impact)
	check(is_equal_approx(s1.top_speed, 213.0), "top speed keeps the maximum (%.1f)" % s1.top_speed)
	check(is_equal_approx(s1.distance, 1500.0), "distance only grows (%.1f)" % s1.distance)
	check(is_equal_approx(s1.seconds, 90.0), "time accumulates (%.1f)" % s1.seconds)
	check(s1.shots == 1, "shots accumulate (%d)" % s1.shots)
	# The debounce deadline is armed once: live driving touches the counters
	# every tick and must not push the write forward indefinitely.
	s1._touch()
	var deadline: int = s1._next_save
	s1._touch()
	s1.add_speed(10.0)
	check(s1._next_save == deadline, "changes do not slide the debounce deadline")
	s1._dirty = true               # save() is normally driven by the debounce
	s1.save()
	check(FileAccess.file_exists(PATH), "save writes the file")

	var s2 = script.new()
	s2.load_values()
	check(s2.runs == 2, "a new instance reads the saved runs (%d)" % s2.runs)
	check(s2.crashes == 3 and s2.shots == 1, "counters survive the reload")
	check(is_equal_approx(s2.best_impact, 112.5) and is_equal_approx(s2.top_speed, 213.0), "records survive the reload")

	# ---- v2: per-map and per-car records -------------------------------------
	# A run feeds two independent buckets (its map and its car). Switching the
	# run must not leak the previous map/car into the new one.
	var sv = script.new()
	sv.begin_run("arena", "sedan")
	sv.add_run()
	sv.add_run()
	sv.add_impact(120.0)
	sv.add_speed(200.0)
	sv.add_distance(1000.0)
	sv.add_time(60.0)
	sv.add_best_lap(70.0)
	sv.add_best_lap(65.5)
	sv.add_best_lap(80.0)          # slower: the best stays
	sv.add_best_lap(0.0)           # "no lap yet" is not a lap
	sv.begin_run("town", "pickup")
	sv.add_run()
	sv.add_impact(50.0)
	sv.add_speed(80.0)
	sv.add_distance(100.0)
	sv.add_time(5.0)
	sv.add_best_lap(90.0)
	var arena: Dictionary = sv.map_record("arena")
	var town: Dictionary = sv.map_record("town")
	var sedan: Dictionary = sv.car_record("sedan")
	var pickup: Dictionary = sv.car_record("pickup")
	check(int(arena["runs"]) == 2 and int(arena["crashes"]) == 1,
		"the map bucket counts its own runs and impacts (%s)" % str(arena))
	check(is_equal_approx(float(arena["best_impact"]), 120.0)
			and is_equal_approx(float(arena["top_speed"]), 200.0),
		"the map bucket keeps its own records")
	check(is_equal_approx(float(arena["distance"]), 1000.0)
			and is_equal_approx(float(arena["seconds"]), 60.0),
		"the map bucket accumulates distance and time")
	check(is_equal_approx(float(arena["best_lap"]), 65.5),
		"the map bucket keeps the fastest lap (%.2f)" % float(arena["best_lap"]))
	check(int(town["runs"]) == 1 and int(town["crashes"]) == 1,
		"a second map starts from zero and counts only its own run (%s)" % str(town))
	check(is_equal_approx(float(sedan["best_lap"]), 65.5)
			and is_equal_approx(float(pickup["best_lap"]), 90.0),
		"car buckets keep separate best laps")
	check(int(sedan["runs"]) == 2 and int(pickup["runs"]) == 1,
		"car buckets count runs independently of maps")
	check(sv.map_record("missing").is_empty() and sv.car_record("missing").is_empty(),
		"unknown ids have no record instead of an empty-looking zero row")
	# The accessor returns a copy: a UI accidentally editing it must not change
	# the lifetime record.
	arena["runs"] = 999
	check(int(sv.map_record("arena")["runs"]) == 2, "map_record returns a defensive copy")
	# Empty/oversized ids never become file keys.
	sv.begin_run("", "x".repeat(200))
	sv.add_run()
	check(not sv.maps.has("") and not sv.cars.has("x".repeat(200)),
		"invalid map/car ids are ignored, not stored as junk keys")
	check(sv.maps.size() == 2 and sv.cars.size() == 2,
		"ignored ids did not create extra buckets (%d/%d)" % [sv.maps.size(), sv.cars.size()])
	sv.save()
	var reloaded = script.new()
	reloaded.load_values()
	var arena2: Dictionary = reloaded.map_record("arena")
	check(int(arena2["runs"]) == 2 and is_equal_approx(float(arena2["best_lap"]), 65.5),
		"per-map records survive a reload (%s)" % str(arena2))
	check(int(reloaded.car_record("pickup")["runs"]) == 1,
		"per-car records survive a reload")
	var saved_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check(saved_json is Dictionary and int(saved_json.get("version", 0)) == 2,
		"the file is written with the current version")
	# Hostile buckets: wrong container types, junk records and non-string keys
	# are dropped one by one; one broken map must not wipe the other.
	put('{"version":2,"runs":7,"maps":{"arena":{"runs":3,"crashes":"bad","best_impact":1e30,"top_speed":-5,"distance":100,"seconds":2,"best_lap":-1},"bad":[],"": {"runs":9}},"cars":[]}')
	var hostile = script.new()
	hostile.load_values()
	var hrec: Dictionary = hostile.map_record("arena")
	check(hostile.runs == 7, "v2 keeps the lifetime totals")
	check(int(hrec.get("runs", 0)) == 3, "a valid map record reads back")
	check(int(hrec.get("crashes", -1)) == 0, "a string counter falls back to zero")
	check(is_equal_approx(float(hrec.get("best_impact", 0.0)), 1e12),
		"a hostile magnitude still clamps in a bucket (%.1g)" % float(hrec.get("best_impact", 0.0)))
	check(is_equal_approx(float(hrec.get("top_speed", -1.0)), 0.0),
		"a negative bucket record clamps to zero")
	check(is_equal_approx(float(hrec.get("best_lap", -1.0)), 0.0),
		"a negative lap is not a record")
	check(not hostile.maps.has("bad") and not hostile.maps.has(""),
		"junk bucket keys are dropped")
	check(hostile.cars.is_empty(), "a non-dictionary bucket store is dropped")
	# The cap is enforced before the file can grow into thousands of keys.
	var many := {}
	for i in 70:
		many["map_%d" % i] = {"runs": i + 1}
	check(script._records(many).size() == 64, "at most 64 map/car buckets are kept")
	check(script._records({1: {"runs": 2}}).is_empty(), "non-string bucket ids are dropped")
	# A v1 file has no buckets at all and must still load its global counters.
	put('{"version":1,"runs":5,"crashes":4,"best_impact":88.0,"top_speed":140.0,"distance":300.0,"seconds":12.0,"shots":2}')
	var v1 = script.new()
	v1.load_values()
	check(v1.runs == 5 and v1.crashes == 4 and v1.shots == 2,
		"a v1 file still loads its lifetime counters")
	check(v1.maps.is_empty() and v1.cars.is_empty(),
		"a v1 file starts with no per-map/per-car buckets")

	# A hostile file: wrong types must not poison the counters or abort the load
	# — one broken field falls back, the rest still read.
	put("{\"version\":1,\"runs\":\"oops\",\"crashes\":[1,2],\"shots\":-4,\"top_speed\":5}")
	var s3 = script.new()
	s3.load_values()
	check(s3.runs == 0, "a string run count falls back to zero (%d)" % s3.runs)
	check(s3.crashes == 0, "an array crash count falls back to zero")
	check(s3.shots == 0, "a negative shot count falls back to zero (%d)" % s3.shots)
	check(is_equal_approx(s3.top_speed, 5.0), "a valid field still reads (%.1f)" % s3.top_speed)
	# Absurd magnitudes clamp, and non-finite numbers (NaN/INF from a hand edit)
	# never reach a counter — guarded in _num directly, since Godot's JSON parser
	# rejects the NaN literal and would reject the whole file with it.
	put("{\"version\":1,\"top_speed\":1e30}")
	var s5 = script.new()
	s5.load_values()
	check(s5.top_speed == 1e12, "an absurd record clamps to the ceiling (%s)" % s5.top_speed)
	check(script._num(NAN, 3.0) == 3.0 and script._num(INF, 3.0) == 3.0,
		"NaN and INF fall back to the current value")

	# The tmp file never survives a failed save: the honest tape is either the
	# previous file or the new one, never a half-written pair.
	put("{broken")
	var s4 = script.new()
	s4.load_values()
	check(s4.runs == 0, "a corrupt file keeps factory values")
	check(not FileAccess.file_exists(PATH + ".part"), "no draft file is left behind")

	DirAccess.remove_absolute(PATH)
	if fails == 0: print("ALL PASS")
	else: print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
