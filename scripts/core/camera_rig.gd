class_name CameraRig
extends Camera3D

var _car: CarRig
var _mode := 0
var _trauma := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.35
var _orbit_dist := 9.0
var _drag := false

func setup(car: CarRig) -> void:
	_car = car

func mode() -> int: return _mode
func cycle_mode() -> int:
	_mode = (_mode + 1) % 3
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
	if _car == null: return
	_trauma = maxf(0.0, _trauma - dt * 1.5)
	var t := _trauma * _trauma
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.4 * t
	var target := _car.chassis.global_position
	var look := target + Vector3(0, 0.6, 0)
	match _mode:
		0:
			var fwd := _car.chassis.global_transform.basis.x
			var want := target - fwd * 5.0 + Vector3(0, 1.9, 0)
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(target + Vector3(0, 1.2, 0), want)
			q.collide_with_bodies = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty(): want = hit.position + (want - hit.position).normalized() * 0.5
			var w := 1.0 - exp(-dt * 10.0)
			global_position = global_position.lerp(want, w) + shake
			_look_at(look)
		1:
			global_position = _car.chassis.global_transform * Vector3(0.2, _hood_y(), 0) + shake * 0.3
			_look_at(_car.chassis.global_transform * Vector3(10, 0.4, 0))
		2:
			var o := Vector3(cos(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), sin(_orbit_yaw) * cos(_orbit_pitch))
			global_position = target + o * _orbit_dist + shake
			_look_at(look)

func _hood_y() -> float:
	return _car.params.gc + _car.params.body_h + _car.params.roof_h * 0.55

func _look_at(p: Vector3) -> void:
	if (p - global_position).length_squared() < 1e-6: return
	look_at(p, Vector3.UP)
