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
