extends SceneTree
# Бюджет Большого Города после обвески. FPS на встроенной графике шумит сильнее,
# чем эффект от деталей (разброс 24–58 на одном и том же коде), поэтому проверяем
# детерминированное: число узлов, время сборки, число отбрасывающих тень и количество
# сбиваемых предметов. Живой FPS меряет h_picture-подобный прогон вручную.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _walk(n: Node, st: Dictionary) -> void:
	if n is MeshInstance3D:
		st["meshes"] += 1
		if (n as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			st["casters"] += 1
	if n is RigidBody3D:
		st["loose"] += 1
	st["nodes"] += 1
	for c in n.get_children():
		_walk(c, st)

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var built: Dictionary = MapDB.build("bigcity")
	var ms := Time.get_ticks_msec() - t0
	var st := {"nodes": 0, "meshes": 0, "casters": 0, "loose": 0}
	_walk(built["root"], st)
	print("bigcity: %d мс, узлов %d, мешей %d, теней %d, сбиваемых %d" % [
		ms, st["nodes"], st["meshes"], st["casters"], st["loose"]])
	check(ms <= 1400, "сборка уложилась в бюджет (%d мс)" % ms)
	check(st["nodes"] >= 4000, "город стал плотным, узлов %d" % st["nodes"])
	check(st["nodes"] <= 9600, "узлов не больше бюджета (%d)" % st["nodes"])
	check(st["casters"] <= 1400, "отбрасывают тень не больше бюджета (%d)" % st["casters"])
	check(st["loose"] >= 700, "сбиваемой мелочи хватает (%d)" % st["loose"])
	check(st["loose"] <= 1100,
		"тел не больше бюджета физики (%d) — шаг физики растёт вместе с ними" % st["loose"])
	quit(0 if _fails == 0 else 1)
