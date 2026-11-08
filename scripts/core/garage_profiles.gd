class_name GarageProfiles
extends RefCounted

const PATH := "user://garage_v1.json"
const VERSION := 1
const LIMITS := {
	"accel_max": Vector2(0.5, 1.5),
	"brake_decel": Vector2(6.0, 16.1865),
	"grip": Vector2(4.0, 14.0),
	"suspension_stiffness": Vector2(60.0, 180.0),
	"damping_compression": Vector2(3.5, 10.5),
	"damping_relaxation": Vector2(4.5, 13.5),
	"nitro_accel": Vector2(2.0, 18.0),
	"nitro_capacity": Vector2(50.0, 200.0),
	"paint_metallic": Vector2(0.05, 1.0),
	"paint_roughness": Vector2(0.05, 1.0),
}
# Тяга — множитель заводной (иначе лимузину 6.0 не дали бы и паспортного),
# остальные границы абсолютные: потолок тормоза задаёт физический предел шин.
const RELATIVE := ["accel_max"]

var path: String
var last_error := ""
var car_id := ""
var draft: Dictionary = {}
var _saved: Dictionary = {}
var _future_version := false

func _init(file_path := PATH) -> void:
	path = file_path
	_load()

static func bounds(stock: VehicleParams, key: String) -> Vector2:
	var span: Vector2 = LIMITS.get(key, Vector2.ZERO)
	return span * stock.accel_max if key in RELATIVE else span

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func sanitize(stock: VehicleParams, values: Dictionary) -> Dictionary:
	var clean := {}
	for key in LIMITS:
		var value: Variant = values.get(key)
		if not _number(value): continue
		var span := bounds(stock, key)
		clean[key] = clampf(float(value), span.x, span.y)
	var color: Variant = values.get("paint_color")
	if color is Array and color.size() == 3:
		if _number(color[0]) and _number(color[1]) and _number(color[2]):
			clean.paint_color = [clampf(color[0], 0, 1), clampf(color[1], 0, 1), clampf(color[2], 0, 1)]
	return clean

static func build_params(stock: VehicleParams, values: Dictionary) -> VehicleParams:
	if stock == null: return null
	var p := stock.duplicate() as VehicleParams
	var clean := sanitize(stock, values)
	for key in clean:
		if key == "paint_color":
			var c: Array = clean[key]
			p.paint_color = Color(c[0], c[1], c[2])
		else:
			p.set(key, clean[key])
	return p

func effective_params(id: String) -> VehicleParams:
	return build_params(VehicleDB.get_params(id), _saved.get(id, {}))

func select_vehicle(id: String) -> bool:
	if not id in VehicleDB.ids(): return false
	car_id = id
	cancel()
	return true

func draft_params() -> VehicleParams:
	return build_params(VehicleDB.get_params(car_id), draft)

func set_value(key: String, value: Variant) -> void:
	var stock := VehicleDB.get_params(car_id)
	if stock == null: return
	var clean := sanitize(stock, {key: value})
	draft.merge(clean, true)

func cancel() -> void:
	draft = _saved.get(car_id, {}).duplicate(true)

func factory_reset() -> void:
	draft = {}

func save() -> Error:
	last_error = ""
	if _future_version:
		return _error(ERR_UNAVAILABLE, "Файл гаража из более новой версии игры")
	var stock := VehicleDB.get_params(car_id)
	if stock == null: return _error(ERR_INVALID_PARAMETER, "Неизвестная машина")
	var next := _saved.duplicate(true)
	next[car_id] = sanitize(stock, draft)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return _error(FileAccess.get_open_error(), "Не удалось записать гараж")
	file.store_string(JSON.stringify({"version": VERSION, "vehicles": next}))
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if result != OK:
		DirAccess.remove_absolute(temp)
		return _error(result, "Не удалось сохранить гараж; прежний файл сохранён")
	_saved = next
	cancel()
	return OK

func _error(code: Error, message: String) -> Error:
	last_error = "%s (%s)" % [I18n.t(message), error_string(code)]
	return code

func _load() -> void:
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error(FileAccess.get_open_error(), "Не удалось прочитать гараж")
		return
	if file.get_length() > 1048576:
		last_error = I18n.t("Файл гаража слишком большой; используются заводские настройки")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		last_error = I18n.t("Повреждённый файл гаража; используются заводские настройки")
		return
	var data: Dictionary = json.data
	var raw_version: Variant = data.get("version")
	# «Новая версия» — это только число больше нашей. Файл без версии (ручная
	# правка, черновая запись, формат до версионирования) содержит те же профили,
	# и запереть из-за него сохранение навсегда — хуже, чем принять его и дописать
	# версию при первой записи.
	if (raw_version is int or raw_version is float) and float(raw_version) > float(VERSION):
		_future_version = true
		last_error = I18n.t("Неподдерживаемая версия файла гаража")
		return
	if not data.get("vehicles") is Dictionary: return
	for id in data.vehicles:
		if not id in VehicleDB.ids() or not data.vehicles[id] is Dictionary: continue
		_saved[id] = sanitize(VehicleDB.get_params(id), data.vehicles[id])
