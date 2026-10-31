extends Node3D
# Нитро. Первое, что тут проверяется: форсаж — свойство МОДЕЛИ машины, а не строчка в
# пресете. Параметры стоят в VehicleParams с дефолтами, поэтому тест смотрит и на чистый
# VehicleParams.new(), и на каждую машину из списка — новый кузов обязан получить нитро
# сам, иначе «сделай нитро ко всем новым машинам» придётся помнить руками.
# Дальше — что форсаж разгоняет, жрёт бак, на пустом баке не помогает, копится обратно и
# не расходуется без газа.

var _fails := 0
var car: CarRig
var _emits := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	car.nitro_changed.connect(func(_a: bool) -> void: _emits += 1)
	_check_all_cars()
	await _check_boost_over_vmax()
	await _check_boost_off_the_line()
	await _check_drain_and_refill()
	await _check_no_throttle()
	_check_inputs()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _check_all_cars() -> void:
	var fresh := VehicleParams.new()
	check(fresh.nitro_capacity > 0.0 and fresh.nitro_accel > 0.0 and fresh.nitro_vmax > 1.0,
		"свежий VehicleParams уже с форсажом (бак %.0f, тяга %.1f, потолок ×%.2f)" % [
			fresh.nitro_capacity, fresh.nitro_accel, fresh.nitro_vmax])
	for id in VehicleDB.ids():
		var p := VehicleDB.get_params(id)
		check(p != null and p.nitro_capacity > 0.0, "%s: нитро есть" % id)
		check(p != null and p.nitro_accel > 0.0 and p.nitro_vmax > 1.0, "%s: форсаж даёт тягу и потолок" % id)

func _launch(kmh: float, with_nitro: bool) -> void:
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for _i in 20:
		await get_tree().physics_frame
	car.chassis.linear_velocity = Vector3(kmh / 3.6, 0.0, 0.0)
	Input.action_press("throttle")
	if with_nitro: Input.action_press("nitro")

func _release() -> void:
	Input.action_release("throttle")
	Input.action_release("nitro")

func _settle_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

# На паспортном потолке тяга по кривой равна нулю, поэтому именно там нитро и обязано
# быть видно: без него машина стоит на vmax, с ним — едет дальше.
func _check_boost_over_vmax() -> void:
	var vmax: float = car.params.vmax_kmh
	await _launch(vmax * 0.95, false)
	await _settle_frames(240)
	var plain := car.speed_kmh()
	await _launch(vmax * 0.95, true)
	await _settle_frames(240)
	var boost := car.speed_kmh()
	_release()
	print("потолок %.0f км/ч: без нитро %.0f, с нитро %.0f (%.2f×)" % [vmax, plain, boost,
		boost / maxf(vmax, 1.0)])
	check(plain < vmax * 1.06,
		"без форсажа машина не переползает паспорт (%.0f при %.0f)" % [plain, vmax])
	check(boost > vmax * 1.15,
		"форсаж поднимает потолок минимум на 15%% (%.0f при %.0f)" % [boost, vmax])

# Разгон с места: сравнение пройденного — то, что игрок чувствует как «рвано вперёд».
func _check_boost_off_the_line() -> void:
	await _launch(0.0, false)
	await _settle_frames(180)
	var plain := car.speed_kmh()
	await _launch(0.0, true)
	await _settle_frames(180)
	var boost := car.speed_kmh()
	_release()
	print("с места за 3 с: без нитро %.0f км/ч, с нитро %.0f км/ч (+%.0f%%)" % [
		plain, boost, 100.0 * (boost / maxf(plain, 1.0) - 1.0)])
	check(boost > plain * 1.25,
		"форсаж добавляет минимум четверть скорости за 3 с (%.0f против %.0f)" % [boost, plain])

func _check_drain_and_refill() -> void:
	_emits = 0
	await _launch(120.0, true)
	var start := car.nitro_fraction()
	var low_before := 1.0
	var spent := 0.0
	for _k in 6:
		await _settle_frames(30)
		low_before = car.nitro_fraction()
		spent += 0.5
	check(start > 0.99, "полный бак на старте заезда (%.2f)" % start)
	check(low_before < 0.35, "бак убывает на глазах за %.1f с (%.2f)" % [spent, low_before])
	for _k in 12:
		await _settle_frames(15)
	check(car.nitro_fraction() < 0.02, "бак пустеет полностью (%.2f)" % car.nitro_fraction())
	check(not car.nitro_active, "на пустом баке форсаж не горит")
	check(_emits >= 2, "форсаж объявляет начало и конец (%d сигналов)" % _emits)
	# и копится обратно: без кнопки нитро бак наполняется вчетверо медленнее, чем тратится
	Input.action_release("nitro")
	await _settle_frames(60)
	var back := car.nitro_fraction()
	check(back > 0.10, "бак копится сам (%.2f за 1 с)" % back)
	Input.action_press("nitro")
	await _settle_frames(2)
	check(car.nitro_active, "попробовав снова, игрок опять получает форсаж")
	Input.action_release("nitro")
	await _settle_frames(40)
	_release()

func _check_no_throttle() -> void:
	await _settle_frames(40)
	var before := car.nitro_fraction()
	Input.action_press("nitro")
	await _settle_frames(60)
	var after := car.nitro_fraction()
	Input.action_release("nitro")
	# накатом форсаж не жжётся (бак при этом спокойно копится — убывать он не должен)
	check(after >= before - 0.001, "без газа бак не тратится (%.2f -> %.2f)" % [before, after])
	check(not car.nitro_active, "без газа форсаж не горит")

func _check_inputs() -> void:
	check(InputRouter.DEFAULTS.has("nitro"), "действие nitro есть в раскладке")
	var d: Dictionary = InputRouter.DEFAULTS.get("nitro", {})
	check((d.get("keys", []) as Array).size() > 0, "нитро назначено на клавишу")
	check((d.get("joy", []) as Array).size() > 0, "нитро назначено на кнопку геймпада")
	check(InputMap.has_action("nitro"), "нитро зарегистрировано в InputMap")
	var kb := 0
	var pad := 0
	for e in InputMap.action_get_events("nitro"):
		if e is InputEventKey: kb += 1
		elif e is InputEventJoypadButton or e is InputEventJoypadMotion: pad += 1
	check(kb > 0 and pad > 0, "в InputMap нитро живёт и на клавиатуре, и на геймпаде (%d/%d)" % [kb, pad])
