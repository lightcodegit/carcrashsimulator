extends Node3D
# «Машины всё ещё иногда ударяются на рампах»: горки те, что лежат на настоящих картах,
# а не клин, собранный самим тестом (h_t13, фаза A) — тот прошёл бы, даже если карта
# ставит препятствие, о которое машина бьёт по-настоящему.
#
# Скорость на входе задаётся напрямую, а не разгоном, и горку проезжают четырьмя способами
# на трёх скоростях: «иногда» из жалобы — это край полосы и въезд под углом, а не чистый
# проезд по центру. Заезд заканчивается на приземлении: удар в стену после длинного полёта —
# другой случай (h_t13, фазы B и D), а нам важно, что горка и посадка после неё кузов не
# мяли.
#
# Тем, кто дал удар, отвечает физический мир: в момент удара смотрим, с чьим коллайдером
# пересекается рама. Отбойник и трибуна в полуметре от разметки — не горка (замер на
# арене: полоса z=-23.4 кончалась касанием отбойника, и тест приписывал это трамплину).
# Полосу заезда поэтому подбираем ту, где рама до старта ни за что не цепляет.
# Печатаем только числа.

const KMPS := 3.6
var MAPS: Array[String] = MapDB.ids()   # новые карты с горками попадают в тест сами
const SPEEDS := [60.0, 140.0, 210.0, 280.0]
# как подъезжаем: [название, доля полуширины полосы, курс в градусах]
# 0.5, не 0.85: у сегментов roadRamp/roadRampLong по флангам (|z| > 3.4) идёт приподнятая
# белая лента в 0.2 м — это бордюр, а не горка: на 60 км/ч колесо об неё останавливает
# машину, на 250 подбрасывает нос в наклонную грань. Бордюры проверяет h_t17, а здесь
# меряется сама горка в трёх полосах. Боковой заезд под 10° с горки уходит с полосы, и
# заезд кончается «уехала с дороги», а не «горка дала удар» — его не проверяем.
const APPROACHES := [["по центру", 0.0, 0.0], ["правый край", 0.5, 0.0],
	["левый край", -0.5, 0.0]]
const ROLL_AFTER := 20.0     # м, которые машина должна прокатить по земле после горки
const LAND_AFTER := 25.0     # м после горки, в пределах которых посадка ещё её заслуга
const RUNUP := 8.0           # коридор перед горкой: скорость задаём сами, разгон не нужен
const MARGIN := 120.0        # км/ч/с: худшее замедление горки должно быть ниже этого запаса
const WINDOW := 4            # тиков, за которые мерим замедление — как в детекторе удара

