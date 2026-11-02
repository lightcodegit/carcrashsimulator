class_name CarRig
extends Node3D
# Механика машины — штатный VehicleBody3D + VehicleWheel3D из Godot: подвеска на лучах,
# сцепление шин, скольжение и торможение считаются движком. Сверху только аркадная
# кривая тяги (иначе машина не достигает паспортной vmax) и детектор удара по потере
# скорости — он же мнёт кузов.

signal impact(speed_kmh: float, point: Vector3, normal: Vector3)
signal nitro_changed(active: bool)

const IMPACT_DECEL := 210.0        # км/ч за секунду (~6 g): резкое торможение, которое считаем ударом
const IMPACT_MIN_KMH := 28.0
const IMPACT_WINDOW := 4           # тиков, за которые меряем потерю скорости
const STEER_MAX_DEG := 30.0        # полный угол передних колёс на месте
# Минимальный радиус, который машина обязана уметь выдать на любой скорости. Пол — не в
# градусах, а в радиусах: угол, нужный для одного и того же радиуса, растёт с базой
# (R = L/tgδ), поэтому единый градус на всех машинах оставляет «не поворачивает» именно
# длиннобазную — именно оттуда и жалоба. Замер: 22 м — это 7.5° передних колёс седану и
# 11.6° лимузину, и в коридор вписывания на 30° при 200 км/ч умещаются все три машины
# (29–37 м, меряет h_steering).
const STEER_MIN_R := 22.0
const LAT_ACCEL_CAP := 18.0        # м/с²: потолок бокового ускорения в повороте (~1.8 g)
const SLIP_BASE := 2.2             # сцепление шины при grip=8 (см. VehicleParams.grip)
const SLIP_HANDBRAKE := 1.2        # сцепление задних колёс на ручнике — отсюда занос
# HB_DECEL — запрос тормоза на заднюю ось ЦЕЛИКОМ (делится на её колёса через
# _rear_scale). 5.5 м/с² с передней добавкой HB_FRONT_G даёт 0.74–0.87 g накатом —
# ровно замеры h_handbrake_devices, в которых ручник остаётся заносом, а не экстренной остановкой
# (короче педали). Прежний код маскировал ошибку счёта осей: константа 11 при
# удвоенном _rear_count физически прикладывалась как 5.5 — теперь арифметика чистая.
const HB_DECEL := 5.5
const HB_HOLD_DECEL := 7.0         # на почти остановившейся машине ручник должен её держать
const HB_HOLD_MS := 1.0            # м/с, ниже которой включается режим удержания
# Доля тяги передних колёс на ручнике: заносом можно рулить газом. Чем она больше, тем
# сильнее передок вытягивает машину из торможения: при 0.4 ручник с зажатым W терял почти
# всю силу (замер h_handbrake_devices: 0.43 g за секунду).
const HB_THROTTLE := 0.22
# Сколько тормоза передняя ось добавляет к заблокированной задней, в долях g. Цифры ниже —
# из h_handbrake_devices (окно в 1 с на ~57 км/ч), там же они и проверяются. Без этой доли: 0.47 g с
# зажатым газом и 0.53 g накатом — ровно жалоба «ручник почти не тормозит». С ней: 0.74 g
# с газом и 0.81 g накатом, пик одного тика 0.87 g, короткое касание за 0.2 с снимает 6–7%
# скорости. Служебная педаль в том же тесте — 0.96 g, то есть ручник по-прежнему тормозит
# короче педали, и нарастание педали в 0.14 с не даёт ему читаться как «мгновенная остановка»
# из прежней жалобы на геймпад.
const HB_FRONT_G := 0.30
const REVERSE_RATIO := 0.18        # задний ход — 18% от vmax
const REVERSE_LAG := 0.5           # с удержания педали на остановке до включения задней
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
const SUSP_MAX_G := 6.0            # предел силы подвески в единицах веса
# Гидроупор: как далеко от грани и с каким потолком замедления он гасит падение. Без него
# жёсткая посадка пробивает подвеску, и дальше падает уже коллайдер — а это не упругий
# удар, а трение кузова об дорогу с потерей продольной скорости.
const BUMP_GAP := 0.12             # м: ниже этого запаса упор уже не разгоняется
const BUMP_SOFT := 1.5             # м/с: с такой вертикалью кузову разрешаем коснуться граны
const BUMP_A := 45.0               # м/с²: потолок замедления падения (~4.6 g)
const BUMP_K := 120.0              # 1/с²: сколько упор добирает, если кузов ушёл под грань
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
var _box_bottom := -0.2            # низ коллайдера рамы в системе координат кузова
var _box_half := Vector3(0.9, 0.0, 1.9)
var _traction_count := 0
# Задняя ось считается с нуля и только прибавлением невёрстных колёс: прежняя
# инициализация двойкой плюс счётчик давала 4 на обычной машине, _rear_scale 0.25 —
# и задняя ось получала половину заявленного HB_DECEL.
var _rear_count := 0
var _drive_scale := 0.25
var _brake_scale := 0.25
var _rear_scale := 0.5
var _steer := 0.0
var _pedal := 0.0
var _hand_pedal := 0.0             # ручник тоже набирает давление, а не включается по щелчку
var _rev_lag := 0.0                # с удержания педали на остановке (REVERSE_LAG)
var nitro := 0.0                 # сколько форсажа в баке (единицы params.nitro_capacity)
var nitro_active := false        # горит ли он прямо сейчас
var _nitro_was := false
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
	_box_bottom = col_bottom
	_box_half = Vector3(p.width, 0.0, p.length) * 0.5
	col.shape = shape
	col.position = Vector3(0, (col_top + col_bottom) * 0.5, 0)
	chassis.add_child(col)
	var locals := body.wheel_local_positions()
	_slip_normal = SLIP_BASE * p.grip / GRIP_REF
	var z_max := -INF
	var z_min := INF
	for lp in locals:
		z_max = maxf(z_max, lp.z)
		z_min = minf(z_min, lp.z)
	# Межосевое расстояние — по ОСи Z: в раме длина машины лежит вдоль Z, а вдоль X стоит
	# колея. Прежний расчёт брал x_max - x_min, то есть ширину колеи (~1.6 м вместо ~2.9),
	# и потолок угла выходил почти вдвое меньше допустимого — руль на скорости дубел.
	_wheelbase = maxf(0.5, z_max - z_min)
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
	# Телепорт без сброса интерполяции рисуется разъездом: кадры между тиками
	# выводят машину по пути от старой позиции к новой.
	chassis.reset_physics_interpolation()
	_steer = 0.0
	_pedal = 0.0
	# новый заезд — полный бак, и огонь в выхлопе должен погаснуть, а не мигать
	nitro = params.nitro_capacity
	if nitro_active:
		nitro_active = false
		_nitro_was = false
		nitro_changed.emit(false)
	_recent_speed = 0.0
	_hist.clear()
	_impact_cooldown = 0.0
	_yaw_init = false
	for i in _roll.size(): _roll[i] = 0.0
	if body != null: body.reset()

