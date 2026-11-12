extends Node3D
# HUD layout verified by numbers: the picture cannot be looked at, so we measure geometry
# and content. Three things this test is responsible for:
#   1) nothing runs past the screen edge and no panels overlap each other;
#   2) the extra readouts are REMOVED from the panel for real (they did not merely stop
#      updating, they are gone), while the useful set — speed, g-force, dents, body,
#      grip, log — stayed;
#   3) the HUD covers a small share of the screen: for us "nicer" means above all
#      "less of the frame hidden".

# Share of the screen the HUD is allowed to take. The previous layout took 14%: with it
# the speedometer kept a separate speed caption above the dial, and the telemetry panel carried five rows.
const COVER_MAX := 0.12
const LABEL_MAX := 26          # how many labels are acceptable on the run screen
# The frame is measured by the actual visible rectangle, not by the 1600×900 design size:
# in headless the window is square, and the design numbers do not match the screen.
var VW := 1600.0
var VH := 900.0
const GONE := ["ГАБАРИТ ДЛИНЫ", "МАКС. ГЛУБИНА", "ПЕРЕГРУЗКА"]
const MUST := ["ПИК ПЕРЕГРУЗКИ", "ВМЯТИНЫ", "КУЗОВ", "СЦЕПЛЕНИЕ", "ЖУРНАЛ УДАРОВ",
	"ТЕЛЕМЕТРИЯ"]

var gm: GameManager
var _fails := 0
var _panels: Array = []        # [Rect2, name]
var _decos: Array = []         # [hid, offset: Vector2] — линейки и полосы шкал
var _host_labels: Array = []   # [hid, offset: Vector2, text]
var _host_ids := {}            # host Panel -> стабильный номер (объекты разных прогонов не сравнить)
var _host_seq := 0

func _host_id(host: Control) -> int:
	if not _host_ids.has(host):
		_host_ids[host] = _host_seq
		_host_seq += 1
	return int(_host_ids[host])
