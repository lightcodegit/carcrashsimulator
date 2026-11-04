extends Node
# Контракт пиксельной сетки: 2D-слой обязан совпадать с пикселями окна.
# Любое масштабирование движком (canvas_items) передёргивает уже отрисованные
# глифы: замерено — контраст края шрифта 16px падает с 0.675 до 0.471 при
# коэффициенте 1.2 и до 0.561 при 0.8, а при точных 2× мыло остаётся
# (2079 против 1840 «мягких» переходов на одном и том же физическом размере).
# Отсюда — растяжение запрещено, интерфейс растёт самими числами (UiTheme.step).

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): экранная сетка без живого окна не измеряется")
		print("ALL PASS")
		get_tree().quit(0)
		return
	var w := get_window()
	check(w.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED,
		"движковое растяжение 2D выключено (режим %d)" % w.content_scale_mode)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(size)
		await _stable(size)
		var st := get_viewport().get_screen_transform()
		check(is_equal_approx(st.get_scale().x, 1.0),
			"окно %s: экранная сетка 1:1, а не %s" % [str(size), str(st.get_scale())])
		check(get_viewport().get_visible_rect().size == Vector2(size),
			"окно %s: логическая область равна окну (%s)" % [str(size), str(get_viewport().get_visible_rect().size)])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _stable(size: Vector2i) -> void:
	var same := 0
	while same < 8:
		await get_tree().process_frame
		same = same + 1 if get_window().size == size else 0
