class_name MapCircuit
extends RefCounted
# Замкнутое кольцо «ГОНКА» и лента «БЕСКОНЕЧНОСТЬ»: курсор по тайлам,
# обвес трассы и перестановка плит за спиной машины.

# ------------------------------------------------------------ замкнутое кольцо «ГОНКА»
# Трасса собирается Курсором по тайлам Kenney, а не расстановкой на глаз: у каждого
# тайла полоса идёт по местной +Z, поэтому якорь (куда встанет узел, куда денется полоса
# и как повернёт курсор) измерен по геометрии модели. Правые повороты чередуются
# 25/15/25/15 — при таком чередовании прямоугольник сходится при любых длинах
# противоположных прямых (условие замыкания: L1-L3 = R2+R3-R1-R4, L2-L4 = R3+R4-R1-R2),
# так что между плитами нет ни ступеньки, ни щели.
const TILE_ANCHOR := {
	"roadStraightLong": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadStartPositions": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadRampLong": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadStraight": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 10.0), "turn": 0, "len": 10.0},
	# у арки полоса шире тайла: её асфальт по местной X лежит 2.54..10.06, центр 6.3
	"roadStart": {"in": Vector2(6.3, 0.0), "out": Vector2(6.3, 20.0), "turn": 0, "len": 20.0},
	# бугор — 20 м по ходу, гребень 0.9 м: на трассе он сжат так же, как на других картах
	"roadBump": {"in": Vector2(5.0, 0.0), "out": Vector2(5.0, 20.0), "turn": 0, "len": 20.0},
	"roadCornerLarge": {"in": Vector2(5.0, 0.0), "out": Vector2(20.0, 15.0), "turn": 1, "len": 15.0},
	"roadCornerLarger": {"in": Vector2(5.0, 0.0), "out": Vector2(30.0, 25.0), "turn": 1, "len": 25.0},
}
# Курс в осях (x, z): куда едет машина. 0 = −Z, 1 = +X, 2 = +Z, 3 = −X.
const TRAV := {0: Vector2(0.0, -1.0), 1: Vector2(1.0, 0.0), 2: Vector2(0.0, 1.0), 3: Vector2(-1.0, 0.0)}
# Куда смотрит местная +X тайла (поперёк полосы) при том же курсе: у поворота входной
# край лежит по местной X, и без этого якоря стык с прямой расходился бы на полтайла.
const SIDE := {0: Vector2(-1.0, 0.0), 1: Vector2(0.0, -1.0), 2: Vector2(1.0, 0.0), 3: Vector2(0.0, 1.0)}
# Поворот узла, дающий этот курс: местная +Z должна смотреть на курс, отсюда 180-90h.
const ROT := {0: 180.0, 1: 90.0, 2: 0.0, 3: -90.0}

# AABB узла, который ещё не в дереве: global_transform вне дерева возвращает единичный,
# а отпечаток трассы нужен прямо во время сборки.
static func _track_debug() -> bool:
	return OS.get_environment("TRACKDEBUG") != ""

static func _placed_aabb(mi: MeshInstance3D) -> AABB:
	var a: AABB = mi.get_aabb()
	var sc: Vector3 = mi.scale
	return Transform3D(Basis(Vector3.UP, mi.rotation.y), mi.position) * AABB(a.position * sc, a.size * sc)

