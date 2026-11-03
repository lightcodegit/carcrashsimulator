extends Node
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)
func _physics_process(_dt: float) -> void:
	check(InputMap.has_action("throttle"), "throttle action registered")
	# «клавиша + геймпад» по общему числу событий не проверить: два джойстиковых
	# события без единой клавиши дают те же 2. Считаем по типу события.
	var keys := 0
	var pads := 0
	for e in InputMap.action_get_events("handbrake"):
		if e is InputEventKey: keys += 1
		elif e is InputEventJoypadButton or e is InputEventJoypadMotion: pads += 1
	check(keys >= 1, "у ручника есть клавиша (%d)" % keys)
	check(pads >= 1, "у ручника есть геймпад (%d)" % pads)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
