extends Node3D
# Колёса из ассета и непроходимость: ось колеса поперёк машины, колёса стоят на земле,
# передние поворачивают, рама и кузов не проходят сквозь тонкую стену.
var _fails := 0
var _frame := 0
var car: CarRig
var wall_x := 6.0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(60, 2, 60); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	# тонкая стена: грань x = 6.0
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.2, 4, 8); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(6.1, 2, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-14.0, 1.0, 0)))

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 6:
		var b := car.body
		check(b.wheels.size() == 4, "четыре колеса (%d)" % b.wheels.size())
		check(b.front_wheels.size() == 2, "два передних (%d)" % b.front_wheels.size())
		for w in b.wheels:
			# колесо ассета — ArrayMesh: проверяем по мировому AABB.
			# Машина смотрит в +X, значит ось колеса — мировая Z (тонкая), а диаметр — по X и Y.
			var wa: AABB = w.global_transform * w.get_aabb()
			check(wa.size.z < wa.size.y * 0.75, "ось колеса поперёк машины (шина %.2f тоньше диаметра %.2f)" % [wa.size.z, wa.size.y])
			check(absf(wa.size.y * 0.5 - b.wheel_radius) < 0.03, "радиус колеса совпадает с params (%.3f vs %.3f)" % [wa.size.y * 0.5, b.wheel_radius])
			check(absf(wa.size.x * 0.5 - b.wheel_radius) < 0.03, "колесо круглое в продольной плоскости (%.3f)" % (wa.size.x * 0.5))
		Input.action_press("steer_left")
	if _frame == 30:
		# подвеска VehicleBody3D оседает несколько тиков, поэтому высоту меряем не сразу
		for w in car.body.wheels:
			var wa: AABB = w.global_transform * w.get_aabb()
			check(absf(wa.position.y) < 0.03, "колесо касается пола (низ на %.3f)" % wa.position.y)
		var f0 := car.body.front_wheels[0].rotation.y
		var back := car.body.wheels[0]
		for w in car.body.wheels:
			if not car.body.front_wheels.has(w): back = w
		check(absf(f0) > 0.05, "переднее колесо повернулось (%.3f рад)" % f0)
		check(absf(back.rotation.y) < 0.01, "заднее колесо не поворачивается (%.3f)" % back.rotation.y)
		Input.action_release("steer_left")
		Input.action_press("throttle")
	if _frame == 240:
		Input.action_release("throttle")
		check(car.chassis.global_position.x < wall_x, "рама не прошла сквозь стену (%.2f)" % car.chassis.global_position.x)
		check(car.speed_kmh() < 12.0, "машина остановилась о стену (%.1f км/ч)" % car.speed_kmh())
		check(car.body.dent_count > 0, "удар о стену помял кузов (%d)" % car.body.dent_count)
		var below := 0; var thru := 0; var bad := 0
		for i in car.body.vertex_count():
			var w := car.body.vertex_world(i)
			if not w.is_finite(): bad += 1
			if w.y < -0.05: below += 1
			if w.x > wall_x + 0.15: thru += 1
		check(bad == 0, "все вершины конечны (%d)" % bad)
		check(below == 0, "кузов не ушёл под пол (%d)" % below)
		check(thru == 0, "кузов не прошёл сквозь стену (%d)" % thru)
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
