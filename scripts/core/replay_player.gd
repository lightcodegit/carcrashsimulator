class_name ReplayPlayer
extends Node
# Проигрывание кольца ReplayRecorder. Мир стоит (Physics paused), поэтому сюда
# приходят только читаемые кадры: ни одного шага симуляции плеер не делает и
# ничего не досчитывает — он перекладывает записанное.
#
# Возврат из реплея обязан быть точным: на входе сохраняется живое состояние
# (поза и скорости шасси, позы предметов, геометрия кузова), на выходе оно
# возвращается целиком. Иначе «посмотрел повтор» превращалось бы в перестановку
# мира или потерянную вмятину.

const RATES := [0.25, 0.5, 1.0, 2.0]
const STEP_S := 1.0 / ReplayRecorder.RATE     # один кадр кольца

signal started
signal stopped
signal cursor_changed(t: float, total: float)

var rec: ReplayRecorder
var car: CarRig
var gm: GameManager
var active := false
var playing := false
var rate_i := 0
var cursor := 0.0                 # секунды симуляции внутри окна
var _i := 0                       # индекс левого кадра пары
var _dents_applied := -1
var _stash_tf := Transform3D()
var _stash_lin := Vector3.ZERO
var _stash_ang := Vector3.ZERO
var _stash_dent := {}
var _stash_props := {}            # LooseProp -> Transform3D

func setup(p_rec: ReplayRecorder, p_car: CarRig, p_gm: GameManager) -> void:
	rec = p_rec
	car = p_car
	gm = p_gm
	name = "ReplayPlayer"

func rate() -> float: return RATES[clampi(rate_i, 0, RATES.size() - 1)]

func total_s() -> float:
	return maxf(0.0, rec.window_end() - rec.window_start())

# Лента замещена чужим набором вмятин: счётчик применённых событий остался от
# прежней ленты, и следующий шаг «вперёд» наложил бы новые события поверх
# геометрии старой. Присваиваем -1, как это делает begin_at на входе в реплей.
func invalidate_dents() -> void:
	_dents_applied = -1

# Точка входа по умолчанию: за секунду до последнего удара — ровно то, зачем
# реплей и нужен: увидеть, как именно машина влетела.
func begin_default() -> bool:
	var lt := rec.last_impact_t()
	if lt < 0.0: return begin_at(rec.window_start())
	return begin_at(lt - 1.0)

func begin_at(t: float) -> bool:
	if active or rec.count() == 0: return false
	_stash_tf = car.chassis.global_transform
	_stash_lin = car.chassis.linear_velocity
	_stash_ang = car.chassis.angular_velocity
	_stash_dent = car.body.stash()
	for f in rec.frames:
		var pr: PackedFloat32Array = f.pr
		for o in range(0, pr.size(), 13):
			var p := rec.prop_by_index(int(pr[o]))
			if p != null and is_instance_valid(p) and not _stash_props.has(p):
				_stash_props[p] = p.global_transform
	active = true
	playing = true
	car.replaying = true
	cursor = clampf(t, rec.window_start(), rec.window_end())
	_i = _find(cursor)
	_dents_applied = -1
	_apply(cursor)
	started.emit()
	return true

func end() -> void:
	if not active: return
	active = false
	playing = false
	car.replaying = false
	car.replay_speed = 0.0
	car.chassis.global_transform = _stash_tf
	car.chassis.linear_velocity = _stash_lin
	car.chassis.angular_velocity = _stash_ang
	car.chassis.reset_physics_interpolation()
	car.body.unstash(_stash_dent)
	for p in _stash_props:
		if is_instance_valid(p):
			p.global_transform = _stash_props[p]
			p.reset_physics_interpolation()
	_stash_props.clear()
	_dents_applied = -1
	stopped.emit()

func scrub(delta_frames: int) -> void:
	if not active: return
	seek(cursor + delta_frames * STEP_S)

# Точная мотка по времени: курсор, кадр для blend и остановка проигрывания —
# из одного места, иначе шаг и перемотка разошлись бы по разным правилам.
func seek(t: float) -> void:
	if not active: return
	cursor = clampf(t, rec.window_start(), rec.window_end())
	_i = _find(cursor)
	playing = false
	_apply(cursor)
	cursor_changed.emit(cursor, rec.window_end())

func set_rate_index(i: int) -> void:
	rate_i = clampi(i, 0, RATES.size() - 1)
	cursor_changed.emit(cursor, rec.window_end())

func bump_rate(dir: int) -> void:
	set_rate_index(rate_i + dir)

func toggle_play() -> void:
	if not active: return
	playing = not playing
	if playing and cursor >= rec.window_end() - 1e-3:
		cursor = rec.window_start()      # «повтор» после конца окна
		_i = _find(cursor)
	# Полная пересборка нужна только после перемотки в начало: там счётчик откатывается,
	# и обычная ветка «назад» сама построит кузов с нуля. Безусловный force на каждый
	# старт/паузу перестраивал меш зря (комментарий в _apply_dents: 64 вмятины = 284 мс).
	_apply_dents(cursor <= rec.window_start() + 1e-3)

