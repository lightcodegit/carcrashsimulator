extends Node3D
# Audio driver on a live machine: the flash frequency follows the rpm, frames
# really go into playback, settings reach the "SFX" bus, the impact reaches the mixer.
# Headless audio is a stub: if nothing was pushed to playback we print PARTIAL, but
# everything else (hz, peaks, bus, counters) is checked anyway.
var _fails := 0
var car: CarRig
var drv: AudioDriver
var _f := 0
var _phase := "idle"
var _hz_a := 0.0
var _hz_b := 0.0
var _pushed_a := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wb := BoxShape3D.new()
	wb.size = Vector3(2, 4, 40); wcs.shape = wb
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(48, 1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	drv = AudioDriver.new(); add_child(drv)
	drv.attach(car)
	_bus_idempotent()
	_mute_volume()
	_phase = "accel"
	Input.action_press("throttle")

# the "SFX" bus is idempotent: a repeated ensure must not spawn a second bus
func _bus_idempotent() -> void:
	var idx0 := drv.sfx_bus_index()
	check(idx0 >= 0, "SFX bus exists (%d)" % idx0)
	var n0 := AudioServer.get_bus_count()
	drv._ensure_bus()
	drv._ensure_bus()
	check(AudioServer.get_bus_count() == n0, "repeated ensure added no bus (%d vs %d)" % [
		AudioServer.get_bus_count(), n0])
	check(drv.sfx_bus_index() == idx0, "bus index is stable (%d)" % drv.sfx_bus_index())

func _mute_volume() -> void:
	Settings.set_value("audio_enabled", true)
	Settings.set_value("audio_volume", 0.5)
	drv.apply_settings()
	var idx := drv.sfx_bus_index()
	check(idx >= 0 and not AudioServer.is_bus_mute(idx), "with sound enabled the bus is not muted")
	var lin := drv.bus_linear_volume()
	check(lin > 0.45 and lin < 0.55, "volume 0.5 reached the bus linearly (%.3f)" % lin)
	Settings.set_value("audio_enabled", false)
	drv.apply_settings()
	check(AudioServer.is_bus_mute(drv.sfx_bus_index()), "disabled sound mutes the bus")
	Settings.set_value("audio_enabled", true)
	drv.apply_settings()
	check(not AudioServer.is_bus_mute(drv.sfx_bus_index()), "enabled sound lifts the mute")
	Settings.set_value("audio_volume", 0.9)
	drv.apply_settings()
	check(absf(drv.bus_linear_volume() - 0.9) < 0.05, "the volume slider reached the bus (%.3f)" % drv.bus_linear_volume())
	Settings.set_value("audio_volume", 0.8)
	drv.apply_settings()

func _physics_process(_dt: float) -> void:
	_f += 1
	match _phase:
		"accel":
			if _f == 30:
				_hz_a = drv.last_engine_hz
				_pushed_a = drv.frames_pushed
			if _f == 90:
				_hz_b = drv.last_engine_hz
				Input.action_release("throttle")
				# one honest kick into the wall side: the impact detector measures the
				# speed loss, not a forcibly set velocity
				car.chassis.linear_velocity = Vector3(35.0, 0.0, 0.0)
				_phase = "crash"
		"crash":
			if _f == 300:
				check(false, "no impact against the wall by frame %d" % _f)
				_finish()
			elif drv.impacts_heard > 0:
				_phase = "after_impact"
		"after_impact":
			if drv.mixer.impact_env() > 0.1 or _f > 340:
				_finish()

func _finish() -> void:
	if _phase == "done": return
	_phase = "done"
	check(drv.last_engine_hz > 0.0, "after acceleration the flash frequency is non-zero (%.1f Hz)" % drv.last_engine_hz)
	check(_hz_b > _hz_a and _hz_a > 0.0,
		"the frequency grows with the rpm (%.1f -> %.1f Hz)" % [_hz_a, _hz_b])
	# RPM→Hz correspondence: firing = rpm/60×CYL/2; compare against the actual wheels
	var rpm := 0.0
	var n := 0
	for i in car.wheel_count():
		var w := car.chassis.get_node_or_null("Wheel%d" % i) as VehicleWheel3D
		if w != null and w.is_in_contact():
			rpm += absf(w.get_rpm()); n += 1
	if n > 0:
		rpm /= float(n)
		var want := rpm / 60.0 * AudioMixer.CYL / 2.0
		check(absf(drv.last_engine_hz - want) <= 2.0,
			"flash Hz = rpm/60×cylinders/2 (%.1f vs %.1f)" % [drv.last_engine_hz, want])
	# The pushed-frame counter only makes sense where output exists:
	# on the dummy driver the driver deliberately does not start the generator (freeing
	# a live AudioStreamGenerator in headless crashed the process).
	if AudioDriver.has_output_device():
		check(drv.frames_pushed > _pushed_a,
			"frames go into playback as the car moves (%d -> %d)" % [_pushed_a, drv.frames_pushed])
	check(drv.impacts_heard >= 1, "the impact reached the driver (%d)" % drv.impacts_heard)
	check(drv.mixer.impact_env() > 0.1,
		"after the impact the mixer rings with a burst (%.3f)" % drv.mixer.impact_env())
	check(drv.last_block_peak > 0.0 and drv.last_block_peak <= 1.0,
		"block peak within bounds (%.3f)" % drv.last_block_peak)
	if drv.playback_missing:
		print("PARTIAL: audio driver %s — no output started, data checked up to the output boundary" %
			AudioServer.get_driver_name())
	else:
		print("PARTIAL: speaker sound is not checked here — data checked up to the output boundary")
	# live run through GameManager: mute must reach the bus on Settings.changed
	await _in_game()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _in_game() -> void:
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().physics_frame
	check(g.audio != null and g.vibration != null, "GameManager creates audio and vibration nodes")
	Settings.set_value("audio_enabled", false)
	await get_tree().physics_frame
	var idx := g.audio.sfx_bus_index()
	check(idx >= 0 and AudioServer.is_bus_mute(idx), "the mute setting reaches the bus in a live scene")
	Settings.set_value("audio_enabled", true)
	Settings.set_value("audio_volume", 0.4)
	await get_tree().physics_frame
	check(absf(g.audio.bus_linear_volume() - 0.4) < 0.05,
		"volume reaches the bus in a live scene (%.3f)" % g.audio.bus_linear_volume())
	g.queue_free()
	for i in 3:
		await get_tree().process_frame
