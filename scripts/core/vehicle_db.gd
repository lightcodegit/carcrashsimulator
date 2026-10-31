class_name VehicleDB
extends RefCounted

static func get_params(id: String) -> VehicleParams:
	var p := VehicleParams.new()
	p.car_id = id
	match id:
		"sedan":
			p.model = "res://assets/cars/sedan.glb"
			p.mass = 1300; p.accel_max = 7.0; p.vmax_kmh = 160; p.brake_decel = 10.5
			p.steer_rate_deg = 190; p.grip = 8.0; p.width = 1.8
			p.accent_color = Color(0.78, 0.18, 0.16)
		"pickup":
			p.model = "res://assets/cars/truck.glb"
			p.mass = 1900; p.accel_max = 6.0; p.vmax_kmh = 140; p.brake_decel = 9.0
			p.steer_rate_deg = 150; p.grip = 6.0; p.width = 2.0
			p.accent_color = Color(0.16, 0.35, 0.72)
		"sport":
			p.model = "res://assets/cars/race.glb"
			p.mass = 1050; p.accel_max = 11.0; p.vmax_kmh = 210; p.brake_decel = 12.3
			p.steer_rate_deg = 230; p.grip = 9.0; p.width = 1.9
			p.accent_color = Color(0.85, 0.75, 0.2)
		_:
			return null
	# габариты берём из модели: единый равномерный масштаб под целевую ширину
	var m := DentBody.measure(p.model)
	var aabb: AABB = m.aabb
	var s := p.width / maxf(0.001, aabb.size.x)
	p.length = aabb.size.z * s
	p.height = aabb.size.y * s
	p.wheel_r = float(m.wheel_r) * s
	return p
