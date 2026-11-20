extends Node
# Video export contract: the parent process saves the replay ring and starts a
# second instance of the same executable with Godot's Movie Maker options. The
# child finds the tape through --replay-export. This test covers the parts that
# can be decided without a window: argument parsing, path safety, tape
# validation and the exact argv that would be launched.
#
# Movie Maker itself needs a rendering driver, so a headless run cannot record a
# real AVI. That part is verified live; here a bad tape or a misspelled flag is
# caught before a window is ever opened.
var fails := 0

const DIR := "user://videos"
const TAPE := "user://videos/h_video_export.replay"

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _frame(t: float, kmh: float) -> Dictionary:
	return {
		"t": t,
		"p": PackedFloat32Array([0.0, 1.0, 0.0]),
		"b": PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]),
		"kmh": kmh,
		"slip": 0.0,
		"nitro": 0.5,
		"hot": 0.0,
		"w": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		"pr": PackedFloat32Array(),
	}

func _put_tape(path: String, map_id: String, car_id: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "the test can create a tape file")
	if f == null: return
	f.store_var({
		"version": 1, "map": map_id, "car": car_id, "sim_t": 1.0,
		"frames": [_frame(0.0, 0.0), _frame(0.5, 40.0), _frame(1.0, 80.0)],
		"dents": [],
	})
	f.close()

