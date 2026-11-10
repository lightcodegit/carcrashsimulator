class_name MapProps
extends RefCounted
# Пропы и городская мебель: модели из ассетов, сбиваемые предметы,
# скамейки, урны, кашпо, знаки и фонтан — всё, что ставится на поверхность.

# Имя с координатами: "." и ":" Godot в именах узлов молча заменяет, а одинаковые имена
# среди соседей переименовывает в @Node3D@N, поэтому без координат пропы ненаходимы.
static func _prop_name(path: String, pos: Vector3) -> String:
	return "%s_%d_%d" % [path.get_file().get_basename().replace("-", "_"), int(pos.x), int(pos.z)]

static func _aabb_in(n: Node3D) -> AABB:
	var merged := AABB(); var first := true
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var g: AABB = mi.transform * mi.get_aabb()
		if first: merged = g; first = false
		else: merged = merged.merge(g)
	return merged

# Модель из ассетов. solid => отдельный StaticBody3D по мировому AABB (без масштабирования формы).
static func prop(root: Node3D, path: String, pos: Vector3, sc: float, rot_y: float, solid: bool) -> Node3D:
	pos.y = _sit(pos.y, pos.x, pos.z)
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("MapDB: ассет не найден " + path)
		return null
	var n: Node3D = ps.instantiate()
	n.name = _prop_name(path, pos)
	var local := _aabb_in(n)
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * sc
	# сажаем низ модели на pos.y: у зданий/конусов начало координат в основании,
	# а у колёс и покрышек — в центре оси, поэтому без правки они левитируют или тонут
	n.position = Vector3(pos.x, pos.y - local.position.y * sc, pos.z)
	if path.begins_with(MapDefs.CARS):
		Materials.apply_tree(n, "car")
		n.add_to_group(MapDefs.GROUP_PARKED)
	root.add_child(n)
	if solid:
		var w: AABB = n.transform * local
		if w.size.length() > 0.05:
			var body := StaticBody3D.new()
			body.position = w.get_center()
			var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
			sh.size = w.size; cs.shape = sh; body.add_child(cs)
			var pm := PhysicsMaterial.new(); pm.friction = 0.0; body.physics_material_override = pm
			root.add_child(body)
	return n

# Лёгкий предмет, который можно снести: визуал живёт внутри RigidBody3D, коллайдер —
# коробка по его габариту. Массу задаём явно: от неё зависит и разлёт предмета, и то,
# насколько машина замедлится. Здания, отбойники трассы, фонари и деревья остаются
# статичными — их сносом не снести, а физика на них тратиться не должна.
static func loose(root: Node3D, path: String, pos: Vector3, sc: float, rot_y: float, mass_kg: float) -> Node3D:
	pos.y = _sit(pos.y, pos.x, pos.z)
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("MapDB: ассет не найден " + path)
		return null
	var n: Node3D = ps.instantiate()
	n.name = _prop_name(path, pos)
	var local := _aabb_in(n)
	n.scale = Vector3.ONE * sc
	# центр по X/Z и низ на y = 0 тела: у конусов основание в нуле, у покрышек — центр оси
	n.position = Vector3(-local.get_center().x * sc, -local.position.y * sc, -local.get_center().z * sc)
	return _wrap_loose(root, n, local, pos, rot_y, mass_kg)

# То же самое для сегмента Kenney Racing Kit (пилоны, пластиковые отбойники).
static func loose_kit(root: Node3D, name: String, pos: Vector3, rot_y_deg: float, mass_kg: float) -> Node3D:
	pos.y = _sit(pos.y, pos.x, pos.z)
	var m: Mesh = load(MapDefs.R + name + ".obj")
	if m == null:
		push_warning("MapDB: сегмент не найден " + name)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "loose_" + name
	var local := m.get_aabb()
	mi.position = Vector3(-local.get_center().x, -local.position.y, -local.get_center().z)
	return _wrap_loose(root, mi, local, pos, deg_to_rad(rot_y_deg), mass_kg)

