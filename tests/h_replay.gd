extends Node3D
# Реплей удара. Два курса: голый харнес (кольцо кадров, горизонт, события ударов и
# точность проигрывания до последнего кадра) и живая сцена GameManager (меню паузы,
# кнопки полосы, Esc, рестарт и возврат живого состояния).
#
# Главный признак, что реплей НЕ пересимулирует: позу машина берёт из кадра кольца,
# а не из физики. В живой сцене мир стоит на паузе (ни одного шага симуляции), и
# recorder за это время не дописывает ни кадра — обе проверки падают, если плеер
# начнёт считать сам или если пауза не заморозит запись.
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
	rec.attach(car, null)          # без сцены: паузу харнес моделирует сам
	player = ReplayPlayer.new()
	add_child(player)
	player.setup(rec, car, null)
	rec.player = player
	_guard_validation()

# Регресс на дыру валидации ленты (#2) и падение frame_at на пустом кольце (#3).
# Проверяем на реальном пустом рекордере до начала живых стадий.
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
		"полный кадр с nitro и hot принимается")
	check(not ReplayRecorder._frames_valid([_mkframe(false, true)]),
		"кадр без nitro отклоняется: иначе _apply читает a.nitro и падает в реплее")
	check(not ReplayRecorder._frames_valid([_mkframe(true, false)]),
		"кадр без hot отклоняется: иначе _apply читает a.hot и падает в реплее")
	check(rec.frame_at(0.0) == {},
		"frame_at на пустом кольце отдаёт {}, а не индексирует frames[0]")

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

# ── 1. кольцо: частота, горизонт, память ────────────────────────────────────
func _ring() -> void:
	if _ticks == 2:
		_drive(true)
		_t0 = rec.sim_t
		return
	if _ticks == 62:
		# секунда физики = ровно RATE кадров и ровно 1 с симуляции
		check(absf(rec.sim_t - (_t0 + 1.0)) < 0.05,
			"секунда симуляции считается физическими тиками (%.3f)" % (rec.sim_t - _t0))
		check(absf(rec.count() - ReplayRecorder.RATE) <= 2,
			"кадров в секунду ровно %d (%d)" % [int(ReplayRecorder.RATE), rec.count()])
		return
	if _ticks == 1202:
		var span := rec.window_end() - rec.window_start()
		check(rec.count() == ReplayRecorder.MAX_FRAMES,
			"кольцо заполнено и не растёт дальше (%d из %d)" % [rec.count(), ReplayRecorder.MAX_FRAMES])
		check(span <= ReplayRecorder.HORIZON_S + 0.15 and span >= ReplayRecorder.HORIZON_S - 0.6,
			"окно реплея держит ровно %.0f с (%.2f)" % [ReplayRecorder.HORIZON_S, span])
		var bytes := rec.bytes_used()
		check(bytes > 0 and bytes < 4_000_000,
			"окно в 10 с весит %.0f КБ и не раздувается" % (bytes / 1024.0))
		print("bench: окно %d кадров = %.1f КБ, sim_t=%.2f" % [rec.count(), bytes / 1024.0, rec.sim_t])
		_phase = "impact"
		_f = _ticks

# ── 2. удар пишется событием, а не переписывается с нуля ────────────────────
func _impact_stage() -> void:
	if _ticks == _f + 2:
		_drive(false)
		car.chassis.global_position = Vector3(48, 1.2, 0)
		car.chassis.linear_velocity = Vector3(60, 0, 0)
		car.chassis.reset_physics_interpolation()
		return
	if _ticks != _f + 40: return
	check(rec.dents.size() >= 1, "удар записан как событие (%d)" % rec.dents.size())
	var lt := rec.last_impact_t()
	check(lt >= rec.window_start() and lt <= rec.window_end(),
		"момент удара внутри окна (%.2f против [%.2f..%.2f])" % [lt, rec.window_start(), rec.window_end()])
	var d: Dictionary = rec.dents[rec.dents.size() - 1]
	check(d.lp is Vector3 and absf(d.ld.length() - 1.0) < 0.01,
		"событие хранит точку и единичное направление в пространстве кузова (|n|=%.4f)" % d.ld.length())
	_phase = "exact"
	_f = _ticks

