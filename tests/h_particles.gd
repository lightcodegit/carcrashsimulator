extends Node3D
# Частицы второго этапа: дым резины по колёсам, искры скребка о стену, пыль от
# сбитого предмета и честная вкл/выкл-настройка. Курсы два: голый харнес (условия
# включения считаются от CarRig напрямую) и живая сцена GameManager (настройка,
# пауза, рестарт и крючок предмета доходят туда, где их ожидает игрок).
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
	# сцена-хост может поставить паузу (gm._set_paused), а харнес обязан считать кадры дальше
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	# длинная стена: на первом этапе стоит в стороне (z=60), под этап скребка
	# переезжает на грань z=5.0 ровно напротив полосы
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
	# тот же крючок, что ставит GameManager; без него конус вёл бы себя как раньше
	_cone.on_hit_fx = fx.on_prop_hit
	check(fx.smoke_emitters().size() == car.wheel_count(),
		"дым на каждое колесо (%d против %d)" % [fx.smoke_emitters().size(), car.wheel_count()])
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
			# и след, и дым — величины накопленные: сравнивать их по одному кадру
			# бессмысленно (на 200-м занос уже мог кончиться), поэтому сверяем
			# условие по каждому каку окна и требуем совпадения везде
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
				check(false, "конус не был сбит за бюджет (%d всплесхов)" % fx.prop_puffs)
				_to_wall()
		"wall":
			# переключатель проверяем там, где что-то реально происходит: скребок
			# сыплет залпами каждые ~0.13 с, и «выключено» обязано остановить счётчик,
			# а не только погасить уже затухающий эммитер
			if _f == _wall_at + 150:
				_tog_off = fx.scrape_bursts
				fx.set_enabled(false)
			if _f == _wall_at + 270:
				var missed := fx.scrape_bursts - _tog_off
				check(missed <= 1,
					"выключенные частицы останавливают скребок (%d залпов за 2 с)" % missed)
				fx.set_enabled(true)
			if _f >= _wall_at + 420:
				_after_wall()
		"game":
			_game_stage()
		_:
			pass

# A) дым и след резины включаются одним и тем же условием по одним и тем же уровням
func _after_drift() -> void:
	var drawn := skid.marks_drawn() - _drawn_at_drift
	check(drawn > 10, "занос чертит следы (%d отметок)" % drawn)
	check(_drift_mismatch == 0,
		"дымят ровно те колёса, что чертят: расходимость %d кадров из %d" % [
			_drift_mismatch, _drift_frames])
	check(_drift_level > 0, "в окне заноса было колесо выше порога SkidMarks")
	check(_drift_smoke == _drift_level,
		"кадры с порогом %d, кадры с дымом %d" % [_drift_level, _drift_smoke])
	# B) выключенные частицы гасят ВСЕ эммитеры, включённые возвращают условие
	fx.set_enabled(false)
	await get_tree().physics_frame
	check(not _any_emitting(fx), "particles off: ни один эммитер не активен")
	fx.set_enabled(true)
	await get_tree().physics_frame
	check(_smoke_on_count() == _wheels_at_threshold(),
		"particles on: дым снова равен условию (%d против %d)" % [
			_smoke_on_count(), _wheels_at_threshold()])
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 10.0)))
	_cone.restore()
	_puff_at = -1
	_prop_at = _f
	_phase = "prop"

# C) сбитый предмет: пыль через callback; пролёт конуса ждём честно, 1.5 с
func _after_prop() -> void:
	if _phase != "prop": return
	check(fx.prop_puffs >= 1, "сбитый конус дал всплесх пыли (%d)" % fx.prop_puffs)
	var fly := _cone.global_position.distance_to(_cone_pos)
	check(fly > 2.0, "конус реально сбит и улетел (%.1f м)" % fly)
	check(fx._debris.emitting, "пылевой эммитер взведён ударом")
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

