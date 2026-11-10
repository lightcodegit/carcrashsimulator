extends Node3D
# Crash replay. Two tracks: the bare harness (frame ring, horizon, impact events and
# playback accuracy down to the last frame) and the live GameManager scene (pause menu,
# bar buttons, Esc, restart and restoration of live state).
#
# Key sign that the replay does NOT re-simulate: the car pose comes from ring frames,
# not from physics. In the live scene the world is paused (zero simulation steps) and the
# recorder appends not a single frame meanwhile — both checks fail if the player starts
# computing on its own or if the pause does not freeze recording.
var _fails := 0
var car: CarRig
var rec: ReplayRecorder
var player: ReplayPlayer
var _f := 0
var _phase := "ring"
var _ticks := 0
var _t0 := 0.0
var _wall: StaticBody3D
var _gm: GameManager
var _gm_f := 0
var _entry_tf := Transform3D()
var _entry_lin := Vector3.ZERO
var _entry_dents := 0
var _entry_depth := 0.0
var _sim_t_at_entry := 0.0
var _sub := 0
var _sub_at := 0
var _n_snap := 0
var _t_snap := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _act(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = StringName(name)
	e.pressed = true
	e.strength = 1.0
	return e

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wall = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 8, 1)
	cs.shape = bx
	_wall.add_child(cs)
	add_child(_wall)
	_wall.global_position = Vector3(60, 4, 0)

	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)))

	rec = ReplayRecorder.new()
	add_child(rec)
	rec.attach(car, null)          # no scene: the harness simulates the pause itself
	player = ReplayPlayer.new()
	add_child(player)
	player.setup(rec, car, null)
	rec.player = player
	_guard_validation()

# Regression for the tape-validation hole (#2) and frame_at crashing on an empty ring (#3).
# Checked on a real empty recorder before the live stages begin.
func _mkframe(with_nitro: bool, with_hot: bool) -> Dictionary:
	var b := PackedFloat32Array(); b.resize(9)
	for i in 9: b[i] = float(i)
	var f := {"t": 0.0, "kmh": 0.0, "slip": 0.0, "p": PackedFloat32Array([0.0, 0.0, 0.0]),
		"b": b, "w": PackedFloat32Array(), "pr": PackedFloat32Array()}
	if with_nitro: f["nitro"] = 0.0
	if with_hot: f["hot"] = 0.0
	return f

func _guard_validation() -> void:
	check(ReplayRecorder._frames_valid([_mkframe(true, true)]),
		"a full frame with nitro and hot is accepted")
	check(not ReplayRecorder._frames_valid([_mkframe(false, true)]),
		"a frame without nitro is rejected: otherwise _apply reads a.nitro and crashes in replay")
	check(not ReplayRecorder._frames_valid([_mkframe(true, false)]),
		"a frame without hot is rejected: otherwise _apply reads a.hot and crashes in replay")
	check(rec.frame_at(0.0) == {},
		"frame_at on an empty ring returns {}, it does not index frames[0]")

func _physics_process(_dt: float) -> void:
	_ticks += 1
	match _phase:
		"ring": _ring()
		"impact": _impact_stage()
		"exact": _exact_stage()
		"scrub": _scrub_stage()
		"game": _game_stage()
		_: pass

func _drive(on: bool) -> void:
	if on: Input.action_press("throttle")
	else: Input.action_release("throttle")

# ── 1. ring: rate, horizon, memory ────────────────────────────────────
func _ring() -> void:
	if _ticks == 2:
		_drive(true)
		_t0 = rec.sim_t
		return
	if _ticks == 62:
		# one second of physics = exactly RATE frames and exactly 1 s of simulation
		check(absf(rec.sim_t - (_t0 + 1.0)) < 0.05,
			"a simulation second is counted by physics ticks (%.3f)" % (rec.sim_t - _t0))
		check(absf(rec.count() - ReplayRecorder.RATE) <= 2,
			"frames per second are exactly %d (%d)" % [int(ReplayRecorder.RATE), rec.count()])
		return
	if _ticks == 1202:
		var span := rec.window_end() - rec.window_start()
		check(rec.count() == ReplayRecorder.MAX_FRAMES,
			"the ring is full and does not grow further (%d of %d)" % [rec.count(), ReplayRecorder.MAX_FRAMES])
		check(span <= ReplayRecorder.HORIZON_S + 0.15 and span >= ReplayRecorder.HORIZON_S - 0.6,
			"the replay window holds exactly %.0f s (%.2f)" % [ReplayRecorder.HORIZON_S, span])
		var bytes := rec.bytes_used()
		check(bytes > 0 and bytes < 4_000_000,
			"the 10 s window weighs %.0f KB and does not bloat" % (bytes / 1024.0))
		print("bench: window %d frames = %.1f KB, sim_t=%.2f" % [rec.count(), bytes / 1024.0, rec.sim_t])
		_phase = "impact"
		_f = _ticks

