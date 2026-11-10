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
var _labels := 0
var _texts := ""

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
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
	print("panels %d, labels %d, %.1f%% of the screen covered" % [_panels.size(), _labels,
		cover * 100.0])
	check(_panels.size() >= 3, "the screen has at least some panels (%d)" % _panels.size())
	check(cover <= COVER_MAX, "the HUD covers a small part of the frame (%.1f%% ≤ %.0f%%)" % [
		cover * 100.0, COVER_MAX * 100.0])
	check(_labels <= LABEL_MAX, "no excess of labels (%d ≤ %d)" % [_labels, LABEL_MAX])
	for t in GONE:
		check(not I18n.t(t) in _texts, "removed from the HUD: «%s»" % t)
	for t in MUST:
		check(I18n.t(t) in _texts, "still present in the HUD: «%s»" % t)
	for i in _panels.size():
		for j in range(i + 1, _panels.size()):
			var a: Rect2 = _panels[i][0]
			var b: Rect2 = _panels[j][0]
			check(not a.intersects(b), "panels do not overlap: %s / %s" % [_panels[i][1],
				_panels[j][1]])
	# is the HUD live: the numbers must come from the car, not sit at zero
	check(gm.hud._gauge.speed > 10.0, "the speedometer shows motion (%.0f)" % gm.hud._gauge.speed)
	# Live HUD: a readout must come from the car. `text != ""` is always true,
	# because hud.gd writes the format every frame. So we check the link: dent the
	# body — and the HUD number must become the same one as on the body.
	gm.car.body.apply_impact(gm.car.chassis.global_position + Vector3(0.5, 0.4, 0.0),
		Vector3(1, 0, 0), 90.0)
	for _i in 3:
		await get_tree().process_frame
	check(gm.hud._v_dents.text == str(gm.car.body.dent_count),
		"dents in the HUD = dents on the body (%s vs %d)" % [gm.hud._v_dents.text, gm.car.body.dent_count])
	check(gm.hud._v_dents.text != "0", "the impact is visible in the HUD (%s)" % gm.hud._v_dents.text)
	check(gm.hud._v_peak.text == "%.2f g" % gm.hud._peak_g,
		"the g-force is captioned with a live value (%s)" % gm.hud._v_peak.text)
	check(gm.hud._v_deform.text.ends_with("%"), "the body scale is in percent (%s)" % gm.hud._v_deform.text)
	check(gm.hud._v_grip.text.ends_with("%"), "the grip scale is in percent (%s)" % gm.hud._v_grip.text)
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
		_walk(c)