# Доля бака для индикатора: 1.0 — полный, 0.0 — форсажа нет.
func nitro_fraction() -> float:
	return nitro / maxf(params.nitro_capacity, 1.0)

func speed_kmh() -> float:
	return chassis.linear_velocity.length() * 3.6

func forward() -> Vector3:
	return chassis.global_transform.basis.z

# То же «вперёд», но без вертикальной составляющей: тормозной импульс должен гасить
# движение по земле, а не прижимать машину к асфальту или срывать её в прыжок.
func _flat_forward() -> Vector3:
	var f := forward()
	f.y = 0.0
	return f / f.length() if f.length_squared() > 1e-6 else Vector3.ZERO

# Как машина выглядит НА ЭКРАНЕ в этом кадре. Физика считает 60 Гц, кадр строится чаще,
# и между тиками движок сам выводит положение (интерполяция физики). Всё, что за машиной
# следит — камера в первую очередь — обязано брать эту позицию, а не состояние тика:
# за тиковым камера гонится за точкой, которая на экране уже ушла на метр вперёд, и
# зазор менял знак каждый кадр («камера отстаёт, догоняет и мелькает»).
func render_transform() -> Transform3D:
	return chassis.get_global_transform_interpolated()

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
	# Нитро даёт тягу И поднимает потолок скорости: без второго кривая pull глушила бы
	# форсаж ровно там, где он и нужен — на вершине диапазона. Бак тратится только с
	# нажатым газом и только вперёд: «нитро на нейтрали» ничего не разгоняет, а
	# расходовать его задом нелогично.
	nitro_active = Input.is_action_pressed("nitro") and throttle > 0.0 and vf >= -0.5 \
		and nitro > 0.0
	if nitro_active != _nitro_was:
		_nitro_was = nitro_active
		nitro_changed.emit(nitro_active)
	var vmax_eff := vmax * (params.nitro_vmax if nitro_active else 1.0)
	# тяга падает к vmax: штатной кривой момента в Godot 4.7 нет, а без этого
	# машина разгонялась бы вечно
	var pull := clampf(1.0 - pow(absf(vf) / vmax_eff, 1.6), 0.0, 1.0)
	var drive := throttle * params.mass * params.accel_max * pull
	if nitro_active:
		drive += throttle * params.mass * params.nitro_accel
		nitro = maxf(nitro - params.nitro_drain * dt, 0.0)
	else:
		nitro = minf(nitro + params.nitro_refill * dt, params.nitro_capacity)
	# S — тормоз, пока машина катится вперёд. На остановке педаль сначала ДЕРЖИТ
	# машину, и только после REVERSE_LAG удержания включается задний ход: прежняя
	# мгновенная реверс-тяга отбрасывала машину назад ровно в тот момент, когда
	# водитель ждал остановки, — «торможу, а машина едет назад». Обратный ход
	# держит сам себя: пока vf ушёл за -0.6, тяга не требует лага.
	var holding := brake_in > 0.0 and vf < 0.6 and not hand
	_rev_lag = _rev_lag + dt if holding else 0.0
	var reverse := holding and (vf < -0.6 or _rev_lag >= REVERSE_LAG)
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
	# Педаль считается НЕЗАВИСИМО от ручника: раньше «ручник или педаль» исключали
	# друг друга, и зажатыми вместе машина тормозила СЛАБЕЕ, чем одной педалью —
	# жалоба «тормозить очень сложно и кнопкой назад, и ручником». Задняя ось не
	# получит двойного счёта: там доли сравниваются максимумом ниже, в цикле колёс.
	if reverse:
		pass
	elif _pedal > 0.0:
		service = params.mass * minf(params.brake_decel, BRAKE_MAX_G * GRAVITY) * _pedal * dt
	elif throttle <= 0.0 and not hand:
		# накат при зажатом ручнике не в счёт: окно чистого ручника (0.74–0.87 g)
		# замерялось и проверяется без него, а плюс 1.8 м/с² на четыре колеса сдвигает
		# его до 0.98 g (замер h-прогона после этой правки)
		service = params.mass * COAST_DECEL * dt
	# Ручник — ТОЛЬКО задняя ось. Через chassis.brake его нельзя дать на одно колесо:
	# Godot рассылает свойство всем колёсам разом (vehicle_body_3d.cpp: set_brake
	# проходит по m_wheelInfos), поэтому прошлый «ручник» блокировал четыре колеса
	# и стирал 0.8 g — на геймпаде, где курок держат пальцем, это выглядело как
	# мгновенная остановка. Теперь блокируются только задние, а передняя ось добирает
	# фиксированную долю тормоза (HB_FRONT_G) и остаётся рулевой.
	var rear_brake := 0.0
	var front_brake := 0.0
	if hand:
		rear_brake = params.mass * (HB_DECEL if absf(vf) > HB_HOLD_MS else HB_HOLD_DECEL) * dt
		_hand_pedal = minf(_hand_pedal + PEDAL_RISE * dt, 1.0)
		front_brake = params.mass * HB_FRONT_G * GRAVITY * _hand_pedal * dt
	else:
		_hand_pedal = 0.0
	# Угол колёс ограничен допустимым боковым ускорением, но не ниже STEER_MIN_R.
	# Прежний потолок 1.07 g без нижнего порога на 180 км/ч оставлял 0.5° — руль крутится,
	# машина едет прямо: «на большой скорости не поворачивают нормально». Замер по этой
	# модели шин: боковое ускорение доходит до ~2 g, поэтому потолок поднят до 18 м/с²,
	# а пол по радиусу держит передок в деле. Курс на 180 км/ч: 26°/с вместо 9.8°/с (радиус
	# 111 м против 300 м), после отпускания руля машина доворачивает ещё 1.6° — то есть
	# поворот управляемый, а не занос. На 40 км/ч радиус 19 м вместо 38.
	var lock := deg_to_rad(STEER_MAX_DEG)
	var sp := absf(vf)
	# низ — по радиусу, а не по градусу: см. STEER_MIN_R
	var min_lock := atan(_wheelbase / STEER_MIN_R)
	if sp > 2.0: lock = clampf(atan(LAT_ACCEL_CAP * _wheelbase / (sp * sp)), min_lock, lock)
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
		# Служебный тормоз и накат — на все четыре колеса, ручник сверху блокирует только
		# заднюю ось: через chassis.brake Godot разовьёт тормоз на все колёса разом, а
		# блокировка четырёх колёс стирала 0.8 g и на геймпаде читалась как мгновенная
		# остановка. Доли передней оси здесь нет — она приходит импульсом по телу ниже:
		# на переднем колёсе с тягой колёсный brake не применяется.
		# На задней оси педаль и ручник НЕ складываются (за то же колесо нельзя взять
		# две нормы тормоза): берётся большая из двух долей, поэтому вместе они дают
		# не меньше, чем по отдельности.
		var pedal_share := service * _brake_scale
		var hand_share := rear_brake * _rear_scale if rear else 0.0
		w.brake = maxf(pedal_share, hand_share)
		w.wheel_friction_slip = SLIP_HANDBRAKE if locked else _slip_normal
		if w.is_in_contact():
			_grounded = true
			# резина оставляет след, когда колесо заблокировано ручником или когда
			# боковой увод велик; на малой скорости пятно не рисуем вовсе
			var s := (1.0 if locked else 0.0) + (slide - SKID_SLIDE_START) * 4.0
			_skid[i] = clampf(s, 0.0, 1.0) * clampf(absf(vf) / SKID_MIN_MS, 0.0, 1.0)
		else:
			_skid[i] = 0.0
	# Гидроупор подвески. Хода колёс на жёсткую посадку не хватает: кузов садится на
	# коллайдер, и тормозит его дальше уже он, а не резина — замер: приземление после
	# вылета с трассового трамплина на 270 км/ч давало 47 g и минус 110 км/ч за пять тиков,
	# а приземление прямо на склон горки на 80 км/ч обнуляло машину (80 → 1 км/ч, 30 g).
	# Запас мерим у ЧЕТЫРЁХ углов коллайдера, а не под центром: горка поднимается вперёд,
	# и на середине кузова грань на 0.17 м ниже, чем под носом — центральный луч даёт
	# запас +0.21 там, где нос уже ушёл под верхнюю грань гребня и упрётся в неё брюхом.
	# Работает только НА ДВИЖЕНИИ ВНИЗ: упор гасит падение, а не держит кузов. С веслом
	# в стену нос уходит под пол, пружина долбит вверх, колёса разгружаются, и машина
	# не останавливается, а скользит по стене с растущей вмятиной (замер h_crash: 72 км/ч).
	if v.y < 0.0:
		var worst := INF
		var xf := chassis.global_transform
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c: Vector3 = xf * Vector3(sx * _box_half.x, _box_bottom, sz * _box_half.z)
				var ray := PhysicsRayQueryParameters3D.create(c + Vector3(0.0, 0.6, 0.0),
					c + Vector3(0.0, -2.0, 0.0), chassis.collision_mask, [chassis.get_rid()])
				ray.collide_with_areas = false
				# без этого луч, начавшийся ВНУТРИ concave-сетки (кузов уже под гранью), ничего
				# не отвечает, упор не срабатывает и машина уходит внутрь геометрии
				ray.hit_from_inside = true
				var hit := get_world_3d().direct_space_state.intersect_ray(ray)
				# Опора — только неподвижный рельеф и полотно: сбитый бачок или припаркованная
				# машина тоже дают горизонтальную грань, но приниматься на неё кузову нельзя —
				# упор выталкивает машину вверх, нормальная нагрузка колёс скачет, и продольная
				# скорость падает на 28 g за тик (замер speedway x=576: 56.4 → 51.9 м/с).
				# Бок стены лучу перпендикулярен, а её нижняя грань машиной не держится.
				if hit.is_empty(): continue
				if not (hit["collider"] is StaticBody3D): continue
				if absf((hit["normal"] as Vector3).y) < 0.5: continue
				worst = minf(worst, c.y - (hit["position"] as Vector3).y)
		if worst < INF:
			# Сколько нужно гашения, чтобы к моменту, когда низ кузова дойдёт до грани, от
			# падения осталась BUMP_SOFT: a = g + (vy² − soft²)/(2·остаток). Формула сама
			# выбирает момент включения (мягкое касание не трогает вовсе) и успевает погасить
			# падение с 12 м, чего запас «в метрах от земли» не делал: либо упор не успевал
			# и удар принимал коллайдер (11 g на посадке с 12 м), либо множитель при
			# скорости превращал его в парашют (спуск 10 м кончался касанием при 1 м/с).
			var a := GRAVITY + (v.y * v.y - BUMP_SOFT * BUMP_SOFT) / (2.0 * maxf(worst, BUMP_GAP))
			if a > GRAVITY:
				# пружина — только когда кузов УШЁЛ под грань, иначе она выталкивала бы
				# машину, стоящую на склоне или у борта
				var push := minf(a, BUMP_A) + BUMP_K * maxf(0.0, -worst)
				chassis.apply_central_impulse(Vector3.UP * params.mass * minf(push, 2.0 * BUMP_A) * dt)
	# Тормоз передней оси на ручнике. Отдавать его в колёсный brake — значит потерять его
	# ровно там, где жалобнее всего: с зажатым W на переднем колесе есть тяга, а Godot не
	# применяет brake при nonzero engine_force (vehicle_body_3d.cpp:
	# `if (m_engineForce != 0) rollingFriction = -engineForce*step`). Замер (окно 0.5 с):
	# накатом ручник тормозил на 0.86 g, а с газом — на 0.48 g, то есть «почти не тормозит».
	# Тот же тормоз, отданный ОТРИЦАТЕЛЬНОЙ тягой, тоже не годится: недобирал вдвое
	# (замер: 0.54 g накатом).
	# Поэтому доля передней оси идёт импульсом по телу: он складывается с импульсами
	# подвески (в отличие от записи скорости), направлен против горизонтального движения,
	# не трогает боковую составляющую (занос остаётся заносом) и выключается в воздухе и
	# ниже порога удержания, чтобы стоячая машина не поползла назад.
	if hand and _grounded and absf(vf) > HB_HOLD_MS:
		chassis.apply_central_impulse(-_flat_forward() * front_brake * signf(vf))
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
# покоя равна радиусу (замерено в h_susp_ground), поэтому минус радиус по Y — это поверхность.
func wheel_contact(i: int) -> Vector3:
	var w := _wheels[i]
	return w.global_position - Vector3(0.0, w.wheel_radius, 0.0)

