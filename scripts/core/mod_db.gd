class_name ModDB
extends RefCounted
# Player car mods: user://mods/<folder>/mod.json.
#
# A mod is pure data on purpose. It picks a built-in car as its base and
# overrides physics numbers and the accent color; the model, wheel placement and
# body measuring stay with VehicleDB, so a hand-written file cannot point the
# game at an arbitrary resource or inject a property the physics never reads.
# That keeps the loader small enough to audit and lets a modded car work in the
# garage, Stats and replay export without special cases.
#
# Loading is lazy and one-shot: VehicleDB.ids()/get_params() call ensure_loaded()
# the first time, and the MODS menu can call reload() after the player drops a
# new folder into user://mods. No autoload is involved, so d_* tests can use the
# same code without the autoload singletons.

const DIR := "user://mods"
const FILE := "mod.json"
const MAX_FILE_BYTES := 65536
const MAX_MODS := 32
const MAX_CARS_PER_MOD := 8
const MAX_CARS := 32
const MAX_ID := 32
const MAX_NAME := 64
const MAX_DESC := 240
const MAX_ERRORS := 40

# Whitelist with sane physics ranges. Values outside the range are clamped, not
# rejected: a typo in a hobby mod should not stop the car from loading, and the
# simulation must never see NaN, a negative mass or a 10 000 km/h top speed.
const PARAM_RANGES := {
	"mass": Vector2(400.0, 4000.0),
	"accel_max": Vector2(1.0, 60.0),
	"vmax_kmh": Vector2(40.0, 1000.0),
	"brake_decel": Vector2(4.0, 20.0),
	"steer_rate_deg": Vector2(120.0, 600.0),
	"grip": Vector2(2.0, 20.0),
	"suspension_stiffness": Vector2(40.0, 260.0),
	"damping_compression": Vector2(2.0, 16.0),
	"damping_relaxation": Vector2(2.0, 20.0),
	"width": Vector2(1.2, 2.6),
	"body_stretch": Vector2(0.8, 2.0),
	"nitro_capacity": Vector2(0.0, 400.0),
	"nitro_drain": Vector2(0.0, 200.0),
	"nitro_refill": Vector2(0.0, 100.0),
	"nitro_accel": Vector2(0.0, 30.0),
	"nitro_vmax": Vector2(1.0, 3.0),
}

static var _mods: Array[Dictionary] = []
static var _errors: Array[String] = []
static var _loaded := false

# Snapshot for the menu: a caller cannot accidentally edit the loaded pack.
static func mods() -> Array[Dictionary]:
	ensure_loaded()
	return _mods.duplicate(true)

static func errors() -> Array[String]:
	ensure_loaded()
	return _errors.duplicate()

static func car_ids() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for mod in _mods:
		for car in (mod["cars"] as Array):
			out.append(String((car as Dictionary)["id"]))
	return out

static func car(id: String) -> Dictionary:
	ensure_loaded()
	for mod in _mods:
		for car in (mod["cars"] as Array):
			if String((car as Dictionary)["id"]) == id:
				return car as Dictionary
	return {}

# Called once by VehicleDB. A second call is free; reload() is the explicit way
# to pick up a folder that appeared while the game is running.
static func ensure_loaded() -> void:
	if _loaded: return
	reload()

static func ensure_dir() -> void:
	var root := DirAccess.open("user://")
	if root == null: return
	if not root.dir_exists("mods"): root.make_dir("mods")

static func reload() -> void:
	_loaded = true
	_mods.clear()
	_errors.clear()
	ensure_dir()
	var root := DirAccess.open(DIR)
	if root == null: return
	var folders: Array[String] = []
	for d in root.get_directories(): folders.append(String(d))
	folders.sort()
	if folders.size() > MAX_MODS:
		_error("", "too many mod folders (max %d); extra folders ignored" % MAX_MODS)
		folders.resize(MAX_MODS)
	var seen := {}
	for folder in folders:
		_load_mod(folder, seen)

