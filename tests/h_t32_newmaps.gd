extends Node3D
# Новые карты. «ГОНКА» — замкнутое кольцо: оно обязана сходиться (иначе между плитами
# дыра или ступенька, на 200 км/ч это удар), и под каждой точкой оси полосы должен быть
# асфальт. «БЕСКОНЕЧНОСТЬ» — переставка плит: меш и его коллайдер уезжают парой, иначе
# горка остаётся висеть невидимым коллайдером посреди дороги.

var _fails := 0
var _space: PhysicsDirectSpaceState3D

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await _circuit()
	await _endless()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _circuit() -> void:
	var m: Dictionary = MapDB.build("circuit")
	add_child(m.root)
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	var info: Dictionary = m.info
	var line: Array = info.line
	check(line.size() > 20, "кольцо построено: %d точек оси" % line.size())
	check(float(info.closure) < 0.05,
		"кольцо замыкается: концы не совпали на %.2f м" % float(info.closure))
	var where: Array[String] = []
	var gaps := 0
	var steps := 0
	var prev := 0.0
	var seen := 0
	for i in line.size():
		var a: Vector3 = line[i]
		var b: Vector3 = line[(i + 1) % line.size()]
		var span := a.distance_to(b)
		# шаг 1 м: свой уклон у горки (5.2 м на 60 м) даёт 0.09 м на метр, а ступенька на
		# стыке плит была бы больше 0.2 — при шаге в 4 м уклон и ступенька неразличимы
		for k in int(maxf(1.0, span)) + 1:
			var p := a.lerp(b, float(k) / maxf(span, 0.001))
			var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 4.0, p.z), Vector3(p.x, -6.0, p.z)))
			if hit.is_empty():
				gaps += 1
				continue
			var y := float(hit.position.y)
			# только ПОДЪЁМ: обрыв сверху горки — это и есть трамплин (машина летит),
			# а ступенька вверх на стыке плит — то, о что бьют колесом
			if seen > 0 and y - prev > 0.20:
				steps += 1
				where.append("%.0f/%.0f: %.2f -> %.2f" % [p.x, p.z, prev, y])
			prev = y
			seen += 1
	check(gaps == 0, "под осью полосы нет дыр (%d лучей мимо)" % gaps)
	check(steps == 0, "на стыке плит нет подъёма выше 20 см (%s)" % str(where))
	m.root.queue_free()
	await get_tree().physics_frame

func _endless() -> void:
	var m: Dictionary = MapDB.build("endless")
	add_child(m.root)
	await get_tree().physics_frame
	var root: Node3D = m.root
	# горка с коллайдером: меш и тело при ней
	var plate: MeshInstance3D = null
	var body: StaticBody3D = null
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not String(mi.name).contains("roadRamp"): continue
		plate = mi
		for b in root.get_children():
			var sb := b as StaticBody3D
			if sb != null and sb.position.distance_squared_to(mi.position) < 0.0004: body = sb
		break
	check(plate != null and body != null, "на «бесконечности» есть горка с коллайдером")
	var x0 := plate.position.x
	var b0 := body.position.x
	var n0 := _plates(root)
	var moved: int = MapDB.recycle(root, x0 + 400.0, 20.0)
	check(moved > 0, "переставка сдвинула плиты (%d из %d)" % [moved, n0])
	check(plate.position.x > x0, "плита уехала вперёд (%.0f -> %.0f)" % [x0, plate.position.x])
	check(body.position.x - b0 == plate.position.x - x0,
		"её коллайдер уехал на те же %.0f м, что и меш (%.0f -> %.0f)" % [
			plate.position.x - x0, b0, body.position.x])
	check(_plates(root) == n0, "число плит не изменилось (%d -> %d)" % [n0, _plates(root)])
	root.queue_free()
	await get_tree().physics_frame

func _plates(root: Node3D) -> int:
	var n := 0
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_road"): n += 1
	return n
