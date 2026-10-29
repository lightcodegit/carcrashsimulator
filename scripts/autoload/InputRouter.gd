extends Node
const ACTIONS := {
	"throttle":   {"keys": [[KEY_W], [KEY_UP]], "joy": [["motion", 5, 0.5]]},
	"brake":      {"keys": [[KEY_S], [KEY_DOWN]], "joy": [["motion", 4, 0.5]]},
	"steer_left": {"keys": [[KEY_A], [KEY_LEFT]], "joy": [["motion", 0, -0.5]]},
	"steer_right":{"keys": [[KEY_D], [KEY_RIGHT]], "joy": [["motion", 0, 0.5]]},
	"handbrake":  {"keys": [[KEY_SPACE]], "joy": [["button", 0]]},
	"slowmo":     {"keys": [[KEY_SHIFT]], "joy": [["button", 1]]},
	"cam_cycle":  {"keys": [[KEY_C]], "joy": [["button", 2]]},
	"respawn":    {"keys": [[KEY_R]], "joy": [["button", 3]]},
	"pause":      {"keys": [[KEY_ESCAPE]], "joy": [["button", 6]]},
}
func _ready() -> void:
	for name_v in ACTIONS:
		if not InputMap.has_action(name_v): InputMap.add_action(name_v)
		for kd in ACTIONS[name_v].keys:
			var e := InputEventKey.new(); e.physical_keycode = kd[0]
			InputMap.action_add_event(name_v, e)
		for jd in ACTIONS[name_v].joy:
			if jd[0] == "button":
				var b := InputEventJoypadButton.new(); b.button_index = jd[1]
				InputMap.action_add_event(name_v, b)
			else:
				var m := InputEventJoypadMotion.new(); m.axis = jd[1]; m.axis_value = jd[2]
				InputMap.action_add_event(name_v, m)
