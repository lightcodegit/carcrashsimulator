extends Node3D
# Restart returns knocked props to their places: otherwise after several runs the track
# loads with debris, and the car could spawn inside a cone.
var _fails := 0
var gm: GameManager

# Bottom face of a prop's visual mesh in world coordinates.
# [sunk count, max vertical speed] for all of the map's knockable props.
func _seating(id: String) -> Array[float]:
	GameContext.select("sedan", id)
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	var bottoms := {}
	var surfs := {}
	for p in get_tree().get_nodes_in_group(LooseProp.GROUP):
		var n := p as Node3D
		bottoms[n] = _aabb(n).position.y
		surfs[n] = MapKit.surface_y(n.global_position.x, n.global_position.z)
	var hop := 0.0
	for t in 60:
		await get_tree().physics_frame
		for n in bottoms:
			if is_instance_valid(n): hop = maxf(hop, absf((n as RigidBody3D).linear_velocity.y))
	var sunk := 0
	for n in bottoms:
		if is_instance_valid(n) and _aabb(n).position.y < float(surfs[n]) - 0.004: sunk += 1
	g.queue_free()
	# four frames: the bodies must leave the physical space before the next map is
	# built, otherwise its props jostle with the old ones
	for i in 4:
		await get_tree().physics_frame
	return [float(sunk), hop, float(bottoms.size())]

func _aabb(n: Node3D) -> AABB:
	var m := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var g: AABB = mi.global_transform * mi.get_aabb()
			if first: m = g; first = false
			else: m = m.merge(g)
		for k in c.get_children(): stack.append(k)
	return m

