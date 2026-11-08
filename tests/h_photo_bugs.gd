extends Node3D
# Проба багов фотомода/реплея/удара: геометрия нижних панелей, восстановление
# HUD через настоящий пайплайн ввода, колёса в фотомоде, удар при посадке.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sedan", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 10: await get_tree().physics_frame

	# --- 1. геометрия полос: кнопки обязаны сидеть внутри своей панели ---
	var photo: Control = gm.hud._photo_panel
	var replay: Control = gm.hud._replay_panel
	for pair in [["photo", photo, gm.hud._photo_buttons], ["replay", replay, gm.hud._replay_buttons]]:
		var pr: Rect2 = (pair[1] as Control).get_global_rect()
		var out := 0
		for b in pair[2]:
			var br: Rect2 = (b as Control).get_global_rect()
			if not pr.encloses(br): out += 1
		check(out == 0, "%s bar: %d кнопок вылезают из панели" % [pair[0], out])
	# подпись не должна вылезать за панель
	for pair in [["photo", gm.hud._photo_info, photo], ["replay", gm.hud._replay_info, replay]]:
		var lab: Label = pair[1]
		var pr: Rect2 = (pair[2] as Control).get_global_rect()
		check(pr.encloses(Rect2(lab.get_global_position(), Vector2(1, 1))),
			"%s bar: подпись начинается вне панели" % pair[0])

	# --- 2. БЕЗ HUD и восстановление через настоящий пайплайн ввода ---
	gm.hud.photo_button("СБРОС ВИДА")  # warm: панели существуют
	gm._open_photo()
	await get_tree().process_frame
	check(gm.photo.active, "photo mode open")
	gm.hud.photo_button("БЕЗ HUD").pressed.emit()
	await get_tree().process_frame
	check(gm.hud._panels_hidden, "BEZ HUD hides panels")
	_key(KEY_F5)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not gm.hud._panels_hidden, "F5 through the real input pipeline restores HUD")
	check(gm.photo.hud_off == false, "hud_off flag synced after F5")

	# --- 3. колёса в фотомоде: WASD камеры не трогает машину ---
	var steer0: float = gm.car._wheels[0].steering
	var pos0: Vector3 = gm.car.chassis.global_position
	_key(KEY_A)
	_key(KEY_W)
	for f in 30: await get_tree().physics_frame
	var steer1: float = gm.car._wheels[0].steering
	check(absf(steer1 - steer0) < 0.001,
		"wheels not steered by camera keys in photo mode (%.3f → %.3f)" % [steer0, steer1])
	check(gm.car.chassis.global_position.distance_to(pos0) < 0.01,
		"car does not creep in photo mode")
	_key(KEY_A)
	_key(KEY_W)

	# --- 4. посадка после трамплина на малой скорости не считается ударом ---
	gm._exit_photo()
	await get_tree().process_frame
	GameContext.select("sedan", "speedway")
	gm._respawn_now()
	for f in 10: await get_tree().physics_frame
	var impacts := 0
	gm.car.impact.connect(func(_s, _p, _n): impacts += 1)
	# разгон до ~35 км/ч и прыжок с трамплина: тормоз держим, чтобы скорость была малой
	Input.action_press("throttle")
	for f in 240:
		await get_tree().physics_frame
		if gm.car.chassis.linear_velocity.length() > 10.0: break
	Input.action_press("brake")   # газ отпускаем тормозом: скорость на кромке малая
	Input.action_release("throttle")
	for f in 600:
		await get_tree().physics_frame
		if gm.car.chassis.global_position.x > 400.0: break
	Input.action_release("brake")
	check(impacts == 0, "no impact counted on a low-speed ramp landing (%d)" % impacts)

	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
