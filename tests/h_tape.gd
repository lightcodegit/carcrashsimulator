extends Node3D
# Replay tape on disk: saving after a run, rejection by a foreign map, adoption by
# a live recorder and playback of the adopted tape with dents.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 200: await get_tree().physics_frame   # the ring accumulates frames (~10 samples)

	# an impact: the detector might have missed it — for the test write the event directly
	gm.replay._on_impact(90.0, gm.car.chassis.global_position, Vector3(1, 0, 0))
	for f in 5: await get_tree().physics_frame   # the ring sample catches up with the impact event
	var dents0: int = gm.replay.dents.size()
	check(dents0 == 1, "the impact made it into the tape (%d)" % dents0)

	var path := ReplayRecorder.replay_path("arena")
	check(gm.replay.save_to(path), "the tape was saved to disk")
	check(ReplayRecorder.has_tape("arena"), "has_tape sees the saved tape")
	check(not ReplayRecorder.has_tape("town"), "a foreign map has no tape")
	var tape := ReplayRecorder.tape_at(path)
	check(not tape.is_empty() and tape.get("map", "") == "arena", "the tape reads back and remembers its map")

	# a foreign map does not accept the tape: item indices of that layout make no sense
	var gm2: GameManager = load("res://scenes/game.tscn").instantiate()
	gm2.name = "GM2"
	add_child(gm2)
	var wrong := tape.duplicate(true); wrong["map"] = "town"
	check(not gm2.replay.adopt_tape(wrong), "another map's tape is not accepted")

	# a garbage tape is not accepted: broken sizes would crash later in _blend
	var bad_ver := tape.duplicate(true); bad_ver["version"] = 7
	check(not gm2.replay.adopt_tape(bad_ver), "a tape with a foreign version is not accepted")
	var bad_key := tape.duplicate(true); (bad_key["frames"] as Array)[0].erase("b")
	check(not gm2.replay.adopt_tape(bad_key), "a frame without a basis is not accepted")
	var bad_len := tape.duplicate(true)
	(bad_len["frames"] as Array)[0]["b"] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0])
	check(not gm2.replay.adopt_tape(bad_len), "a short basis is not accepted")
	var bad_dent := tape.duplicate(true); bad_dent["dents"] = [{"t": 1.0}]
	check(not gm2.replay.adopt_tape(bad_dent), "a dent without lp/ld is not accepted")

	# same map: adoption and playback with dents
	check(gm2.replay.adopt_tape(tape), "the same map's tape was accepted")
	check(gm2.replay.count() == (tape["frames"] as Array).size(), "the adopted tape's frames are all there")
	gm2.replay_player.setup(gm2.replay, gm2.car, gm2)
	gm2.replay_player.begin_default()
	gm2.replay_player.seek(gm2.replay.window_end())
	gm2.car.body.apply_impact_local(Vector3(0, 0, 1.5), Vector3(0, 0, -1), 120.0)
	await get_tree().process_frame
	check(gm2.car.body.dent_count >= 1, "the adopted tape's dents are on the body (%d)" % gm2.car.body.dent_count)
	gm2.replay_player.end()

	if _fails == 0: print("ALL PASS")
	else: print("FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