func _ready() -> void:
	DirAccess.remove_absolute(TAPE)
	check(VideoExport.ensure_dir(), "the videos directory is created")
	_put_tape(TAPE, "arena", "sedan")

	check(VideoExport.is_export_run(PackedStringArray(["--replay-export", TAPE])),
		"the export flag is recognised")
	check(not VideoExport.is_export_run(PackedStringArray(["--other", TAPE])),
		"a child without the flag is a normal run")

	var req: Dictionary = VideoExport.parse_user_args(
		PackedStringArray(["--unrelated", VideoExport.ARG, TAPE, "tail"]))
	check(String(req.get("map", "")) == "arena" and String(req.get("car", "")) == "sedan",
		"the tape names the child's map and car (%s)" % str(req))
	check(String(req.get("tape", "")) == TAPE, "the child gets the tape path it was launched with")
	check(VideoExport.parse_user_args(PackedStringArray([VideoExport.ARG])).is_empty(),
		"a bare flag with no path is rejected")
	check(VideoExport.parse_user_args(PackedStringArray([VideoExport.ARG, "user://videos/nope.replay"])).is_empty(),
		"a missing tape is rejected")
	_put_tape(TAPE, "", "sedan")
	check(VideoExport.parse_user_args(PackedStringArray([VideoExport.ARG, TAPE])).is_empty(),
		"a tape without a map id cannot start an export")
	_put_tape(TAPE, "arena", "sedan")
	var loaded: Dictionary = VideoExport.load_tape(req)
	check(not loaded.is_empty() and (loaded["frames"] as Array).size() == 3,
		"the child can reload the same tape")

	# Filenames are built from map/car ids, so a hand-edited id must never turn
	# into a directory escape or a path separator.
	for raw in ["../../etc/passwd", "a/b\\c", "map with spaces", ""]:
		var safe := VideoExport.safe_id(raw)
		check(not safe.contains("/") and not safe.contains("\\") and not safe.contains(".."),
			"safe_id(%s) has no path syntax (%s)" % [raw, safe])
		check(safe.length() > 0 and safe.length() <= VideoExport.MAX_ID_LEN,
			"safe_id(%s) has a sane length (%d)" % [raw, safe.length()])
	check(VideoExport.safe_id("") == "replay", "an empty id falls back to a readable stem")
	check(VideoExport.safe_id("arena_2") == "arena_2", "letters, digits and underscores survive")

	var stamp := 1700000000
	var tape_path := VideoExport.tape_path("arena", "sedan", stamp)
	var out_path := VideoExport.output_path("arena", "sedan", stamp)
	check(tape_path.begins_with(DIR + "/replay_arena_sedan_") and tape_path.ends_with(".replay"),
		"the tape path is stable and inside user://videos (%s)" % tape_path)
	check(out_path.begins_with(DIR + "/replay_arena_sedan_") and out_path.ends_with(".avi"),
		"the output is an AVI next to the tape (%s)" % out_path)
	# A second export in the same second must not overwrite the first file.
	var fout := FileAccess.open(out_path, FileAccess.WRITE)
	if fout != null: fout.store_string("x"); fout.close()
	var out_path2 := VideoExport.output_path("arena", "sedan", stamp)
	check(out_path2 != out_path and out_path2.ends_with("_1.avi"),
		"a same-second export gets a unique output name (%s)" % out_path2)
	DirAccess.remove_absolute(out_path)
	DirAccess.remove_absolute(out_path2)

	var plan: Dictionary = VideoExport.plan(TAPE, out_path, true, 640, 360, 24)
	check(not plan.is_empty(), "a valid tape produces a child plan")
	if not plan.is_empty():
		var args: PackedStringArray = plan["args"]
		check(args.has("--write-movie") and args.has("--fixed-fps") and args.has("--resolution"),
			"the child gets Movie Maker options (%s)" % str(args))
		check(args[args.find("--write-movie") + 1] == VideoExport.absolute(out_path),
			"the movie path is absolute, as the child process resolves it")
		check(args[args.find("--fixed-fps") + 1] == "24", "the requested frame rate is passed")
		check(args[args.find("--resolution") + 1] == "640x360", "the requested resolution is passed")
		check(args.has("--path"), "an editor child gets the project path")
		var dash := args.find("--")
		check(dash >= 0 and args.find(VideoExport.ARG) == dash + 1,
			"the game flag goes after the -- boundary (%s)" % str(args))
		check(args[args.find(VideoExport.ARG) + 1] == VideoExport.absolute(TAPE),
			"the child receives the saved tape, not the live ring")
		var exported_plan: Dictionary = VideoExport.plan(TAPE, out_path, false)
		check(not exported_plan.is_empty() and not (exported_plan["args"] as PackedStringArray).has("--path"),
			"an exported game child does not need --path")
	check(VideoExport.plan("user://videos/missing.replay", out_path, true).is_empty(),
		"a missing tape never builds a child plan")
	check(VideoExport.absolute(TAPE) != TAPE and not VideoExport.absolute(TAPE).begins_with("user://"),
		"absolute() globalises user:// paths")

	# ---- autoplay child: the game scene must enter export mode without
	# counting a player run or waiting for a menu click ------------------------
	_put_tape(TAPE, "arena", "sedan")
	GameContext.map_id = "arena"
	GameContext.car_id = "sedan"
	VideoExport.request = {"tape": TAPE, "map": "arena", "car": "sedan"}
	var runs_before := Stats.runs
	var crashes_before := Stats.crashes
	var gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	check(gm.camera != null and gm.camera.global_position.y > 1.0,
		"the chase camera is placed before the first recorded frame (y=%.2f)" % (
			gm.camera.global_position.y if gm.camera != null else -1.0))
	for i in 3: await get_tree().process_frame
	check(gm._export_mode, "the child autoplays the tape without opening the menu")
	check(gm.is_frozen(), "the exported replay keeps the live world frozen")
	check(gm.replay_player != null and gm.replay_player.active,
		"the exported replay is playing from the saved tape")
	check(gm.hud._panels_hidden, "the HUD is hidden from the recorded frame")
	check(Stats.runs == runs_before and Stats.crashes == crashes_before,
		"an export child is not a player run in Stats (%d/%d vs %d/%d)" % [
			Stats.runs, Stats.crashes, runs_before, crashes_before])
	check(VideoExport.request.is_empty(), "the child consumes its one-shot export request")
	# The saved tape is an intermediate file: after the child exits, the parent
	# deletes it and keeps only the video. Checked on the helper directly because
	# spawning a real Movie Maker child is a live-GPU test.
	var trash := "user://videos/h_video_export_trash.replay"
	var tf := FileAccess.open(trash, FileAccess.WRITE)
	if tf != null: tf.store_string("x"); tf.close()
	gm._export_tape = trash
	gm._drop_export_tape()
	check(not FileAccess.file_exists(trash),
		"the intermediate tape is removed after the export finishes")
	check(gm._export_tape == "", "the tape path is cleared so it is not removed twice")
	# Leave export mode before the three-frame tape reaches its end, otherwise
	# the end guard would quit the test process on purpose.
	gm._export_mode = false
	if gm.replay_player != null and gm.replay_player.active: gm.replay_player.end()
	gm.hud.set_panels_hidden(false)
	gm._set_paused(false)
	# Regression for the lap rule: a best lap is a lifetime record even when no
	# ghost recording exists. The arena has no lap line, so _racer is null here —
	# exactly the case the old "recording must be non-empty" gate swallowed.
	Stats.begin_run("arena", "sedan")
	gm._on_lap(42.0, 1, true)
	check(is_equal_approx(float(Stats.map_record("arena").get("best_lap", 0.0)), 42.0),
		"a best lap reaches Stats without a ghost recording")
	gm.queue_free()
	await get_tree().process_frame

	DirAccess.remove_absolute(TAPE)
	if fails == 0: print("ALL PASS")
	else: print("FAILS %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
