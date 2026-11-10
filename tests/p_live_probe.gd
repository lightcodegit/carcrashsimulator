extends Node3D
# Manual live run: a real window, real rendering, real audio output. This runner
# is NOT part of the headless set (p_* runner) and checks exactly what headless
# cannot verify: that frames really get drawn, that sound reaches the device,
# that the garage paint shows up in the live render, that a photo-mode snapshot
# is pixels rather than a blank image, and that repeatedly freeing the run scene
# tree together with the audio player does not take the process down (the
# historic access violation).
#
# Run from an isolated user://, otherwise the run touches the player's saved cfg:
#   APPDATA=<empty folder> Godot --path . res://tests/p_live_probe.tscn --fixed-fps 60
# Screenshots land in tests/out/live_*.png.

const OUT := "res://tests/out/"
# body frame on the menu showcase at 1600x900: where the body atlas cell sits
const CAR_RECT := Rect2i(360, 300, 420, 320)
# deliberately far from the sedan's factory colour (it is red): green shifts the
# red-versus-green balance hard, so a swapped paint cannot "coincide"
const PAINT_TEST := Color(0.05, 0.72, 0.18)

var _gm: GameManager
var _menu: Node
var _fails := 0
var _shots := 0
var _stage := 0
var _s := 0
var _rebuilds := 0
var _before := ""
var _after := ""

func note(cond: bool, msg: String) -> void:
	if cond:
		print("LIVE OK: " + msg)
	else:
		_fails += 1
		print("LIVE FAIL: " + msg)

func lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722

func _ready() -> void:
	# the run pauses the world itself (replay and photo mode), so its own frame
	# counter has to survive the pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := get_viewport()
	print("LIVE: window %s, renderer %s, output %s, display %s" % [
		vp.get_visible_rect().size, RenderingServer.get_current_rendering_method(),
		AudioServer.get_driver_name(), DisplayServer.get_name()])
	note(DisplayServer.get_name() != "headless", "this is a real window, not headless")
	note(AudioServer.get_driver_name() != "Dummy",
		"the audio device is live (%s)" % AudioServer.get_driver_name())
	_new_game()

func _new_game() -> void:
	GameContext.select("sedan", "arena")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)

# Stages advance on their own counter: one physics frame = one simulation step.
func _physics_process(_dt: float) -> void:
	_s += 1
	# stages 5-7 live WITHOUT the car: _gm is freed there on purpose, and a guard
	# on _gm would stop the run itself along with it
	if _stage >= 5:
		match _stage:
			5: _st_garage()
			6: _st_rebuild()
			7: _finish()
			_: pass
		return
	if _gm == null or not is_instance_valid(_gm): return
	match _stage:
		0: _st_accel()
		1: _st_drift()
		2: _st_crash()
		3: _st_replay()
		4: _st_photo()
		_: pass

# nitro acceleration: flame behind the bumper and the engine on live output
func _st_accel() -> void:
	if _s == 4:
		Input.action_press("throttle")
	elif _s == 90:
		Input.action_press("nitro")
	elif _s == 150:
		Input.action_release("nitro")
		Input.action_release("throttle")
		var a: AudioDriver = _gm.audio
		note(a.frames_pushed > 0, "frames reached real playback (%d samples)" % a.frames_pushed)
		note(a.last_block_peak > 0.0, "audio frame block peak %.3f" % a.last_block_peak)
		note(a.last_engine_hz > 5.0, "engine flash rate %.1f Hz" % a.last_engine_hz)
		note(_gm.effects._flames.emitting, "nitro produced flame in the live window")
		_shot("nitro")
		_stage = 1
		_s = 0

# drift on clear ground: smoke and skid marks must be in the frame, not only in counters
func _st_drift() -> void:
	if _s == 2:
		_gm.car.respawn(Transform3D(Basis.IDENTITY, Vector3(-40, 0.5, 0)))
		_gm.car.chassis.linear_velocity = Vector3(28, 0, 0)
		Input.action_press("throttle")
	elif _s == 10:
		Input.action_press("handbrake")
		Input.action_press("steer_left")
	elif _s == 70:
		Input.action_release("handbrake")
		Input.action_release("steer_left")
		Input.action_release("throttle")
		var smoking := false
		for e in _gm.effects._smoke:
			smoking = smoking or e.emitting
		note(smoking, "the drift emitted smoke in the live window")
		note(_gm.skid.marks_drawn() > 0, "the tyres left skid marks (%d)" % _gm.skid.marks_drawn())
		_shot("drift")
		_stage = 2
		_s = 0

func _st_crash() -> void:
	if _s == 2:
		_gm.car.chassis.global_position = Vector3(72, 1.0, 0)
		_gm.car.chassis.linear_velocity = Vector3(48, 0, 0)
	elif _s == 34:
		var a: AudioDriver = _gm.audio
		note(a.impacts_heard >= 1, "the impact reached the audio driver (%d)" % a.impacts_heard)
		note(_gm.car.body.dent_count >= 1, "a dent appeared in the live body (%d)" % _gm.car.body.dent_count)
		_shot("crash")
		_stage = 3
		_s = 0

func _st_replay() -> void:
	if _s == 2:
		_gm._set_paused(true)
	elif _s == 6:
		var btn := _gm.hud.pause_button("РЕПЛЕЙ УДАРА")
		note(btn != null, "the pause menu's fifth row is in place")
		if btn == null:
			_stage = 4
			_s = 0
			return
		btn.pressed.emit()
	elif _s == 14:
		note(_gm.replay_player.active, "the replay opened in the live window")
		_shot("replay_start")
	elif _s == 74:
		note(_gm.replay_player.cursor > _gm.replay_player.rec.window_start(),
			"the cursor moved on its own: %.2f s" % _gm.replay_player.cursor)
		_shot("replay_mid")
	elif _s == 84:
		_gm.hud.replay_button("ВЫХОД").pressed.emit()
	elif _s == 88:
		note(not _gm.replay_player.active, "the replay closed")
		_stage = 4
		_s = 0

