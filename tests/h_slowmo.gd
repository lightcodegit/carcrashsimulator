extends Node3D
# Контроллер обязан уважать Engine.time_scale: при 0.3 за то же число физических тиков
# машина набирает примерно втрое меньшую скорость. Прежний жёсткий dt = 1/60 давал
# обычный разгон даже в слоу-мо.
var _fails := 0
var car: CarRig
var _ticks := 0
var _phase := 0
var _v_normal := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var b := BoxShape3D.new()
	b.size = Vector3(900, 2, 60); cs.shape = b
	fl.add_child(cs); add_child(fl); fl.global_position = Vector3(300, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_ticks += 1
	if _phase == 0 and _ticks == 150:
		_v_normal = car.speed_kmh()
		_phase = 1
		_ticks = 0
		TimeScale.set_hold(true)
		car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
		Input.action_press("throttle")
	elif _phase == 1 and _ticks == 150:
		var v_slow := car.speed_kmh()
		var ratio := v_slow / maxf(0.001, _v_normal)
		check(Engine.time_scale == 0.3, "слоу-мо включено (%.2f)" % Engine.time_scale)
		check(_v_normal > 20.0, "обычный разгон состоялся (%.1f км/ч)" % _v_normal)
		check(ratio > 0.2 and ratio < 0.45,
			"в слоу-мо разгон втрое медленнее (%.1f против %.1f км/ч, доля %.2f)" % [v_slow, _v_normal, ratio])
		TimeScale.set_hold(false)
		check(Engine.time_scale == 1.0, "после отпускания масштаб вернулся (%.2f)" % Engine.time_scale)
		print("SLOWMO normal=%.1f км/ч slow=%.1f км/ч ratio=%.2f" % [_v_normal, v_slow, ratio])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
