extends Node3D
# Photo mode: the world on pause, its own free camera, a hideable interface and a PNG on
# disk. There is no way to get a live pixel in headless (the engine draws nothing), so the
# frame capture is replaced by a stub and exactly what can be verified without a GPU is
# checked: the path, the name, the counter and the file bytes.
var _fails := 0
var gm: GameManager
var _f := 0
var _stage := 0
var _p: PhotoMode
var _car: CarRig
var _p0 := Vector3.ZERO
var _sim_at_entry := 0.0
var _disk_shots := 0
var _shots_at_stage := 0
var _disk_at_stage := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _act(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = StringName(name)
	e.pressed = true
	e.strength = 1.0
	return e

func _wheel(notch: int, ctrl: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if notch > 0 else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e

func _fake_shot(w: int) -> void:
	_p.look_fn = func() -> Image:
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.6, 0.9))
		return img

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	_p = gm.photo
	_car = gm.car

func _physics_process(_dt: float) -> void:
	_f += 1
	match _stage:
		0: _s_boot()
		1: _s_frozen()
		2: _s_camera()
		3: _s_shot()
		4: _s_exit()
		5: _s_numbering()
		_: pass

# ── 0. entry from the pause menu ─────────────────────────────────────────────────
func _s_boot() -> void:
	if _f < 30: return
	check(_p != null, "GameManager assembled the photo mode")
	Input.action_press("throttle")
	if _f < 90: return
	Input.action_release("throttle")
	gm._set_paused(true)
	var btn := gm.hud.pause_button("ФОТОМОД")
	check(btn != null, "the pause menu has the sixth row «ФОТОМОД»")
	if btn == null:
		_finish(); return
	btn.pressed.emit()
	_stage = 1
	_f = 0

# ── 1. the world stands still: physics moves the car by not even a micrometre ─────
func _s_frozen() -> void:
	if _f == 2:
		check(_p.active, "the photo mode opened")
		check(gm.is_frozen(), "the photo mode froze the world")
		check(_p.camera.current, "the photo mode camera became the current one")
		check(get_viewport().get_camera_3d() == _p.camera,
			"the viewport sees the photo mode camera, not the game one")
		check(gm.hud.photo_ui_visible(), "the photo mode strip is visible")
		check(not gm.hud._pause_panel.visible, "the pause card is hidden")
		_p0 = _car.chassis.global_position
		_sim_at_entry = gm.replay.sim_t
	if _f != 60: return
	var moved := _car.chassis.global_position.distance_to(_p0)
	check(moved < 1e-6,
		"over 58 physics ticks the car did not move by a single micrometre (%.7f m)" % moved)
	check(gm.replay.sim_t == _sim_at_entry,
		"the recorder stays silent during the photo-mode pause (%.3f vs %.3f)" % [gm.replay.sim_t, _sim_at_entry])
	_stage = 2
	_f = 0

