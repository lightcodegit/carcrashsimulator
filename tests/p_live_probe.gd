extends Node3D
# Ручной живой прогон: окно, настоящий рендер, настоящий аудиовывод. Этот
# раннер НЕ входит в headless-набор (p_* раннер) и проверяет ровно то, что
# headless проверить не может: что кадры действительно рисуются, что звук
# доходит до устройства, что окраска из гаража видна в живом рендере, что
# снимок фотомода — это пиксели, а не пустышка, и что многократное освобождение
# дерева заезда вместе с аудиоплеером не роняет процесс (исторический
# access violation).
#
# Запуск из изолированного user://, иначе прогон тронет сохранённый cfg игрока:
#   APPDATA=<пустая папка> Godot --path . res://tests/p_live_probe.tscn --fixed-fps 60
# Скриншоты ложатся в tests/out/live_*.png.

const OUT := "res://tests/out/"
# рамка кузова на витрине меню при 1600x900: там, где атласная ячейка кузова
const CAR_RECT := Rect2i(360, 300, 420, 320)
# заведомо далеко от заводского цвета седана (он красный): зелёный сдвигает
# баланс красного и зелёного сильно, и подмена окраски не может «совпасть»
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
	# прогон сам ставит мир на паузу (реплей и фотомод), поэтому его собственный
	# счётчик кадров обязан переживать паузу
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := get_viewport()
	print("LIVE: окно %s, рендер %s, вывод %s, дисплей %s" % [
		vp.get_visible_rect().size, RenderingServer.get_current_rendering_method(),
		AudioServer.get_driver_name(), DisplayServer.get_name()])
	note(DisplayServer.get_name() != "headless", "это настоящее окно, не headless")
	note(AudioServer.get_driver_name() != "Dummy",
		"аудиоустройство живое (%s)" % AudioServer.get_driver_name())
	_new_game()

func _new_game() -> void:
	GameContext.select("sedan", "arena")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)

# Стадии идут по собственному счётчику: физический кадр = один шаг симуляции.
func _physics_process(_dt: float) -> void:
	_s += 1
	# стадии 5–7 живут БЕЗ машины: там _gm освобождён намеренно, и защита по
	# _gm остановила бы сам прогон вместе с ней
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

# разгон с нитро: пламя из-за бампера и мотор в живом выводе
func _st_accel() -> void:
	if _s == 4:
		Input.action_press("throttle")
	elif _s == 90:
		Input.action_press("nitro")
	elif _s == 150:
		Input.action_release("nitro")
		Input.action_release("throttle")
		var a: AudioDriver = _gm.audio
		note(a.frames_pushed > 0, "кадры ушли в настоящий playback (%d отсчётов)" % a.frames_pushed)
		note(a.last_block_peak > 0.0, "пик блока звукового кадра %.3f" % a.last_block_peak)
		note(a.last_engine_hz > 5.0, "частота вспышек мотора %.1f Гц" % a.last_engine_hz)
		note(_gm.effects._flames.emitting, "нитро в живом окне дало пламя")
		_shot("nitro")
		_stage = 1
		_s = 0

# занос на чистом месте: дым и следы обязаны быть в кадре, а не только в счётчиках
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
		note(smoking, "занос в живом окне пустил дым")
		note(_gm.skid.marks_drawn() > 0, "резина оставила следы (%d)" % _gm.skid.marks_drawn())
		_shot("drift")
		_stage = 2
		_s = 0

func _st_crash() -> void:
	if _s == 2:
		_gm.car.chassis.global_position = Vector3(72, 1.0, 0)
		_gm.car.chassis.linear_velocity = Vector3(48, 0, 0)
	elif _s == 34:
		var a: AudioDriver = _gm.audio
		note(a.impacts_heard >= 1, "удар долетел до драйвера (%d)" % a.impacts_heard)
		note(_gm.car.body.dent_count >= 1, "вмятина в живом кузове (%d)" % _gm.car.body.dent_count)
		_shot("crash")
		_stage = 3
		_s = 0

