extends Node
# Сквозь стойку стартовой арки проезжать нельзя: арка без коллайдера была
# невидимой рамкой — игрок жаловался «сквозь арку можно проехать». Под аркой
# проезд остаётся свободным, твёрдыми становятся стойки.
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
	# стойка арки занимает z 3.76..6.3 у x -420..-400: едем вдоль улицы по этой линии
	await _drive(Vector3(-455, 1.2, 5.0), 90.0, 240)
	var x := gm.car.chassis.global_position.x
	print("стойка: impact %.0f, x=%.1f" % [_max_impact, x])
	check(_max_impact > 20.0, "удар о стойку арки есть (%.0f км/ч)" % _max_impact)
	check(x < -402.0, "машина не прошла сквозь стойку (x=%.1f)" % x)
	await _free()

func _opening_case() -> void:
	await _spawn()
	# по оси улицы (z=0) проезд под аркой обязан остаться свободным
	await _drive(Vector3(-455, 1.2, 0.0), 90.0, 240)
	var x := gm.car.chassis.global_position.x
	print("проём: impact %.0f, x=%.1f" % [_max_impact, x])
	check(_max_impact < 20.0, "под аркой ничего не цепляет (%.0f км/ч)" % _max_impact)
	check(x > -400.0, "проезд сквозь проём свободен (x=%.1f)" % x)
	await _free()