# ── 3. точность проигрывания: поза из кадра, возврат состояния ───────────────
func _exact_stage() -> void:
	if _ticks != _f + 4: return
	var tf_before := car.chassis.global_transform
	var dents_before := car.body.dent_count
	check(player.begin_at(rec.window_end() - 2.0), "плеер открыл окно за 2 с до конца")
	check(car.replaying, "CarRig переведён в режим проигрывания")
	# сравниваем ровно с кадром: между кадрами плеер blend-ит, и расхождение
	# в полметра на 600 км/ч — это интерполяция, а не ошибка
	var k: int = rec.count() - 20
	var ft: float = float(rec.frames[k].t)
	player.seek(ft)
	var fr: Dictionary = rec.frame_at(ft)
	var fp: PackedFloat32Array = fr.p
	var got := car.chassis.global_transform.origin
	check(absf(float(fr.t) - ft) < 1e-6, "мотка к кадру %.3f попала в тот же кадр" % ft)
	check(got.distance_to(Vector3(fp[0], fp[1], fp[2])) < 1e-3,
		"поза кадра отдана дословно (%.5f м расхождения)" %
		got.distance_to(Vector3(fp[0], fp[1], fp[2])))
	check(absf(car.speed_kmh() - float(fr.kmh)) < 0.05,
		"скорость на полосе = скорость из кадра (%.2f против %.2f)" % [car.speed_kmh(), float(fr.kmh)])
	var before := car.chassis.global_position
	player.scrub(-1)
	var prev: PackedFloat32Array = rec.frames[k - 1].p
	check(absf(player.cursor - (ft - 1.0 / ReplayRecorder.RATE)) < 1e-6,
		"шаг назад сдвинул курсор ровно на кадр (%.5f против %.5f)" % [
			player.cursor, ft - 1.0 / ReplayRecorder.RATE])
	check(car.chassis.global_position.distance_to(Vector3(prev[0], prev[1], prev[2])) < 0.02,
		"шаг назад = предыдущий кадр кольца (%.5f м)" %
		car.chassis.global_position.distance_to(Vector3(prev[0], prev[1], prev[2])))
	check(car.chassis.global_position != before, "шаг назад реально сдвинул машину")
	if dents_before > 0:
		player.seek(rec.window_start())
		check(car.body.dent_count == 0,
			"мотка к началу окна даёт кузов без вмятин этого окна (было %d)" % dents_before)
		player.seek(rec.window_end())
		check(car.body.dent_count >= 1,
			"перемотка к концу окна вернула вмятины (%d)" % car.body.dent_count)
	player.end()
	check(not car.replaying, "плеер снял режим проигрывания")
	var d0 := car.chassis.global_transform.origin.distance_to(tf_before.origin)
	check(d0 < 1e-4, "выход из реплея вернул живую позу точно (%.5f м)" % d0)
	check(car.body.dent_count == dents_before,
		"выход вернул кузов в состояние входа (%d против %d)" % [car.body.dent_count, dents_before])
	check(absf(car.chassis.global_transform.origin.y - tf_before.origin.y) < 1e-4,
		"возврат не уронил и не поднял машину (%.4f)" % car.chassis.global_transform.origin.y)
	_phase = "scrub"
	_f = _ticks

