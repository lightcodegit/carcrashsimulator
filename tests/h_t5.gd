extends Node3D
var _fails := 0
var _frame := 0
var shell: SoftShell
var chassis: Node3D
var floor_top_y := 0.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	# пол: верх y=0
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40); cs.shape = box
	body.add_child(cs); body.global_position = Vector3(0, -0.5, 0)
	add_child(body)
	# тонкая стена: грань x=6.0 (центр 6.1, толщина 0.2) — тест свип-рея на «дырявых» объектах
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.2, 4, 8); wcs.shape = wbox
	wall.add_child(wcs); wall.global_position = Vector3(6.1, 2, 0)
	add_child(wall)
	await get_tree().process_frame
	shell = SoftShell.new()
	var p: VehicleParams = VehicleDB.get_params("sedan")
	add_child(shell)
	chassis = Node3D.new()
	add_child(chassis)
	# шасси: нос (local x=2.35) в 5.95 — ровно перед стеной
	chassis.global_position = Vector3(3.6, 2.5, 0)
	shell.setup(ShellBuilder.build(p), chassis, p)
	shell.space_state = get_world_3d().direct_space_state
	# dir — outward normal стены (от стены к машине) = -X; точки полетят +X (внутрь стены)
	shell.apply_impact(Vector3(6.0, 3.17, 0), Vector3(-1, 0, 0), 30.0)
	# и вниз к полу: dir = +Y (нормаль пола), точки полетят -Y
	shell.apply_impact(chassis.global_position + Vector3(0, 0.13, 0), Vector3(0, 1, 0), 30.0)

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 240:
		var below_floor := 0; var behind_wall := 0
		for i in shell.point_count():
			var wp := shell.point_world(i)
			if not wp.is_finite(): check(false, "NaN at %d" % i); break
			if wp.y < floor_top_y - 0.02: below_floor += 1
			if wp.x > 6.25: behind_wall += 1
		check(below_floor == 0, "no point under floor (%d)" % below_floor)
		check(behind_wall == 0, "no point through wall (%d)" % behind_wall)
		check(shell.broken_by_zone[Zones.FRONT] > 0, "wall crash damaged front (%d)" % shell.broken_by_zone[Zones.FRONT])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
