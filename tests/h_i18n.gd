# Свип локализации: при language=en во всех разделах меню, гараже, HUD и паузе
# не должно быть ни одной кириллической надписи. Ловит ровно тот класс дефектов,
# когда строка склеивается или режется до bind() и перестаёт быть ключом каталога.
# Уже дважды ловил реальные утечки (описания карточек и сводка паузы).
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

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	Settings.language = "en"
	I18n.set_locale("en")
	# 1) главное меню: все разделы
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var nav: Array = mm._nav.duplicate()
	for i in nav.size() + 1:
		var found: Array = []
		_walk(mm, "menu#%d" % i, found)
		for f in found: print("CYR: " + f)
		_check(found.is_empty(), "раздел %d меню без кириллицы" % i)
		if i < nav.size():
			(nav[i] as Button).emit_signal("pressed")
			await get_tree().process_frame
			await get_tree().process_frame
	mm.queue_free()
	await get_tree().process_frame
	# 2) экран заезда: HUD, пауза
	GameContext.select("sedan", "arena")
	var gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for i in 5: await get_tree().physics_frame
	var found2: Array = []
	_walk(gm, "game", found2)
	for f in found2: print("CYR: " + f)
	_check(found2.is_empty(), "HUD без кириллицы")
	gm._set_paused(true)
	await get_tree().process_frame
	var found3: Array = []
	_walk(gm, "pause", found3)
	for f in found3: print("CYR: " + f)
	_check(found3.is_empty(), "пауза без кириллицы")
	print("PROBES %d" % _fails)
	if _fails == 0: print("ALL PASS")
	get_tree().quit(1 if _fails > 0 else 0)