# ── 4. recorder молчит, пока идёт повтор ────────────────────────────────────
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
		check(ok, "второй вход открылся")
		player.playing = true
		player.rate_i = 3          # ×2: пусть крутит как умеет
		_sub = 2
		_sub_at = _ticks
		return
	if _sub == 2 and _ticks == _sub_at + 240:
		_sub = 3
		check(rec.sim_t == _t_snap,
			"во время проигрывания recorder не пишет ни кадра (sim_t %.3f против %.3f)" % [rec.sim_t, _t_snap])
		check(rec.count() == _n_snap,
			"кольцо не выросло во время реплея (%d против %d)" % [rec.count(), _n_snap])
		check(player.cursor > rec.window_end() - 0.5,
			"плеер продвинулся сам, без физического тика (%.2f)" % player.cursor)
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
# ── 5. живой путь: меню паузы → реплей → выход ──────────────────────────────
func _game_stage() -> void:
	_gm_f += 1
	if _gm_f == 30:
		check(_gm.replay != null and _gm.replay_player != null,
			"GameManager собрал recorder и плеер")
		check(_gm.replay.player == _gm.replay_player,
			"recorder подключён к плееру: повтор сам себя не пишет")
		Input.action_press("throttle")
	if _gm_f == 150:
		Input.action_release("throttle")
		_gm.car.chassis.global_position = Vector3(0, 3.0, 0)
		_gm.car.chassis.linear_velocity = Vector3(0, -18, 0)
		_gm.car.chassis.reset_physics_interpolation()
	if _gm_f == 175:
		check(_gm.replay.dents.size() >= 1,
			"жёсткая посадка записана как удар (%d)" % _gm.replay.dents.size())
		_gm._set_paused(true)
		var btn := _gm.hud.pause_button("РЕПЛЕЙ УДАРА")
		check(btn != null, "в меню паузы есть пятая строка «РЕПЛЕЙ УДАРА»")
		if btn == null:
			_finish(); return
		_entry_tf = _gm.car.chassis.global_transform
		_entry_lin = _gm.car.chassis.linear_velocity
		_entry_dents = _gm.car.body.dent_count
		_entry_depth = _gm.car.body.max_depth
		_sim_t_at_entry = _gm.replay.sim_t
		btn.pressed.emit()
	if _gm_f == 180:
		check(_gm.replay_player.active, "РЕПЛЕЙ открыл проигрывание")
		check(_gm.is_frozen(), "на реплее мир заморожен")
		check(_gm.hud.replay_ui_visible(), "полоса реплея видна")
		check(not _gm.hud._pause_panel.visible, "карточка паузы спрятана, мир виден")
		check(_gm.car.replaying, "машина рисуется из плеера")
	if _gm_f == 210:
		var lt := _gm.replay.last_impact_t()
		var c := _gm.replay_player.cursor
		check(c >= lt - 1.6 and c <= lt + 0.5,
			"реплей стартовал у последнего удара (курсор %.2f, удар %.2f)" % [c, lt])
		check(_gm.replay_player.rate() == 0.25, "повтор идёт в ×0.25")
		_gm.hud.replay_button("ШАГ ▶").pressed.emit()
		_gm.hud.replay_button("БЫСТРЕЕ").pressed.emit()
	if _gm_f == 212:
		check(absf(_gm.replay_player.rate() - 0.5) < 1e-6,
			"«БЫСТРЕЕ» подняло скорость до ×0.5 (%.2f)" % _gm.replay_player.rate())
		_gm.hud.replay_button("◀ ШАГ").pressed.emit()
	if _gm_f == 214:
		check(not _gm.replay_player.playing, "шаг не возобновляет проигрывание")
		_gm.hud.replay_button("ПАУЗА/ПУСК").pressed.emit()
	if _gm_f == 216:
		check(_gm.replay_player.playing, "«ПАУЗА/ПУСК» на остановленном запускает снова")
		_gm.hud.replay_button("ПАУЗА/ПУСК").pressed.emit()
	if _gm_f == 218:
		check(not _gm.replay_player.playing, "тот же клик ставит на паузу")
		check(_gm.replay.sim_t == _sim_t_at_entry,
			"recorder на живом реплее молчит (%.3f против %.3f)" % [_gm.replay.sim_t, _sim_t_at_entry])
		_gm.hud.replay_button("ВЫХОД").pressed.emit()
	if _gm_f == 222:
		check(not _gm.replay_player.active, "выход завершил реплей")
		check(not _gm.is_frozen(), "мир снова идёт")
		check(not _gm.hud.replay_ui_visible(), "полоса реплея скрыта после выхода")
		var d := _gm.car.chassis.global_transform.origin.distance_to(_entry_tf.origin)
		check(d < 0.05, "поза после выхода совпала с позами входа (%.4f м)" % d)
		check(_gm.car.chassis.linear_velocity.distance_to(_entry_lin) < 0.5,
			"возврат не обнулил скорость машины (%.2f против %.2f)" %
			[_gm.car.chassis.linear_velocity.length(), _entry_lin.length()])
		check(_gm.car.body.dent_count == _entry_dents,
			"кузов вернулся в состояние входа (%d против %d)" % [_gm.car.body.dent_count, _entry_dents])
		check(absf(_gm.car.body.max_depth - _entry_depth) < 1e-3,
			"глубина вмятины та же, что до реплея (%.4f против %.4f)" %
			[_gm.car.body.max_depth, _entry_depth])
	if _gm_f == 250:
		_gm._set_paused(true)
		_gm.hud.pause_button("РЕПЛЕЙ УДАРА").pressed.emit()
	if _gm_f == 254:
		check(_gm.replay_player.active, "второй вход в реплей открылся")
		_gm._unhandled_input(_act("pause"))
	if _gm_f == 258:
		check(not _gm.replay_player.active, "Esc вышел из реплея в заезд")
		check(not _gm.is_frozen(), "после Esc мир размяк")
		_gm._set_paused(true)
		_gm.hud.pause_button("РЕПЛЕЙ УДАРА").pressed.emit()
	if _gm_f == 262:
		_gm._unhandled_input(_act("respawn"))
	if _gm_f == 266:
		check(not _gm.replay_player.active, "R во время реплея выходит из повтора")
		# окно началось заново: до респауна оно было полным (200 кадров), а после
		# рестарта не успело наполниться и до секунды
		check(_gm.replay.count() < int(ReplayRecorder.RATE),
			"рестарт обнулил окно: повтора через телепорт нет (%d кадров)" % _gm.replay.count())
		check(not _gm.is_frozen(), "после R заезд продолжается")
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
