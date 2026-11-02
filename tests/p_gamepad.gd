extends Node3D
# Что движок видит от живого геймпада: имя устройства, знает ли он его раскладку и
# какими индексами приходят кнопки. Без этого спорить о том, что игрок называет
# «кнопкой ручника», можно только гадать. Печатает только числа и строки.
var _f := 0
var _seen := {}

func _ready() -> void:
	for a in InputRouter.DEFAULTS:
		print("BIND %s -> %s" % [a, InputRouter.describe(a)])
	print("PADS: ", Input.get_connected_joypads())
	for d in Input.get_connected_joypads():
		print("DEV %d: name=%s known=%s" % [d, Input.get_joy_name(d), Input.is_joy_known(d)])
		for axis in 8:
			print("  AXIS %d = %.2f" % [axis, Input.get_joy_axis(d, axis)])

func _process(_dt: float) -> void:
	_f += 1
	for d in Input.get_connected_joypads():
		for b in 20:
			if Input.is_joy_button_pressed(d, b) and not _seen.has([d, b]):
				_seen[[d, b]] = true
				print("BUTTON DOWN dev=%d idx=%d" % [d, b])
			elif not Input.is_joy_button_pressed(d, b) and _seen.has([d, b]):
				_seen.erase([d, b])
				print("BUTTON UP   dev=%d idx=%d" % [d, b])
		for a in [4, 5]:
			var v := Input.get_joy_axis(d, a)
			if absf(v) > 0.05: print("TRIG dev=%d axis=%d v=%.2f" % [d, a, v])
	for act in ["throttle", "brake", "handbrake", "respawn", "slowmo", "cam_cycle", "pause"]:
		var s := Input.get_action_strength(act)
		if s > 0.0 and not _seen.has(act):
			_seen[act] = true
			print("ACTION %s = %.2f" % [act, s])
		elif s <= 0.0 and _seen.has(act):
			_seen.erase(act)
			print("ACTION %s off" % act)
	if _f > 3000: get_tree().quit(0)
