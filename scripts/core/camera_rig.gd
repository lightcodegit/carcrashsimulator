class_name CameraRig
extends Camera3D

const SHAKE_DECAY := 1.5
const SWAY_RATE := 6.0           # 1/с: как быстро направление погони догоняет курс машины
const STANDOFF := 0.45         # насколько отойти от заслонившей поверхности
const MIN_FROM := 1.8          # и не вплотную к машине, если места хватает
const GUARD_STEPS := 4         # сколько раз переснять луч, обходя мелкие тела

var _car: CarRig
var _mode := 0
var _trauma := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.35
var _orbit_dist := 9.0
var _drag := false
var _fwd := Vector3.ZERO           # сглаженный курс машины: единственное, что погоня помнит
var _fwd_seen := false
var _shake := 1.0              # множитель тряски: 0 — камера неподвижна даже в краше

func setup(car: CarRig) -> void:
	_car = car
	_fwd_seen = false
	# Плавностью заведует _process, и покадровая интерполяция физики нам только мешает:
	# движок предупреждает «Interpolated Camera3D triggered from outside physics process»,
	# потому что мы ставим трансформ вне физического тика.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	apply_settings()

# Отдельно от _ready: настройка тряски меняется на глазах, в том числе из меню паузы.
func apply_settings() -> void:
	_shake = Settings.shake
	if Settings.fov > 0.0:
		fov = Settings.fov

func mode() -> int: return _mode

func cycle_mode() -> int:
	_mode = (_mode + 1) % 3
	_fwd_seen = false
	return _mode

func add_trauma(t: float) -> void:
	_trauma = clampf(_trauma + t, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if _mode != 2: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: _orbit_dist = clampf(_orbit_dist - 1.0, 3.0, 25.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _orbit_dist = clampf(_orbit_dist + 1.0, 3.0, 25.0)
	elif event is InputEventMouseMotion and _drag:
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.005, -0.3, 1.2)

func _process(dt: float) -> void:
	if _car == null or _car.chassis == null: return
	_trauma = maxf(0.0, _trauma - dt * SHAKE_DECAY)
	var t := _trauma * _trauma
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35 * t * _shake
	# рисуемое положение машины, не тиковое — см. CarRig.render_transform()
	var gt := _car.render_transform()
	var target: Vector3 = gt.origin
	var look := target + Vector3(0, 0.6, 0)
	match _mode:
		0:
			# Погоня стоит на фиксированной дистанции за СГЛАЖЕННЫМ курсом машины:
			# `target − курс·back + up` — чистая функция от рисуемого положения, своей
			# прошлой позиции у неё нет. Прежний lerp позиции на 150 км/ч недобирал метр
			# дистанции и гулял по полуметру каждый кадр: «камера отстаёт, отходит и
			# возвращается, мелькает». Сглаживается только направление — это ровно то, за
			# что погоню ценят: в повороте камера доворачивает следом, а не телепортируется.
			var fwd_raw: Vector3 = gt.basis.z
			fwd_raw.y = 0.0
			if fwd_raw.length_squared() < 1e-6:
				fwd_raw = Vector3(0.0, 0.0, 1.0)
			else:
				fwd_raw = fwd_raw.normalized()
			if not _fwd_seen:
				_fwd = fwd_raw
				_fwd_seen = true
			else:
				var mix := _fwd.lerp(fwd_raw, 1.0 - exp(-dt * SWAY_RATE))
				# Разворот на 180° при весе около 0.5 (медленный кадр) даёт нулевой
				# вектор: normalized() из нуля — ZERO, и на один кадр камера складывается
				# в машину, а потом резко возвращается.
				_fwd = mix.normalized() if mix.length_squared() > 1e-6 else fwd_raw
			var speed := _car.speed_kmh() / 3.6   # скорость — величина физическая, она не джиттерит; на реплее её отдаёт плеер
			var back := 5.0 + minf(speed, 60.0) * 0.045     # на скорости отъезжаем дальше
			var up := 1.9 + minf(speed, 60.0) * 0.010
			# к цели сквозь стены идти нельзя: луч из машины в точку погони и там, и там
			# считается по одному курсу, поэтому ограничение нигде не «тянет» камеру назад
			global_position = _pull(target, target - _fwd * back + Vector3(0, up, 0)) + shake
			_look_at(look)
		1:
			var hp: Vector3 = _car.body.hood_point(0.30, 0.14)
			var eye: Vector3 = gt * hp
			global_position = eye + shake * 0.3
			_look_at(eye + _car.forward() * 12.0 + Vector3(0, -0.45, 0))
		2:
			var o := Vector3(cos(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), sin(_orbit_yaw) * cos(_orbit_pitch))
			# орбита раньше не проверяла ничего: камеру можно было увести за стену и
			# смотреть на машину сквозь бетон
			global_position = _pull(target, target + o * _orbit_dist) + shake
			_look_at(look)

# Куда встанет камера, если между ней и машиной есть твёрдая geometry. Камера обязана
# остаться с МАШИНОЙ по одну сторону заслона: прежний вариант сдвигал её от точки
# попадания в сторону желаемой позиции, то есть ЗА стену, — именно поэтому погоня
# всё равно проходила сквозь бетон. Заслоном считаются только StaticBody3D — здания,
# стены, плиты: сбиваемые конусы и покрышки (RigidBody3D) не должны прятать машину,
# иначе камера липнет к мелочи на дороге.
func _pull(from: Vector3, want: Vector3) -> Vector3:
	var to := want - from
	var span := to.length()
	if span < 1e-4: return want
	var dir := to / span
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [_car.chassis.get_rid()]
	for i in GUARD_STEPS:
		var q := PhysicsRayQueryParameters3D.create(from, want)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty(): return want
		if not (hit.collider is StaticBody3D):
			excl.append(hit.rid)
			continue
		var allowed := from.distance_to(hit.position)
		var keep := maxf(allowed - STANDOFF, 0.0)
		var t := minf(keep, span)
		t = maxf(t, minf(MIN_FROM, keep))
		return from + dir * minf(t, span)
	return want

func _look_at(p: Vector3) -> void:
	if (p - global_position).length_squared() < 1e-6: return
	look_at(p, Vector3.UP)
