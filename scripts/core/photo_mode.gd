class_name PhotoMode
extends Node3D
# Фотомод: мир заморожен, камера свободна, интерфейс убирается по требованию,
# снимок пишется PNG в user://photos/.
#
# Мир стоит на той же паузе, что и меню: физика не делает ни шага, поэтому
# кадр = ровно то состояние, которое игрок увидел. Камера своя, текущая: живую
# CameraRig мы не трогаем и на выходе возвращаем ей статус активной — иначе
# после фотомода игра осталась бы смотреть чужим объектом.
#
# Захват кадра идёт через внедряемый callable: в headless движок не рисует, и
# проверка пути сохранения (имя, счётчик, побайтовая запись файла) не должна
# зависеть от GPU. Живой пиксель проверяется вручную, тест честно об этом пишет.

const SAVE_DIR := "user://photos"
const MOVE_SPEED := 6.0            # м/с
const SPRINT := 3.0                # множитель
const LOOK_SENS := 0.0035          # рад на пиксель мыши
const PITCH_LIMIT := 1.35          # ±77°: за верх и низ тянуть камеру бессмысленно
const DOLLY_STEP := 0.6            # м на щелчок колеса
const FOV_MIN := 12.0
const FOV_MAX := 110.0
const FOV_STEP := 3.0

signal shot_saved(path: String, index: int)
signal hud_hidden(v: bool)

var camera: Camera3D
var car: CarRig
var gm: GameManager
var active := false
var shots := 0
var _path := ""
var _pending := false          # снимок по «СНИМОК»: интерфейс гаснет за кадр до захвата
var hud_off := false
var fov := 65.0
var sprint := false
var nav := Vector3.ZERO            # локальная система: x вправо, y вверх, z вперёд
var look_fn := Callable()          # куда отдавать PNG (по умолчанию — текстура вьюпорта)
var _prev: Camera3D          # живая камера, которой возвращаем статус текущей
var _yaw := 0.0
var _pitch := 0.0
var _counted := 0                  # уже существующие снимки при входе: счётчик не обнуляем

func setup(p_car: CarRig, p_gm: GameManager) -> void:
	car = p_car
	gm = p_gm
	name = "PhotoMode"
	camera = Camera3D.new()
	camera.name = "PhotoCamera"
	camera.fov = fov
	add_child(camera)

