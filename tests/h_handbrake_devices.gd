extends Node3D
# The handbrake must not depend on what triggered it: keyboard and gamepad brake the
# car identically, the lock stays on the rear axle (the front picks up only a share of
# the braking and keeps steering), and braking force is measured in g — the complaint
# "the handbrake barely brakes" is about magnitude, not the fact it fires: losing
# 5 km/h from 60 is 0.14 g, and the old check could not see it.
# K) accelerate and handbrake via keyboard events
# J) the same via real gamepad events (trigger + button)
# Runs: with the throttle held (drift), released (braking proper), and the foot brake as
# a ruler — the handbrake must stop shorter than the pedal, not longer.
const WINDOW := 60
const RUNS := ["key:gas", "key:coast", "key:foot", "joy:gas", "joy:coast"]
var car: CarRig
var _run_i := 0
var _dev := "key"
var _mode := "gas"
var _f := 0
var _v0 := 0.0
var _curve: Array[float] = []
var _curves := {}
var _gs := {}
var _pads := true
var _brake_ok := true
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

# Events come from the CURRENT layout, not hardcoded keys: the tests run on the
# player's machine, where they may have their own bindings, and checking "space is the
# handbrake" catches someone's settings, not behaviour.
static func _first_of(action: String, cls: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if cls == "key" and e is InputEventKey: return e
		if cls == "pad" and (e is InputEventJoypadButton or e is InputEventJoypadMotion): return e
	return null

var _key_gas: InputEventKey
var _key_hb: InputEventKey
var _key_brk: InputEventKey
var _pad_gas: InputEventJoypadMotion
var _pad_hb: InputEventJoypadButton

func _key(e: InputEventKey, down: bool) -> void:
	if e == null: return
	var ev := e as InputEventKey
	var out := InputEventKey.new()
	out.physical_keycode = ev.physical_keycode
	out.pressed = down
	Input.parse_input_event(out)

func _pad_btn(down: bool) -> void:
	if _pad_hb == null: return
	var e := InputEventJoypadButton.new()
	e.button_index = _pad_hb.button_index
	e.device = 0
	e.pressed = down
	Input.parse_input_event(e)

# InputEventJoypadMotion has no pressed: the state is carried by axis_value itself, and
# a trigger stays "held" only if a value arrives on every poll. The value uses the FULL
# travel (1.0 with the binding's sign), not the layout's 0.5 threshold: otherwise the
# comparison with the keyboard is unfair — on the keyboard throttle = 1.0.
func _pad_axis(down: bool) -> void:
	if _pad_gas == null: return
	var e := InputEventJoypadMotion.new()
	e.axis = _pad_gas.axis
	e.axis_value = (signf(_pad_gas.axis_value) if down else 0.0)
	e.device = 0
	Input.parse_input_event(e)

func _gas(down: bool) -> void:
	if _dev == "joy":
		_pad_axis(down)
	else:
		_key(_key_gas, down)

func _brk(down: bool) -> void:
	_key(_key_brk, down)

func _hb(down: bool) -> void:
	if _dev == "joy":
		_pad_btn(down)
	else:
		_key(_key_hb, down)

func _start(run: String) -> void:
	var parts: PackedStringArray = run.split(":")
	_dev = parts[0]
	_mode = parts[1]
	_f = 0
	_v0 = 0.0
	_brake_ok = true
	_curve.clear()
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	_hb(false)
	_brk(false)
	_gas(true)

func _ready() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(2400, 2, 900); cs.shape = bx
	fb.add_child(cs); add_child(fb); fb.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	_key_gas = _first_of("throttle", "key") as InputEventKey
	_key_hb = _first_of("handbrake", "key") as InputEventKey
	_key_brk = _first_of("brake", "key") as InputEventKey
	_pad_gas = _first_of("throttle", "pad") as InputEventJoypadMotion
	_pad_hb = _first_of("handbrake", "pad") as InputEventJoypadButton
	check(_key_gas != null and _key_hb != null, "throttle and handbrake have a keyboard event")
	if Input.get_connected_joypads().is_empty():
		print("PARTIAL: no gamepad connected — device comparison is skipped, only the keyboard is checked")
		_pads = false
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	_start(RUNS[0])

func _check_axles() -> void:
	# The rear axle is locked and has no drive; the front on throttle pulls (a drift can
	# steer), coasts freely, but is in any case braked NOT harder than the rear. Setting
	# brake via chassis.brake makes Godot apply it to all four wheels at once, and locking
	# four wheels pins the car to a spot — exactly the old gamepad complaint.
	var rear_max := 0.0
	for w in car._wheels:
		if not w.use_as_steering: rear_max = maxf(rear_max, w.brake)
	for w in car._wheels:
		var front := w.use_as_steering
		if front and w.brake >= rear_max: _brake_ok = false
		if front and _mode == "gas" and w.engine_force <= 0.0: _brake_ok = false
		if not front and (w.brake <= 0.0 or w.engine_force != 0.0): _brake_ok = false

func _physics_process(_dt: float) -> void:
	_f += 1
	# both the trigger and a held key reach the game as an event every tick:
	# Godot applies action state only at the end of the frame
	if _dev == "joy" and _mode == "gas": _gas(true)
	if _f == 150:
		_v0 = car.speed_kmh()
		if _mode == "foot": _brk(true)
		else: _hb(true)
		if _mode != "gas": _gas(false)
	if _f > 150:
		_curve.append(car.speed_kmh())
		# CarRig is a child of the harness, so its _physics_process runs after ours:
		# the wheel state for the tick becomes visible only on the next one
		if _f == 155: _check_axles()
	if _f == 151 + WINDOW:
		var run: String = RUNS[_run_i]
		_curves[run] = _curve.duplicate()
		if _mode != "foot": check(_brake_ok, "%s: the handbrake locks only the rear axle" % run)
		var g := (_v0 - _curve[WINDOW - 1]) / 3.6 / 9.81
		# the gamepad's "instant stop" is not about the loss over a second but a short
		# trigger tap: measure how much the car lost within 0.2 s and what the peak
		# braking tick was. The old threshold ("more than 60% of speed left after 1 s")
		# masked both a normal 0.8 g stop and the complaint — it could not tell them apart.
		var tap := _v0 - _curve[11]
		var peak := 0.0
		for i in range(1, WINDOW):
			peak = maxf(peak, (_curve[i - 1] - _curve[i]) * 60.0 / 3.6 / 9.81)
		var what := "foot brake" if _mode == "foot" else "handbrake"
		print("%s: %s on %.0f km/h loses %.1f km/h in 1 s = %.2f g, tap in 0.2 s %.1f km/h (%.0f%%), peak %.2f g" % [
			run, what, _v0, _v0 - _curve[WINDOW - 1], g, tap, tap / _v0 * 100.0, peak])
		_gs[run] = g
		if _mode == "foot":
			# the window was raised together with BRAKE_MAX_G (1.25→1.65 g): the pedal at
			# 57 km/h now measures 1.23 g with a 1.39 peak; the 1.5 cap still catches the
			# "hit on an invisible wall" the window was invented for (the old run gave 2.7 g)
			check(g < 1.5, "%s: pedal within the tyre limit (%.2f g)" % [run, g])
		elif _mode == "gas":
			check(g > 0.55, "%s: the handbrake brakes even with the throttle held (%.2f g)" % [run, g])
			check(g < 1.1, "%s: handbrake on throttle is not an invisible-wall hit (%.2f g)" % [run, g])
		else:
			check(g > 0.7, "%s: off throttle the handbrake brakes like the pedal (%.2f g)" % [run, g])
			check(g < 1.15, "%s: the coasting handbrake stays braking, not stopping (%.2f g)" % [run, g])
		check(tap < _v0 * 0.25, "%s: a short handbrake tap does not zero the speed (%.1f -> %.1f)" % [run, _v0, _v0 - tap])
		check(peak < 1.5, "%s: no tick brakes harder than the grip limit (%.2f g)" % [run, peak])
		check(_curve[WINDOW - 1] > 0.0, "%s: the car keeps moving (%.1f km/h)" % [run, _curve[WINDOW - 1]])
		_hb(false)
		_brk(false)
		_gas(false)
		_run_i += 1
		while _run_i < RUNS.size() and not _pads and RUNS[_run_i].begins_with("joy"):
			_run_i += 1
		if _run_i < RUNS.size():
			_start(RUNS[_run_i])
			return
		if _gs.has("key:foot"):
			check(_gs["key:foot"] > _gs.get("key:coast", 0.0),
				"the pedal does not brake shorter than the handbrake (%.2f g vs %.2f g)" % [_gs["key:foot"], _gs.get("key:coast", 0.0)])
		if _pads:
			for mode in ["gas", "coast"]:
				var k: Array = _curves["key:" + mode]
				var j: Array = _curves["joy:" + mode]
				var worst := 0.0
				for i in WINDOW:
					worst = maxf(worst, absf(k[i] - j[i]))
				check(worst < 2.0, "gamepad and keyboard brake identically (%s, spread %.2f km/h)" % [mode, worst])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
