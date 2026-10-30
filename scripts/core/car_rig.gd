class_name CarRig
extends Node3D

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

# Поверхность, на которую можно заезжать: рампа, пол, пологий склон.
const DRIVABLE_NORMAL_Y := 0.55
# Касание быстрее этого — настоящий удар; медленнее машина просто скользит вдоль препятствия.
const HARD_HIT_MS := 2.5
const IMPACT_MIN_KMH := 28.0
const HANDBRAKE_GRIP := 1.05
const HANDBRAKE_BRAKE := 0.55
const HANDBRAKE_STEER := 1.45
# На какую ступень можно заехать (бордюр 0.2 м, площадки) и как держаться земли.
const STEP_UP := 0.55
const RIDE_GAP := 0.005
const GROUND_LIFT := 0.30
const GROUND_DROP := 0.35
const SUPPORT_NORMAL_Y := 0.35

var params: VehicleParams
var chassis: RigidBody3D
var body: DentBody
var heading := 0.0
var _world: World3D
var _prev_speed := 0.0
var _recent_speed := 0.0
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
	body = DentBody.new()
	chassis.add_child(body)
	body.setup(p.model, p)
	# кузов в DentBody стоит колёсами на локальном нуле: опускаем на низ коллайдера
	body.position = Vector3(0, -p.collider_size().y * 0.5, 0)

func respawn(tf: Transform3D) -> void:
	heading = tf.basis.get_euler().y
	var rest_y := params.collider_size().y * 0.5 + 0.02
	chassis.global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(tf.origin.x, rest_y, tf.origin.z))
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	_recent_speed = 0.0
	_prev_speed = 0.0
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
	# state.step, а не 1/physics_ticks_per_second: при Engine.time_scale Godot делает
	# столько же тиков в секунду, но с уменьшенной дельтой. С жёстким dt машина
	# разгонялась и тормозила на полной скорости даже в слоу-мо.
	var dt: float = state.step
	var vel := state.linear_velocity
	vel += Vector3(0, -9.8, 0) * dt            # custom_integrator отключает штатную гравитацию
	# опору ищем лучом, а не числом контактов: рама держится на зазоре RIDE_GAP над
	# землёй, поэтому контактов может не быть вовсе, а газ при этом нужен
	var fwd_axis := Vector3(cos(heading), 0.0, -sin(heading))
	var support := _ground_probe(state.transform.origin, fwd_axis)
	_grounded = support.on
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
		if hand:
			# ручник: тормозит и срывает боковое сцепление — занос вместо «ничего»
			if vf > 0.0: vf = maxf(vf - params.brake_decel * HANDBRAKE_BRAKE * dt, 0.0)
			vl *= exp(-dt * HANDBRAKE_GRIP)
		else:
			vl *= exp(-dt * params.grip)
		var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")  # + = налево
		var sf := clampf(1.25 - absf(vf) / vmax * 1.05, 0.22, 1.0)
		var speed_gate := clampf(absf(vf) / 2.0, 0.0, 1.0)
		var drift := HANDBRAKE_STEER if hand else 1.0
		heading += deg_to_rad(params.steer_rate_deg) * steer * sf * dt * speed_gate * drift * (1.0 if vf >= 0.0 else -1.0)
		vel = fwd * vf + right * vl + Vector3(0.0, vel.y, 0.0)
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform.basis = Basis(Vector3.UP, heading)
	_apply_ground(state, support)
	_clamp_and_impact(state)
	_prev_speed = state.linear_velocity.length() * 3.6
	_recent_speed = maxf(_recent_speed - 1.6, _prev_speed)  # распад ~95 км/ч за секунду
	_impact_cooldown = maxi(_impact_cooldown - 1, 0)

# Рама не должна входить в статичные тела (custom_integrator не даёт штатного выталкивания).
# Проверяем 4 направления. Позиция выталкивается всегда, а скорость гасится и удар
# регистрируется только при жёстком контакте: лёгкое касание не останавливает машину,
# заезд на рампу не считается столкновением, приземление после прыжка — тоже.
func _clamp_and_impact(state: PhysicsDirectBodyState3D) -> void:
	var fwd := Vector3(cos(heading), 0.0, -sin(heading))
	var right := Vector3(sin(heading), 0.0, cos(heading))
	var vel := state.linear_velocity
	var half_len := params.length * 0.5
	var half_wid := params.width * 0.5
	var axes := [[fwd, half_len], [-fwd, half_len], [right, half_wid], [-right, half_wid]]
	var origin := state.transform.origin
	var best_dir := Vector3.ZERO
	var best_into := 0.0
	var best_point := Vector3.ZERO
	for cfg in axes:
		var dir: Vector3 = cfg[0]
		var half: float = cfg[1]
		var r := _probe(origin, dir, half, vel)
		if r.is_empty(): continue
		var push: float = r.push
		if push > 0.0:
			origin -= dir * push
			state.transform.origin = origin
		var into: float = vel.dot(dir)
		if into > best_into:
			best_into = into
			best_dir = dir
			best_point = r.point
	if best_into <= HARD_HIT_MS: return
	vel -= best_dir * best_into
	state.linear_velocity = vel
	if _recent_speed > IMPACT_MIN_KMH and _impact_cooldown <= 0:
		impact.emit(_recent_speed, best_point, -best_dir)
		body.apply_impact(best_point, best_dir, _recent_speed)  # dir — внутрь кузова
		_impact_cooldown = 60

