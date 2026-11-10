extends Node3D
# How much each device actually brakes the car — a metric without checks.
# The complaint «the handbrake on a gamepad instantly drops speed» does not
# reproduce on a bare CarRig or on a live scene via synthetic events, so what
# must be compared is the deceleration profile itself: keyboard vs gamepad,
# service brake vs handbrake.
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
		# the peak loss per tick: «instantly» is what the player feels as a sharp
		# step, not as smooth deceleration
		_min_d = minf(_min_d, (v - _prev) / dt)
		_prev = v
	if _f == SETTLE + WINDOW:
		for x in ["throttle", "brake", "handbrake"]: Input.action_release(x)
		print("PROFILE %s: %.0f -> %.0f km/h in %.1f s; peak %.0f km/h/s (%.1f g); x=%.0f" % [
			_phase, _v0, v, WINDOW / 60.0, -_min_d, -_min_d / 3.6 / 9.81,
			gm.car.chassis.global_position.x])
		_next()

func _next() -> void:
	match _phase:
		"brake": _begin("handbrake")
		_: get_tree().quit(0)
