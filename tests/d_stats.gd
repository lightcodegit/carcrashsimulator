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
	s1._dirty = true               # save() is normally driven by the debounce
	s1.save()
	check(FileAccess.file_exists(PATH), "save writes the file")

	var s2 = script.new()
	s2.load_values()
	check(s2.runs == 2, "a new instance reads the saved runs (%d)" % s2.runs)
	check(s2.crashes == 3 and s2.shots == 1, "counters survive the reload")
	check(is_equal_approx(s2.best_impact, 112.5) and is_equal_approx(s2.top_speed, 213.0), "records survive the reload")

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
