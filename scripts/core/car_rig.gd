class_name CarRig
extends Node3D
# Механика машины — штатный VehicleBody3D + VehicleWheel3D из Godot: подвеска на лучах,
# сцепление шин, скольжение и торможение считаются движком. Сверху только аркадная
# кривая тяги (иначе машина не достигает паспортной vmax) и детектор удара по потере
# скорости — он же мнёт кузов.

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)

const IMPACT_DECEL := 210.0        # км/ч за секунду (~6 g): резкое торможение, которое считаем ударом
const IMPACT_MIN_KMH := 28.0
const IMPACT_WINDOW := 4           # тиков, за которые меряем потерю скорости
const STEER_MAX_DEG := 30.0        # полный угол передних колёс на месте
const LAT_ACCEL_CAP := 10.5        # м/с²: потолок бокового ускорения в повороте (~1.07 g)
const SLIP_BASE := 2.2             # сцепление шины при grip=8 (см. VehicleParams.grip)
const SLIP_HANDBRAKE := 1.2        # сцепление задних колёс на ручнике — отсюда занос
const HB_DECEL := 11.0             # м/с² запроса к задней оси: заведомо выше того, что держат шины, поэтому колёса именно блокируются, а фактическое торможение ограничено уже сцеплением
const HB_HOLD_DECEL := 14.0        # на почти остановившейся машине ручник должен её держать
const HB_HOLD_MS := 1.0            # м/с, ниже которой включается режим удержания
const HB_THROTTLE := 0.4           # доля тяги передних колёс на ручнике: заносом можно рулить газом
const REVERSE_RATIO := 0.18        # задний ход — 18% от vmax
const GRAVITY := 9.81
# Предел торможения по сцеплению: шины легковушки держат ~1.1 g, спорткар на сликах —
# ~1.3 g. Замедление выше этого физически невозможно: машина встаёт в одну точку, и
# это ощущается не как торможение, а как удар о невидимую стену.
const BRAKE_MAX_G := 1.25
const PEDAL_RISE := 7.0            # 1/с: педаль набирает давление за ~0.14 с, а не по щелчку
const ESP_SLIDE_START := 0.15      # доля бокового скольжения, с которой включается ESP
const ESP_DAMP := 5.0              # 1/с: насколько ESP гасит рыскание в заносе
const YAW_DAMP := 0.35             # 1/с: фоновое затухание рыскания
const AIR_ANGULAR_DAMP := 3.0      # 1/с: затухание вращения в полёте
const COAST_DECEL := 1.8           # м/с² замедления на нейтрали (накат и движущее торможение)
const AIR_DRAG := 0.008            # 1/с: сопротивление воздуха, гасит раскачку и даёт спад тяги к vmax
const CLEARANCE := 0.22            # м: низ коллайдера над полом = высота ступени, которую машина переедет
const SUSP_STIFFNESS := 120.0
const SUSP_TRAVEL := 0.20
const SUSP_DAMP_COMPRESS := 7.0
const SUSP_DAMP_RELAX := 9.0
const SUSP_MAX_G := 3.0            # предел силы подвески в единицах веса
const GRIP_REF := 8.0
const RECENT_DECAY := 96.0         # км/ч за секунду
const YAW_OFFSET := PI * 0.5       # VehicleBody3D едет носом в +Z (проверено), а проект живёт в «+X вперёд»
const SKID_SLIDE_START := 0.18     # боковой увод, с которого резина начинает чертить
const SKID_MIN_MS := 3.0           # медленнее — след не оставляем
const SLIP_FULL := 0.45            # боковой увод, при котором шин уже не осталось

