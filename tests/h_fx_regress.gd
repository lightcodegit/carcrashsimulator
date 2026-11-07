extends Node3D
# Регрессии пакета правок по аудиту: идемпотентный attach, таймеры искр по
# симуляции (а не по часовой стене), честный playback_missing после
# пауза/продолжить и закрытие реплея при респауне.
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
	fx.attach(car)                 # та же машина: ничего не должно удвоиться
	check(fx.get_child_count() == kids,
		"повторный attach той же машины не плодит детей (%d против %d)" % [fx.get_child_count(), kids])
	check(fx.all_emitters().size() == emitters,
		"все эммитеры по-прежнему в списке (%d против %d)" % [fx.all_emitters().size(), emitters])
	fx.attach(car)
	check(fx.get_child_count() == kids, "третий attach тоже молчит")
	_stage = 1
	_f = 0

func _spark_cadence() -> void:
	if _f == 2:
		fx.set_enabled(true)
		fx._spark_gap = 0.0
		fx.prop_puffs = 0
		# два удара в соседних тиках: прежнее ограничение по часовой стене
		# глушило второй в headless с --fixed-fps и расходилось с живым окном
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		var first := fx._sparks.emitting
		fx._sparks.emitting = false
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		check(first, "первый удар дал искры")
		check(not fx._sparks.emitting,
			"второй удар в том же тике заглушен зазором — это и есть троттлинг")
		check(absf(fx._spark_gap - 0.08) < 1e-6,
			"зазор искрового залпа задан в секундах симуляции (%.3f)" % fx._spark_gap)
		# главное: зазор тратится на симуляционном времени. Прежний Time.get_ticks_msec
		# в headless с --fixed-fps съедал залпы пачкой (тик быстрее часовой стены),
		# и счётчик искр расходился с живым окном.
		for i in 6:
			fx._physics_process(1.0 / 60.0)
		check(fx._spark_gap <= 1e-6,
			"шесть тиков по 16.6 мс погасили зазор полностью (%.4f)" % fx._spark_gap)
		fx._sparks.emitting = false
		fx._on_impact(120.0, car.chassis.global_position, Vector3.RIGHT)
		check(fx._sparks.emitting, "по истечении зазора по симуляции искры снова есть")
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
	check(before, "в headless playback_missing поднят сразу")
	check(drv.playback_missing,
		"пауза/продолжить не прячут playback_missing (иначе h_audio врёт про PARTIAL)")
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
		# в городе на стоянке ударов нет — открываем окно вручную
		_gm.replay_player.begin_at(_gm.replay.window_start())
	if _f == 50:
		check(_gm.replay_player.active, "реплей открыт")
		check(_gm.car.replaying, "машина в режиме проигрывания")
		_gm._respawn_now()
	if _f == 54:
		check(not _gm.replay_player.active,
			"респаун закрыл проигрывание, а не оставил replaying поверх физики")
		check(not _gm.car.replaying, "CarRig вышел из режима проигрывания")
		check(_gm.replay.count() < int(ReplayRecorder.RATE),
			"кольцо после респауна началось заново (%d кадров)" % _gm.replay.count())
		_gm._set_paused(false)
		_stage = 4
		_f = 0

func _finish() -> void:
	if _gm != null and is_instance_valid(_gm): _gm.queue_free()
	if fx != null and is_instance_valid(fx): fx.queue_free()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
