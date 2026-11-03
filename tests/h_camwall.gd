extends Node3D
# Камера не должна проходить сквозь стены и смотреть сквозь них.
# A) орбита: желаемая позиция за бетонной стеной — камера остаётся со стороны машины
# B) погоня: то же самое, когда стена позади машины
# C) сбиваемый предмет (RigidBody3D, как конус) между машиной и камерой машину не прячет
# D) чистое направление — камера встаёт на полную дистанцию
const WALL_X := 3.5          # ближняя грань стены
var _fails := 0
var _phase := ""
var _f := 0
var car: CarRig
var cam: CameraRig

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _body(pos: Vector3, size: Vector3, dynamic := false) -> CollisionObject3D:
	var b: CollisionObject3D = RigidBody3D.new() if dynamic else StaticBody3D.new()
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh
	b.add_child(cs); add_child(b); b.global_position = pos
	return b

func _orbit(yaw: float, dist: float) -> void:
	while cam.mode() != 2:
		cam.cycle_mode()
	cam._orbit_pitch = 0.0
	cam._orbit_yaw = yaw
	cam._orbit_dist = dist

func _chase(heading: float) -> void:
	car.respawn(Transform3D(Basis(Vector3.UP, heading), Vector3(0, 1.0, 0)))
	while cam.mode() != 0:
		cam.cycle_mode()
	cam._fwd_seen = false

func _ready() -> void:
	_body(Vector3(600, -1, 0), Vector3(2400, 2, 900))     # пол: верх при y = 0
	_body(Vector3(4, 3, 0), Vector3(1, 6, 40))            # стена: ближняя грань x = 3.5
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	cam = CameraRig.new(); add_child(cam)
	cam.setup(car)
	_orbit(0.0, 9.0)
	_phase = "A"; _f = 0

func _physics_process(_dt: float) -> void:
	_f += 1
	match _phase:
		"A":
			if _f == 10:
				var p := cam.global_position
				check(p.x < WALL_X - 0.05, "A: орбита не прошла сквозь стену (x=%.2f)" % p.x)
				check(p.x > 0.5, "A: орбита не прилипла к машине (x=%.2f)" % p.x)
				#respawn добавляет YAW_OFFSET, поэтому -π даёт нос вдоль -X, а камера
				# погони хочет встать в +X — то есть за стеной
				_chase(-PI)
				_phase = "B"; _f = 0
		"B":
			if _f == 14:
				var behind := -car.forward()
				var along: float = (cam.global_position - car.chassis.global_position).dot(behind)
				check(along < WALL_X - 0.05, "B: погоня не прошла сквозь стену (%.2f м за машиной)" % along)
				check(along > 0.5, "B: погоня не прилипла к машине (%.2f м)" % along)
				_body(Vector3(-2, 0.5, 0), Vector3(0.4, 0.8, 0.4), true)   # «конус»
				_orbit(PI, 9.0)
				_phase = "C"; _f = 0
		"C":
			if _f == 10:
				var d := cam.global_position.distance_to(car.chassis.global_position)
				check(absf(d - 9.0) < 0.05, "C: конус не спрятал машину (дистанция %.2f)" % d)
				_orbit(PI * 0.5, 6.0)
				_phase = "D"; _f = 0
		"D":
			if _f == 10:
				var d := cam.global_position.distance_to(car.chassis.global_position)
				check(absf(d - 6.0) < 0.05, "D: без заслона дистанция полная (%.2f)" % d)
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)
	if _f > 120:
		check(false, "таймаут: фазы не дошли до проверок (кадр %d)" % _f)
		print("TIMEOUT в фазе %s" % _phase)
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
