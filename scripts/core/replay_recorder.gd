class_name ReplayRecorder
extends Node
# Кольцо кадров последних HORIZON_S секунд заезда. Пишется с частотой RATE из
# физического тика, поэтому в буфере ровно то, что посчитала физика: реплей
# позже проигрывает эти кадры БЕЗ пересимуляции (мир на паузе), и картинка
# обязана совпасть с оригиналом до последнего сбитого конуса.
#
# Что попадёт в кадр:
#   трансформ шасси + скорость, поза каждого колеса (ход, поворот, качение),
#   позы предметов вокруг машины, удары — отдельным списком событий, потому что
#   геометрия вмятины есть чистая функция от событий до данного момента.
#   Следы резины и частицы не пишутся: они и так рождаются из этих же кадров,
#   а на паузе их эмиттеры выключены.

const HORIZON_S := 10.0
const RATE := 20.0                       # снапшотов в секунду симуляции
const MAX_FRAMES := int(HORIZON_S * RATE)
const PROP_RADIUS := 45.0
# События ударов хранятся дольше окна: перемотка пересобирает кузов из полного
# списка, и лимит в 64 на длинной сессии стирал старые вмятины на время повтора.
const MAX_DENTS := 256
const NEAR_REFRESH_S := 0.5        # раз в полсекунды симуляции пересчитываем окрестность                # предметы вокруг машины, которые стоит писать

var car: CarRig
var gm: GameManager
var player: ReplayPlayer     # своё проигрывание recorder видит напрямую: на реплее писать нечего
var frames: Array = []
var dents: Array = []            # {t, lp: Vector3, ld: Vector3, kmh}
var sim_t := 0.0                 # время симуляции, а не часовой стены: слоу-мо внутри окна остаётся слоу-мо
var _acc := 0.0
var _props: Array[LooseProp] = []
var _prop_idx := {}              # LooseProp -> номер в плоском списке кадра
var _near := {}                  # номер предмета в окрестности машины (словарь: has() за O(1))
var _near_at := -1.0

func attach(p_car: CarRig, p_gm: GameManager) -> void:
	car = p_car
	gm = p_gm
	name = "ReplayRecorder"
	p_car.impact.connect(_on_impact)

func _physics_process(dt: float) -> void:
	if car == null or car.chassis == null: return
	if frozen(): return
	sim_t += dt
	_acc += dt
	if _acc < 1.0 / RATE: return
	_acc = minf(_acc - 1.0 / RATE, 1.0 / RATE)   # догон без лавины кадров после просадки
	_push(_sample())

# Пишется только живой мир: пауза, настройки и сам повтор замораживают запись.
# Признание берётся у GameManager, а проигрывание видно напрямую — иначе харнеси
# без сцены не могли бы проверить, что плеер и recorder не воюют.
func frozen() -> bool:
	if player != null and player.active: return true
	return gm != null and gm.is_frozen()

# Кадрирование окна: ring без копирования — просто выкидываем голову.
func _push(f: Dictionary) -> void:
	frames.append(f)
	while frames.size() > MAX_FRAMES: frames.pop_front()

func _sample() -> Dictionary:
	var xf := car.chassis.global_transform
	var b := xf.basis
	var wheels := PackedFloat32Array()
	wheels.resize(car.wheel_count() * 4)
	var levels := car.skid_levels()
	for i in car.wheel_count():
		# поза колеса берётся у CarRig: там уже лежат накопленное качение и ход
		# подвески в тех же единицах, что видит set_wheel_pose
		var w := car.wheel_pose(i)
		wheels[i * 4 + 0] = w.x
		wheels[i * 4 + 1] = w.y
		wheels[i * 4 + 2] = w.z
		wheels[i * 4 + 3] = levels[i] if i < levels.size() else 0.0
	return {
		"t": sim_t,
		"p": PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z]),
		"b": PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]),
		"kmh": car.speed_kmh(),
		"slip": car.slip,
		"nitro": car.nitro_fraction(),
		"hot": 1.0 if car.nitro_active else 0.0,
		"w": wheels,
		"pr": _prop_frame(),
	}

