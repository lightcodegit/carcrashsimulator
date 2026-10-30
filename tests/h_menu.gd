extends Control
var _f := 0
func _ready() -> void:
	add_child(load("res://scenes/main_menu.tscn").instantiate())
func _process(_d: float) -> void:
	_f += 1
	if _f == 8:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/menu.png")
		get_tree().quit(0)