# Опора ищется тремя лучами (нос, центр, корма) и берётся самая высокая поверхность
# в пределах STEP_UP. Один центральный луч видит ступень только когда коллайдер уже
# упёрся в неё, поэтому машина не могла заехать на бордюр.
func _ground_probe(origin: Vector3, fwd: Vector3) -> Dictionary:
	var ride: float = params.collider_size().y * 0.5 + RIDE_GAP
	var reach := ride + STEP_UP + 0.6
	var limit := maxf(STEP_UP, GROUND_DROP)
	var best := -INF
	var along := params.length * 0.42
	var offsets: Array[float] = [along, 0.0, -along]
	for off in offsets:
		var from := origin + fwd * off + Vector3(0, 0.30, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -reach, 0))
		q.exclude = [chassis.get_rid()]
		var hit := _space().intersect_ray(q)
		if hit.is_empty(): continue
		var n: Vector3 = hit.normal
		if n.y < SUPPORT_NORMAL_Y: continue        # стена или крутой склон, не опора
		var top: float = hit.position.y
		if absf(top + ride - origin.y) > limit: continue
		best = maxf(best, top)
	if best == -INF: return {"on": false, "dy": 0.0}
	return {"on": true, "dy": best + ride - origin.y}

# Держим раму на опоре: без этого контакт с полом даёт пилообразный прыжок на ~2.5 см
# каждый кадр, а колёса как потомки шасси дёргаются вместе с ним. Заодно позволяет
# заезжать на бордюры и площадки высотой до STEP_UP.
func _apply_ground(state: PhysicsDirectBodyState3D, support: Dictionary) -> void:
	if not support.on: return
	var dy: float = support.dy
	state.transform.origin.y += clampf(dy, -GROUND_LIFT, GROUND_LIFT)
	if absf(dy) < 0.06:
		var v := state.linear_velocity
		state.linear_velocity = Vector3(v.x, 0.0, v.z)

# Высота верха препятствия в точке контакта: нужна, чтобы отличить бордюр от стены.
func _obstacle_top(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.6, 0), p + Vector3(0, -0.6, 0))
	q.exclude = [chassis.get_rid()]
	var hit := _space().intersect_ray(q)
	return -INF if hit.is_empty() else hit.position.y

# Луч из центра рамы вдоль dir. Пусто, если препятствия нет, оно пологое (рампа/пол),
# это низкая ступень (бордюр) или до него далеко. Иначе — точка контакта и выталкивание.
func _probe(origin: Vector3, dir: Vector3, half: float, vel: Vector3) -> Dictionary:
	var space := _space()
	var eye := origin + Vector3(0, 0.2, 0)      # выше пола, чтобы не цеплять землю
	var margin := half + 0.25 + vel.length() * 0.012
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * (margin + 0.1))
	q.exclude = [chassis.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty(): return {}
	var n: Vector3 = hit.normal
	if n.y > DRIVABLE_NORMAL_Y: return {}       # на такую поверхность можно заезжать
	var along: float = (hit.position - eye).dot(dir)
	if along >= half + 0.05: return {}
	# низкое препятствие не стена: на бордюр и площадку заезжаем, а не упираемся
	var car_bottom := origin.y - params.collider_size().y * 0.5
	var top := _obstacle_top(hit.position)
	if top > -INF and top < car_bottom + STEP_UP: return {}
	return {"point": hit.position, "push": maxf(0.0, half + 0.03 - along)}

func _physics_process(dt: float) -> void:
	if body == null or body.wheels.is_empty(): return
	var space := _space()
	var rest := 0.5 + body.wheel_radius
	var exts: Array[float] = []
	for w in body.wheels:
		var from := w.global_position + Vector3(0, 0.5, 0)
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