# Пишем только то, что имеет смысл: сбитые предметы и всё, что рядом с машиной.
# Плоский массив (номер, 9 базиса, 3 позиции) — чтобы на кадр была одна аллокация.
# «Рядом» пересчитывается раз в HALF_SECOND_S, а не на каждый сэмпл: на bigcity
# с 703 предметами полный обход стоил 0.37 мс на сэмпл (20 Гц), а окрестность
# машины меняется заметно медленнее.
func _prop_frame() -> PackedFloat32Array:
	_sync_props()
	var cp := car.chassis.global_position
	if sim_t - _near_at >= NEAR_REFRESH_S:
		_near_at = sim_t
		_near.clear()
		for i in _props.size():
			var p := _props[i]
			if is_instance_valid(p) and p.global_position.distance_squared_to(cp) <= PROP_RADIUS * PROP_RADIUS:
				_near[i] = true
	var out := PackedFloat32Array()
	for i in _props.size():
		var p := _props[i]
		if not is_instance_valid(p): continue
		if not p.disturbed and not _near.has(i): continue
		var t := p.global_transform
		var bb := t.basis
		var o := out.size()
		out.resize(o + 13)
		out[o] = float(i)
		out[o + 1] = bb.x.x; out[o + 2] = bb.x.y; out[o + 3] = bb.x.z
		out[o + 4] = bb.y.x; out[o + 5] = bb.y.y; out[o + 6] = bb.y.z
		out[o + 7] = bb.z.x; out[o + 8] = bb.z.y; out[o + 9] = bb.z.z
		out[o + 10] = t.origin.x; out[o + 11] = t.origin.y; out[o + 12] = t.origin.z
	return out

func _sync_props() -> void:
	var live := get_tree().get_nodes_in_group(LooseProp.GROUP)
	if live.size() == _props.size(): return
	_props.clear()
	_prop_idx.clear()
	_near.clear()
	_near_at = -1.0
	for n in live:
		if n is LooseProp:
			_prop_idx[_props.size()] = n
			_props.append(n as LooseProp)

func prop_by_index(i: int) -> LooseProp:
	return _prop_idx.get(i) as LooseProp

func _on_impact(speed_kmh: float, point: Vector3, normal: Vector3) -> void:
	if car.body == null: return
	# CarRig отдаёт normal КАК направление ушедшего импульса наружу (см. _detect_impact:
	# сигнал уходит с -n, а мнёт кузов по n), поэтому внутрь — это -normal.
	var f := car.body.dent_frame(point, -normal)
	dents.append({"t": sim_t, "lp": f[0], "ld": f[1], "kmh": speed_kmh,
		"point": point, "normal": normal})
	while dents.size() > MAX_DENTS: dents.pop_front()

# Момент последнего удара в окне или -1, если ударов не было.
func last_impact_t() -> float:
	return dents[dents.size() - 1].t if not dents.is_empty() else -1.0

func window_start() -> float: return frames[0].t if not frames.is_empty() else 0.0
func window_end() -> float: return frames[frames.size() - 1].t if not frames.is_empty() else 0.0
func count() -> int: return frames.size()

# Кадр, ближайший к моменту t (не следующий: у последнего кадра «следующего» нет).
# Индекс бинарным поиском — кольцо отсортировано по времени по построению.
func index_at(t: float) -> int:
	var lo := 0
	var hi := frames.size() - 1
	if hi < 0: return 0
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(frames[mid].t) <= t: lo = mid
		else: hi = mid - 1
	return lo

func frame_at(t: float) -> Dictionary:
	return frames[clampi(index_at(t), 0, maxi(frames.size() - 1, 0))]

func clear() -> void:
	frames.clear()
	dents.clear()
	_acc = 0.0

# Память кольца: кадр — ~30 float на машину плюс предметы. Считается честной,
# если в буфере хотя бы один кадр.
func bytes_used() -> int:
	var n := 0
	for f in frames:
		n += 32 + 4 * (f.p as PackedFloat32Array).size() + 4 * (f.b as PackedFloat32Array).size() \
			+ 4 * (f.w as PackedFloat32Array).size() + 4 * (f.pr as PackedFloat32Array).size()
	return n
