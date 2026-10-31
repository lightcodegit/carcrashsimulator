extends Node3D
# Краш-сценарий: седан разгоняется в бетонную стену. Проверяет регистрацию удара,
# остановку, появление и сохранение вмятин, непроходимость стены и стоимость удара.
var _fails := 0
var _frame := 0
var car: CarRig
var _impacts: Array[float] = []
var _impact_ms := 0.0
var _def_at_crash := 0.0
const WALL_X := 60.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 30); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(WALL_X, 4, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	car.impact.connect(func(s: float, _p: Vector3, _n: Vector3) -> void: _impacts.append(s))

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame == 750:
		Input.action_release("throttle")
		var b := car.body
		check(_impacts.size() > 0, "удар зарегистрирован (%s)" % str(_impacts))
		check(_impacts.size() > 0 and _impacts[0] > 40.0 and _impacts[0] < 170.0,
			"скорость удара правдоподобна (%s)" % str(_impacts))
		check(car.speed_kmh() < 8.0, "машина остановилась (%.1f км/ч)" % car.speed_kmh())
		check(car.chassis.global_position.x < WALL_X, "рама не вошла в стену (%.2f)" % car.chassis.global_position.x)
		check(b.dent_count > 0, "вмятины появились (%d)" % b.dent_count)
		_def_at_crash = b.deformation()
		check(_def_at_crash > 0.5, "кузов деформирован заметно (%.2f м)" % _def_at_crash)
		check(b.max_depth > 0.05 and b.max_depth < b.height * 0.45,
			"глубина вмятины в пределах кузова (%.3f м при высоте %.2f)" % [b.max_depth, b.height])
		var thru := 0; var below := 0; var bad := 0
		for i in b.vertex_count():
			var w := b.vertex_world(i)
			if not w.is_finite(): bad += 1
			if w.x > WALL_X + 0.6: thru += 1
			if w.y < -0.05: below += 1
		check(bad == 0, "все вершины конечны (%d)" % bad)
		check(thru == 0, "кузов не прошёл сквозь стену (%d)" % thru)
		check(below == 0, "кузов не ушёл под пол (%d)" % below)
		pass
	if _frame == 1250:
		var b := car.body
		check(absf(b.deformation() - _def_at_crash) < 1e-6,
			"вмятины не заживают (%.4f -> %.4f)" % [_def_at_crash, b.deformation()])
		check(car.speed_kmh() < 4.0, "машина стоит (%.1f км/ч)" % car.speed_kmh())
		# Стоимостью удара считаем пересборку меша кузова. Мерить её межфрейдовым таймером
		# нельзя: на фоновой нагрузке вылетало ложно (61–83 мс на «максимальном кадре» при
		# реальной пересборке в единицы миллисекунд). Берём медиану трёх ударов и в самом
		# конце — чтобы лишняя вмятина не мешала проверке «вмятины не заживают».
		var costs: Array[float] = []
		for i in 3:
			var t0 := Time.get_ticks_usec()
			b.apply_impact(car.chassis.global_position + Vector3(0, 0.25, 0.6 + i * 0.35), Vector3(0, 0, 1), 120.0)
			costs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		costs.sort()
		_impact_ms = costs[1]
		check(_impact_ms < 40.0, "пересборка кузова после удара (%.2f мс, все %s)" % [_impact_ms, str(costs)])
		print("CRASH impacts=%s dents=%d depth=%.3f м deform=%.2f м удар=%.2f мс" % [
			str(_impacts), b.dent_count, b.max_depth, b.deformation(), _impact_ms])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
