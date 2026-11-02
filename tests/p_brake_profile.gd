extends Node3D
# Сколько реально тормозит машина с каждого устройства — метрика без проверок.
# Жалоба «ручник на геймпаде моментально сбрасывает скорость» не воспроизводится на
# голом CarRig и на живой сцене синтетическими событиями, значит сравнивать надо
# сам профиль замедления: клавиатура и геймпад, служебный тормоз и ручник.
const SETTLE := 150
const WINDOW := 60
var gm: GameManager
var _phase := ""
var _f := 0
var _v0 := 0.0
var _min_d := 0.0
var _prev := 0.0

func _ready() -> void:
	GameContext.select("sport", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().process_frame
	_begin("brake")

func _begin(p: String) -> void:
	_phase = p
	_f = 0
	_v0 = 0.0
	_min_d = 0.0
	_prev = 0.0
	gm._respawn_now()
	Input.action_press("throttle")

func _physics_process(dt: float) -> void:
	_f += 1
	var v := gm.car.speed_kmh()
	if _phase != "" and _f == SETTLE:
		_v0 = v
		Input.action_release("throttle")
		Input.action_press("brake" if _phase == "brake" else "handbrake")
		_prev = v
	if _f > SETTLE and _f <= SETTLE + WINDOW and _prev > 0.0:
		# пик потери за тик: именно «моментально» игрок чувствует как резкий шаг,
		# а не как плавное замедление
		_min_d = minf(_min_d, (v - _prev) / dt)
		_prev = v
	if _f == SETTLE + WINDOW:
		for x in ["throttle", "brake", "handbrake"]: Input.action_release(x)
		print("PROFILE %s: %.0f -> %.0f км/ч за %.1f с; пик %.0f км/ч/с (%.1f g); x=%.0f" % [
			_phase, _v0, v, WINDOW / 60.0, -_min_d, -_min_d / 3.6 / 9.81,
			gm.car.chassis.global_position.x])
		_next()

func _next() -> void:
	match _phase:
		"brake": _begin("handbrake")
		_: get_tree().quit(0)
