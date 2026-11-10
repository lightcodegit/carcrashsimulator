extends Node
# Clean font experiment: a flat dark backdrop plus a caption. No 3D background
# that could spoil the edge measurement. The same logical rectangle is measured
# under different screen transforms.

const TEXT := "ЩУК 0123 ПИВО-НАСТРОЙКИ"
const LOGICAL := Rect2i(40, 60, 640, 120)
const SIZES := [16, 20, 26, 48]

var _f := 0
var _step := 0
var _stable := 0
var _sizes := [Vector2i(1600, 900), Vector2i(3200, 1800), Vector2i(2400, 1350), Vector2i(1920, 1080)]
var _box: ColorRect
var _labs: Array[Label] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	_box = ColorRect.new()
	_box.color = Color(0.07, 0.08, 0.10)
	_box.size = Vector2(1600, 400)
	add_child(_box)
	for i in SIZES.size():
		var l := Label.new()
		l.text = TEXT
		l.add_theme_font_override("font", UiTheme.sans_font(600))
		l.add_theme_font_size_override("font_size", SIZES[i])
		l.add_theme_color_override("font_color", Color.WHITE)
		l.position = Vector2(LOGICAL.position.x, 40 + i * 70)
		add_child(l)
		_labs.append(l)

func _process(_d: float) -> void:
	_f += 1
	if _f < 20:
		return
	if _step >= _sizes.size():
		get_tree().quit(0)
		return
	var want: Vector2i = _sizes[_step]
	if _f % 4 == 0:
		DisplayServer.window_set_size(want)
	if get_window().size == want:
		_stable += 1
		if _stable >= 8:
			_report(want)
			_step += 1
			_stable = 0
	else:
		_stable = 0

func _report(want: Vector2i) -> void:
	var vp := get_viewport()
	var st := vp.get_screen_transform()
	var k: float = st.get_scale().x
	var tex := vp.get_texture().get_image()
	for i in SIZES.size():
		var lr := Rect2i(LOGICAL.position.x, 40 + i * 70, 640, 56)
		var r := Rect2i(int(lr.position.x * k), int(lr.position.y * k),
			int(lr.size.x * k), int(lr.size.y * k))
		r = r.intersection(Rect2i(0, 0, tex.get_width(), tex.get_height()))
		var img := tex.get_region(r)
		var tag := "%dx%d_k%.2f_f%d" % [want.x, want.y, k, SIZES[i]]
		img.save_png("res://tests/out/font_%s.png" % tag)
		var bytes := img.get_data()
		var w := img.get_width()
		var h := img.get_height()
		var d := PackedFloat32Array()
		d.resize(maxi(w - 1, 1) * h)
		var j := 0
		for y in h:
			var row := y * w * 4
			for x in range(1, w):
				var a := row + (x - 1) * 4
				var b := row + x * 4
				var la := (bytes[a] * 0.3 + bytes[a + 1] * 0.59 + bytes[a + 2] * 0.11) / 255.0
				var lb := (bytes[b] * 0.3 + bytes[b + 1] * 0.59 + bytes[b + 2] * 0.11) / 255.0
				d[j] = absf(lb - la)
				j += 1
		d.sort()
		var n := d.size()
		var hard := 0
		var soft := 0
		for m in n:
			if d[m] > 0.25:
				hard += 1
			elif d[m] > 0.05:
				soft += 1
		var line := "%s | frame=%dx%d | p99=%.4f max=%.4f | hard=%d soft=%d" % [
			tag, tex.get_width(), tex.get_height(), d[int(n * 0.99)], d[n - 1], hard, soft]
		print(line)
		var f := FileAccess.open("res://tests/out/font_matrix.txt", FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open("res://tests/out/font_matrix.txt", FileAccess.WRITE)
			f.store_line(line + "\n")
		else:
			f.seek_end()
			f.store_line(line + "\n")
		f = null