var params: VehicleParams
var chassis: VehicleBody3D
var body: DentBody
var heading := 0.0
var _wheels: Array[VehicleWheel3D] = []
var _slip_normal := SLIP_BASE
var _wheelbase := 2.6
var _traction_count := 0
var _rear_count := 2
var _drive_scale := 0.25
var _brake_scale := 0.25
var _rear_scale := 0.5
var _steer := 0.0
var _pedal := 0.0
var _roll: Array[float] = []
var _mount_y: Array[float] = []
var _susp_static := 0.0
var _skid: PackedFloat32Array = PackedFloat32Array()
# 0 = шины держат прямо, 1 = машина едет боком (отношение боковой составляющей
# скорости к продольной). Наружу отдаётся уже с учётом ручника: на ручнике увод
# считается сорванным всегда, иначе индикатор сцепления показывал бы «держит».
var slip := 0.0
var _hist: Array[Vector3] = []
var _recent_speed := 0.0
var _impact_cooldown := 0.0
var _grounded := true
var _prev_yaw := 0.0
var _yaw_init := false

func build(p: VehicleParams, _world: World3D) -> void:
	params = p
	chassis = VehicleBody3D.new()
	chassis.mass = p.mass
	chassis.contact_monitor = true
	chassis.max_contacts_reported = 8
	chassis.continuous_cd = true
	chassis.can_sleep = false
	# дефолтное затухание проекта (0.1) съедало треть vmax, поэтому в project.godot оно
	# обнулено, а сопротивление воздуха задаём сами — на порядок слабее
	chassis.linear_damp = AIR_DRAG
	# Трение только у коробки кузова: скользкий борт не съедает скорость при касании стены
	# (с 0.85 машина теряла почти половину). На шины это не влияет — там wheel_friction_slip.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15
	pm.bounce = 0.0
	chassis.physics_material_override = pm
	add_child(chassis)
	body = DentBody.new()
	chassis.add_child(body)
	body.setup(p.model, p)
	var wr := body.wheel_radius
	# центр масс ниже линии осей: иначе VehicleBody3D валится на бок при первом же повороте
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = Vector3(0, -wr * 0.55, 0)
	# кузов стоит колёсами на локальном нуле: опускаем так, чтобы оси колёс легли в ноль рамы,
	# и доворачиваем на -90°, чтобы его «+X вперёд» совпал с «+Z вперёд» у VehicleBody3D
	body.position = Vector3(0, -wr, 0)
	body.rotation.y = -YAW_OFFSET
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# В раме длина машины лежит вдоль Z, ширина вдоль X. Коробка обязана описывать кузов
	# целиком: с запасом 0.94 нос выступал на 9 см и при ударе проходил сквозь стену.
	# Низ поднимаем на CLEARANCE над срезом колёс — иначе коробка трётся о пол и съедает
	# 3.4 м/с² разгона; заодно это позволяет переезжать бордюр, а не упираться в него.
	var col_bottom := -wr + CLEARANCE
	var col_top := p.height - wr
	shape.size = Vector3(p.width, col_top - col_bottom, p.length)
	col.shape = shape
	col.position = Vector3(0, (col_top + col_bottom) * 0.5, 0)
	chassis.add_child(col)
	var locals := body.wheel_local_positions()
	_slip_normal = SLIP_BASE * p.grip / GRIP_REF
	var x_max := -INF
	var x_min := INF
	for lp in locals:
		x_max = maxf(x_max, lp.x)
		x_min = minf(x_min, lp.x)
	# база (межосевое расстояние) заметно короче длины кузова — именно она задаёт
	# радиус поворота, поэтому ограничение угла считаем по ней
	_wheelbase = maxf(0.5, x_max - x_min)
	var rest := _suspension_rest(wr, locals.size())
	# на сколько подвеска сжата на стоянке: из него считаем, как далеко колесо вышло из арки
	var static_c := 9.81 / (maxf(1.0, float(locals.size())) * SUSP_STIFFNESS)
	_susp_static = rest - static_c
	for i in locals.size():
		var w := VehicleWheel3D.new()
		w.name = "Wheel%d" % i
		w.position = body.transform * locals[i]
		w.wheel_radius = wr
		w.wheel_rest_length = rest
		w.suspension_travel = SUSP_TRAVEL
		w.suspension_stiffness = SUSP_STIFFNESS
		w.suspension_max_force = p.mass * 9.8 * SUSP_MAX_G
		w.wheel_friction_slip = _slip_normal
		w.damping_compression = SUSP_DAMP_COMPRESS
		w.damping_relaxation = SUSP_DAMP_RELAX
		w.use_as_steering = body.wheel_is_front(i)
		w.use_as_traction = true
		w.wheel_roll_influence = 0.0   # визуальные колёса крутим сами из ассета
		chassis.add_child(w)
		_wheels.append(w)
		_mount_y.append(w.position.y)
		_roll.append(0.0)
		if w.use_as_traction: _traction_count += 1
		if not w.use_as_steering: _rear_count += 1
	# engine_force и brake Godot прикладывает к каждому ведущему колесу отдельно
	# (замерено: 4 колеса дают ровно 4·F/m), поэтому паспортные м/с² делим на их число
	_drive_scale = 1.0 / maxf(1.0, float(_traction_count))
	# служебный тормоз делится на все колёса, ручник — только на заднюю ось
	_brake_scale = 1.0 / maxf(1.0, float(_wheels.size()))
	_rear_scale = 1.0 / maxf(1.0, float(_rear_count))
	_skid.resize(_wheels.size())
	_skid.fill(0.0)