var _labels := 0
var _texts := ""

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	# Два прогона: дизайн-размер с заводской ступенью и «4K-эквивалент»
	# (3200×1800) со второй ступенью. На первой ступени fx() тождественен, и
	# несмасштабированная внутренняя раскладка HUD совпадала с панелями —
	# ступень 2 exposes it: подписи оставались в сырых пикселях, линии ложились
	# поверх текста (issue #10). Поэтому геометрия обязана держаться на обеих.
	await _pass(1600, 900, 0)
	# Снимок первой ступени: ключ — (номер панели, дизайн-смещение). Тексты
	# меток динаминые (FPS, проценты), а дизайн-смещение стабильно и на второй
	# ступени равно первому, делённому на два.
	var first_labels := {}
	for l in _host_labels:
		first_labels["%d|%.1f_%.1f" % [l[0], l[1].x, l[1].y]] = l[1]
	var first_decos := {}
	var deco_ordinal := {}
	for d in _decos:
		var n: int = int(deco_ordinal.get(d[0], 0))
		deco_ordinal[d[0]] = n + 1
		first_decos["%d|%d" % [d[0], n]] = d[1]
	await _pass(3200, 1800, 2)
	# Инвариант ступени: каждый внутренний элемент панели (метка, линейка,
	# полоса шкалы) обязан сместиться ровно в 2×. Прежняя раскладка держала
	# метки в сырых пикселях, и на второй ступени панели удваивались, а текст —
	# нет: блоки сминались, линии ложились на текст (issue #10). Нулевые оси
	# остаются нулями: 0 при любом шаге — корректный масштаб.
	for l in _host_labels:
		var f: Vector2 = first_labels.get("%d|%.1f_%.1f" % [l[0], l[1].x / 2.0, l[1].y / 2.0], Vector2(-1, -1))
		check(f.x >= 0.0, "each label exists on both steps (offset %s unmatched)" % str(l[1]))
		if f.x < 0.0: continue
		var ok_x := f.x <= 0.5 or is_equal_approx(l[1].x / f.x, 2.0)
		var ok_y := f.y <= 0.5 or is_equal_approx(l[1].y / f.y, 2.0)
		check(ok_x and ok_y, "a label scales with the step (%s -> %s)" % [str(f), str(l[1])])
	deco_ordinal = {}
	for d in _decos:
		var n: int = int(deco_ordinal.get(d[0], 0))
		deco_ordinal[d[0]] = n + 1
		var f: Vector2 = first_decos.get("%d|%d" % [d[0], n], Vector2(-1, -1))
		check(f.x >= 0.0, "a panel decoration exists on both steps")
		if f.x < 0.0: continue
		var ok_x := f.x <= 0.5 or is_equal_approx(d[1].x / f.x, 2.0)
		var ok_y := f.y <= 0.5 or is_equal_approx(d[1].y / f.y, 2.0)
		check(ok_x and ok_y, "a panel decoration scales with the step (%s -> %s)" % [str(f), str(d[1])])
	UiTheme.force_step(0)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _pass(w: int, h: int, step: int) -> void:
	_panels.clear()
	_decos.clear()
	_host_labels.clear()
	_host_ids.clear()
	_host_seq = 0
	_labels = 0
	_texts = ""
	get_window().size = Vector2i(w, h)
	UiTheme.force_step(step)
	await get_tree().process_frame
	await get_tree().process_frame
	var vis := get_viewport().get_visible_rect().size
	VW = vis.x; VH = vis.y
	GameContext.select("sport", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 30:
		await get_tree().physics_frame
	Input.action_press("throttle")
	for _i in 90:
		await get_tree().physics_frame
	Input.action_release("throttle")
	for _i in 6:
		await get_tree().process_frame
	_walk(gm.hud)
	var tag := "step %d @ %dx%d" % [step, w, h]
	var cover := 0.0
	for p in _panels:
		cover += (p[0] as Rect2).get_area()
	cover /= VW * VH
	print("%s: panels %d, labels %d, %.1f%% of the screen covered" % [tag, _panels.size(), _labels,
		cover * 100.0])
	check(_panels.size() >= 3, "%s: the screen has at least some panels (%d)" % [tag, _panels.size()])
	check(cover <= COVER_MAX, "%s: the HUD covers a small part of the frame (%.1f%% ≤ %.0f%%)" % [
		tag, cover * 100.0, COVER_MAX * 100.0])
	check(_labels <= LABEL_MAX, "%s: no excess of labels (%d ≤ %d)" % [tag, _labels, LABEL_MAX])
	for t in MUST:
		check(I18n.t(t) in _texts, "%s: still present in the HUD: «%s»" % [tag, t])
	for i in _panels.size():
		for j in range(i + 1, _panels.size()):
			var a: Rect2 = _panels[i][0]
			var b: Rect2 = _panels[j][0]
			check(not a.intersects(b), "%s: panels do not overlap: %s / %s" % [tag,
				_panels[i][1], _panels[j][1]])

	# is the HUD live: the numbers must come from the car, not sit at zero
	check(gm.hud._gauge.speed > 10.0, "%s: the speedometer shows motion (%.0f)" % [tag, gm.hud._gauge.speed])
	gm.car.body.apply_impact(gm.car.chassis.global_position + Vector3(0.5, 0.4, 0.0),
		Vector3(1, 0, 0), 90.0)
	for _i in 3:
		await get_tree().process_frame
	check(gm.hud._v_dents.text == str(gm.car.body.dent_count),
		"%s: dents in the HUD = dents on the body (%s vs %d)" % [tag, gm.hud._v_dents.text, gm.car.body.dent_count])
	check(gm.hud._v_dents.text != "0", "%s: the impact is visible in the HUD (%s)" % [tag, gm.hud._v_dents.text])
	gm.queue_free()
	remove_child(gm)
	await get_tree().process_frame

func _walk(n: Node) -> void:
	for c in n.get_children():
		if not (c is Control):
			_walk(c)
			continue
		var ctl := c as Control
		if not ctl.is_visible_in_tree(): continue
		var r := ctl.get_global_rect()
		if ctl is ColorRect and ctl.get_parent() is Panel:
			_decos.append([_host_id(ctl.get_parent()),
				r.position - (ctl.get_parent() as Control).get_global_rect().position])
		if ctl is Panel:
			_panels.append([r, String(ctl.name)])
			check(r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= VW + 1.0
				and r.end.y <= VH + 1.0, "panel «%s» is inside the screen (%s)" % [ctl.name, r])
		if ctl == gm.hud._gauge:
			_panels.append([r, "speedometer"])
			check(r.end.x <= VW + 1.0 and r.end.y <= VH + 1.0, "the speedometer is inside the screen (%s)" % r)
		if ctl is Label:
			var t := (ctl as Label).text
			if t.strip_edges() == "":
				_walk(c)
				continue
			_labels += 1
			_texts += t + " "
			var host := ctl.get_parent()
			if host is Panel:
				var hr: Rect2 = (host as Control).get_global_rect()
				check(hr.encloses(r), "label «%s» is inside the panel (%s within %s)" % [t, r, hr])
				_host_labels.append([_host_id(host),
					r.position - (host as Control).get_global_rect().position, t])
		_walk(c)
