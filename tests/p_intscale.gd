extends Node
# Decisive experiment: an exact 2x factor against native 2x pixels with no
# scaling. If the text at k=2.0 is as sharp as a natively doubled font, the
# engine rasterises glyphs into the final pixels and the steps can be made by
# content_scale_size itself. If it is blurrier, px() must be multiplied instead.

var _f := 0
var _stable := 0
var _done := false
var _want := Vector2i(1600, 900)
var _half := false
var _px := 32

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	for a in OS.get_cmdline_user_args():
		if a == "half":
			_half = true
		elif a.begins_with("px"):
			_px = int(a.substr(2))
		elif a.begins_with("w"):
			var ww := int(a.substr(1))
			_want = Vector2i(ww, int(ww * 9.0 / 16.0))
	var box := ColorRect.new()
	box.color = Color(0.07, 0.08, 0.10)
	box.size = Vector2(4000, 400)
	add_child(box)
	var l := Label.new()
	l.text = "ЩУК 0123 ПИВО-НАСТРОЙКИ"
	l.add_theme_font_override("font", UiTheme.sans_font(600))
	l.add_theme_font_size_override("font_size", _px)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.position = Vector2(40, 60)
	add_child(l)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE

func _process(_d: float) -> void:
	_f += 1
	if _f < 20 or _done:
		return
	if _f % 4 == 0:
		DisplayServer.window_set_size(_want)
	if get_window().size != _want:
		return
	_stable += 1
	if _stable < 8:
		return
	_done = true
	if _half:
		get_window().content_scale_size = _want / 2
	else:
		get_window().content_scale_size = _want
	await get_tree().create_timer(0.5).timeout
	_report()
	get_tree().quit(0)

func _report() -> void:
	var vp := get_viewport()
	var st := vp.get_screen_transform()
	var k: float = st.get_scale().x
	var tex := vp.get_texture().get_image()
	var lr := Rect2i(40, 50, int(_px * 12), int(_px * 2))
	var r := Rect2i(int(lr.position.x * k), int(lr.position.y * k),
		int(lr.size.x * k), int(lr.size.y * k))
	r = r.intersection(Rect2i(0, 0, tex.get_width(), tex.get_height()))
	var img := tex.get_region(r)
	var tag := "%s_px%d_k%.2f" % ["half" if _half else "one", _px, k]
	img.save_png("res://tests/out/scale_%s.png" % tag)
	var bytes := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	var d := PackedFloat32Array()
	d.resize(maxi(w - 1, 1) * h)
	var i := 0
	for y in h:
		var row := y * w * 4
		for x in range(1, w):
			var a := row + (x - 1) * 4
			var b := row + x * 4
			d[i] = absf((bytes[b] * 0.3 + bytes[b + 1] * 0.59 + bytes[b + 2] * 0.11)
				- (bytes[a] * 0.3 + bytes[a + 1] * 0.59 + bytes[a + 2] * 0.11)) / 255.0
			i += 1
	d.sort()
	var n := d.size()
	var hard := 0
	var soft := 0
	for m in n:
		if d[m] > 0.25:
			hard += 1
		elif d[m] > 0.05:
			soft += 1
	print("%s | window=%s | k=%.2f | frame=%dx%d | p99=%.4f max=%.4f | hard=%d soft=%d" % [
		tag, str(get_window().size), k, tex.get_width(), tex.get_height(),
		d[int(n * 0.99)], d[n - 1], hard, soft])