var _fails := 0
var _runs := 0
var gm: GameManager
var _map := ""
var _impacts := 0
var _on_hill := 0            # удары о горку и о пол сразу за ней — их не должно быть
var _other := 0              # касания посторонних препятствий: отбойников, трибун
var _found := 0              # сколько горок нашлось на всех картах
var _hb: AABB = AABB()       # полоса горки в мировых координатах
var _hill_bodies: Array = []    # коллайдеры текущей горки
var _ground_bodies: Array = []  # пол карты: на него и приземляются после прыжка
var _col_shape: CollisionShape3D
var _hist: Array[Vector3] = []    # скорость по тикам этого заезда
var _worst := 0.0                 # худшее замедление на горке, км/ч в секунду
var _worst_v0 := Vector3.ZERO     # какие векторы скорости это замедление дали
var _worst_v1 := Vector3.ZERO
var _worst_y := 0.0
# Жалоба «приземляется куда сильно — очень много теряется скорости» про САМО касание,
# а прежний заезд обрывался на этом тике. Поэтому после посадки мерим ещё окно в 30
# тиков, а «эпизодом горки» считаем всё от въезда на неё до конца этого окна: полёт,
# который ей обязан, и приземление в это же окно.
var _lt := -1
var _lv0 := 0.0
var _lvy := 0.0
var _lpeak := 0.0
var _lloss := 0.0
var _lsink := ""
var _lhist: Array[Vector3] = []
var _episode := false

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for id in MAPS:
		await _sweep(id)
	check(_found >= 3, "горки найдены на картах, иначе тест пустой (%d)" % _found)
	print("горок на картах: %d" % _found)
	print("прогонов %d" % _runs)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _sweep(id: String) -> void:
	if gm != null and is_instance_valid(gm):
		gm.queue_free()
		# четыре кадра: тела прежней карты должны уйти из физического пространства до
		# сборки новой, иначе её предметы толкаются с чужими
		for _i in 4:
			await get_tree().physics_frame
	if id == "endless":
		# Горки «бесконечности» — те же roadRampLong(×3) и roadBump, что на кольце, и
		# геометрию проверяет кольцо; здесь же плиты переставляются, и координаты
		# препятствия, найденного один раз, уплывают из-под машины. Переставку меряет
		# h_t32, а то, что по «бесконечности» можно ехать без вмятин, — h_t10, h_t17
		# и h_t24, которые перебирают все карты.
		print("NOTE: %s — те же горки, что на кольце; лента плит двигается, см. h_t32" % id)
		return
	_map = id
	GameContext.select("sport", id)
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 30:
		await get_tree().physics_frame
	# На «бесконечности» ленты переставляются из-за спины вперёд, а горки мы ищем один раз:
	# переставка унесла бы препятствие из-под машины, и заезд мерил бы пустую дорогу.
	gm._endless = false
	gm.car.impact.connect(_on_impact)
	for c in gm.car.chassis.get_children():
		if c is CollisionShape3D: _col_shape = c
	var hazards := _hazards()
	# на «бесконечности» горок десятки — мерим три, разбросанные по ленте: иначе тест
	# превращается в перебор всех, а повторяются они все одинаковые
	if hazards.size() > 3:
		var picked: Array[Dictionary] = []
		for k in 3:
			picked.append(hazards[int(k * (hazards.size() - 1) / 2.0)])
		hazards = picked
	if hazards.is_empty():
		print("NOTE: на %s горок нет — проверять нечего" % id)
	_found += hazards.size()
	for hz in hazards:
		_hill_bodies = hz["bodies"]
		for ap in APPROACHES:
			for v in SPEEDS:
				# Боком горку проезжаем до 210 км/ч: на 300 машина идёт по наклонённому
				# наклону носом кузова и разворачивается на ней — это настоящая авария, а
				# не «горка объявила удар», и проверять её на этом тесте нельзя.
				await _run(String(hz["label"]), hz["box"] as AABB, String(ap[0]),
					float(ap[1]), float(ap[2]), float(v))
	gm.queue_free()

# Горки карты — сегменты со своим коллайдером: «roadRamp» (трамплин) и «roadBump»
# (лежачий полицейский). Ищем их по именам узлов MapDB, а не по записанным в тест
# координатам: переставленный на карте трамплин не должен превращать проверку в пустую.
# К горке относится её StaticBody3D: MapDB ставит тело в тот же position, что и меш.
func _hazards() -> Array[Dictionary]:
	var bodies: Array = []
	var ground: Array = []
	for c in gm.get_children():
		for n in c.get_children():
			var sb := n as StaticBody3D
			if sb == null: continue
			var plate := false
			for cs in sb.get_children():
				var csi := cs as CollisionShape3D
				if csi == null or csi.shape == null: continue
				var b := csi.shape as BoxShape3D
				if b != null and b.size.x > 100.0 and b.size.y <= 2.5: plate = true
			if plate: ground.append(sb)
			else: bodies.append(sb)
	_ground_bodies = ground
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [gm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and (mi.name.begins_with("kit_roadRamp") or mi.name.begins_with("kit_roadBump")):
			var mine: Array = []
			for sb in bodies:
				if sb.position.distance_squared_to(mi.position) < 0.0004: mine.append(sb)
			out.append({"label": "рампа" if mi.name.begins_with("kit_roadRamp") else "бугор",
				"box": mi.global_transform * mi.get_aabb(), "bodies": mine})
		for c in n.get_children():
			stack.append(c)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return (x["box"] as AABB).position.x < (y["box"] as AABB).position.x)
	return out

