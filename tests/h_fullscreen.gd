extends Node
# Fullscreen must return the window exactly where it was: the size and position
# the window had AT THE MOMENT of entering fullscreen, not what a frame poll
# remembered a couple of seconds ago.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): window modes cannot be checked without a live window")
		print("ALL PASS")
		get_tree().quit(0)
		return
	var start := get_window().size
	var start_pos := get_window().position
	print("initial window %s at %s" % [str(start), str(start_pos)])

	# 1) resize, wait until the OS actually applies it
	DisplayServer.window_set_size(Vector2i(1100, 640))
	await _stable_size()
	var want := get_window().size
	check(want == Vector2i(1100, 640), "resize applied (%s)" % str(want))

	# 2) fullscreen and back
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"fullscreen engaged (mode=%d)" % DisplayServer.window_get_mode())
	Settings.set_value("fullscreen", false)
	await get_tree().create_timer(0.5).timeout
	var back := get_window().size
	check(back == want,
		"the size after leaving fullscreen is the same (%s instead of %s)" % [str(back), str(want)])

	# 3) the same after a second resize: the old value must not "win"
	DisplayServer.window_set_size(Vector2i(900, 600))
	await _stable_size()
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	Settings.set_value("fullscreen", false)
	await get_tree().create_timer(0.5).timeout
	var back2 := get_window().size
	check(back2 == Vector2i(900, 600),
		"the second fullscreen cycle returns 900x600, not %s" % str(back2))

	# 4) race: resize and immediately fullscreen without waiting for a frame poll. That is
	# exactly how the size gets lost: _win_rect updates once per frame, the OS applies the
	# resize asynchronously, and leaving fullscreen restores a stale rectangle.
	DisplayServer.window_set_size(Vector2i(1280, 760))
	Settings.set_value("fullscreen", true)
	await get_tree().create_timer(0.5).timeout
	Settings.set_value("fullscreen", false)
	await _stable_size()
	var raced := get_window().size
	check(absi(raced.x - 1280) <= 2 and absi(raced.y - 760) <= 2,
		"fullscreen right after a resize does not eat it (%s instead of 1280x760)" % str(raced))

	DisplayServer.window_set_size(start)
	DisplayServer.window_set_position(start_pos)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Wait until the size stops changing: window_set_size reaches the OS asynchronously.
func _stable_size() -> void:
	var last := Vector2i(-1, -1)
	var same := 0
	while same < 6:
		await get_tree().process_frame
		var now := get_window().size
		same = same + 1 if now == last else 0
		last = now
