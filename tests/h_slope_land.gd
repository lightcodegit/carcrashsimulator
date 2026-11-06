extends Node3D
# Жалоба: «когда машина при падении приземляется на трамплин или на его край, то скорость
# снижается». Прежние проверки (h_ramp_run, h_landing) мерили посадку на РОВНЫЙ пол и проезд горки
# колёсами, а этот случай — кузов падает на наклонную грань горки или на кромку её гребня.
# Замер до правки: приземление на склон 4.4° с 80 км/ч — 30 g, 1079 км/ч/с и минус 79 км/ч
# за 12 тиков: нос уходит под верхнюю грань гребня и упирается брюхом в торец горки.
#
# Горка — настоящий ассет дорог (roadRamp и roadRampLong, растянутые втрое, как на картах),
# а не клин из кода теста. Полосу берём по ЦЕНТРУ плиты: у roadRamp геометрия смещена от
# начала координат, и на z=0 машина стоит на краю плиты половиной колёс в воздухе — в
# таком прогоне лучи опоры поверхность не видят и проверка мерит пустоту.
#
# Машину держим на нужной ВЫСОТЕ НАД ГРАНЬЮ ( Position каждый тик), а потом отпускаем:
# иначе точка отрыва зависит от скорости и на 200 км/ч машина улетает за горку — проверка
# начинает мерить посадку за трамплином вместо приземления на него.

const KMPS := 3.6
const WINDOW := 4          # тиков, за которые мерим замедление — как в детекторе удара
const LAND_TICKS := 30     # 0.5 с после касания: окно, в котором потеря ещё заслуга посадки
const PEAK_MAX := 120.0    # км/ч/с: порог удара (210) с тем же запасом, что в h_ramp_run
const LOSS_MAX := 25.0     # км/ч за окно
const ADVANCE_MIN := 5.0   # м вперёд за окно: встала у горки — значит упёрлась в неё
const SINK_MIN := 1.0        # м: такой спуск прогон считает настоящим падением
const HEIGHTS := [3.0, 6.0]
const SPEEDS := [60.0, 110.0, 200.0]
const RAMPS := ["roadRamp", "roadRampLong"]
# На горку садятся не все прогоны: на 200 км/ч машина с гребня улетает за неё, и это
# нормальное поведение трамплина, а не ошибка. Поэтому пороги агрегатные — они же и
# доказательство, что проверка мерит приземление именно на горку, а не пустоту.
const ON_RAMP_MIN := 3
const HARD_MIN := 8

var car: CarRig
var _fails := 0
var _cases := 0
var _on_ramp := 0
var _hard := 0
var _worst_peak := 0.0
var _worst_loss := 0.0
var _impacts := 0

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
	car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)
	for name in RAMPS:
		# плита горки с тем же stretching, что на картах: ramp(..., 3.0) и roadRampLong ×3
		var m := MapKit.kit(self, name, Vector3(60, 0, 0), 90, true, true, Vector3(1.0, 1.0, 3.0))
		MapKit.kit(self, "roadStraight", Vector3(180, 0, 0), 90, false, true)
		# тело горки появляется в физическом мире только после синхронизации пространства
		for _i in 3:
			await get_tree().physics_frame
		await _sweep(name, m)
		for c in get_children():
			if c != fb and c != car: c.free()
	check(_cases >= HEIGHTS.size() * SPEEDS.size() * RAMPS.size() * 2,
		"тест не пустой: посадок измерено %d" % _cases)
	check(_on_ramp >= ON_RAMP_MIN,
		"машины садятся ИМЕННО на горку: %d посадок из %d" % [_on_ramp, _cases])
	check(_hard >= HARD_MIN,
		"это падения, а не съезды: %d спусков ≥ %.1f м из %d" % [_hard, SINK_MIN, _cases])
	print("посадок %d, на горке %d, со спуском ≥ %.1f м %d" % [_cases, _on_ramp, SINK_MIN, _hard])
	print("худшая посадка: пик %.0f км/ч/с, потеря за окно %.1f км/ч (пороги %.0f и %.1f)" % [
		_worst_peak, _worst_loss, PEAK_MAX, LOSS_MAX])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Перебор: середина склона и кромка гребня, две высоты, три скорости.
func _sweep(name: String, m: MeshInstance3D) -> void:
	var box: AABB = m.global_transform * m.get_aabb()
	var lane := (box.position.z + box.end.z) * 0.5
	var half: float = car._box_half.z
	for h in HEIGHTS:
		for v in SPEEDS:
			var mid := box.position.x + box.size.x * 0.55
			await _land(name, "склон", mid, float(h), float(v), lane, box)
			await _land(name, "кромка", box.end.x - half, float(h), float(v), lane, box)

