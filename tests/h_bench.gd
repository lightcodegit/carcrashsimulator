extends Node3D
# Бенчмарк симуляции: wall-clock на фиксированном числе физических тиков в headless,
# то есть чистая стоимость симуляции без рендера. MAP=speedway|town|arena.
# Метрика, без проверок: печатает мс/тик и долю бюджета шага 16.67 мс.
const FROM := 300
const TO := 900
var _gm: GameManager
var _f := 0
var _t0 := 0

func _ready() -> void:
	var id := OS.get_environment("MAP")
	if id == "": id = "speedway"
	GameContext.select("sport", id)
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	await get_tree().process_frame
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	_f += 1
	if _f == FROM: _t0 = Time.get_ticks_usec()
	if _f == TO:
		var per := float(Time.get_ticks_usec() - _t0) / float(TO - FROM)
		print("BENCH %s: %.4f мс/тик (%.2f× шага 16.67 мс), x=%.0f км/ч=%.0f" % [
			OS.get_environment("MAP"), per / 1000.0, per / 16670.0,
			_gm.car.chassis.global_position.x, _gm.car.speed_kmh()])
		get_tree().quit(0)