static func _load_mod(folder: String, seen: Dictionary) -> void:
	var path := "%s/%s/%s" % [DIR, folder, FILE]
	if not FileAccess.file_exists(path):
		_error(folder, "mod.json is missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_error(folder, "mod.json cannot be opened")
		return
	if f.get_length() > MAX_FILE_BYTES:
		f.close()
		_error(folder, "mod.json is larger than %d KB" % (MAX_FILE_BYTES / 1024))
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		_error(folder, "mod.json is not a valid JSON object")
		return
	var data: Dictionary = json.data
	var mod_name := _text(data.get("name", folder), MAX_NAME)
	if mod_name == "": mod_name = folder
	var raw_cars: Variant = data.get("cars", [])
	if not (raw_cars is Array) or (raw_cars as Array).is_empty():
		_error(folder, "no cars in the pack")
		return
	var cars: Array[Dictionary] = []
	for raw in (raw_cars as Array):
		if cars.size() >= MAX_CARS_PER_MOD:
			_error(folder, "too many cars (max %d)" % MAX_CARS_PER_MOD)
			break
		if mods_total_cars() >= MAX_CARS:
			_error(folder, "too many cars across all mods (max %d)" % MAX_CARS)
			break
		var car := _car(folder, raw, seen)
		if not car.is_empty(): cars.append(car)
	if cars.is_empty(): return
	_mods.append({
		"folder": folder,
		"name": mod_name,
		"version": _text(data.get("version", ""), 16),
		"author": _text(data.get("author", ""), MAX_NAME),
		"cars": cars,
	})

static func mods_total_cars() -> int:
	var n := 0
	for mod in _mods: n += (mod["cars"] as Array).size()
	return n

static func _car(folder: String, raw: Variant, seen: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		_error(folder, "a car entry is not an object")
		return {}
	var d: Dictionary = raw
	var id := String(d.get("id", "")).strip_edges()
	if not _valid_id(id):
		_error(folder, "car id '%s' must be 2..%d chars of a-z, 0-9 or _" % [id, MAX_ID])
		return {}
	if id in VehicleDB.base_ids():
		_error(folder, "car id '%s' is already a built-in car" % id)
		return {}
	if seen.has(id):
		_error(folder, "car id '%s' is already used by another mod" % id)
		return {}
	var base := String(d.get("base", ""))
	if not base in VehicleDB.base_ids():
		_error(folder, "car '%s' has unknown base '%s'" % [id, base])
		return {}
	var name := _text(d.get("name", id), MAX_NAME)
	if name == "":
		_error(folder, "car '%s' has no name" % id)
		return {}
	var params := _params(folder, id, d.get("params", {}))
	var out := {
		"id": id,
		"name": name,
		"description": _text(d.get("description", ""), MAX_DESC),
		"base": base,
		"params": params,
	}
	if d.has("color"):
		var color: Variant = _color(d["color"])
		if color == null:
			_error(folder, "car '%s' color must be [r, g, b] from 0 to 1" % id)
		else:
			out["color"] = color
	seen[id] = true
	return out

static func _params(folder: String, id: String, raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary): return out
	for key in (raw as Dictionary):
		if not (key is String) or not PARAM_RANGES.has(key):
			_error(folder, "car '%s' ignores unknown parameter '%s'" % [id, str(key)])
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not _is_num(value):
			_error(folder, "car '%s' parameter '%s' is not a number" % [id, key])
			continue
		var span: Vector2 = PARAM_RANGES[key]
		out[key] = clampf(float(value), span.x, span.y)
	return out

static func _color(value: Variant) -> Variant:
	if not (value is Array) or (value as Array).size() != 3: return null
	var arr: Array = value
	for v in arr:
		if not _is_num(v): return null
	return Color(clampf(float(arr[0]), 0.0, 1.0), clampf(float(arr[1]), 0.0, 1.0),
		clampf(float(arr[2]), 0.0, 1.0))

static func _is_num(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _text(value: Variant, limit: int) -> String:
	if not (value is String): return ""
	var s := (value as String).strip_edges().replace("\r", " ").replace("\n", " ")
	# Control characters in a hand-edited file would end up in the label verbatim.
	while s.contains("\t"): s = s.replace("\t", " ")
	return s.substr(0, limit).strip_edges()

static func _valid_id(id: String) -> bool:
	if id.length() < 2 or id.length() > MAX_ID: return false
	for i in id.length():
		var c := id.substr(i, 1)
		var alpha := c >= "a" and c <= "z"
		var digit := c >= "0" and c <= "9"
		if not (alpha or digit or c == "_"): return false
		if i == 0 and not alpha: return false
	return true

static func _error(folder: String, message: String) -> void:
	if _errors.size() >= MAX_ERRORS: return
	_errors.append(("%s: %s" % [folder, message]) if folder != "" else message)