class TrackCursor:
	var root: Node3D
	var pos := Vector3.ZERO
	var h := 1
	var box := AABB()
	var line: Array[Vector3] = []      # ось полосы по точкам — по ней проверяется замыкание
	var spawn := Transform3D.IDENTITY
	var _tiles := 0

	func tile(name: String, solid := false, sc := Vector3.ONE) -> MeshInstance3D:
		var d: Dictionary = TILE_ANCHOR[name]
		var tr: Vector2 = TRAV[h]
		var sd: Vector2 = SIDE[h]
		var pin: Vector2 = d["in"]
		var outp: Vector2 = d["out"]
		var rot: float = ROT[h]
		# точка полосы -> мир: местная X идёт по SIDE, местная Z — по TRAV. Множитель
		# тайла обязан попасть и в шаг курсора: растянутая втрое рамка занимает 60 м, и
		# без этого кольцо не сходится (замер: расходился ровно на 90 м).
		var dx := (outp.x - pin.x) * sc.x
		var dz := (outp.y - pin.y) * sc.z
		var off := Vector3(sd.x * dx + tr.x * dz, 0.0, sd.y * dx + tr.y * dz)
		var node := pos - Vector3(sd.x * pin.x * sc.x + tr.x * pin.y * sc.z, 0.0,
			sd.y * pin.x * sc.x + tr.y * pin.y * sc.z)
		var mi: MeshInstance3D = MapKit.kit(root, name, node, rot, solid, true, sc)
		line.append(Vector3(pos.x, 0.0, pos.z))
		if MapCircuit._track_debug():
			print("  %s: узел (%.1f, %.1f) rot %.0f -> полоса (%.1f, %.1f), курс %d" % [
				name, node.x, node.z, rot, pos.x, pos.z, h])
		if mi != null:
			var g: AABB = MapCircuit._placed_aabb(mi)
			box = g if _tiles == 0 else box.merge(g)
			_tiles += 1
		pos += off
		if int(d["turn"]) == 1:
			h = (h + 1) % 4
		return mi

	func place(name: String, side_off: float, along: float, rot_extra: int, solid: bool) -> void:
		var tr: Vector2 = TRAV[h]
		var sd: Vector2 = SIDE[h]
		var node := pos + Vector3(tr.x * along + sd.x * side_off, 0.0, tr.y * along + sd.y * side_off)
		MapKit.kit(root, name, node, ROT[(h + rot_extra + 8) % 4], solid, false)

# 6 км плит в строю: лента уходит на 5.9 км вперёд от машины (за туман),
# чтобы горизонт читался бесконечным даже на 671 км/ч — 31 секунда дороги
# впереди. Перестановка хвоста не подорожала: двигаются те же ленты.
const SEGMENTS := 300

static func endless() -> Dictionary:
	# «БЕСКОНЕЧНОСТЬ» — дорога, которая не кончается: лента плит лежит на одном большом
	# полотнище, а по мере того, как машина уходит вперёд, MapDB.recycle() переносит
	# самые задние плиты и отбойники за спину в начало хвоста. Полотно не двигается,
	# ездок не чувствует шва, и трасса теоретически длиннее, чем сядет терпения.
	var root := Node3D.new(); root.name = "Endless"
	# Физический пол остаётся поверхностью езды (у плоских плит своих коллайдеров
	# нет — верх пола и есть полотно). А ВИЗУАЛ пола уходит на 6 см ниже: верх
	# коробки и асфальт плит разделяли два миллиметра, и на дистанции буфер
	# глубины их смыкал — асфальт мерцал полосами (жалоба: «мелькает, конфликтует
	# с чем-то»). Колёса вне полотна садутся на 6 см в траву — читается как рельеф.
	var floor_body := MapKit.box(root, Vector3(0, MapDefs.FLOOR_Y - 1.0, 0), Vector3(40000.0, 2.0, 240.0),
		Color(0.34, 0.37, 0.33), Basis.IDENTITY, true)
	floor_body.name = "endless_floor"
	for c in floor_body.get_children():
		if c is MeshInstance3D: (c as MeshInstance3D).position.y -= 0.06
	var t := TrackCursor.new()
	t.root = root
	t.pos = Vector3(-40.0, 0.0, 0.0)
	t.h = 1
	for k in SEGMENTS:
		var name := "roadStraightLong"
		match k % 9:
			3: name = "roadRampLong"
			6: name = "roadBump"
			7: name = "roadStartPositions"
		var sc := Vector3.ONE
		var solid := false
		if name == "roadRampLong":
			sc = Vector3(1.0, 1.0, 3.0)
			solid = true
		elif name == "roadBump":
			sc = Vector3(1.0, MapDefs.BUMP_Y, 1.0)
			solid = true
		t.tile(name, solid, sc)
	# отбойники вдоль всей ленты: они тоже уезжают вперёд вместе с плитами
	for side in [1, -1]:
		for k in int(SEGMENTS * 2.0):
			# узел плиты на «бесконечности» стоит на z = +5 (полоса по оси z = 0), поэтому
			# отбойники в тех же смещениях, что и на трассе: иначе один из них лежит на
			# асфальте и цепляется боком
			MapKit.kit(root, "barrierWall", Vector3(-40.0 + k * 10.0, 0, 4.9 if side > 0 else -6.13),
				0, true, false)
	# стартовое кольцо прожекторов и щит — чтобы первый взгляд был на трассу, а не в пустоту.
	# Щиты и прожекторы входят в ленты перестановки (свой шаг у каждого ряда), поэтому
	# декорация идёт вдоль всей ленты, а не заканчивается на первых сотнях метров —
	# иначе впереди, за туманом, обочина пустая, и карта выглядит непрогруженной.
	for k in 60:
		MapKit.kit(root, "lightRed", Vector3(-30.0 + k * 40.0, 0, 6.5), 0, true, false)
		MapKit.kit(root, "billboard", Vector3(10.0 + k * 60.0, 0, -17.0), 0, true, false)
	# сносимый хлам у обочин: предметам известно только плоское полотно, поэтому они
	# стоят на месте, а лента плит уходит вперёд — на «бесконечности» их сбивают один раз
	for k in 6:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(20.0 + k * 3.0, 0, 6.9), MapDefs.PROP, 0.0, 3.0)
	for k in 4:
		MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(120.0 + k * 3.0, 0, -6.9), MapDefs.PROP, 0.0, 10.0)
	MapProps.loose(root, MapDefs.P + "box.glb", Vector3(200.0, 0, 7.2), MapDefs.PROP, 1.1, 15.0)
	MapProps.loose(root, MapDefs.P + "debris-bumper.glb", Vector3(260.0, 0, -7.2), MapDefs.PROP, 0.8, 9.0)
	MapKit.drop_shadows(root)
	# спавн на середине плиты, а не на шве: лучи и колёса на стыке коллайдеров
	# ловили пол вместо полотна (h_map_props: «под спавном пол»)
	return {"root": root, "spawn": Transform3D(Basis.IDENTITY, Vector3(-18.0, 1.0, 0.0)),
		"bounds": AABB(Vector3(-200, -60, -120), Vector3(400000, 120, 240)),
		"info": {"colliders": root.get_child_count(), "has_ramp": true, "endless": true}}