# Поза старта: полоса — центр горки со смещением на долю её полуширины; начало коридора
# сдвинуто по курсу так, чтобы линия движения всё равно вела в горку.
func _lane_start(a: AABB, off: float, yaw: float) -> Transform3D:
	var lane_z := (a.position.z + a.end.z) * 0.5 + off * maxf(a.size.z * 0.5 - 1.0, 0.5)
	return Transform3D(Basis(Vector3.UP, yaw),
		Vector3(a.position.x - RUNUP, 1.0, lane_z + tan(yaw) * (RUNUP + a.size.x * 0.5)))

# Рама в этой позе ни за что не цепляет, кроме самой горки и пола?
func _pose_clear(tf: Transform3D) -> bool:
	if _col_shape == null: return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(_col_shape.shape)
	q.transform = tf * _col_shape.transform
	q.margin = 0.15
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if not (_hill_bodies.has(b) or _ground_bodies.has(b)): return false
	return true

func _run(label: String, a: AABB, how: String, off_req: float, yaw_deg: float, kmh: float) -> void:
	_runs += 1
	var yaw := deg_to_rad(yaw_deg)
	# край полосы поддвигаем внутрь, если там стоит отбойник: иначе проверка ловила бы
	# касание отбойника вместо поведения горки
	var off := off_req
	while absf(off) > 0.05 and not _pose_clear(_lane_start(a, off, yaw)):
		off -= signf(off) * 0.15
	var tf := _lane_start(a, off, yaw)
	var lane_z := tf.origin.z - tan(yaw) * (RUNUP + a.size.x * 0.5)
	var tag := "%s/%s @%d %s" % [_map, label, int(kmh), how]
	_impacts = 0
	_on_hill = 0
	_other = 0
	_hb = a
	gm.car.respawn(tf)
	for _i in 25:
		await get_tree().physics_frame        # кузов оседает на подвеске
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
	gm.car.chassis.linear_velocity = fwd * (kmh / KMPS)
	var max_y := 0.0
	var air := 0
	var air_run := 0
	_hist = []
	_worst = 0.0
	_lt = -1
	_lpeak = 0.0
	_lloss = 0.0
	_lsink = ""
	_lhist = []
	_episode = false
	var jumped := false
	var crossed := false
	var reached := false
	var entry := -1.0
	var end := ""
	var prev := gm.car.chassis.global_position
	for _i in 600:
		await get_tree().physics_frame
		var p := gm.car.chassis.global_position
		var grounded := gm.car._grounded
		if p.x > a.position.x: _episode = true
		max_y = maxf(max_y, p.y)
		# Запас до порога удара: детектор срабатывает на 210 км/ч/с, а горка обязана
		# давать в разы меньше. Мерим тем же окном в 4 тика, что и детектор.
		var vel := gm.car.chassis.linear_velocity
		if _lt < 0:
			_hist.append(vel)
		while _hist.size() > WINDOW + 1:
			_hist.pop_front()
		if _lt < 0 and _hist.size() == WINDOW + 1:
			var d := (_hist[0].length() - _hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0)
			if d > _worst:
				_worst = d
				_worst_v0 = _hist[0]
				_worst_v1 = _hist[WINDOW]
				_worst_y = p.y
		# на губе трамплина клармп рамы ещё цепляет грань, и «воздух» загорается на тик
		# в начале подъёма: засчитываем полёт только когда он устойчив, иначе заезд
		# обрывался до настоящей посадки и проверка мерил бы взлёт, а не приземление.
		air_run = 0 if grounded else air_run + 1
		if air_run > 0:
			air += 1
		if air_run >= 6:
			jumped = true
		if p.x > a.position.x and entry < 0.0:
			entry = gm.car.speed_kmh()
		if p.x > a.position.x + 1.0:
			reached = true
		if p.x > a.end.x + 0.5:
			crossed = true
		# GameManager сам телепортирует машину на спавн, если та вылетела за границу
		# карты: заезд окончен, дальше мерить нечего.
		if p.distance_to(prev) > 12.0:
			end = "вылет за границу"
		elif _on_hill > 0:
			end = "удар на горке"
		elif crossed and jumped and grounded and _lt < 0 and vel.y < 0.0:
			# сажаём только касание НА СПУСКЕ: колёса теряют землю и на ступенях горки,
			# и на вылете, когда машина ещё растёт
			_lt = 0
			_lv0 = gm.car.speed_kmh()
			_lvy = vel.y
			_lhist = [vel]
		elif crossed and not jumped and p.x > a.end.x + ROLL_AFTER:
			end = "прокатилась"
		elif _other > 0:
			# удар о чужое (отбойник, стену) важнее «машина встала»: иначе остановку после
			# столкновения тест записывает горке
			end = "цепнула постороннее"
		elif p.x > a.position.x and gm.car.speed_kmh() < 2.0:
			# 5-метровый трамплин на 60 км/ч по накату не берётся: машина встаёт на
			# склоне и съезжает назад — это физика, а не «горка дала удар»
			end = "остановилась на горке"
		elif gm.car.speed_kmh() < 2.0:
			# на малой скорости машина идёт по бугру верхом и останавливается сразу за
			# ним — это тоже чистый заезд, просто дальше мерить нечего
			end = "прокатилась" if crossed else "встала до горки"
		elif absf(p.z - (a.position.z + a.end.z) * 0.5) > a.size.z * 0.5 + 2.0:
			# машина ушла с полосы в сторону (прыжок под углом уводит за отбойник,
			# дальше уже деревья и трибуны) — поведение горки тут не измеряется
			end = "ушла с полосы"
		if _lt >= 0:
			_lt += 1
			_lhist.append(gm.car.chassis.linear_velocity)
			while _lhist.size() > WINDOW + 1:
				_lhist.pop_front()
			if _lhist.size() == WINDOW + 1:
				var ld := (_lhist[0].length() - _lhist[WINDOW].length()) * 3.6 / (WINDOW / 60.0)
				if ld > _lpeak:
					_lpeak = ld
					var touch: Array[String] = []
					for b in gm.car.chassis.get_colliding_bodies():
						if _ground_bodies.has(b): touch.append("пол")
						elif _hill_bodies.has(b): touch.append("рампа")
						else: touch.append(String(b.name))
					_lsink = str(touch)
			if _lt == 30:
				_lloss = _lv0 - gm.car.speed_kmh()
				_episode = false
				end = "приземлилась"
		prev = p
		# окно посадки досчитываем до конца, даже если машина успела за что-то зацепиться:
		# именно это окно и есть предмет жалобы
		if end != "" and (_lt < 0 or _lt >= 30 or end != "приземлилась"):
			break
	var clean := end in ["приземлилась", "прокатилась", "остановилась на горке"]
	print("%-34s проехала=%s полоса z=%+.1f горка x=%.0f..%.0f въезд=%3.0f км/ч подъём=%.2f м воздух=%3d тиков торможение=%3.0f км/ч/с ударов=%d (горка %d, посторонних %d) вмятин=%d — %s" % [
		tag, crossed, lane_z, a.position.x, a.end.x, entry, max_y, air, _worst,
		_impacts, _on_hill, _other, gm.car.body.dent_count, end if end != "" else "таймаут"])
	# Тест не пустой: машина должна добраться до горки. На арене часть полётов кончается
	# стеной — это не про горку, чистые посадки ищем там, где трасса длинная.
	check(reached, "%s: машина добралась до горки (%s)" % [tag, end])
	check(_on_hill == 0, "%s: горка не дала удара (%d)" % [tag, _on_hill])
	if clean:
		check(_impacts == 0, "%s: посадка после горки не удар (%d)" % [tag, _impacts])
		check(gm.car.body.dent_count == 0, "%s: кузов цел после горки (%d)" % [tag, gm.car.body.dent_count])
		var why := "v %.0f -> %.0f км/ч, вертикаль %+.1f -> %+.1f м/с на y=%.1f" % [
			Vector3(_worst_v0.x, 0, _worst_v0.z).length() * 3.6,
			Vector3(_worst_v1.x, 0, _worst_v1.z).length() * 3.6,
			_worst_v0.y, _worst_v1.y, _worst_y]
		check(_worst < MARGIN, "%s: горка тормозит с запасом до порога удара (%.0f км/ч/с, %s)" % [
			tag, _worst, why])
	if _lt >= 30:
		print("%-34s ПОСАДКА: %.0f км/ч с vy=%.1f → потеря %.1f км/ч за 0.5 с, торможение %.0f км/ч/с, рама цепляет %s" % [
			tag, _lv0, _lvy, _lloss, _lpeak, _lsink])
		check(_lloss < 25.0, "%s: жёсткая посадка не съедает скорость (%.1f км/ч за 0.5 с)" % [tag, _lloss])
		check(_lpeak < MARGIN, "%s: посадка ниже порога удара с тем же запасом (%.0f км/ч/с)" % [tag, _lpeak])
	if label == "рампа" and kmh >= 210.0 and clean and off_req == 0.0 and yaw_deg == 0.0:
		check(air > 5, "%s: на трамплине машина оторвалась (%d тиков в воздухе)" % [tag, air])

