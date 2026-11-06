class_name AudioMixer
extends RefCounted
# Процедурный аудиомикшер: чистый DSP без узлов и без AudioServer, чтобы узловой
# слой (AudioDriver) мог лишь переносить состояние машины в блоки и отдавать их
# наружу. Всё считается на моно-сетке 44100 Гц.
#
# Шум — xorshift32 с заводским seed: reset() возвращает генератор в то же
# состояние, поэтому два экземпляра на одной последовательности входов дают
# бит-в-бит одинаковый сигнал (это проверяет d_audio_mixer). Любые входы
# приводятся на входе: INF/NAN/отрицательные не имеют права отравить отсчёт.

const SAMPLE_RATE := 44100.0
const MAX_BLOCK := 44100            # потолок заказа: ровно секунда; драйвер просит куда меньше
const CYL := 4                     # рядная «четвёрка»: вспышек за оборот = CYL/2
const PULSE_DECAY_S := 0.011       # RC основного «выстрела» цилиндра
const SUB_DECAY_S := 0.034         # субгармоника гаснет дольше — отсюда низ
const ENG_NOISE_MIX := 0.16        # доля шума вклину к импульсному ряду
const IMPACT_LIFE_S := 0.5         # длительность burst'а удара
const IMPACT_CUT_START := 7000.0   # срез шума на старте burst'а, Гц: свист
const IMPACT_CUT_END := 260.0      # к концу — гул: срез скользит вниз
const IMPACT_DECAY_S := 0.16       # RC громкости самого burst'а
const JET_LIN := 0.34              # пиковая амплитуда струи нитро
const SKID_LIN := 0.5              # пиковая амплитуда визга резины
const IMPACT_MIN_KMH := 15.0       # ниже — не удар, а касание
const IMPACT_FULL_KMH := 190.0     # амплитуда удара растёт до этой скорости

var firings_last_block := 0        # сколько вспышек пришлось на последний блок
var last_peak := 0.0               # |максимум| последнего блока: пик считается в том
                                   # же проходе, что и отсчёты, а не вторым циклом

var _rpm := 0.0
var _load := 0.0
var _skid := 0.0
var _nitro := false
var _firing_hz := 0.0
var _eng_phase := 0.0
var _eng_env := 0.0
var _sub_env := 0.0
var _eng_lp := 0.0
var _skid_amp := 0.0               # slew-ограничитель визга: стык блоков не щёлкает
var _skid_hp := 0.0                # состояние однополюсного ВЧ-фильтра визга
var _jet_amp := 0.0
var _jet_lp := 0.0
var _imp_env := 0.0
var _imp_age := IMPACT_LIFE_S + 1.0
var _imp_lp := 0.0
var _seed := 0x1234ABCD

# Частота вспышек для тестов и драйвера: rpm/60 × CYL/2, как у 4-тактного мотора.
func firing_hz() -> float:
	return _firing_hz

# Входная гигиена: NAN/INF/отрицательные значения не долетают до DSP-состояния.
static func _num(v: float, lo: float, hi: float) -> float:
	if not is_finite(v): return 0.0
	return clampf(v, lo, hi)

func reset() -> void:
	_rpm = 0.0; _load = 0.0; _skid = 0.0; _nitro = false
	_firing_hz = 0.0; firings_last_block = 0
	_eng_phase = 0.0; _eng_env = 0.0; _sub_env = 0.0; _eng_lp = 0.0
	_skid_amp = 0.0; _skid_hp = 0.0
	_jet_amp = 0.0; _jet_lp = 0.0
	_imp_env = 0.0; _imp_age = IMPACT_LIFE_S + 1.0; _imp_lp = 0.0
	_seed = 0x1234ABCD

func set_engine(rpm: float, load: float) -> void:
	_rpm = _num(rpm, 0.0, 20000.0)
	_load = _num(load, 0.0, 1.0)
	_firing_hz = _rpm / 60.0 * float(CYL) / 2.0

func set_skid(level: float) -> void:
	_skid = _num(level, 0.0, 1.0)

func set_nitro(on: bool) -> void:
	_nitro = on

# Текущая огибающая burst'а удара — для тестов: по ней видно, что trigger
# долетел до DSP-состояния, не вскрывая приватные поля.
func impact_env() -> float:
	return _imp_env

func trigger_impact(speed_kmh: float) -> void:
	var s := _num(speed_kmh, 0.0, 1000.0)
	if s < IMPACT_MIN_KMH: return
	_imp_env = clampf(0.25 + 0.65 * (s - IMPACT_MIN_KMH) / (IMPACT_FULL_KMH - IMPACT_MIN_KMH), 0.0, 0.95)
	_imp_age = 0.0