# Переставка плит «бесконечности»: то, что осталось за спиной, уезжает за голову
# своей же ленты. Шаг — фактическая длина головы, а не «число плит × 20»: растянутая
# втрое рампа занимает 60 м, и номинальный шаг на реальной длине ленты складывал
# плиты в одну кучу и оставлял твёрдые плиты без коллайдеров (проверено: 12 пар
# плит внахлёст и 6 из 20 гор/бугров без тела на трёх оборотах).
# Кэш строк recycle: перескан всех детей и сортировка трёх лент стоили ~2 мс на
# каждый вызов, даже когда нечего переставлять, — на слабом GPU это периодический
# hitch раз в полсекунды. Ленты живут между вызовами (за игру детей у корня никто
# не добавляет и не удаляет) и пересобираются только при смене корня, изменении
# числа детей или протухшей ссылке.
static var _rc_root: Node3D = null
static var _rc_count := -1
static var rc_lines: Array = []

# Пол «бесконечности» следует за машиной квантами 2 км: без этого травяное
# полотно заканчивалось на 20-м километре, и съехавший с дороги игрок видел
# пустоту и край ленты, висящей над ним (issue #5). Трипланарный шум текстуры
# лежит в мировых координатах — сдвиг коробки не «плавит» рисунок.
static func floor_follow(root: Node3D, car_x: float) -> void:
	var body := root.get_node_or_null("endless_floor") as StaticBody3D
	if body == null: return
	var want := roundf(car_x / 2000.0) * 2000.0
	var dx := want - body.position.x
	if absf(dx) < 0.5: return
	body.position.x += dx

static func recycle(root: Node3D, car_x: float, spacing: float) -> int:
	if not rc_lines_fresh(root):
		_rc_rebuild_lines(root)
	var moved := 0
	for line in rc_lines:
		moved += _rc_roll(line, car_x, spacing, root)
	return moved

static func rc_lines_fresh(root: Node3D) -> bool:
	if root != _rc_root or root.get_child_count() != _rc_count:
		return false
	for line in rc_lines:
		var nodes: Array = line[0]
		if not is_instance_valid(nodes[0]) or not is_instance_valid(nodes[nodes.size() - 1]):
			return false
	return true

