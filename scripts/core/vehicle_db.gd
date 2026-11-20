class_name VehicleDB
extends RefCounted

# Список машин. От него зависит проверка «нитро есть у всех» (h_nitro): новый пресет,
# добавленный в match ниже, обязан появиться и здесь — иначе он останется невидимым
# для теста и для игрока.
#
# Player mods add ids after the built-ins: ModDB reads user://mods and keeps the
# physics whitelist, so ids()/get_params() are the only surfaces the rest of the
# game needs to know about.
static func base_ids() -> Array[String]:
	return ["sedan", "pickup", "limousine", "infinity", "sport"]

static func ids() -> Array[String]:
	var out := base_ids()
	for id in ModDB.car_ids():
		if not out.has(id): out.append(id)
	return out

static func get_params(id: String) -> VehicleParams:
	var p := _base_params(id)
	if p != null: return p
	var mod := ModDB.car(id)
	return _mod_params(mod) if not mod.is_empty() else null

static func _base_params(id: String) -> VehicleParams:
	var p := VehicleParams.new()
	p.car_id = id
	match id:
		"sedan":
			p.model = "res://assets/cars/sedan.glb"
			p.mass = 1300; p.accel_max = 7.0; p.vmax_kmh = 160; p.brake_decel = 13.5
			p.steer_rate_deg = 300; p.grip = 8.0; p.width = 1.8
			p.accent_color = Color(0.78, 0.18, 0.16)
		"pickup":
			p.model = "res://assets/cars/truck.glb"
			p.mass = 1900; p.accel_max = 6.0; p.vmax_kmh = 140; p.brake_decel = 12.0
			p.steer_rate_deg = 240; p.grip = 6.0; p.width = 2.0
			p.accent_color = Color(0.16, 0.35, 0.72)
		"infinity":
			# «Машина бесконечности»: паспортного потолка нет (vmax = INF, и кривая
			# тяги тогда не падает вовсе), разгон вчетверо сильнее спортивного.
			# Тормоз при этом остаётся в покрышечном пределе — иначе она была бы
			# неуправляемой игрушкой, а не машиной, которой можно ехать.
			p.model = "res://assets/cars/race.glb"
			p.mass = 900; p.accel_max = 45.0; p.vmax_kmh = INF; p.brake_decel = 16.2
			p.steer_rate_deg = 390; p.grip = 12.0; p.width = 1.9
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
			p.mass = 2100; p.accel_max = 5.6; p.vmax_kmh = 175; p.brake_decel = 13.0
			# сцепление 7.5: ниже седановского (машина высокая и тяжёлая), но не «грузовое»
			# — с шестёркой на 260 км/ч руль давал 12.5°/с, и вписаться было нельзя
			p.steer_rate_deg = 240; p.grip = 7.5; p.width = 1.9
			p.accent_color = Color(0.10, 0.11, 0.16)
			p.nitro_accel = 5.5; p.nitro_vmax = 1.25
		"sport":
			p.model = "res://assets/cars/race.glb"
			p.mass = 1050; p.accel_max = 11.0; p.vmax_kmh = 210; p.brake_decel = 16.2
			p.steer_rate_deg = 360; p.grip = 9.0; p.width = 1.9
			p.accent_color = Color(0.85, 0.75, 0.2)
		_:
			return null
	# габариты берём из модели: единый равномерный масштаб под целевую ширину
	_derive_dims(p)
	p.paint_color = Materials.stock_paint_color(p.model)
	return p

# Length, height and wheel radius come from the model, so a mod that changes the
# target width or the body stretch must have them re-derived: the collider and
# wheel placement read these numbers, not the raw model.
static func _derive_dims(p: VehicleParams) -> void:
	var m := DentBody.measure(p.model, p.body_stretch)
	var aabb: AABB = m.aabb
	var s := p.width / maxf(0.001, aabb.size.x)
	p.length = aabb.size.z * s
	p.height = aabb.size.y * s
	p.wheel_r = float(m.wheel_r) * s

# A mod car is the base car plus whitelisted overrides. ModDB already clamped
# every value; the base is guaranteed to be a built-in by the loader, so this
# cannot recurse into another mod.
static func _mod_params(car: Dictionary) -> VehicleParams:
	var p := _base_params(String(car.get("base", "")))
	if p == null: return null
	p.car_id = String(car.get("id", ""))
	var params: Dictionary = car.get("params", {})
	for key in params:
		if ModDB.PARAM_RANGES.has(key): p.set(key, params[key])
	var color: Variant = car.get("color")
	if color is Color: p.accent_color = color
	_derive_dims(p)
	return p
