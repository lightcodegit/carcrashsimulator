class_name AudioDriver
extends Node3D
# Узловой слой поверх AudioMixer: один AudioStreamGenerator на 44100 Гц, один
# AudioStreamPlayer, шина «SFX» создаётся программно и идемпотентно. Драйвер
# опрашивает машину в _process, кормит микшер состоянием и отдаёт ровно столько
# кадров, сколько вмещает буфер воспроизведения — лишнего не выдумывает.
#
# Границы честности: на dummy-аудиодровере (headless) генератор никто не
# расходует, а освобождение живого AudioStreamGenerator вместе с деревом сцены
# оборачивалось access violation — НЕДЕТЕРМИНИРОВАННО: три пересборки городка
# подряд давали падение / ALL PASS / падение, а h_settings печатал ALL PASS и
# умирал на выходе. Поэтому без аудиожелеза вывод не заводится вовсе: микшер
# считается, пики и обороты обновляются, playback_missing поднят, и тест обязан
# напечатать PARTIAL вместо молчаливого «слышим звук».
#
# Штатного AudioEffectVolumeFader в этом билде движка нет (замер ClassDB:
# class_exists=false), его роль играет AudioEffectAmplify на той же шине.

const MAX_PUSH_S := 0.2             # не запасать больше 0.2 с: отклик важнее глубины

var mixer: AudioMixer
var last_block_peak := 0.0
var last_engine_hz := 0.0
var frames_pushed := 0
var impacts_heard := 0
var playback_missing := false

var _car: CarRig
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _sfx_idx := -1
var _suspended := false

# Headless-прогон сидит на dummy-аудиодровере: вывода нет, и заводить его нельзя
# (см. шапку файла). Реальные драйверы — WASAPI/DirectSound/CoreAudio/Pulse/ALSA.
static func has_output_device() -> bool:
	return AudioServer.get_driver_name() != "Dummy"

func attach(car: CarRig) -> void:
	mixer = AudioMixer.new()
	_car = car
	_ensure_bus()
	if has_output_device():
		_player = AudioStreamPlayer.new()
		_player.stream = _make_stream()
		_player.bus = "SFX"
		add_child(_player)
		_start_playback()
	else:
		playback_missing = true
	car.impact.connect(_on_impact)
	apply_settings()

func _make_stream() -> AudioStreamGenerator:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AudioMixer.SAMPLE_RATE
	return gen

func _start_playback() -> void:
	if _player == null: return
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	playback_missing = _pb == null

# Стоимость одного РЕАЛЬНОГО кадра звука: тот же путь, что в _process (генерация →
# перенос в стерео → push_buffer), но с размером кадра, а не с размером буфера.
# В headless буфер AudioStreamGenerator ничего не расходует и растёт до потолка,
# поэтому wall-clock всего `_process` там мерить бессмысленно — этот метод и есть
# честная метрика для p_audio_perf.
func measure_audio_frame(samples: int) -> int:
	if mixer == null: return 0
	var want := clampi(samples, 1, AudioMixer.MAX_BLOCK)
	var blk := mixer.produce_block(want)
	if blk.is_empty() or _pb == null: return blk.size()
	var st := PackedVector2Array()
	st.resize(blk.size() * 2)
	for i in blk.size():
		st[2 * i] = Vector2(blk[i], blk[i])
	_pb.push_buffer(st)
	return blk.size()

# Шина «SFX»: индекс проверяем перед каждым изменением, повторные вызовы
# (attach из теста, смена сцены) не плодят дубликаты.
func _ensure_bus() -> int:
	_sfx_idx = AudioServer.get_bus_index("SFX")
	if _sfx_idx < 0:
		_sfx_idx = AudioServer.get_bus_count()
		AudioServer.add_bus(_sfx_idx)
		AudioServer.set_bus_name(_sfx_idx, "SFX")
		var amp := AudioEffectAmplify.new()
		amp.volume_db = 0.0
		AudioServer.add_bus_effect(_sfx_idx, amp, 0)
		_sfx_idx = AudioServer.get_bus_index("SFX")
	_player_bus()
	return _sfx_idx

func _player_bus() -> void:
	if _player != null: _player.bus = "SFX"

