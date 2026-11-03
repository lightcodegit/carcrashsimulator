extends Node
# Пауза обязана замораживать симуляцию. GameManager стоит в PROCESS_MODE_ALWAYS,
# чтобы Esc и «в меню» работали, — и этот режим наследуют ВСЕ его дети. Если машина
# крутится на паузе, она уезжает с места, а после снятия получает залп импульсов.
var _fails := 0
var gm: GameManager
var _f := 0
var _phase := "drive"
var _p_pause := Vector3.ZERO
var _v_pause := 0.0
var _leak := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameContext.select("sedan", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	_f += 1
	match _phase:
		"drive":
			if _f == 150:
				Input.action_release("throttle")
				_phase = "coast"
		"coast":
			if _f == 170:
				gm._set_paused(true)
				check(gm.get_tree().paused, "дерево поставлено на паузу")
				check(gm.process_mode == Node.PROCESS_MODE_ALWAYS,
					"меню паузы живёт при паузе: Esc работает")
				_p_pause = gm.car.chassis.global_position
				_v_pause = gm.car.speed_kmh()
				_leak = 0.0
				_phase = "paused"
		"paused":
			_leak = maxf(_leak, gm.car.chassis.global_position.distance_to(_p_pause))
			if _f == 230:
				var dspeed := absf(gm.car.speed_kmh() - _v_pause)
				print("на паузе: уезд %.3f м, скорость %.1f -> %.1f км/ч" % [_leak, _v_pause, gm.car.speed_kmh()])
				check(_leak < 0.05, "на паузе машина стоит на месте (%.3f м)" % _leak)
				check(dspeed < 0.5, "на паузе скорость не меняется (%.1f км/ч)" % dspeed)
				var before := gm.car.chassis.global_position
				_before = before
				gm._set_paused(false)
				_phase = "resumed"
		"resumed":
			if _f == 235:
				var jump := gm.car.chassis.global_position.distance_to(_before)
				print("первые 5 кадров после паузы: %.3f м" % jump)
				check(jump < 1.5, "после снятия с паузы нет залпа (%.2f м за 5 кадров)" % jump)
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)

var _before := Vector3.ZERO
