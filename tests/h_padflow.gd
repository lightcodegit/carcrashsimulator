extends Node3D
# The gamepad handbrake is checked on the LIVE scene, not on a bare CarRig: h_handbrake_devices
# proved that the wheel brakes are the same from the keyboard and from the trigger, yet the
# player's complaint stayed. So the A button does something besides raising the "handbrake"
# action — and that can only be caught together with the HUD, the pause menu and control focus.
# K) the keyboard space bar, J) a real gamepad button through the full event path.
const WINDOW := 60
var _fails := 0
var gm: GameManager
var _dev := "key"
var _f := 0
var _v0 := 0.0
var _pos_before := Vector3.ZERO
var _curve: Array[float] = []
var _curves := {}
var _events := {}
var _pad := false
var _pad_hb: InputEventJoypadButton
var _pad_gas: InputEventJoypadMotion
var _key_gas: InputEventKey
var _key_hb: InputEventKey

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	_pad = not Input.get_connected_joypads().is_empty()
	for e in InputMap.action_get_events("throttle"):
		if e is InputEventKey: _key_gas = e
		elif e is InputEventJoypadMotion: _pad_gas = e
	for e in InputMap.action_get_events("handbrake"):
		if e is InputEventKey: _key_hb = e
		elif e is InputEventJoypadButton: _pad_hb = e
	# The curve is measured in the town: the arena and the track now have honest hills and
	# bumps (they used to be decoration), and a braking car used to run into them — the test
	# would then measure the relief instead of the handbrake. The town's flat asphalt is chosen for this.
	GameContext.select("sedan", "town")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().process_frame
	# we catch not the state but the fact itself: what managed to happen during the press
	gm.hud.menu_requested.connect(func(): _note("menu"))
	gm.hud.resume_requested.connect(func(): _note("resume"))
	gm.hud.restart_requested.connect(func(): _note("restart"))
	gm.hud.settings_requested.connect(func(): _note("settings"))
	if _pad: await _focus_trap()
	_start("key")

func _note(what: String) -> void:
	_events[what] = int(_events.get(what, 0)) + 1

# A live event travels two roads at once: Input updates the action states (which CarRig
# reads), while the viewport dispatches it to the controls (which the GUI reads: pause
# buttons, ui_accept). push_input by itself does NOT raise the action states — that is why a
# harness on a bare CarRig never saw this.
func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	get_viewport().push_input(ev)

func _key(e: InputEvent, down: bool) -> void:
	if e == null: return
	var ev := InputEventKey.new()
	ev.physical_keycode = (e as InputEventKey).physical_keycode
	ev.pressed = down
	_send(ev)

func _pad_btn(down: bool) -> void:
	if _pad_hb == null or not _pad: return
	var e := InputEventJoypadButton.new()
	e.button_index = _pad_hb.button_index
	e.device = 0
	e.pressed = down
	_send(e)

func _pad_axis(down: bool) -> void:
	if _pad_gas == null or not _pad: return
	var e := InputEventJoypadMotion.new()
	e.axis = _pad_gas.axis
	e.axis_value = signf(_pad_gas.axis_value) if down else 0.0
	e.device = 0
	_send(e)

func _gas(down: bool) -> void:
	if _dev == "joy": _pad_axis(down)
	else: _key(_key_gas, down)

func _hb(down: bool) -> void:
	if _dev == "joy": _pad_btn(down)
	else: _key(_key_hb, down)

func _start(dev: String) -> void:
	_dev = dev
	_f = 0
	_curve.clear()
	_events = {}
	_v0 = 0.0
	gm._respawn_now()
	_gas(true)

# The focus trap: a pause-menu button stays focused once its card is already hidden, and the
# gamepad A button is also ui_accept. So "handbrake" can end up pressing an invisible button,
# and the car stops dead — a restart or a trip back to the menu. That is exactly what we
# check: focus is set by hand, then the handbrake is pressed.
func _focus_trap() -> void:
	var b := gm.hud.pause_button("ЗАПУСТИТЬ ЗАНОВО")
	check(b != null, "the pause menu has a restart button")
	if b == null: return
	gm._set_paused(true)
	await get_tree().process_frame
	b.grab_focus()
	gm._set_paused(false)
	await get_tree().process_frame
	_events = {}
	_pad_btn(true)
	await get_tree().process_frame
	_pad_btn(false)
	await get_tree().process_frame
	check(_events.is_empty(),
		"a hidden button does not eat the gamepad handbrake (%s)" % str(_events.keys()))
	check(not gm._paused, "the handbrake does not pause the game through a hidden button")

func _physics_process(_dt: float) -> void:
	_f += 1
	# a trigger lives until the next event, but a button arrives once: for the action to stay
	# pressed the event must be sent every tick — which is what holding does
	if _dev == "joy": _gas(true)
	if _f == 150:
		_v0 = gm.car.speed_kmh()
		_pos_before = gm.car.chassis.global_position
		_hb(true)
	if _f > 150:
		_curve.append(gm.car.speed_kmh())
	if _f == 151 + WINDOW:
		_finish()

func _finish() -> void:
	var moved := gm.car.chassis.global_position.distance_to(_pos_before)
	check(_events.is_empty(), "%s: the handbrake leaves the interface alone (%s)" % [_dev, str(_events.keys())])
	check(not get_tree().paused, "%s: the handbrake does not pause the game" % _dev)
	check(moved > 1.0, "%s: the car keeps rolling instead of teleporting (%.1f m)" % [_dev, moved])
	check(_curve.size() >= WINDOW, "%s: the curve is captured in full (%d)" % [_dev, _curve.size()])
	# "instantly zeroes the speed" from a gamepad is about a short trigger tap, not about the
	# loss per second: over 1 s a normal 0.8 g deceleration is supposed to shed ~45% of the
	# speed. We measure the tap over 0.2 s and the peak tick, and the braking force in g.
	var tap := _v0 - _curve[11]
	var peak := 0.0
	for i in range(1, WINDOW):
		peak = maxf(peak, (_curve[i - 1] - _curve[i]) * 60.0 / 3.6 / 9.81)
	var g := (_v0 - _curve[WINDOW - 1]) / 3.6 / 9.81
	print("%s: handbrake in the live game at %.0f km/h = %.2f g, tap over 0.2 s %.1f km/h (%.0f%%), peak %.2f g" % [
		_dev, _v0, g, tap, tap / _v0 * 100.0, peak])
	check(tap < _v0 * 0.25, "%s: a short handbrake tap does not zero the speed (%.1f -> %.1f)" % [_dev, _v0, _v0 - tap])
	check(peak < 1.5, "%s: no tick brakes harder than the grip limit (%.2f g)" % [_dev, peak])
	check(g > 0.5, "%s: the handbrake brakes noticeably in the live game (%.2f g)" % [_dev, g])
	_curves[_dev] = _curve.duplicate()
	_hb(false)
	_gas(false)
	if _dev == "key" and _pad:
		_start("joy")
	else:
		if _pad:
			var k: Array = _curves["key"]
			var j: Array = _curves["joy"]
			var worst := 0.0
			for i in WINDOW: worst = maxf(worst, absf(k[i] - j[i]))
			check(worst < 8.0, "a live gamepad and the keyboard slow down alike (spread %.1f km/h)" % worst)
		else:
			print("PARTIAL: no gamepad connected — only the keyboard was checked")
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
