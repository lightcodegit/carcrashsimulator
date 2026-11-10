extends Node3D
# h_wrap: regression tests for three fixed systems — the endless belt recycle,
# key loading robustness to foreign keys in the config, and id validation.
var _fails := 0
func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)

func _physics_process(_dt: float) -> void:
	_wrap()
	_keys()
	_context()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---- the «infinity» belt: no overlap, colliders follow their plates, barriers
# move, teleporting back puts the road under the car
func _wrap() -> void:
	var m: Dictionary = MapDB.build("endless")
	var root: Node3D = m.root
	add_child(root)
	var plates: Array[Node3D] = []
	var solids: Array[Node3D] = []
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		if String(mi.name).begins_with("kit_road"):
			plates.append(mi)
			if String(mi.name).contains("roadBump") or String(mi.name).contains("roadRampLong"):
				solids.append(mi)
	var bar0 := INF
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_barrierWall"):
			bar0 = minf(bar0, mi.position.x)
	var car_x := -20.0
	while car_x < 6000.0:
		car_x += 50.0
		MapDB.recycle(root, car_x, 20.0)
	var seen := {}
	var dupes := 0
	for mi in plates:
		var k := "%.0f|%.0f" % [mi.position.x, mi.position.z]
		if seen.has(k): dupes += 1
		seen[k] = true
	# an empty list would give «0 overlaps» and «0 orphans» — a green test without checking anything
	check(plates.size() > 0, "%d plates collected for comparison" % plates.size())
	check(solids.size() > 0, "%d solid plates collected" % solids.size())
	check(dupes == 0, "after three-plus belt cycles no plates overlap (dupes=%d)" % dupes)
	var orphan := 0
	for mi in solids:
		var body := root.get_node_or_null(NodePath("col_" + mi.name))
		if body == null or absf(body.position.x - mi.position.x) > 0.01: orphan += 1
	check(orphan == 0, "every solid plate has its collider next to it (orphans=%d of %d)" % [orphan, solids.size()])
	var bar1 := INF
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi != null and String(mi.name).begins_with("kit_barrierWall"):
			bar1 = minf(bar1, mi.position.x)
	check(bar1 > bar0, "barriers move along with the belt (min x %.0f -> %.0f)" % [bar0, bar1])
	# teleport back: the road must return under the start point. In a live run
	# recycle is called every physics frame, here the same five calls in a row
	for _i in 5: MapDB.recycle(root, -20.0, 20.0)
	var covered := false
	for mi in plates:
		if mi.position.x <= -20.0 and mi.position.x + MapCircuit._advance_of(mi) >= -20.0:
			covered = true
	check(covered, "after the car returns to the start the road lies under the spawn (x=-20)")
	root.queue_free()

# ---- [keys] with a foreign key: loading is not aborted, valid bindings get through
func _keys() -> void:
	var cf := ConfigFile.new()
	cf.set_value("keys", "throttle", "k84")
	cf.set_value("keys", "ghost_from_future", "k57")
	cf.set_value("keys", "respawn", "k82")
	InputRouter.load_keys(cf)
	var got := false
	for e in InputMap.action_get_events("throttle"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_T: got = true
	check(got, "the throttle-to-T rebind loaded despite the foreign key in the file")
	var back := false
	for e in InputMap.action_get_events("respawn"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_R: back = true
	check(back, "bindings after the foreign key are not lost (respawn=R)")
	InputRouter.reset_keys()

# ---- GameContext: a garbage id never reaches run assembly
func _context() -> void:
	GameContext.select("bogus_car", "bogus_map")
	check(GameContext.car_id != "bogus_car" and GameContext.map_id != "bogus_map",
		"garbage ids rejected (%s / %s)" % [GameContext.car_id, GameContext.map_id])
	var p := VehicleDB.get_params(GameContext.car_id)
	check(p != null, "after rejection a car can still be built (params != null)")
