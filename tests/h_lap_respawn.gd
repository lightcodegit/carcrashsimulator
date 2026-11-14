extends Node3D
# Respawn on a lap map must restart the lap tracker from the SPAWN point.
# The tracker snapshots its reference position in reset(); if reset() runs before
# the respawn teleport, the jump "crash site → spawn" (~300 m straight line on the
# circuit) lands in _dist, and the drive back to the line completes a lap with an
# artificially small time — which _on_lap then saved as the new best, poisoning
# the saved record and the ghost permanently.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	GameContext.select("sedan", "circuit")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 30:
		await get_tree().physics_frame
	# honest precondition, not a skip: the circuit map is expected to wire laps
	check(gm._has_laps and gm._racer != null,
		"circuit wires the lap tracker (has_laps=%s)" % str(gm._has_laps))
	if gm._racer == null:
		print("FAILS %d" % _fails)
		get_tree().quit(1)
		return

	# 1) teleport far away, respawn, and let the tracker tick while the car sits:
	# _dist must stay ~0. With reset() called before the teleport the first tick
	# measured the whole teleport as driven distance (hundreds of meters).
	gm.car.chassis.global_position = gm.car.chassis.global_position + Vector3(300.0, 0.0, 0.0)
	gm._respawn_now()
	await get_tree().physics_frame
	var dist_after_one_tick: float = gm._racer._dist
	check(dist_after_one_tick >= 0.0 and dist_after_one_tick < 5.0,
		"the teleport is not charged into _dist (%.1f m after the first tick)" % dist_after_one_tick)

	# 2) the tracker reference is the spawn point, not the crash site
	var last_to_spawn := gm._racer._last.distance_to(gm.car.chassis.global_position)
	check(last_to_spawn < 5.0, "reset() snapped the post-teleport pose (%.1f m off)" % last_to_spawn)

	# 3) respawn from inside the replay: the tracker must still restart from the
	# spawn, not from the replay pose shown mid-window
	if gm.replay != null and gm.replay.count() > 0:
		if gm.replay_player.begin_at(gm.replay.window_start()):
			gm._respawn_now()
			await get_tree().physics_frame
			check(not gm.car.replaying, "replay is closed by respawn from inside it")
			check(gm._racer._dist < 5.0,
				"respawn from replay restarts _dist at the spawn (%.1f m)" % gm._racer._dist)
	else:
		# an honest fallback: drive forward a moment to fill the ring, then repeat
		Input.action_press("throttle")
		for f in 40:
			await get_tree().physics_frame
		Input.action_release("throttle")
		check(gm.replay != null and gm.replay.count() > 0, "the ring holds frames after driving")
		if gm.replay.count() > 0:
			gm.replay_player.begin_at(gm.replay.window_start())
			gm._respawn_now()
			await get_tree().physics_frame
			check(not gm.car.replaying, "replay is closed by respawn from inside it")
			check(gm._racer._dist < 5.0,
				"respawn from replay restarts _dist at the spawn (%.1f m)" % gm._racer._dist)

	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
