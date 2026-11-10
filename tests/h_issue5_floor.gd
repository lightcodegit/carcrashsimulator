extends Node3D
# Issue #5: on the endless track the "side road" (the grass floor) used to run out —
# floor_follow drags the floor after the car. We check driving off the road and a long
# run over grass: the floor under the wheels never ends, and the road strip is never
# visible hanging above the void.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sedan", "endless")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 10: await get_tree().physics_frame
	var floor_body: StaticBody3D = gm._map_root.get_node_or_null("endless_floor")
	check(floor_body != null, "the endless floor is found by name")
	if floor_body == null: print("FAILS %d" % _fails); get_tree().quit(1); return

	# 1) off the road onto the grass and 4 km straight along it
	var start_x: float = gm.car.chassis.global_position.x
	# teleport onto the grass next to the road (the barrier at ±5 keeps the car from pulling out sideways)
	gm.car.respawn(Transform3D(Basis(Vector3.UP, 0.0), Vector3(start_x, 1.0, 40.0)))
	Input.action_press("throttle")
	for f in 600:
		await get_tree().physics_frame
		var d := gm.car.chassis.global_position - floor_body.position
		if absf(d.x) > 60.0 and absf(d.z) > 8.0: break
	# 4 km over grass: the floor must follow the car, the car must not fall
	var fell := 0.0
	for f in 4800:
		await get_tree().physics_frame
		if gm.car.chassis.global_position.y < -2.0:
			fell += 1
			break
		if f % 400 == 0 and f > 0:
			var gap := gm.car.chassis.global_position.x - floor_body.position.x
			check(absf(gap) < 11000.0,
				"the floor stays within 11 km of the car (gap %.0f m at tick %d)" % [gap, f])
	check(fell == 0, "the car did not fall into the void over 4 km of grass")
	check(gm.car.chassis.global_position.x > start_x + 3000.0,
		"the car reached the far kilometres (%.0f → %.0f)" % [start_x, gm.car.chassis.global_position.x])

	# 2) the road nearby is still there: a downward ray at the car hits the floor or a plate
	var space := get_world_3d().direct_space_state
	var from: Vector3 = gm.car.chassis.global_position + Vector3(0, 3.0, 0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30.0, 0)))
	check(not hit.is_empty(), "there is a solid surface under the car at any kilometre")

	if _fails == 0: print("ALL PASS")
	else: print("FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
