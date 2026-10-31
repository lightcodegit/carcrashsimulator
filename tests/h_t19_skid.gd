extends Node3D
# Следы резины: полоса появляется только там, где колесо реально скользит.
# A) прямолинейный разгон — следов нет
# B) занос на ручнике — следы есть, лежат на земле, ширина и длина в пределах пятна
# C) отпустил ручник — сцепление вернулось, следы перестали расти
# D) респавн обрывает полосу: нет мазка через всю карту от места аварии до старта
# E) кольцо перезаписывает самые старые слоты и не растёт
# F) GameManager подключает SkidMarks к живой машине
const SLOTS_HALF := SkidMarks.SLOTS / 2

var _fails := 0
var car: CarRig
var skid: SkidMarks
var _phase := "A"
var _ticks := 0
var _marks_at_phase := 0
var _spawn := Vector3(-20, 1.0, 0)
var _marks_before_respawn := 0
var _marks_at_drift := 0
var _marks_settled := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _enter(phase: String) -> void:
	_phase = phase
	_ticks = 0
	_marks_at_phase = skid.marks_drawn()

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(2400, 2, 900); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body)
	floor_body.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, _spawn))
	skid = SkidMarks.new(); add_child(skid)
	skid.setup(car)
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_ticks += 1
	match _phase:
		"A":
			if _ticks == 90:
				check(skid.marks_drawn() == 0, "A: прямолинейный разгон без следов (%d)" % skid.marks_drawn())
				check(car.speed_kmh() > 30.0, "A: машина разогналась (%.1f км/ч)" % car.speed_kmh())
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_enter("B")
		"B":
			if _ticks == 60:
				check(skid.marks_drawn() - _marks_at_phase > 30,
					"B: занос на ручнике оставил след (%d сегментов)" % (skid.marks_drawn() - _marks_at_phase))
				_check_geometry()
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				_enter("C")
		"C":
			# занос гасится ESP не мгновенно: сначала даём сцеплению вернуться, и только
			# потом требуем, чтобы следы перестали расти вовсе
			if _ticks == 90:
				_marks_settled = skid.marks_drawn()
			if _ticks == 180:
				check(skid.marks_drawn() == _marks_settled,
					"C: после возврата сцепления следы не растут (%d за 1.5 с)" % (skid.marks_drawn() - _marks_settled))
				_marks_before_respawn = skid.marks_drawn()
				car.respawn(Transform3D(Basis.IDENTITY, Vector3(400, 1.0, 200)))
				skid.respawn()
				_enter("D")
		"D":
			if _ticks == 60:
				check(skid.marks_drawn() == _marks_before_respawn,
					"D: респавн не прочертил полосу через карту (%d → %d)" % [_marks_before_respawn, skid.marks_drawn()])
				check(car.speed_kmh() > 15.0, "D: после респавна машина снова в движении (%.1f км/ч)" % car.speed_kmh())
				_marks_at_drift = skid.marks_drawn()
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_enter("E")
		"E":
			if _ticks == 8:
				var drawn := skid.marks_drawn() - _marks_at_drift
				check(drawn > 0, "D: занос после респавна снова чертит (%d)" % drawn)
				var here := car.chassis.global_position
				for k in drawn:
					var t := skid.segment((_marks_at_drift + k) % SkidMarks.SLOTS)
					var flat := Vector2(t.origin.x - here.x, t.origin.z - here.z).length()
					check(flat < 10.0, "D: новый след у машины, а не у старой точки (%.1f м)" % flat)
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				Input.action_release("throttle")
				_enter("F")
		"F":
			if _ticks == 5:
				_check_ring()
				var live := skid.marks_live()
				check(live > 0, "F: до истечения срока полосы живые (%d)" % live)
				# 1 секунда игрового времени — и след обязан исчезнуть сам
				Settings.skid_life = 1.0
				_enter("G")
		"G":
			if _ticks == 120:
				check(skid.marks_live() == 0,
					"G: срок вышел — колец живых не осталось (%d)" % skid.marks_live())
				var seen := 0
				for i in SkidMarks.SLOTS:
					if skid.segment(i).basis.get_scale().length() > 0.001: seen += 1
				check(seen == 0, "G: исчезнувшие полосы правда скрыты, а не перезаписаны (%d)" % seen)
				# 0 = «не исчезают»: старое поведение кольца оставляем проверяемым
				Settings.skid_life = 0.0
				car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
				Input.action_press("throttle")
				_enter("H")
		"H":
			if _ticks == 150:
				Input.action_press("handbrake")
				Input.action_press("steer_left")
			if _ticks == 165:
				var drawn := skid.marks_live()
				check(drawn > 0, "H: без срока годности полосы рисуются (%d)" % drawn)
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				Input.action_release("throttle")
			if _ticks == 400:
				check(skid.marks_live() > 0,
					"H: со сроком 0 полосы не исчезают (%d живых через 4 с)" % skid.marks_live())
				Settings.skid_life = 30.0
				_check_manager()
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)

