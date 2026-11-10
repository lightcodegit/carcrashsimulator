extends Node3D
# Second-stage particles: tyre smoke per wheel, sparks from scraping the wall, dust from a
# knocked-over prop and an honest on/off setting. Two courses: a bare harness (the enable
# conditions are computed straight from CarRig) and the live GameManager scene (the setting,
# pause, restart and the prop hook reach the place where the player expects them).
var _fails := 0
var car: CarRig
var fx: EffectsDirector
var skid: SkidMarks
var _f := 0
var _phase := "boot"
var _drawn_at_drift := 0
var _bursts_at_wall := 0
var _wall_at := 0
var _puff_at := -1
var _prop_at := 0
var _cone_pos := Vector3(0.0, 0.0, 10.0)
var _cone: LooseProp
var _wall: StaticBody3D
var _gm: GameManager
var _gm_f := 0
var _gm_marks_at := 0
var _drift_frames := 0
var _drift_smoke := 0
var _drift_level := 0
var _drift_mismatch := 0
var _tog_off := 0
var _saw_live_smoke := false
var _live_state := 0
var _live_f0 := 0
var _live_off_marks := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	# the host scene may raise the pause (gm._set_paused), while the harness must keep counting frames
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	# the long wall: in the first stage it stands aside (z=60), and for the scrape stage it
	# moves to the z=5.0 edge exactly opposite the lane
	_wall = StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wb := BoxShape3D.new()
	wb.size = Vector3(900, 3, 2); wcs.shape = wb
	_wall.add_child(wcs); add_child(_wall); _wall.global_position = Vector3(300, 0.5, 60.0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	fx = EffectsDirector.new(); add_child(fx)
	fx.attach(car)
	skid = SkidMarks.new(); add_child(skid)
	skid.setup(car)
	_cone = MapProps.loose(self, "res://assets/props/cone.glb", _cone_pos,
		MapDefs.PROP, 0.0, 3.0) as LooseProp
	# the same hook GameManager installs; without it the cone would behave as before
	_cone.on_hit_fx = fx.on_prop_hit
	check(fx.smoke_emitters().size() == car.wheel_count(),
		"smoke on every wheel (%d vs %d)" % [fx.smoke_emitters().size(), car.wheel_count()])
	_phase = "drift"
	Input.action_press("throttle")

func _smoke_on_count() -> int:
	var n := 0
	for p in fx.smoke_emitters():
		if p.emitting: n += 1
	return n

func _wheels_at_threshold() -> int:
	var n := 0
	for l in car.skid_levels():
		if l >= SkidMarks.MIN_SKID: n += 1
	return n

func _any_emitting(owner: EffectsDirector) -> bool:
	for p in owner.all_emitters():
		if p.emitting: return true
	return false

func _physics_process(_dt: float) -> void:
	_f += 1
	match _phase:
		"drift":
			if _f == 100:
				_drawn_at_drift = skid.marks_drawn()
				Input.action_press("handbrake")
				Input.action_press("steer_right")
			# both the mark and the smoke are accumulated quantities: comparing them on a
			# single frame is pointless (by frame 200 the slide could already be over), so the
			# condition is compared on every frame of the window and must match everywhere
			if _f > 100 and _f <= 200:
				_drift_frames += 1
				var smoke_now := _smoke_on_count()
				var level_now := _wheels_at_threshold()
				_drift_smoke += 1 if smoke_now > 0 else 0
				_drift_level += 1 if level_now > 0 else 0
				_drift_mismatch += 1 if smoke_now != level_now else 0
			if _f == 200:
				_after_drift()
		"prop":
			if _puff_at < 0 and fx.prop_puffs >= 1:
				_puff_at = _f
			if _puff_at >= 0 and _f >= _puff_at + 90:
				_after_prop()
			elif _f == _prop_at + 560:
				check(false, "the cone was not knocked over within the budget (%d puffs)" % fx.prop_puffs)
				_to_wall()
		"wall":
			# the switch is checked where something really happens: the scraper fires bursts
			# about every 0.13 s, and "off" has to stop the counter, not only dim an emitter
			# that is already fading
			if _f == _wall_at + 150:
				_tog_off = fx.scrape_bursts
				fx.set_enabled(false)
			if _f == _wall_at + 270:
				var missed := fx.scrape_bursts - _tog_off
				check(missed <= 1,
					"disabled particles stop the scraper (%d bursts over 2 s)" % missed)
				fx.set_enabled(true)
			if _f >= _wall_at + 420:
				_after_wall()
		"game":
			_game_stage()
		_:
			pass

# A) smoke and tyre marks are enabled by one and the same condition on one and the same levels
func _after_drift() -> void:
	var drawn := skid.marks_drawn() - _drawn_at_drift
	check(drawn > 10, "the slide draws marks (%d marks)" % drawn)
	check(_drift_mismatch == 0,
		"exactly the wheels that mark are the ones smoking: mismatch %d frames out of %d" % [
			_drift_mismatch, _drift_frames])
	check(_drift_level > 0, "inside the slide window a wheel was above the SkidMarks threshold")
	check(_drift_smoke == _drift_level,
		"frames at the threshold %d, frames with smoke %d" % [_drift_level, _drift_smoke])
	# B) disabled particles extinguish ALL emitters, enabling them restores the condition
	fx.set_enabled(false)
	await get_tree().physics_frame
	check(not _any_emitting(fx), "particles off: no emitter is active")
	fx.set_enabled(true)
	await get_tree().physics_frame
	check(_smoke_on_count() == _wheels_at_threshold(),
		"particles on: smoke equals the condition again (%d vs %d)" % [
			_smoke_on_count(), _wheels_at_threshold()])
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 10.0)))
	_cone.restore()
	_puff_at = -1
	_prop_at = _f
	_phase = "prop"

