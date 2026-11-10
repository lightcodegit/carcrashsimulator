extends SceneTree
# Procedural mixer (pure DSP, no AudioServer): finiteness on poison inputs,
# silence without sources, RMS monotonicity over rpm, flash frequency matching
# rpm, impact decay, skid growth, the [-1,1] bound and determinism.

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _rms(a: PackedFloat32Array) -> float:
	var s := 0.0
	for x in a: s += x * x
	return sqrt(s / maxf(1.0, float(a.size())))

func _peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for x in a: p = maxf(p, absf(x))
	return p

func _all_finite(a: PackedFloat32Array) -> bool:
	for x in a:
		if not is_finite(x): return false
	return true

func _silence() -> AudioMixer:
	var m := AudioMixer.new()
	m.reset()
	return m

func _initialize() -> void:
	_poison()
	_silence_and_bounds()
	_rpm_monotonic()
	_firing_hz()
	_impact()
	_skid()
	_nitro()
	_determinism()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)

# INF/NAN/negative/extreme inputs must not poison a single sample.
func _poison() -> void:
	var m := _silence()
	m.set_engine(INF, NAN)
	m.set_skid(-INF)
	m.set_nitro(true)
	m.trigger_impact(NAN)
	var a := m.produce_block(4096)
	check(a.size() == 4096, "poison inputs: block of requested length (%d)" % a.size())
	check(_all_finite(a), "poison inputs: all samples finite")
	check(_peak(a) <= 1.0 + 1e-9, "poison inputs: output within bound (%.3f)" % _peak(a))
	m.set_engine(1e12, 50.0)
	m.trigger_impact(1e9)
	var b := m.produce_block(2048)
	check(_all_finite(b) and _peak(b) <= 1.0 + 1e-9, "extreme rpm: finiteness and bound (%.3f)" % _peak(b))
	check(m.produce_block(-5).is_empty() and m.produce_block(0).is_empty(), "zero/negative request — empty block")

func _silence_and_bounds() -> void:
	var m := _silence()
	m.set_engine(0.0, 0.0)
	m.set_skid(0.0)
	m.set_nitro(false)
	var a := m.produce_block(4410)
	check(_peak(a) < 0.001, "no sources — silence (peak %.6f)" % _peak(a))

# RMS grows with rpm: more flashes per second — more energy in the block.
# Measured on long blocks (0.5 s) so the flash phase has time to average out.
func _rpm_monotonic() -> void:
	var prev := 0.0
	var first := -1.0
	var rpms := [600.0, 1500.0, 3000.0, 6000.0]
	for rpm in rpms:
		var m := _silence()
		var rms := 0.0
		for k in 3:
			m.set_engine(rpm, 1.0)
			rms = maxf(rms, _rms(m.produce_block(22050)))
		print("rpm=%.0f rms=%.4f" % [rpm, rms])
		check(rms > 0.001, "rpm %.0f: engine is not silent (%.4f)" % [rpm, rms])
		if first < 0.0: first = rms
		check(rms > prev, "rpm %.0f: RMS greater than previous (%.4f > %.4f)" % [rpm, rms, prev])
		prev = rms

# Expected flash count per block = rpm/60 × cylinders/2; the mixer counter must
# match a whole number of periods (the block is exactly one second).
func _firing_hz() -> void:
	for rpm in [1200.0, 1800.0, 3000.0]:
		var m := _silence()
		m.set_engine(rpm, 1.0)
		var want_hz: float = float(rpm) / 60.0 * AudioMixer.CYL / 2.0
		check(is_equal_approx(m.firing_hz(), want_hz), "firing_hz=%.1f at rpm=%.0f (expected %.1f)" % [m.firing_hz(), rpm, want_hz])
		var n := m.produce_block(44100).size()
		check(n == 44100, "one-second block delivered in full (%d)" % n)
		print("rpm=%.0f: flashes per second %d (expected %.0f)" % [rpm, m.firings_last_block, want_hz])
		check(absf(float(m.firings_last_block) - want_hz) <= 1.0, "flashes per block %.0f±1 (counter %d)" % [want_hz, m.firings_last_block])

func _impact() -> void:
	var quiet := _silence()
	var p0 := _peak(quiet.produce_block(4410))
	var m := _silence()
	m.trigger_impact(120.0)
	var hit := m.produce_block(4410)
	var p1 := _peak(hit)
	check(p1 > p0 + 0.05, "120 km/h impact louder than silence (%.3f vs %.6f)" % [p1, p0])
	check(p1 <= 1.0 + 1e-9, "impact within bound [-1,1] (%.3f)" % p1)
	var prev := p1
	for k in 4:
		var a := m.produce_block(4410)
		var p := _peak(a)
		check(p < prev, "impact decays (step %d: %.3f < %.3f)" % [k, p, prev])
		prev = p
	var slow := _silence()
	var fast := _silence()
	slow.trigger_impact(20.0)
	fast.trigger_impact(190.0)
	check(_peak(fast.produce_block(4410)) > _peak(slow.produce_block(4410)),
		"peak impact louder than the weak one")

func _skid() -> void:
	var m := _silence()
	m.set_skid(0.0)
	var r0 := _rms(m.produce_block(4410))
	m.set_skid(0.9)
	var r1 := 0.0
	for k in 4: r1 = _rms(m.produce_block(4410))
	check(r1 > r0 + 0.002, "skid adds energy (%.4f vs %.6f)" % [r1, r0])
	check(_peak(m.produce_block(4410)) <= 1.0 + 1e-9, "skid within bound")

func _nitro() -> void:
	var m := _silence()
	m.set_nitro(false)
	var r0 := _rms(m.produce_block(4410))
	m.set_nitro(true)
	var r1 := 0.0
	for k in 4: r1 = _rms(m.produce_block(4410))
	check(r1 > r0 + 0.002, "jet exhaust is audible (%.4f vs %.6f)" % [r1, r0])

# The same path on two instances with one fixed seed — bit-for-bit the same
# signal. reset() returns the noise generator to its factory seed, so the tests
# are reproducible without passing a number explicitly.
func _determinism() -> void:
	var a := _silence()
	var b := _silence()
	a.set_engine(2400.0, 0.8); a.set_skid(0.5); a.set_nitro(true); a.trigger_impact(90.0)
	b.set_engine(2400.0, 0.8); b.set_skid(0.5); b.set_nitro(true); b.trigger_impact(90.0)
	var x := a.produce_block(8000)
	var y := b.produce_block(8000)
	var same := x.size() == y.size() and x.size() == 8000
	if same:
		for i in x.size():
			if x[i] != y[i]: same = false; break
	check(same, "two instances on the same factory seed: blocks matched bit for bit")
	var c := _silence()
	c.set_engine(NAN, 0.8)
	check(_all_finite(c.produce_block(1000)), "NAN input after reset stays finite")