# Высота наклонной грани горки в точке x: плита идёт от земли до гребня линейно.
func _rise(box: AABB, x: float) -> float:
	var t := clampf((x - box.position.x) / maxf(box.size.x, 0.001), 0.0, 1.0)
	return box.position.y + t * (box.end.y - box.position.y)

func _land(name: String, where: String, x: float, h: float, kmh: float,
		lane: float, box: AABB) -> void:
	var tag := "%s/%s %.1f м @%.0f" % [name, where, h, kmh]
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(20.0, 1.0, lane)))
	for _i in 25:
		await get_tree().physics_frame
	# Удержание считаем по ЦЕНТРУ кузова: у roadRamp верхняя грань в начале плиты лежит
	# на уровне земли, и «низ на h выше грани» означал бы падение в 10 см.
	for _i in 12:
		car.chassis.global_position = Vector3(x, _rise(box, x) + h, lane)
		car.chassis.linear_velocity = Vector3.ZERO
		car.chassis.angular_velocity = Vector3.ZERO
		car.chassis.reset_physics_interpolation()
		await get_tree().physics_frame
	var y0 := car.chassis.global_position.y
	car.chassis.linear_velocity = Vector3(kmh / KMPS, 0.0, 0.0)
	var air := 0
	var flew := false
	var touch := false
	var fticks := 0
	var lt := 0
	var x0 := x
	var v0 := 0.0
	var vy0 := 0.0
	var sink := 0.0
	var peak := 0.0
	var impacts0 := _impacts
	var hist: Array[Vector3] = []
	# фаза 1: полёт должен быть устойчивым (3 тика подряд без земли) — доказательство, что
	# машина именно падала, а не съезжала по склону
	for _i in 120:
		await get_tree().physics_frame
		air = 0 if car._grounded else air + 1
		if air >= 3:
			flew = true
			break
	# фаза 2: касание на движении вниз — на губе горки колёса теряют землю и на подъёме,
	# и на вылете, а жалоба про приземление
	for _i in 240:
		if not flew or touch: break
		await get_tree().physics_frame
		fticks += 1
		var v: Vector3 = car.chassis.linear_velocity
		if car._grounded and v.y < 0.0:
			touch = true
			v0 = car.speed_kmh()
			vy0 = v.y
			x0 = car.chassis.global_position.x
			sink = y0 - car.chassis.global_position.y
			impacts0 = _impacts
			hist = [v]
	if not flew:
		print("PARTIAL: %s: полёта не было — машина не оторвалась" % tag)
		return
	if not touch:
		print("PARTIAL: %s: посадки не было (воздух %d тиков, скорость %.0f км/ч)" % [
			tag, fticks, car.speed_kmh()])
		return
	# фаза 3: окно посадки
	for _i in LAND_TICKS + 8:
		if lt >= LAND_TICKS: break
		await get_tree().physics_frame
		var v2: Vector3 = car.chassis.linear_velocity
		lt += 1
		hist.append(v2)
		while hist.size() > WINDOW + 1: hist.pop_front()
		if hist.size() == WINDOW + 1:
			peak = maxf(peak, (hist[0].length() - hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0))
	var loss := v0 - car.speed_kmh()
	var after := car.chassis.global_position.x - x0
	var hit := _impacts - impacts0
	var on_ramp := x0 >= box.position.x and x0 <= box.end.x
	_cases += 1
	if on_ramp: _on_ramp += 1
	_worst_peak = maxf(_worst_peak, peak)
	_worst_loss = maxf(_worst_loss, loss)
	print("%-26s полёт %2d тик, спуск %.2f м, vy=%.1f, x=%.1f %s: потеря %5.1f км/ч, пик %4.0f км/ч/с (%.1f g), %5.1f м за окно, ударов %d" % [
		tag, fticks, sink, vy0, x0, "НА ГОРКЕ" if on_ramp else "за горкой", loss, peak,
		peak / 3.6 / 9.81, after, hit])
	if sink >= SINK_MIN: _hard += 1
	check(loss < LOSS_MAX, "%s: приземление на %s не съедает скорость (%.1f км/ч за 0.5 с)" % [
		tag, where, loss])
	check(peak < PEAK_MAX, "%s: приземление на %s ниже порога удара с запасом (%.0f км/ч/с)" % [
		tag, where, peak])
	check(hit == 0, "%s: приземление на %s не регистрирует удар (%d)" % [tag, where, hit])
	check(after > ADVANCE_MIN, "%s: машина уехала от %s, а не упёрлась в него (%.1f м)" % [
		tag, where, after])