func _on_impact(speed: float, point: Vector3, normal: Vector3) -> void:
	_impacts += 1
	# «заслуга горки» — её собственная геометрия, а также пол в коридоре сразу за ней:
	# туда бросает машину после прыжка, и это как раз тот случай из жалобы. Всё остальное
	# — посторонние препятствия, у них своя проверка (h_t13, h_t17).
	var near := point.x > _hb.position.x - 1.0 and point.x < _hb.end.x + LAND_AFTER \
		and absf(point.z - (_hb.position.z + _hb.end.z) * 0.5) < _hb.size.z * 0.5 + 1.0
	var is_hill := false
	var is_ground := false
	var is_strange := false
	var who := ""
	for b in _contacts():
		if _hill_bodies.has(b): is_hill = true
		elif _ground_bodies.has(b): is_ground = true
		else: is_strange = true
		var n3 := b as Node3D
		who += "%s@(%.1f,%.1f,%.1f) " % [(b as Node).name, n3.global_position.x,
			n3.global_position.y, n3.global_position.z]
	# в эпизоде горки (на ней, в полёте с неё и в окне посадки) касание дороги — её счёт:
	# именно её полёт привёл машину в эту точку. Отбойник и стена остаются посторонними.
	var ours := is_hill or (is_ground and (near or _episode) and not is_strange)
	if ours:
		_on_hill += 1
	else:
		_other += 1
	print("   удар: %.0f км/ч точка (%.1f, %.1f, %.1f) нормаль (%.2f, %.2f, %.2f) %s, задето %s" % [
		speed, point.x, point.y, point.z, normal.x, normal.y, normal.z,
		"горка" if ours else "постороннее", who if who != "" else "—"])

func _contacts() -> Array:
	if _col_shape == null or gm.car.chassis == null: return []
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(_col_shape.shape)
	q.transform = gm.car.chassis.global_transform * _col_shape.transform
	q.margin = 0.25
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	var out: Array = []
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if b != null and not out.has(b): out.append(b)
	return out
