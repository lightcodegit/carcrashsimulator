extends Node3D
# Рестарт возвращает сбитые предметы на место: иначе за несколько заездов трасса
# загружается обломками, и машина может родиться внутри конуса.
var _fails := 0
var gm: GameManager

# Нижняя грань визуального меша предмета в мировых координатах.
# [погружено, максимальная вертикальная скорость] для всех сбиваемых предметов карты.
func _seating(id: String) -> Array[float]:
	GameContext.select("sedan", id)
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	await get_tree().physics_frame
	var bottoms := {}
	var surfs := {}
	for p in get_tree().get_nodes_in_group(LooseProp.GROUP):
		var n := p as Node3D
		bottoms[n] = _aabb(n).position.y
		surfs[n] = MapDB.surface_y(n.global_position.x, n.global_position.z)
	var hop := 0.0
	for t in 60:
		await get_tree().physics_frame
		for n in bottoms:
			if is_instance_valid(n): hop = maxf(hop, absf((n as RigidBody3D).linear_velocity.y))
	var sunk := 0
	for n in bottoms:
		if is_instance_valid(n) and _aabb(n).position.y < float(surfs[n]) - 0.004: sunk += 1
	g.queue_free()
	# четыре кадра: тела должны уйти из физического пространства до сборки следующей
	# карты, иначе её предметы толкаются с чужими
	for i in 4:
		await get_tree().physics_frame
	return [float(sunk), hop, float(bottoms.size())]

func _aabb(n: Node3D) -> AABB:
	var m := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var g: AABB = mi.global_transform * mi.get_aabb()
			if first: m = g; first = false
			else: m = m.merge(g)
		for k in c.get_children(): stack.append(k)
	return m

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	# Посадка по всем картам и ДО создания собственного заезда: два мира с предметами
	# в одной сцене начали бы толкаться, и проверка ловила бы не посадку, а это.
	# На трассе у этого бага свой случай: предмет стоит одним концом на асфальте,
	# другим на полу, и solver выталкивает его на старте заезда.
	for id in ["arena", "town", "speedway"]:
		var seats := await _seating(id)
		check(seats[2] > 4, "%s: предметов для проверки найдено %d" % [id, int(seats[2])])
		check(seats[0] == 0, "%s: ни один предмет не погружен в поверхность (%d)" % [id, int(seats[0])])
		check(seats[1] < 0.60, "%s: на старте заезда предметы не подпрыгивают (vy=%.2f)" % [id, seats[1]])
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

	# Посадка: после рестарта предметы снова на своих местах, и каждый стоит НА
	# поверхности, а не внутри неё. Погруженный предмет solver выталкивает, и конусы
	# запрыгают по всей трассе прямо на старте заезда.
	var sunk := 0
	var hop := 0.0
	for i in props.size():
		var n := props[i] as Node3D
		var bottom := _aabb(n).position.y
		var surf := MapDB.surface_y(n.global_position.x, n.global_position.z)
		var home_surf := MapDB.surface_y(home[i].origin.x, home[i].origin.z)
		if bottom < home_surf - 0.004: sunk += 1
		hop = maxf(hop, absf((props[i] as RigidBody3D).linear_velocity.y))
	check(sunk == 0, "ни один предмет не погрузился в поверхность (%d)" % sunk)
	for i in 20:
		await get_tree().physics_frame
		for p in props:
			hop = maxf(hop, absf((p as RigidBody3D).linear_velocity.y))
	check(hop < 0.60, "предметы не подпрыгивают на старте (макс. vy=%.2f м/с)" % hop)
	var pos := gm.car.chassis.global_position
	check(pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)) < 0.8,
		"машина стартовала там, где её поставили (%.2f м)" % pos.distance_to(Vector3(gm._spawn.origin.x, pos.y, gm._spawn.origin.z)))
	check(gm.car.chassis.linear_velocity.length() < 0.5,
		"машину не выталкивает и не разгоняет (%.2f м/с)" % gm.car.chassis.linear_velocity.length())
	check(gm.car.body.dent_count == 0, "рестарт починил кузов")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
