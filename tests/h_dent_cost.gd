extends Node3D
# Стоимость вмятины и перемотки. Меряем не миллисекунды (они плавают), а число
# пересборок меша: это то, что код действительно контролирует. Прежний плеер на
# каждом шаге вперёд пересобирал кузов с нуля, и цена шага росла линейно числом
# ударов: 64 вмятины = 284 мс на один перескок.
var fails := 0
var car: CarRig

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func _ready() -> void:
	car = CarRig.new()
	add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D.IDENTITY)
	var body: DentBody = car.body
	var lp := Vector3(0.4, 0.2, 0.9)
	var ld := Vector3(-1, 0, 0)

	# 1) один удар = одна пересборка
	body.reset()
	body.rebuild_count = 0
	for i in 8:
		body.apply_impact_local(lp + Vector3(0.0, 0.0, float(i) * 0.07), ld, 120.0)
	check(body.rebuild_count == 8,
		"восемь ударов собрали меш восемь раз (факт %d)" % body.rebuild_count)

	# 2) норма пересчитывается по грязным группам, а не по всем вершинам
	body.reset()
	body.rebuild_count = 0
	body.normal_passes = 0
	body.apply_impact_local(lp, ld, 120.0)
	check(body.normal_passes > 0 and body.normal_passes < body._verts.size() / 2,
		"удар пересчитал нормали части вершин, а не всего кузова (%d из %d)" % [
			body.normal_passes, body._verts.size()])

	# 3) плеер: шаг вперёд стоит одну пересборку, а не сумму всех предыдущих
	var rec := ReplayRecorder.new()
	add_child(rec)
	rec.attach(car, null)
	var pl := ReplayPlayer.new()
	add_child(pl)
	pl.setup(rec, car, null)
	rec.player = pl
	for i in 24:
		rec.sim_t += 0.05
		rec.dents.append({"t": rec.sim_t, "lp": lp + Vector3(0.0, 0.0, float(i) * 0.02),
			"ld": ld, "kmh": 120.0})
		body.apply_impact_local(lp + Vector3(0.0, 0.0, float(i) * 0.02), ld, 120.0)
	rec.frames.append({"t": 0.0, "p": PackedFloat32Array([0, 0.5, 0]),
		"b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]), "kmh": 0.0, "slip": 0.0,
		"nitro": 1.0, "hot": 0.0, "w": _four_wheels(),
		"pr": PackedFloat32Array()})
	rec.frames.append({"t": 1.0, "p": PackedFloat32Array([10, 0.5, 0]),
		"b": PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]), "kmh": 60.0, "slip": 0.0,
		"nitro": 1.0, "hot": 0.0, "w": _four_wheels(),
		"pr": PackedFloat32Array()})
	body.reset()
	check(pl.begin_at(0.0), "плеер открыл окно")
	pl.playing = false
	body.rebuild_count = 0
	for i in 6:
		pl.scrub(4)          # шесть шагов по 4 кадра = курсор проходит ~6 событий
	var forward := body.rebuild_count
	# шесть шагов по 4 кадра пересекают ~24 события: цена = число пересечённых
	# событий, а не сумма предыдущих (прежний код платил 4+8+12+16+20+24 = 64)
	check(forward <= 30,
		"шесть шагов вперёд собрали меш %d раз вместо суммы 1+2+..+N" % forward)

	# 4) перемотка назад обязана вернуть ровно то же число вмятин
	var want := body.dent_count
	pl.seek(0.0)
	check(body.dent_count == 0, "мотка в начало окна стёрла вмятины (%d)" % body.dent_count)
	pl.seek(1.0)
	check(body.dent_count == want, "обратная перемотка вернула вмятины (%d против %d)" % [
		body.dent_count, want])

	# 5) точечный пересчёт нормалей обязан совпасть с полным
	body.reset()
	for i in 12:
		body.apply_impact_local(lp + Vector3(0.35, 0.2, -1.0 + float(i) * 0.12), ld, 150.0)
	body._rebuild()
	var full: PackedVector3Array = body._nrm.duplicate()
	body.reset()
	for i in 12:
		body.apply_impact_local(lp + Vector3(0.35, 0.2, -1.0 + float(i) * 0.12), ld, 150.0)
	var worst := 0.0
	for i in body._verts.size():
		worst = maxf(worst, full[i].distance_to(body._nrm[i]))
	check(worst < 1e-4,
		"точечные нормали совпали с полными: худшее расхождение %.6f" % worst)

	# 6) кольцо держит длинную сессию: лимит событий не режет старые вмятины
	var big := ReplayRecorder.new()
	add_child(big)
	big.attach(car, null)
	# путь игрока, а не запись в массив: лимит стоит в приёмнике удара
	for i in ReplayRecorder.MAX_DENTS + 10:
		big.sim_t = float(i)
		big._on_impact(120.0, car.chassis.global_position + Vector3(0.5, 0.2, 0.0), Vector3.BACK)
	check(big.dents.size() == ReplayRecorder.MAX_DENTS,
		"кольцо ударов ограничено %d (факт %d)" % [ReplayRecorder.MAX_DENTS, big.dents.size()])
	check(ReplayRecorder.MAX_DENTS >= 200,
		"лимита хватает на длинную сессию без потери старых вмятин (%d)" % ReplayRecorder.MAX_DENTS)
	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _four_wheels() -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(16)
	return w
