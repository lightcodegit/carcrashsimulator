# Localization sweep: with language=en no menu section, the garage, the HUD or the pause
# screen may contain a single Cyrillic label. It catches exactly the defect class where a
# string gets concatenated or truncated before bind() and stops being a catalog key.
# Already caught real leaks twice (card descriptions and the pause summary).
extends Node

var _fails := 0

func _cyr(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 0x410 and c <= 0x44F) or c == 0x451 or c == 0x401: return true
	return false

func _walk(root: Node, ctx: String, out: Array) -> void:
	for c in root.get_children():
		if c is Control and not (c as Control).visible: continue
		if c is Label or c is Button or c is CheckBox:
			var t: String = (c as Control).get("text")
			if t != null and _cyr(t): out.append(ctx + " | " + t.replace("\n", " ⏎ "))
		_walk(c, ctx, out)

func _check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

# Recursively look through the sources for draw_string/draw_multiline_string calls where
# Cyrillic comes as a raw literal rather than inside I18n.t(…). Comments are dropped so
# that the Russian explanations of the line itself are not reported.
func _scan_draw_string_leaks(path: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(path)
	if da == null: return out
	for fn in da.get_files():
		if not fn.ends_with(".gd"): continue
		var fp := path + "/" + fn
		var f := FileAccess.open(fp, FileAccess.READ)
		if f == null: continue
		var lineno := 0
		for line in f.get_as_text().split("\n"):
			lineno += 1
			var code := line.split("#")[0]
			if (code.contains("draw_string") or code.contains("draw_multiline_string")) \
					and _cyr(code) and not code.contains("I18n.t("):
				out.append(fp + ":" + str(lineno))
	for d in da.get_directories():
		out.append_array(_scan_draw_string_leaks(path + "/" + d))
	return out

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	Settings.language = "en"
	I18n.set_locale("en")
	# A photo on disk so the gallery section builds with content: the count
	# label formats an argument and the thumbnail path runs — both were
	# invisible to this sweep while the folder stayed empty.
	var pd := DirAccess.open("user://")
	if pd != null and not pd.dir_exists("photos"): pd.make_dir("photos")
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.5, 0.7))
	img.save_png("user://photos/photo_0001.png")
	# 1) main menu: every section
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var nav: Array = mm._nav.duplicate()
	for i in nav.size() + 1:
		var found: Array = []
		_walk(mm, "menu#%d" % i, found)
		for f in found: print("CYR: " + f)
		_check(found.is_empty(), "menu section %d has no Cyrillic" % i)
		if i < nav.size():
			(nav[i] as Button).emit_signal("pressed")
			await get_tree().process_frame
			await get_tree().process_frame
	# The gallery with a photo on disk must be fully built: a label that formats
	# an argument against a key without a placeholder raised a formatting error
	# that aborted the section silently, below any text sweep — the grid is the
	# witness. This is why the photo is seeded before the walk.
	(mm._nav[4] as Button).emit_signal("pressed")   # Section.GALLERY
	await get_tree().process_frame
	await get_tree().process_frame
	# the settings preset grid lives on its own layer — search the section panel
	var grids: Array = mm._panel.find_children("*", "GridContainer", true, false)
	var cards: int = (grids[0] as GridContainer).get_child_count() if grids.size() == 1 else -1
	_check(grids.size() == 1 and cards == 1,
		"the gallery builds fully with a photo on disk (%d grids, %s cards)" % [grids.size(), str(cards)])
	# A label with format args against a key without a placeholder does NOT abort:
	# the engine logs a formatting error and returns an empty string, so the count
	# label would show nothing while the section looks alive. The text is the proof.
	var want_count: String = I18n.t("СНИМКОВ: %d") % [1]
	var count_ok := false
	for l in mm._panel.find_children("*", "Label", true, false):
		if String(l.text) == want_count: count_ok = true; break
	_check(count_ok, "the gallery count label shows the formatted count (%s expected)" % want_count)
	DirAccess.remove_absolute("user://photos/photo_0001.png")
	mm.queue_free()
	await get_tree().process_frame
	# 2) the run screen: HUD, pause
	GameContext.select("sedan", "arena")
	var gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for i in 5: await get_tree().physics_frame
	var found2: Array = []
	_walk(gm, "game", found2)
	for f in found2: print("CYR: " + f)
	_check(found2.is_empty(), "the HUD has no Cyrillic")
	gm._set_paused(true)
	await get_tree().process_frame
	var found3: Array = []
	_walk(gm, "pause", found3)
	for f in found3: print("CYR: " + f)
	_check(found3.is_empty(), "the pause screen has no Cyrillic")
	# The runtime walk only sees the text of Label/Button/CheckBox nodes. Text drawn
	# directly through draw_string (the speed/nitro dial) is not a node and slips past
	# the sweep unless it is wrapped in I18n.t. So the UI sources are scanned for such
	# leaks — a class a tree walk can never catch.
	var ds_leaks := _scan_draw_string_leaks("res://scripts")
	for l in ds_leaks: print("DRAW-CYR: " + l)
	_check(ds_leaks.is_empty(), "draw_string without I18n.t leaves no Cyrillic behind")
	print("PROBES %d" % _fails)
	if _fails == 0: print("ALL PASS")
	get_tree().quit(1 if _fails > 0 else 0)