# ── 2. free camera: yaw, pitch, step, zoom, view reset ────────────────────────────
func _s_camera() -> void:
	var cam := _p.camera
	if _f == 2:
		var yaw0 := cam.global_rotation.y
		var y0 := cam.global_position.y
		_p.look(200.0, 0.0)
		check(absf(cam.global_rotation.y - yaw0) > 0.3,
			"the mouse turns the camera yaw (%.3f rad of shift)" % absf(cam.global_rotation.y - yaw0))
		_p.look(0.0, 9000.0)
		check(absf(cam.global_rotation.x) <= PhotoMode.PITCH_LIMIT + 0.01,
			"the pitch does not flip over (%.3f against a ceiling of %.3f)" %
			[absf(cam.global_rotation.x), PhotoMode.PITCH_LIMIT])
		check(absf(absf(cam.global_rotation.x) - PhotoMode.PITCH_LIMIT) < 0.02,
			"the tilt does not go past the ceiling (%.3f vs %.3f)" %
			[absf(cam.global_rotation.x), PhotoMode.PITCH_LIMIT])
		_p.reset_view()
		check(cam.global_transform.origin.distance_to(gm.camera.global_transform.origin) < 1e-4,
			"«СБРОС ВИДА» returns the camera to where the game one stood")
		_p.sprint = true
		var w0 := cam.global_position
		_p.set_nav(0, 0, 1)
		_p.move_step(1.0)
		check(w0.distance_to(cam.global_position) > PhotoMode.MOVE_SPEED * PhotoMode.SPRINT * 0.9,
			"Shift speeds up the step (%.2f m per second)" % w0.distance_to(cam.global_position))
		_p.sprint = false
		var before := cam.global_position
		_p.set_nav(0, 0, 1)
		_p.move_step(1.0)
		check(before.distance_to(cam.global_position) > 1.0,
			"W steps forward along the camera yaw (%.2f m)" % before.distance_to(cam.global_position))
		var up0 := cam.global_position
		_p.set_nav(0, 1, 0)
		_p.move_step(1.0)
		check(cam.global_position.y > before.y + 1.0,
			"E lifts the camera up instead of forward (%.2f vs %.2f)" % [cam.global_position.y, before.y])
		var up_at := cam.global_position.y
		_p.set_nav(1, 0, 0)
		_p.move_step(1.0)
		check(absf(cam.global_position.y - up_at) < 1e-6,
			"D moves sideways and keeps the height (%.4f vs %.4f)" % [cam.global_position.y, up_at])
		var sideways := Vector2(cam.global_position.x, cam.global_position.z).distance_to(
			Vector2(up0.x, up0.z))
		check(absf(sideways - PhotoMode.MOVE_SPEED) < 0.2,
			"D travelled exactly MOVE_SPEED sideways (%.2f)" % sideways)
		_p.set_nav(0, 0, 0)
		check(cam.global_position.y != y0, "the camera really left the game height")
	if _f == 4:
		var f0 := cam.fov
		for i in 40: _p.zoom(PhotoMode.FOV_STEP)
		check(absf(cam.fov - PhotoMode.FOV_MAX) < 0.01,
			"zoom stops at the ceiling of %d° (%.1f)" % [int(PhotoMode.FOV_MAX), cam.fov])
		for i in 100: _p.zoom(-PhotoMode.FOV_STEP)
		check(absf(cam.fov - PhotoMode.FOV_MIN) < 0.01,
			"zoom does not drop under the minimum of %d° (%.1f)" % [int(PhotoMode.FOV_MIN), cam.fov])
		cam.fov = f0
		_p.fov = f0
		var wu := _wheel(1, false)
		var pos := cam.global_position
		_p._unhandled_input(wu)
		check(absf(cam.fov - f0) < 0.01, "the plain wheel does not change the angle (%.1f)" % cam.fov)
		check(absf(pos.distance_to(cam.global_position) - PhotoMode.DOLLY_STEP) < 1e-4,
			"the wheel dollies in by one step (%.2f m with a step of %.2f)" %
			[pos.distance_to(cam.global_position), PhotoMode.DOLLY_STEP])
		# the wheel arrives as a pair of events; the release must not move the camera
		var wu_off := _wheel(1, false)
		wu_off.pressed = false
		var parked := cam.global_position
		_p._unhandled_input(wu_off)
		check(cam.global_position.distance_to(parked) < 1e-6,
			"releasing the wheel moves nothing (%.4f m)" % cam.global_position.distance_to(parked))
		_p._unhandled_input(_wheel(1, true))
		check(absf(cam.fov - (f0 + PhotoMode.FOV_STEP)) < 0.01,
			"Ctrl+wheel widens the angle (%.1f vs %.1f)" % [cam.fov, f0 + PhotoMode.FOV_STEP])
		_p._unhandled_input(_wheel(-1, true))
		check(absf(cam.fov - f0) < 0.01,
			"Ctrl+wheel backwards restores the angle (%.1f vs %.1f)" % [cam.fov, f0])
		var zk := InputEventKey.new()
		zk.keycode = KEY_Z
		zk.pressed = true
		_p._unhandled_input(zk)
		check(absf(cam.fov - f0) < 0.01,
			"Z no longer zooms — the key is yielded to the game bindings (%.1f)" % cam.fov)
	if _f == 6:
		gm.hud.photo_button("БЕЗ HUD").pressed.emit()
	if _f == 8:
		check(_p.hud_off, "«БЕЗ HUD» toggled")
		var hidden := 0
		for c in gm.hud._gameplay:
			if not c.visible: hidden += 1
		check(hidden == gm.hud._gameplay.size(),
			"all gameplay panels are hidden (%d of %d)" % [hidden, gm.hud._gameplay.size()])
		check(not gm.hud.photo_ui_visible(), "and the photo mode strip is hidden")
		var f5 := InputEventKey.new()
		f5.keycode = KEY_F5
		f5.pressed = true
		_p._unhandled_input(f5)
	if _f == 10:
		check(not _p.hud_off, "F5 brings the interface back")
		var shown := 0
		for c in gm.hud._gameplay:
			if c.visible: shown += 1
		check(shown == gm.hud._gameplay.size(),
			"the interface came back in full (%d of %d)" % [shown, gm.hud._gameplay.size()])
		# a service key yields when the player put their own action on it
		var f5b := InputEventKey.new()
		f5b.keycode = KEY_F5
		f5b.pressed = true
		InputRouter.rebind("cam_cycle", f5b)
		_p._unhandled_input(f5b)
		check(not _p.hud_off,
			"F5 assigned to a game action does not hide the interface")
		InputRouter.reset_keys()
		_fake_shot(16)
		_p.hide_hud(true)
	if _f == 12:
		check(_p.hud_off, "the interface is hidden by hand («БЕЗ HUD»)")
		gm.hud.photo_button("СНИМОК").pressed.emit()
	if _f == 14:
		check(_p.hud_off,
			"the shot hides the interface for one frame and returns exactly what was there before it")
		var off := 0
		for c in gm.hud._gameplay:
			if not c.visible: off += 1
		check(off == gm.hud._gameplay.size(), "and the panels really are hidden (%d)" % off)
		_p.hide_hud(false)
		_stage = 3
		_f = 0


