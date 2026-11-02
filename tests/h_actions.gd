extends Node
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)
func _physics_process(_dt: float) -> void:
	check(InputMap.has_action("throttle"), "throttle action registered")
	check(InputMap.action_get_events("handbrake").size() >= 2, "handbrake keys+pad")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