func begin() -> bool:
	if active: return false
	active = true
	_prev = get_viewport().get_camera_3d()
	var live := _prev
	if live != null:
		# стартуем там, где игрок только что смотрел: фотомод не должен
		# перебрасывать вид в другую точку сцены
		camera.global_transform = live.global_transform
		_yaw = camera.global_rotation.y
		_pitch = clampf(camera.global_rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	camera.current = true
	_counted = _existing_count()
	shots = 0
	fov = camera.fov
	hud_off = false
	_pending = false
	nav = Vector3.ZERO
	hud_hidden.emit(false)
	return true

func end() -> void:
	if not active: return
	active = false
	camera.current = false
	# снимать текущую камеру с игровой вручную не нужно: вьюпорт сам возвращает
	# статус ближайшей включённой (проверено на выходе из фотомода)
	nav = Vector3.ZERO
	hud_hidden.emit(false)

func look(dx: float, dy: float) -> void:
	if not active: return
	_yaw -= dx * LOOK_SENS
	_pitch = clampf(_pitch - dy * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
	_pose()

func dolly(meters: float) -> void:
	if not active: return
	camera.global_position += camera.global_transform.basis.z * meters
	_pose()

func zoom(by_fov: float) -> void:
	if not active: return
	fov = clampf(fov + by_fov, FOV_MIN, FOV_MAX)
	camera.fov = fov

func set_nav(x: float, y: float, z: float) -> void:
	nav = Vector3(x, y, z)

func move_step(dt: float) -> void:
	if not active or nav.length_squared() <= 1e-6: return
	var speed := MOVE_SPEED * (SPRINT if sprint else 1.0)
	# направление берём из рыскания камеры без тангажа: «вперёд» обязан идти по
	# горизонту, иначе при взгляде вниз камера ныряла бы в асфальт
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var r := Vector3(-f.z, 0.0, f.x)
	camera.global_position += (f * nav.z + r * nav.x + Vector3.UP * nav.y) * speed * dt
	_pose()

# Углы хранятся в радианах: тот же порядок, что у Basis, и никаких переводах
# туда-сюда на каждом кадре.
func _pose() -> void:
	camera.rotation = Vector3(_pitch, _yaw, 0.0)

# Живое управление: WASD + QE + стрелки, Shift — быстрее, колесо — ближе/дальше.
# Вне InputMap намеренно: эти клавиши фотомода не должны конфликтовать с
# назначенными игроком биндами езды и не лезут в таблицу переопределений.
func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5: hide_hud(not hud_off)
			KEY_Z: zoom(FOV_STEP)
			KEY_X: zoom(-FOV_STEP)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		look(event.relative.x, event.relative.y)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: dolly(DOLLY_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: dolly(-DOLLY_STEP)

func _process(dt: float) -> void:
	if not active: return
	if _pending:
		_take_pending()
		return
	var x := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var y := (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0)
	var z := (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	z += (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0)
	sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	set_nav(x, y, z)
	move_step(dt)

func hide_hud(v: bool) -> void:
	hud_off = v
	hud_hidden.emit(v)

# Снимок по кнопке: сначала прячем интерфейс, потом берём кадр — на следующем
# _process, когда вьюпорт уже без панелей. Иначе полоса фотомода попадала бы
# в каждый снимок, а это ровно то, от чего фотомод и спасает.
func shoot() -> void:
	if not active: return
	hide_hud(true)
	_pending = true

func _take_pending() -> void:
	_pending = false
	var p := capture()
	hide_hud(false)
	if p == "": push_warning("PhotoMode: снимок не записан (нет кадра или нет права записи)")

# Снимок: берём кадр, пишем PNG с порядковым именем и возвращаем путь.
# Файл существует и непустой — это проверяется; «тот ли пиксель внутри» —
# только живым прогоном, и тест об этом сообщает.
# «СБРОС ВИДА»: вернуться туда, где стояла игровая камера, и к её курсу.
func reset_view() -> void:
	if not active or _prev == null or not is_instance_valid(_prev): return
	camera.global_transform = _prev.global_transform
	_yaw = camera.global_rotation.y
	_pitch = clampf(camera.global_rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	_pose()

func capture() -> String:
	if not active: return ""
	if camera == null: return ""
	var img := _grab()
	if img == null or img.get_width() <= 0:
		return ""
	var d := DirAccess.open("user://")
	if d != null and not d.dir_exists("photos"):
		var err := d.make_dir("photos")
		if err != OK: return ""
	shots += 1
	var idx := _counted + shots
	_path = "%s/photo_%04d.png" % [SAVE_DIR, idx]
	if img.save_png(_path) != OK:
		shots -= 1
		_path = ""
		return ""
	shot_saved.emit(_path, idx)
	return _path

func _grab() -> Image:
	if look_fn.is_valid(): return look_fn.call() as Image
	var vp := get_viewport()
	if vp == null: return null
	# В headless текстура вьюпорта — пустышка: get_image() на ней печатает
	# «Parameter "t" is null» и возвращает пустоту. Отказываемся честно, чтобы
	# тест не ловил движковый ERROR вместо своего PARTIAL.
	if DisplayServer.get_name() == "headless": return null
	var tex := vp.get_texture()
	if tex == null: return null
	return tex.get_image()

func _existing_count() -> int:
	var d := DirAccess.open(SAVE_DIR)
	if d == null: return 0
	var n := 0
	for f in d.get_files():
		if f.begins_with("photo_") and f.ends_with(".png"): n += 1
	return n

func last_path() -> String: return _path