func _st_replay() -> void:
	if _s == 2:
		_gm._set_paused(true)
	elif _s == 6:
		var btn := _gm.hud.pause_button("РЕПЛЕЙ УДАРА")
		note(btn != null, "пятая строка меню паузы на месте")
		if btn == null:
			_stage = 4
			_s = 0
			return
		btn.pressed.emit()
	elif _s == 14:
		note(_gm.replay_player.active, "реплей открылся в живом окне")
		_shot("replay_start")
	elif _s == 74:
		note(_gm.replay_player.cursor > _gm.replay_player.rec.window_start(),
			"курсор сам двинулся: %.2f с" % _gm.replay_player.cursor)
		_shot("replay_mid")
	elif _s == 84:
		_gm.hud.replay_button("ВЫХОД").pressed.emit()
	elif _s == 88:
		note(not _gm.replay_player.active, "реплей закрылся")
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
			"свободная камера проехала в живом окне %.2f м" % before.distance_to(cam.global_position))
	elif _s == 16:
		_gm.hud.photo_button("СНИМОК").pressed.emit()
	elif _s == 26:
		var p := _gm.photo.last_path()
		note(p != "" and FileAccess.file_exists(ProjectSettings.globalize_path(p)),
			"фотомод писал настоящий PNG: %s" % p)
		if p != "":
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			note(img != null and img.get_width() > 100,
				"файл читается как изображение %dx%d" % [img.get_width(), img.get_height()])
			if img != null:
				var mn := 1.0
				var mx := 0.0
				for yy in range(0, img.get_height(), 7):
					for xx in range(0, img.get_width(), 5):
						var l := lum(img.get_pixel(xx, yy))
						mn = minf(mn, l)
						mx = maxf(mx, l)
				note(mx > 0.05 and mx - mn > 0.02,
					"снимок — сцена, а не заливка: яркость %.3f…%.3f" % [mn, mx])
	elif _s == 30:
		_gm.hud.photo_button("ВЫХОД").pressed.emit()
	elif _s == 34:
		note(get_viewport().get_camera_3d() == _gm.camera, "игровая камера вернулась")
		_stage = 5
		_s = 0

# Гараж в живом рендере: витрина до и после окраски. Это ровно то, что
# h_garage помечает PARTIAL — картинка GPU.
func _st_garage() -> void:
	if _s == 2:
		_gm._set_paused(false)
		_gm.queue_free()
		_gm = null
		# базовый кадр обязан быть заводским: прошлый прогон мог оставить
		# сохранённую окраску в user://, и тогда «до» и «после» совпадут
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
		# путь игрока, а не бэкдора: три ползунка каналов и настоящая кнопка
		# СОХРАНИТЬ — именно так окраска доходит до витрины
		var g = _menu._garage
		note(g != null, "панель гаража собрана при входе в раздел")
		g.colors[0].value = PAINT_TEST.r
		g.colors[1].value = PAINT_TEST.g
		g.colors[2].value = PAINT_TEST.b
		g.save_button.pressed.emit()
	elif _s == 100:
		_after = OUT + "live_garage_paint.png"
		_save_to(_after)
		var a := _red_balance(_before)
		var b := _red_balance(_after)
		note(is_finite(a) and is_finite(b), "обе картинки кузова прочитаны")
		note(b - a < -0.05,
			"окраска видна живым пикселем: красный минус зелёный %.3f → %.3f" % [a, b])
		_menu.queue_free()
		_menu = null
		_rebuilds = 1
		_stage = 6
		_s = 0

# Освобождение дерева заезда вместе с аудио-плеером — то самое место, где
# исторически был native crash. Три пересборки подряд, в каждой машина едет.
func _st_rebuild() -> void:
	if _s != 40: return
	_new_game()
	_gm.car.chassis.linear_velocity = Vector3(40, 0, 0)
	Input.action_press("throttle")
	if _rebuilds >= 3:
		Input.action_release("throttle")
		note(true, "%d пересборки заезда проживены, процесс цел" % _rebuilds)
		note(_gm.audio != null, "драйвер жив после пересборок")
		note(_shots >= 6, "кадры рисовались всё это время (скриншотов %d)" % _shots)
		_stage = 7
		_s = 0
		return
	_rebuilds += 1
	_s = 0

func _save_to(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.get_width() <= 0:
		_fails += 1
		print("LIVE FAIL: вьюпорт не отдал кадр для %s" % path)
		return
	_shots += 1
	note(img.save_png(path) == OK, "скриншот %s (%dx%d)" % [path.get_file(), img.get_width(), img.get_height()])

func _shot(tag: String) -> void:
	_save_to(OUT + "live_%s.png" % tag)

# средний перевес красного над зелёным в рамке кузова: окраска обязана двигать
# именно эту разницу, а не яркость вообще
func _red_balance(path: String) -> float:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	# NAN, а не -1: баланс красного и зелёного честно бывает отрицательным,
	# и -1 означал бы «не прочиталось» там, где всё прочиталось
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
	print("LIVE: скриншотов %d, провалов %d" % [_shots, _fails])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
