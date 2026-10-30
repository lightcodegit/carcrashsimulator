extends Control
var _f := 0
var mm
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
func _process(_d: float) -> void:
	_f += 1
	if _f == 8:
		print("SIZES mm=" + str(mm.size) + " colpos=" + str(mm.get_child(1).global_position))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/menu.png")
		get_tree().quit(0)
