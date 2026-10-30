class_name CameraRig
extends Camera3D

const SHAKE_DECAY := 1.5
const FOLLOW_RATE := 9.0
const TELEPORT_M := 8.0

var _car: CarRig
var _mode := 0
var _trauma := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.35
var _orbit_dist := 9.0
var _drag := false
var _pos := Vector3.ZERO           # чистая позиция без шейка: инакше шейк накапливается и тянет камеру
var _prev_target := Vector3.ZERO
var _have_pos := false

func setup(car: CarRig) -> void:
	_car = car
	_have_pos = false

func mode() -> int: return _mode

func cycle_mode() -> int:
	_mode = (_mode + 1) % 3
	_have_pos = false
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
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35 * t
	var target := _car.chassis.global_position
	var look := target + Vector3(0, 0.6, 0)
	match _mode:
		0:
			var fwd := _car.chassis.global_transform.basis.x
			var speed := _car.chassis.linear_velocity.length()
			var back := 5.0 + minf(speed, 60.0) * 0.045     # на скорости отъезжаем дальше
			var up := 1.9 + minf(speed, 60.0) * 0.010
			var want := target - fwd * back + Vector3(0, up, 0)
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(target + Vector3(0, 1.2, 0), want)
			q.collide_with_bodies = true
			q.exclude = [_car.chassis.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty(): want = hit.position + (want - hit.position).normalized() * 0.4
			if not _have_pos:
				_pos = want
				_prev_target = target
				_have_pos = true
			else:
				var delta := target - _prev_target
				if delta.length() > TELEPORT_M:   # респавн/телепорт — без плавного доезда
					_pos = want
				else:
					# наследуем движение машины целиком, сглаживаем только отклонение:
					# чистый lerp позиции давал отставание на несколько метров на скорости
					_pos += delta
					_pos = _pos.lerp(want, 1.0 - exp(-dt * FOLLOW_RATE))
				_prev_target = target
			global_position = _pos + shake
			_look_at(look)
		1:
			var hp: Vector3 = _car.body.hood_point(0.30, 0.14)
			global_position = _car.chassis.global_transform * hp + shake * 0.3
			_look_at(_car.chassis.global_transform * (hp + Vector3(12.0, -0.45, 0.0)))
		2:
			var o := Vector3(cos(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), sin(_orbit_yaw) * cos(_orbit_pitch))
			global_position = target + o * _orbit_dist + shake
			_look_at(look)

func _look_at(p: Vector3) -> void:
	if (p - global_position).length_squared() < 1e-6: return
	look_at(p, Vector3.UP)
