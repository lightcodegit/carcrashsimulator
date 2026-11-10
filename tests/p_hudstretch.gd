extends Node
# The live HUD at a chosen window size with 2D 1:1: speedometer, panels, log.

var _f := 0
var _stable := 0
var _stage := 0
var gm: Node
var _want := Vector2i(1920, 1080)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w"):
			var ww := int(a.substr(1))
			_want = Vector2i(ww, int(ww * 9.0 / 16.0))
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/out/%s.png" % name)
	print("SHOT " + name)

func _process(_d: float) -> void:
	_f += 1
	if _f < 20:
		return
	match _stage:
		0:
			DisplayServer.window_set_size(_want)
			if get_window().size == _want:
				_stable += 1
				if _stable >= 8:
					_stage = 1
			else:
				_stable = 0
		1:
			if _f % 5 == 0:
				Input.action_press("throttle")
			if _f > 120:
				Input.action_release("throttle")
				_stage = 2
		2:
			_stage = 3
			_run()

func _run() -> void:
	var tag := "%dx%d" % [_want.x, _want.y]
	await _shot("hud_" + tag)
	gm._set_paused(true)
	await get_tree().create_timer(0.4).timeout
	await _shot("hud_pause_" + tag)
	get_tree().quit(0)