# A real button press: the event goes through the viewport, GameManager._unhandled_input
# reads it. Between press and release there is a physics tick, otherwise
# is_action_pressed() has no time to fire.
func _tap(key: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().physics_frame
	ev.pressed = false
	get_viewport().push_input(ev)

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	# Seating across all maps, BEFORE building our own run: two worlds with props in one
	# scene would start jostling, and the check would catch that instead of the seating.
	# On the track this bug has its own case: a prop stands one end on asphalt and the
	# other on the floor, and the solver ejects it at the start of the run.
	for id in MapDB.ids():
		var seats := await _seating(id)
		if id != "void":
			check(seats[2] > 4, "%s: found %d props to check" % [id, int(seats[2])])
			check(seats[0] == 0, "%s: no prop is sunk into the surface (%d)" % [id, int(seats[0])])
			check(seats[1] < 0.60, "%s: props do not bounce at the start of the run (vy=%.2f)" % [id, seats[1]])
		else:
			check(seats[2] == 0, "void: no props to check (%d)" % int(seats[2]))
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for i in 30:
		await get_tree().physics_frame
	var props: Array = get_tree().get_nodes_in_group(LooseProp.GROUP)
	check(props.size() > 5, "the arena has something to knock over (%d)" % props.size())
	var home: Array[Transform3D] = []
	for p in props: home.append((p as Node3D).global_transform)
	# scatter the props: put one exactly on the car spawn, carry the rest aside
	for i in props.size():
		var n := props[i] as Node3D
		n.global_position = gm._spawn.origin + (Vector3(0, 0.4, 0) if i == 0 else Vector3(6 + i, 0.4, 3 * (i % 3)))
		n.linear_velocity = Vector3.ZERO
	await get_tree().physics_frame
	var before: Vector3 = (props[0] as Node3D).global_position
	check(before.distance_to(gm._spawn.origin) < 1.0, "a prop stands on the spawn (%.2f m)" % before.distance_to(gm._spawn.origin))
	gm._respawn_now()
	for i in 12:
		await get_tree().physics_frame
	var back := 0
	for i in props.size():
		if (props[i] as Node3D).global_transform.origin.distance_to(home[i].origin) < 0.30: back += 1
	check(back == props.size(), "props returned home (%d of %d)" % [back, props.size()])

	# Seating: after the restart the props are back in place and each stands ON the
	# surface, not inside it. The solver ejects a submerged prop, and cones start
	# bouncing all over the track right at the beginning of the run.
	var sunk := 0
	var hop := 0.0
	for i in props.size():
		var n := props[i] as Node3D
		var bottom := _aabb(n).position.y
		var surf := MapKit.surface_y(n.global_position.x, n.global_position.z)
		var home_surf := MapKit.surface_y(home[i].origin.x, home[i].origin.z)
		if bottom < home_surf - 0.004: sunk += 1
		hop = maxf(hop, absf((props[i] as RigidBody3D).linear_velocity.y))
	check(sunk == 0, "no prop sank into the surface (%d)" % sunk)
	for i in 20:
		await get_tree().physics_frame
		for p in props:
			hop = maxf(hop, absf((p as RigidBody3D).linear_velocity.y))
	check(hop < 0.60, "props do not bounce at the start (max vy=%.2f m/s)" % hop)
	var pos := gm.car.chassis.global_position
	check(pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)) < 0.8,
		"the car started where it was placed (%.2f m)" % pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)))
	check(gm.car.chassis.linear_velocity.length() < 0.5,
		"the car is neither ejected nor accelerated (%.2f m/s)" % gm.car.chassis.linear_velocity.length())
	check(gm.car.body.dent_count == 0, "the restart repaired the body")

	# The most frequent restart complaint: "the speed zeroed but the car stayed in place".
	# The old test only checked the start pose, i.e. the moment BEFORE driving. Now we
	# drive away, press R with real events (read by GameManager._unhandled_input) and
	# demand a return to spawn — by position, heading and speed. Distance is taken from
	# the track: on the arena, in 3 seconds the car would hit the wall and the check
	# would become vacuous.
	gm.queue_free()
	for _i in 4:
		await get_tree().physics_frame
	GameContext.select("sedan", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 20:
		await get_tree().physics_frame
	Input.action_press("throttle")
	for _i in 200:
		await get_tree().physics_frame
	Input.action_release("throttle")
	var far := gm.car.chassis.global_position.x
	check(absf(far - gm._spawn.origin.x) > 20.0,
		"the test is not vacuous: the car really drove away (%.1f m from spawn)" % absf(far - gm._spawn.origin.x))
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_R
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().physics_frame
	ev.pressed = false
	get_viewport().push_input(ev)
	for _i in 20:
		await get_tree().physics_frame
	var landed := gm.car.chassis.global_position
	check(absf(landed.x - gm._spawn.origin.x) < 1.0 and absf(landed.z - gm._spawn.origin.z) < 1.0,
		"R teleports the car to spawn (was x=%.1f, now x=%.1f, spawn x=%.1f)" % [far, landed.x, gm._spawn.origin.x])
	check(gm.car.speed_kmh() < 2.0, "the car stands still after R (%.1f km/h)" % gm.car.speed_kmh())
	check(absf(angle_difference(gm.car.heading, gm._spawn.basis.get_euler().y)) < 0.05,
		"after R the heading matches the spawn (%.2f rad)" % gm.car.heading)

	# What the player sees, not what physics computed: the on-screen position (with
	# interpolation it can lag a tick) and the camera near the car. The repeat complaint
	# about R — "the car does not restart, it just drops speed to zero" — is about the
	# frame, so it is measured via get_global_transform_interpolated(), not global_position.
	var shown := gm.car.chassis.get_global_transform_interpolated().origin
	check(Vector2(shown.x - gm._spawn.origin.x, shown.z - gm._spawn.origin.z).length() < 1.0,
		"R: the car is on spawn on screen (drawn at x=%.1f z=%.1f, spawn x=%.1f)" % [
			shown.x, shown.z, gm._spawn.origin.x])
	check(gm.camera.global_position.distance_to(gm.car.chassis.global_position) < 14.0,
		"R: the camera is next to the car after the restart (%.1f m)" %
		gm.camera.global_position.distance_to(gm.car.chassis.global_position))
	check(gm.hud._tip_label.visible, "R: the restart is labeled on screen")

	# R while paused: the player presses it to start over, not to escape the menu.
	gm._set_paused(true)
	await get_tree().physics_frame
	await _tap(KEY_R)
	for _i in 8:
		await get_tree().physics_frame
	check(not gm._paused, "R while paused unpauses (%s)" % str(gm._paused))
	check(absf(gm.car.chassis.global_position.x - gm._spawn.origin.x) < 1.0,
		"R while paused returns to spawn (x=%.1f)" % gm.car.chassis.global_position.x)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