# C) knocked-over prop: dust through the callback; the cone's flight is waited for honestly, 1.5 s
func _after_prop() -> void:
	if _phase != "prop": return
	check(fx.prop_puffs >= 1, "the knocked-over cone gave a dust puff (%d)" % fx.prop_puffs)
	var fly := _cone.global_position.distance_to(_cone_pos)
	check(fly > 2.0, "the cone really got hit and flew off (%.1f m)" % fly)
	check(fx._debris.emitting, "the dust emitter was armed by the impact")
	_to_wall()

func _to_wall() -> void:
	if _phase == "wall": return
	_wall.global_position = Vector3(300, 0.5, 6.0)
	car.respawn(Transform3D(Basis.from_euler(Vector3(0, -0.05, 0)), Vector3(-20, 1.0, 3.7)))
	_bursts_at_wall = fx.scrape_bursts
	Input.action_release("steer_right")
	Input.action_release("handbrake")
	Input.action_press("throttle")
	_phase = "wall"
	_wall_at = _f

# D) sliding contact along the wall: sparks in bursts, but throttled
func _after_wall() -> void:
	if _phase != "wall": return
	_phase = "reset"
	var bursts := fx.scrape_bursts - _bursts_at_wall
	check(bursts >= 2, "sliding along the wall produced spark bursts (%d)" % bursts)
	# the window is 420 frames ≈ 7 s, the burst threshold 0.13 s: without throttling it would be ~3200
	check(bursts <= 60, "scraper bursts are throttled instead of raining every frame (%d)" % bursts)
	check(fx.all_emitters().size() >= car.wheel_count() + 4,
		"the full emitter set: sparks, dust, debris, flame, smoke (%d)" % fx.all_emitters().size())
	Input.action_release("throttle")
	_reset_stage()

func _reset_stage() -> void:
	_phase = "game"
	fx.reset_transient()
	check(not fx._sparks.emitting, "reset_transient extinguished the live sparks")
	Input.action_release("throttle")
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	GameContext.select("sedan", "town")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	_gm_f = 0
	_live_state = 0
	_live_f0 = 0

# The live-scene milestones are tied to the first visible smoke, not to a frame number:
# on the arena the hills kill the slide before the scheduled check frame arrives, so the
# town's flat asphalt is chosen for this (the same conclusion as in h_padflow).
func _game_stage() -> void:
	_gm_f += 1
	if _gm_f == 40:
		var wired := 0
		for n in get_tree().get_nodes_in_group(LooseProp.GROUP):
			if not (n is LooseProp): continue
			if not (n as LooseProp).on_hit_fx.is_valid():
				check(false, "GameManager did not hang a dust receiver on prop %s" % n.name)
				return
			wired += 1
		check(wired > 0, "all %d props of the live scene have a dust receiver" % wired)
		Input.action_press("throttle")
	if _gm_f == 150:
		_gm_marks_at = _gm.skid.marks_drawn()
		Input.action_press("handbrake")
		Input.action_press("steer_right")
	match _live_state:
		0:
			# waiting for the first smoke in the window 150..340
			for p in _gm.effects.smoke_emitters():
				if p.emitting:
					_saw_live_smoke = true
					_live_f0 = _gm_f
					_live_state = 1
					break
			if _gm_f == 340:
				check(false, "in the live scene the smoke never appeared (marks +%d)" % [
					_gm.skid.marks_drawn() - _gm_marks_at])
				check(_gm.skid.marks_drawn() > _gm_marks_at,
					"in the live scene at least the marks were drawn")
				_live_state = 9
		1:
			if _gm_f == _live_f0 + 10:
				check(_gm.skid.marks_drawn() > _gm_marks_at,
					"in the live scene the slide draws marks and smokes at once")
				_live_off_marks = _gm.skid.marks_drawn()
				Settings.set_value("particles_enabled", false)
				_live_state = 2
		2:
			if _gm_f == _live_f0 + 25:
				check(not _any_emitting(_gm.effects), "the particles setting extinguishes the whole live scene")
				check(_gm.skid.marks_drawn() > _live_off_marks,
					"tyre marks are not particles: they keep being drawn")
				Settings.set_value("particles_enabled", true)
				_live_state = 3
		3:
			if _gm_f == _live_f0 + 38:
				var any3 := false
				for p in _gm.effects.smoke_emitters():
					if p.emitting: any3 = true
				check(any3, "the enabled setting brings smoke back in the live slide")
				_gm._set_paused(true)
				_live_state = 4
		4:
			if _gm_f == _live_f0 + 46:
				check(not _any_emitting(_gm.effects), "pause extinguishes the particles")
				_gm._set_paused(false)
				_gm._respawn_now()
				_live_state = 5
		5:
			if _gm_f == _live_f0 + 54:
				check(not _any_emitting(_gm.effects),
					"the restart extinguished everything live (smoke, sparks, flame, dust)")
				Input.action_release("handbrake")
				Input.action_release("steer_right")
				_finish()
		_:
			pass

func _finish() -> void:
	if _phase == "done": return
	_phase = "done"
	_gm.queue_free()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
