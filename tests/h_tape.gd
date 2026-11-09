extends Node3D
# Лента реплея на диске: сохранение после заезда, отказ чужой карте,
# приём живым рекордером и проигрывание принятой ленты с вмятинами.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 200: await get_tree().physics_frame   # кольцо набирает кадры (~10 сэмплов)

	# удар: детектор мог бы его не поймать — для теста пишем событие напрямую
	gm.replay._on_impact(90.0, gm.car.chassis.global_position, Vector3(1, 0, 0))
	for f in 5: await get_tree().physics_frame   # сэмпл кольца догоняет событие удара
	var dents0: int = gm.replay.dents.size()
	check(dents0 == 1, "удар попал в ленту (%d)" % dents0)

	var path := ReplayRecorder.replay_path("arena")
	check(gm.replay.save_to(path), "лента сохранена на диск")
	check(ReplayRecorder.has_tape("arena"), "has_tape видит сохранённую ленту")
	check(not ReplayRecorder.has_tape("town"), "чужой карте ленты нет")
	var tape := ReplayRecorder.tape_at(path)
	check(not tape.is_empty() and tape.get("map", "") == "arena", "лента читается и помнит карту")

	# чужая карта не принимает ленту: индексы предметов той раскладки не имеют смысла
	var gm2: GameManager = load("res://scenes/game.tscn").instantiate()
	gm2.name = "GM2"
	add_child(gm2)
	var wrong := tape.duplicate(); wrong["map"] = "town"
	check(not gm2.replay.adopt_tape(wrong), "лента другой карты не принимается")

	# та же карта: приём и проигрывание с вмятинами
	check(gm2.replay.adopt_tape(tape), "лента той же карты принята")
	check(gm2.replay.count() == (tape["frames"] as Array).size(), "кадры принятой ленты на месте")
	gm2.replay_player.setup(gm2.replay, gm2.car, gm2)
	gm2.replay_player.begin_default()
	gm2.replay_player.seek(gm2.replay.window_end())
	gm2.car.body.apply_impact_local(Vector3(0, 0, 1.5), Vector3(0, 0, -1), 120.0)
	await get_tree().process_frame
	check(gm2.car.body.dent_count >= 1, "вмятины принятой ленты на кузове (%d)" % gm2.car.body.dent_count)
	gm2.replay_player.end()

	if _fails == 0: print("ALL PASS")
	else: print("FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
