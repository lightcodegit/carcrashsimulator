class_name GaragePanel
extends VBoxContainer

signal preview_changed(params: VehicleParams)

const LABELS := {
	"accel_max": "ТЯГА · м/с²",
	"brake_decel": "РАБОЧИЙ ТОРМОЗ · м/с²",
	"grip": "СЦЕПЛЕНИЕ ШИН",
	"suspension_stiffness": "ЖЁСТКОСТЬ ПОДВЕСКИ",
	"damping_compression": "ДЕМПФИРОВАНИЕ · СЖАТИЕ",
	"damping_relaxation": "ДЕМПФИРОВАНИЕ · ОТБОЙ",
	"nitro_accel": "ТЯГА НИТРО · м/с²",
	"nitro_capacity": "БАК НИТРО",
	"paint_metallic": "МЕТАЛЛИЧНОСТЬ КУЗОВА",
	"paint_roughness": "ШЕРОХОВАТОСТЬ КУЗОВА",
}
var profiles: GarageProfiles
var sliders := {}
var colors: Array[HSlider] = []
var scroll: ScrollContainer
var save_button: Button
var cancel_button: Button
var factory_button: Button
var status: Label
var _values := {}
var _swatch: ColorRect

func setup(store: GarageProfiles, vehicle_name: String) -> void:
	profiles = store
	name = "GaragePanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", UiTheme.px(10))
	add_child(UiTheme.label("ГАРАЖ · %s", 28, Color.WHITE, 800, false, [vehicle_name]))
	var hint := UiTheme.label("Черновик · Сохрани для следующего заезда.\nУход из раздела отменяет несохранённые изменения.", 13, UiTheme.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UiTheme.px(10))
	scroll.add_child(content)
	var stock := VehicleDB.get_params(profiles.car_id)
	for key in LABELS:
		var span := GarageProfiles.bounds(stock, key)
		var row := VBoxContainer.new()
		content.add_child(row)
		var header := HBoxContainer.new()
		row.add_child(header)
		var label := UiTheme.label(LABELS[key], 14, UiTheme.DIM, 600)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(label)
		var value := UiTheme.label("", 14, UiTheme.TEXT, 600, true)
		header.add_child(value)
		_values[key] = value
		var slider := _slider(span)
		slider.name = key
		slider.tooltip_text = LABELS[key]
		row.add_child(slider)
		sliders[key] = slider
		slider.value_changed.connect(func(v: float) -> void:
			profiles.set_value(key, v)
			_changed())
	content.add_child(UiTheme.label("ЦВЕТ ОКРАШЕННЫХ ПАНЕЛЕЙ · RGB", 14, UiTheme.DIM, 600))
	var paint := HBoxContainer.new()
	paint.add_theme_constant_override("separation", UiTheme.px(12))
	content.add_child(paint)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(UiTheme.fx(56), UiTheme.fx(56))
	paint.add_child(_swatch)
	var channels := VBoxContainer.new()
	channels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint.add_child(channels)
	for channel in ["R · КРАСНЫЙ", "G · ЗЕЛЁНЫЙ", "B · СИНИЙ"]:
		var row := HBoxContainer.new()
		channels.add_child(row)
		var label := UiTheme.label(channel, 12, UiTheme.DIM)
		label.custom_minimum_size.x = UiTheme.fx(115)
		row.add_child(label)
		var slider := _slider(Vector2(0, 1))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = channel
		row.add_child(slider)
		colors.append(slider)
		slider.value_changed.connect(func(_v: float) -> void:
			set_paint(Color(colors[0].value, colors[1].value, colors[2].value)))
	status = UiTheme.label("", 13, UiTheme.DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.px(8))
	add_child(actions)
	save_button = UiTheme.action_button("СОХРАНИТЬ", 16)
	cancel_button = UiTheme.ghost_button("ОТМЕНА", 16)
	factory_button = UiTheme.ghost_button("ЗАВОДСКИЕ", 16)
	for button in [save_button, cancel_button, factory_button]: actions.add_child(button)
	save_button.pressed.connect(_save)
	cancel_button.pressed.connect(func() -> void:
		profiles.cancel()
		_changed("Восстановлена сохранённая конфигурация"))
	factory_button.pressed.connect(func() -> void:
		profiles.factory_reset()
		_changed("Заводские настройки в черновике · нажми СОХРАНИТЬ"))
	_refresh()
	_message(profiles.last_error if not profiles.last_error.is_empty() else "Одна сохранённая конфигурация для каждой машины", not profiles.last_error.is_empty())
	sliders.accel_max.grab_focus.call_deferred()

func _slider(span: Vector2) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = span.x
	slider.max_value = span.y
	slider.step = 0.0
	slider.custom_minimum_size.y = UiTheme.fx(28)
	slider.focus_mode = Control.FOCUS_ALL
	UiTheme.style_slider(slider)
	return slider

func set_paint(color: Color) -> void:
	profiles.set_value("paint_color", [color.r, color.g, color.b])
	_changed()

func _refresh() -> void:
	var p := profiles.draft_params()
	for key in sliders:
		var value: float = p.get(key)
		sliders[key].set_value_no_signal(value)
		_values[key].text = "%.2f" % minf(value, sliders[key].max_value)
	colors[0].set_value_no_signal(p.paint_color.r)
	colors[1].set_value_no_signal(p.paint_color.g)
	colors[2].set_value_no_signal(p.paint_color.b)
	_swatch.color = p.paint_color

func _changed(message := "Черновик изменён · ещё не сохранён") -> void:
	_refresh()
	_message(message)
	preview_changed.emit(profiles.draft_params())

func _message(text: String, error := false) -> void:
	# last_error уже переведён у источника, ключи-сообщения переводятся здесь:
	# t() возвращает неизменённой любую строку, которой нет в каталоге.
	status.text = I18n.t(text)
	status.add_theme_color_override("font_color", UiTheme.BAD if error else UiTheme.DIM)

func _save() -> void:
	if profiles.save() != OK:
		_message(profiles.last_error, true)
		return
	_changed("Сохранено · применяется в следующем заезде и при рестарте")
