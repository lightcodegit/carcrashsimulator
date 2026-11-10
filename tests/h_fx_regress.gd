extends Node3D
# Regressions from the audit fix batch: idempotent attach, spark timers measured on
# simulated time (not the wall clock), honest playback_missing after pause/resume,
# and closing the replay on respawn.
var _fails := 0
var car: CarRig
var fx: EffectsDirector
var _f := 0
var _stage := 0
var _gm: GameManager
var _gm_f := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D.IDENTITY)
	fx = EffectsDirector.new()
	add_child(fx)
	fx.attach(car)

func _physics_process(_dt: float) -> void:
	_f += 1
	match _stage:
		0: _attach_twice()
		1: _spark_cadence()
		2: _audio_flag()
		3: _respawn_closes_replay()
		4: _finish()
		_: pass

func _attach_twice() -> void:
	if _f != 4: return
	var kids := fx.get_child_count()
	var emitters := fx.all_emitters().size()
	fx.attach(car)                 # same car: nothing must double
	check(fx.get_child_count() == kids,
		"re-attaching the same car spawns no extra children (%d vs %d)" % [fx.get_child_count(), kids])
	check(fx.all_emitters().size() == emitters,
		"all emitters are still in the list (%d vs %d)" % [fx.all_emitters().size(), emitters])
	fx.attach(car)
	check(fx.get_child_count() == kids, "the third attach is silent too")
	_stage = 1
	_f = 0

func _spark_cadence() -> void:
	if _f == 2:
		fx.set_enabled(true)
		fx._spark_gap = 0.0
		fx.prop_puffs = 0
		# two impacts in adjacent ticks: the old wall-clock gate
		# silenced the second under headless --fixed-fps and diverged from the live window
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		var first := fx._sparks.emitting
		fx._sparks.emitting = false
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		check(first, "the first impact produced sparks")
		check(not fx._sparks.emitting,
			"the second impact in the same tick is suppressed by the gap — that is the throttling")
		check(absf(fx._spark_gap - 0.08) < 1e-6,
			"the spark-volley gap is in simulated seconds (%.3f)" % fx._spark_gap)
		# the key point: the gap is spent on simulated time. The old Time.get_ticks_msec
		# under headless --fixed-fps ate volleys in batches (a tick ran faster than the wall
		# clock), and the spark counter diverged from the live window.
		for i in 6:
			fx._physics_process(1.0 / 60.0)
		check(fx._spark_gap <= 1e-6,
			"six ticks of 16.6 ms drained the gap completely (%.4f)" % fx._spark_gap)
		fx._sparks.emitting = false
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		check(fx._sparks.emitting, "after the simulated gap expires, sparks are back")
		_stage = 2
		_f = 0

func _audio_flag() -> void:
	if _f != 2: return
	var drv := AudioDriver.new()
	add_child(drv)
	drv.attach(car)
	var before := drv.playback_missing
	drv.suspend()
	drv.resume()
	check(before, "playback_missing is raised immediately in headless")
	check(drv.playback_missing,
		"pause/resume does not hide playback_missing (otherwise h_audio lies about PARTIAL)")
	drv.stop_all()
	drv.queue_free()
	_stage = 3
	_f = 0

func _respawn_closes_replay() -> void:
	if _f == 2:
		GameContext.select("sedan", "town")
		_gm = load("res://scenes/game.tscn").instantiate()
		add_child(_gm)
	if _f == 40:
		_gm._set_paused(true)
		_gm.hud.pause_button("РЕПЛЕЙ УДАРА").pressed.emit()
	if _f == 46 and not _gm.replay_player.active:
		# there are no impacts in the town parking lot — open the window manually
		_gm.replay_player.begin_at(_gm.replay.window_start())
	if _f == 50:
		check(_gm.replay_player.active, "replay opened")
		check(_gm.car.replaying, "the car is in playback mode")
		_gm._respawn_now()
	if _f == 54:
		check(not _gm.replay_player.active,
			"respawn closed playback instead of leaving replaying on top of the physics")
		check(not _gm.car.replaying, "CarRig left playback mode")
		check(_gm.replay.count() < int(ReplayRecorder.RATE),
			"the ring restarted after respawn (%d frames)" % _gm.replay.count())
		_gm._set_paused(false)
		_stage = 4
		_f = 0

func _finish() -> void:
	if _gm != null and is_instance_valid(_gm): _gm.queue_free()
	if fx != null and is_instance_valid(fx): fx.queue_free()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
