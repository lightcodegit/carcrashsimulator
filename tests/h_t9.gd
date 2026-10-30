extends Node3D
var _fails := 0
var _frame := 0
var car: CarRig
var cam: CameraRig

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200); cs.shape = box
	body.add_child(cs); add_child(body); body.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	cam = CameraRig.new(); add_child(cam); cam.setup(car)
	cam.make_current()

func _physics_process(_dt: float) -> void:
	_frame += 1
	if _frame == 30:
		var d := cam.global_position.distance_to(car.chassis.global_position)
		check(d > 2.0 and d < 15.0, "chase distance %.1f" % d)
		check(cam.global_position.y > 0.3, "chase above ground")
	if _frame == 40: cam.cycle_mode()
	if _frame == 70:
		check(cam.mode() == 1, "hood mode")
		check(cam.global_position.distance_to(car.chassis.global_position) < 3.0, "hood close")
	if _frame == 80: cam.cycle_mode()
	if _frame == 90:
		check(cam.mode() == 2, "orbit mode")
		cam.cycle_mode()
		check(cam.mode() == 0, "wrap to chase")
	if _frame == 100:
		cam.add_trauma(1.0)
	if _frame == 110:
		check(cam.global_position.is_finite(), "finite after shake")
	if _frame == 120:
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
