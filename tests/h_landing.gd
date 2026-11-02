extends Node3D
# Жалоба: «когда машина приземляется куда сильно, то у ней очень много теряется скорости».
# Причина найдена замером: хода подвески на жёсткую посадку не хватает, рама садится на
# коллайдер, и тормозит её дальше уже он, а не резина. Проверка падает, если гидроупор
# (BUMP_DAMP в CarRig) убрать: см. сравнение в README.
const KMPS := 3.6
const DROPS := [5.5, 8.0, 12.0]
const SPEEDS := [200.0, 280.0]
# пороги из замера С упором (ухудшение без него — в скобках):
const PEAK_MAX := 85.0     # км/ч в секунду (без упора 106)
const LOSS_MAX := 6.0      # км/ч за первые 5 тиков посадки (без упора 7.2)
const WINDOW := 4

var car: CarRig
var _fails := 0
var _cases := 0
var _worst_peak := 0.0
var _worst_loss := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fb := StaticBody3D.new()
	fb.name = "пол"
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 120); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(1100, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	for h in DROPS:
		for v in SPEEDS:
			await _drop(float(h), float(v))
	check(_cases >= DROPS.size() * SPEEDS.size(),
		"тест не пустой: посадок измерено %d" % _cases)
	print("худшая посадка: пик %.0f км/ч/с, потеря за 5 тиков %.2f км/ч (пороги %.0f и %.1f)" % [
		_worst_peak, _worst_loss, PEAK_MAX, LOSS_MAX])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _drop(h: float, kmh: float) -> void:
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(20.0, 1.0, 0)))
	for _i in 6:
		await get_tree().physics_frame
	# respawn сам ставит машину на высоту покоя, поэтому высоту падения задаём напрямую
	var p0 := car.chassis.global_position
	car.chassis.global_position = Vector3(p0.x, p0.y + h, p0.z)
	car.chassis.reset_physics_interpolation()
	car.chassis.linear_velocity = Vector3(kmh / KMPS, 0.0, 0.0)
	var air := false
	var lt := 0
	var v0 := 0.0
	var vy0 := 0.0
	var peak := 0.0
	var loss5 := 0.0
	var hist: Array[Vector3] = []
	for _i in 240:
		await get_tree().physics_frame
		var v: Vector3 = car.chassis.linear_velocity
		if not air:
			if not car._grounded: air = true
			continue
		if car._grounded:
			v0 = car.speed_kmh()
			vy0 = v.y
			hist = [v]
			lt = 0
			break
	if not air or v0 == 0.0:
		print("NOTE: падение %.1f м @%.0f: полёт или касание не пойманы" % [h, kmh])
		return
	for _i in 120:
		await get_tree().physics_frame
		lt += 1
		hist.append(car.chassis.linear_velocity)
		while hist.size() > WINDOW + 1: hist.pop_front()
		if hist.size() == WINDOW + 1:
			peak = maxf(peak, (hist[0].length() - hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0))
		if lt == 5: loss5 = v0 - car.speed_kmh()
	_cases += 1
	_worst_peak = maxf(_worst_peak, peak)
	_worst_loss = maxf(_worst_loss, loss5)
	print("падение %.1f м @%.0f км/ч: касание при vy=%.1f, пик %.0f км/ч/с (%.1f g), потеря за 5 тиков %.2f км/ч" % [
		h, kmh, vy0, peak, peak / 3.6 / 9.81, loss5])
	check(peak < PEAK_MAX, "посадка %.1f м @%.0f тормозит в пределах сцепления (%.0f км/ч/с)" % [h, kmh, peak])
	check(loss5 < LOSS_MAX, "посадка %.1f м @%.0f не съедает скорость за первые тики (%.2f км/ч)" % [h, kmh, loss5])