# ── 2. the impact is written as an event, not rewritten from scratch ─────────
func _impact_stage() -> void:
	if _ticks == _f + 2:
		_drive(false)
		car.chassis.global_position = Vector3(48, 1.2, 0)
		car.chassis.linear_velocity = Vector3(60, 0, 0)
		car.chassis.reset_physics_interpolation()
		return
	if _ticks != _f + 40: return
	check(rec.dents.size() >= 1, "the impact was recorded as an event (%d)" % rec.dents.size())
	var lt := rec.last_impact_t()
	check(lt >= rec.window_start() and lt <= rec.window_end(),
		"the impact moment is inside the window (%.2f vs [%.2f..%.2f])" % [lt, rec.window_start(), rec.window_end()])
	var d: Dictionary = rec.dents[rec.dents.size() - 1]
	check(d.lp is Vector3 and absf(d.ld.length() - 1.0) < 0.01,
		"the event stores a point and a unit direction in body space (|n|=%.4f)" % d.ld.length())
	_phase = "exact"
	_f = _ticks

# ── 3. playback accuracy: pose from the frame, state restoration ────────────
func _exact_stage() -> void:
	if _ticks != _f + 4: return
	var tf_before := car.chassis.global_transform
	var dents_before := car.body.dent_count
	check(player.begin_at(rec.window_end() - 2.0), "the player opened the window 2 s before the end")
	check(car.replaying, "CarRig switched into replay mode")
	# compare exactly against a frame: between frames the player blends, and half a meter
	# of drift at 600 km/h is interpolation, not an error
	var k: int = rec.count() - 20
	var ft: float = float(rec.frames[k].t)
	player.seek(ft)
	var fr: Dictionary = rec.frame_at(ft)
	var fp: PackedFloat32Array = fr.p
	var got := car.chassis.global_transform.origin
	check(absf(float(fr.t) - ft) < 1e-6, "seek to frame %.3f landed on the same frame" % ft)
	check(got.distance_to(Vector3(fp[0], fp[1], fp[2])) < 1e-3,
		"the frame pose is delivered verbatim (%.5f m of drift)" %
		got.distance_to(Vector3(fp[0], fp[1], fp[2])))
	check(absf(car.speed_kmh() - float(fr.kmh)) < 0.05,
		"speed on the bar = speed from the frame (%.2f vs %.2f)" % [car.speed_kmh(), float(fr.kmh)])
	var before := car.chassis.global_position
	player.scrub(-1)
	var prev: PackedFloat32Array = rec.frames[k - 1].p
	check(absf(player.cursor - (ft - 1.0 / ReplayRecorder.RATE)) < 1e-6,
		"one step back moved the cursor by exactly one frame (%.5f vs %.5f)" % [
			player.cursor, ft - 1.0 / ReplayRecorder.RATE])
	check(car.chassis.global_position.distance_to(Vector3(prev[0], prev[1], prev[2])) < 0.02,
		"one step back = the previous ring frame (%.5f m)" %
		car.chassis.global_position.distance_to(Vector3(prev[0], prev[1], prev[2])))
	check(car.chassis.global_position != before, "stepping back actually moved the car")
	if dents_before > 0:
		player.seek(rec.window_start())
		check(car.body.dent_count == 0,
			"seeking to the window start gives a body without this window's dents (was %d)" % dents_before)
		player.seek(rec.window_end())
		check(car.body.dent_count >= 1,
			"seeking to the window end brought the dents back (%d)" % car.body.dent_count)
	player.end()
	check(not car.replaying, "the player cleared the replay mode")
	var d0 := car.chassis.global_transform.origin.distance_to(tf_before.origin)
	check(d0 < 1e-4, "exiting the replay restored the live pose exactly (%.5f m)" % d0)
	check(car.body.dent_count == dents_before,
		"exit restored the body to the entry state (%d vs %d)" % [car.body.dent_count, dents_before])
	check(absf(car.chassis.global_transform.origin.y - tf_before.origin.y) < 1e-4,
		"the restore neither dropped nor lifted the car (%.4f)" % car.chassis.global_transform.origin.y)
	_phase = "scrub"
	_f = _ticks