# Статический ход подвески. В Godot луч колеса имеет длину rest+radius, но параметр
# попадания нормируется на (2*radius+rest), поэтому равновесие наступает при
# (R+L)·L/(2R+L) = g/(N·k). Решаем относительно L — тогда на стоянке колёса стоят
# на земле, а не висят над ней и не тонут в ней.
static func _suspension_rest(radius: float, wheel_count: int) -> float:
	var c := 9.81 / (maxf(1.0, float(wheel_count)) * SUSP_STIFFNESS)
	var b := radius - c
	return 0.5 * (-b + sqrt(b * b + 8.0 * c * radius))

func respawn(tf: Transform3D) -> void:
	heading = tf.basis.get_euler().y
	var rest_y := body.wheel_radius + 0.02
	chassis.global_transform = Transform3D(Basis(Vector3.UP, heading + YAW_OFFSET), Vector3(tf.origin.x, rest_y, tf.origin.z))
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	_steer = 0.0
	_pedal = 0.0
	_recent_speed = 0.0
	_hist.clear()
	_impact_cooldown = 0.0
	_yaw_init = false
	for i in _roll.size(): _roll[i] = 0.0
	if body != null: body.reset()

func speed_kmh() -> float:
	return chassis.linear_velocity.length() * 3.6

func forward() -> Vector3:
	return chassis.global_transform.basis.z

func forward_speed_ms() -> float:
	return chassis.linear_velocity.dot(forward())

func _physics_process(dt: float) -> void:
	if chassis == null or _wheels.is_empty(): return
	_update_heading()
	_drive(dt)
	_pose_wheels(dt)
	_detect_impact(dt)

