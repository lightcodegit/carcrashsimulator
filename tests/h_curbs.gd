extends Node
# Бордюры и боковые стенки трамплинов должны быть «наезжаемыми», а не стенами.
# Машина едет газом: прямой teleport+linear_velocity дал бы юл от некрутящихся колёс
# и торможение двигателем — контакт засчитался бы как удар без всякой стены.
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

# разгон вдоль axis: мораль шасси — локальная +Z (проверено живьём: rot 0 едет по +Z)
func _aim(pos: Vector3, rot_deg: float) -> void:
	gm.car.chassis.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(rot_deg)), pos)

func _curb_case() -> void:
	await _spawn()
	# южный бордюр парка (-335,-335): гребень на линии z=-427, за ним газон
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
	check(_max_impact < 75.0, "удар о бордюр парка мягкий (макс. %.0f км/ч)" % _max_impact)
	check(_v_after > 45.0, "после бордюра машина катится дальше (%.0f км/ч)" % _v_after)
	await _free()

func _bump_side_case() -> void:
	await _spawn()
	# борт плиты бугра на бульваре: подъезд с z=+30 вдоль -Z. Газ держим до конца:
	# тут важно, что geometry не глушит удар; катение без газа меряло бы сопротивление
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
	check(_max_impact < 75.0, "боковой борт бугра не стена (макс. %.0f км/ч)" % _max_impact)
	check(_v_after > 35.0, "после съезда на бугор сбоку скорость цела (%.0f км/ч)" % _v_after)
	await _free()
