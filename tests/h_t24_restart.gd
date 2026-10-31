extends Node3D
# Рестарт возвращает сбитые предметы на место: иначе за несколько заездов трасса
# загружается обломками, и машина может родиться внутри конуса.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for i in 30:
		await get_tree().physics_frame
	var props: Array = get_tree().get_nodes_in_group(LooseProp.GROUP)
	check(props.size() > 5, "на арене есть что сбить (%d)" % props.size())
	var home: Array[Transform3D] = []
	for p in props: home.append((p as Node3D).global_transform)
	# разбрасываем предметы: один ставим ровно на спавн машины, остальные уносим в стороны
	for i in props.size():
		var n := props[i] as Node3D
		n.global_position = gm._spawn.origin + (Vector3(0, 0.4, 0) if i == 0 else Vector3(6 + i, 0.4, 3 * (i % 3)))
		n.linear_velocity = Vector3.ZERO
	await get_tree().physics_frame
	var before: Vector3 = (props[0] as Node3D).global_position
	check(before.distance_to(gm._spawn.origin) < 1.0, "предмет стоит на спавне (%.2f м)" % before.distance_to(gm._spawn.origin))
	gm._respawn_now()
	for i in 12:
		await get_tree().physics_frame
	var back := 0
	for i in props.size():
		if (props[i] as Node3D).global_transform.origin.distance_to(home[i].origin) < 0.30: back += 1
	check(back == props.size(), "предметы вернулись домой (%d из %d)" % [back, props.size()])
	var pos := gm.car.chassis.global_position
	check(pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)) < 0.8,
		"машина стартовала там, где её поставили (%.2f м)" % pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)))
	check(gm.car.chassis.linear_velocity.length() < 0.5,
		"машину не выталкивает и не разгоняет (%.2f м/с)" % gm.car.chassis.linear_velocity.length())
	check(gm.car.body.dent_count == 0, "рестарт починил кузов")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
