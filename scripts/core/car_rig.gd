class_name CarRig
extends Node3D

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

var params: VehicleParams
var chassis: RigidBody3D
var shell: SoftShell
var heading := 0.0
var _prev_speed := 0.0
var _recent_speed := 0.0
var _impact_cooldown := 0
var _grounded := true
var _susp: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _visual: Node3D
var _wheel_pivots: Array[Node3D] = []
var _wheel_meshes: Array[MeshInstance3D] = []

class ChassisBody extends RigidBody3D:
	var rig: CarRig

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		rig._chassis_physics(state)

func build(p: VehicleParams, world: World3D) -> void:
	params = p
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
	_visual = Node3D.new()
	chassis.add_child(_visual)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.12, 0.12, 0.14); wmat.roughness = 0.9
	for i in 4:
		var piv := Node3D.new()
		var mi := MeshInstance3D.new()
		var geo := CylinderMesh.new()
		geo.height = 0.3; geo.top_radius = 0.4; geo.bottom_radius = 0.4
		mi.mesh = geo; mi.material_override = wmat
		mi.rotation = Vector3(0, 0, PI * 0.5)
		piv.add_child(mi); _visual.add_child(piv)
		_wheel_pivots.append(piv); _wheel_meshes.append(mi)
	var wx := params.length * 0.32
	var wz := params.width * 0.5 - 0.02
	var wy := -(params.height - 0.12) * 0.5 + 0.34
	_wheel_pivots[0].position = Vector3(wx, wy, wz)
	_wheel_pivots[1].position = Vector3(wx, wy, -wz)
	_wheel_pivots[2].position = Vector3(-wx, wy, wz)
	_wheel_pivots[3].position = Vector3(-wx, wy, -wz)
	var inner := MeshInstance3D.new()
	var ibm := BoxMesh.new()
	ibm.size = Vector3(params.length * 0.8, params.height * 0.5, params.width * 0.72)
	var im := StandardMaterial3D.new(); im.albedo_color = Color(0.1, 0.1, 0.12)
	ibm.material = im; inner.mesh = ibm
	inner.position = Vector3(0, -params.height * 0.12, 0)
	chassis.add_child(inner)
	shell = SoftShell.new()
	add_child(shell)
	shell.setup(ShellBuilder.build(p), chassis, p)
	shell.velocity_getter = func() -> Vector3: return chassis.linear_velocity
	shell.space_state = world.direct_space_state

func _on_body_entered(_other: Node) -> void:
	# скорость в момент события уже обнулена solver'ом — берём свежий пик
	if _recent_speed < 28.0 or _impact_cooldown > 0: return
	var v := chassis.linear_velocity
	var n: Vector3 = Vector3(-cos(heading), 0.0, sin(heading))  # против направления машины (стена перед носом)
	var point := chassis.global_position + Vector3(params.length * 0.5, 0.1, 0)
	impact.emit(_recent_speed, point, n)
	shell.apply_impact(point, n, _recent_speed / 3.6)
	_impact_cooldown = 60

func respawn(tf: Transform3D) -> void:
	heading = tf.basis.get_euler().y
	chassis.global_transform = tf
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	shell.reset()

func speed_kmh() -> float:
	return chassis.linear_velocity.length() * 3.6

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
		var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")  # + = налево; Basis(UP,h): h>0 => fwd к -Z = влево
		var sf := clampf(1.25 - absf(vf) / vmax * 1.05, 0.22, 1.0)
		var speed_gate := clampf(absf(vf) / 2.0, 0.0, 1.0)
		heading += deg_to_rad(params.steer_rate_deg) * steer * sf * dt * speed_gate * (1.0 if vf >= 0.0 else -1.0)
		vel = fwd * vf + right * vl + Vector3(0.0, vel.y, 0.0)
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform.basis = Basis(Vector3.UP, heading)
	# позиционный клмп: рама не должна входить в статичные тела (custom_integrator не даёт штатного выталкивания)
	var fwd_dir := Vector3(cos(heading), 0.0, -sin(heading))
	var space := get_world_3d().direct_space_state
	var nose := state.transform.origin + fwd_dir * (params.length * 0.5)
	var margin := params.length * 0.5 + 0.30 + vel.length() * 0.02
	var q := PhysicsRayQueryParameters3D.create(state.transform.origin + Vector3(0, 0.2, 0), state.transform.origin + fwd_dir * (margin + 0.1) + Vector3(0, 0.2, 0))
	q.exclude = [chassis.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and state.transform.origin.distance_to(hit.position) < params.length * 0.5 + 0.33:
		var fixed_origin: Vector3 = hit.position - fwd_dir * (params.length * 0.5 + 0.03)
		if fwd_dir.dot(fixed_origin - state.transform.origin) < 0.0:
			state.transform.origin = fixed_origin
			if vel.dot(fwd_dir) > 0.0:
				vel -= fwd_dir * vel.dot(fwd_dir)
				state.linear_velocity = vel
		if _recent_speed > 28.0 and _impact_cooldown <= 0:
			var cn: Vector3 = hit.normal
			var cpoint: Vector3 = hit.position
			impact.emit(_recent_speed, cpoint, cn)
			shell.apply_impact(cpoint, cn, _recent_speed / 3.6)
			_impact_cooldown = 60
	_prev_speed = vel.length() * 3.6
	_recent_speed = maxf(_recent_speed - 1.6, _prev_speed)  # распад ~95 км/ч за секунду
	_impact_cooldown = maxi(_impact_cooldown - 1, 0)

func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in 4:
		var anchor := chassis.global_transform * _wheel_pivots[i].position + Vector3(0, 0.5, 0)
		var q := PhysicsRayQueryParameters3D.create(anchor, anchor + Vector3(0, -1.2, 0))
		q.exclude = [chassis.get_rid()]
		var hit := space.intersect_ray(q)
		var ext := 0.3 if hit.is_empty() else clampf(anchor.distance_to(hit.position) - 0.35, 0.0, 0.6)
		_susp[i] = lerpf(_susp[i], ext, 0.25)
		_wheel_meshes[i].position.y = -_susp[i]
	var pitch: float = ((_susp[0] + _susp[1]) - (_susp[2] + _susp[3])) * 0.15
	var roll: float = ((_susp[0] + _susp[2]) - (_susp[1] + _susp[3])) * 0.15
	_visual.rotation.z = lerpf(_visual.rotation.z, pitch, 0.15)
	_visual.rotation.x = lerpf(_visual.rotation.x, -roll, 0.15)
	var steer_vis := (Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")) * 0.5
	_wheel_pivots[0].rotation.y = steer_vis
	_wheel_pivots[1].rotation.y = steer_vis
