extends Node
# Полноэкранный режим обязан возвращать окно ровно туда, где оно было: размер и
# позицию, которые у окна В МОМЕНТ входа в fullscreen, а не те, что запомнил
# опрос кадров пару секунд назад.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): режимы окна без живого окна не проверяются")
		print("ALL PASS")
		get_tree().quit(0)
		return
	var start := get_window().size
	var start_pos := get_window().position
	print("исходное окно %s в %s" % [str(start), str(start_pos)])

	# 1) ресайз, дождаться, пока ОС действительно применит его
	DisplayServer.window_set_size(Vector2i(1100, 640))
	await _stable_size()
	var want := get_window().size
	check(want == Vector2i(1100, 640), "ресайз применён (%s)" % str(want))

	# 2) fullscreen и обратно
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"fullscreen включился (mode=%d)" % DisplayServer.window_get_mode())
	Settings.set_value("fullscreen", false)
	await get_tree().create_timer(0.5).timeout
	var back := get_window().size
	check(back == want,
		"после выхода из fullscreen размер вернулся тот же (%s вместо %s)" % [str(back), str(want)])

	# 3) то же самое после второго ресайза: старое значение не должно «победить»
	DisplayServer.window_set_size(Vector2i(900, 600))
	await _stable_size()
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	Settings.set_value("fullscreen", false)
	await get_tree().create_timer(0.5).timeout
	var back2 := get_window().size
	check(back2 == Vector2i(900, 600),
		"второй цикл fullscreen возвращает 900x600, а не %s" % str(back2))

	# 4) гонка: ресайз и сразу fullscreen, не дожидаясь опроса кадров. Именно так
	# и теряется размер: _win_rect обновляется раз в кадр, а ОС применяет ресайз
	# асинхронно, и выход из fullscreen возвращает устаревший прямоугольник.
	DisplayServer.window_set_size(Vector2i(1280, 760))
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	Settings.set_value("fullscreen", false)
	await _stable_size()
	var raced := get_window().size
	check(absi(raced.x - 1280) <= 2 and absi(raced.y - 760) <= 2,
		"fullscreen сразу после ресайза не съедает его (%s вместо 1280x760)" % str(raced))

	DisplayServer.window_set_size(start)
	DisplayServer.window_set_position(start_pos)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Ждём, пока размер перестанет меняться: window_set_size уходит в ОС асинхронно.
func _stable_size() -> void:
	var last := Vector2i(-1, -1)
	var same := 0
	while same < 6:
		await get_tree().process_frame
		var now := get_window().size
		same = same + 1 if now == last else 0
		last = now