# ── 3. the shot: file, name, counter, absence of a live pixel ─────────────────────
func _s_shot() -> void:
	if _f == 2:
		_fake_shot(64)
		var before := _p.shots
		_shots_at_stage = before
		_disk_at_stage = _count_files()
		var p := _p.capture()
		check(_p.shots == before + 1, "the shot increased the counter (%d vs %d)" % [_p.shots, before + 1])
		check(p.begins_with("user://photos/photo_") and p.ends_with(".png"),
			"the shot path is in user://photos with a serial name (%s)" % p)
		var abs := ProjectSettings.globalize_path(p)
		check(FileAccess.file_exists(abs), "the PNG landed on disk (%s)" % abs)
		if FileAccess.file_exists(abs):
			var fa := FileAccess.open(abs, FileAccess.READ)
			var bytes := fa.get_length()
			var magic := fa.get_buffer(4)
			fa.close()
			check(bytes > 40, "the file is not empty (%d bytes)" % bytes)
			check(magic[0] == 0x89 and magic[1] == 0x50 and magic[2] == 0x4E and magic[3] == 0x47,
				"the first bytes are the PNG signature")
		var second := _p.capture()
		check(second != p, "the second shot does not overwrite the first (%s vs %s)" % [second, p])
		check(gm.hud._photo_info.text.contains(second.replace("user://", "")),
			"the strip caption updates from the write signal, not by waiting for a frame (%s)" %
			gm.hud._photo_info.text)
		# «СНИМОК» as a button: first it dims the interface, writes the frame on the next
		# process tick and returns the interface afterwards
		gm.hud.photo_button("СНИМОК").pressed.emit()
	if _f == 4:
		check(_p.shots == _shots_at_stage + 3,
			"the «СНИМОК» button added a frame (%d vs %d)" % [_p.shots, _shots_at_stage + 3])
		check(not _p.hud_off, "after the shot the interface came back")
		check(gm.hud.photo_ui_visible(), "after the shot the strip is visible again")
		_disk_shots = _count_files()
		check(_disk_shots == _disk_at_stage + 3,
			"the disk has three new shots: two by hand and one by button (%d vs %d)" %
			[_disk_shots, _disk_at_stage + 3])
		_p.look_fn = Callable()
		var got := _p.capture()
		if got == "":
			print("PARTIAL: headless does not give up the viewport texture — the live pixel was not checked")
		else:
			check(FileAccess.file_exists(ProjectSettings.globalize_path(got)),
				"the live capture still wrote a file (%s)" % got)
		_stage = 4
		_f = 0

