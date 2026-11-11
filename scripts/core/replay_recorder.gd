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
	if frames.is_empty(): return {}
	return frames[clampi(index_at(t), 0, frames.size() - 1)]

func clear() -> void:
	frames.clear()
	dents.clear()
	_acc = 0.0

# ---- сохранение и загрузка ленты на диск ------------------------------------
# Лента самодостаточна: id карты и машины нужны, чтобы повтор принимался только
# той же картой (предметы в кадре — индексы в её же раскладке), а машина — чтобы
# отображение скорости и нитро совпадало с записью.

static func replay_path(map_id: String) -> String:
	return "user://replays/last_%s.replay" % map_id

static func has_tape(map_id: String) -> bool:
	return FileAccess.file_exists(replay_path(map_id))

static func tape_at(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	# A size cap, like settings.cfg and the garage have: get_var reads the whole
	# file, and a gigabyte one would eat memory before any structure check.
	if f.get_length() > MAX_TAPE_BYTES: return {}
	var v: Variant = f.get_var()
	# get_var без allow_objects не создаёт произвольные объекты, но файл — это
	# всё ещё структура из сети недоверенных дисков: мусорные размеры падали бы
	# позже, в _blend. Проверяем и размер, и каждый кадр.
	if not (v is Dictionary) or int(v.get("version", 0)) != 1: return {}
	if not (v.get("frames", []) is Array) or not (v.get("dents", []) is Array): return {}
	if (v["frames"] as Array).size() > MAX_SAVED_FRAMES: return {}
	if not _frames_valid(v["frames"]): return {}
	if not _dents_valid(v["dents"]): return {}
	return v

# Лента валидна, если каждый кадр несёт правильные размеры массивов: транспорт
# дальше читает a.p/b/w напрямую, и короткий массив — script error посреди реплея.
# Numbers must be finite: NaN passes an "is float" check and then breaks the
# index_at binary search (comparisons with NaN are always false) and spreads
# INF across poses.
static func _frames_valid(list: Array) -> bool:
	for f in list:
		if not (f is Dictionary): return false
		if not f.has("t") or not f.has("kmh") or not f.has("slip") or not f.has("nitro") or not f.has("hot"): return false
		if not (f.get("p", []) is PackedFloat32Array) or (f["p"] as PackedFloat32Array).size() != 3: return false
		if not (f.get("b", []) is PackedFloat32Array) or (f["b"] as PackedFloat32Array).size() != 9: return false
		if not (f.get("w", []) is PackedFloat32Array) or (f["w"] as PackedFloat32Array).size() % 4 != 0: return false
		if not (f.get("pr", []) is PackedFloat32Array) or (f["pr"] as PackedFloat32Array).size() % 13 != 0: return false
		# Finiteness comes after types and sizes: no access to a foreign key
		if not _finite_all(f["p"]) or not _finite_all(f["b"]) or not _finite_all(f["w"]) or not _finite_all(f["pr"]): return false
		if not (f["hot"] is float) or not (f["nitro"] is float) or not (f["kmh"] is float) or not (f["t"] is float): return false
		if not (is_finite(float(f["hot"])) and is_finite(float(f["nitro"]))
				and is_finite(float(f["kmh"])) and is_finite(float(f["t"]))): return false
	return true

static func _finite_all(arr: Variant) -> bool:
	if not (arr is PackedFloat32Array): return false
	for v in (arr as PackedFloat32Array):
		if not is_finite(v): return false
	return true

# Dents hit harder than frames: apply_impact_local expects Vector3 in typed
# parameters, and a foreign type (a string from a hand edit) is a script error
# mid-replay. Type, size and finiteness are checked here, once at the input.
static func _dents_valid(list: Array) -> bool:
	if list.size() > MAX_DENTS: return false
	for d in list:
		if not (d is Dictionary) or not d.has("t") or not d.has("lp") or not d.has("ld") or not d.has("kmh"): return false
		if not ((d["lp"] is Vector3) and (d["ld"] is Vector3)): return false
		if not ((d["t"] is float) and (d["kmh"] is float)): return false
		if not (is_finite(float(d["t"])) and is_finite(float(d["kmh"]))): return false
		var lp: Vector3 = d["lp"]
		var ld: Vector3 = d["ld"]
		if not (lp.is_finite() and ld.is_finite()): return false
	return true

# Потолок сохранённой ленты: вдвое больше игрового окна (20 Гц × 10 с). Куски
# больше — либо мусор, либо попытка выесть память загрузкой гигабайт массивов.
const MAX_SAVED_FRAMES := 400
# File size cap: an honest tape is a few megabytes (the flat prop list in a
# frame is the worst case); the cap is seven times larger for headroom.
const MAX_TAPE_BYTES := 16 * 1024 * 1024

func save_to(path: String) -> bool:
	if frames.is_empty(): return false
	var d := DirAccess.open("user://")
	if d != null and not d.dir_exists("replays") and d.make_dir("replays") != OK: return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_var({
		"version": 1, "car": GameContext.car_id, "map": GameContext.map_id,
		"frames": frames, "dents": dents, "sim_t": sim_t,
	})
	var ok := f.get_error() == OK
	f.close()   # не дожидаясь сборщика: файл мог понадобиться сразу после записи
	return ok

# Принимает сохранённую ленту В ЖИВОЙ рекордер той же карты: окно и вмятины
# замещаются, счётчики откатываются. Плеер после этого обязан перемотаться на
# начало — _apply_dents пересоберёт кузов с нуля.
func adopt_tape(tape: Dictionary) -> bool:
	if int(tape.get("version", 0)) != 1: return false
	if tape.get("map", "") != GameContext.map_id: return false
	if not (tape.get("frames", []) is Array) or (tape["frames"] as Array).is_empty(): return false
	if (tape["frames"] as Array).size() > MAX_SAVED_FRAMES: return false
	if not _frames_valid(tape["frames"]): return false
	if not (tape.get("dents", []) is Array): return false
	if not _dents_valid(tape["dents"]): return false
	var sim: Variant = tape.get("sim_t", 0.0)
	if not (sim is float) or not is_finite(float(sim)): return false
	frames = (tape["frames"] as Array).duplicate()
	dents = (tape.get("dents", []) as Array).duplicate()
	sim_t = float(tape.get("sim_t", 0.0))
	_acc = 0.0
	# sim_t откатан к началу ленты, а _near_at остался от живого заезда: шлюз
	# обновления окрестности (sim_t - _near_at >= NEAR_REFRESH_S) закрылся бы, и
	# первые кадры после «ПРОШЛЫЙ» писали бы старый набор предметов вокруг машины.
	# Сбрасываем кэш, как это делает _sync_props.
	_near.clear()
	_near_at = -1.0
	return true

# Память кольца: кадр — ~30 float на машину плюс предметы. Считается честной,
# если в буфере хотя бы один кадр.
func bytes_used() -> int:
	var n := 0
	for f in frames:
		n += 32 + 4 * (f.p as PackedFloat32Array).size() + 4 * (f.b as PackedFloat32Array).size() \
			+ 4 * (f.w as PackedFloat32Array).size() + 4 * (f.pr as PackedFloat32Array).size()
	return n
