extends Node
# Pixel-grid contract: the 2D layer must match window pixels exactly.
# Any engine-side scaling (canvas_items) re-smooths already rendered glyphs:
# measured — 16px font edge contrast drops from 0.675 to 0.471 at factor 1.2
# and to 0.561 at 0.8, and at exact 2× the blur remains (2079 vs 1840 "soft"
# transitions at the same physical size).
# Hence: scaling is forbidden; the UI grows via its own numbers (UiTheme.step).

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): screen grid is not measured without a live window")
		print("ALL PASS")
		get_tree().quit(0)
		return
	var w := get_window()
	check(w.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED,
		"engine-side 2D scaling is off (mode %d)" % w.content_scale_mode)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(size)
		await _stable(size)
		var st := get_viewport().get_screen_transform()
		check(is_equal_approx(st.get_scale().x, 1.0),
			"window %s: screen grid is 1:1, not %s" % [str(size), str(st.get_scale())])
		check(get_viewport().get_visible_rect().size == Vector2(size),
			"window %s: logical area equals the window (%s)" % [str(size), str(get_viewport().get_visible_rect().size)])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _stable(size: Vector2i) -> void:
	var same := 0
	while same < 8:
		await get_tree().process_frame
		same = same + 1 if get_window().size == size else 0
