extends Node3D
# Фотомод: мир на паузе, своя свободная камера, снимаемый интерфейс и PNG на
# диске. Живой пиксель в headless неоткуда брать (движок не рисует), поэтому
# захват кадра подменяется заглушкой и проверяется ровно то, что проверяется без
# GPU: путь, имя, счётчик и байты файла.
var _fails := 0
var gm: GameManager
var _f := 0
var _stage := 0
var _p: PhotoMode
var _car: CarRig
var _p0 := Vector3.ZERO
var _sim_at_entry := 0.0
var _disk_shots := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _act(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = StringName(name)
	e.pressed = true
	e.strength = 1.0
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

# ── 0. вход из меню паузы ───────────────────────────────────────────────────
func _s_boot() -> void:
	if _f < 30: return
	check(_p != null, "GameManager собрал фотомод")
	Input.action_press("throttle")
	if _f < 90: return
	Input.action_release("throttle")
	gm._set_paused(true)
	var btn := gm.hud.pause_button("ФОТОМОД")
	check(btn != null, "в меню паузы есть шестая строка «ФОТОМОД»")
	if btn == null:
		_finish(); return
	btn.pressed.emit()
	_stage = 1
	_f = 0

# ── 1. мир стоит: физика не двигает машину ни на микрометр ──────────────────
func _s_frozen() -> void:
	if _f == 2:
		check(_p.active, "ФОТОМОД открылся")
		check(gm.is_frozen(), "фотомод заморозил мир")
		check(_p.camera.current, "текущей стала камера фотомода")
		check(get_viewport().get_camera_3d() == _p.camera,
			"вьюпорт видит камеру фотомода, а не игровую")
		check(gm.hud.photo_ui_visible(), "полоса фотомода видна")
		check(not gm.hud._pause_panel.visible, "карточка паузы спрятана")
		_p0 = _car.chassis.global_position
		_sim_at_entry = gm.replay.sim_t
	if _f != 60: return
	var moved := _car.chassis.global_position.distance_to(_p0)
	check(moved < 1e-6,
		"за 58 физических тиков машина не сдвинулась ни на микрометр (%.7f м)" % moved)
	check(gm.replay.sim_t == _sim_at_entry,
		"recorder на паузе фотомода молчит (%.3f против %.3f)" % [gm.replay.sim_t, _sim_at_entry])
	_stage = 2
	_f = 0

# ── 2. свободная камера: курс, наклон, шаг, зум, возврат вида ───────────────
func _s_camera() -> void:
	var cam := _p.camera
	if _f == 2:
		var yaw0 := cam.global_rotation.y
		var y0 := cam.global_position.y
		_p.look(200.0, 0.0)
		check(absf(cam.global_rotation.y - yaw0) > 0.3,
			"мышь крутит курс камеры (%.3f рад сдвига)" % absf(cam.global_rotation.y - yaw0))
		_p.look(0.0, 9000.0)
		check(absf(cam.global_rotation.x) <= PhotoMode.PITCH_LIMIT + 0.01,
			"тангаж не переворачивается (%.3f при потолке %.3f)" %
			[absf(cam.global_rotation.x), PhotoMode.PITCH_LIMIT])
		check(absf(absf(cam.global_rotation.x) - PhotoMode.PITCH_LIMIT) < 0.02,
			"дальше потолка наклон не уходит (%.3f против %.3f)" %
			[absf(cam.global_rotation.x), PhotoMode.PITCH_LIMIT])
		_p.reset_view()
		check(cam.global_transform.origin.distance_to(gm.camera.global_transform.origin) < 1e-4,
			"«СБРОС ВИДА» возвращает камеру туда, где стояла игровая")
		_p.sprint = true
		var w0 := cam.global_position
		_p.set_nav(0, 0, 1)
		_p.move_step(1.0)
		check(w0.distance_to(cam.global_position) > PhotoMode.MOVE_SPEED * PhotoMode.SPRINT * 0.9,
			"Shift ускоряет шаг (%.2f м за секунду)" % w0.distance_to(cam.global_position))
		_p.sprint = false
		var before := cam.global_position
		_p.set_nav(0, 0, 1)
		_p.move_step(1.0)
		check(before.distance_to(cam.global_position) > 1.0,
			"W шагает вперёд по курсу камеры (%.2f м)" % before.distance_to(cam.global_position))
		var up0 := cam.global_position
		_p.set_nav(0, 1, 0)
		_p.move_step(1.0)
		check(cam.global_position.y > before.y + 1.0,
			"E поднимает камеру вверх, а не вперёд (%.2f против %.2f)" % [cam.global_position.y, before.y])
		var up_at := cam.global_position.y
		_p.set_nav(1, 0, 0)
		_p.move_step(1.0)
		check(absf(cam.global_position.y - up_at) < 1e-6,
			"D едет вбок и не меняет высоту (%.4f против %.4f)" % [cam.global_position.y, up_at])
		var sideways := Vector2(cam.global_position.x, cam.global_position.z).distance_to(
			Vector2(up0.x, up0.z))
		check(absf(sideways - PhotoMode.MOVE_SPEED) < 0.2,
			"D прошёл ровно MOVE_SPEED поперёк (%.2f)" % sideways)
		_p.set_nav(0, 0, 0)
		check(cam.global_position.y != y0, "камера реально ушла с игровой высоты")
	if _f == 4:
		var f0 := cam.fov
		for i in 40: _p.zoom(PhotoMode.FOV_STEP)
		check(absf(cam.fov - PhotoMode.FOV_MAX) < 0.01,
			"зум упирается в потолок %d° (%.1f)" % [int(PhotoMode.FOV_MAX), cam.fov])
		for i in 100: _p.zoom(-PhotoMode.FOV_STEP)
		check(absf(cam.fov - PhotoMode.FOV_MIN) < 0.01,
			"зум не проваливается под минимум %d° (%.1f)" % [int(PhotoMode.FOV_MIN), cam.fov])
		cam.fov = f0
		_p.fov = f0
		var zk := InputEventKey.new()
		zk.keycode = KEY_Z
		zk.pressed = true
		_p._unhandled_input(zk)
		check(absf(cam.fov - (f0 + PhotoMode.FOV_STEP)) < 0.01,
			"Z расширяет угол (%.1f против %.1f)" % [cam.fov, f0 + PhotoMode.FOV_STEP])
		var xk := InputEventKey.new()
		xk.keycode = KEY_X
		xk.pressed = true
		_p._unhandled_input(xk)
		check(absf(cam.fov - f0) < 0.01,
			"X возвращает угол назад (%.1f против %.1f)" % [cam.fov, f0])
		var pos := cam.global_position
		_p.dolly(2.0)
		check(cam.global_position.distance_to(pos) > 1.5,
			"колесо подъезжает к объекту (%.2f м)" % cam.global_position.distance_to(pos))
	if _f == 6:
		gm.hud.photo_button("БЕЗ HUD").pressed.emit()
	if _f == 8:
		check(_p.hud_off, "«БЕЗ HUD» переключилась")
		var hidden := 0
		for c in gm.hud._gameplay:
			if not c.visible: hidden += 1
		check(hidden == gm.hud._gameplay.size(),
			"все игровые панели скрыты (%d из %d)" % [hidden, gm.hud._gameplay.size()])
		check(not gm.hud.photo_ui_visible(), "и полоса фотомода скрыта")
		var f5 := InputEventKey.new()
		f5.keycode = KEY_F5
		f5.pressed = true
		_p._unhandled_input(f5)
	if _f == 10:
		check(not _p.hud_off, "F5 возвращает интерфейс")
		var shown := 0
		for c in gm.hud._gameplay:
			if c.visible: shown += 1
		check(shown == gm.hud._gameplay.size(),
			"интерфейс вернулся целиком (%d из %d)" % [shown, gm.hud._gameplay.size()])
		_stage = 3
		_f = 0


# ── 3. снимок: файл, имя, счётчик, отсутствие живого пикселя ────────────────
func _s_shot() -> void:
	if _f == 2:
		_fake_shot(64)
		var before := _p.shots
		var p := _p.capture()
		check(_p.shots == before + 1, "снимок увеличил счётчик (%d против %d)" % [_p.shots, before + 1])
		check(p.begins_with("user://photos/photo_") and p.ends_with(".png"),
			"путь снимка в user://photos с порядковым именем (%s)" % p)
		var abs := ProjectSettings.globalize_path(p)
		check(FileAccess.file_exists(abs), "PNG лёг на диск (%s)" % abs)
		if FileAccess.file_exists(abs):
			var fa := FileAccess.open(abs, FileAccess.READ)
			var bytes := fa.get_length()
			var magic := fa.get_buffer(4)
			fa.close()
			check(bytes > 40, "файл непустой (%d байт)" % bytes)
			check(magic[0] == 0x89 and magic[1] == 0x50 and magic[2] == 0x4E and magic[3] == 0x47,
				"первые байты — подпись PNG")
		var second := _p.capture()
		check(second != p, "второй снимок не перезатирает первый (%s против %s)" % [second, p])
		# «СНИМОК» по кнопке: сначала гаснит интерфейс, пишет кадр на следующем
		# процесс-тик и возвращает интерфейс обратно
		gm.hud.photo_button("СНИМОК").pressed.emit()
	if _f == 4:
		check(_p.shots == 3, "кнопка «СНИМОК» добавила третий кадр (%d)" % _p.shots)
		check(not _p.hud_off, "после съёмки интерфейс вернулся")
		check(gm.hud.photo_ui_visible(), "после съёмки полоса снова видна")
		_disk_shots = _count_files()
		check(_disk_shots == 3,
			"на диске три снимка: два руками и один кнопкой (%d)" % _disk_shots)
		_p.look_fn = Callable()
		var got := _p.capture()
		if got == "":
			print("PARTIAL: headless не отдаёт текстуру вьюпорта — живой пиксель не проверялся")
		else:
			check(FileAccess.file_exists(ProjectSettings.globalize_path(got)),
				"живой захват всё равно написал файл (%s)" % got)
		_stage = 4
		_f = 0

func _count_files() -> int:
	var d := DirAccess.open("user://photos")
	if d == null: return -1
	var n := 0
	for f in d.get_files():
		if f.begins_with("photo_") and f.ends_with(".png"): n += 1
	return n

# ── 4. выход: камера и мир возвращаются ─────────────────────────────────────
func _s_exit() -> void:
	if _f == 2:
		gm.hud.photo_button("ВЫХОД").pressed.emit()
	if _f == 4:
		check(not _p.active, "выход закрыл фотомод")
		check(not gm.is_frozen(), "мир размяк")
		check(gm.camera.current, "игровая камера снова текущая")
		check(get_viewport().get_camera_3d() == gm.camera, "вьюпорт вернулся к игровой камере")
		check(not gm.hud.photo_ui_visible(), "полоса фотомода скрыта")
		var shown := 0
		for c in gm.hud._gameplay:
			if c.visible: shown += 1
		check(shown == gm.hud._gameplay.size(), "интерфейс снова целый (%d)" % shown)
		Input.action_press("throttle")
	if _f == 70:
		Input.action_release("throttle")
		check(_car.chassis.global_position.distance_to(_p0) > 0.5,
			"после выхода машина поехала (%.2f м)" % _car.chassis.global_position.distance_to(_p0))
		check(gm.replay.sim_t > _sim_at_entry,
			"recorder снова пишет (%.2f против %.2f)" % [gm.replay.sim_t, _sim_at_entry])
		gm._set_paused(true)
		gm.hud.pause_button("ФОТОМОД").pressed.emit()
	if _f == 74:
		gm._unhandled_input(_act("pause"))
	if _f == 76:
		check(not _p.active, "Esc вышел из фотомода")
		check(not gm.is_frozen(), "после Esc заезд идёт")
		_stage = 5
		_f = 0

# ── 5. нумерация продолжается, а не начинается заново ───────────────────────
func _s_numbering() -> void:
	if _f == 4:
		_disk_shots = _count_files()
		check(_disk_shots >= 3, "снимки переживают выход из фотомода (%d)" % _disk_shots)
		gm._set_paused(true)
		gm.hud.pause_button("ФОТОМОД").pressed.emit()
	if _f == 8:
		check(_p.active, "второй вход в фотомод открылся")
		_fake_shot(8)
		var p := _p.capture()
		check(p.ends_with("photo_%04d.png" % (_disk_shots + 1)),
			"нумерация продолжается с числа файлов на диске (%s после %d снимков)" % [p, _disk_shots])
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