# D) скользящий контакт вдоль стены: искры залпами, но с троттлингом
func _after_wall() -> void:
	if _phase != "wall": return
	_phase = "reset"
	var bursts := fx.scrape_bursts - _bursts_at_wall
	check(bursts >= 2, "скольжение вдоль стены дало залпы искр (%d)" % bursts)
	# окно 420 кадров ≈ 7 с, порог залпа 0.13 с: без троттлинга было бы ~3200
	check(bursts <= 60, "залпы скребка троттлятся, а не сыплются каждый кадр (%d)" % bursts)
	check(fx.all_emitters().size() >= car.wheel_count() + 4,
		"полный набор эммитеров: искры, пыль, обломки, пламя, дым (%d)" % fx.all_emitters().size())
	Input.action_release("throttle")
	_reset_stage()

func _reset_stage() -> void:
	_phase = "game"
	fx.reset_transient()
	check(not fx._sparks.emitting, "reset_transient погасил текущие искры")
	Input.action_release("throttle")
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	GameContext.select("sedan", "town")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	_gm_f = 0
	_live_state = 0
	_live_f0 = 0

# Вехи живой сцены привязаны к первому видимому задымлению, а не к номеру кадра:
# на арене горки гасят занос раньше, чем наступает расписанный кадр проверки,
# плоский асфальт городка для этого и выбран (тот же вывод, что у h_padflow).
func _game_stage() -> void:
	_gm_f += 1
	if _gm_f == 40:
		var wired := 0
		for n in get_tree().get_nodes_in_group(LooseProp.GROUP):
			if not (n is LooseProp): continue
			if not (n as LooseProp).on_hit_fx.is_valid():
				check(false, "GameManager не повесил приёмник пыли на предмет %s" % n.name)
				return
			wired += 1
		check(wired > 0, "все %d предметов живой сцены имеют приёмник пыли" % wired)
		Input.action_press("throttle")
	if _gm_f == 150:
		_gm_marks_at = _gm.skid.marks_drawn()
		Input.action_press("handbrake")
		Input.action_press("steer_right")
	match _live_state:
		0:
			# ждём первое задымление в окне 150..340
			for p in _gm.effects.smoke_emitters():
				if p.emitting:
					_saw_live_smoke = true
					_live_f0 = _gm_f
					_live_state = 1
					break
			if _gm_f == 340:
				check(false, "в живой сцене дым так и не появился (следов +%d)" % [
					_gm.skid.marks_drawn() - _gm_marks_at])
				check(_gm.skid.marks_drawn() > _gm_marks_at,
					"в живой сцене хотя бы следы чертились")
				_live_state = 9
		1:
			if _gm_f == _live_f0 + 10:
				check(_gm.skid.marks_drawn() > _gm_marks_at,
					"в живой сцене занос чертит и дымит одновременно")
				_live_off_marks = _gm.skid.marks_drawn()
				Settings.set_value("particles_enabled", false)
				_live_state = 2
		2:
			if _gm_f == _live_f0 + 25:
				check(not _any_emitting(_gm.effects), "настройка «частицы» гасит живую сцену целиком")
				check(_gm.skid.marks_drawn() > _live_off_marks,
					"следы резины — не частицы: они продолжают чертить")
				Settings.set_value("particles_enabled", true)
				_live_state = 3
		3:
			if _gm_f == _live_f0 + 38:
				var any3 := false
				for p in _gm.effects.smoke_emitters():
					if p.emitting: any3 = true
				check(any3, "включённая настройка возвращает дым на живом заносе")
				_gm._set_paused(true)
				_live_state = 4
		4:
			if _gm_f == _live_f0 + 46:
				check(not _any_emitting(_gm.effects), "пауза гасит частицы")
				_gm._set_paused(false)
				_gm._respawn_now()
				_live_state = 5
		5:
			if _gm_f == _live_f0 + 54:
				check(not _any_emitting(_gm.effects),
					"рестарт погасил всё текущее (дым, искры, пламя, пыль)")
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
