class_name CarRig
extends Node3D

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

var params: VehicleParams
var chassis: RigidBody3D
var shell: SoftShell
var heading := 0.0
var _prev_speed := 0.0
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
	wmat.albedo_color = Color(0.08, 0.08, 0.08)
	for i in 4:
		var piv := Node3D.new()
		var mi := MeshInstance3D.new()
		var geo := CylinderMesh.new()
		geo.height = 0.26; geo.top_radius = 0.34; geo.bottom_radius = 0.34
		mi.mesh = geo; mi.material_override = wmat
		mi.rotation = Vector3(0, 0, PI * 0.5)
		piv.add_child(mi); _visual.add_child(piv)
		_wheel_pivots.append(piv); _wheel_meshes.append(mi)
	var wx := params.length * 0.32
	var wz := (params.width - 0.5) * 0.5
	_wheel_pivots[0].position = Vector3(wx, 0, wz)
	_wheel_pivots[1].position = Vector3(wx, 0, -wz)
	_wheel_pivots[2].position = Vector3(-wx, 0, wz)
	_wheel_pivots[3].position = Vector3(-wx, 0, -wz)
	shell = SoftShell.new()
	add_child(shell)
	shell.setup(ShellBuilder.build(p), chassis, p)
	shell.velocity_getter = func() -> Vector3: return chassis.linear_velocity
	shell.space_state = world.direct_space_state

func _on_body_entered(_other: Node) -> void:
	if _prev_speed < 28.0: return
	var v := chassis.linear_velocity
	var n: Vector3 = -v.normalized() if v.length_squared() > 0.04 else Vector3.UP
	var point := chassis.global_position - n * 0.3
	impact.emit(_prev_speed, point, n)
	shell.apply_impact(point, n, _prev_speed / 3.6)

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
	_prev_speed = vel.length() * 3.6

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
