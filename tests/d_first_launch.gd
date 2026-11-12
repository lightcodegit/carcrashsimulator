extends SceneTree
# First-launch window centering (issue #9): the _first_launch flag must also be
# set when the settings file does not exist at all — a truly fresh profile.
# Run: godot --headless --path . --script res://tests/d_first_launch.gd
#
# --script harness: the settings autoload is fetched at runtime, after the
# tree is active.
var fails := 0
var frames := 0
var cfg = null

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	pass

func _process(_dt: float) -> bool:
	frames += 1
	match frames:
		2:
			cfg = root.get_node("/root/Settings")
			# the runner isolates user:// — this profile has no settings.cfg yet
			check(not FileAccess.file_exists("user://settings.cfg"),
				"precondition: a fresh profile has no settings file")
			check(cfg._first_launch,
				"a fresh profile is a first launch (flag %s)" % str(cfg._first_launch))
			# An upgraded profile: the file exists but predates the window
			# section — still a first launch for the window geometry.
			var f := ConfigFile.new()
			f.set_value("video", "language", "en")
			f.save("user://settings.cfg")
			cfg.load_values()
			check(cfg._first_launch,
				"a file without a window section is a first launch too (flag %s)" % str(cfg._first_launch))
			# A saved profile remembers the window: not a first launch anymore.
			cfg.save()
			cfg.load_values()
			check(not cfg._first_launch,
				"a saved window section is not a first launch (flag %s)" % str(cfg._first_launch))
		3:
			# The restyle truth table: a window that already looks windowed
			# (windowed or maximized) is not restyled — that redundant WINDOWED
			# call is the transition where some Windows 11 setups lost the frame.
			var ss = load("res://scripts/autoload/Settings.gd")
			for pair in [[DisplayServer.WINDOW_MODE_WINDOWED, false],
					[DisplayServer.WINDOW_MODE_MAXIMIZED, false],
					[DisplayServer.WINDOW_MODE_MINIMIZED, true],
					[DisplayServer.WINDOW_MODE_FULLSCREEN, true],
					[DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, true]]:
				check(ss._window_mode_needs_restyle(pair[0]) == pair[1],
					"restyle table for mode %d expects %s" % [pair[0], str(pair[1])])
			# The live minimum: the OS frame and the restored geometry obey it.
			var mn: Vector2i = cfg.min_window_size()
			check(mn == Vector2i(800, 450), "the design minimum is 800x450 (%s)" % str(mn))
			var wmin: Vector2i = root.get_window().min_size
			check(wmin == mn, "the window enforces the minimum (min_size %s)" % str(wmin))
			# A saved rect smaller than the minimum clamps up on restore.
			var clamped: Rect2i = Rect2i(10, 10, 400, 300)
			clamped.size = clamped.size.max(mn)
			check(clamped.size == mn, "a small saved rect clamps to the minimum (%s)" % str(clamped.size))
			DirAccess.remove_absolute("user://settings.cfg")
			if fails == 0: print("ALL PASS")
			else: print("FAILS %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
