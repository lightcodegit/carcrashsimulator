extends Node3D
# Simulation benchmark: wall-clock over a fixed number of physics ticks in headless,
# i.e. the pure simulation cost without rendering. MAP=speedway|town|arena.
# A metric, no checks: prints ms/tick and the share of the 16.67 ms step budget.
const FROM := 300
const TO := 900
var _gm: GameManager
var _map := ""
var _car := ""
var _f := 0
var _t0 := 0

func _ready() -> void:
	_map = OS.get_environment("MAP")
	if _map == "": _map = "speedway"
	_car = OS.get_environment("CAR")
	if _car == "": _car = "sport"
	GameContext.select(_car, _map)
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	await get_tree().process_frame
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	_f += 1
	if _f == FROM: _t0 = Time.get_ticks_usec()
	if _f == TO:
		var per := float(Time.get_ticks_usec() - _t0) / float(TO - FROM)
		print("BENCH %s/%s: %.4f ms/tick (%.2f× of the 16.67 ms step), x=%.0f km/h=%.0f" % [
			_map, _car, per / 1000.0, per / 16670.0,
			_gm.car.chassis.global_position.x, _gm.car.speed_kmh()])
		get_tree().quit(0)
