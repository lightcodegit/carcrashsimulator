class_name VibrationFeed
extends Node
# Мост от состояния машины к вибрации геймпада. Все три пути наружу — внедряемые
# callable (rumble_fn/impulse_fn/device_fn), поэтому тесты проверяют логику
# без железа, а на железе по умолчанию зовётся Input.start_joy_vibration.
#
# Устройство берётся из InputRouter.pad_index() (там помнится последний seen/
# rebound джой-девайс); при -1 реальные вызовы не делаются вовсе — без геймпада
# никакого побочного эффекта. Настройки vibration_enabled и vibration_strength
# читаются в момент события: выключенная настройка не порождает ни одного вызова,
# а нулевая сила делает амплитуды нулевыми, не трогая остальное.

const SLIP_RUMBLE_START := 0.35   # с какого slip начинается ощущаемый занос
const RUMBLE_REFRESH_S := 0.12    # start_joy_vibration конечна по длительности — обновляем
const RUMBLE_HOLD_S := 0.25
const AIR_S := 0.3                # дольше 0.3 с в воздухе — просим лёгкий rumble
const IMPACT_KMH_FULL := 160.0    # на этой скорости импульс достигает максимума

var car: CarRig
var rumble_fn: Callable
var impulse_fn: Callable
var device_fn: Callable
var rumble_calls := 0
var impulse_calls := 0

var _slip_t := 0.0
var _air_t := 0.0
var _stopped := true
var _active := true

func attach(c: CarRig) -> void:
	car = c
	if not rumble_fn.is_valid(): rumble_fn = _default_rumble
	if not impulse_fn.is_valid(): impulse_fn = _default_impulse
	if not device_fn.is_valid(): device_fn = _default_device
	# тот же гвард от двойного attach, что у EffectsDirector и AudioDriver:
	# повторное соединение удваивает импульсы вибрации
	if not c.impact.is_connected(_on_impact): c.impact.connect(_on_impact)

# Пауза/рестарт: непрерывная вибрация выключается, и на нулевой амплитуде
# остаётся один нулевой вызов; обратно включает её снятие с паузы.
func set_active(v: bool) -> void:
	_active = v
	if not v: stop()

func _enabled() -> bool:
	return _active and car != null and bool(Settings.vibration_enabled)

func _strength() -> float:
	return clampf(float(Settings.vibration_strength), 0.0, 1.0)

func _device() -> int:
	return int(device_fn.call()) if device_fn.is_valid() else -1

func _slip_level() -> float:
	if car == null: return 0.0
	var lvl := clampf(car.slip, 0.0, 1.0)
	for s in car.skid_levels(): lvl = maxf(lvl, s)
	return lvl

func _grounded_now() -> bool:
	if car == null or car.chassis == null: return true
	return bool(car.debug_snapshot()["grounded"])

func _process(dt: float) -> void:
	if not _enabled(): return
	# таймеры копим кадрами, а не часовой стеной: headless с --fixed-fps гонит
	# кадры быстрее реального времени, и ticks_msec давал бы один rumble на занос
	var step := clampf(dt, 0.0, 0.25)
	_slip_t = maxf(_slip_t - step, 0.0)
	_air_t = maxf(_air_t - step, 0.0)
	var lvl := _slip_level()
	if lvl >= SLIP_RUMBLE_START:
		if _slip_t <= 0.0:
			_slip_t = RUMBLE_REFRESH_S
			var s := _strength()
			_rumble(0.6 * lvl * s, 0.35 * lvl * s)
			_stopped = false
		_air_t = 0.0
	elif not _grounded_now():
		_air_t += step
		if _air_t > AIR_S:
			_air_t = RUMBLE_REFRESH_S
			var sa := _strength()
			_rumble(0.25 * sa, 0.12 * sa)
			_stopped = false
	else:
		_air_t = 0.0

func _on_impact(speed_kmh: float, _point: Vector3, _normal: Vector3) -> void:
	if not _enabled(): return
	var amp := clampf(speed_kmh / IMPACT_KMH_FULL, 0.1, 1.0) * _strength()
	var ms := clampf(60.0 + speed_kmh * 1.0, 60.0, 240.0)
	impulse_calls += 1
	if impulse_fn.is_valid():
		impulse_fn.call(amp, amp * 0.75, int(ms), _device())

# Остановить всё непрерывное: на паузе, респавне и выходе из сцены.
func stop() -> void:
	if car == null or _stopped: return
	_stopped = true
	_rumble(0.0, 0.0)

func _rumble(low: float, high: float) -> void:
	rumble_calls += 1
	if rumble_fn.is_valid():
		rumble_fn.call(clampf(low, 0.0, 1.0), clampf(high, 0.0, 1.0), _device())

func _default_device() -> int:
	return InputRouter.pad_index()

func _default_rumble(low: float, high: float, dev: int) -> void:
	if dev < 0: return
	Input.start_joy_vibration(dev, low, high, RUMBLE_HOLD_S)

func _default_impulse(low: float, high: float, ms: int, dev: int) -> void:
	if dev < 0: return
	Input.start_joy_vibration(dev, low, high, float(ms) / 1000.0)

func _exit_tree() -> void:
	# уходя из сцены, оставляем геймпад молчащим: залипшая вибрация переживает заезд
	if _enabled() and not _stopped: stop()
