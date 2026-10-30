extends Node3D
var _fails := 0
var _frame := 0
var car: CarRig
var _impacts: Array[float] = []

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	ObstacleField.reset()
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200); cs.shape = box
	body.add_child(cs); add_child(body); body.global_position = Vector3(0, -0.5, 0)
	ObstacleField.add(Vector3(0, -0.5, 0), Vector3(100, 0.5, 100))
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 30); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(60, 4, 0)
	ObstacleField.add(Vector3(60, 4, 0), Vector3(0.5, 4, 15))
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	car.impact.connect(func(s: float, _p: Vector3, _n: Vector3) -> void: _impacts.append(s))

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 5: Input.action_press("throttle")
	if _frame == 750:
		Input.action_release("throttle")
		check(_impacts.size() > 0, "crashed registered (%s)" % str(_impacts))
		check(_impacts.size() > 0 and _impacts[0] > 40.0 and _impacts[0] < 130.0, "impact speed plausible (%s)" % str(_impacts))
		check(car.chassis.linear_velocity.length() * 3.6 < 8.0, "car stopped (%.1f)" % (car.chassis.linear_velocity.length() * 3.6))
		check(car.shell.broken_by_zone[Zones.FRONT] >= 12, "front damage >=12 (%d)" % car.shell.broken_by_zone[Zones.FRONT])
		check(car.shell.get_broken_total() < car.shell.spec.springs.size() * 0.5, "damage is local, not total")
		var thru := 0
		var shown := 0
		for i in car.shell.point_count():
			if car.shell.point_world(i).x > 60.6:
				thru += 1
				if shown < 5: print("VPT "+str(i)+" "+str(car.shell.point_world(i))+" dyn="+str(car.shell._dyn[i] if i < car.shell._dyn.size() else "?")); shown += 1
		check(thru == 0, "no shell points inside wall (%d)" % thru)
		var avg := car.shell.get_sim_ms_avg()
		check(avg < 8.0, "shell sim budget (%.2f ms)" % avg)
	if _frame == 1250:
		car.shell.debug_dyn()
		check(car.shell.dyn_count() == 0, "damaged cage settles to sleep (%d)" % car.shell.dyn_count())
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
