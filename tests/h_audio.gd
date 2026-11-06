extends Node3D
# Драйвер звука на живой машине: частота вспышек следует за оборотами, кадры
# реально уходят в playback, настройки доходят до шины «SFX», удар — до микшера.
# Headless-аудио — заглушка: если playback не выдался, печатаем PARTIAL, но всё
# остальное (hz, пики, шина, счётчики) проверяется и так.
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

# шина «SFX» идемпотентна: повторный ensure не плодит вторую шину
func _bus_idempotent() -> void:
	var idx0 := drv.sfx_bus_index()
	check(idx0 >= 0, "шина SFX существует (%d)" % idx0)
	var n0 := AudioServer.get_bus_count()
	drv._ensure_bus()
	drv._ensure_bus()
	check(AudioServer.get_bus_count() == n0, "повторный ensure не добавил шину (%d против %d)" % [
		AudioServer.get_bus_count(), n0])
	check(drv.sfx_bus_index() == idx0, "индекс шины стабилен (%d)" % drv.sfx_bus_index())

func _mute_volume() -> void:
	Settings.set_value("audio_enabled", true)
	Settings.set_value("audio_volume", 0.5)
	drv.apply_settings()
	var idx := drv.sfx_bus_index()
	check(idx >= 0 and not AudioServer.is_bus_mute(idx), "при включённом звуке шина не глуха")
	var lin := drv.bus_linear_volume()
	check(lin > 0.45 and lin < 0.55, "громкость 0.5 дошла до шины линейно (%.3f)" % lin)
	Settings.set_value("audio_enabled", false)
	drv.apply_settings()
	check(AudioServer.is_bus_mute(drv.sfx_bus_index()), "выключенный звук глушит шину")
	Settings.set_value("audio_enabled", true)
	drv.apply_settings()
	check(not AudioServer.is_bus_mute(drv.sfx_bus_index()), "включённый звук снимает mute")
	Settings.set_value("audio_volume", 0.9)
	drv.apply_settings()
	check(absf(drv.bus_linear_volume() - 0.9) < 0.05, "ползунок громкости дошёл до шины (%.3f)" % drv.bus_linear_volume())
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
				# один честный пинок в бок стены: детектор удара меряет потерю
				# скорости, а не принудительно заданную скорость
				car.chassis.linear_velocity = Vector3(35.0, 0.0, 0.0)
				_phase = "crash"
		"crash":
			if _f == 300:
				check(false, "удар о стену не случился к кадру %d" % _f)
				_finish()
			elif drv.impacts_heard > 0:
				_phase = "after_impact"
		"after_impact":
			if drv.mixer.impact_env() > 0.1 or _f > 340:
				_finish()

func _finish() -> void:
	if _phase == "done": return
	_phase = "done"
	check(drv.last_engine_hz > 0.0, "после разгона частота вспышек ненулевая (%.1f Гц)" % drv.last_engine_hz)
	check(_hz_b > _hz_a and _hz_a > 0.0,
		"частота растёт вместе с оборотами (%.1f -> %.1f Гц)" % [_hz_a, _hz_b])
	# соответствие RPM→Гц: firing = rpm/60×CYL/2; сверяем с фактическими колёсами
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
			"Гц вспышек = обороты/60×цилиндров/2 (%.1f против %.1f)" % [drv.last_engine_hz, want])
	# Счётчик протолканных кадров имеет смысл только там, где вывод существует:
	# на dummy-дровере драйвер намеренно не заводит генератор (освобождение
	# живого AudioStreamGenerator в headless валило процесс).
	if AudioDriver.has_output_device():
		check(drv.frames_pushed > _pushed_a,
			"кадры уходят в playback по мере движения (%d -> %d)" % [_pushed_a, drv.frames_pushed])
	check(drv.impacts_heard >= 1, "удар долетел до драйвера (%d)" % drv.impacts_heard)
	check(drv.mixer.impact_env() > 0.1,
		"после удара микшер звенит burst'ом (%.3f)" % drv.mixer.impact_env())
	check(drv.last_block_peak > 0.0 and drv.last_block_peak <= 1.0,
		"пик блока в границах (%.3f)" % drv.last_block_peak)
	if drv.playback_missing:
		print("PARTIAL: аудиодрайвер %s — вывод не заводится, проверены данные до границы вывода" %
			AudioServer.get_driver_name())
	else:
		print("PARTIAL: звук из колонок здесь не проверяется — проверены данные до границы вывода")
	# живой прогон через GameManager: mute обязан доходить до шины на Settings.changed
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
	check(g.audio != null and g.vibration != null, "GameManager создаёт аудио- и вибро-узлы")
	Settings.set_value("audio_enabled", false)
	await get_tree().physics_frame
	var idx := g.audio.sfx_bus_index()
	check(idx >= 0 and AudioServer.is_bus_mute(idx), "настройка mute доходит до шины в живой сцене")
	Settings.set_value("audio_enabled", true)
	Settings.set_value("audio_volume", 0.4)
	await get_tree().physics_frame
	check(absf(g.audio.bus_linear_volume() - 0.4) < 0.05,
		"громкость доходит до шины в живой сцене (%.3f)" % g.audio.bus_linear_volume())
	g.queue_free()
	for i in 3:
		await get_tree().process_frame
