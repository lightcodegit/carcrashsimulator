extends Node3D
# Сколько стоит звук: два замера, а не один.
#  A) чистый DSP — produce_block без AudioServer, чтобы видеть цену микшера на любой
#     машине (её можно сравнить с бюджетом шага 16.67 мс и с ценой симуляции из p_bench);
#  B) живой кадр — AudioDriver внутри настоящей сцены, то есть и DSP, и опрос колёс,
#     и перенос в AudioStreamGeneratorPlayback. Метрика, без проверок: печатает мс/кадр.
const BLOCK_S := 0.1               # ровно кадр звука при 10 Гц заказа: 4410 отсчётов
const REPS := 60                   # 60 блоков = 6 с аудиопотока на конфигурацию
const FROM := 300
const N := 600                     # сколько звуковых кадров прогнать в живом замере
const FRAME_S := 1.0 / 60.0        # ровно один кадр звука при 60 к/с

var _stage := 0
var _f := 0
var _gm: GameManager

func _ready() -> void:
	print("mixer: %d Гц, блок %.0f отсчётов" % [int(AudioMixer.SAMPLE_RATE), BLOCK_S * AudioMixer.SAMPLE_RATE])
	_measure(0.0, 0.0, 0.0, false, "тишина")
	_measure(3000.0, 0.6, 0.0, false, "мотор 3000 об/мин")
	_measure(6500.0, 1.0, 0.0, true, "мотор 6500 + нитро")
	_measure(6500.0, 1.0, 0.9, true, "мотор 6500 + нитро + визг резины")
	_start_scene()

func _measure(rpm: float, load: float, skid: float, nitro: bool, label: String) -> void:
	var m := AudioMixer.new()
	var count := int(BLOCK_S * AudioMixer.SAMPLE_RATE)
	var total := 0
	for i in REPS:
		m.set_engine(rpm, load)
		m.set_skid(skid)
		m.set_nitro(nitro)
		var t := Time.get_ticks_usec()
		m.produce_block(count)
		total += Time.get_ticks_usec() - t
	var per := float(total) / float(REPS)
	print("DSP %s: %.3f мс на блок %.0f мс звука (%.2f%% реального времени), %.3f мс на 60 к/с" % [
		label, per / 1000.0, BLOCK_S * 1000.0, 100.0 * per / (BLOCK_S * 1e6),
		per * 60.0 / 1e6])

func _start_scene() -> void:
	var map := OS.get_environment("MAP")
	if map == "": map = "speedway"
	GameContext.select("sport", map)
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	await get_tree().process_frame
	Input.action_press("throttle")
	_stage = 1

func _physics_process(_dt: float) -> void:
	if _stage != 1: return
	_f += 1
	if _f < FROM: return
	if _f == FROM:
		var d := _gm.audio
		var total := 0
		var pushed := 0
		for i in N:
			var t := Time.get_ticks_usec()
			pushed += d.measure_audio_frame(int(FRAME_S * AudioMixer.SAMPLE_RATE))
			total += Time.get_ticks_usec() - t
		var per := float(total) / float(N)
		print("live %s: путь одного звукового кадра (%.0f отсчётов при 60 к/с) = %.3f мс (%.2f%% шага 16.67 мс); hz=%.0f, пик=%.2f, протолкано %d отсчётов за %d кадров%s" % [
			GameContext.map_id, FRAME_S * AudioMixer.SAMPLE_RATE, per / 1000.0,
			100.0 * per / 16670.0, d.last_engine_hz, d.last_block_peak,
			pushed, N, "" if pushed > 0 else " (playback не отдан — заглушка аудио)"])
		Input.action_release("throttle")
		get_tree().quit(0)
