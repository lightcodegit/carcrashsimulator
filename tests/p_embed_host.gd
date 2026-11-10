extends Node

# Host: an "editor" window the game is embedded into via --wid.
# Writes its native handle to a file and lives for a fixed number of frames.

const OUT := "res://tests/out/embed_host.txt"
const LIFE := 400

var _frames := 0

func _ready() -> void:
	get_window().title = "embed host"
	get_window().size = Vector2i(1400, 900)
	get_window().position = Vector2i(-12000, -12000)
	var h := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_line("handle=%s" % str(h))
		f.store_line("host size=%s pos=%s" % [str(get_window().size), str(get_window().position)])
		f = null
	print("HOST handle=%s" % str(h))

func _process(_d: float) -> void:
	_frames += 1
	if _frames >= LIFE:
		get_tree().quit(0)
