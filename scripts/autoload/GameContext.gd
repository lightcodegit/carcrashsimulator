extends Node
var car_id := "sedan"
var map_id := "arena"

# Загрузочный экран:autoload живёт поверх смен сцен, поэтому слой анимации
# переживает и меню, и заезд. Показывается на запуске заезда и на выходе в меню.
var _loading_layer: CanvasLayer
var _loading_ring: TextureRect
var _loading_hide_ready := false
var _loading_until_ms := 0

# Автозагрузки ниже по списку (Settings) уже прочитали settings.cfg к этому
# моменту: восстанавливаем последний выбор машины и карты. Мусорные id из
# чужого файла отсеет select — до car.build они не доживают.
func _ready() -> void:
	# Автозагрузки ниже по списку (Settings) уже прочитали settings.cfg к этому
	# моменту: восстанавливаем последний выбор машины и карты. Мусорные id из
	# чужого файла отсеет select — до car.build они не доживают.
	select(Settings.last_car, Settings.last_map)
	_build_loading()
	set_process(false)   # анимация крутится только пока экран загрузки виден
	# Версия в заголовке окна ОС: видно, какой билд запущен, не заглядывая в меню.
	var ver: String = ProjectSettings.get_setting("application/config/version")
	DisplayServer.window_set_title("Car Crash Simulator v" + ver)

func select(c: String, m: String) -> void:
	if c in VehicleDB.ids(): car_id = c
	if m in MapDB.ids(): map_id = m
	# Выбор переживает и выход в меню, и выход из игры: пишем в settings.cfg
	# той же атомарной записью, что и остальные настройки. На диске — только
	# когда выбор реально изменился: загрузка игры не должна переписывать файл.
	if Settings.last_car == car_id and Settings.last_map == map_id: return
	Settings.set_value("last_car", car_id, false)
	Settings.set_value("last_map", map_id, false)
	Settings.save()

# ---- загрузочный экран ------------------------------------------------------
const LOADING_MIN_MS := 700

func _build_loading() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.name = "LoadingScreen"
	_loading_layer.layer = 100
	_loading_layer.visible = false
	add_child(_loading_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.07, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UiTheme.px(18))
	center.add_child(box)
	_loading_ring = TextureRect.new()
	_loading_ring.texture = load("res://assets/ui/logo_emblem.svg")
	_loading_ring.custom_minimum_size = Vector2(UiTheme.fx(96), UiTheme.fx(96))
	_loading_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading_ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_loading_ring)
	var cap := UiTheme.label("ЗАГРУЗКА", 16, UiTheme.AMBER, 700, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)

func loading_show() -> void:
	_loading_hide_ready = false
	_loading_until_ms = Time.get_ticks_msec() + LOADING_MIN_MS
	_loading_layer.visible = true
	set_process(true)

func loading_hide() -> void:
	_loading_hide_ready = true

func loading_visible() -> bool:
	return _loading_layer != null and _loading_layer.visible

func _process(_dt: float) -> void:
	_loading_ring.rotation += _dt * 2.2
	_loading_ring.pivot_offset = _loading_ring.size * 0.5
	if _loading_hide_ready and Time.get_ticks_msec() >= _loading_until_ms:
		_loading_layer.visible = false
		set_process(false)