func _count_files() -> int:
	var d := DirAccess.open("user://photos")
	if d == null: return -1
	var n := 0
	for f in d.get_files():
		if f.begins_with("photo_") and f.ends_with(".png"): n += 1
	return n

# ── 4. exit: the camera and the world come back ───────────────────────────────────
func _s_exit() -> void:
	if _f == 2:
		gm.hud.photo_button("ВЫХОД").pressed.emit()
	if _f == 4:
		check(not _p.active, "the exit closed the photo mode")
		check(not gm.is_frozen(), "the world unfroze")
		check(gm.camera.current, "the game camera is the current one again")
		check(get_viewport().get_camera_3d() == gm.camera, "the viewport returned to the game camera")
		check(not gm.hud.photo_ui_visible(), "the photo mode strip is hidden")
		var shown := 0
		for c in gm.hud._gameplay:
			if c.visible: shown += 1
		check(shown == gm.hud._gameplay.size(), "the interface is whole again (%d)" % shown)
		Input.action_press("throttle")
	if _f == 70:
		Input.action_release("throttle")
		check(_car.chassis.global_position.distance_to(_p0) > 0.5,
			"after the exit the car started driving (%.2f m)" % _car.chassis.global_position.distance_to(_p0))
		check(gm.replay.sim_t > _sim_at_entry,
			"the recorder writes again (%.2f vs %.2f)" % [gm.replay.sim_t, _sim_at_entry])
		gm._set_paused(true)
		gm.hud.pause_button("ФОТОМОД").pressed.emit()
	if _f == 74:
		gm._unhandled_input(_act("pause"))
	if _f == 76:
		check(not _p.active, "Esc exited the photo mode")
		check(not gm.is_frozen(), "after Esc the run goes on")
		_stage = 5
		_f = 0

# ── 5. numbering continues instead of starting over ────────────────────────────────
func _s_numbering() -> void:
	if _f == 4:
		_disk_shots = _count_files()
		check(_disk_shots >= 3, "the shots survive leaving the photo mode (%d)" % _disk_shots)
		gm._set_paused(true)
		gm.hud.pause_button("ФОТОМОД").pressed.emit()
	if _f == 8:
		check(_p.active, "the second entry into the photo mode opened")
		check(absf(_p.fov - gm.camera.fov) < 0.01,
			"entry takes the game camera's angle, not the previous zoom (%.1f vs %.1f)" %
			[_p.fov, gm.camera.fov])
		check(absf(_p.camera.fov - gm.camera.fov) < 0.01,
			"and sets it on its own camera right away (%.1f)" % _p.camera.fov)
		_fake_shot(8)
		var p := _p.capture()
		check(p.ends_with("photo_%04d.png" % (_disk_shots + 1)),
			"numbering continues from the number of files on disk (%s after %d shots)" % [p, _disk_shots])
		# «СНИМОК» writes the frame on the next tick; exiting before that tick has to
		# finish the shot instead of dropping it silently
		var shot_n := _p.shots
		var disk_n := _count_files()
		_p.shoot()
		gm._exit_photo()
		check(_p.shots == shot_n + 1,
			"leaving the photo mode finished the unwritten frame (%d vs %d)" % [_p.shots, shot_n + 1])
		check(_count_files() == disk_n + 1,
			"and it landed on disk (%d vs %d)" % [_count_files(), disk_n + 1])
		_finish()

func _finish() -> void:
	if _stage == 99: return
	_stage = 99
	Input.action_release("throttle")
	if gm != null and is_instance_valid(gm):
		if gm.photo != null and gm.photo.active: gm.photo.end()
		gm._set_paused(false)
		gm.queue_free()
	Settings.reset()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
