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
			DirAccess.remove_absolute("user://settings.cfg")
			if fails == 0: print("ALL PASS")
			else: print("FAILS %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
