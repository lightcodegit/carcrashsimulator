extends Node3D
# Жалоба: «машина рандомно на каких-то объектах резко снижает скорость». Резкое торможение
# само по себе не ошибка — ошибка, когда оно случается БЕЗ столкновения: едешь по своей
# полосе, ни во что не вписываешься, а скорость пропадает. Поэтому проверка едет по живым
# картам ровно и на каждом скачке торможения спрашивает у физического мира, кто в этом
# виноват: чужое тело (стена, отбойник, сбитый бачок) — это авария, её меряют h_crash и h_handling;
# воздух (прыжок и посадка) — это h_landing и h_slope_land; а если машина на всех колёсах на дороге
# и ни за что не держится, торможение выше порога — тот самый баг.
#
# Мерим ГОРИЗОНТАЛЬНУЮ потерю: посадка после прыжка меняет |v| за счёт вертикали, и по
# полному вектору прыжок не отличить от удара о невидимую стену. Продольная скорость — то,
# что игрок читает как «машина потеряла скорость».

const KMPS := 3.6
const WINDOW := 4            # тиков, за которые мерим замедление — как в детекторе удара
const THRESH := 60.0         # км/ч/с (~1.7 g): горизонтальное торможение без столкновения
const TICKS := 1200          # на карте: 20 с хода, чтобы успеть и трамплины, и бугры
const SPEED := 200.0         # км/ч на входе: разгон держим газом, торможение — только дорога

var _fails := 0
var _events := 0
var _explained := 0
var _ticks := 0
var _maps := 0
var _seen: Dictionary = {}
var gm: GameManager
var _map := ""
var _ground: Array = []
var _hist: Array[Vector3] = []

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for id in MapDB.ids():
		await _sweep(id)
	check(_ticks >= 4000, "тест не пустой: проехано %d тиков" % _ticks)
	# Покрытие по картам считается по фактическим тикам, а не по числу итераций
	# цикла: счётчик, растущий один раз на id из того же списка, ничего не проверяет.
	for id in MapDB.ids():
		var t := int(_seen.get(id, 0))
		# Замер по картам: arena/speedway/circuit/endless дают полные 1200 тиков,
		# bigcity 1065, town 301 — там машина уходит за границы полигона и скуп
		# обрывается. Порог 120 (2 с наблюдения) оставляет от этого запаса двойной
		# запас и всё ещё ловит карту, которая не проехалась вовсе.
		check(t >= 120, "карта %s проехана с замерами (%d тиков)" % [id, t])
	print("тикачей %d, скачков ≥ %.0f км/ч/с: %d, из них объяснённых: %d" % [
		_ticks, THRESH, _events, _explained])
	print("тики по картам: %s" % str(_seen))
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _sweep(id: String) -> void:
	if gm != null and is_instance_valid(gm):
		gm.queue_free()
		for _i in 4:
			await get_tree().physics_frame
	_map = id
	_maps += 1
	GameContext.select("sport", id)
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 30:
		await get_tree().physics_frame
	gm._endless = false        # лента «бесконечности» переставляется, координаты уплывают
	_ground = _ground_bodies()
	gm.car.respawn(gm._spawn)
	for _i in 25:
		await get_tree().physics_frame
	gm.car.chassis.linear_velocity = _forward() * (SPEED / KMPS)
	Input.action_press("throttle")
	var prev := gm.car.chassis.global_position
	_hist = []
	for _i in TICKS:
		await get_tree().physics_frame
		_ticks += 1
		_seen[_map] = int(_seen.get(_map, 0)) + 1
		var p := gm.car.chassis.global_position
		# GameManager телепортирует машину на спавн, если та вылетела за границу: заезд
		# окончен, дальше мерить нечего
		if p.distance_to(prev) > 12.0: break
		prev = p
		var v: Vector3 = gm.car.chassis.linear_velocity
		# торможение считаем по горизонтали: вертикаль при посадке меняется, а «скорость
		# машины» для игрока — это продольный ход
		var flat := Vector3(v.x, 0.0, v.z)
		_hist.append(flat)
		while _hist.size() > WINDOW + 1: _hist.pop_front()
		if _hist.size() < WINDOW + 1: continue
		var d := (_hist[0].length() - _hist[WINDOW].length()) * KMPS / (WINDOW / 60.0)
		if d < THRESH: continue
		_events += 1
		var air := 0
		for w in gm.car._wheels:
			if not w.is_in_contact(): air += 1
		var crash := _foreign()
		if air > 0 or crash != "":
			_explained += 1
			continue
		var why := ("%s x=%.0f z=%.0f: горизонтальное торможение %.0f км/ч/с (%.1f g) при %.0f км/ч "
			+ "на всех колёсах, рама ни за что не держится — дорога сама съедает скорость") % [
				_map, p.x, p.z, d, d / 3.6 / 9.81, gm.car.speed_kmh()]
		check(false, why)
	Input.action_release("throttle")
	gm.queue_free()

# Рама касается тела, которое не является дорожной плитой? Это и есть столкновение.
# get_colliding_bodies() для этого не годится: список контактов VehicleBody3D даёт не всё
# (замер: торможение 7 g у торцовой стены speedway с пустым списком), поэтому спрашиваем
# физический мир прямым запросом формы вокруг рамы.
func _foreign() -> String:
	var col := _col_shape()
	if col == null: return ""
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(col.shape)
	q.transform = gm.car.chassis.global_transform * col.transform
	# 0.6 м, а не контакт в ноль: сбитый отбойник улетает из-под рамы за тот же тик, и
	# проверка, которая смотрит только текущее пересечение, остаётся без виноватого
	# (замер speedway x=576: минус 4.6 м/с за тик — это разгон пяти отбойников по 25 кг,
	# а не дорога; к следующему тику они уже вне рамы).
	q.margin = 0.6
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	var out := ""
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if b == null or _ground.has(b): continue
		out += String((b as Node).name) + " "
	return out.trim_suffix(" ")

func _col_shape() -> CollisionShape3D:
	for c in gm.car.chassis.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape != null: return cs
	return null

# Плиты пола: длинные плоские коробки — у MapDB каждая плита со своим телом. Горки и
# бугры ставят свои trimesh-тела; их считаем препятствиями, на них тормозить можно (h_ramp_run).
func _ground_bodies() -> Array:
	var out: Array = []
	for c in gm.get_children():
		for n in c.get_children():
			var sb := n as StaticBody3D
			if sb == null: continue
			for cs in sb.get_children():
				var csi := cs as CollisionShape3D
				if csi == null or csi.shape == null: continue
				var b := csi.shape as BoxShape3D
				if b != null and maxf(b.size.x, b.size.z) > 40.0 and b.size.y <= 2.5:
					out.append(sb)
	return out

# Курс машины, а не ось X её рамки: VehicleBody3D смотрит носом в +Z (YAW_OFFSET в CarRig),
# и если задать скорость по X, машина едет боком, шины скребут асфальт, и тест ловит
# торможение, которого игрок не видит (замер: 68 «необъяснённых» скачков на 5831 тике).
func _forward() -> Vector3:
	return gm.car._flat_forward()
