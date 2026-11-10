extends Node
# Frames the GRAPHICS tab during an embedded run: the note about the editor
# window must fit in full and sit directly under its own heading.

var _f := 0
var mm: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)

func _process(_d: float) -> void:
	_f += 1
	if _f == 60:
		mm._show_section(3)
	if _f == 80:
		mm._settings._show_tab(1)
	if _f == 100:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/embed_note.png")
		print("SHOT embedded=%s" % str(Engine.is_embedded_in_editor()))
		get_tree().quit(0)
