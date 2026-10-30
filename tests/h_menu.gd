extends Control
# Меню: структура, реакция описаний на выбор, переход в игру по «В ПУТЬ».
var _fails := 0
var _f := 0
var mm: Control

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _design_size() -> Vector2:
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))

func _opts(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is OptionButton: out.append(c)
		_opts(c, out)

func _buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button and not (c is OptionButton): out.append(c)
		_buttons(c, out)

func _labels(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Label: out.append(c)
		_labels(c, out)

func _rich(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is RichTextLabel: out.append(c)
		_rich(c, out)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)

func _process(_d: float) -> void:
	_f += 1
	if _f != 8: return
	var vp := _design_size()
	check(mm.size == get_viewport().get_visible_rect().size,
		"menu fills viewport (%s vs %s)" % [str(mm.size), str(get_viewport().get_visible_rect().size)])
	var labels: Array = []; _labels(mm, labels)
	var title_found := false
	for l in labels:
		if l.text == "CAR CRASH SIMULATOR": title_found = true
		var r: Rect2 = l.get_global_rect()
		check(r.position.x >= -1 and r.position.y >= -1 and r.position.x + r.size.x <= vp.x + 1 and r.position.y + r.size.y <= vp.y + 1,
			"label %s inside viewport (%s)" % [l.text.substr(0, 18), str(r)])
	check(title_found, "title present")
	var opts: Array = []; _opts(mm, opts)
	check(opts.size() == 2, "two option buttons (%d)" % opts.size())
	for o in opts:
		check(o.item_count == 3, "option %s has 3 items (%d)" % [o.name, o.item_count])
		check(o.selected == 0, "option %s defaults to first" % o.name)
	var rich: Array = []; _rich(mm, rich)
	check(rich.size() == 2, "two description fields (%d)" % rich.size())
	var d0: String = rich[0].text
	opts[0].select(2)
	opts[0].emit_signal("item_selected", 2)
	check(rich[0].text != d0, "description follows selection")
	var btns: Array = []; _buttons(mm, btns)
	check(btns.size() == 1, "single start button (%d)" % btns.size())
	var br: Rect2 = btns[0].get_global_rect()
	check(br.position.x > 0 and br.position.y > 0 and br.position.x + br.size.x < vp.x and br.position.y + br.size.y < vp.y,
		"start button inside viewport (%s)" % str(br))
	# переход: сцена-харнес не должна быть current_scene, иначе её снесёт смена сцены
	get_tree().current_scene = null
	opts[0].select(1)
	opts[0].emit_signal("item_selected", 1)
	opts[1].select(2)
	opts[1].emit_signal("item_selected", 2)
	btns[0].emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameContext.car_id == "pickup" and GameContext.map_id == "speedway",
		"selection reaches GameContext (%s/%s)" % [GameContext.car_id, GameContext.map_id])
	var gm: Node = get_tree().current_scene
	check(gm is GameManager, "start opens the game scene (%s)" % str(gm))
	check(gm is GameManager and gm.car != null and gm.hud != null and gm.camera != null, "game scene wired")
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
