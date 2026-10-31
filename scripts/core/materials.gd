class_name Materials
extends RefCounted
# Доводка материалов ассетов до PBR.
#
# Kenney отдаёт плоский диффуз: у импортированных материалов roughness = 1 и
# metallic = 0, поэтому specular отсутствует вовсе и кузова в тени выглядят
# почти чёрными — на это и была жалоба. Цвета автора не трогаем, добавляем только
# шероховатость, металл и (для асфальта/травы/бетона) процедурные карты.

# rough — итоговая шероховатость, metal — металличность, tile — сколько раз
# процедурная карта укладывается на метр (0 = без карт, только шероховатость)
const SURFACE := {
	"road":        {"rough": 0.90, "metal": 0.00, "tile": 1.6},
	"grass":       {"rough": 1.00, "metal": 0.00, "tile": 0.9},
	"grey":        {"rough": 0.78, "metal": 0.00, "tile": 1.2},
	"red":         {"rough": 0.50, "metal": 0.05, "tile": 1.2},
	"bark":        {"rough": 0.95, "metal": 0.00, "tile": 0.8},
	"pylon":       {"rough": 0.55, "metal": 0.00, "tile": 1.5},
	"net":         {"rough": 0.80, "metal": 0.25, "tile": 0.0},
	"glass":       {"rough": 0.06, "metal": 0.00, "tile": 0.0},
	"tankco":      {"rough": 0.45, "metal": 0.35, "tile": 1.0},
	"checkers":    {"rough": 0.70, "metal": 0.00, "tile": 0.0},
	"_defaultMat": {"rough": 0.80, "metal": 0.00, "tile": 1.0},
}
const PAINT_ROUGH := 0.28      # лак поверх краски: без него кузов матовый и тёмный
const PAINT_METAL := 0.15      # металличность держим низкой: она гасит диффуз, а светит здесь лак
const PAINT_CLEAR := 0.7
const PROP_ROUGH := 0.82

# Пятнистость крупных поверхностей. Плоский диффуз Kenney — главная причина, по которой
# карты выглядят мультяшно: у настоящего асфальта есть заплатки, потёртости от шин и
# выцветшие участки, у травы — сухие и тенистые проплешины. lo/hi смешиваются с альфой
# самого слоя детали, а середина градиента прозрачна, чтобы базовый цвет автора проглядывал.
const DETAIL := {
	"road":  {"lo": Color(0.05, 0.05, 0.055, 0.34), "hi": Color(0.60, 0.60, 0.58, 0.22)},
	"grass": {"lo": Color(0.04, 0.07, 0.02, 0.42), "hi": Color(0.50, 0.52, 0.18, 0.34)},
	"grey":  {"lo": Color(0.11, 0.11, 0.11, 0.28), "hi": Color(0.80, 0.80, 0.78, 0.20)},
	"bark":  {"lo": Color(0.05, 0.03, 0.02, 0.38), "hi": Color(0.44, 0.37, 0.29, 0.20)},
}
const DETAIL_SCALE := 0.055    # пятен на метр: одна текстура накрывает ~18 м
const DETAIL_FREQ := 0.021     # длина волны пятна ~3 м

static var _rough_tex: NoiseTexture2D
static var _normal_tex: NoiseTexture2D
static var _detail_texs := {}
static var _cache := {}

# Кузовная краска: дублируем материал автора и добавляем лак, металличность и
# шероховатость, чтобы машина ловила отражение неба вместо того чтобы чернеть.
static func car_paint(src: Material) -> StandardMaterial3D:
	var m := _clone(src)
	m.roughness = PAINT_ROUGH
	m.metallic = PAINT_METAL
	m.metallic_specular = 0.65
	m.clearcoat_enabled = true
	m.clearcoat = PAINT_CLEAR
	m.clearcoat_roughness = 0.06
	return m

# Обход дерева: каждому материалу каждого меша подбираем доводку. Имя материала автора
# (у OBJ из Racing Kit это road / grass / grey / red / ...) побеждает род, если оно
# есть в таблице SURFACE; иначе решает род, который передал вызывающий (car / prop).
static func apply_tree(root: Node, kind: String) -> void:
	if root is MeshInstance3D:
		_apply_mesh(root as MeshInstance3D, kind)
	for c in root.get_children():
		apply_tree(c, kind)

static func _apply_mesh(mi: MeshInstance3D, kind: String) -> void:
	var mesh := mi.mesh
	if mesh == null: return
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		if src == null: continue
		# уже доведённый поверх материал (например, кузовная краска) не перетираем
		if mi.get_surface_override_material(i) != null: continue
		# Имя материала автора важнее рода, только если оно известно (road/grass/grey/...):
		# у GLB имена произвольные, и подбирать по ним шероховатость нельзя. В ключ кэша
		# обязательно входит оттенок — «grey» в roadStraightLong.mtl и в barrierWhite.mtl
		# разные, и общий материал перекрасил бы чужие объекты.
		var nm := src.resource_name
		var key_name := kind if kind == "car" or not SURFACE.has(nm) else nm
		var key := key_name + _tint_of(src)
		var tuned: Material = _cache.get(key)
		if tuned == null:
			if key_name == "car": tuned = car_paint(src)
			elif key_name == "prop": tuned = _prop(src)
			else: tuned = _surface(src, key_name)
			_cache[key] = tuned
		mi.set_surface_override_material(i, tuned)

