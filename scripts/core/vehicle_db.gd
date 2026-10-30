class_name VehicleDB
extends RefCounted

static func get_params(id: String) -> VehicleParams:
	var p := VehicleParams.new()
	p.car_id = id
	match id:
		"sedan":
			p.mass = 1300; p.accel_max = 7.0; p.vmax_kmh = 160; p.brake_decel = 22
			p.steer_rate_deg = 38; p.grip = 8.0
			p.length = 4.4; p.width = 1.8; p.height = 1.45; p.gc = 0.32
			p.body_h = 0.62; p.roof_h = 0.51; p.cab_x0 = -1.0; p.cab_x1 = 0.95
			p.hood_scale = 0.82; p.trunk_scale = 0.88; p.wheel_r = 0.37
			p.sections = 20; p.k_struct = 1.0; p.k_anchor = 1.2
			p.break_strain = 0.22; p.shell_color = Color(0.78, 0.18, 0.16)
		"pickup":
			p.mass = 1900; p.accel_max = 6.0; p.vmax_kmh = 140; p.brake_decel = 18
			p.steer_rate_deg = 30; p.grip = 6.0
			p.length = 5.2; p.width = 2.0; p.height = 1.9; p.gc = 0.45
			p.body_h = 0.85; p.roof_h = 0.60; p.cab_x0 = -1.55; p.cab_x1 = -0.15
			p.hood_scale = 0.78; p.trunk_scale = 0.62; p.wheel_r = 0.46
			p.sections = 22; p.k_struct = 1.3; p.k_anchor = 1.6
			p.break_strain = 0.28; p.shell_color = Color(0.16, 0.35, 0.72)
		"sport":
			p.mass = 1050; p.accel_max = 11.0; p.vmax_kmh = 210; p.brake_decel = 26
			p.steer_rate_deg = 42; p.grip = 9.0
			p.length = 4.2; p.width = 1.9; p.height = 1.0; p.gc = 0.22
			p.body_h = 0.44; p.roof_h = 0.34; p.cab_x0 = -1.25; p.cab_x1 = -0.05
			p.hood_scale = 0.72; p.trunk_scale = 0.82; p.wheel_r = 0.33
			p.sections = 18; p.k_struct = 0.8; p.k_anchor = 1.0
			p.break_strain = 0.16; p.shell_color = Color(0.85, 0.75, 0.2)
		_:
			return null
	return p
