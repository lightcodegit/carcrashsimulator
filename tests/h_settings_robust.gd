extends Node
# Settings survive a hostile file, conflicting bindings are not duplicated, and a
# restart does not inherit pedal state. The parent case: one hand edit of
# settings.cfg aborted the load mid-way and every setting silently reset (verified
# on bool(Array) and String(dict)).
const PATH_CFG := "user://settings.cfg"
var _backup := ""
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(PATH_CFG):
		var f := FileAccess.open(PATH_CFG, FileAccess.READ)
		_backup = f.get_as_text()
	await _hostile_cfg()
	await _corrupt_cfg()
	await _oversized_cfg()
	await _crash_recovery()
	await _rebind_collision()
	await _pad_device()
	await _respawn_state()
	if _backup != "":
		var w := FileAccess.open(PATH_CFG, FileAccess.WRITE)
		w.store_string(_backup)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _write(text: String) -> void:
	var f := FileAccess.open(PATH_CFG, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _hostile_cfg() -> void:
	_write("[video]\nfog = [1, 2, 3]\nfov = {}\nscale = \"abc\"\npreset = -1\n" +
		"exposure = \"nan\"\nshadow_preset = Vector2(1,1)\n[window]\nw = 0\nh = 0\nmax = [true]\n" +
		"[keys]\nthrottle = {}\nbrake = 42\nnitro = [65, 66]\npause = \"k0\"\n")
	Settings.load_values()
	check(Settings.preset == 0, "preset out of range clamped to the bound (%d)" % Settings.preset)
	check(Settings.preset_name() != "", "preset name is readable (%s)" % Settings.preset_name())
	check(Settings.fov >= 60.0 and Settings.fov <= 120.0,
		"fov within sane bounds after garbage (%.1f)" % Settings.fov)
	check(Settings.scale >= 0.5 and Settings.scale <= 1.0,
		"scale within sane bounds after garbage (%.2f)" % Settings.scale)
	# NaN in the file would poison every later boot: the string "nan" is not a number,
	# and clampf already drops the non-finite value past the bounds.
	check(is_finite(Settings.exposure), "exposure stayed finite (%.2f)" % Settings.exposure)
	check(typeof(Settings.fog) == TYPE_BOOL, "bool key stayed bool (%s)" % typeof(Settings.fog))
	# binds from broken strings are not read, but not lost either: the action keeps its default
	var th := InputMap.action_get_events("throttle")
	check(th.size() > 0, "throttle kept a bind after {} in the file (%d)" % th.size())
	var br := InputMap.action_get_events("brake")
	check(br.size() > 0, "brake kept a bind after a number in the file (%d)" % br.size())
	# "pause = k0": physical code 0 cannot be pressed. If such a bind were accepted, the
	# action would be left with no event, and pause in a run opens only by key.
	var pz := InputMap.action_get_events("pause")
	check(pz.size() > 0, "pause did not stay unbound after k0 (%d)" % pz.size())
	var pz_ok := false
	for e in pz:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
			pz_ok = true
	check(pz_ok, "pause returned to ESC after k0")
	check(not Settings._win_ok(Rect2i(0, 0, 2000000000, 2000000000)),
		"absurd window size fails the check")
	# Window geometry: returning the window to the screen. The check is synthetic, not via
	# DisplayServer: in headless the screen reads as 0x0, a live call would prove nothing and
	# would instead catch its own clamp bug.
	var one := Rect2i(0, 0, 1920, 1080)
	var win := Vector2i(1600, 900)
	check(Settings._clamp_pos(Vector2i(120, 80), win, one) == Vector2i(120, 80),
		"a visible position is not moved")
	var back := Settings._clamp_pos(Vector2i(-90000, -90000), win, one)
	check(back.x == -1440 and back.y == 0,
		"a window that flew off up-left returns with 160 px on screen (%s)" % str(back))
	var fwd := Settings._clamp_pos(Vector2i(5000, 5000), win, one)
	check(fwd.x == 1760 and fwd.y == 920,
		"a window that flew off down-right returns (%s)" % str(fwd))
	# Second monitor on the left: negative coordinates are a normal place; the window must
	# not be dragged to the primary screen on every start.
	var left := Rect2i(-1920, 0, 3840, 1080)
	check(Settings._clamp_pos(Vector2i(-1900, 10), win, left) == Vector2i(-1900, 10),
		"a window on the left monitor stays on the left monitor")
	# Window geometry: zero in the file is not a size, it is garbage. Worse, in headless the
	# engine itself reports a 0x0 window, and polling the window in a test run would wipe the
	# real player settings (w=0 h=0 appearing in user://settings.cfg).
	check(Settings._win_ok(Settings._win_rect),
		"a zero size from the file did not enter the geometry (%s)" % str(Settings._win_rect.size))
	# Force the corrupted geometry and require save() to patch it: exactly this zero turns the
	# window into a grey field with a thin strip of UI.
	Settings._win_rect = Rect2i(0, 0, 0, 0)
	Settings.save()
	var cf := ConfigFile.new()
	check(cf.load(PATH_CFG) == OK, "the settings file reloads after save")
	var saved_w := int(cf.get_value("window", "w", 0))
	var saved_h := int(cf.get_value("window", "h", 0))
	check(saved_w >= Settings.WIN_MIN.x and saved_h >= Settings.WIN_MIN.y,
		"a meaningful window size was written to the file (%dx%d)" % [saved_w, saved_h])
	Settings.reset()

func _corrupt_cfg() -> void:
	# A syntactically broken file (unterminated array) is the one case where the game must
	# keep a copy: without it the next save silently wipes binds and settings.
	var bad := "user://settings.cfg.bad"
	if FileAccess.file_exists(bad): DirAccess.remove_absolute(bad)
	_write("[video]\nfog = [1, 2\n")
	Settings.load_values()
	check(FileAccess.file_exists(bad), "a broken settings.cfg is kept as a .bad copy")
	if FileAccess.file_exists(bad): DirAccess.remove_absolute(bad)

func _oversized_cfg() -> void:
	# The ConfigFile parser is single-threaded: a log-sized file would halt startup. Such a
	# file is garbage and must not be read: a .bad copy and life on the current values.
	var junk := "[video]\n"
	while junk.length() < Settings.CFG_MAX_BYTES + 4096:
		junk += "filler_%d = 1\n" % junk.length()
	_write(junk)
	Settings.set_value("fov", 99.0, false)
	Settings.load_values()
	check(is_equal_approx(Settings.fov, 99.0),
		"an oversized file is not reloaded (%.1f)" % Settings.fov)
	check(FileAccess.file_exists("user://settings.cfg.bad"), "an oversized file was stashed to .bad")
	if FileAccess.file_exists("user://settings.cfg.bad"):
		DirAccess.remove_absolute("user://settings.cfg.bad")
	# atomic write: neither the draft nor the shadow of the previous file should survive save
	Settings.save()
	check(not FileAccess.file_exists("user://settings.cfg.part"),
		"no .part draft remained after save")
	check(not FileAccess.file_exists("user://settings.cfg.old"),
		"no .old shadow of the previous file remained after save")
	var after := ConfigFile.new()
	check(after.load(PATH_CFG) == OK, "the file reads after the atomic replace")

func _crash_recovery() -> void:
	# State after the process dies in the window "the target moved to .old, the draft not yet
	# in place": settings.cfg is gone, the only copy is the shadow. The first save of that run
	# used to delete .old as a leftover and wipe the settings for good.
	_write("[video]\nfov = 92.0\n")
	Settings.load_values()
	var saved := Settings.fov
	check(is_equal_approx(saved, 92.0), "the file was read before simulating the crash (%.1f)" % saved)
	check(DirAccess.rename_absolute(PATH_CFG, "user://settings.cfg.old") == OK,
		"simulation: the target moved to the shadow")
	check(not FileAccess.file_exists(PATH_CFG), "simulation: settings.cfg is absent")
	Settings.load_values()
	check(FileAccess.file_exists(PATH_CFG), "the .old shadow restored settings.cfg in place")
	check(is_equal_approx(Settings.fov, saved),
		"the restored values are intact (%.1f vs %.1f)" % [Settings.fov, saved])
	check(not FileAccess.file_exists("user://settings.cfg.old"),
		"recovery left no dangling shadow")

func _rebind_collision() -> void:
	# conflict of two player-ASSIGNED binds: the second takes the key from the first
	var k1 := InputEventKey.new(); k1.physical_keycode = KEY_G
	var k2 := InputEventKey.new(); k2.physical_keycode = KEY_G
	InputRouter.rebind("throttle", k1)
	InputRouter.rebind("brake", k2)
	var has_g := func(action: String) -> bool:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_G:
				return true
		return false
	check(has_g.call("brake"), "G assigned to brake")
	check(not has_g.call("throttle"),
		"G removed from throttle: two player bindings do not share one key")
	# a default conflict remains possible (the class-substitution model does not express
	# "there are no keys"), so we only check that the previous behavior is intact: the new
	# binding is accepted, the key class is replaced by one event
	var w := InputEventKey.new(); w.physical_keycode = KEY_H
	InputRouter.rebind("handbrake", w)
	var hk := 0
	for e in InputMap.action_get_events("handbrake"):
		if e is InputEventKey:
			hk += 1
			check((e as InputEventKey).physical_keycode == KEY_H,
				"only the assigned key remains on handbrake")
	check(hk == 1, "a binding over a default replaced the key class (%d)" % hk)
	InputRouter.clear_binding("throttle")
	InputRouter.clear_binding("brake")
	InputRouter.clear_binding("handbrake")

func _pad_device() -> void:
	# device must survive a restart. Without it a bind became "any gamepad" after restart,
	# though in the same run it belonged to a specific one.
	var jb := InputEventJoypadButton.new()
	jb.button_index = 3
	jb.device = 1
	InputRouter.rebind("throttle", jb)
	Settings.save()
	var cf := ConfigFile.new()
	check(cf.load(PATH_CFG) == OK, "the file reads after the gamepad binding")
	var tok := String(cf.get_value("keys", "throttle", ""))
	check(tok.contains("@1"), "the gamepad number was written to the file (%s)" % tok)
	InputRouter.reset_keys()
	Settings.load_values()
	var found := false
	for e in InputMap.action_get_events("throttle"):
		if e is InputEventJoypadButton and e.button_index == 3 and e.device == 1:
			found = true
	check(found, "the binding came back with the same gamepad (%s)" % str(InputMap.action_get_events("throttle")))
	# the old format must read as "any", otherwise the player's file loses binds
	var legacy: InputEventJoypadButton = InputRouter._decode("b3")
	check(legacy != null and legacy.device == -1,
		"an old token without device reads as any gamepad")
	var modern: InputEventJoypadMotion = InputRouter._decode("a0_50@2")
	check(modern != null and modern.device == 2 and is_equal_approx(modern.axis_value, 0.5),
		"an axis with a gamepad number reads whole")
	# the token could be mangled by a hand edit of the file; a bind to a nonexistent button
	# shows in settings as "BUTTON 999" and is never pressable
	for bad in ["b", "k0", "k-3", "kabc", "b-1", "bXX", "b1000", "a-1_50", "a1000_50",
			"a0_5000", "a0_ab", "a0", "b3@-2", "b3@x", "q0_50"]:
		check(InputRouter._decode(bad) == null, "garbage token %s does not become a bind" % bad)
	check(InputRouter._decode("b%d" % (InputRouter.BUTTON_MAX + 1)) == null,
		"a button past the token bound does not become a bind")
	var last_button: InputEventJoypadButton = InputRouter._decode("b%d" % InputRouter.BUTTON_MAX)
	check(last_button != null and last_button.button_index == InputRouter.BUTTON_MAX,
		"the last legal button reads (%s)" % str(last_button))
	var neg: InputEventJoypadMotion = InputEventJoypadMotion.new()
	neg.axis = 1
	neg.axis_value = -0.5
	neg.device = 0
	check(InputRouter._decode(InputRouter._encode(neg)) != null,
		"a negative axis value survives write and read")
	InputRouter.clear_binding("throttle")
	InputRouter.reset_keys()

func _respawn_state() -> void:
	GameContext.select("sedan", "arena")
	var g: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 10:
		await get_tree().physics_frame
	var car := g.car
	car.chassis.linear_velocity = Vector3.ZERO
	Input.action_press("brake")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("brake")
	check(car._rev_lag > 0.0, "on a braking car the reverse lag accumulated (%.2f)" % car._rev_lag)
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	check(is_equal_approx(car._rev_lag, 0.0) and is_equal_approx(car._hand_pedal, 0.0),
		"restart zeroed the lag and the handbrake pressure (%.2f / %.2f)" % [car._rev_lag, car._hand_pedal])
	g.queue_free()
	for i in 6:
		await get_tree().physics_frame