func _drive(dt: float) -> void:
	var throttle := Input.get_action_strength("throttle")
	var brake_in := Input.get_action_strength("brake")
	var hand := Input.is_action_pressed("handbrake")
	var steer_in := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var v := chassis.linear_velocity
	var vf := v.dot(forward())
	var vmax := params.vmax_kmh / 3.6
	# тяга падает к vmax: штатной кривой момента в Godot 4.7 нет, а без этого
	# машина разгонялась бы вечно
	var pull := clampf(1.0 - pow(absf(vf) / vmax, 1.6), 0.0, 1.0)
	var drive := throttle * params.mass * params.accel_max * pull
	# S — тормоз, пока машина катится вперёд, и задний ход, когда она почти встала
	var reverse := brake_in > 0.0 and vf < 0.6 and not hand
	if reverse:
		var back := clampf(1.0 - absf(vf) / (vmax * REVERSE_RATIO), 0.0, 1.0)
		drive = -brake_in * params.mass * params.accel_max * 0.55 * back
	# Именно brake-импульс на колесо, а не правка linear_velocity: запись скорости из
	# _physics_process обнуляет импульсы подвески, и машина оседает на коллайдер.
	# brake — это потолок импульса за тик (замерено: 98 Н·с даёт 18 м/с²), поэтому dt.
	var service := 0.0
	# педаль — состояние, а не мгновенное чтение: иначе короткое касание курка или
	# клавиши отдаёт полным тормозом за один тик
	_pedal = move_toward(_pedal, brake_in, PEDAL_RISE * dt)
	if reverse or hand:
		pass
	elif _pedal > 0.0:
		service = params.mass * minf(params.brake_decel, BRAKE_MAX_G * GRAVITY) * _pedal * dt
	elif throttle <= 0.0:
		service = params.mass * COAST_DECEL * dt
	# Ручник — ТОЛЬКО задняя ось. Через chassis.brake его нельзя дать на одно колесо:
	# Godot рассылает свойство всем колёсам разом (vehicle_body_3d.cpp: set_brake
	# проходит по m_wheelInfos), поэтому прошлый «ручник» блокировал четыре колеса
	# и стирал 0.8 g — на геймпаде, где курок держат пальцем, это выглядело как
	# мгновенная остановка. Теперь задние блокируются, передние катятся свободно.
	var rear_brake := 0.0
	if hand:
		rear_brake = params.mass * (HB_DECEL if absf(vf) > HB_HOLD_MS else HB_HOLD_DECEL) * dt
	# Угол колёс ограничен сверху допустимым боковым ускорением: линейная зависимость
	# от скорости не спасала — на 150 км/ч даже 7° требуют от шин 10 g, машина срывается
	# в скольжение и «поворачивает» на 70° в секунду.
	var lock := deg_to_rad(STEER_MAX_DEG)
	var sp := absf(vf)
	if sp > 2.0: lock = minf(lock, atan(LAT_ACCEL_CAP * _wheelbase / (sp * sp)))
	_steer = move_toward(_steer, lock * steer_in, deg_to_rad(params.steer_rate_deg) * dt)
	chassis.steering = _steer
	var side := v - forward() * vf
	side.y = 0.0
	var slide := side.length() / maxf(2.0, absf(vf))
	_grounded = false
	for i in _wheels.size():
		var w := _wheels[i]
		var rear := not w.use_as_steering
		var locked := hand and rear
		# в Godot brake колеса учитывается только при engine_force == 0
		# (vehicle_body_3d.cpp: `if (m_engineForce != 0) rollingFriction = -engineForce*step`),
		# поэтому на ручнике задняя ось теряет тягу, а передняя продолжает тянуть
		# HB_THROTTLE — заносом можно рулить газом, и с зажатым W ручник работает.
		w.engine_force = 0.0 if (hand and rear) else drive * _drive_scale * (HB_THROTTLE if hand else 1.0)
		# служебный тормоз и накат — на все четыре колеса, ручник сверху добавляет
		# блокировку только задней оси
		w.brake = service * _brake_scale + (rear_brake * _rear_scale if rear else 0.0)
		w.wheel_friction_slip = SLIP_HANDBRAKE if locked else _slip_normal
		if w.is_in_contact():
			_grounded = true
			# резина оставляет след, когда колесо заблокировано ручником или когда
			# боковой увод велик; на малой скорости пятно не рисуем вовсе
			var s := (1.0 if locked else 0.0) + (slide - SKID_SLIDE_START) * 4.0
			_skid[i] = clampf(s, 0.0, 1.0) * clampf(absf(vf) / SKID_MIN_MS, 0.0, 1.0)
		else:
			_skid[i] = 0.0
	# ESP: упрощённые шины Godot не гасят начатый занос — сорвавшуюся машину не поймать
	# даже контррулём. Поэтому без ручника наращиваем затухание рыскания пропорционально
	# тому, насколько сильно машина едет боком. Именно свойство angular_damp, а не правка
	# angular_velocity: запись скорости из _physics_process ломает подвеску.
	slip = clampf(1.0 if hand else slide / SLIP_FULL, 0.0, 1.0)
	var slide_esp := 0.0 if hand else slide
	if _grounded:
		chassis.angular_damp = YAW_DAMP + ESP_DAMP * clampf((slide_esp - ESP_SLIDE_START) * 4.0, 0.0, 1.0)
	else:
		# в воздухе вращение гасим сильнее: прыжок должен заканчиваться приземлением
		# на четыре колеса, а не кульбитом и ударом об угол
		chassis.angular_damp = AIR_ANGULAR_DAMP

