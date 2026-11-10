extends Node
# Menu and settings frames at a chosen window size (we set the size ourselves: cfg
# overrides --resolution). Checking whether the layout slips without scaling.

var _f := 0
var _stable := 0
var mm: Node
var _want := Vector2i(1920, 1080)
var _stage := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w"):
			var ww := int(a.substr(1))
			_want = Vector2i(ww, int(ww * 9.0 / 16.0))
		elif a == "s2":
			UiTheme.force_step(2)
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/out/%s.png" % name)
	print("SHOT %s %dx%d" % [name, img.get_width(), img.get_height()])

func _process(_d: float) -> void:
	_f += 1
	if _f < 20:
		return
	if _stage == 0:
		DisplayServer.window_set_size(_want)
		if get_window().size == _want:
			_stable += 1
			if _stable >= 8:
				_stage = 1
		else:
			_stable = 0
	elif _stage == 1:
		mm._show_section(3)
		_stage = 2
	elif _stage == 2 and _f % 3 == 0:
		mm._settings._show_tab(1)
		_stage = 3
	elif _stage == 3:
		_stage = 4
		_do_shots()

func _do_shots() -> void:
	var tag := "%dx%d" % [_want.x, _want.y]
	await _shot("stretch_menu_" + tag)
	mm._show_section(3)
	await get_tree().create_timer(0.3).timeout
	mm._settings._show_tab(0)
	await get_tree().create_timer(0.3).timeout
	await _shot("stretch_quality_" + tag)
	mm._settings._show_tab(1)
	await get_tree().create_timer(0.3).timeout
	await _shot("stretch_video_" + tag)
	get_tree().quit(0)
