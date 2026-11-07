class_name EffectsDirector
extends Node3D
# Отклик на удар без состояния урона: искры и пыль в точке контакта, дым резины
# у каждого колеса, искры от скребка о стену и пыль от сбитого предмета.
# Никаких зон, HP, дыма и огня — кузов теперь просто мнётся (DentBody).
#
# Порог дыма резины НЕ свой: он берётся из SkidMarks.MIN_SKID — там же, где
# решается, чертить ли следу. Два визуальных эффекта от одного состояния машины
# обязаны включаться на одном и том же условии, иначе «дым есть, следа нет»
# становится нормой.
#
# Стеной занимается не RigidBody3D.get_last_contact_collider: в этом билде
# движка (замер ClassDB на 4.7.2) у RigidBody3D есть только get_contact_count,
# а get_last_contact_* и get_slide_collision не экспортированы вовсе. Поэтому
# бок стены ищется двумя лучами в стороны от кузова: попадание в StaticBody3D
# с почти горизонтальной нормалью — это и есть скользящий контакт боком.

const SCRAPE_MIN_KMH := 30.0       # медленнее — это приставание, а не скребок
const SCRAPE_SUSTAIN_S := 0.08     # контакт должен продержаться, чтобы стать скребком
const SCRAPE_STEP_S := 0.13        # частота искр: каждый следующий залп не чаще этого
const SCRAPE_REACH := 0.5          # луч-«усик» от борта наружу, м

var _sparks: CPUParticles3D
var _dust: CPUParticles3D
var _flames: CPUParticles3D
var _debris: CPUParticles3D
var _smoke: Array[CPUParticles3D] = []
var _smoke_wheels: Array[VehicleWheel3D] = []
var _spark_gap := 0.0
var _car: CarRig
var _enabled := true
var _nitro_on := false
var _scrape_hold := 0.0
var _scrape_gap := 0.0
# счётчики для тестов: сколько залпов скребка и пыльных всплесхов случилось
var scrape_bursts := 0
var prop_puffs := 0

func attach(car: CarRig) -> void:
	# Идемпотентность обязательна: прежний attach оставлял старых детей сиротами
	# в дереве (детей 8 → 16), они выпадали из all_emitters(), и ни set_enabled(false),
	# ни _exit_tree их не гасили — ровно тот путь, на котором исторически был
	# native crash на освобождении эммитеров.
	if _car == car and not _smoke.is_empty(): return
	_car = car
	for c in get_children():
		c.queue_free()
	_sparks = _mk_particles(Color(1.0, 0.82, 0.35), 42, 0.9)
	_dust = _mk_particles(Color(0.62, 0.6, 0.58, 0.5), 26, 2.0)
	_debris = _mk_particles(Color(0.55, 0.48, 0.4, 0.55), 18, 1.1)
	_flames = _mk_flames(car)
	add_child(_sparks)
	add_child(_dust)
	add_child(_debris)
	add_child(_flames)
	_mk_smoke(car)
	if get_parent(): get_parent().remove_child(self)
	car.chassis.add_child(self)
	position = Vector3.ZERO
	if not car.impact.is_connected(_on_impact): car.impact.connect(_on_impact)
	if not car.nitro_changed.is_connected(_on_nitro): car.nitro_changed.connect(_on_nitro)

func _mk_flames(car: CarRig) -> CPUParticles3D:
	var p := _mk_particles(Color(0.45, 0.75, 1.0, 0.85), 60, 0.22)
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 60
	p.lifetime = 0.22
	p.preprocess = 0.0
	p.direction = Vector3(0.0, 0.08, -1.0)
	p.spread = 9.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 13.0
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.26
	p.emitting = false
	# Язык пламени из-за заднего бампера. Нос машины — это локальный +Z (см. YAW_OFFSET),
	# поэтому выхлоп смотрит в −Z и частицы живут в мировых координатах: на 200 км/ч они
	# остаются в воздухе за машиной, а не летят вместе с ней.
	p.position = Vector3(0.0, car.params.wheel_r * 0.55, -car.params.length * 0.5 - 0.12)
	return p

# Дым резины: по эммитеру на колесо, ребёнок самого VehicleWheel3D — узел колеса
# Godot двигает вдоль подвески сам, поэтому точка привязки остаётся у пятна
# контакта на любом ходу подвески.
func _mk_smoke(car: CarRig) -> void:
	# Эммитеры живут НАМ, а не внутри колёс: при удалении машины VehicleWheel3D
	# освобождается вместе с детьми, и активный CPUParticles3D на этом освободении
	# обрывал процесс (замер: 4 пересборки городка = access violation без принтов).
	# Колёса здесь только как источник точки контакта.
	_smoke.clear()
	_smoke_wheels.clear()
	for i in car.wheel_count():
		var vw := car.chassis.get_node_or_null("Wheel%d" % i) as VehicleWheel3D
		if vw == null: continue
		var p := _mk_particles(Color(0.74, 0.74, 0.75, 0.38), 32, 1.15)
		p.one_shot = false
		p.explosiveness = 0.0
		p.preprocess = 0.0
		p.direction = Vector3(0.0, 0.55, -0.55)
		p.spread = 30.0
		p.initial_velocity_min = 1.2
		p.initial_velocity_max = 3.2
		p.gravity = Vector3(0.0, 0.55, 0.0)
		# облако резины — не пылинка: 0.12–0.34 м живым кадром читалось как
		# ничего, хотя эммитер был включён; настоящие клубы — доли метра
		p.scale_amount_min = 0.35
		p.scale_amount_max = 0.95
		p.emitting = false
		add_child(p)
		_smoke.append(p)
		_smoke_wheels.append(vw)