# Насколько сильно скользит i-е колесо (0..1) — вход для следов резины на асфальте.
func skid_levels() -> PackedFloat32Array:
	return _skid

func wheel_count() -> int:
	return _wheels.size()

# Точка контакта i-го колеса. Godot сам двигает узел колеса вдоль хода подвески, а высота
# покоя равна радиусу (замерено в h_t15), поэтому минус радиус по Y — это поверхность.
func wheel_contact(i: int) -> Vector3:
	var w := _wheels[i]
	return w.global_position - Vector3(0.0, w.wheel_radius, 0.0)

# Удар — это резкое торможение, а не сам факт касания: поэтому заезд на рампу,
# приземление после прыжка и лёгкое касание борта ударом не считаются. Меряем по окну
# в несколько тиков: настоящая физика гасит скорость не мгновенно, как прежний
# аркадный контроллер, и порог «за тик» не срабатывал вообще.
func _detect_impact(dt: float) -> void:
	var v := chassis.linear_velocity
	_hist.append(v)
	while _hist.size() > IMPACT_WINDOW + 1: _hist.pop_front()
	_impact_cooldown = maxf(_impact_cooldown - dt, 0.0)
	var hspeed := _hspeed(v)
	var old: Vector3 = _hist[0]
	var window := dt * float(_hist.size() - 1)
	var decel := 0.0 if window <= 0.0 else (_hspeed(old) - hspeed) / window
	if decel > IMPACT_DECEL and _recent_speed > IMPACT_MIN_KMH and _impact_cooldown <= 0.0:
		var dv := old - v
		if dv.length_squared() > 0.25:
			var n := dv.normalized()                 # куда ушёл импульс — туда и мнётся кузов
			var hx := absf(n.x) * params.length * 0.5 + absf(n.z) * params.width * 0.5
			var point := chassis.global_position + n * hx + Vector3(0, 0.1, 0)
			impact.emit(_recent_speed, point, -n)
			body.apply_impact(point, n, _recent_speed)
			_impact_cooldown = 1.0
	_recent_speed = maxf(_recent_speed - RECENT_DECAY * dt, hspeed)

func _hspeed(v: Vector3) -> float:
	return Vector3(v.x, 0.0, v.z).length() * 3.6

# Визуальные колёса ассета следят за физическими: ход подвески, угол поворота, качение.
func _pose_wheels(dt: float) -> void:
	for i in _wheels.size():
		var w := _wheels[i]
		# Godot сам двигает узел колеса вдоль подвески (get_suspension_travel() — это просто
		# геттер свойства), поэтому ход берём из смещения узла относительно опоры
		var drop: float = (_mount_y[i] - w.position.y) - _susp_static
		_roll[i] = fposmod(_roll[i] + w.get_rpm() / 60.0 * TAU * dt, TAU)
		body.set_wheel_pose(i, clampf(drop, -SUSP_TRAVEL, w.wheel_rest_length), w.get_steering(), _roll[i])

# get_euler() отдаёт рыскание в [-π, π], поэтому heading разворачиваем по кратчайшей
# дуге: иначе на полном круге он скачет на ±360° и ломает всё, что его сравнивает.
func _update_heading() -> void:
	var yaw := chassis.global_basis.get_euler().y - YAW_OFFSET
	heading = yaw if not _yaw_init else heading + wrapf(yaw - _prev_yaw, -PI, PI)
	_prev_yaw = yaw
	_yaw_init = true
