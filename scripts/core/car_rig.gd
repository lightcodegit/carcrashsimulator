class_name CarRig
extends Node3D

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

var params: VehicleParams
var chassis: RigidBody3D
var body: DentBody
var heading := 0.0
var _world: World3D
var _prev_speed := 0.0
var _recent_speed := 0.0
var _travel := Vector3.ZERO            # куда машина летела до удара: solver обнуляет velocity
var _impact_cooldown := 0
var _grounded := true
var _roll := 0.0

class ChassisBody extends RigidBody3D:
	var rig: CarRig

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		rig._chassis_physics(state)

func build(p: VehicleParams, world: World3D) -> void:
	params = p
	_world = world
	var ch := ChassisBody.new()
	ch.rig = self
	ch.mass = p.mass
	ch.custom_integrator = true
	ch.contact_monitor = true
	ch.max_contacts_reported = 8
	ch.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0; pm.bounce = 0.0
	ch.physics_material_override = pm
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = p.collider_size()
	col.shape = shape
	ch.add_child(col)
	add_child(ch)
	chassis = ch
	chassis.body_entered.connect(_on_body_entered)
	body = DentBody.new()
	chassis.add_child(body)
	body.setup(p.model, p)
	# кузов в DentBody стоит колёсами на локальном нуле: опускаем на низ коллайдера
	body.position = Vector3(0, -p.collider_size().y * 0.5, 0)

func _on_body_entered(_other: Node) -> void:
	# скорость в момент события уже обнулена solver'ом — берём свежий пик
	if _recent_speed < 28.0 or _impact_cooldown > 0: return
	var d := _travel if _travel.length_squared() > 0.25 else Vector3(cos(heading), 0.0, -sin(heading))
	var point := chassis.global_position + d * (params.length * 0.5) + Vector3(0, 0.1, 0)
	impact.emit(_recent_speed, point, -d)
	body.apply_impact(point, d, _recent_speed)   # d — внутрь кузова: поверхность мнётся по ходу движения
	_impact_cooldown = 60

func respawn(tf: Transform3D) -> void:
	heading = tf.basis.get_euler().y
	var rest_y := params.collider_size().y * 0.5 + 0.02
	chassis.global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(tf.origin.x, rest_y, tf.origin.z))
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	_recent_speed = 0.0
	_prev_speed = 0.0
	_travel = Vector3.ZERO
	_impact_cooldown = 0
	_roll = 0.0
	if body != null: body.reset()

func speed_kmh() -> float:
	return chassis.linear_velocity.length() * 3.6

func forward_speed_ms() -> float:
	return chassis.linear_velocity.dot(Vector3(cos(heading), 0.0, -sin(heading)))

func is_airborne() -> bool:
	return not _grounded

func _chassis_physics(state: PhysicsDirectBodyState3D) -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var vel := state.linear_velocity
	vel += Vector3(0, -9.8, 0) * dt            # custom_integrator отключает штатную гравитацию
	var contacts := state.get_contact_count()
	_grounded = contacts > 0
	if _grounded:
		var fwd := Vector3(cos(heading), 0.0, -sin(heading))
		var right := Vector3(sin(heading), 0.0, cos(heading))
		var vf := vel.dot(fwd)
		var vl := vel.dot(right)
		var vmax := params.vmax_kmh / 3.6
		var throttle := Input.get_action_strength("throttle") - Input.get_action_strength("brake")
		if throttle > 0.0:
			vf += params.accel_max * (1.0 - 0.75 * clampf(vf / vmax, 0.0, 1.0)) * throttle * dt
		elif throttle < 0.0:
			if vf > 0.5: vf = maxf(vf - params.brake_decel * dt, 0.0)
			else: vf += params.accel_max * 0.35 * throttle * dt
		if absf(throttle) < 0.01: vf *= exp(-dt * 0.8)   # накат/движущее торможение
		vf = clampf(vf, -vmax * 0.12, vmax)
		var hand := Input.is_action_pressed("handbrake")
		vl *= exp(-dt * (1.6 if hand else params.grip))
		var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")  # + = налево
		var sf := clampf(1.25 - absf(vf) / vmax * 1.05, 0.22, 1.0)
		var speed_gate := clampf(absf(vf) / 2.0, 0.0, 1.0)
		heading += deg_to_rad(params.steer_rate_deg) * steer * sf * dt * speed_gate * (1.0 if vf >= 0.0 else -1.0)
		vel = fwd * vf + right * vl + Vector3(0.0, vel.y, 0.0)
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform.basis = Basis(Vector3.UP, heading)
	# позиционный клмп: рама не должна входить в статичные тела (custom_integrator не даёт штатного выталкивания)
	var fwd_dir := Vector3(cos(heading), 0.0, -sin(heading))
	var space := _space()
	var eye := state.transform.origin + Vector3(0, 0.2, 0)   # луч выше пола, чтобы не цеплять землю
	var margin := params.length * 0.5 + 0.30 + vel.length() * 0.02
	var q := PhysicsRayQueryParameters3D.create(eye, eye + fwd_dir * (margin + 0.1))
	q.exclude = [chassis.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var d_fwd: float = (hit.position - eye).dot(fwd_dir)   # только проекция на курс: вертикаль луча не в счёт
		if d_fwd < params.length * 0.5 + 0.33:
			var push := params.length * 0.5 + 0.03 - d_fwd
			if push > 0.0:
				state.transform.origin -= fwd_dir * push   # горизонталью: иначе машина подпрыгивает и скачет вечно
				if vel.dot(fwd_dir) > 0.0:
					vel -= fwd_dir * vel.dot(fwd_dir)
					state.linear_velocity = vel
			if _recent_speed > 28.0 and _impact_cooldown <= 0:
				impact.emit(_recent_speed, hit.position, hit.normal)
				body.apply_impact(hit.position, -hit.normal, _recent_speed)
				_impact_cooldown = 60
	_prev_speed = vel.length() * 3.6
	if vel.length_squared() > 1.0: _travel = vel.normalized()
	_recent_speed = maxf(_recent_speed - 1.6, _prev_speed)  # распад ~95 км/ч за секунду
	_impact_cooldown = maxi(_impact_cooldown - 1, 0)

func _physics_process(dt: float) -> void:
	if body == null or body.wheels.is_empty(): return
	var space := _space()
	var rest := 0.5 + body.wheel_radius
	var exts: Array[float] = []
	for w in body.wheels:
		var wp := w.global_position
		var from := wp + Vector3(0, 0.5, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.4, 0))
		q.exclude = [chassis.get_rid()]
		var hit := space.intersect_ray(q)
		exts.append(0.35 if hit.is_empty() else clampf(from.distance_to(hit.position) - rest, -0.22, 0.35))
	var steer_vis := (Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")) * 0.45
	_roll += forward_speed_ms() * dt / maxf(0.05, body.wheel_radius)
	body.pose_wheels(exts, steer_vis, _roll)

func _space() -> PhysicsDirectSpaceState3D:
	if _world != null: return _world.direct_space_state
	return get_world_3d().direct_space_state