# «Ноль» в раскладке карт означает «стою на поверхности под этой точкой», а не «в
# плоскости y=0». Высоту, которую вызывающий выбрал сам (тротуар — WALK_Y), не трогаем.
static func _sit(y: float, x: float, z: float) -> float:
	return y if y > 0.005 else MapKit.surface_y(x, z)

static func _wrap_loose(root: Node3D, visual: Node3D, local: AABB, pos: Vector3, rot_y: float,
		mass_kg: float, tumble := true) -> RigidBody3D:
	var body := LooseProp.new()
	body.mass = mass_kg
	body.continuous_cd = true     # иначе на 200 км/ч конус пролетает сквозь машину
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0             # на скользком предмет уезжает, не успев перевернуться
	pm.bounce = clampf(6.0 / mass_kg, 0.08, 0.20)    # лёгкое отскакивает сильнее, тяжёлое почти не прыгает
	# Дороги и пол заведомо с нулевым трением: машина не должна терять скорость от
	# любого касания (отдельная просьба игрока), а Bullet перемножает трение пары —
	# 1.0 предмета о 0.0 пола даёт те же нули. Без гашения сбитый конус уезжал и не
	# останавливался никогда. Режим REPLACE, потому что в проекте default_linear_damp
	# стоит в 0, а ADD прибавлял бы ноль к значению материала, а не к нашему.
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 1.6
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 2.4
	body.physics_material_override = pm
	body.rotation.y = rot_y
	body.position = pos
	body.add_child(visual)
	var w: AABB = visual.transform * local
	if w.size.length() > 0.05:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = w.size
		cs.shape = sh
		cs.position = w.get_center()
		body.add_child(cs)
		body.height_m = w.size.y
	if tumble: body.setup_tumble()
	root.add_child(body)
	return body

static func street_lamp(root: Node3D, pos: Vector3, side: float) -> void:
	MapKit.box(root, pos + Vector3(0, 3.0, 0), Vector3(0.22, 6.0, 0.22), Color(0.18, 0.18, 0.2))
	MapKit.box_vis(root, pos + Vector3(side * 0.9, 5.9, 0), Vector3(1.8, 0.16, 0.3), Color(0.22, 0.22, 0.24))
	var head := MapKit.box_vis(root, pos + Vector3(side * 1.6, 5.72, 0), Vector3(0.62, 0.18, 0.34), Color(1.0, 0.93, 0.72))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.93, 0.72)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.65)
	m.emission_energy_multiplier = 1.6
	head.material_override = m

# ---- городская мелочь -----------------------------------------------------
# В Kenney-наборе нет скамеек, урн, столов и фонтанов, а без них город читается
# макетом: поэтому эти предметы собраны из тех же процедурных ящиков, что пол и
# бордюры, в той же плоской палитре. Твёрдыми делаем то, о что складывается кузов
# (сиденье, спинка, чаша фонтана), ножки и крышки — только видимость.

# Мелочь (скамейки, урны, столы) тень не бросает: на Compatibility каждый caster
# удваивается в проходе теней, а город после обвески держал 50 FPS вместо 60 — с
# выключенными тенями мелочи вернулся к 60. Предметы выше метра тень сохраняют.
static func bench(root: Node3D, x: float, z: float, rot_deg: float) -> void:
	var y := MapKit.surface_y(x, z)
	var b := Basis(Vector3.UP, deg_to_rad(rot_deg))
	var seat := MapKit.box(root, Vector3(x, y + 0.45, z), Vector3(1.8, 0.08, 0.55), MapDefs.WOOD_COL, b, true)
	var back := MapKit.box(root, Vector3(x, y + 0.75, z) + b * Vector3(0, 0, -0.24),
		Vector3(1.8, 0.5, 0.07), MapDefs.WOOD_COL, b, true)
	MapKit.far(seat, 220.0)
	MapKit.far(back, 220.0)
	for s in [-0.7, 0.7]:
		var leg := MapKit.box_vis(root, Vector3(x, y + 0.22, z) + b * Vector3(s, 0, 0),
			Vector3(0.09, 0.44, 0.5), MapDefs.METAL_COL, b)
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MapKit.far(leg, 220.0)

