extends Node3D
# What audio costs: two measurements, not one.
#  A) pure DSP — produce_block without AudioServer, to see the mixer's cost on any
#     machine (comparable against the 16.67 ms step budget and the simulation cost from p_bench);
#  B) a live frame — AudioDriver inside a real scene, i.e. DSP, wheel polling,
#     and the copy into AudioStreamGeneratorPlayback. A metric, no checks: prints ms/frame.
const BLOCK_S := 0.1               # exactly one audio frame at the 10 Hz request rate: 4410 samples
const REPS := 60                   # 60 blocks = 6 s of audio stream per configuration
const FROM := 300
const N := 600                     # how many audio frames to run in the live measurement
const FRAME_S := 1.0 / 60.0        # exactly one audio frame at 60 fps

var _stage := 0
var _f := 0
var _gm: GameManager

func _ready() -> void:
	print("mixer: %d Hz, block %.0f samples" % [int(AudioMixer.SAMPLE_RATE), BLOCK_S * AudioMixer.SAMPLE_RATE])
	_measure(0.0, 0.0, 0.0, false, "silence")
	_measure(3000.0, 0.6, 0.0, false, "engine 3000 rpm")
	_measure(6500.0, 1.0, 0.0, true, "engine 6500 + nitro")
	_measure(6500.0, 1.0, 0.9, true, "engine 6500 + nitro + tire skid")
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
	print("DSP %s: %.3f ms per %.0f ms audio block (%.2f%% of real time), %.3f ms at 60 fps" % [
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
		print("live %s: one audio frame path (%.0f samples at 60 fps) = %.3f ms (%.2f%% of the 16.67 ms step); hz=%.0f, peak=%.2f, pushed %d samples over %d frames%s" % [
			GameContext.map_id, FRAME_S * AudioMixer.SAMPLE_RATE, per / 1000.0,
			100.0 * per / 16670.0, d.last_engine_hz, d.last_block_peak,
			pushed, N, "" if pushed > 0 else " (playback not granted — audio stub)"])
		Input.action_release("throttle")
		get_tree().quit(0)
