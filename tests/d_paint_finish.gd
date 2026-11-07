extends SceneTree
# Границы финишного слоя кузова: metallic/roughness уходят в знаменатели маски,
# поэтому ноль на ползунке — это не «матово», а INF в текстуре и NaN в шейдере.
# Проверки построены так, чтобы падать на прежнем коде: LIMITS с нулевым
# минимумом, маска без кэша и один канал на оба слоя.
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + message)

func _params() -> VehicleParams:
	var p: VehicleParams = VehicleDB.get_params("sedan").duplicate()
	p.paint_color = Color(0.2, 0.6, 0.9)
	return p

func _src() -> Material:
	var model: Node = load(VehicleDB.get_params("sedan").model).instantiate()
	var mat: Material = (model.get_node("body") as MeshInstance3D).mesh.surface_get_material(0)
	var keep := mat
	model.free()
	return keep

func _mask_finite(tex: Texture2D) -> bool:
	if tex == null: return true
	var img := tex.get_image()
	for y in range(0, img.get_height(), 17):
		for x in range(0, img.get_width(), 17):
			var c := img.get_pixel(x, y)
			if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)):
				return false
	return true

func _initialize() -> void:
	var src := _src()

	# 1) знаменатель: metallic=0 обязан давать конечную маску
	var p := _params()
	p.paint_metallic = 0.0
	p.paint_roughness = 0.05
	var m := Materials.body_paint(src, p)
	check(_mask_finite(m.metallic_texture), "маска металла при metallic=0 конечна (была INF)")
	check(_mask_finite(m.roughness_texture), "маска лака при roughness=минимум конечна")
	check(m.metallic >= 0.0 and m.metallic <= 1.0, "металличность осталась в диапазоне (%.3f)" % m.metallic)

	# 2) ползунок не может выставить значение, на котором модель маски неопределима
	var lo: Vector2 = GarageProfiles.LIMITS["paint_metallic"]
	check(lo.x > 0.0, "у МЕТАЛЛИЧНОСТИ минимум ненулевой (%.3f)" % lo.x)
	var service := GarageProfiles.new()
	service.select_vehicle("sedan")
	service.set_value("paint_metallic", 0.0)
	var clamped: VehicleParams = service.draft_params()
	check(clamped.paint_metallic > 0.0,
		"нулевая металличность из конфига sanitize'ится в положительную (%.3f)" % clamped.paint_metallic)

	# 3) маска не пересоздаётся на каждое движение ползунка
	var a := _params()
	a.paint_metallic = 0.4
	a.paint_roughness = 0.6
	var b := _params()
	b.paint_metallic = 0.4
	b.paint_roughness = 0.6
	var ma := Materials.body_paint(src, a)
	var mb := Materials.body_paint(src, b)
	check(ma.metallic_texture == mb.metallic_texture,
		"одинаковый финиш отдаёт ту же текстуру маски (прежний код — 9 МБ на каждое событие)")
	# и при этом разные значения не путаются между собой
	var c := _params()
	c.paint_metallic = 0.9
	c.paint_roughness = 0.6
	var mc := Materials.body_paint(src, c)
	check(mc.metallic_texture != ma.metallic_texture, "разный финиш не берёт чужую маску")

	# 4) один слой на канал: металл в R, лак в G
	check(m.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
		"металличность читается из красного канала")
	check(m.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
		"шероховатость читается из зелёного канала общего слоя")
	var img: Image = m.metallic_texture.get_image()
	var cell := Materials.paint_cell(VehicleDB.get_params("sedan").model)
	var w := img.get_width()
	var h := img.get_height()
	var painted := img.get_pixel((cell.x * 2 + 1) * w / 16, (cell.y * 2 + 1) * h / 8)
	check(absf(painted.r - 1.0) < 0.004 and absf(painted.g - 1.0) < 0.004,
		"в ячейке кузова оба слоя равны базе (r=%.3f g=%.3f)" % [painted.r, painted.g])
	var other := img.get_pixel(w - 2, h - 2)
	check(other.r > 1.0 and other.g > 1.0,
		"вне кузова маска возвращает заводские значения (r=%.2f g=%.2f)" % [other.r, other.g])

	print("ALL PASS" if fails == 0 else "FAILS %d" % fails)
	quit(0 if fails == 0 else 1)
