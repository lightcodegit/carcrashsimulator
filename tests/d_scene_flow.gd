extends SceneTree
# Scene transitions: held keys must not travel into a new run, and returning to the
# menu must not leave the tree paused.
# Run: godot --headless --path . --fixed-fps 60 --script res://tests/d_scene_flow.gd
var _f := 0
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _held() -> String:
	var out := ""
	for a in ["throttle", "brake", "handbrake", "steer_left", "steer_right", "slowmo"]:
		if Input.is_action_pressed(a): out += a + " "
	return out

func _process(_d: float) -> bool:
	_f += 1
	match _f:
		3:
			change_scene_to_file("res://scenes/game.tscn")
		30:
			var gm = current_scene.get_children()[0] if current_scene.get_child_count() else null
			check(current_scene.scene_file_path == "res://scenes/game.tscn", "game loaded")
			Input.action_press("throttle")
			Input.action_press("handbrake")
		40:
			check(_held() == "throttle handbrake ", "precondition: keys are held (%s)" % _held())
			change_scene_to_file("res://scenes/main_menu.tscn")
		60:
			check(_held() == "throttle handbrake ", "the menu does not release keys itself — check on game entry")
			change_scene_to_file("res://scenes/game.tscn")
		95:
			check(_held() == "", "a new run starts with no held keys (%s)" % _held())
			check(not paused, "after returning from the menu the tree is not paused")
			print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
			quit(0 if _fails == 0 else 1)
			return true
	return false
