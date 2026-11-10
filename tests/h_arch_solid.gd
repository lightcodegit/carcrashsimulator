extends Node
# The start-arch pillar must not be drivable through: an arch without a collider
# was an invisible frame — players complained "you can drive through the arch".
# The passage under the arch stays free; the pillars become solid.
var _fails := 0
var gm: GameManager
var _max_impact := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _post_case()
	await _opening_case()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _spawn() -> void:
	GameContext.select("sport", "bigcity")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	_max_impact = 0.0
	gm.car.impact.connect(func(s, _p, _n): _max_impact = maxf(_max_impact, s))

func _free() -> void:
	gm.queue_free()
	for i in 6:
		await get_tree().physics_frame

func _drive(pos: Vector3, rot_deg: float, frames: int) -> void:
	gm.car.chassis.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(rot_deg)), pos)
	Input.action_press("throttle")
	for i in frames:
		await get_tree().physics_frame
		if gm.car.chassis.global_position.x > -380.0: break
	Input.action_release("throttle")

func _post_case() -> void:
	await _spawn()
	# the arch pillar spans z 3.76..6.3 at x -420..-400: drive along the street on this line
	await _drive(Vector3(-455, 1.2, 5.0), 90.0, 240)
	var x := gm.car.chassis.global_position.x
	print("pillar: impact %.0f, x=%.1f" % [_max_impact, x])
	check(_max_impact > 20.0, "the car hits the arch pillar (%.0f km/h)" % _max_impact)
	check(x < -402.0, "the car did not pass through the pillar (x=%.1f)" % x)
	await _free()

func _opening_case() -> void:
	await _spawn()
	# along the street axis (z=0) the passage under the arch must stay free
	await _drive(Vector3(-455, 1.2, 0.0), 90.0, 240)
	var x := gm.car.chassis.global_position.x
	print("opening: impact %.0f, x=%.1f" % [_max_impact, x])
	check(_max_impact < 20.0, "nothing clips under the arch (%.0f km/h)" % _max_impact)
	check(x > -400.0, "driving through the opening is free (x=%.1f)" % x)
	await _free()