func _mk_particles(color: Color, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 42.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.albedo_texture = _soft_dot()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = m
	p.mesh = q
	return p

func _soft_dot() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 32; gt.height = 32
	return gt

# Единый переключатель всех частиц: настройка «ЧАСТИЦЫ» и пауза заезда.
# Плотность не крутим — только вкл/выкл: дешёвые CPUParticles3D с малым бюджетом
# не дают заметной выгоды от промежуточных количеств, а честный on/off тестируется
# без GPU (см. README, раздел «Звук, вибрация и частицы»).
func set_enabled(v: bool) -> void:
	_enabled = v
	if not v:
		for p in all_emitters(): p.emitting = false
		return
	_flames.emitting = _nitro_on

func all_emitters() -> Array[CPUParticles3D]:
	var out: Array[CPUParticles3D] = [_sparks, _dust, _debris, _flames]
	out.append_array(_smoke)
	return out

func reset_transient() -> void:
	# рестарт заезда: текущие залпы гасим, пороги скребка забываем
	for p in [_sparks, _dust, _debris]: p.emitting = false
	_scrape_hold = 0.0
	_scrape_gap = 0.0
	_spark_gap = 0.0

# Дым живёт детьми колёс, поэтому при удалении машины его нужно погасить ДО того,
# как узел колеса начнёт освобождаться: CPUParticles3D с активным потоком частиц на
# освобождении родителя оборвал процесс (access violation без единого принта).
func _exit_tree() -> void:
	for p in all_emitters():
		p.emitting = false

func smoke_emitters() -> Array[CPUParticles3D]:
	return _smoke

func _on_nitro(active: bool) -> void:
	_nitro_on = active
	if _enabled: _flames.emitting = active

# Скольжение колеса → дым по тому же условию, что и след резины у SkidMarks.
func _physics_process(dt: float) -> void:
	if not _enabled or _car == null or _car.chassis == null: return
	var levels := _car.skid_levels()
	for i in mini(_smoke.size(), levels.size()):
		var on := levels[i] >= SkidMarks.MIN_SKID
		_smoke[i].emitting = on
		# точка привязки живёт у пятна контакта: ход подвески колесо двигает само,
		# а эммитер теперь наш ребёнок, поэтому высоту доносим сюда
		if on: _smoke[i].global_position = _car.wheel_contact(i)
	_update_scrape(clampf(dt, 0.0, 0.25))

# Таймеры скребка копим кадрами: headless с --fixed-fps гонит симуляцию быстрее
# часовой стены, и ticks_msec-порог давал бы один залп на весь заезд.
func _update_scrape(dt: float) -> void:
	_scrape_gap = maxf(_scrape_gap - dt, 0.0)
	_spark_gap = maxf(_spark_gap - dt, 0.0)
	if _car.speed_kmh() < SCRAPE_MIN_KMH:
		_scrape_hold = 0.0
		return
	var side := _side_wall_contact()
	if side.is_empty():
		_scrape_hold = 0.0
		return
	_scrape_hold += dt
	if _scrape_hold < SCRAPE_SUSTAIN_S or _scrape_gap > 0.0: return
	_scrape_gap = SCRAPE_STEP_S
	scrape_bursts += 1
	var amt := clampi(int(_car.speed_kmh() * 0.25), 8, 36)
	_sparks.global_position = side["position"]
	_sparks.amount = amt
	_sparks.emitting = false
	_sparks.emitting = true

# Два луча из бортов наружу. Стена — это неподвижное тело с почти горизонтальной
# нормалью; пол (нормаль вертикальна) и сбитые предметы (не StaticBody3D) отсекаются.
func _side_wall_contact() -> Dictionary:
	var xf := _car.chassis.global_transform
	var half := _car.params.width * 0.5
	var rid := _car.chassis.get_rid()
	for sx in [-1.0, 1.0]:
		var from: Vector3 = xf * Vector3(sx * maxf(half - 0.06, 0.05), 0.12, 0.0)
		var to: Vector3 = xf * Vector3(sx * (half + SCRAPE_REACH), 0.12, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to, _car.chassis.collision_mask, [rid])
		q.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty(): continue
		if not (hit["collider"] is StaticBody3D): continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.5: continue
		return hit
	return {}

# Всплесх пыли от сбитого предмета. GameManager передаёт этот метод в
# LooseProp.on_hit_fx — без него предмет ведёт себя ровно как раньше.
func on_prop_hit(point: Vector3, speed_ms: float) -> void:
	if not _enabled: return
	var v := 0.0 if not is_finite(speed_ms) else maxf(speed_ms, 0.0)
	if v < 3.0: return
	prop_puffs += 1
	_debris.global_position = point
	_debris.amount = clampi(int(10.0 + v * 1.2), 10, 30)
	_debris.emitting = false
	_debris.emitting = true

func _on_impact(speed_kmh: float, point: Vector3, _normal: Vector3) -> void:
	if not _enabled: return
	if speed_kmh < 15.0: return
	var now := _spark_gap
	if now > 0.0: return
	_spark_gap = 0.08
	_sparks.global_position = point
	_dust.global_position = point
	_sparks.amount = int(clampf(speed_kmh * 0.4, 12.0, 64.0))
	_dust.amount = int(clampf(speed_kmh * 0.22, 8.0, 40.0))
	for p in [_sparks, _dust]:
		p.emitting = false
		p.emitting = true