func _noise() -> float:
	# xorshift32: детерминирован, дёшев, управляемого шума этого хватает
	_seed ^= (_seed << 13) & 0xFFFFFFFF
	_seed ^= _seed >> 17
	_seed ^= (_seed << 5) & 0xFFFFFFFF
	return float(_seed & 0xFFFFFFFF) / 2147483647.5 - 1.0

func produce_block(count: int) -> PackedFloat32Array:
	var n := clampi(count, 0, MAX_BLOCK)
	var out := PackedFloat32Array()
	if n <= 0: return out
	out.resize(n)
	var dt := 1.0 / SAMPLE_RATE
	var eng_dec := exp(-dt / PULSE_DECAY_S)
	var sub_dec := exp(-dt / SUB_DECAY_S)
	var skid_slew := clampf(8.0 * dt, 0.0, 0.1)
	var jet_slew := clampf(5.0 * dt, 0.0, 0.1)
	var eng_lp_a := clampf(2.0 * PI * (40.0 + 60.0 * _load) * dt, 0.0, 0.9)
	var jet_lp_a := clampf(2.0 * PI * 1800.0 * dt, 0.0, 0.9)
	var skid_hp_a := clampf(2.0 * PI * 2600.0 * dt, 0.0, 0.9)
	var firings := 0
	var peak := 0.0
	var fstep := _firing_hz * dt
	var imp_dec := exp(-dt / IMPACT_DECAY_S)
	for i in n:
		var s := 0.0
		if fstep > 0.0:
			_eng_phase += fstep
			if _eng_phase >= 1.0:
				_eng_phase -= 1.0
				_eng_env = 0.55 + 0.45 * _load
				_sub_env = maxf(_sub_env, 0.3 + 0.35 * _load)
				firings += 1
		_eng_env *= eng_dec
		_sub_env *= sub_dec
		# шумовая составляющая мотора живёт только пока есть обороты: на нуле микшер
		# обязан давать настоящую тишину, а не дрейф фильтра
		if _rpm > 0.0:
			_eng_lp += eng_lp_a * (_noise() - _eng_lp)
			s += 0.5 * (_eng_env + 0.5 * _sub_env)
			s += ENG_NOISE_MIX * _eng_lp * (0.2 + 0.8 * _load) * minf(1.0, _rpm / 300.0)
		else:
			_eng_lp *= 0.9
		# визг резины: ВЧ-шум, амплитуда идёт со slew — на стыке блоков тише не щёлкает.
		# Молчаливый источник не считается вовсе: три фильтра на каждый отсчёт стоили
		# кадром там, где слышен только мотор (замер p_audio_perf).
		if _skid > 0.0 or _skid_amp > 0.001:
			_skid_amp += clampf(_skid * SKID_LIN - _skid_amp, -skid_slew, skid_slew)
			var skid_n := _noise()
			_skid_hp = _skid_hp + skid_hp_a * (skid_n - _skid_hp)
			s += _skid_amp * (skid_n - _skid_hp) * 1.4
		else:
			_skid_hp *= 0.9
		# струя нитро: узкополосный свист из LP-шума, тоже со slew
		if _nitro or _jet_amp > 0.001:
			_jet_amp += clampf((JET_LIN if _nitro else 0.0) - _jet_amp, -jet_slew, jet_slew)
			_jet_lp += jet_lp_a * (_noise() - _jet_lp)
			s += _jet_amp * _jet_lp * 2.2
		else:
			_jet_lp *= 0.9
		if _imp_age <= IMPACT_LIFE_S:
			_imp_age += dt
			var k := clampf(_imp_age / IMPACT_LIFE_S, 0.0, 1.0)
			var cut_a := clampf(2.0 * PI * lerpf(IMPACT_CUT_START, IMPACT_CUT_END, k) * dt, 0.0, 0.9)
			_imp_lp += cut_a * (_noise() - _imp_lp)
			_imp_env *= imp_dec
			s += _imp_lp * _imp_env * 1.6
		var lim := _limit(s)
		out[i] = lim
		var mag := absf(lim)
		if mag > peak: peak = mag
	firings_last_block = firings
	last_peak = peak
	return out

# Мягкий лимитер: ветвящаяся кривая держает выход строго в [-1,1] без щелчка на
# обрезке — громкие события складываются в насыщение, а не в клиппинг.
func _limit(x: float) -> float:
	var a := absf(x)
	if a <= 0.7: return x
	var s := 0.7 + (a - 0.7) / (1.0 + (a - 0.7) * 1.6)
	return minf(s, 0.999) * signf(x)
