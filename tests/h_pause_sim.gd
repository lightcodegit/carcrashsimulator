extends Node
# Pause must freeze the simulation. GameManager runs in PROCESS_MODE_ALWAYS so that Esc and
# "back to menu" keep working — and ALL of its children inherit that mode. If the car keeps
# ticking while paused, it drifts away from its spot and, once resumed, gets a volley of impulses.
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
				check(gm.get_tree().paused, "the tree is paused")
				check(gm.process_mode == Node.PROCESS_MODE_ALWAYS,
					"the pause menu lives while paused: Esc works")
				_p_pause = gm.car.chassis.global_position
				_v_pause = gm.car.speed_kmh()
				_leak = 0.0
				_phase = "paused"
		"paused":
			_leak = maxf(_leak, gm.car.chassis.global_position.distance_to(_p_pause))
			if _f == 230:
				var dspeed := absf(gm.car.speed_kmh() - _v_pause)
				print("while paused: drift %.3f m, speed %.1f -> %.1f km/h" % [_leak, _v_pause, gm.car.speed_kmh()])
				check(_leak < 0.05, "the car stays in place while paused (%.3f m)" % _leak)
				check(dspeed < 0.5, "the speed does not change while paused (%.1f km/h)" % dspeed)
				var before := gm.car.chassis.global_position
				_before = before
				gm._set_paused(false)
				_phase = "resumed"
		"resumed":
			if _f == 235:
				var jump := gm.car.chassis.global_position.distance_to(_before)
				print("the first 5 frames after the pause: %.3f m" % jump)
				check(jump < 1.5, "no volley after unpausing (%.2f m over 5 frames)" % jump)
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)

var _before := Vector3.ZERO