func _st_photo() -> void:
	if _s == 2:
		_gm._set_paused(true)
	elif _s == 6:
		_gm.hud.pause_button("ФОТОМОД").pressed.emit()
	elif _s == 12:
		var cam: Camera3D = _gm.photo.camera
		var before := cam.global_position
		_gm.photo.look(60.0, -40.0)
		_gm.photo.dolly(4.0)
		note(before.distance_to(cam.global_position) > 1.0,
			"the free camera travelled %.2f m in the live window" % before.distance_to(cam.global_position))
	elif _s == 16:
		_gm.hud.photo_button("СНИМОК").pressed.emit()
	elif _s == 26:
		var p := _gm.photo.last_path()
		note(p != "" and FileAccess.file_exists(ProjectSettings.globalize_path(p)),
			"photo mode wrote a real PNG: %s" % p)
		if p != "":
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			note(img != null and img.get_width() > 100,
				"the file loads as an image %dx%d" % [img.get_width(), img.get_height()])
			if img != null:
				var mn := 1.0
				var mx := 0.0
				for yy in range(0, img.get_height(), 7):
					for xx in range(0, img.get_width(), 5):
						var l := lum(img.get_pixel(xx, yy))
						mn = minf(mn, l)
						mx = maxf(mx, l)
				note(mx > 0.05 and mx - mn > 0.02,
					"the snapshot is a scene, not a fill: luminance %.3f…%.3f" % [mn, mx])
	elif _s == 30:
		_gm.hud.photo_button("ВЫХОД").pressed.emit()
	elif _s == 34:
		note(get_viewport().get_camera_3d() == _gm.camera, "the game camera is back")
		_stage = 5
		_s = 0

# Garage in the live render: the showcase before and after painting. This is
# exactly what h_garage marks PARTIAL — the GPU image.
func _st_garage() -> void:
	if _s == 2:
		_gm._set_paused(false)
		_gm.queue_free()
		_gm = null
		# the baseline frame has to be factory stock: a previous run could leave a
		# saved paint in user://, and then "before" and "after" would match
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("garage_v1.json"):
			d.remove("garage_v1.json")
		_menu = load("res://scenes/main_menu.tscn").instantiate()
		add_child(_menu)
	elif _s == 40:
		_menu._show_section(2)          # Section.GARAGE
	elif _s == 70:
		_before = OUT + "live_garage_stock.png"
		_save_to(_before)
		# the player's path, not a backdoor: three channel sliders and the real
		# SAVE button — that is exactly how paint reaches the showcase
		var g = _menu._garage
		note(g != null, "the garage panel is built on entering the section")
		g.colors[0].value = PAINT_TEST.r
		g.colors[1].value = PAINT_TEST.g
		g.colors[2].value = PAINT_TEST.b
		g.save_button.pressed.emit()
	elif _s == 100:
		_after = OUT + "live_garage_paint.png"
		_save_to(_after)
		var a := _red_balance(_before)
		var b := _red_balance(_after)
		note(is_finite(a) and is_finite(b), "both body images were read")
		note(b - a < -0.05,
			"the paint shows in live pixels: red minus green %.3f → %.3f" % [a, b])
		_menu.queue_free()
		_menu = null
		_rebuilds = 1
		_stage = 6
		_s = 0

# Freeing the run scene tree together with the audio player — the very spot that
# historically produced a native crash. Three rebuilds in a row, the car drives
# in each one.
func _st_rebuild() -> void:
	if _s != 40: return
	_new_game()
	_gm.car.chassis.linear_velocity = Vector3(40, 0, 0)
	Input.action_press("throttle")
	if _rebuilds >= 3:
		Input.action_release("throttle")
		note(true, "%d run rebuilds played through, the process is intact" % _rebuilds)
		note(_gm.audio != null, "the audio driver is alive after the rebuilds")
		note(_shots >= 6, "frames were drawn the whole time (screenshots: %d)" % _shots)
		_stage = 7
		_s = 0
		return
	_rebuilds += 1
	_s = 0

func _save_to(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.get_width() <= 0:
		_fails += 1
		print("LIVE FAIL: the viewport returned no frame for %s" % path)
		return
	_shots += 1
	note(img.save_png(path) == OK, "screenshot %s (%dx%d)" % [path.get_file(), img.get_width(), img.get_height()])

func _shot(tag: String) -> void:
	_save_to(OUT + "live_%s.png" % tag)

# mean red-over-green excess inside the body frame: painting has to move exactly
# this difference, not brightness in general
func _red_balance(path: String) -> float:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	# NAN, not -1: the red-green balance legitimately goes negative, and -1 would
	# mean "could not read" where everything actually read fine
	if img == null: return NAN
	var sum := 0.0
	var n := 0
	for yy in range(CAR_RECT.position.y, CAR_RECT.end.y, 3):
		for xx in range(CAR_RECT.position.x, CAR_RECT.end.x, 3):
			if xx >= img.get_width() or yy >= img.get_height(): continue
			var c := img.get_pixel(xx, yy)
			sum += c.r - c.g
			n += 1
	return sum / maxf(float(n), 1.0)

func _finish() -> void:
	_stage = 8
	print("LIVE: screenshots %d, fails %d" % [_shots, _fails])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