func _process(dt: float) -> void:
	if not active or not playing: return
	cursor += dt * rate()
	var hi := rec.window_end()
	if cursor >= hi:
		cursor = hi
		playing = false
	_i = _find(cursor)
	_apply(cursor)
	cursor_changed.emit(cursor, hi)

func _find(t: float) -> int:
	return rec.index_at(t)

func _apply(t: float) -> void:
	if rec.count() == 0: return
	var a: Dictionary = rec.frames[_i]
	var b: Dictionary = rec.frames[mini(_i + 1, rec.count() - 1)]
	var span := float(b.t) - float(a.t)
	var w := 0.0 if span <= 1e-6 else clampf((t - float(a.t)) / span, 0.0, 1.0)
	car.replay_xf = _blend(a, b, w)
	# физику шасси тоже ставим: попадание в лучи, камера-орбита и всё, что читает
	# global_transform, видят ту же позу, что и рисовка
	car.chassis.global_transform = car.replay_xf
	car.replay_speed = lerpf(float(a.kmh), float(b.kmh), w)
	car.replay_nitro = lerpf(float(a.nitro), float(b.nitro), w)
	car.replay_hot = float(a.hot) > 0.5 if w < 0.5 else float(b.hot) > 0.5
	var wa: PackedFloat32Array = a.w
	var wb: PackedFloat32Array = b.w
	for i in car.wheel_count():
		var o := i * 4
		if o + 3 >= wa.size() or o + 3 >= wb.size(): break
		car.body.set_wheel_pose(i, lerpf(wa[o], wb[o], w), lerpf(wa[o + 1], wb[o + 1], w),
			wa[o + 2] + (wrapf(wb[o + 2] - wa[o + 2], -PI, PI) * w))
	_apply_props(a, b, w)
	_apply_dents(false)

func _blend(a: Dictionary, b: Dictionary, w: float) -> Transform3D:
	var pa: PackedFloat32Array = a.p
	var pb: PackedFloat32Array = b.p
	var ba: PackedFloat32Array = a.b
	var bb: PackedFloat32Array = b.b
	var org := Vector3(lerpf(pa[0], pb[0], w), lerpf(pa[1], pb[1], w), lerpf(pa[2], pb[2], w))
	var from := Basis(Vector3(ba[0], ba[1], ba[2]), Vector3(ba[3], ba[4], ba[5]), Vector3(ba[6], ba[7], ba[8]))
	var to := Basis(Vector3(bb[0], bb[1], bb[2]), Vector3(bb[3], bb[4], bb[5]), Vector3(bb[6], bb[7], bb[8]))
	# между кадрами кольцо даёт два разных рыскания на одном и том же кувырке:
	# обычное усреднение столбцов роняет ортонормальность, а Basis.slerp идёт по
	# кратчайшей дуге и остаётся жёстким базисом
	return Transform3D(from.slerp(to, w), org)

func _apply_props(a: Dictionary, b: Dictionary, w: float) -> void:
	var pb: PackedFloat32Array = b.pr
	var pa: PackedFloat32Array = a.pr
	for o in range(0, pb.size(), 13):
		var idx := int(pb[o])
		var p := rec.prop_by_index(idx)
		if p == null or not is_instance_valid(p): continue
		var to := Transform3D(Basis(_col(pb, o + 1), _col(pb, o + 4), _col(pb, o + 7)), _col(pb, o + 10))
		var s := _find_prop(pa, idx)
		if s >= 0 and w > 0.0:
			var from := Transform3D(Basis(_col(pa, s + 1), _col(pa, s + 4), _col(pa, s + 7)), _col(pa, s + 10))
			to = from.interpolate_with(to, w)
		p.global_transform = to
		p.reset_physics_interpolation()

func _find_prop(arr: PackedFloat32Array, idx: int) -> int:
	for o in range(0, arr.size(), 13):
		if int(arr[o]) == idx: return o
	return -1

func _col(arr: PackedFloat32Array, o: int) -> Vector3:
	if o + 2 >= arr.size(): return Vector3.ZERO
	return Vector3(arr[o], arr[o + 1], arr[o + 2])

# Кузов — функция от списка ударов: до курсора должно быть ровно столько вмятин,
# сколько случилось. Пересобираем только при смене числа событий, иначе скраб
# утыкается в перестройку меша каждый кадр.
func _apply_dents(force: bool) -> void:
	var want := 0
	for d in rec.dents:
		if float(d.t) <= cursor + 1e-6: want += 1
		else: break
	if not force and want == _dents_applied: return
	# Вперёд — только новые события: прежнее «reset + всё с нуля» на каждый шаг
	# стоило сумму всех предыдущих пересборок (64 вмятины = 284 мс на один
	# перескок). Назад пересборка остаётся: откатить вмятину по одной нельзя,
	# накопленное смещение вершин не обратимо без исходной геометрии.
	if want > _dents_applied and _dents_applied >= 0:
		for i in range(_dents_applied, want):
			var d: Dictionary = rec.dents[i]
			car.body.apply_impact_local(d.lp, d.ld, float(d.kmh))
		_dents_applied = want
		return
	_dents_applied = want
	car.body.reset()
	for i in want:
		var e: Dictionary = rec.dents[i]
		car.body.apply_impact_local(e.lp, e.ld, float(e.kmh))