# ── 4. the recorder stays silent while playback runs ────────────────────────
func _scrub_stage() -> void:
	if _sub == 0:
		_drive(true)
		_sub_at = _ticks
		_sub = 1
		return
	if _sub == 1 and _ticks == _sub_at + 60:
		_n_snap = rec.count()
		_t_snap = rec.sim_t
		var ok := player.begin_at(rec.window_end() - 0.5)
		if not ok:
			print("dbg begin: active=%s count=%d window=[%.2f..%.2f]" % [
				player.active, rec.count(), rec.window_start(), rec.window_end()])
		check(ok, "the second entry opened")
		player.playing = true
		player.rate_i = 3          # ×2: let it spin as it can
		_sub = 2
		_sub_at = _ticks
		return
	if _sub == 2 and _ticks == _sub_at + 240:
		_sub = 3
		check(rec.sim_t == _t_snap,
			"while playing the recorder writes not a single frame (sim_t %.3f vs %.3f)" % [rec.sim_t, _t_snap])
		check(rec.count() == _n_snap,
			"the ring did not grow during the replay (%d vs %d)" % [rec.count(), _n_snap])
		check(player.cursor > rec.window_end() - 0.5,
			"the player advanced on its own, without a physics tick (%.2f)" % player.cursor)
		player.end()
		return
	if _sub == 3:
		_drive(false)
		_sub = 4
		_phase = "game"
		GameContext.select("sedan", "town")
		_gm = load("res://scenes/game.tscn").instantiate()
		add_child(_gm)
		_gm_f = 0
