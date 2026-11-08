extends Control
# Отладочный оверлей: четыре секции на F3, включается F2 (или настройкой).
# Обновляется 4 раза в секунду, а не каждый кадр: текст на экране — это тоже
# отрисовка, и измерение на каждом кадре меняло бы ровно то, что показывает.
const SECTION_NAMES := ["КАДР", "МАШИНА", "МИР", "ЖУРНАЛ"]
const REFRESH_MS := 250
const LOG_MAX := 8
const PROBE_LEN := 60.0

var gm: GameManager
var hud: HUD
var _section := 0
var _next_ms := 0
var _label: Label
var _log: Array[String] = []
var _last_crashes := 0
var _last_dents := 0
var _frame_ms := 0.0
var _phys_ms := 0.0
var _prev_frame_us := 0
var _prev_phys_us := 0

func setup(g: GameManager, h: HUD) -> void:
	gm = g
	hud = h

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(24, 196)
	custom_minimum_size = Vector2(UiTheme.fx(372), UiTheme.fx(236))
	size = Vector2(372, 236)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = UiTheme.label("", 14, Color(0.86, 0.9, 0.95), 500, true)
	_label.position = Vector2(UiTheme.fx(12), UiTheme.fx(10))
	_label.size = Vector2(UiTheme.fx(348), UiTheme.fx(216))
	_label.clip_text = true
	add_child(_label)
	_redraw()
	_next_ms = Time.get_ticks_msec() + REFRESH_MS

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("debug_section"):
		_section = (_section + 1) % SECTION_NAMES.size()
		_redraw()
		_next_ms = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()

# Интервалы, а не стоимость: измерить именно стоимость шага из узла нельзя, а
# Performance.TIME_PHYSICS_PROCESS под --fixed-fps врёт (показывал 52 мс там, где
# стена давала 0,5). Поэтому рядом и то, и другое — игрок видит расхождение.
func _physics_process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev_phys_us > 0:
		_phys_ms = lerpf(_phys_ms, float(now - _prev_phys_us) / 1000.0, 0.25)
	_prev_phys_us = now

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev_frame_us > 0:
		_frame_ms = lerpf(_frame_ms, float(now - _prev_frame_us) / 1000.0, 0.25)
	_prev_frame_us = now
	if Time.get_ticks_msec() < _next_ms: return
	_next_ms = Time.get_ticks_msec() + REFRESH_MS
	_track_events()
	_redraw()

# Удары и рестарты — по переходам счётчиков: заводить шину событий ради четырёх
# строк в углу значит добавить интерфейс, который никто больше не использует.
func _track_events() -> void:
	if gm == null or not is_instance_valid(gm) or gm.car == null: return
	var s := gm.debug_scene()
	var crashes := int(s.crashes)
	if crashes > _last_crashes:
		_note(I18n.t("удар #%d, топ %d км/ч") % [crashes, int(s.top_crash)])
	_last_crashes = crashes
	var dents := gm.car.body.dent_count if gm.car.body != null else 0
	if dents < _last_dents:
		_note(I18n.t("рестарт: вмятин %d → %d") % [_last_dents, dents])
	_last_dents = dents

func _note(text: String) -> void:
	var t := int(Time.get_ticks_msec() / 1000)
	_log.push_front("%02d:%02d  %s" % [t / 60, t % 60, text])
	if _log.size() > LOG_MAX: _log.resize(LOG_MAX)

func _redraw() -> void:
	if _label == null: return
	match _section:
		1: _label.text = _text_car()
		2: _label.text = _text_world()
		3: _label.text = _text_log()
		_: _label.text = _text_frame()

func _text_frame() -> String:
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	return "DEBUG · %s\n" % I18n.t(String(SECTION_NAMES[_section])) + \
		I18n.t("кадр (интервал)  %.1f мс\n") % _frame_ms + \
		I18n.t("физика (шаг)     %.1f мс\n") % _phys_ms + \
		"fps              %.1f\n" % fps + \
		I18n.t("движок           %s\n") % RenderingServer.get_current_rendering_method() + \
		I18n.t("объектов в кадре %d\n") % int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)) + \
		I18n.t("вызовов отрисовки %d\n") % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + \
		I18n.t("примитивов        %d\n") % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) + \
		I18n.t("видеопамять       %d МБ\n") % int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) + \
		I18n.t("узлов %d · сирот %d\n") % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))]

