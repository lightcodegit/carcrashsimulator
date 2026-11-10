extends Node3D
# Car behaviour after the impact rework:
# A) running up a ramp and landing are NOT counted as an impact and do not kill speed
# B) a wall hit is registered and dents the body
# C) brushing the side along a wall while moving loses no speed and gives no impact
# D) a side impact into a wall stops the car and dents the side
# E) the handbrake brakes and breaks the car into a slide
var _fails := 0
var _frame := 0
var car: CarRig
var _impacts := 0
var _max_y := 0.0
var _ramp_impacts := -1
var _phase := "A"
var _phase_frame := 0
var _brush_speed := 0.0
var _hb_speed := 0.0
var _done := {}
var _hold := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func once(key: String, cond: bool, msg: String) -> void:
	if _done.has(key): return
	_done[key] = true
	check(cond, msg)

func _enter(phase: String, spawn: Transform3D) -> void:
	_phase = phase
	_phase_frame = 0
	_impacts = 0
	_hold = 0
	car.respawn(spawn)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(240, 2, 120); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(40, -1, 0)
	MapKit.wedge(self, Vector3(20, 0.0, 0), 14, 3.2, 10, Color(0.9, 0.8, 0.2))   # ramp x = 20..34
	var wall := StaticBody3D.new()                                             # wall ahead, x = 90
	var wcs := CollisionShape3D.new(); var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 8, 40); wcs.shape = wbox
	wall.add_child(wcs); add_child(wall); wall.global_position = Vector3(90, 4, 0)
	var side := StaticBody3D.new()                                             # long side wall along z = 6.3
	var scs := CollisionShape3D.new(); var sbox := BoxShape3D.new()
	sbox.size = Vector3(120, 4, 0.6); scs.shape = sbox
	side.add_child(scs); add_child(side); side.global_position = Vector3(40, 2, 6.3)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void: _impacts += 1)
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_frame += 1
	_phase_frame += 1
	var p := car.chassis.global_position
	_max_y = maxf(_max_y, p.y)
	match _phase:
		"A":
			if _ramp_impacts < 0 and p.x > 45.0:
				_ramp_impacts = _impacts
				once("A1", _ramp_impacts == 0, "A1 the ramp run-up and the jump give no impact (%d)" % _ramp_impacts)
				once("A2", _max_y > 1.5, "A2 the car climbed the ramp (max y=%.2f)" % _max_y)
				once("A3", car.body.dent_count == 0, "A3 the ramp dents no body (%d)" % car.body.dent_count)
			if p.x > 87.0 and car.speed_kmh() < 20.0: _hold += 1
			if _phase_frame > 1200 or _hold > 6:
				Input.action_release("throttle")
				once("B1", _impacts > 0, "B1 the wall impact is registered (%d)" % _impacts)
				once("B2", car.body.dent_count > 0, "B2 the wall dented the body (%d)" % car.body.dent_count)
				once("B3", p.x < 90.0, "B3 the frame did not enter the wall (%.2f)" % p.x)
				_enter("C", Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 4.9)))
				Input.action_press("throttle")
		"C":
			if _brush_speed == 0.0 and car.speed_kmh() > 70.0:
				_brush_speed = car.speed_kmh()
			if _brush_speed > 0.0 and p.x > 55.0:
				once("C1", absf(p.z - 4.9) < 1.2, "C1 the car runs along the wall (z=%.2f)" % p.z)
				once("C2", _impacts == 0, "C2 a glancing brush is not an impact (%d)" % _impacts)
				once("C3", car.speed_kmh() > _brush_speed * 0.85,
					"C3 the brush does not eat speed (%.1f of %.1f km/h)" % [car.speed_kmh(), _brush_speed])
				once("C4", car.body.dent_count == 0, "C4 the brush dents no body (%d)" % car.body.dent_count)
				Input.action_release("throttle")
				_enter("D", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 1.0, -6)))
				Input.action_press("throttle")
		"D":
			if _phase_frame > 200:
				once("D1", p.z < 6.3, "D1 the side clamp holds the frame (z=%.2f)" % p.z)
				once("D2", _impacts > 0, "D2 the side impact is registered (%d)" % _impacts)
				once("D3", car.body.dent_count > 0, "D3 the side is dented (%d)" % car.body.dent_count)
				once("D4", car.speed_kmh() < 25.0, "D4 the car came to a stop (%.1f km/h)" % car.speed_kmh())
				Input.action_release("throttle")
				_enter("E", Transform3D(Basis.IDENTITY, Vector3(-40, 1.0, -12)))
				Input.action_press("throttle")
		"E":
			if _hb_speed == 0.0 and car.speed_kmh() > 75.0:
				_hb_speed = car.speed_kmh()
				# the throttle is NOT released: this is exactly the case from the reports — W and Space together.
				# Godot only counts brake while engine_force == 0, so CarRig
				# must drop the drive torque itself when the handbrake is held.
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_phase_frame = 0
			elif _hb_speed > 0.0 and _phase_frame == 60:
				var vel := car.chassis.linear_velocity
				var fwd := Vector3(cos(car.heading), 0, -sin(car.heading))
				var lat := (vel - fwd * vel.dot(fwd)).length() * 3.6
				# The handbrake is a drifting brake, not an emergency one: only the rear
				# axle locks (through chassis.brake Godot locked all four wheels, and on a
				# gamepad that read as an instant stop). The force is measured in g: "losing
				# 8 km/h per second" also passed at 0.2 g, i.e. when "the handbrake barely brakes".
				var g := (_hb_speed - car.speed_kmh()) / 3.6 / 9.81
				print("E1 handbrake with the throttle held: %.1f -> %.1f km/h = %.2f g" % [_hb_speed, car.speed_kmh(), g])
				check(g > 0.5, "E1 the handbrake slows noticeably even under power (%.2f g)" % g)
				check(g < 1.1, "E1b the handbrake does not turn into a stop (%.2f g)" % g)
				check(lat > 3.0, "E2 the handbrake breaks the car into a slide (lateral %.1f km/h)" % lat)
				check(car.heading > deg_to_rad(8.0), "E3 the handbrake swings the nose (%.0f°)" % rad_to_deg(car.heading))
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)
	if _frame > 3000:
		check(false, "timeout: the phases never reached the checks (frame %d)" % _frame)
		print("TIMEOUT in phase %s at frame %d" % [_phase, _frame])
		print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
		get_tree().quit(0 if _fails == 0 else 1)
