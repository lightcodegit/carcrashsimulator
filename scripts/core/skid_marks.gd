class_name SkidMarks
extends MultiMeshInstance3D
# Следы резины на асфальте: заблокированное ручником колесо или сильный боковой увод
# чертят полосу там, где колесо действительно скользит.
#
# Один MultiMesh на всё кольцо — это один draw call. Полосы стареют и исчезают: у
# слотов есть время рождения, а курсор снятия идёт вдоль кольца, где времена упорядочены,
# — то есть за O(1) на тик, без сканирования 2048 записей. Отдельный квад на пятно был
# бы сотнями draw call'ов.

const SLOTS := 2048
const WIDTH := 0.17          # ширина пятна контакта
const LIFT := 0.012          # над полотном: иначе z-fighting с дорогой
const MIN_SKID := 0.12
const MIN_LEN := 0.05        # короче — колесо стоит, тянуть пятно нечего
const MAX_LEN := 1.4         # длиннее — это телепорт (респавн или прыжок), след рвём
const BLACK := Color(0.03, 0.03, 0.035)
const GREY := Color(0.30, 0.30, 0.31)

var _car: CarRig
var _next := 0
var _drawn := 0
var _last: Array[Vector3] = []
var _live: Array[bool] = []
# Серверный буфер MultiMesh не читается обратно в headless-режиме: get_instance_transform
# отдаёт единичную матрицу. Держим кольцо и на стороне скрипта — это же состояние нужно
# тестам, чтобы проверять геометрию следа без живого рендера.
var _ring: Array[Transform3D] = []
# Время рождения каждого слота в секундах игрового времени (INF — слот пуст). Кольцо
# пишется по порядку, поэтому снятие — один ход курсора, а не обход 2048 записей.
# После полного оборота кольца курсор может догнать свежий слот раньше старых: такая
# полоса поживёт вдвое дольше срока, но исчезнет в любом случае.
var _born: PackedFloat64Array = PackedFloat64Array()
var _exp := 0
var _t := 0.0

func setup(car: CarRig) -> void:
	_car = car
	_last.resize(car.wheel_count())
	_live.resize(car.wheel_count())
	_live.fill(false)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _patch()
	multimesh.instance_count = SLOTS
	_ring.resize(SLOTS)
	# пустые слоты должны быть невидимы: нулевой масштаб вместо единичного квада в начале координат
	for i in SLOTS:
		_ring[i] = _hidden()
		multimesh.set_instance_transform(i, _ring[i])
		multimesh.set_instance_color(i, BLACK)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _rubber()
	# без своей AABB MultiMesh отбрасывался бы как «вне камеры»: кольцо живёт по всему миру
	multimesh.custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 100, 4000))
	_born.resize(SLOTS)
	_born.fill(INF)

# CarRig стоит в дереве раньше, поэтому к своему тиковому вызову скольжение уже посчитано.
func _physics_process(dt: float) -> void:
	if _car == null or _car.chassis == null: return
	# Пауза и реплей замирают мир: и возраст следа тоже — иначе полосы старели
	# под стоящей машиной и выцветали, пока игрок смотрит повтор.
	if get_tree().paused: return
	_t += dt
	_expire()
	var levels := _car.skid_levels()
	for i in levels.size():
		# CarRig обнуляет скольжение колеса, которое не касается земли, — в воздухе следов нет
		if levels[i] < MIN_SKID:
			_live[i] = false
			continue
		var p := _car.wheel_contact(i)
		if not _live[i]:
			_live[i] = true
			_last[i] = p
			continue
		var d := p - _last[i]
		d.y = 0.0
		var len := d.length()
		if len > MAX_LEN:
			_last[i] = p              # разрыв: новый след начнётся со следующего тика
		elif len >= MIN_LEN:
			_put(_last[i] + d * 0.5, d / len, len, levels[i])
			_last[i] = p

# На респавне старые полосы остаются на асфальте (они часть мира), но текущий след
# обрывается: иначе машина прочертит полосу от места аварии до точки старта.
func respawn() -> void:
	_live.fill(false)

# Срок годности следа. life = 0 значит «не исчезает»: полоса уходит только когда её
# перезапишет кольцо.
func expire_after() -> float:
	return Settings.skid_life if Settings != null else 30.0

func _expire() -> void:
	var life := expire_after()
	if life <= 0.0: return
	# курсор не должен обогнать запись: пустой слот с INF всё равно не «протух»
	while _born[_exp] != INF and _born[_exp] + life <= _t:
		_ring[_exp] = _hidden()
		multimesh.set_instance_transform(_exp, _ring[_exp])
		_born[_exp] = INF
		_exp = (_exp + 1) % SLOTS

# Сколько полос ещё живы (не скрыто сроком годности).
func marks_live() -> int:
	var n := 0
	for i in SLOTS:
		if _born[i] != INF: n += 1
	return n

func marks_drawn() -> int:
	return _drawn

func segment(i: int) -> Transform3D:
	return _ring[i]

func _put(center: Vector3, dir: Vector3, len: float, strength: float) -> void:
	var side := Vector3.UP.cross(dir).normalized()
	# оси задаём явно: Basis.scaled() умножает слева и на повёрнутом базисе перемешал бы
	# ширину с длиной. Длина с запасом на ширину — соседние сегменты перекрываются,
	# и полоса не рвётся.
	var b := Basis(side * WIDTH, Vector3.UP, dir * (len + WIDTH))
	_ring[_next] = Transform3D(b, center + Vector3(0.0, LIFT, 0.0))
	multimesh.set_instance_transform(_next, _ring[_next])
	# сила скольжения даёт насыщенность: лёгкий увод — серая полоса, блокировка — чёрная
	multimesh.set_instance_color(_next, BLACK.lerp(GREY, 1.0 - strength))
	_born[_next] = _t
	_next = (_next + 1) % SLOTS
	_drawn += 1

static func _hidden() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

static func _patch() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [
		Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5),
		Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5),
	]
	for v in q:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()

static func _rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.62          # свежая резина слегка лоснится, в отличие от матового асфальта
	m.metallic_specular = 0.4
	m.render_priority = 1
	return m