static func _rc_rebuild_lines(root: Node3D) -> void:
	# полотно и каждый ряд обочины — своя линия: у барьеров два ряда по разные
	# стороны полосы, у щитов и прожекторов свой шаг раскладки (60 и 40 м), и общая
	# «голова» оставляла в них дыры. Каждая лента несёт свой шаг: 0 — шаг берётся
	# по узлу (плиты: рампа, растянутая втрое, занимает 60 м), число — фиксированный
	# шаг ряда, каким он и раскладывался при постройке карты.
	var fixed_advance := {"kit_road": 0.0, "kit_barrier": 10.0, "kit_billboard": 60.0, "kit_light": 40.0}
	var groups := {}
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var nm := String(mi.name)
		var cls := ""
		for kind in fixed_advance:
			if nm.begins_with(kind): cls = kind; break
		if cls == "": continue
		var gkey := cls + "|%.0f" % mi.position.z
		if not groups.has(gkey): groups[gkey] = {"nodes": [], "adv": float(fixed_advance[cls])}
		(groups[gkey]["nodes"] as Array).append(mi)
	rc_lines = []
	for gkey in groups:
		var line: Array = groups[gkey]["nodes"]
		if line.size() < 2: continue
		line.sort_custom(func(a: Node, b: Node) -> bool: return a.position.x < b.position.x)
		rc_lines.append([line, groups[gkey]["adv"]])
	_rc_root = root
	_rc_count = root.get_child_count()

# Прокрутка одной ленты: хвост уходит за голову, пока полностью не останется
# за спиной машины; обратно — если машина телепортировалась в начало трассы.
static func _rc_roll(line: Array, car_x: float, spacing: float, root: Node3D) -> int:
	var nodes: Array = line[0]
	var fixed: float = line[1]
	var moved := 0
	var guard := nodes.size()
	while guard > 0:
		guard -= 1
		var tail: Node3D = nodes[0]
		var head: Node3D = nodes[nodes.size() - 1]
		# плита едет в хвост, только когда полностью осталась за машиной; шаг
		# впереди берётся по классу ленты: у плит — по фактической длине тайла,
		# у рядов обочины — их фиксированный шаг раскладки
		var adv_tail := fixed if fixed > 0.0 else _advance_of(tail)
		if tail.position.x + adv_tail + spacing >= car_x - 120.0: break
		var adv_head := fixed if fixed > 0.0 else _advance_of(head)
		_shift(tail, head.position.x + adv_head - tail.position.x, root)
		nodes.pop_front()
		nodes.append(tail)
		moved += 1
	# телепорт назад (вылет за карту, R на старте) оставляет ленту впереди:
	# голова переезжает перед хвостом, пока полотно не дотянется до машины
	guard = nodes.size()
	while guard > 0:
		guard -= 1
		var tail2: Node3D = nodes[0]
		if tail2.position.x <= car_x - spacing: break
		var head2: Node3D = nodes.pop_back()
		var adv_h2 := fixed if fixed > 0.0 else _advance_of(head2)
		_shift(head2, tail2.position.x - adv_h2 - head2.position.x, root)
		nodes.insert(0, head2)
		moved += 1
	return moved

# Узел и его тело-коллайдер едут на один и тот же шаг: раздельные перестановки
# давали горку без коллайдера.
static func _shift(mi: Node3D, dx: float, root: Node3D) -> void:
	mi.position.x += dx
	var body := root.get_node_or_null(NodePath("col_" + mi.name))
	if body != null: body.position.x += dx

# Длина тайла вдоль ленты: якорный сдвиг полосы, умноженный на растяжение по местной Z.
# Отбойников в таблице якорей нет — они стоят в 10-метровом шаге раскладки.
static func _advance_of(mi: MeshInstance3D) -> float:
	var tile := String(mi.name).trim_prefix("kit_").split("_")[0]
	if not TILE_ANCHOR.has(tile): return 10.0
	var d: Dictionary = TILE_ANCHOR[tile]
	return (float(d["out"].y) - float(d["in"].y)) * mi.scale.z

