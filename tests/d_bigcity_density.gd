extends SceneTree
# Big City budget after dressing. FPS on integrated graphics is noisier than the
# effect of the details (a 24–58 spread on the very same code), so we check the
# deterministic part: node count, build time, shadow-caster count and the number of
# knockdown props. Live FPS is measured manually by an h_picture-like run.
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
	print("bigcity: %d ms, nodes %d, meshes %d, shadow casters %d, knockdowns %d" % [
		ms, st["nodes"], st["meshes"], st["casters"], st["loose"]])
	check(ms <= 1400, "build fit the budget (%d ms)" % ms)
	check(st["nodes"] >= 4000, "city got dense, %d nodes" % st["nodes"])
	check(st["nodes"] <= 9600, "nodes within budget (%d)" % st["nodes"])
	check(st["casters"] <= 1400, "shadow casters within budget (%d)" % st["casters"])
	check(st["loose"] >= 700, "enough knockdown props (%d)" % st["loose"])
	check(st["loose"] <= 1100,
		"bodies within the physics budget (%d) — the physics step grows with them" % st["loose"])
	built["root"].free()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)