# Каждый сегмент — плоская полоса на уровне земли: выше она зависнет над полотном,
# ниже — провалится в асфальт и пропадёт.
func _check_geometry() -> void:
	var seen := 0
	var widest := 0.0
	var longest := 0.0
	var highest := 0.0
	var farthest := 0.0
	for i in SkidMarks.SLOTS:
		var t := skid.segment(i)
		var s := t.basis.get_scale()
		if s.length() < 0.001: continue
		seen += 1
		widest = maxf(widest, absf(s.x))
		longest = maxf(longest, absf(s.z))
		highest = maxf(highest, absf(t.origin.y))
		farthest = maxf(farthest, t.origin.distance_to(_spawn))
	check(seen > 30, "B: сегментов на земле (%d)" % seen)
	check(is_equal_approx(widest, SkidMarks.WIDTH), "B: ширина равна пятну контакта (%.3f)" % widest)
	check(longest >= SkidMarks.MIN_LEN and longest <= SkidMarks.MAX_LEN + SkidMarks.WIDTH + 1e-4,
		"B: длина сегмента в пределах (%.3f)" % longest)
	# высота покоя подвески равна радиусу колеса с погрешностью колебаний, поэтому допуск
	check(highest <= SkidMarks.LIFT + 0.05, "B: полоса лежит на земле (%.4f м)" % highest)
	check(farthest < 200.0, "B: следы рядом с траекторией (%.1f м)" % farthest)

# Кольцо фиксированного размера: synthetic-сегменты с шагом 1 м занимают все слоты,
# поэтому старые следы заноса обязаны исчезнуть, а число инстансов — не вырасти.
func _check_ring() -> void:
	var before := skid.marks_drawn()
	for k in SkidMarks.SLOTS + 7:
		skid._put(Vector3(float(k), 0.0, -100.0), Vector3.FORWARD, 0.1, 1.0)
	check(skid.marks_drawn() == before + SkidMarks.SLOTS + 7, "E: счётчик растёт за пределами кольца")
	check(skid.multimesh.instance_count == SkidMarks.SLOTS,
		"E: число инстансов фиксировано (%d)" % skid.multimesh.instance_count)
	var used := 0
	var fresh := 0
	for i in SkidMarks.SLOTS:
		var t := skid.segment(i)
		if t.basis.get_scale().length() < 0.001: continue
		used += 1
		if is_equal_approx(t.origin.z, -100.0) and t.origin.x > float(SLOTS_HALF): fresh += 1
	check(used == SkidMarks.SLOTS, "E: кольцо перезаписало все слоты (%d)" % used)
	check(fresh >= SLOTS_HALF, "E: самые старые следы вытеснены новыми (%d)" % fresh)

# Интеграция: GameManager сам создаёт SkidMarks, даёт ему машину и держит слоты пустыми.
func _check_manager() -> void:
	GameContext.select("sport", "arena")
	var gm: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	check(gm.skid != null, "F: GameManager создаёт SkidMarks")
	check(gm.skid.get_parent() == gm, "F: следы живут в мире игры")
	check(gm.skid.multimesh != null and gm.skid.multimesh.instance_count == SkidMarks.SLOTS, "F: кольцо выделено")
	check(gm.skid.multimesh.use_colors, "F: насыщенность следа задаётся цветом инстанса")
	check(gm.skid.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "F: следы не отбрасывают тень")
	check(gm.car.wheel_count() == 4, "F: у машины четыре колеса (%d)" % gm.car.wheel_count())
	var hidden := true
	for i in SkidMarks.SLOTS:
		if gm.skid.segment(i).basis.get_scale().length() >= 0.001:
			hidden = false
			break
	check(hidden, "F: до заноса все слоты пусты")
	check(gm.skid.marks_drawn() == 0, "F: на старте следов нет (%d)" % gm.skid.marks_drawn())
	gm.queue_free()
