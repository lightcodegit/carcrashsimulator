extends SceneTree
# Lap tracking, best-lap persistence and ghost playback.
# Run: godot --headless --path . --script res://tests/d_lap_ghost.gd
var fails := 0
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	pass

func _process(_dt: float) -> bool:
	frames += 1
	match frames:
		2:
			# ---- lap detection with fake positions ----
			var lt = load("res://scripts/core/lap_tracker.gd").new()
			lt.line = Vector3.ZERO
			lt.heading = Vector3(1, 0, 0)
			lt._last = Vector3.ZERO
			# first tick: at the line, no distance → no lap
			check(not lt.tick(Vector3.ZERO, 0.016, 10.0), "the spawn tick is not a lap")
			# drive away: distance accumulates, but no line → no lap
			var d := 0.0
			for i in 50:
				d += 20.0
				check(not lt.tick(Vector3(d, 0, 0), 0.016, 10.0), "no lap away from the line")
			check(lt._dist > 900.0, "the distance accumulated (%.0f m)" % lt._dist)
			# return to the line: dist ≥ 600, near line, forward → lap!
			var fired := [false, 0.0, 0, false]
			lt.lap_finished.connect(func(t: float, l: int, b: bool) -> void:
				fired[0] = true; fired[1] = t; fired[2] = l; fired[3] = b)
			var lap_happened: bool = lt.tick(Vector3(5.0, 0, 0), 0.016, 10.0)
			check(lap_happened and fired[0], "returning to the line with 900+ m completes a lap")
			check(fired[2] == 1 and fired[3], "the first completed lap is the best (lap %d, best %s)" % [fired[2], str(fired[3])])
			check(lt.best < INF and lt.best > 0.0, "the best time was recorded (%.3f)" % lt.best)
			check(not lt.last_recording.is_empty(), "the recording survived the lap")
			# the next tick at the line: dist reset to 0 → no immediate re-lap
			check(not lt.tick(Vector3(3.0, 0, 0), 0.016, 10.0), "the distance reset prevents an instant re-lap")
			# a slower second lap: best stays
			for i in 50:
				lt.tick(Vector3(20.0 + i * 20.0, 0, 0), 0.016, 10.0)
			var fired2 := [false, 0.0]
			lt.lap_finished.connect(func(t: float, _l: int, b: bool) -> void:
				fired2[0] = true; fired2[1] = t)
			lt.tick(Vector3(3.0, 0, 0), 0.016, 10.0)
			check(fired2[0] and not lt.best < fired[1], "a slower lap does not replace the best")
			lt.free()

			# ---- persistence ----
			var lt2 = load("res://scripts/core/lap_tracker.gd").new()
			var tape_frames: Array = [
				{"t": 0.0, "p": PackedFloat32Array([0, 1, 0]),
				 "b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]),
				 "w": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])},
				{"t": 0.05, "p": PackedFloat32Array([1, 1, 0]),
				 "b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]),
				 "w": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])},
			]
			var path: String = lt2.best_path("circuit", "sedan")
			DirAccess.remove_absolute(path)
			check(not lt2.load_best("circuit", "sedan").has("time"), "no best without a file")
			check(lt2.save_best("circuit", "sedan", 29.52, tape_frames), "the best lap saves")
			var loaded: Dictionary = lt2.load_best("circuit", "sedan")
			check(is_equal_approx(float(loaded.get("time", 0.0)), 29.52), "the best time reads back")
			check((loaded["frames"] as Array).size() == 2, "the frames read back")
			# corrupt file is rejected, not crashed on
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string("{broken")
			f.close()
			check(lt2.load_best("circuit", "sedan").is_empty(), "a corrupt file is rejected")
			# oversized file is rejected (the cap covers the largest honest save,
			# MAX_FRAMES ≈ 400–500 KB, so this garbage has to be past it)
			f = FileAccess.open(path, FileAccess.WRITE)
			f.store_string("x".repeat(900000))
			f.close()
			check(lt2.load_best("circuit", "sedan").is_empty(), "an oversized file is rejected")
			DirAccess.remove_absolute(path)
			lt2.free()
		4:
			# ---- ghost car build + playback ----
			var ghost = load("res://scripts/core/ghost_car.gd").new()
			ghost.setup(load("res://scripts/core/vehicle_db.gd").get_params("sedan"))
			root.add_child(ghost)
			check(ghost._body_node != null, "the ghost model is built")
			# the ghost warms up its shader (visible for a few frames, then
			# hidden if not playing) — a hidden check here would race the warmup
			check(ghost._warmup > 0 and ghost.visible,
				"the ghost warms up its shader on setup (warmup %d)" % ghost._warmup)
			var play_frames: Array = [
				{"t": 0.0, "p": PackedFloat32Array([0, 1, 0]),
				 "b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]),
				 "w": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])},
				{"t": 1.0, "p": PackedFloat32Array([10, 1, 0]),
				 "b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]),
				 "w": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])},
			]
			ghost.play(play_frames)
			check(ghost.visible and ghost.playing(), "play starts the ghost")
			ghost._apply(0.5)
			var gt: Vector3 = ghost.global_position
			check(gt.x > 4.0 and gt.x < 6.0, "the mid-lap playback is at x=5 (%.1f)" % gt.x)
			check(is_equal_approx(gt.y, 1.0), "the playback y matches the recording (%.2f)" % gt.y)
			# the ghost material is translucent on every surface
			var found_trans := false
			for c in ghost._root.get_child(0).get_children():
				if c is MeshInstance3D:
					for si in (c as MeshInstance3D).mesh.get_surface_count():
						var m: Material = (c as MeshInstance3D).get_surface_override_material(si)
						if m != null and m is StandardMaterial3D:
							var sm := m as StandardMaterial3D
							if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and sm.albedo_color.a < 0.5:
								found_trans = true
			check(found_trans, "the ghost surfaces are translucent")
			ghost.free()
		6:
			if fails == 0: print("ALL PASS")
			else: print("FAILS %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