# ── 5. the live path: pause menu → replay → exit ────────────────────────────
func _game_stage() -> void:
	_gm_f += 1
	if _gm_f == 30:
		check(_gm.replay != null and _gm.replay_player != null,
			"GameManager built the recorder and the player")
		check(_gm.replay.player == _gm.replay_player,
			"the recorder is wired to the player: a replay does not record itself")
		Input.action_press("throttle")
	if _gm_f == 150:
		Input.action_release("throttle")
		_gm.car.chassis.global_position = Vector3(0, 3.0, 0)
		_gm.car.chassis.linear_velocity = Vector3(0, -18, 0)
		_gm.car.chassis.reset_physics_interpolation()
	if _gm_f == 175:
		check(_gm.replay.dents.size() >= 1,
			"the hard landing was recorded as an impact (%d)" % _gm.replay.dents.size())
		_gm._set_paused(true)
		var btn := _gm.hud.pause_button("РЕПЛЕЙ УДАРА")
		check(btn != null, "the pause menu has a fifth row «РЕПЛЕЙ УДАРА»")
		if btn == null:
			_finish(); return
		_entry_tf = _gm.car.chassis.global_transform
		_entry_lin = _gm.car.chassis.linear_velocity
		_entry_dents = _gm.car.body.dent_count
		_entry_depth = _gm.car.body.max_depth
		_sim_t_at_entry = _gm.replay.sim_t
		btn.pressed.emit()
	if _gm_f == 180:
		check(_gm.replay_player.active, "РЕПЛЕЙ started playback")
		check(_gm.is_frozen(), "the world is frozen during the replay")
		check(_gm.hud.replay_ui_visible(), "the replay bar is visible")
		check(not _gm.hud._pause_panel.visible, "the pause card is hidden, the world is visible")
		check(_gm.car.replaying, "the car is rendered from the player")
	if _gm_f == 210:
		var lt := _gm.replay.last_impact_t()
		var c := _gm.replay_player.cursor
		check(c >= lt - 1.6 and c <= lt + 0.5,
			"the replay started at the last impact (cursor %.2f, impact %.2f)" % [c, lt])
		check(_gm.replay_player.rate() == 0.25, "playback runs at ×0.25")
		_gm.hud.replay_button("ШАГ ▶").pressed.emit()
		_gm.hud.replay_button("БЫСТРЕЕ").pressed.emit()
	if _gm_f == 212:
		check(absf(_gm.replay_player.rate() - 0.5) < 1e-6,
			"«БЫСТРЕЕ» raised the speed to ×0.5 (%.2f)" % _gm.replay_player.rate())
		_gm.hud.replay_button("◀ ШАГ").pressed.emit()
	if _gm_f == 214:
		check(not _gm.replay_player.playing, "stepping does not resume playback")
		_gm.hud.replay_button("ПАУЗА/ПУСК").pressed.emit()
	if _gm_f == 216:
		check(_gm.replay_player.playing, "«ПАУЗА/ПУСК» while stopped starts playback again")
		_gm.hud.replay_button("ПАУЗА/ПУСК").pressed.emit()
	if _gm_f == 218:
		check(not _gm.replay_player.playing, "the same click pauses again")
		check(_gm.replay.sim_t == _sim_t_at_entry,
			"the recorder is silent during the live replay (%.3f vs %.3f)" % [_gm.replay.sim_t, _sim_t_at_entry])
		_gm.hud.replay_button("ВЫХОД").pressed.emit()
	if _gm_f == 222:
		check(not _gm.replay_player.active, "exit finished the replay")
		check(not _gm.is_frozen(), "the world runs again")
		check(not _gm.hud.replay_ui_visible(), "the replay bar is hidden after exit")
		var d := _gm.car.chassis.global_transform.origin.distance_to(_entry_tf.origin)
		check(d < 0.05, "the pose after exit matches the entry poses (%.4f m)" % d)
		check(_gm.car.chassis.linear_velocity.distance_to(_entry_lin) < 0.5,
			"the restore did not zero the car's speed (%.2f vs %.2f)" %
			[_gm.car.chassis.linear_velocity.length(), _entry_lin.length()])
		check(_gm.car.body.dent_count == _entry_dents,
			"the body returned to the entry state (%d vs %d)" % [_gm.car.body.dent_count, _entry_dents])
		check(absf(_gm.car.body.max_depth - _entry_depth) < 1e-3,
			"the dent depth is the same as before the replay (%.4f vs %.4f)" %
			[_gm.car.body.max_depth, _entry_depth])
	if _gm_f == 250:
		_gm._set_paused(true)
		_gm.hud.pause_button("РЕПЛЕЙ УДАРА").pressed.emit()
	if _gm_f == 254:
		check(_gm.replay_player.active, "the second entry into the replay opened")
		_gm._unhandled_input(_act("pause"))
	if _gm_f == 258:
		check(not _gm.replay_player.active, "Esc left the replay back into the run")
		check(not _gm.is_frozen(), "after Esc the world unfroze")
		_gm._set_paused(true)
		_gm.hud.pause_button("РЕПЛЕЙ УДАРА").pressed.emit()
	if _gm_f == 262:
		_gm._unhandled_input(_act("respawn"))
	if _gm_f == 266:
		check(not _gm.replay_player.active, "R during the replay exits the playback")
		# the window restarted: before respawn it was full (200 frames), after the
		# restart it had no time to fill even a second
		check(_gm.replay.count() < int(ReplayRecorder.RATE),
			"the restart reset the window: no replay through a teleport (%d frames)" % _gm.replay.count())
		check(not _gm.is_frozen(), "after R the run continues")
		_finish()

func _finish() -> void:
	if _phase == "done": return
	_phase = "done"
	_drive(false)
	Input.action_release("throttle")
	if _gm != null and is_instance_valid(_gm):
		if _gm.replay_player != null and _gm.replay_player.active: _gm.replay_player.end()
		_gm._set_paused(false)
		_gm.queue_free()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