# Удар — это гибель СКОРОСТИ КАК ТАКОВОЙ, а не смена её направления. Мерим полную
# величину вектора: на гребне трамплина машина теряет 12 км/ч по горизонтали, зато
# получает +13 м/с вверх (замер на 210 км/ч), то есть скорость просто повернула — и по
# полной величине там потери почти нет. Приземление с 13-метрового подъёма тоже стоит
# машине меньше 6 км/ч. Стена же или отбойник забирают скорость целиком, и поворот
# сюда уже не оправдание. Замер по прежнему горизонтальному признаку на 280 км/ч давал
# на трамплине 240 км/ч/с — то есть горка сама объявлялась ударом, ровно то, на что
# жалуется игрок. Меряем по окну
func _detect_impact(dt: float) -> void:
	var v := chassis.linear_velocity
	_hist.append(v)
	while _hist.size() > IMPACT_WINDOW + 1: _hist.pop_front()
	_impact_cooldown = maxf(_impact_cooldown - dt, 0.0)
	var fspeed := _speed(v)
	var old: Vector3 = _hist[0]
	var window := dt * float(_hist.size() - 1)
	var decel := 0.0 if window <= 0.0 else (_speed(old) - fspeed) / window
	if decel > IMPACT_DECEL and _recent_speed > IMPACT_MIN_KMH and _impact_cooldown <= 0.0:
		var dv := old - v
		if dv.length_squared() > 0.25:
			var n := dv.normalized()                 # куда ушёл импульс — туда и мнётся кузов
			var hx := absf(n.x) * params.length * 0.5 + absf(n.z) * params.width * 0.5
			var point := chassis.global_position + n * hx + Vector3(0, 0.1, 0)
			impact.emit(_recent_speed, point, -n)
			body.apply_impact(point, n, _recent_speed)
			_impact_cooldown = 1.0
	_recent_speed = maxf(_recent_speed - RECENT_DECAY * dt, fspeed)

func _speed(v: Vector3) -> float:
	return v.length() * 3.6

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
