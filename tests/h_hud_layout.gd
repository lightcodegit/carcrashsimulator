extends Node3D
# Проверка раскладки HUD числами: картинку смотреть нельзя, поэтому меряем геометрию и
# состав. Три вещи, за которые отвечает тест:
#   1) ничего не залезает за край экрана и панели не наезжают друг на друга;
#   2) лишние показания из панели убраны НАСТОЯЩО (не перестали обновляться, а исчезли),
#      а useful-набор — скорость, перегрузка, вмятины, кузов, сцепление, журнал — остался;
#   3) HUD занимает малую долю экрана: «красивее» для нас означает прежде всего «меньше
#      закрытого кадра».

# Доля экрана, которую вправе занять HUD. Прежняя раскладка брала 14%: к ней спидометр
# держал отдельную подпись скорости поверх круга, а панель телеметрии несла пять строк.
const COVER_MAX := 0.12
const LABEL_MAX := 26          # сколько надписей допустимо на экране заезда
# Адаптивный HUD (stretch canvas_items + aspect expand) прижимается к фактическим
# углам окна, поэтому рамка меряется по видимому прямоугольнику, а не по
# дизайн-1600×900: в headless он бывает квадратным.
var VW := 1600.0
var VH := 900.0
const GONE := ["ГАБАРИТ ДЛИНЫ", "МАКС. ГЛУБИНА", "ПЕРЕГРУЗКА"]
const MUST := ["ПИК ПЕРЕГРУЗКИ", "ВМЯТИНЫ", "КУЗОВ", "СЦЕПЛЕНИЕ", "ЖУРНАЛ УДАРОВ",
	"ТЕЛЕМЕТРИЯ"]

var gm: GameManager
var _fails := 0
var _panels: Array = []        # [Rect2, имя]
var _labels := 0
var _texts := ""

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
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
	var cover := 0.0
	for p in _panels:
		cover += (p[0] as Rect2).get_area()
	cover /= VW * VH
	print("панелей %d, надписей %d, закрыто %.1f%% экрана" % [_panels.size(), _labels,
		cover * 100.0])
	check(_panels.size() >= 3, "панелей на экранe хоть сколько-нибудь (%d)" % _panels.size())
	check(cover <= COVER_MAX, "HUD закрыта малая часть кадра (%.1f%% ≤ %.0f%%)" % [
		cover * 100.0, COVER_MAX * 100.0])
	check(_labels <= LABEL_MAX, "надписей не перебор (%d ≤ %d)" % [_labels, LABEL_MAX])
	for t in GONE:
		check(not t in _texts, "из HUD убрано «%s»" % t)
	for t in MUST:
		check(t in _texts, "в HUD осталось «%s»" % t)
	for i in _panels.size():
		for j in range(i + 1, _panels.size()):
			var a: Rect2 = _panels[i][0]
			var b: Rect2 = _panels[j][0]
			check(not a.intersects(b), "панели не наезжают: %s / %s" % [_panels[i][1],
				_panels[j][1]])
	# живой ли HUD: цифры обязаны приходить из машины, а не стоять нулями
	check(gm.hud._gauge.speed > 10.0, "спидометр показывает ход (%.0f)" % gm.hud._gauge.speed)
	check(gm.hud._v_peak.text != "", "перегрузка подписана (%s)" % gm.hud._v_peak.text)
	check(gm.hud._v_dents.text != "", "вмятины подписаны (%s)" % gm.hud._v_dents.text)
	check(gm.hud._v_deform.text.ends_with("%"), "шкала кузова в процентах (%s)" % gm.hud._v_deform.text)
	check(gm.hud._v_grip.text.ends_with("%"), "шкала сцепления в процентах (%s)" % gm.hud._v_grip.text)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _walk(n: Node) -> void:
	for c in n.get_children():
		if not (c is Control):
			_walk(c)
			continue
		var ctl := c as Control
		if not ctl.is_visible_in_tree(): continue
		var r := ctl.get_global_rect()
		if ctl is Panel:
			_panels.append([r, String(ctl.name)])
			check(r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= VW + 1.0
				and r.end.y <= VH + 1.0, "панель «%s» внутри экрана (%s)" % [ctl.name, r])
		if ctl == gm.hud._gauge:
			_panels.append([r, "спидометр"])
			check(r.end.x <= VW + 1.0 and r.end.y <= VH + 1.0, "спидометр внутри экрана (%s)" % r)
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
				check(hr.encloses(r), "надпись «%s» внутри панели (%s в %s)" % [t, r, hr])
		_walk(c)
