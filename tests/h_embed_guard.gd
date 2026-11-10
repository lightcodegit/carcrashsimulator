extends Node

# Embedded-run contract: while the editor owns the window, the game has no right
# to impose geometry on it or to remember its rectangle. The second point is the same
# hole that used to produce the "grey window": a size taken from the editor panel goes
# into cfg and becomes the player's window size on the next standalone start.
# MUST run with --wid <host window handle> (see tests/p_embed_host.tscn).

const SEEDED := Rect2i(100, 120, 1280, 720)

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		print("SKIP (headless): a foreign window cannot exist without a live window")
		print("ALL PASS")
		get_tree().quit(0)
		return
	if not Engine.is_embedded_in_editor():
		print("FAIL: test started without --wid: the game owns the window, nothing to check")
		print("FAILS 1")
		get_tree().quit(1)
		return
	_seed(SEEDED)
	Settings.load_values()
	check(Settings._win_rect == SEEDED, "after load we still remember the seeded rectangle (%s)" % str(Settings._win_rect))

	# Wait longer than the write debounce (500 ms): by then _capture_window on broken
	# code has time to grab the geometry from the panel and queue a save().
	await get_tree().create_timer(1.2).timeout
	check(Settings._win_rect == SEEDED,
		"editor geometry did not leak into memory (%s instead of %s)" % [str(Settings._win_rect), str(SEEDED)])
	var on_disk := _read_window()
	check(on_disk == SEEDED,
		"cfg not overwritten by a foreign window (%s instead of %s)" % [str(on_disk), str(SEEDED)])
	# The guard check itself runs last: on broken code the behaviours must fail
	# loudly first, not just a call to a nonexistent function.
	check(not Settings.owns_window(), "the window is the editor's — the guard must recognise it")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _seed(r: Rect2i) -> void:
	Settings.save()
	var cf := ConfigFile.new()
	if cf.load(Settings.FILE) != OK:
		check(false, "cfg read for seeding [window]")
		return
	cf.set_value(Settings.WIN_SECTION, "x", r.position.x)
	cf.set_value(Settings.WIN_SECTION, "y", r.position.y)
	cf.set_value(Settings.WIN_SECTION, "w", r.size.x)
	cf.set_value(Settings.WIN_SECTION, "h", r.size.y)
	cf.set_value(Settings.WIN_SECTION, "max", false)
	if cf.save(Settings.FILE) != OK:
		check(false, "cfg written with the seeded geometry")

func _read_window() -> Rect2i:
	var cf := ConfigFile.new()
	if cf.load(Settings.FILE) != OK:
		return Rect2i(-1, -1, -1, -1)
	return Rect2i(int(cf.get_value(Settings.WIN_SECTION, "x", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "y", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "w", -1)),
		int(cf.get_value(Settings.WIN_SECTION, "h", -1)))