static func circuit() -> Dictionary:
	var root := Node3D.new(); root.name = "Circuit"
	var t := TrackCursor.new()
	t.root = root
	t.pos = Vector3(-140.0, 0.0, -60.0)
	t.h = 1
	# Нижняя прямая — 280 м: арка, места старта, разгон и длинный трамплин с посадочной
	# плитой. Трамплин взят растянутым (×3): 5.2 м высоты на 60 м — это 5°, и прыжок
	# остаётся прыжком даже на 300 км/ч, а не ударом носом в грань (замер на арена-рампе:
	# 15° машина начинала складываться с 250 км/ч).
	t.tile("roadStart", true)
	for k in 3:
		t.tile("roadStraightLong")
	t.tile("roadStartPositions")
	for k in 3:
		t.tile("roadStraightLong")
	t.tile("roadRampLong", true, Vector3(1.0, 1.0, 3.0))
	t.tile("roadStraight", false, Vector3(1.0, 1.0, 6.0))
	# Развороты чередуются 25/15/25/15 и противоположные прямые равны (280 и 280,
	# 120 и 120) — при таком чередовании кольцо сходится точно, без ступеньки на стыке.
	t.tile("roadCornerLarger")
	for k in 6:
		t.tile("roadStraightLong")
	t.tile("roadCornerLarge")
	# старт — за аркой на нижней прямой, курсом вдоль неё
	t.spawn = Transform3D(Basis(Vector3.UP, 0.0), Vector3(-118.0, 1.0, -60.0))
	for k in 13:
		t.tile("roadStraightLong")
	t.tile("roadBump", true, Vector3(1.0, MapDefs.BUMP_Y, 1.0))
	t.tile("roadCornerLarger")
	for k in 6:
		t.tile("roadStraightLong")
	t.tile("roadCornerLarge")
	var f: AABB = t.box
	# зрительский пояс: внешние отбойники по периметру асфальта, внутренние — по краю
	# инфилда, трибуны и боксы на прямой, мачты, тенты, флаги и деревья за пределами.
	# прямоугольник ОСЕЙ четырёх прямых (не отпечаток тайлов: углы выступают за полосу на
	# радиус разворота). Внутренний пояс отставляется от оси на 8 м — на 3 м за кромку
	# асфальта, иначе отбойник лежит на полосе и машина бьётся о него на горке.
	_decorate(root, f, AABB(Vector3(-125.0, 0.0, -60.0), Vector3(290.0, 0.0, 110.0)))
	if OS.get_environment("TRACKDEBUG") != "":
		var a0: Vector3 = t.line[0]
		var a1: Vector3 = t.pos
		print("незамыкание: (%.2f, %.2f) при курсе %d (старт был курс 1)" % [
			a1.x - a0.x, a1.z - a0.z, t.h])
		print("кольцо: отпечаток x=%.1f..%.1f z=%.1f..%.1f y=%.2f..%.2f тайлов %d" % [
			f.position.x, f.end.x, f.position.z, f.end.z, f.position.y, f.end.y, t._tiles])
	var floor_y := -0.4
	MapKit.box(root, Vector3((f.position.x + f.end.x) * 0.5, floor_y, (f.position.z + f.end.z) * 0.5),
		Vector3(f.size.x + 90.0, 0.8, f.size.z + 90.0), Color(0.42, 0.46, 0.4), Basis.IDENTITY, true)
	return {"root": root, "spawn": t.spawn,
		"bounds": AABB(f.position - Vector3(40, 40, 40), f.size + Vector3(80, 100, 80)),
		# closure — незамыкание в метрах, line — ось полосы: по ним h_newmaps проверяет кольцо
		"info": {"colliders": root.get_child_count(), "has_ramp": true,
			"closure": t.pos.distance_to(t.line[0]), "line": t.line}}

# Мелкий пояс (отбойники, газоны, мачты, щиты, тенты) теней не бросает: на новых картах
# таких узлов сотни, и каждый стоил места в проходе теней — живьём кадр на кольце вышел
# 35 мс против 10 мс на трассе. Тень от отбойника высотой 0.7 м на картинке не видна.
const NO_SHADOW_PREFIX := ["barrier", "grass", "light", "billboard", "tent", "fence",
	"flag", "rail", "pylon", "road"]

static func drop_shadows(root: Node3D) -> void:
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: continue
		var stem := String(mi.name).trim_prefix("kit_")
		for pre in NO_SHADOW_PREFIX:
			if stem.begins_with(pre):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break