static func _tint_of(src: Material) -> String:
	var m := src as StandardMaterial3D
	if m == null: return ""
	var tex := "" if m.albedo_texture == null else m.albedo_texture.resource_path
	return "|" + str(m.albedo_color) + "|" + tex

static func _prop(src: Material) -> StandardMaterial3D:
	var m := _clone(src)
	m.roughness = PROP_ROUGH
	m.metallic = 0.04
	m.metallic_specular = 0.5
	return m

static func _surface(src: Material, name_key: String) -> StandardMaterial3D:
	var m := _clone(src)
	var p: Dictionary = SURFACE.get(name_key, {"rough": 0.85, "metal": 0.0, "tile": 0.0})
	m.roughness = p.rough
	m.metallic = p.metal
	m.metallic_specular = 0.5
	var tile: float = p.tile
	if tile <= 0.0: return m
	_ensure_noise()
	# трипланар в мировых координатах: у OBJ из Asset Forge UV развёрнуты кое-как,
	# а так зерно асфальта совпадает на стыках плит и не плывёт по вертикальным граням
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tile, tile, tile)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness_texture = _rough_tex
	m.normal_enabled = true
	m.normal_scale = 0.55
	m.normal_texture = _normal_tex
	_apply_detail(m, name_key)
	return m

# Пятнистость кладём во второй UV-набор (DETAIL_UV_2): у него свой мировой трипланар и
# свой масштаб, поэтому крупные заплатки не зависят от мелкого зерна.
static func _apply_detail(m: StandardMaterial3D, name_key: String) -> void:
	if not DETAIL.has(name_key): return
	m.detail_enabled = true
	m.detail_albedo = _detail_tex(name_key)
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3.ONE * DETAIL_SCALE

# Материал процедурных коробок MapDB (пол, тротуары, стены) — тот же бетон с зерном.
static func concrete(color: Color, tile := 1.1) -> StandardMaterial3D:
	var ck := "concrete|" + str(color) + "|" + str(tile)
	var cached: Material = _cache.get(ck)
	if cached != null: return cached as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = "concrete"    # по нему тест отличает процедурные коробки от GLB
	m.albedo_color = color
	m.roughness = 0.88
	m.metallic_specular = 0.45
	if tile > 0.0:
		_ensure_noise()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(tile, tile, tile)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.roughness_texture = _rough_tex
		m.normal_enabled = true
		m.normal_scale = 0.45
		m.normal_texture = _normal_tex
		_apply_detail(m, "grey")
	_cache[ck] = m
	return m

static func _clone(src: Material) -> StandardMaterial3D:
	if src is StandardMaterial3D:
		return (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	var m := StandardMaterial3D.new()
	if src is ORMMaterial3D:
		var o := src as ORMMaterial3D
		m.albedo_color = o.albedo_color
		m.albedo_texture = o.albedo_texture
		m.roughness = o.roughness
	return m

# Шероховатость и нормали из одного бесшовного шума. Диапазон шероховатости сдвинут
# градиентом к светлому: иначе среднее значение 0.5 затемнило бы всё вдвое.
static func _ensure_noise() -> void:
	if _rough_tex != null: return
	var fn := _noise(0.11, 4)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0.72, 0.72, 0.72), Color(1, 1, 1)])
	_rough_tex = _noise_tex(fn, ramp)
	var nm := _noise_tex(fn, null)
	nm.as_normal_map = true
	nm.bump_strength = 2.0
	_normal_tex = nm

static func _detail_tex(name_key: String) -> NoiseTexture2D:
	var got: NoiseTexture2D = _detail_texs.get(name_key)
	if got != null: return got
	var d: Dictionary = DETAIL[name_key]
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	# середина полностью прозрачна: там остаётся чистый цвет автора
	ramp.colors = PackedColorArray([d.lo, Color(0, 0, 0, 0), d.hi])
	got = _noise_tex(_noise(DETAIL_FREQ, 3), ramp)
	_detail_texs[name_key] = got
	return got

static func _noise(freq: float, octaves: int) -> FastNoiseLite:
	var fn := FastNoiseLite.new()
	fn.seed = 20261031
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.frequency = freq
	fn.fractal_octaves = octaves
	return fn

static func _noise_tex(fn: FastNoiseLite, ramp: Gradient) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.noise = fn
	t.width = 256
	t.height = 256
	t.seamless = true
	if ramp != null: t.color_ramp = ramp
	return t