func sfx_bus_index() -> int:
	return _sfx_idx

func bus_linear_volume() -> float:
	var idx := _sfx_bus_live()
	if idx < 0: return 0.0
	return AudioServer.get_bus_volume_linear(idx)

func _sfx_bus_live() -> int:
	return AudioServer.get_bus_index("SFX")

# Настройки доходят до звука отсюда: вызывает и _ready, и Settings.changed.
func apply_settings() -> void:
	if _ensure_bus() < 0: return
	var idx := _sfx_bus_live()
	if idx < 0: return
	var on := bool(Settings.audio_enabled)
	var v := clampf(float(Settings.audio_volume), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, not on or v <= 0.0)
	# linear_to_db(0) дал бы -inf; ноль уже закрыт mute'ом выше
	if on and v > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))

func _process(dt: float) -> void:
	if mixer == null or _suspended: return
	var rpm := 0.0
	var grounded := 0
	if _car != null and _car.chassis != null:
		for i in _car.wheel_count():
			var w := _car.chassis.get_node_or_null("Wheel%d" % i) as VehicleWheel3D
			if w == null: continue
			rpm += absf(w.get_rpm())
			if w.is_in_contact(): grounded += 1
		if grounded > 0: rpm /= float(grounded)
	var kmh := 0.0
	if _car != null and _car.chassis != null: kmh = _car.speed_kmh()
	var load := clampf(0.3 + 0.7 * kmh / 200.0, 0.3, 1.0)
	mixer.set_engine(rpm, load)
	var skid := 0.0
	var levels := _car.skid_levels() if _car != null else PackedFloat32Array()
	for l in levels: skid = maxf(skid, l)
	if _car != null: skid = maxf(skid, _car.slip * 0.6)
	mixer.set_skid(skid)
	mixer.set_nitro(_car != null and _car.nitro_active)
	last_engine_hz = mixer.firing_hz()
	# просим ровно столько, сколько нужно на кадр (с запасом на джиттер), и не
	# больше, чем вмещает буфер: недомер — тише, перемер — щелчок и потеря кадра
	var want := clampi(int(AudioMixer.SAMPLE_RATE * clampf(dt * 1.1, 0.0, MAX_PUSH_S)), 0, AudioMixer.MAX_BLOCK)
	if _pb != null: want = mini(want, int(_pb.get_frames_available()))
	else: want = mini(want, 2048)   # без playback микшер всё равно считается — иначе пиков не измерить
	if want <= 0: return
	var blk := mixer.produce_block(want)
	last_block_peak = mixer.last_peak
	if _pb == null or blk.is_empty(): return
	var st := PackedVector2Array()
	st.resize(blk.size() * 2)
	for i in blk.size():
		st[2 * i] = Vector2(blk[i], blk[i])
	_pb.push_buffer(st)
	frames_pushed += blk.size()

func _on_impact(speed_kmh: float, _point: Vector3, _normal: Vector3) -> void:
	impacts_heard += 1
	if mixer != null: mixer.trigger_impact(speed_kmh)

func suspend() -> void:
	_suspended = true
	if _player != null and _player.playing: _player.stop()
	_pb = null

func resume() -> void:
	_suspended = false
	_start_playback()
	# флаг отражает фактическое состояние вывода: прежнее безусловное false после
	# первого же пауза/продолжить в headless прятало playback_missing, и h_audio
	# терял основание сказать PARTIAL
	playback_missing = _pb == null

func stop_all() -> void:
	suspend()
	if mixer != null: mixer.reset()

func reset_state() -> void:
	if mixer != null: mixer.reset()
	impacts_heard = 0
	last_block_peak = 0.0

func _exit_tree() -> void:
	# Порядок задаёт порядок выживания: плеер обязан отдать стрим-генератор ДО того,
	# как его удалит дерево сцены, а playback-рукоятка — не пережить свой стрим.
	# На реальном драйвере это гигиена, на dummy — единственный шанс не словить AV
	# в потоке, который всё ещё читает ring-буфер умирающего генератора.
	if _player != null:
		if _player.playing: _player.stop()
		_player.stream = null
	_pb = null
