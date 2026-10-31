class_name VehicleDB
extends RefCounted

# Список машин. От него зависит проверка «нитро есть у всех» (h_t30): новый пресет,
# добавленный в match ниже, обязан появиться и здесь — иначе он останется невидимым
# для теста и для игрока.
static func ids() -> Array[String]:
	return ["sedan", "pickup", "limousine", "infinity", "sport"]

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
		"infinity":
			# «Машина бесконечности»: паспортного потолка нет (vmax = INF, и кривая
			# тяги тогда не падает вовсе), разгон вчетверо сильнее спортивного.
			# Тормоз при этом остаётся в покрышечном пределе — иначе она была бы
			# неуправляемой игрушкой, а не машиной, которой можно ехать.
			p.model = "res://assets/cars/race.glb"
			p.mass = 900; p.accel_max = 45.0; p.vmax_kmh = INF; p.brake_decel = 12.3
			p.steer_rate_deg = 260; p.grip = 12.0; p.width = 1.9
			p.accent_color = Color(0.62, 0.28, 0.95)
		"limousine":
			# Лимузин — растянутый кузов седана (DentBody.stretch_model): длиннее на 45%,
			# задняя ось уехала назад. Тяжёлый, длинный и потому медленный: разгон
			# и нитро слабее, чем у спорткара — иначе длинный кузов был бы просто
			# быстрой машиной с другой картинкой.
			p.model = "res://assets/cars/sedan.glb"
			p.body_stretch = 1.45
			# тормоза как у седана: двухтонная машина с 0.67 g тормозила слабее ручника (0.81 g),
			# и педаль на ней ощущалась отказавшей
			p.mass = 2100; p.accel_max = 5.6; p.vmax_kmh = 175; p.brake_decel = 10.5
			# сцепление 7.5: ниже седановского (машина высокая и тяжёлая), но не «грузовое»
			# — с шестёркой на 260 км/ч руль давал 12.5°/с, и вписаться было нельзя
			p.steer_rate_deg = 150; p.grip = 7.5; p.width = 1.9
			p.accent_color = Color(0.10, 0.11, 0.16)
			p.nitro_accel = 5.5; p.nitro_vmax = 1.25
		"sport":
			p.model = "res://assets/cars/race.glb"
			p.mass = 1050; p.accel_max = 11.0; p.vmax_kmh = 210; p.brake_decel = 12.3
			p.steer_rate_deg = 230; p.grip = 9.0; p.width = 1.9
			p.accent_color = Color(0.85, 0.75, 0.2)
		_:
			return null
	# габариты берём из модели: единый равномерный масштаб под целевую ширину
	var m := DentBody.measure(p.model, p.body_stretch)
	var aabb: AABB = m.aabb
	var s := p.width / maxf(0.001, aabb.size.x)
	p.length = aabb.size.z * s
	p.height = aabb.size.y * s
	p.wheel_r = float(m.wheel_r) * s
	return p
