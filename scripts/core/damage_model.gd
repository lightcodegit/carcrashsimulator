class_name DamageModel
extends RefCounted

signal zone_hp_changed(zone: int, hp: float)
signal totaled_changed(is_totaled_now: bool)

var _cap: Array[int] = [1, 1, 1, 1, 1]
var _broken: Array[int] = [0, 0, 0, 0, 0]
var _totaled := false

func bind_spec(spec: ShellSpec) -> void:
	_cap = spec.zone_spring_totals.duplicate()
	reset()

func bind_shell(shell: SoftShell) -> void:
	bind_spec(shell.spec)
	shell.spring_burst.connect(func(z): report_breaks(z, 1))

func reset() -> void:
	_broken = [0, 0, 0, 0, 0]
	if _totaled: totaled_changed.emit(false)
	_totaled = false

func report_breaks(zone: int, n: int) -> void:
	_broken[zone] += n
	zone_hp_changed.emit(zone, hp(zone))
	var was := _totaled
	_totaled = is_totaled()
	if was != _totaled: totaled_changed.emit(_totaled)

func hp(zone: int) -> float:
	return 100.0 * clampf(1.0 - float(_broken[zone]) / maxf(1.0, 0.35 * float(_cap[zone])), 0.0, 1.0)

func hp_array() -> Array[float]:
	return [hp(0), hp(1), hp(2), hp(3), hp(4)]

func worst_zone() -> int:
	var w := 0
	for z in 5:
		if hp(z) < hp(w): w = z
	return w

func is_totaled() -> bool:
	return hp(worst_zone()) <= 0.5