static func bin(root: Node3D, x: float, z: float) -> void:
	var y := MapKit.surface_y(x, z)
	var body := MapKit.box(root, Vector3(x, y + 0.42, z), Vector3(0.55, 0.84, 0.55), MapDefs.METAL_COL,
		Basis.IDENTITY, true)
	var lid := MapKit.box_vis(root, Vector3(x, y + 0.87, z), Vector3(0.66, 0.06, 0.66), MapDefs.STONE_COL)
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MapKit.far(body, 220.0)
	MapKit.far(lid, 220.0)

static func picnic(root: Node3D, x: float, z: float, rot_deg: float) -> void:
	var y := MapKit.surface_y(x, z)
	var b := Basis(Vector3.UP, deg_to_rad(rot_deg))
	var top := MapKit.box(root, Vector3(x, y + 0.72, z), Vector3(1.7, 0.08, 0.95), MapDefs.WOOD_COL, b, true)
	MapKit.far(top, 220.0)
	for s in [-0.62, 0.62]:
		var seat := MapKit.box(root, Vector3(x, y + 0.42, z) + b * Vector3(0, 0, s),
			Vector3(1.7, 0.07, 0.3), MapDefs.WOOD_COL, b, true)
		MapKit.far(seat, 220.0)
	for s in [-0.6, 0.6]:
		var leg := MapKit.box_vis(root, Vector3(x, y + 0.36, z) + b * Vector3(s, 0, 0),
			Vector3(0.1, 0.72, 0.9), MapDefs.METAL_COL, b)
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MapKit.far(leg, 220.0)

# Сбиваемый предмет из процедурных ящиков: сборка становится ОДНИМ RigidBody с
# коробкой по общему габариту. Россыпью куски летали бы по-разному и цепляли машину
# насквозь, а единое тело улетает как предмет: ударил — унесло.
static func knock(root: Node3D, visual: Node3D, pos: Vector3, rot_deg: float, mass: float) -> RigidBody3D:
	var local := AABB()
	var first := true
	for c in visual.get_children():
		var mi := c as MeshInstance3D
		if mi == null: continue
		var g: AABB = mi.transform * mi.get_aabb()
		local = g if first else local.merge(g)
		first = false
	# Тень у летящей мелочи не нужна: двести урн и кашпо в проходе теней стоили
	# городу больше тысячи лишних отрисовок, а след от них виден только вблизи.
	MapKit.no_shadow(visual)
	# Непрерывный CD оставлен включённым намеренно: без него удар на 223 км/ч
	# разрешается неполно — машина теряет 23 км/ч, а урна проходит всего 0.8 м
	# вместо десятков (замер p_fast). Цена — время шага физики, поэтому экономим
	# НЕ отключением CD, а плотностью расстановки.
	return _wrap_loose(root, visual, local, pos, deg_to_rad(rot_deg), mass)

static func knock_bin(root: Node3D, x: float, z: float, rot_deg: float) -> RigidBody3D:
	var v := Node3D.new()
	MapKit.box_vis(v, Vector3(0, 0.42, 0), Vector3(0.55, 0.84, 0.55), MapDefs.METAL_COL)
	MapKit.box_vis(v, Vector3(0, 0.87, 0), Vector3(0.66, 0.06, 0.66), MapDefs.STONE_COL)
	return knock(root, v, Vector3(x, MapKit.surface_y(x, z), z), rot_deg, 25.0)

static func knock_planter(root: Node3D, x: float, z: float, rot_deg: float) -> RigidBody3D:
	var v := Node3D.new()
	MapKit.box_vis(v, Vector3(0, 0.24, 0), Vector3(0.9, 0.48, 0.9), MapDefs.STONE_COL)
	MapKit.box_vis(v, Vector3(0, 0.56, 0), Vector3(0.78, 0.2, 0.78), Color(0.30, 0.46, 0.28))
	return knock(root, v, Vector3(x, MapKit.surface_y(x, z), z), rot_deg, 40.0)