# Обвес кольца. Координаты — по отпечатку трассы: внешний пояс в 6 м от асфальта,
# внутренний — вдоль инфилда, всё остальное за пределами полосы, чтобы не стоять под
# колёсами (на арена-рампе именно отбойники в коридоре приземления давали «удар на рампе»).
static func _decorate(root: Node3D, f: AABB, infill: AABB) -> void:
	var out_x0 := f.position.x - 6.0
	var out_x1 := f.end.x + 6.0
	var out_z0 := f.position.z - 6.0
	var out_z1 := f.end.z + 6.0
	for k in int((out_x1 - out_x0) / 10.0) + 1:
		MapKit.kit(root, "barrierWall", Vector3(out_x0 + k * 10.0, 0, out_z0), 0, true, false)
		MapKit.kit(root, "barrierWall", Vector3(out_x0 + k * 10.0, 0, out_z1), 0, true, false)
	for k in int((out_z1 - out_z0) / 10.0) + 1:
		MapKit.kit(root, "barrierWall", Vector3(out_x0, 0, out_z0 + k * 10.0), 90, true, false)
		MapKit.kit(root, "barrierWall", Vector3(out_x1, 0, out_z0 + k * 10.0), 90, true, false)
	# инфилд: внутренний ряд отбойников и слалом из пилонов — между ними можно
	# остановиться и осмотреть кузов, на полосу они не выходят
	var in_x0 := infill.position.x + 8.0
	var in_x1 := infill.end.x - 8.0
	var in_z0 := infill.position.z + 8.0
	var in_z1 := infill.end.z - 8.0
	for k in int((in_x1 - in_x0) / 10.0) + 1:
		MapKit.kit(root, "barrierWhite", Vector3(in_x0 + k * 10.0, 0, in_z0), 0, true, false)
		MapKit.kit(root, "barrierWhite", Vector3(in_x0 + k * 10.0, 0, in_z1), 0, true, false)
	for k in 8:
		MapProps.loose_kit(root, "pylon", Vector3(in_x0 + 10.0 + k * 12.0, 0, (in_z0 + in_z1) * 0.5
			+ 6.0 * (1.0 if k % 2 == 0 else -1.0)), 0, 6.0)
	# трибуны, боксы и щиты за нижней прямой
	for k in 3:
		MapKit.kit(root, "grandStandCovered", Vector3(-90.0 + k * 26.0, 0, out_z0 - 8.0), 0, true, false)
	MapKit.kit(root, "pitsOffice", Vector3(30.0, 0, out_z0 - 8.0), 0, true, false)
	for k in 4:
		MapKit.kit(root, "billboard", Vector3(out_x0 + 20.0 + k * 40.0, 0, out_z1 + 8.0), 0, true, false)
	# мачты освещения вдоль обеих прямых и радара у финиша
	for k in 6:
		MapKit.kit(root, "lightRedDouble", Vector3(-120.0 + k * 50.0, 0, out_z0 - 3.0), 0, true, false)
		MapKit.kit(root, "lightRed", Vector3(-120.0 + k * 50.0, 0, out_z1 + 3.0), 180, true, false)
	MapKit.kit(root, "radarEquipment", Vector3(out_x0 + 8.0, 0, in_z0 + 8.0), 0, true, false)
	# арка над стартом — без коллайдера: под ней проезжают, и луч тесту она
	# перекрывает полосу (стойки roadStart твёрдые, этот навес — декорация)
	MapKit.kit(root, "overheadRound", Vector3(-132.0, 0, -55.0), 90, false, false)
	for k in 4:
		MapKit.kit(root, "tentLong", Vector3(in_x0 + 6.0 + k * 26.0, 0, in_z1 - 6.0), 0, true, false)
	# деревья и газон за внешним поясом: силуэт полигона, а не препятствие
	for k in 12:
		var gx := out_x0 - 14.0 + k * 28.0
		MapKit.kit(root, "grass", Vector3(gx, 0.02, out_z0 - 14.0), 90, false, false)
		MapKit.kit(root, "treeLarge", Vector3(gx + 8.0, 0, out_z1 + 16.0), 0, true, false)
	for k in 5:
		MapProps.loose(root, MapDefs.P + "cone.glb", Vector3(-60.0 + k * 4.0, 0, in_z0 + 4.0), MapDefs.PROP, 0.0, 3.0)
	for k in 3:
		MapProps.loose(root, MapDefs.P + "debris-tire.glb", Vector3(60.0 + k * 3.0, 0, in_z1 - 4.0), MapDefs.PROP, 0.0, 10.0)
	Materials.apply_tree(root, "prop")
