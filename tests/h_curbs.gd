extends Node
# Curbs and jump side walls must be drivable-over, not walls.
# The car rolls in on throttle: a raw teleport+linear_velocity would jerk on non-spinning
# wheels and engine-brake — the contact would count as an impact without any wall.
var _fails := 0
var gm: GameManager
var _max_impact := 0.0
var _v_after := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _curb_case()
	await _bump_side_case()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _spawn() -> void:
	GameContext.select("sedan", "bigcity")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	_max_impact = 0.0
	gm.car.impact.connect(func(s, _p, _n): _max_impact = maxf(_max_impact, s))

func _free() -> void:
	gm.queue_free()
	for i in 6:
		await get_tree().physics_frame

# accelerate along axis: chassis forward is local +Z (verified live: rot 0 drives along +Z)
func _aim(pos: Vector3, rot_deg: float) -> void:
	gm.car.chassis.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(rot_deg)), pos)

func _curb_case() -> void:
	await _spawn()
	# south park curb (-335,-335): crest along z=-427, grass beyond it
	_aim(Vector3(-335, 1.2, -460), 0.0)
	Input.action_press("throttle")
	for i in 400:
		await get_tree().physics_frame
		var p := gm.car.chassis.global_position
		if p.z > -429.0:
			Input.action_release("throttle")
		if p.z > -419.0: break
	_v_after = gm.car.speed_kmh()
	print("curb: max_impact %.0f, v_after %.0f, pos %s" % [_max_impact, _v_after,
		str(gm.car.chassis.global_position)])
	check(_max_impact < 75.0, "the park curb hit is soft (max %.0f km/h)" % _max_impact)
	check(_v_after > 45.0, "the car keeps rolling after the curb (%.0f km/h)" % _v_after)
	await _free()

func _bump_side_case() -> void:
	await _spawn()
	# bump slab edge on the boulevard: approach from z=+30 along -Z. Hold throttle to the end:
	# what matters here is that the geometry does not kill the impact; coasting without throttle would measure drag
	_aim(Vector3(-140, 1.2, 30), 180.0)
	Input.action_press("throttle")
	for i in 400:
		await get_tree().physics_frame
		var p := gm.car.chassis.global_position
		if p.z < 4.0: break
	Input.action_release("throttle")
	_v_after = gm.car.speed_kmh()
	print("bump: max_impact %.0f, v_after %.0f, pos %s" % [_max_impact, _v_after,
		str(gm.car.chassis.global_position)])
	check(_max_impact < 75.0, "the bump's side edge is not a wall (max %.0f km/h)" % _max_impact)
	check(_v_after > 35.0, "speed survives entering the bump from the side (%.0f km/h)" % _v_after)
	await _free()