static func knock_bench(root: Node3D, x: float, z: float, rot_deg: float) -> RigidBody3D:
	var v := Node3D.new()
	# Части собираются без поворота: вращение даёт сам корпус (knock передаёт rot_deg
	# в body.rotation.y). Сместить части поворотом, не повернув их сами, — спинка и
	# ножки разъезжаются от доски, а общий габарит раздувается в коробку-«бублик».
	MapKit.box_vis(v, Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.55), MapDefs.WOOD_COL)
	MapKit.box_vis(v, Vector3(0, 0.75, -0.24), Vector3(1.8, 0.5, 0.07), MapDefs.WOOD_COL)
	for sg in [-0.7, 0.7]:
		MapKit.box_vis(v, Vector3(sg, 0.22, 0), Vector3(0.09, 0.44, 0.5), MapDefs.METAL_COL)
	return knock(root, v, Vector3(x, MapKit.surface_y(x, z), z), rot_deg, 45.0)

# Дорожный знак на ножке: лёгкий, но высокий — от удара встаёт на ребро и падает.
static func knock_sign(root: Node3D, x: float, z: float, rot_deg: float) -> RigidBody3D:
	var v := Node3D.new()
	MapKit.box_vis(v, Vector3(0, 1.1, 0), Vector3(0.09, 2.2, 0.09), MapDefs.METAL_COL)
	MapKit.box_vis(v, Vector3(0, 2.35, 0), Vector3(0.86, 0.86, 0.07), Color(0.80, 0.20, 0.16))
	return knock(root, v, Vector3(x, MapKit.surface_y(x, z), z), rot_deg, 18.0)

static func knock_hydrant(root: Node3D, x: float, z: float, rot_deg: float) -> RigidBody3D:
	var v := Node3D.new()
	MapKit.box_vis(v, Vector3(0, 0.34, 0), Vector3(0.34, 0.68, 0.34), Color(0.72, 0.16, 0.14))
	MapKit.box_vis(v, Vector3(0, 0.74, 0), Vector3(0.46, 0.12, 0.46), Color(0.55, 0.12, 0.11))
	MapKit.box_vis(v, Vector3(0, 0.42, 0), Vector3(0.62, 0.12, 0.12), Color(0.55, 0.12, 0.11))
	return knock(root, v, Vector3(x, MapKit.surface_y(x, z), z), rot_deg, 35.0)

# Фонтан: чаша из восьми гранитных граней по кругу, зеркало воды и колонна.
static func fountain(root: Node3D, x: float, z: float) -> void:
	var y := MapKit.surface_y(x, z)
	for k in 8:
		var a := k * TAU / 8.0
		var rim := MapKit.box(root, Vector3(x + cos(a) * 3.0, y + 0.3, z + sin(a) * 3.0),
			Vector3(2.6, 0.6, 0.55), MapDefs.STONE_COL, Basis(Vector3.UP, -a), true)
		MapKit.far(rim, 280.0)
	var water := MapKit.box_vis(root, Vector3(x, y + 0.12, z), Vector3(5.4, 0.1, 5.4), MapDefs.WATER_COL)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MapKit.far(water, 280.0)
	var col := MapKit.box(root, Vector3(x, y + 1.0, z), Vector3(0.7, 2.0, 0.7), MapDefs.STONE_COL,
		Basis.IDENTITY, true)
	MapKit.far(col, 280.0)

static func planter(root: Node3D, pos: Vector3, rot_deg: float) -> void:
	var p := prop(root, MapDefs.A + "planter.glb", pos, 1.7 if rot_deg > 80.0 else 1.6, rot_deg, true)
	MapKit.no_shadow(p)
	MapKit.far(p, 240.0)