func _text_car() -> String:
	if gm == null or gm.car == null: return I18n.t("DEBUG · МАШИНА\nнет машины")
	var s := gm.car.debug_snapshot()
	var g: Dictionary = hud.debug_g() if hud != null else {"live": 0.0, "peak": 0.0}
	var contacts := ""
	for y in s.contacts:
		contacts += "·" if float(y) > 0.0 else " "
	return I18n.t("DEBUG · МАШИНА\n") + \
		I18n.t("скорость     %.0f км/ч\n") % float(s.speed_kmh) + \
		I18n.t("руль         %.1f° из %.0f°\n") % [float(s.steer_deg), float(s.steer_max_deg)] + \
		I18n.t("занос        %.2f\n") % float(s.slip) + \
		I18n.t("боковое g    %.2f (пик %.2f)\n") % [float(g.live), float(g.peak)] + \
		I18n.t("педали       тормоз %.2f · ручник %.2f\n") % [float(s.pedal), float(s.hand)] + \
		I18n.t("колёса       %s (%s)\n") % [contacts, I18n.t("на земле") if s.grounded else I18n.t("в воздухе")] + \
		I18n.t("курс         %.0f°\n") % float(s.heading_deg)

func _text_world() -> String:
	if gm == null: return I18n.t("DEBUG · МИР\nнет сцены")
	var s := gm.debug_scene()
	var cam := gm.camera.global_position if gm.camera != null else Vector3.ZERO
	var c := MapDB.debug_counts(s.map_root, cam)
	var b: AABB = s.bounds
	var near := float(c.nearest)
	var probe := _probe(cam)
	return I18n.t("DEBUG · МИР\n") + \
		I18n.t("карта        %s%s\n") % [String(s.map_id), I18n.t(" (лента)") if s.endless else ""] + \
		I18n.t("узлов %d · тел %d · стат. %d\n") % [int(c.nodes), int(c.bodies), int(c.statics)] + \
		I18n.t("мешей %d · за LOD %d\n") % [int(c.meshes), int(c.hidden)] + \
		I18n.t("ближ. тело   %s\n") % ((I18n.t("%.1f м") % near) if is_finite(near) else I18n.t("нет")) + \
		I18n.t("луч: %s\n") % probe + \
		I18n.t("границы      x %.0f..%.0f z %.0f..%.0f\n") % [b.position.x, b.end.x, b.position.z, b.end.z] + \
		I18n.t("спавн        %.0f, %.0f, %.0f\n") % [s.spawn.x, s.spawn.y, s.spawn.z] + \
		I18n.t("пар физики   %d\n") % int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))

func _text_log() -> String:
	var out := I18n.t("DEBUG · ЖУРНАЛ\n")
	if _log.is_empty(): return out + I18n.t("событий пока нет\n")
	for l in _log:
		out += l + "\n"
	return out

# Движок этой сборки не отдаёт скрипту отрисовку коллайдеров (ни World3D.debug_draw,
# ни PhysicsServer3DDrawing), а вопрос «во что я врезался, если этого не видно»
# остаётся. Отвечаем на него прямым запросом к физическому пространству.
func _probe(from: Vector3) -> String:
	if gm == null: return I18n.t("нет сцены")
	var space := gm.get_world_3d().direct_space_state
	if space == null: return I18n.t("нет пространства")
	var dir := -gm.camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * PROBE_LEN)
	q.collide_with_bodies = true
	q.hit_from_inside = false
	# Камера стоит за машиной, поэтому без исключения луч вечно показывал бы
	# «в 3 м — собственный кузов», а вопрос был про то, что впереди.
	if gm.car != null and gm.car.chassis != null:
		q.exclude = [gm.car.chassis.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty(): return I18n.t("чисто на %.0f м") % PROBE_LEN
	var where: Vector3 = hit.position
	# Автоимена вида «@StaticBody3D@7» игроку ничего не говорят, а вопрос именно про
	# «во что я врезался». Поэтому: форма и её размер (это и есть опознание — бордюр,
	# плита, стена) плюс ближайшее осмысленное имя наверх по дереву.
	var body := _body_of(hit.collider as Node)
	var desc := _shape_desc(hit.collider as Node, body)
	var label := _named(body) if body != null else I18n.t("без тела")
	return I18n.t("%s · %s в %.1f м") % [desc, label, where.distance_to(from)]

func _body_of(n: Node) -> Node:
	var p := n
	while p != null:
		if p is PhysicsBody3D: return p
		p = p.get_parent()
	return n

func _named(n: Node) -> String:
	var p := n
	while p != null:
		var s := String(p.name)
		if not s.begins_with("@"): return s
		p = p.get_parent()
	return String(n.name)

func _shape_desc(collider: Node, body: Node) -> String:
	var shape_node: CollisionShape3D = null
	if collider is CollisionShape3D:
		shape_node = collider as CollisionShape3D
	elif body != null:
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_node = c as CollisionShape3D
				break
	if shape_node == null or shape_node.shape == null: return I18n.t("форма?")
	var sh := shape_node.shape
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return "Box %.0f×%.0f×%.0f" % [s.x, s.y, s.z]
	return String(sh.get_class())
