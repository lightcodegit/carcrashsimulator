extends Node
var _f := 0
var mm: Node3D
var gm: GameManager
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/out/" + name + ".png")
func _process(_d: float) -> void:
	_f += 1
	if _f == 60: _shot("ui_menu_play")
	if _f == 70: mm._show_section(1)
	if _f == 85: _shot("ui_menu_vehicles")
	if _f == 95: mm._show_section(3)
	if _f == 115: _shot("ui_settings_quality")
	if _f == 125: mm._settings._show_tab(1)
	if _f == 140: _shot("ui_settings_video")
	if _f == 150: mm._settings._show_tab(3)
	if _f == 165: _shot("ui_settings_keys")
	if _f == 175:
		mm._settings.close()
		remove_child(mm)
		mm.queue_free()
	if _f == 180:
		gm = load("res://scenes/game.tscn").instantiate()
		add_child(gm)
	if _f == 240: gm._set_paused(true)
	if _f == 260: _shot("ui_pause")
	if _f == 270: get_tree().quit(0)
